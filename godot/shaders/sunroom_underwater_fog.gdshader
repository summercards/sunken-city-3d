shader_type spatial;
// 家园唯一屏幕水雾通道；水面方向只做弱吸收，不与 Snell 水窗抢色。
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float u_reverse_z = 1.0;
uniform float surface_fog_gain : hint_range(0.0, 0.25, 0.005) = 0.06;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 hdr = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	float ndc_z = u_reverse_z > 0.5 ? depth : depth * 2.0 - 1.0;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_z, 1.0);
	float distance_m = max(0.0, -view.z / view.w);
	vec3 world_point = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	float fog = depth <= 0.0 ? 0.0 : region_fog_amount(distance_m);
	vec4 ray_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	float ray_up = max(0.0, (INV_VIEW_MATRIX * vec4(normalize(ray_view.xyz / ray_view.w), 0.0)).y);
	float surface_match = 1.0 - smoothstep(0.35, 2.0, abs(world_point.y - water_level));
	if (depth <= 0.0 || (ray_up > 0.0 && surface_match > 0.0)) {
		fog = ray_up * surface_fog_gain * smoothstep(5.0, 120.0, region_active_depth());
	}
	vec3 display_color = mix(uw_hdr_to_display(hdr), region_water_display(SCREEN_UV), fog);
	ALBEDO = uw_display_to_hdr(display_color);
	ALPHA = 1.0;
}
