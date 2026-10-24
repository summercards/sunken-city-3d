shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/ocean_waves.gdshaderinc"
uniform float phase = 0.0;
uniform float opacity = 0.56;

// Clean, smooth circular ring (with a gentle water-wave breathe so it feels organic)
float smooth_ring(vec2 p, float radius, float half_width) {
	float angle = atan(p.y, p.x);
	float wobble = 0.008 * sin(angle * 2.0 + phase + u_time * 0.9)
		+ 0.004 * cos(angle * 3.0 - u_time * 0.7);
	float d = abs(length(p) - (radius + wobble)) - half_width;
	float aa = max(fwidth(d), 0.004);
	return 1.0 - smoothstep(-aa, aa, d);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += ocean_sample(world.xz).x + 0.042;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y *= 1.05;
	float breath = sin(u_time * 1.35 + phase);

	// Base concentric pair (matching web fish-schools.js inner + outer rings)
	float r_in = 0.55 + breath * 0.016;
	float r_out = 0.72 - breath * 0.014;
	float inner_ring = smooth_ring(p, r_in, 0.017) * (0.64 + 0.14 * breath);
	float outer_ring = smooth_ring(p, r_out, 0.013) * (0.42 - 0.10 * breath);
	float base_rings = max(inner_ring, outer_ring);

	// Gently expanding translucent concentric waves (two staggered phases)
	float expand = 0.0;
	for (int i = 0; i < 2; i++) {
		float age = fract(u_time * 0.24 + phase * 0.159 + float(i) * 0.5);
		float r_wave = mix(0.46, 0.95, age);
		float w_wave = mix(0.016, 0.009, age);
		float env = smoothstep(0.0, 0.18, age) * pow(1.0 - age, 1.35);
		expand = max(expand, smooth_ring(p, r_wave, w_wave) * env * 0.58);
	}

	ALBEDO = vec3(0.76, 0.98, 0.95);
	ALPHA = max(base_rings, expand) * opacity;
}
