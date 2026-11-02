shader_type spatial;
render_mode specular_disabled;
uniform vec4 base_color : source_color = vec4(0.45,0.72,0.65,1.0);
uniform vec4 stripe_color : source_color = vec4(1.0,0.945,0.835,1.0);
varying float cloth_height;
void vertex() { cloth_height = VERTEX.y; }
void fragment() {
	float band = step(0.80, fract((cloth_height + 1.0) * 3.5));
	ALBEDO = mix(base_color.rgb, stripe_color.rgb, band);
	ROUGHNESS = 0.95;
}
