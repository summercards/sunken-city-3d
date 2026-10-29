// Shoreline geometry, open-water crests and the thin-object contact fallback.
//
// The object waterline itself is NOT painted here any more: it comes from
// contact_foam.gdshaderinc (ported from the production stylized-water package),
// which owns the whole "water meets solid" band. What stays in this file is
// everything that is not that band:
//   shoreline_data / shore_height  the geometric contour and its ripples
//   contact_edge                   a whisper of depth-based rim for solids the
//                                  contour atlas rejects (thin railings, cables)
//   crest_foam                     rare white paint on swell tops
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform vec4 shore_bounds;
uniform float shore_texel = 0.0009765625;
uniform bool shore_enabled = false;
// Bounded runtime solids, supplied by scene projection after build/restore.
// These reuse the same contact foam as the static atlas without a full rebake.
#include "res://shaders/runtime_water_contacts.gdshaderinc"
uniform float crest_foam_strength : hint_range(0.0, 1.5) = 0.0;
uniform vec3 foam_color : source_color = vec3(0.91, 0.98, 0.94);
// Water column that still counts as "touching something" for the depth edge.
uniform float contact_depth : hint_range(0.0, 4.0, 0.01) = 0.85;
uniform float edge_strength : hint_range(0.0, 1.5, 0.01) = 0.45;

vec2 shoreline_data(vec2 p) {
	vec2 uv = (p - shore_bounds.xy) / max(shore_bounds.zw, vec2(1.0));
	vec2 result = vec2(100.0, 1.0);
	if (shore_enabled && all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		result = textureLod(shore_distance, uv * (1.0 - shore_texel) + shore_texel * 0.5, 0.0).rg;
	}
	return with_runtime_contacts(p, result);
}

float shoreline_distance(vec2 p) { return shoreline_data(p).x; }

// Small outward wave packets share exactly the contour and clock of the foam.
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

// Stylized foam brightness modulation for the boat wake.
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

// Smooth, lively hand-drawn silhouette that breathes gently with the waves.
float cartoon_ribbon(vec2 p, float distance_to_edge, float width) {
	vec2 flow = p * 0.92 + vec2(u_time * 0.22, -u_time * 0.16);
	float lobes = 0.84 + 0.11 * sin(flow.x * 2.2 + sin(flow.y * 1.4 + u_time * 0.45))
		+ 0.07 * cos(flow.y * 2.9 - flow.x * 1.1 + u_time * 0.35);
	float edge = distance_to_edge - width * lobes;
	float aa = clamp(fwidth(edge), 0.012, max(width * 0.35, 0.014));
	return 1.0 - smoothstep(-aa, aa, edge);
}

// Depth-based contact fallback. The contour atlas deliberately ignores solids
// thinner than 0.22 m, so a railing or a cable would otherwise meet the water
// with no mark at all. This stays a faint inner glow; the real waterline is the
// contact foam band.
float contact_edge(vec2 p, float thickness, float view_dist) {
	float inner = cartoon_ribbon(p, thickness, contact_depth * 0.22);
	float fade = 1.0 - smoothstep(55.0, 130.0, view_dist);
	return inner * edge_strength * fade;
}

// Crest lightening, not whitecaps. At this scale a hard-cut whitecap is two
// metres of white paint on screen, so this stays a rare, soft veil on swell
// tops; the crisp whites belong to the contact band.
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
