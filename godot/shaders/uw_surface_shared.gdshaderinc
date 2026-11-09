// SEA-OCEAN underside adapter. Reuses the existing surface wave field and
// large_waves texture, but never samples shore foam, seabed colour or SSR.
#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/uw_water_color.gdshaderinc"
uniform sampler2D large_wave_normals : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float underside_normal_metres = 28.0;
uniform float underside_normal_strength = 0.36;
uniform float underside_wave_light = 0.85;
uniform float underside_sun_light = 0.80;
uniform float underside_time = 0.0;

vec2 underside_strip(vec2 uv, float clock) {
    // Source texture is X-up: G/B are its two centred slope channels.
    // R has a mean of 0.995 and must not be mistaken for centred X slope.
    vec2 drift = vec2(clock * 0.006, clock * 0.003);
    vec2 a = texture(large_wave_normals, uv - drift).gb;
    vec2 b = texture(large_wave_normals, uv * vec2(0.83, 1.13)
        + drift * 0.73 + vec2(0.37, 0.61)).gb;
    return (a + b - vec2(1.0)) * 2.0;
}

// Same derivative-filtered exponential lobe as water.gdshader: filter the
// angular footprint instead of drawing unfiltered white pixel noise.
float underside_sun_lobe(vec3 transmitted, vec3 toward_sun) {
    float alignment = clamp(dot(transmitted, toward_sun), 0.0, 1.0);
    vec3 dx = dFdx(transmitted);
    vec3 dy = dFdy(transmitted);
    float variance = (dot(dx, dx) + dot(dy, dy)) / 24.0;
    float sharpness = 360.0;
    float width = 1.0 / (1.0 + sharpness * variance);
    return clamp(exp2(-1.44269504089 * sharpness * (1.0 - alignment) * width)
        * width * 2.2, 0.0, 1.0);
}

vec3 underside_surface(vec3 world, float clock, float column, vec2 screen_uv, vec3 camera_position, float distance_m) {
    // Reuse the surface's short-crested packets at a broader, wind-stretched
    // optical scale when seen through a deep water column.
    vec3 wave = ocean_sample_at(world.xz * vec2(0.42, 0.82), clock * 0.55);
    vec2 uv = world.xz / max(underside_normal_metres, 1.0);
    vec2 strip = underside_strip(uv, clock);
    vec3 n = normalize(vec3(-wave.y * 0.65 - strip.x * underside_normal_strength,
        1.0, -wave.z * 0.65 - strip.y * underside_normal_strength));
    vec3 incident = normalize(world - camera_position);
    // Above-water sun refracts toward the vertical underwater. Use its
    // underwater direction and perturb it by the actual shared wave slope;
    // no hard refract/TIR colour switch at the critical angle.
    vec3 s = normalize(sun_direction);
    vec2 sxz = s.xz / 1.333;
    vec3 underwater_sun = normalize(vec3(sxz.x, sqrt(max(0.01, 1.0 - dot(sxz,sxz))), sxz.y));
    vec3 light_ray = normalize(incident + vec3(n.x, 0.0, n.z) * 0.9);
    float alignment = max(dot(light_ray, underwater_sun), 0.0);
    float sun_core = underside_sun_lobe(light_ray, underwater_sun);
    float sun_halo = pow(alignment, 24.0);

    // Only positive moving crests: never multiply the surface by dark bands.
    // Two scrolling samples break up the contour, rather than sin*sin grime.
    vec2 drift = vec2(clock * 0.006, clock * 0.003);
    vec2 a = texture(large_wave_normals, uv - drift).gb;
    vec2 b = texture(large_wave_normals, uv * vec2(0.83,1.13)
        + drift * 0.73 + vec2(0.37,0.61)).gb;
    // Crest lighting follows the shared wave slope, not an isocontour cut
    // from the normal texture (that read as polygon islands/paper flakes).
    float ridge = smoothstep(0.025, 0.105, wave.y + strip.x * 0.018);
    float broken = smoothstep(0.43, 0.58, b.y);
    float crests = ridge * (0.35 + 0.65 * broken);
    float daytime = mix(0.16, 1.0, sun_strength);
    float depth_light = mix(1.0, 0.46, smoothstep(2.0, 120.0, column));
    float upward = smoothstep(0.02, 0.55, max(incident.y,0.0));
    vec3 body = mix(vec3(0.045, 0.31, 0.66), vec3(0.13, 0.57, 0.86), upward);
    body *= depth_light * daytime;
    vec3 crest_colour = vec3(0.77, 0.97, 1.0) * mix(0.65,1.0,depth_light) * daytime;
    vec3 display = mix(body, crest_colour,
        crests * underside_wave_light * mix(0.55,1.0,upward));
    display = mix(display, vec3(0.94,0.99,1.0) * mix(0.65,1.0,depth_light),
        clamp((sun_core * 0.75 + sun_halo * 0.26) * sun_strength * underside_sun_light,0.0,0.88));
    // Fade finite geometry before the established fog boundary; this is only
    // the surface material's optical edge, not a second screen fog pass.
    float edge = smoothstep(125.0,190.0,distance_m);
    display = mix(display, uw_gradient_display(screen_uv,column), edge);
    return uw_display_to_hdr(clamp(display,vec3(0.0),vec3(0.98)));
}
