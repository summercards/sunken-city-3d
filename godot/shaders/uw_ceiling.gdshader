shader_type spatial;
// 水下顶盖：波面法线同时驱动 Snell 折射窗、掠视内反射和暖白太阳碎光。
render_mode unshaded, cull_disabled, fog_disabled;

#include "res://shaders/uw_water_color.gdshaderinc"
uniform float elapsed = 0.0;
varying vec3 v_world;
varying vec3 v_normal;

float uw_wave(vec2 p, float t) {
	return sin(p.x * 0.72 + t * 0.85) * 0.10
		+ sin(p.y * 0.93 - t * 0.69) * 0.07
		+ sin((p.x + p.y) * 1.8 + t * 1.1) * 0.025;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = elapsed == 0.0 ? TIME : elapsed;
	w.y += uw_wave(w.xz, t);
	v_world = w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	float t = elapsed == 0.0 ? TIME : elapsed;
	vec2 p = v_world.xz;
	vec2 slope = vec2(
		0.072 * cos(p.x * 0.72 + t * 0.85) + 0.045 * cos((p.x + p.y) * 1.8 + t * 1.1),
		0.065 * cos(p.y * 0.93 - t * 0.69) + 0.045 * cos((p.x + p.y) * 1.8 + t * 1.1));
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	ALBEDO = uw_surface_optics(v_world, n, v, t, max(0.0, v_world.y - CAMERA_POSITION_WORLD.y));
}
