shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D mouth_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 tile_origin = vec2(0.0);
uniform float openness = 1.0;
uniform float glyph_scale = 1.0;
void fragment() {
	vec2 local = UV;
	local = (local-0.5)/glyph_scale+0.5;
	local.y = (local.y-0.5)/max(openness,0.05)+0.5;
	vec4 paint = texture(mouth_atlas,tile_origin+local*0.25);
	float bounds = step(0.001,local.x)*step(local.x,0.999)*step(0.001,local.y)*step(local.y,0.999);
	float dark = smoothstep(0.03,0.3,dot(paint.rgb,vec3(0.333)));
	ALBEDO = mix(vec3(0.105,0.08,0.07),paint.rgb,dark);
	ALPHA = paint.a*bounds;
}
