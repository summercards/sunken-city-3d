shader_type sky;
#include "res://shaders/uw_water_color.gdshaderinc"
uniform float dive_depth = 10.0;
uniform float view_depth = -1.0;

float active_depth() {
	return view_depth >= 0.0 ? view_depth : dive_depth;
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = mix(uw_srgb_to_linear(vec3(0.188235, 0.32549, 0.545098)),
			uw_srgb_to_linear(vec3(0.733333, 1.0, 0.937255)), EYEDIR.y * 0.5 + 0.5)
			* uw_depth_light(active_depth()) * mix(0.24, 1.0, sun_strength);
	} else {
		COLOR = uw_gradient(SCREEN_UV, active_depth());
	}
}
