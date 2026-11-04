shader_type spatial;
render_mode specular_disabled;
uniform vec4 base_color : source_color = vec4(0.36,0.63,0.56,1.0);
uniform vec4 stripe_color : source_color = vec4(0.96,0.92,0.82,1.0);
varying float cloth_height;
varying vec3 local_nrm;
void vertex() {
	cloth_height = VERTEX.y;
	local_nrm = NORMAL;
}
void fragment() {
	float phase = fract((cloth_height + 1.04) * 3.8);
	float band = smoothstep(0.74, 0.78, phase) * (1.0 - smoothstep(0.95, 0.99, phase));
	vec3 col = mix(base_color.rgb, stripe_color.rgb, band);
	float hem_shade = smoothstep(-1.02, -0.58, cloth_height);
	col *= mix(0.90, 1.03, hem_shade);
	float rim = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.4);
	ALBEDO = col + vec3(0.05, 0.045, 0.035) * rim;
	ROUGHNESS = 0.88;
}
