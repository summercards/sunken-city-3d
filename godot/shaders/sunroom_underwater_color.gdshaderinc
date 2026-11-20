#include "res://shaders/uw_water_color.gdshaderinc"
// 背景与终端雾仍共用屏幕水色；家园在唯一合成通道中对原消光曲线作 RGB 分光。
// 粒子继续用同一条基准密度作标量近似，不另叠一层方向雾。
uniform float region_view_depth : hint_range(0.0, 300.0, 0.01) = 10.0;
uniform float view_depth : hint_range(-1.0, 300.0, 0.01) = -1.0;
uniform float dive_depth : hint_range(-1.0, 300.0, 0.01) = -1.0;
uniform float water_level : hint_range(-200.0, 300.0, 0.001) = 101.587442;

float region_active_depth() {
	if (view_depth >= 0.0) {
		return view_depth;
	}
	if (dive_depth >= 0.0) {
		return dive_depth;
	}
	return region_view_depth;
}

vec3 region_water_display(vec2 screen_uv) {
	return uw_gradient_display(screen_uv, region_active_depth());
}

float region_optical_depth(float distance_m) {
	// 保留项目标定的基础曲线；密度在 85m 后封顶，避免深水变透明。
	float density = mix(0.026, 0.012, smoothstep(65.0, 210.0, min(region_active_depth(), 85.0)));
	return pow(max(distance_m, 0.0) * density, 1.8);
}

float region_fog_amount(float distance_m) {
	return 1.0 - exp(-region_optical_depth(distance_m));
}

vec3 region_refracted_sun() {
	vec2 lateral = normalize(sun_direction).xz / max(surface_ior, 1.001);
	return vec3(lateral.x, sqrt(max(0.01, 1.0 - dot(lateral, lateral))), lateral.y);
}

vec2 region_sun_footprint(vec3 point, vec3 toward_sun) {
	return point.xz + toward_sun.xz * (water_level - point.y) / toward_sun.y;
}

// 环境辐照用的上下双色（与 uw_sky.gdshader 的 AT_CUBEMAP_PASS 分支相同）：
// 天顶薄荷、底部深蓝，建筑上表面偏青绿、下表面偏蓝，才有体积。
vec3 region_hemisphere_linear(vec3 eye_dir) {
	return mix(uw_srgb_to_linear(vec3(0.188235, 0.32549, 0.545098)),
		uw_srgb_to_linear(vec3(0.733333, 1.0, 0.937255)), eye_dir.y * 0.5 + 0.5);
}
