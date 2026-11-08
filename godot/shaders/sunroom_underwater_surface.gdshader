shader_type spatial;
// 家园水面与旧海域共用同一条表面光学：波纹法线、Snell 折射窗、掠视内反射。
render_mode cull_disabled, unshaded, depth_draw_opaque, fog_disabled;

#include "res://shaders/uw_water_color.gdshaderinc"
uniform float water_level = 101.587442;
uniform float elapsed = 0.0;
uniform float view_depth = -1.0;
uniform float region_view_depth = 10.0;
uniform float dive_depth = -1.0;
varying vec3 v_world;

float surface_wave(vec2 p, float t) {
	return sin(p.x * 0.23 + p.y * 0.11 + t * 0.52) * 0.12
		+ sin(p.x * -0.17 + p.y * 0.31 - t * 0.43) * 0.075
		+ sin(p.x * 0.47 - p.y * 0.29 + sin(p.y * 0.13) * 0.8 + t * 0.68) * 0.025;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = elapsed == 0.0 ? TIME : elapsed;
	vec2 p = v_world.xz;
	float e = 0.02;
	float h_x0 = surface_wave(p - vec2(e, 0.0), t);
	float h_x1 = surface_wave(p + vec2(e, 0.0), t);
	float h_z0 = surface_wave(p - vec2(0.0, e), t);
	float h_z1 = surface_wave(p + vec2(0.0, e), t);
	vec3 n = normalize(vec3(-(h_x1 - h_x0) / (2.0 * e), 1.0, -(h_z1 - h_z0) / (2.0 * e)));
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	ALBEDO = uw_surface_optics(v_world, n, v, t, max(0.0, water_level - CAMERA_POSITION_WORLD.y));
}
