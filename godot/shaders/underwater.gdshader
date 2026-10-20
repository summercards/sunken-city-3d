shader_type spatial;
// 水下静态几何：焦散 + 自发光 + 深度衰减（见 uw_common.gdshaderinc）。
// cull_disabled：海床、断崖、帆布在网页版里是双面的，关掉剔除以免漏面。
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

#include "res://shaders/uw_common.gdshaderinc"

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
	ALPHA = 1.0;
}
