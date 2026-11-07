shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float surface_roughness = 0.5;
uniform float surface_metallic = 0.0;
uniform vec3 glow_tint : source_color = vec3(0.0);
uniform float glow_energy = 0.0;
uniform vec2 window_center = vec2(0.5);
uniform vec2 window_radius = vec2(0.2, 0.3);
uniform float reveal_amount : hint_range(0.0, 1.0) = 0.0;
uniform float feather : hint_range(0.01, 0.8) = 0.22;
uniform float ghost_opacity : hint_range(0.0, 1.0) = 0.08;
uniform vec2 focus_xz;
uniform vec2 near_direction;
uniform float focus_depth = 20.0;
varying vec2 world_xz;
varying float view_depth;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_xz = world.xz;
	view_depth = -(VIEW_MATRIX * world).z;
}

void fragment() {
	vec4 swatch = texture(palette, UV);
	ALBEDO = swatch.rgb * tint.rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	EMISSION = swatch.rgb * glow_tint * glow_energy;
	float ellipse = length((SCREEN_UV - window_center) / max(window_radius, vec2(0.001)));
	float aperture = 1.0 - smoothstep(1.0 - feather, 1.0, ellipse);
	// Both gates are necessary: tall far walls can be optically closer than
	// the actor's torso, but still belong to the far side of the room.
	float near_side = smoothstep(-0.35, 0.25, dot(world_xz - focus_xz, near_direction));
	float in_front = 1.0 - smoothstep(focus_depth - 0.12, focus_depth + 0.18, view_depth);
	float cut = aperture * near_side * in_front * smoothstep(0.0, 1.0, reveal_amount);
	ALPHA = tint.a * mix(1.0, ghost_opacity, cut);
}
