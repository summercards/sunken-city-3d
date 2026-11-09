// SEA-OCEAN underside adapter. Reuses the existing surface wave field and
// large_waves texture, but never samples shore foam, seabed colour or SSR.
#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/uw_water_color.gdshaderinc"
uniform sampler2D large_wave_normals : hint_normal, repeat_enable, filter_linear_mipmap;
// P 面板「水下海面」的唯一运行参数组。动态输入（水位、深度、太阳方向、
// 相机和 SCREEN_UV）仍由活动地图/Session 注入，不在调试面板里伪造第二套真相。
uniform float underside_normal_metres = 28.0;
uniform float underside_normal_strength = 0.36;
uniform float underside_wave_scale_x = 0.42;
uniform float underside_wave_scale_z = 0.82;
uniform float underside_wave_time_scale = 0.55;
uniform float underside_normal_scroll_x = 0.006;
uniform float underside_normal_scroll_z = 0.003;
uniform float underside_normal_b_scale_x = 0.83;
uniform float underside_normal_b_scale_z = 1.13;
uniform float underside_normal_b_scroll = 0.73;
uniform vec2 underside_normal_b_offset = vec2(0.37, 0.61);
uniform float underside_wave_slope = 0.65;
uniform float underside_normal_influence = 0.9;
uniform float underside_incident_normal_mix = 0.55;
uniform float underside_wave_light = 0.85;
uniform float underside_ridge_low = 0.025;
uniform float underside_ridge_high = 0.105;
uniform float underside_ridge_strip_mix = 0.018;
uniform float underside_break_low = 0.43;
uniform float underside_break_high = 0.58;
uniform float underside_break_floor = 0.35;
uniform float underside_break_gain = 0.65;
uniform float underside_crest_up_low = 0.02;
uniform float underside_crest_up_high = 0.55;
// These are display-space water colours. Keep them as raw vec3 values so
// adding the inspector controls does not apply a second sRGB conversion to
// the signed adapter's existing defaults.
uniform vec3 underside_body_bottom = vec3(0.045, 0.31, 0.66);
uniform vec3 underside_body_top = vec3(0.13, 0.57, 0.86);
uniform vec3 underside_crest_colour = vec3(0.77, 0.97, 1.0);
uniform float underside_crest_depth_min = 0.65;
uniform float underside_crest_depth_max = 1.0;
uniform float underside_daylight_floor = 0.16;
uniform float underside_depth_near = 2.0;
uniform float underside_depth_far = 120.0;
uniform float underside_depth_light_shallow = 1.0;
uniform float underside_depth_light_deep = 0.46;
uniform float underside_sun_light = 0.80;
uniform float underside_sun_ior = 1.333;
uniform float underside_sun_sharpness = 360.0;
uniform float underside_sun_variance_divisor = 24.0;
uniform float underside_sun_lobe_gain = 2.2;
uniform float underside_sun_core_mix = 0.75;
uniform float underside_sun_halo_power = 24.0;
uniform float underside_sun_halo_mix = 0.26;
uniform float underside_sun_max_mix = 0.88;
uniform vec3 underside_sun_display_colour = vec3(0.94, 0.99, 1.0);
uniform float underside_surface_edge_near = 125.0;
uniform float underside_surface_edge_far = 190.0;
uniform float underside_edge_gradient_mix = 1.0;
uniform float underside_display_max = 0.98;
uniform float underside_time = 0.0;

vec2 underside_strip(vec2 uv, float clock) {
    // Source texture is X-up: G/B are its two centred slope channels.
    // R has a mean of 0.995 and must not be mistaken for centred X slope.
    vec2 drift = vec2(clock * underside_normal_scroll_x, clock * underside_normal_scroll_z);
    vec2 a = texture(large_wave_normals, uv - drift).gb;
    vec2 b = texture(large_wave_normals, uv * vec2(underside_normal_b_scale_x, underside_normal_b_scale_z)
        + drift * underside_normal_b_scroll + underside_normal_b_offset).gb;
    return (a + b - vec2(1.0)) * 2.0;
}

// Same derivative-filtered exponential lobe as water.gdshader: filter the
// angular footprint instead of drawing unfiltered white pixel noise.
float underside_sun_lobe(vec3 transmitted, vec3 toward_sun) {
    float alignment = clamp(dot(transmitted, toward_sun), 0.0, 1.0);
    vec3 dx = dFdx(transmitted);
    vec3 dy = dFdy(transmitted);
    float variance = (dot(dx, dx) + dot(dy, dy)) / max(underside_sun_variance_divisor, 0.001);
    float width = 1.0 / (1.0 + underside_sun_sharpness * variance);
    return clamp(exp2(-1.44269504089 * underside_sun_sharpness * (1.0 - alignment) * width)
        * width * underside_sun_lobe_gain, 0.0, 1.0);
}

vec3 underside_surface(vec3 world, float clock, float column, vec2 screen_uv, vec3 camera_position, float distance_m) {
    // Reuse the surface's short-crested packets at a broader, wind-stretched
    // optical scale when seen through a deep water column.
    vec3 wave = ocean_sample_at(world.xz * vec2(underside_wave_scale_x, underside_wave_scale_z), clock * underside_wave_time_scale);
    vec2 uv = world.xz / max(underside_normal_metres, 1.0);
    vec2 strip = underside_strip(uv, clock);
    vec3 n = normalize(vec3(-wave.y * underside_wave_slope - strip.x * underside_normal_strength,
        1.0, -wave.z * underside_wave_slope - strip.y * underside_normal_strength));
    vec3 incident = normalize(world - camera_position);
    // Above-water sun refracts toward the vertical underwater. Use its
    // underwater direction and perturb it by the actual shared wave slope;
    // no hard refract/TIR colour switch at the critical angle.
    vec3 s = normalize(sun_direction);
    vec2 sxz = s.xz / max(underside_sun_ior, 1.001);
    vec3 underwater_sun = normalize(vec3(sxz.x, sqrt(max(0.01, 1.0 - dot(sxz,sxz))), sxz.y));
    vec3 light_ray = normalize(incident + vec3(n.x, 0.0, n.z) * underside_normal_influence);
    float alignment = max(dot(light_ray, underwater_sun), 0.0);
    float sun_core = underside_sun_lobe(light_ray, underwater_sun);
    float sun_halo = pow(alignment, underside_sun_halo_power);

    // Only positive moving crests: never multiply the surface by dark bands.
    // Two scrolling samples break up the contour, rather than sin*sin grime.
    vec2 drift = vec2(clock * underside_normal_scroll_x, clock * underside_normal_scroll_z);
    vec2 a = texture(large_wave_normals, uv - drift).gb;
    vec2 b = texture(large_wave_normals, uv * vec2(underside_normal_b_scale_x, underside_normal_b_scale_z)
        + drift * underside_normal_b_scroll + underside_normal_b_offset).gb;
    // Crest lighting follows the shared wave slope, not an isocontour cut
    // from the normal texture (that read as polygon islands/paper flakes).
    float ridge = smoothstep(underside_ridge_low, underside_ridge_high,
        wave.y + strip.x * underside_ridge_strip_mix);
    float broken = smoothstep(underside_break_low, underside_break_high, b.y);
    float crests = ridge * (underside_break_floor + underside_break_gain * broken);
    float daytime = mix(underside_daylight_floor, 1.0, sun_strength);
    float depth_light = mix(underside_depth_light_shallow, underside_depth_light_deep,
        smoothstep(underside_depth_near, underside_depth_far, column));
    // Preserve the signed adapter's display baseline. The panel exposes the
    // artistic factors above, while this calibration remains part of the
    // shared water colour chain and is not a second exposure control.
    float underside_display_gain = 1.0;
    float upward = smoothstep(underside_crest_up_low, underside_crest_up_high, max(incident.y,0.0));
    vec3 body = mix(underside_body_bottom, underside_body_top, upward);
    body *= depth_light * daytime;
    vec3 crest_colour = underside_crest_colour
        * mix(underside_crest_depth_min, underside_crest_depth_max, depth_light) * daytime;
    vec3 display = mix(body, crest_colour,
        crests * underside_wave_light * mix(underside_incident_normal_mix,1.0,upward));
    display = mix(display, underside_sun_display_colour * mix(underside_crest_depth_min,1.0,depth_light),
        clamp((sun_core * underside_sun_core_mix + sun_halo * underside_sun_halo_mix)
            * sun_strength * underside_sun_light,0.0,underside_sun_max_mix));
    // Fade finite geometry before the established fog boundary; this is only
    // the surface material's optical edge, not a second screen fog pass.
    float edge = smoothstep(underside_surface_edge_near, underside_surface_edge_far, distance_m)
        * underside_edge_gradient_mix;
    display = mix(display, uw_gradient_display(screen_uv,column), clamp(edge, 0.0, 1.0));
    return uw_display_to_hdr(clamp(display * underside_display_gain,vec3(0.0),vec3(underside_display_max)));
}
