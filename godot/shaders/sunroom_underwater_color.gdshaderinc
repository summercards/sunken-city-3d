#include "res://shaders/uw_water_color.gdshaderinc"
// 家园海底沿用九张旧图的同一套水体模型，不再使用区域自算的方向渐变：
//   1. 屏幕垂直渐变：背景天空、水面、终端雾在任一像素上取同一个显示色；
//   2. 指数水雾：1 - exp(-(距离 × 密度)^1.8)，与 uw_common 的 uw_fog_amount 逐字一致。
// 这里不允许再叠加方向雾 / 水平分层 / 边缘吸收，否则就是第二层雾。
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

float region_fog_amount(float distance_m) {
	// 仅保留一个指数通道；密度在 85m 后封顶，避免 120m 处反而更通透。
	float density_depth = min(region_active_depth(), 85.0);
	float density = mix(0.026, 0.012, smoothstep(65.0, 210.0, density_depth));
	return clamp(1.0 - exp(-pow(max(distance_m, 0.0) * density, 1.8)), 0.0, 1.0);
}

// 环境辐照用的上下双色（与 uw_sky.gdshader 的 AT_CUBEMAP_PASS 分支相同）：
// 天顶薄荷、底部深蓝，建筑上表面偏青绿、下表面偏蓝，才有体积。
vec3 region_hemisphere_linear(vec3 eye_dir) {
	return mix(uw_srgb_to_linear(vec3(0.188235, 0.32549, 0.545098)),
		uw_srgb_to_linear(vec3(0.733333, 1.0, 0.937255)), eye_dir.y * 0.5 + 0.5);
}
