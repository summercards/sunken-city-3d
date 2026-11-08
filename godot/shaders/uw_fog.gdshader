shader_type spatial;
// 单一屏幕水雾通道：只对已有几何按距离吸收，向上看向水面时不把射线抹成纯色。
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://shaders/uw_water_color.gdshaderinc"
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float dive_depth = 10.0;
uniform float view_depth = -1.0;
uniform float water_level = 1.12;
uniform float surface_fog_gain : hint_range(0.0, 0.25, 0.005) = 0.06;
uniform float u_reverse_z = 1.0;

float active_depth() {
	return view_depth >= 0.0 ? view_depth : dive_depth;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 hdr = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec3 ray_ndc = vec3(SCREEN_UV * 2.0 - 1.0, 1.0);
	vec4 ray_view = INV_PROJECTION_MATRIX * vec4(ray_ndc, 1.0);
	vec3 ray_direction = normalize((INV_VIEW_MATRIX * vec4(normalize(ray_view.xyz / ray_view.w), 0.0)).xyz);
	float ndc_z = u_reverse_z > 0.5 ? depth : depth * 2.0 - 1.0;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_z, 1.0);
	float distance_m = max(0.0, -view.z / view.w);
	vec3 world_point = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	float fog = depth <= 0.0 ? 0.0 : clamp(1.0 - exp(-pow(distance_m * mix(0.026, 0.012, smoothstep(65.0, 210.0, min(active_depth(), 85.0))), 1.8)), 0.0, 1.0);
	// 天空或命中水面的向上射线只保留很弱吸收；其它几何雾不减弱。
	float surface_match = 1.0 - smoothstep(0.35, 2.0, abs(world_point.y - water_level));
	if (depth <= 0.0 || (ray_direction.y > 0.0 && surface_match > 0.0)) {
		fog = max(ray_direction.y, 0.0) * surface_fog_gain * smoothstep(5.0, 120.0, active_depth());
	}
	vec3 display_color = mix(uw_hdr_to_display(hdr), uw_gradient_display(SCREEN_UV, active_depth()), fog);
	ALBEDO = uw_display_to_hdr(display_color);
	ALPHA = 1.0;
}
