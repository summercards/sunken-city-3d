// 网页版水色在色调映射后合成；Godot 的 FOG/天空在 ACES 前。
// 反解 Godot ACES（white=14.260244），避免把显示色再次曝光，产生发白的水雾。
// 公式对应 Godot renderer_rd/shaders/effects/tonemap.glsl 的 tonemap_aces。
uniform float water_exposure = 1.0185185185;
vec3 uw_srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 uw_display_to_hdr(vec3 c) {
    mat3 input_matrix = mat3(vec3(0.59719, 0.35458, 0.04823),
        vec3(0.07600, 0.90834, 0.01566), vec3(0.02840, 0.13383, 0.83777)) * 1.8;
    mat3 output_matrix = mat3(vec3(1.60475, -0.53108, -0.07367),
        vec3(-0.10208, 1.10813, -0.00605), vec3(-0.00327, -0.07276, 1.07602));
    // 运行环境白点令归一化因子为 1，和 Three ACES 保持一致。
    vec3 y = uw_srgb_to_linear(c) * inverse(output_matrix);
    vec3 a = y * 0.983729 - 1.0;
    vec3 b = y * 0.432951 - 0.0245786;
    vec3 d = y * 0.238081 + 0.000090537;
    vec3 x = (-b - sqrt(max(b * b - 4.0 * a * d, vec3(0.0)))) / (2.0 * a);
    return (x * inverse(input_matrix)) / water_exposure;
}
vec3 uw_gradient_display(vec2 screen_uv, float depth) {
    float d = clamp((depth - 8.0) / 72.0, 0.0, 1.0);
    vec3 top = mix(vec3(0.12, 0.91, 0.87), vec3(0.025, 0.28, 0.49), d);
    vec3 bottom = mix(vec3(0.025, 0.36, 0.62), vec3(0.008, 0.07, 0.20), d);
    return mix(bottom, top, pow(clamp(1.0 - screen_uv.y, 0.0, 1.0), 0.8));
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
