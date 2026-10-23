// Geometric shoreline distance; no manually placed foam meshes or rectangle masks.
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform vec4 shore_bounds;
uniform float shore_texel = 0.0009765625;
uniform bool shore_enabled = false;
uniform float shore_foam_strength : hint_range(0.0, 1.5) = 1.0;
uniform float crest_foam_strength : hint_range(0.0, 1.5) = 0.0;
uniform vec3 foam_color : source_color = vec3(0.91, 0.98, 0.94);
// Stylized contact rim: crisp, rounded hand-painted waterline and concentric
// cartoon wave arcs along every structure and pillar.
uniform float edge_thickness : hint_range(0.0, 3.0, 0.01) = 0.22;
uniform float contact_depth : hint_range(0.0, 4.0, 0.01) = 0.85;
uniform float edge_strength : hint_range(0.0, 1.5, 0.01) = 0.82;
uniform float edge_noise_scale : hint_range(0.2, 12.0, 0.1) = 3.2;

vec2 shoreline_data(vec2 p) {
	vec2 uv = (p - shore_bounds.xy) / max(shore_bounds.zw, vec2(1.0));
	if (!shore_enabled || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec2(100.0, 1.0);
	return textureLod(shore_distance, uv * (1.0 - shore_texel) + shore_texel * 0.5, 0.0).rg;
}

float shoreline_distance(vec2 p) { return shoreline_data(p).x; }

// Small outward wave packets share the contour and clock of the foam.
float shore_height(vec2 p) {
	vec2 shore = shoreline_data(p);
	float d = shore.x;
	float size = max(shore.y, 0.12);
	if (d > 3.2) return 0.0;
	float bend = noise(p * 1.15 + vec2(u_time * 0.08, -u_time * 0.06));
	float height = 0.0;
	for (int i = 0; i < 2; i++) {
		float age = fract(u_time * 0.18 + float(i) * 0.5 + noise(p * 0.14) * 0.14);
		float ridge = d - (0.12 + age * 2.45) * size + (bend - 0.5) * (0.10 + age * 0.24);
		float life = smoothstep(0.02, 0.18, age) * (1.0 - smoothstep(0.45, 0.98, age));
		height += cos(ridge * 8.5) * exp(-ridge * ridge * 9.0) * life * 0.026 * size;
	}
	return height;
}

// Stylized foam brightness modulation for boat wake and surf.
float foam_grain(vec2 p, float age) {
	vec2 flow = p * 2.6 + vec2(-0.09, 0.06) * u_time;
	float grain = noise(flow + noise(p * 0.95) * 1.4);
	float resolved = 1.0 - smoothstep(0.55, 1.8, length(fwidth(flow)));
	float patch = smoothstep(0.30 + age * 0.08, 0.62 + age * 0.08, grain);
	return mix(0.74, 0.42 + 0.58 * patch, resolved);
}

float torn_shape(float value, float threshold) {
	float aa = max(fwidth(value), 0.006);
	return smoothstep(threshold - aa, threshold + aa, value);
}

// Smooth, lively hand-drawn waterline silhouette that breathes gently with waves.
float cartoon_ribbon(vec2 p, float distance_to_edge, float width) {
	vec2 flow = p * 0.92 + vec2(u_time * 0.22, -u_time * 0.16);
	float lobes = 0.84 + 0.11 * sin(flow.x * 2.2 + sin(flow.y * 1.4 + u_time * 0.45))
		+ 0.07 * cos(flow.y * 2.9 - flow.x * 1.1 + u_time * 0.35);
	float edge = distance_to_edge - width * lobes;
	float aa = clamp(fwidth(edge), 0.012, max(width * 0.35, 0.014));
	return 1.0 - smoothstep(-aa, aa, edge);
}

// Tapered cartoon arc stroke along an iso-distance contour around structures.
float shore_arc_band(vec2 p, float d, float target_d, float half_w, float phase_offset, float freq) {
	float wave1 = sin(p.x * freq + p.y * (freq * 0.82) + u_time * 1.35 + phase_offset);
	float wave2 = cos(p.y * (freq * 1.15) - p.x * (freq * 0.68) - u_time * 0.95 + phase_offset * 1.7);
	float arch_t = 0.5 + 0.5 * (wave1 * 0.62 + wave2 * 0.38);
	// Tapered ends: open arc segments with clean gaps, thicker in the middle
	float mask = smoothstep(0.28, 0.56, arch_t);
	float wobble = sin(p.x * 1.55 - p.y * 1.35 + u_time * 1.1 + phase_offset) * 0.045;
	float w = half_w * (0.45 + 0.70 * mask);
	float dist = abs(d - (target_d + wobble)) - w;
	float aa = clamp(fwidth(d), 0.014, 0.055);
	float stroke = 1.0 - smoothstep(-aa, aa, dist);
	return stroke * mask;
}

float contact_edge(vec2 p, float thickness, float view_dist) {
	// Screen-depth contact line at the immediate intersection of objects and water
	float inner = cartoon_ribbon(p, thickness, contact_depth * 0.22);
	// Secondary subtle depth-hug arc for thin pillars and docks
	float sub_wave = smoothstep(0.32, 0.68, 0.5 + 0.5 * sin(p.x * 1.7 - p.y * 1.5 + u_time * 1.5));
	float sub_dist = abs(thickness - contact_depth * 0.52) - 0.045 * sub_wave;
	float sub_aa = clamp(fwidth(thickness), 0.015, 0.06);
	float sub_line = (1.0 - smoothstep(-sub_aa, sub_aa, sub_dist)) * sub_wave * 0.52;
	float fade = 1.0 - smoothstep(55.0, 130.0, view_dist);
	return max(inner * 0.86, sub_line) * edge_strength * fade;
}

float shore_rim(vec2 p, float thickness) {
	vec2 shore = shoreline_data(p);
	float d = shore.x;
	float scale = clamp(shore.y, 0.48, 1.25);
	float gate = smoothstep(0.14, 0.40, shore.y);
	// 1. Primary waterline hugging the building/pillar contour
	float width = edge_thickness * scale * 0.78;
	float primary = cartoon_ribbon(p, d, width) * 0.90;
	// 2. First concentric cartoon wave arc (double-ring look from reference)
	float ring1_d = width + (0.26 + 0.04 * sin(u_time * 1.25 + p.x * 0.4 + p.y * 0.4)) * scale;
	float ring1 = shore_arc_band(p, d, ring1_d, 0.040 * scale, 0.0, 1.15) * 0.78;
	// 3. Second outer delicate ripple arc
	float ring2_d = ring1_d + (0.34 + 0.05 * cos(u_time * 1.05 - p.y * 0.35)) * scale;
	float ring2 = shore_arc_band(p, d, ring2_d, 0.028 * scale, 2.3, 0.88) * 0.48;
	return max(primary, max(ring1, ring2)) * edge_strength * gate;
}

// Dynamic outward-propagating stylized wave rings around structures.
float shore_foam(vec2 p, float d) {
	vec2 shore = shoreline_data(p);
	float size = clamp(shore.y, 0.35, 1.20);
	if (d > 4.2 || shore.y < 0.14) return 0.0;
	float bend = sin(p.x * 0.95 + p.y * 0.75 + u_time * 0.55) * 0.5
		+ cos(p.y * 1.25 - p.x * 0.85 - u_time * 0.45) * 0.5;
	float arcs = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float phase_seed = sin(p.x * 0.18 + p.y * 0.14 + fi * 1.7) * 0.10;
		float age = fract(u_time * 0.20 + fi * 0.3333 + phase_seed);
		// Propagate outward from just outside the primary rim
		float radius = (0.24 + age * 1.95) * size;
		float warp = bend * (0.06 + age * 0.14);
		// Break each expanding ring into graceful open arcs with tapered tips
		float angle_wave = sin(p.x * (0.85 + fi * 0.22) + p.y * (0.72 - fi * 0.18) + fi * 2.1 + u_time * 0.65) * 0.6
			+ cos(p.y * (1.05 - fi * 0.15) - p.x * (0.65 + fi * 0.20) - u_time * 0.48) * 0.4;
		float arc_mask = smoothstep(0.08 + age * 0.22, 0.46 + age * 0.18, 0.5 + 0.5 * angle_wave);
		// Taper stroke thickness along the arc and as it expands
		float half_w = (0.044 * (1.0 - age * 0.42)) * (0.35 + 0.65 * arc_mask) * sqrt(size);
		float dist = abs(d - radius + warp) - half_w;
		float aa = clamp(fwidth(d), 0.015, 0.055);
		float stroke = 1.0 - smoothstep(-aa, aa, dist);
		// Smooth fade-in at birth and fade-out at outer reach
		float life = smoothstep(0.04, 0.20, age) * (1.0 - smoothstep(0.55, 0.96, age));
		arcs = max(arcs, stroke * arc_mask * life * 0.86);
	}
	return clamp(arcs * shore_foam_strength, 0.0, 1.0);
}

// Subtle open-water cartoon wave glints (sparse curved strokes on swell crests).
float crest_foam(vec2 p, float shore_d, float view_dist, float height) {
	vec4 w = ocean_waves[0];
	vec2 direction = normalize(w.xy);
	float k = 6.2831853 / max(w.w, 0.01);
	vec2 advected = p - direction * sqrt(9.81 / k) * u_time * 0.35;

	float on_top = smoothstep(0.18, 0.32, height);
	vec2 across = vec2(-direction.y, direction.x);
	vec2 local = vec2(dot(advected, direction) * 0.32, dot(advected, across) * 0.72);
	float patch = noise(local + vec2(u_time * 0.04, -u_time * 0.03));
	float body = torn_shape(patch, 0.76 - 0.05 * on_top);
	float lod = 1.0 - smoothstep(65.0, 175.0, view_dist);
	return clamp(on_top * body * 0.65, 0.0, 1.0)
		* lod * smoothstep(0.8, 2.2, shore_d) * crest_foam_strength;
}
