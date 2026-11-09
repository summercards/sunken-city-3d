shader_type sky;
// 可见背景与环境辐照分离；两者均按相机水深使用同一方向色，避免天空/雾边界。
#include "res://shaders/sunroom_underwater_color.gdshaderinc"

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = region_hemisphere_linear(EYEDIR) * uw_irradiance_gain(region_active_depth());
	} else {
		COLOR = uw_display_to_hdr(region_water_display(SCREEN_UV));
	}
}
