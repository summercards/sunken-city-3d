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
	if (is_leg) {
		if (distance < trouser_end) color = trouser_color.rgb;
		if (distance >= shoe_start) color = shoe_color.rgb;
		if (UV2.y > 0.023) color = sole_color.rgb;
	} else if (distance < sleeve_end) color = cloth_color.rgb;
	ALBEDO = color;
	ROUGHNESS = 0.9;
}
