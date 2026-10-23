shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/ocean_waves.gdshaderinc"
uniform float phase = 0.0;
uniform float opacity = 0.84;

// Tapered, scalloped brush strokes: open arcs with dynamic outward pulse.
float stroke(vec2 p, float radius, float center, float span, float width) {
	float angle = atan(p.y, p.x);
	float a = atan(sin(angle - center), cos(angle - center));
	float taper = sqrt(max(0.0, 1.0 - pow(a / span, 2.0)));
	float contour = radius + 0.018 * sin(angle * 3.0 + phase + u_time * 0.7)
		+ 0.010 * cos(angle * 5.0 - u_time * 0.55);
	float d = abs(length(p) - contour) - width * taper;
	float aa = max(fwidth(d), 0.003);
	return (1.0 - smoothstep(-aa, aa, d)) * (1.0 - smoothstep(span - 0.05, span, abs(a)));
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += ocean_sample(world.xz).x + 0.045;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y *= 1.06;
	float breath = sin(u_time * 1.35 + phase);
	float turn = phase + u_time * 0.24 + sin(u_time * 0.45 + phase) * 0.16;

	// Inner primary double-arc ring
	float r1 = 0.54 + breath * 0.022;
	float paint = stroke(p, r1, turn + 0.15, 1.15, 0.025);
	paint = max(paint, stroke(p, r1 + 0.022, turn + 3.25, 0.92, 0.021));

	// Middle concentric arc ring
	float r2 = 0.72 - breath * 0.018;
	float mid = stroke(p, r2, turn + 1.65, 0.98, 0.018) * 0.78;
	mid = max(mid, stroke(p, r2 + 0.02, turn - 1.40, 0.76, 0.015) * 0.72);

	// Expanding outer pulse ring
	float pulse_age = fract(u_time * 0.32 + phase * 0.159);
	float r_pulse = 0.56 + pulse_age * 0.36;
	float pulse_life = smoothstep(0.05, 0.25, pulse_age) * (1.0 - smoothstep(0.55, 0.96, pulse_age));
	float pulse = stroke(p, r_pulse, turn + pulse_age * 1.4, 1.25, 0.016 * (1.0 - pulse_age * 0.35)) * pulse_life * 0.65;

	ALBEDO = vec3(0.88, 0.98, 0.97);
	ALPHA = max(paint, max(mid, pulse)) * opacity * (0.90 + 0.10 * breath);
}
