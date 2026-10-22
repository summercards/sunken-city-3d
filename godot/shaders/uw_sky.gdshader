shader_type sky;
#include "res://shaders/uw_water_color.gdshaderinc"
uniform float dive_depth = 10.0;
void sky() {
    if (AT_CUBEMAP_PASS) {
        // 辐照用网页版 HemisphereLight 的上下两色，不能用可见背景代替环境光。
        COLOR = mix(uw_srgb_to_linear(vec3(0.188235, 0.32549, 0.545098)),
            uw_srgb_to_linear(vec3(0.733333, 1.0, 0.937255)), EYEDIR.y * 0.5 + 0.5);
    } else {
        COLOR = uw_gradient(SCREEN_UV, dive_depth);
    }
}
