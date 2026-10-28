shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_never, blend_mix;

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
	vec3 albedo = base.rgb * albedo_tint;
	vec3 emit = albedo * ambient_boost;
	if (depth_tint) {
		vec3 depth_emit = vec3(0.0);
		albedo = apply_depth_tint(albedo, wp, depth_emit);
		emit += depth_emit;
	}
	ALBEDO = albedo;
	EMISSION += emit * world_daylight;
	ALPHA = base.a;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float half_lambert = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	float sub = depth_tint ? smoothstep(0.0, 0.45, water_level - v_world.y) : 0.0;
	float eff_atten = mix(ATTENUATION, mix(0.62, 1.0, ATTENUATION), sub);
	float lit_factor = half_lambert * eff_atten;
	float low_floor = mix(0.28, 0.60, sub);
	float soft_band = mix(low_floor, 0.96, smoothstep(0.14, 0.78, lit_factor));
	vec3 shadow_tint = mix(vec3(0.68, 0.86, 0.94), vec3(1.0, 0.99, 0.96), smoothstep(0.18, 0.72, lit_factor));
	float local_atten = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	DIFFUSE_LIGHT += soft_band * shadow_tint * LIGHT_COLOR * local_atten / PI;
}
