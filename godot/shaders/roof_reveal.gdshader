shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float surface_roughness = 0.5;
uniform float surface_metallic = 0.0;
uniform vec3 glow_tint : source_color = vec3(0.0);
uniform float glow_energy = 0.0;
uniform mat4 facility_inverse;
uniform vec2 reveal_center = vec2(0.0);
uniform float reveal_amount : hint_range(0.0, 1.0) = 0.0;
uniform float reveal_reach = 16.0;
uniform float feather_width = 1.0;
varying vec2 facility_xz;

void vertex() {
	vec3 local = (facility_inverse * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facility_xz = local.xz;
}

void fragment() {
	vec4 swatch = texture(palette, UV);
	ALBEDO = swatch.rgb * tint.rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	EMISSION = swatch.rgb * glow_tint * glow_energy;
	float eased = smoothstep(0.0, 1.0, reveal_amount);
	float radius = mix(-2.0 * feather_width, reveal_reach + 2.0 * feather_width, eased);
	float distance_from_actor = length(facility_xz - reveal_center);
	float outside_circle = smoothstep(radius - feather_width, radius + feather_width, distance_from_actor);
	float final_fade = 1.0 - smoothstep(0.78, 1.0, reveal_amount);
	ALPHA = tint.a * outside_circle * final_fade;
}
