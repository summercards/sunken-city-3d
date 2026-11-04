shader_type spatial;
render_mode specular_disabled;
uniform bool is_leg = false;
uniform vec4 skin_color : source_color;
uniform vec4 cloth_color : source_color;
uniform vec4 trouser_color : source_color;
uniform vec4 shoe_color : source_color;
uniform vec4 sole_color : source_color;
uniform float sleeve_end = 0.115;
uniform float trouser_end = 0.18;
uniform float shoe_start = 0.341;
uniform bool sneakers = true;
void fragment() {
	float distance = UV2.x;
	vec3 color = skin_color.rgb;
	// Subtle warm skin volume at hands and knees
	float skin_warmth = smoothstep(0.18, 0.35, distance);
	vec3 warm_skin = mix(skin_color.rgb, skin_color.rgb * vec3(1.02, 0.94, 0.90), skin_warmth * 0.45);
	color = warm_skin;
	if (is_leg) {
		float cuff = 1.0 - smoothstep(trouser_end - 0.008, trouser_end + 0.004, distance);
		vec3 trouser = trouser_color.rgb;
		// Subtle woven cuff trim at trouser hem
		if (trouser_end < 0.5 && abs(distance - (trouser_end - 0.012)) < 0.007) {
			trouser = trouser * 1.12;
		}
		color = mix(color, trouser, cuff);
		float sock = smoothstep(shoe_start - 0.026, shoe_start - 0.020, distance) * (1.0 - smoothstep(shoe_start - 0.003, shoe_start + 0.002, distance));
		color = mix(color, vec3(0.95, 0.92, 0.84), sock * 0.85);
		float shoe_mask = smoothstep(shoe_start - 0.004, shoe_start + 0.004, distance);
		vec3 shoe = shoe_color.rgb;
		if (sneakers && distance > shoe_start + 0.018 && UV2.y > 0.010) {
			shoe = mix(shoe, sole_color.rgb, 0.65);
		}
		color = mix(color, shoe, shoe_mask);
		if (UV2.y > 0.021) color = sole_color.rgb;
	} else {
		float sleeve_mask = 1.0 - smoothstep(sleeve_end - 0.006, sleeve_end + 0.005, distance);
		vec3 sleeve = cloth_color.rgb;
		if (abs(distance - (sleeve_end - 0.010)) < 0.005) {
			sleeve = sleeve * 1.10;
		}
		color = mix(color, sleeve, sleeve_mask);
	}
	float rim = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	ALBEDO = color + vec3(0.035, 0.032, 0.025) * rim;
	ROUGHNESS = 0.86;
}
