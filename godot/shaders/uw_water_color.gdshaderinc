// 水下颜色、ACES 逆变换与共享海面光学。显示色先反解到 HDR，再交给 Godot ACES，避免白蒙层。
uniform float water_exposure = 1.0185185185;
uniform vec3 sun_direction = vec3(0.5191, 0.7787, -0.3523);
uniform vec3 sun_color : source_color = vec3(1.0, 0.955, 0.8);
uniform float sun_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float surface_ior : hint_range(1.0, 1.5, 0.001) = 1.333;
uniform float surface_window_strength : hint_range(0.0, 1.5, 0.01) = 1.0;
uniform float surface_reflection_strength : hint_range(0.0, 2.0, 0.01) = 0.78;
uniform float sun_disk_strength : hint_range(0.0, 2.0, 0.01) = 0.14;
uniform float sun_glint_strength : hint_range(0.0, 2.0, 0.01) = 0.28;

vec3 uw_srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 uw_display_to_hdr(vec3 c) {
    mat3 input_matrix = mat3(vec3(0.59719, 0.35458, 0.04823),
        vec3(0.07600, 0.90834, 0.01566), vec3(0.02840, 0.13383, 0.83777)) * 1.8;
    mat3 output_matrix = mat3(vec3(1.60475, -0.53108, -0.07367),
        vec3(-0.10208, 1.10813, -0.00605), vec3(-0.00327, -0.07276, 1.07602));
    vec3 y = uw_srgb_to_linear(c) * inverse(output_matrix);
    vec3 a = y * 0.983729 - 1.0;
    vec3 b = y * 0.432951 - 0.0245786;
    vec3 d = y * 0.238081 + 0.000090537;
    vec3 x = (-b - sqrt(max(b * b - 4.0 * a * d, vec3(0.0)))) / (2.0 * a);
    return (x * inverse(input_matrix)) / water_exposure;
}

float uw_depth_light(float depth) {
    return mix(1.0, 0.26, smoothstep(5.0, 120.0, max(depth, 0.0)));
}
// Sky-source ambient energy is not a reliable scale for sky irradiance.
// Apply the artistic shallow-water lift once, in the cubemap itself.
float uw_irradiance_gain(float depth) {
    return mix(1.8, 0.34, smoothstep(5.0, 120.0, max(depth, 0.0)))
        * mix(0.32, 1.0, sun_strength);
}

vec3 uw_gradient_display(vec2 screen_uv, float depth) {
    float d = clamp((depth - 3.0) / 117.0, 0.0, 1.0);
    vec3 top = mix(vec3(0.12, 0.91, 0.87), vec3(0.018, 0.20, 0.34), d);
    vec3 bottom = mix(vec3(0.025, 0.36, 0.62), vec3(0.004, 0.045, 0.12), d);
    vec3 gradient = mix(bottom, top, pow(clamp(1.0 - screen_uv.y, 0.0, 1.0), 0.8));
    return gradient * uw_depth_light(depth) * mix(0.28, 1.0, sun_strength);
}
vec3 uw_gradient(vec2 screen_uv, float depth) {
    return uw_display_to_hdr(uw_gradient_display(screen_uv, depth));
}
vec3 uw_hdr_to_display(vec3 c) {
    mat3 input_matrix = mat3(vec3(0.59719, 0.35458, 0.04823),
        vec3(0.07600, 0.90834, 0.01566), vec3(0.02840, 0.13383, 0.83777)) * 1.8;
    mat3 output_matrix = mat3(vec3(1.60475, -0.53108, -0.07367),
        vec3(-0.10208, 1.10813, -0.00605), vec3(-0.00327, -0.07276, 1.07602));
    vec3 x = c * water_exposure * input_matrix;
    vec3 y = ((x * (x + 0.0245786) - 0.000090537)
        / (x * (0.983729 * x + 0.432951) + 0.238081)) * output_matrix;
    y = clamp(y, vec3(0.0), vec3(1.0));
    return mix(y * 12.92, 1.055 * pow(y, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), y));
}

vec3 uw_above_water_sky_display(vec3 direction) {
    vec3 d = normalize(vec3(direction.x, max(direction.y, 0.0), direction.z));
    float h = smoothstep(0.0, 1.0, d.y);
    vec3 horizon = vec3(0.31, 0.58, 0.73);
    vec3 zenith = vec3(0.055, 0.25, 0.55);
    vec3 sky = mix(horizon, zenith, h);
    vec3 s = normalize(sun_direction);
    float sun_dot = max(dot(d, s), 0.0);
    float halo = pow(sun_dot, 12.0) * 0.018;
    float disk = pow(sun_dot, 180.0) * sun_disk_strength * sun_strength;
    return sky * mix(0.36, 1.0, sun_strength) + sun_color * (halo * sun_strength + disk);
}
vec3 uw_above_water_sky(vec3 direction) {
    return uw_display_to_hdr(uw_above_water_sky_display(direction));
}

// 共享水面表现：统一屏幕水色底、低频波纹与柔和日光。
// 折射方向仅用于定位阳光，不再切换整片天空/内反射色，防止临界角形成蓝色圆盖。
vec3 uw_surface_optics(vec3 world_position, vec3 normal, vec3 view_direction, float t, float water_column, vec2 screen_uv) {
    vec3 v = normalize(view_direction);
    vec3 n = normalize(normal);
    float n_water = max(surface_ior, 1.001);
    // Incident ray travels from the underwater camera toward the air interface.
    // Water -> air uses n_water/n_air (>1), so grazing rays become total internal reflection.
    vec3 incident = -v;
    vec3 transmitted = refract(incident, -n, n_water);
    float transmitted_length = length(transmitted);
    vec3 sky_direction = transmitted_length > 0.001 ? normalize(transmitted) : vec3(0.0, 1.0, 0.0);

    vec2 p = world_position.xz * 0.18;
    float band_a = sin(p.x * 1.2 + sin(p.y * 0.9 + t * 0.58));
    float band_b = sin(p.y * 1.3 - sin(p.x * 0.75 - t * 0.43));
    float fragments = pow(max(0.0, band_a * band_b), 4.0);
    float wave_sun = pow(max(dot(n, normalize(sun_direction)), 0.0), 7.0);
    float sun_dot = max(dot(sky_direction, normalize(sun_direction)), 0.0);
    float disk = pow(sun_dot, 96.0) * sun_disk_strength * smoothstep(0.0, 0.08, transmitted_length);
    vec3 scattered_sun = sun_color * sun_strength * (fragments * wave_sun * sun_glint_strength + disk);

    vec3 gradient_hdr = uw_display_to_hdr(uw_gradient_display(screen_uv, water_column));
    // A finite water plane must not become a separate circular window. Keep
    // the same water gradient as the fog/background and express the surface
    // only through low-amplitude animated wave modulation and sunlight.
    float wave_phase = world_position.x * 0.11 + world_position.z * 0.073 + t * 0.42;
    float wave_modulation = 0.86 + (0.5 + 0.5 * sin(wave_phase)) * 0.22 + fragments * 0.10;
    vec3 result = gradient_hdr * wave_modulation;
    result += scattered_sun * (0.18 + fragments * 0.16);
    // Surface stays legible at depth, but sunlight is absorbed through the water column.
    result *= mix(0.22, 1.0, exp(-max(water_column, 0.0) * 0.012));
    return max(result, vec3(0.0));
}
