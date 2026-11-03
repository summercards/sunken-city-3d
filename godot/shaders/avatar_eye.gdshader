shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D eye_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 tile_origin = vec2(0.0);
uniform float openness = 1.0;
uniform float side = 1.0;
uniform vec2 gaze = vec2(0.0);
uniform vec4 ink_color : source_color = vec4(0.10,0.08,0.07,1.0);
void fragment() {
	vec2 local = UV;
	if (side > 0.0) local.x = 1.0-local.x;
	local -= gaze;
	float aperture = max(openness, 0.025);
	local.y = (local.y-0.5)/aperture+0.5;
	vec4 paint = texture(eye_atlas, tile_origin+local*vec2(0.25,1.0/3.0));
	float bounds = step(0.001,local.x)*step(local.x,0.999)*step(0.001,local.y)*step(local.y,0.999);
	vec3 rgb = mix(ink_color.rgb, paint.rgb, smoothstep(0.08,0.55,dot(paint.rgb,vec3(0.333))));
	float alpha = paint.a*bounds;
	if (openness < 0.12) {
		float x = (UV.x-0.5)*2.0;
		float curve = 0.53-0.12*(1.0-x*x);
		alpha = (1.0-smoothstep(0.025,0.045,abs(UV.y-curve)))*(1.0-smoothstep(0.34,0.42,abs(UV.x-0.5)));
		rgb = ink_color.rgb;
	}
	ALBEDO = rgb;
	ALPHA = alpha;
}
