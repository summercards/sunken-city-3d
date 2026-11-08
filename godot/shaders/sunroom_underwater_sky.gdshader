shader_type sky;
// 可见背景与环境辐照分离；两者均按相机水深使用同一方向色，避免天空/雾边界。
#include "res://shaders/sunroom_underwater_color.gdshaderinc"

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = region_hemisphere_linear(EYEDIR) * uw_depth_light(region_active_depth()) * mix(0.24, 1.0, sun_strength);
	} else {
		COLOR = uw_display_to_hdr(region_water_display(SCREEN_UV));
	}
}
