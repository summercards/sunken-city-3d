// 所有水下实体共用的着色阶段。实体变体不能读取/写入 ALPHA。
#include "res://shaders/uw_common.gdshaderinc"
#ifdef UW_TRANSPARENT
uniform float alpha : hint_range(0.0, 1.0) = 0.4;
#endif

void vertex() {
    v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal_w = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    v_color = COLOR;
    v_view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
    // Godot 自动翻转双面材质的 NORMAL；自定义世界法线由 uw_face_normal 处理。
    vec3 base = uw_base();
    ALBEDO = base;
    ROUGHNESS = roughness;
    METALLIC = metallic;
    SPECULAR = 0.5;
    EMISSION = uw_emission(base, uw_face_normal(FRONT_FACING));
#ifdef UW_TRANSPARENT
    // 透明物体在统一屏幕水雾之后绘制，需要自行衰减（不能写入实体深度）。
    FOG = vec4(uw_water_color(SCREEN_UV), uw_fog_amount());
    ALPHA = alpha;
#endif
}
