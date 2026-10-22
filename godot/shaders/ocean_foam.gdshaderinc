// Geometric shoreline distance; no manually placed foam meshes or rectangle masks.
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform vec4 shore_bounds;
uniform float shore_texel = 0.0009765625;
uniform bool shore_enabled = false;
uniform float shore_foam_strength : hint_range(0.0, 1.5) = 1.0;
uniform float crest_foam_strength : hint_range(0.0, 1.5) = 0.72;
uniform vec3 foam_color : source_color = vec3(0.91, 0.98, 0.94);

vec2 shoreline_data(vec2 p) {
	vec2 uv = (p - shore_bounds.xy) / max(shore_bounds.zw, vec2(1.0));
	if (!shore_enabled || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec2(100.0, 1.0);
	return textureLod(shore_distance, uv * (1.0 - shore_texel) + shore_texel * 0.5, 0.0).rg;
}

float shoreline_distance(vec2 p) { return shoreline_data(p).x; }

// Small outward wave packets share exactly the contour and clock of the foam.
float shore_height(vec2 p) {
	vec2 shore = shoreline_data(p);
	float d = shore.x;
	float size = max(shore.y, 0.12);
	if (d > 3.0) return 0.0;
	float bend = noise(p * 1.45 + vec2(u_time * 0.08, -u_time * 0.06));
	float height = 0.0;
	for (int i = 0; i < 2; i++) {
		float age = fract(u_time * 0.19 + float(i) * 0.5 + noise(p * 0.16) * 0.16);
		float ridge = d - (0.10 + age * 2.65) * size + (bend - 0.5) * (0.12 + age * 0.28);
		float life = smoothstep(0.02, 0.16, age) * (1.0 - smoothstep(0.45, 0.98, age));
		height += cos(ridge * 9.0) * exp(-ridge * ridge * 9.0) * life * 0.024 * size;
	}
	return height;
}

// Soft, connected film with small holes. Subpixel detail fades instead of sparkling.
float foam_grain(vec2 p, float age) {
	vec2 flow = p * 14.0 + vec2(-0.18, 0.12) * u_time;
	float grain = noise(flow + noise(p * 1.4) * 2.0);
	float resolved = 1.0 - smoothstep(0.5, 1.6, length(fwidth(flow)));
	return mix(0.78, 0.20 + 0.80 * smoothstep(0.15 + age * 0.12, 0.46 + age * 0.12, grain), resolved);
}

float shore_foam(vec2 p, float d) {
	float size = max(shoreline_data(p).y, 0.12);
	float aa = max(fwidth(d), 0.035);
	float bend = noise(p * 1.45 + vec2(u_time * 0.08, -u_time * 0.06));
	// A narrow breathing, scalloped waterline, always anchored to the geometry.
	float width = 0.065 + 0.055 * bend + 0.018 * sin(u_time * 1.8 + noise(p * 0.4) * 5.0);
	float contact = 1.0 - smoothstep(width - aa, width + aa, d);
	float fronts = 0.0;
	for (int i = 0; i < 2; i++) {
		// Two overlapping pulses. The front moves outwards and fades before reset.
		float age = fract(u_time * 0.19 + float(i) * 0.5 + noise(p * 0.16) * 0.16);
		float radius = (0.10 + age * 2.65) * size;
		float warp = (bend - 0.5) * (0.12 + age * 0.28);
		float ridge = d - radius + warp;
		float line_width = mix(0.065, 0.025, age);
		float front = 1.0 - smoothstep(line_width, line_width + aa, abs(ridge));
		float life = smoothstep(0.02, 0.16, age) * (1.0 - smoothstep(0.45, 0.98, age));
		float breakup = smoothstep(age * 0.57, age * 0.57 + 0.19, noise(p * 0.9 + vec2(age * 1.2, -u_time * 0.06)));
		// Thin translucent wash behind the leading edge.
		float wash = exp(-ridge * ridge * 15.0) * 0.13;
		fronts += (front + wash) * life * breakup * 0.55;
	}
	return clamp((contact * 0.72 + fronts * sqrt(size)) * foam_grain(p, 0.25) * shore_foam_strength, 0.0, 1.0);
}

float crest_foam(vec2 p, float shore_d) {
	// Same bent phase as the main displaced wave, so the white crest travels WITH it.
	vec4 w = ocean_waves[0];
	vec2 direction = normalize(w.xy);
	vec2 across = vec2(-direction.y, direction.x);
	float k = 6.2831853 / max(w.w, 0.01);
	float cross_phase = k * 0.61 * dot(across, p) - u_time * 0.19;
	float phase = k * dot(direction, p) - sqrt(9.81 * k) * u_time
		+ 0.85 * sin(cross_phase * 0.83 + 0.7);
	float crest = mod(phase - 1.27 + 3.14159265, 6.2831853) - 3.14159265;
	vec2 advected = p - direction * sqrt(9.81 / k) * u_time;
	float patch = noise(p * 0.22 + vec2(u_time * 0.055, -u_time * 0.035));
	float event = smoothstep(0.56, 0.74, patch) * smoothstep(-0.2, 0.6, sin(cross_phase));
	float fray = noise(advected * 1.6 + vec2(0.0, u_time * 0.17));
	float ridge = crest + (fray - 0.5) * 0.045;
	float aa = clamp(fwidth(crest), 0.008, 0.08);
	float lip = 1.0 - smoothstep(0.018, 0.035 + aa, abs(ridge));
	float wash = (1.0 - smoothstep(0.04, 0.26, -ridge)) * smoothstep(-0.01, 0.035, -ridge) * 0.24;
	return (lip + wash) * event * foam_grain(advected, 0.6)
		* smoothstep(2.0, 4.0, shore_d) * crest_foam_strength * wave_scale;
}
