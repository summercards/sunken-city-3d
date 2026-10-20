shader_type spatial;
// 水下光柱：加色混合的竖直薄片，横截面用 sin 做柔和边缘（避免硬边圆锥）。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

void fragment() {
	float edge = pow(max(0.0, sin(UV.x * 3.14159)), 3.0);
	float end = smoothstep(0.0, 0.35, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	float flow = 0.75 + 0.25 * sin(UV.y * 16.0 + TIME * 0.45);
	ALBEDO = vec3(0.58, 0.88, 0.74);
	ALPHA = edge * end * flow * 0.045;
}
