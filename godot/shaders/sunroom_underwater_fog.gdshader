shader_type spatial;
// 家园唯一屏幕水雾通道；水面方向只做弱吸收，不与 Snell 水窗抢色。
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float surface_fog_gain : hint_range(0.0, 0.25, 0.005) = 0.06;
uniform float shaft_gain : hint_range(0.0, 2.0) = 1.0;
uniform float elapsed = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// World-space pools of focused light. Independent frequency and direction keep
// them from looking like screen-space stripes or perfectly repeated cones.
float shaft_pattern(vec2 q) {
	vec2 p = q * 0.26;
	float filament = sin(dot(p, vec2(0.82, 0.57)) + 0.69 * sin(p.y * 0.49 + elapsed * 0.32));
	float pocket = cos(dot(p, vec2(-0.31, 0.75)) + elapsed * 0.21);
	return smoothstep(0.35, 0.98, filament) * mix(0.14, 1.0, smoothstep(-0.48, 0.92, pocket));
}

vec3 shaft_scattering(vec3 origin, vec3 ray, float opaque_distance, vec3 toward_sun) {
	float column = water_level - origin.y;
	float exposure = shaft_gain * sun_strength * smoothstep(0.01, 0.20, sun_direction.y);
	if (column <= 0.0 || exposure <= 0.0) { return vec3(0.0); }
	float travel = min(opaque_distance, 64.0);
	if (ray.y > 0.0001) { travel = min(travel, column / ray.y); }
	if (travel < 0.1 || column > 104.0) { return vec3(0.0); }
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	const int sample_count = 8;
#else
	const int sample_count = 4;
#endif
	float step_m = travel / float(sample_count);
	vec2 surface_origin = region_sun_footprint(origin, toward_sun);
	vec2 surface_step = (ray.xz - toward_sun.xz * ray.y / toward_sun.y) * step_m;
	float integrated = 0.0;
	for (int i = 0; i < sample_count; i++) {
		float offset = float(i) + 0.5;
		float t = offset * step_m;
		float depth = max(0.0, column - ray.y * t);
		float light = shaft_pattern(surface_origin + surface_step * offset);
		integrated += light * exp(-0.038 * depth / toward_sun.y - 0.035 * t);
	}
	float alignment = max(dot(ray, toward_sun), 0.0);
	float phase = 0.25 + 0.75 * alignment * alignment;
	float deep_fade = 1.0 - smoothstep(62.0, 104.0, column);
	return vec3(0.38, 0.81, 0.92) * sun_color * integrated * step_m * phase * deep_fade * exposure * 0.085;
}

void fragment() {
	vec3 hdr = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	float raw_depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	// Current Godot uses reverse Z on all three renderers, but GL maps it to [-1, 1].
	float ndc_z = raw_depth;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc_z = raw_depth * 2.0 - 1.0;
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, ndc_z, 1.0);
	vec3 point_view = view.xyz / view.w;
	vec3 ray = mat3(INV_VIEW_MATRIX) * normalize(point_view);
	float path_m = length(point_view);
	bool sky_depth = raw_depth <= 0.0000001;
	vec3 origin = CAMERA_POSITION_WORLD;
	vec3 point = origin + ray * path_m;
	vec3 composite = hdr;
	if (!sky_depth) {
		vec3 water_hdr = uw_display_to_hdr(region_water_display(SCREEN_UV));
		float optical = region_optical_depth(path_m);
		vec3 transmittance = exp(-vec3(1.43, 0.95, 0.80) * optical);
		// The existing surface keeps its wave colour nearby. Only geometric hits
		// within the waterline tolerance are eligible; nearby roofs are not.
		float surface_match = 1.0 - smoothstep(0.22, 0.32, abs(point.y - water_level));
		float surface_weight = surface_match * smoothstep(0.002, 0.028, ray.y);
		// At grazing angles merge into the same open-water colour earlier.
		// Steep 20–55m shots retain the signed underside highlights.
		float grazing = 1.0 - smoothstep(0.04, 0.24, ray.y);
		float edge = smoothstep(mix(125.0, 58.0, grazing), mix(190.0, 142.0, grazing), path_m);
		float surface_transmission = (1.0 - max(0.0, ray.y) * surface_fog_gain) * (1.0 - edge);
		transmittance = mix(transmittance, vec3(surface_transmission), surface_weight);
		composite = mix(water_hdr, hdr, transmittance);
	}
	composite += shaft_scattering(origin, ray, path_m, region_refracted_sun());
	ALBEDO = max(composite, vec3(0.0));
	ALPHA = 1.0;
}
