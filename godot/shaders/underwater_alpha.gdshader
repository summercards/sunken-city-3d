shader_type spatial;
render_mode specular_disabled, cull_disabled, blend_mix, depth_draw_never;

#include "res://shaders/uw_common.gdshaderinc"

uniform float alpha : hint_range(0.0, 1.0) = 0.4;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR;
	v_view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec3 base = uw_base();
	float light = uw_light() * caustic_gain;
	vec3 lit = base * (0.88 + light * 1.1);
	float fog = uw_fog_amount();
	// 雾只作用在直射/漫反射上；自发光按剩余可见度衰减，
	// 否则远处每一块珊瑚都会把水色再加一遍，整屏发白。
	ALBEDO = mix(lit, uw_water_color(SCREEN_UV), fog);
	EMISSION = uw_emission(base) * (1.0 - fog);
	ALPHA = alpha;
}
