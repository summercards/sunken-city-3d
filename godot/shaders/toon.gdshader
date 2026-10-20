shader_type spatial;
render_mode diffuse_toon, specular_schlick_ggx, cull_disabled, depth_draw_opaque;

#include "res://shaders/toon_common.gdshaderinc"

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wp = world_pos();
	vec4 base = COLOR;
	if (use_texture) {
		base *= texture(albedo_tex, UV);
	}
	vec3 albedo = base.rgb;
	vec3 emit = vec3(0.0);
	if (depth_tint) {
		albedo = apply_depth_tint(albedo, wp, emit);
	}
	ALBEDO = albedo;
	// 墙面是刷过石灰的旧木/砖，不是塑料：高光只留一点点，粗糙度很高。
	// 全关高光会让大面积浅色墙面完全平掉，看起来就是"白纸过曝"。
	SPECULAR = 0.10;
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
	EMISSION += emit;
}

