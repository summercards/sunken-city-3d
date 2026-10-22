shader_type spatial;
// 共用 PBR / 焦散 / 水雾流程，仅剔除和透明策略不同。
render_mode diffuse_lambert, specular_schlick_ggx, cull_back, depth_draw_opaque;

#include "res://shaders/uw_surface.gdshaderinc"
