shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled, depth_draw_never, blend_mix;

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
	EMISSION += emit;
	ALPHA = base.a;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float band = 1.0;
	if (ndl < -0.5) {
		band = 0.255;
	} else if (ndl < 0.0) {
		band = 0.525;
	} else if (ndl < 0.5) {
		band = 0.855;
	}
	DIFFUSE_LIGHT += band * LIGHT_COLOR * ATTENUATION / PI;
}
