// 无光照材质（网页版 MeshBasicMaterial：泡沫线、白浪、发光小物）。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;

void vertex() {
}

void fragment() {
	vec4 base = COLOR;
	if (use_texture) {
		base *= texture(albedo_tex, UV);
	}
	ALBEDO = base.rgb;
}
