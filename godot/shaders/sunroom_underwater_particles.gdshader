shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, fog_disabled;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 tint : source_color = vec3(0.46, 0.76, 0.73);
uniform bool bubble = true;
uniform float opacity = 0.42;
uniform float gain = 1.0;
varying vec4 particle_color;

void vertex() {
	particle_color = COLOR;
	// 保留实例尺度，仅把单位面片转到视平面；每类仍只有一个 MultiMesh 提交。
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	VERTEX = center + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radial = length(p);
	float shape;
	if (bubble) {
		float rim = exp(-pow((radial - 0.74) / 0.095, 2.0)) * 0.58;
		float glint = exp(-dot(p - vec2(-0.24, -0.34), p - vec2(-0.24, -0.34)) * 64.0);
		shape = (rim + glint * 0.75 + max(0.0, 1.0 - radial * radial) * 0.025)
			* (1.0 - smoothstep(0.82, 0.98, radial));
	} else {
		shape = exp(-radial * radial * 4.8) * (1.0 - smoothstep(0.55, 1.0, radial));
	}
	float raw_depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = raw_depth * 2.0 - 1.0;
#endif
	vec4 opaque_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float opaque_depth = -opaque_view.z / opaque_view.w;
	float soft_contact = smoothstep(0.0, 0.45, opaque_depth + VERTEX.z);
	float camera_fade = smoothstep(0.35, 1.3, -VERTEX.z);
	float far_fade = 1.0 - smoothstep(65.0, 150.0, length(VERTEX));
	vec3 direction=normalize((INV_VIEW_MATRIX*vec4(VERTEX,0.0)).xyz);
	vec3 world=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
	float water_fog=region_fog_amount(length(VERTEX),world.xz);
	ALBEDO = mix(tint * particle_color.rgb,uw_display_to_hdr(region_water_display(direction)),water_fog);
	ALPHA = shape * opacity * particle_color.a * soft_contact * camera_fade * far_fade * gain * (1.0-water_fog);
}
