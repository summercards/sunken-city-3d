shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float roughness_value = 0.72;
uniform float metallic_value = 0.0;
// Exposed for the shared lighting verification contract. No emissive fill.
uniform float ambient_boost = 0.0;
void fragment() {
	ALBEDO = texture(palette, UV).rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.28;
}
