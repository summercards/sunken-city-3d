shader_type spatial;
// 不透明场景统一水雾：在透明特效之前合成，保留实体深度供后续透明物体测试。
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://shaders/uw_water_color.gdshaderinc"
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float dive_depth = 10.0;
// 同 water.gdshader：Reverse-Z 只在 Forward+ 成立，Web(gl_compatibility) 是标准 Z。
uniform float u_reverse_z = 1.0;
void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
    vec3 hdr = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
    float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
    float ndc_z = u_reverse_z > 0.5 ? depth : depth * 2.0 - 1.0;
    vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_z, 1.0);
    float distance = max(0.0, -view.z / view.w);
    float density = mix(0.026, 0.012, smoothstep(65.0, 210.0, dive_depth));
    float fog = depth <= 0.0 ? 0.0 : clamp(1.0 - exp(-pow(distance * density, 1.8)), 0.0, 1.0);
    vec3 display_color = mix(uw_hdr_to_display(hdr), uw_gradient_display(SCREEN_UV, dive_depth), fog);
    ALBEDO = uw_display_to_hdr(display_color);
    // 全屏合成刻意处于透明阶段；普通实体禁止写 ALPHA。
    ALPHA = 1.0;
}
