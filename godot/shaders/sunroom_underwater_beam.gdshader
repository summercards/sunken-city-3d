shader_type spatial;
// 沿用旧海域的低频流动；封闭代理体内积分，不再使用朝相机的白色薄片。
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 tint : source_color = vec3(0.48, 0.78, 0.71);
uniform float elapsed = 0.0;
uniform float phase = 0.0;
uniform float radius = 3.0;
uniform float beam_length = 24.0;
uniform float density = 0.008;
uniform float gain = 1.0;
varying vec3 local_camera;
varying vec3 local_surface;

void vertex() {
	local_camera = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz;
	local_surface = VERTEX;
}

void fragment() {
	vec3 direction = normalize(local_surface - local_camera);
	float a = dot(direction.xz, direction.xz);
	float b = dot(local_camera.xz, direction.xz);
	float c = dot(local_camera.xz, local_camera.xz) - radius * radius;
	float enter = 0.0;
	float leave = 10000.0;
	if (a < 0.000001) {
		if (c > 0.0) { discard; }
	} else {
		float discriminant = b * b - a * c;
		if (discriminant < 0.0) { discard; }
		enter = max(0.0, (-b - sqrt(discriminant)) / a);
		leave = (-b + sqrt(discriminant)) / a;
	}
	if (abs(direction.y) < 0.000001) {
		if (abs(local_camera.y) > beam_length * 0.5) { discard; }
	} else {
		float cap_a = (-beam_length * 0.5 - local_camera.y) / direction.y;
		float cap_b = (beam_length * 0.5 - local_camera.y) / direction.y;
		enter = max(enter, min(cap_a, cap_b));
		leave = min(leave, max(cap_a, cap_b));
	}

	float raw_depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = raw_depth * 2.0 - 1.0;
#endif
	vec4 opaque_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float opaque_distance = length(opaque_view.xyz / opaque_view.w);
	leave = min(leave, opaque_distance - 0.12);
	if (leave <= enter) { discard; }
	float step_length = (leave - enter) / 16.0;
	float integrated = 0.0;
	for (int i = 0; i < 16; i++) {
		float distance_along = enter + (float(i) + 0.5) * step_length;
		vec3 p = local_camera + direction * distance_along;
		float height = clamp(0.5 - p.y / beam_length, 0.0, 1.0);
		float taper = mix(0.42, 0.96, height);
		float radial = length(p.xz) / (radius * taper);
		float edge = pow(max(0.0, 1.0 - radial * radial), 2.0);
		float ends = smoothstep(0.0, 0.09, height) * (1.0 - smoothstep(0.64, 1.0, height));
		float flow = 0.84 + 0.10 * sin(height * 7.1 + elapsed * 0.31 + phase)
			+ 0.06 * sin(p.x * 0.63 + p.z * 0.41 - elapsed * 0.19 + phase);
		float intersection = smoothstep(0.0, 1.25, opaque_distance - distance_along);
		integrated += edge * ends * flow * intersection * step_length;
	}
	vec3 world_center=MODEL_MATRIX[3].xyz;
	float far_fade = 1.0-region_fog_amount(length(world_center-CAMERA_POSITION_WORLD),world_center.xz);
	ALBEDO = vec3(0.58, 0.88, 0.74) * mix(vec3(1.0), tint, 0.15);
	ALPHA = 0.23 * (1.0 - exp(-integrated * density * gain / 0.23)) * far_fade;
}
