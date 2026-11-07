shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform vec4 lamp_color : source_color = vec4(1.0, 0.58, 0.25, 1.0);
uniform float roughness_value = 0.65;
uniform float metallic_value = 0.2;
varying vec3 local_position;
void vertex() { local_position=VERTEX; }
void fragment() {
	ALBEDO=texture(palette,UV).rgb;
	ROUGHNESS=roughness_value;
	METALLIC=metallic_value;
	float lens=step(6.774,local_position.y)*(1.0-step(6.826,local_position.y))*step(0.674,local_position.x);
	EMISSION=lamp_color.rgb*lens*1.6;
}
