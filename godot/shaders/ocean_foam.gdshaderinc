// Geometric shoreline distance; no manually placed foam meshes or rectangle masks.
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform vec4 shore_bounds;
uniform float shore_texel = 0.0009765625;
uniform bool shore_enabled = false;
uniform float shore_foam_strength : hint_range(0.0, 1.5) = 1.0;
uniform float crest_foam_strength : hint_range(0.0, 1.5) = 0.0;
uniform vec3 foam_color : source_color = vec3(0.91, 0.98, 0.94);
// Stylized contact rim: one crisp white line along every waterline, produced by
// hard-cutting the water-column gradient instead of softening it.
// `edge_thickness` is the metric width of the painted ribbon (metres), which the
// contour atlas can resolve; `contact_depth` is the water column that still
// counts as "touching something" for the depth-based edge.
uniform float edge_thickness : hint_range(0.0, 3.0, 0.01) = 0.5;
uniform float contact_depth : hint_range(0.0, 4.0, 0.01) = 0.9;
uniform float edge_strength : hint_range(0.0, 1.5, 0.01) = 0.94;
uniform float edge_noise_scale : hint_range(0.2, 12.0, 0.1) = 5.5;

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
		height += cos(ridge * 9.0) * exp(-ridge * ridge * 9.0) * life * 0.032 * size;
	}
	return height;
}

// Stylized foam is a few broad patches of paint, not fine spray or a hairline.
// This only MODULATES brightness by a low-frequency value; the shape comes from
// the smooth phase bands, so patches keep one clean silhouette.
float foam_grain(vec2 p, float age) {
	vec2 flow = p * 3.2 + vec2(-0.10, 0.07) * u_time;
	float grain = noise(flow + noise(p * 1.05) * 1.6);
	float resolved = 1.0 - smoothstep(0.55, 1.8, length(fwidth(flow)));
	float patch = smoothstep(0.32 + age * 0.08, 0.62 + age * 0.08, grain);
	return mix(0.70, 0.34 + 0.66 * patch, resolved);
}

// Fine, torn grain used by the painted bands. Two scales multiplied instead of
// added: adding two value noises concentrates the result around 0.5 and the band
// comes out as a grey smear, multiplying keeps the dark tails that let the steep
// ramp below actually tear the edge.
float edge_grain(vec2 p) {
	float a = noise(p * 1.0 + vec2(3.1, -1.7));
	float b = noise(p * 2.63 + vec2(-7.4, 5.2));
	return clamp(a * (0.45 + 0.55 * b) * 1.55, 0.0, 1.0);
}

// The reference's `edge_ramp`: a 1D ramp that goes white -> black over the first
// 0.08 of its range, sampled at `noise * (1 - edge_t)` and then normalised.
// That single trick is what makes the foam edges read as painted, torn shapes:
// near an object (edge_t -> 1) the sample sits at 0 and the band is solid white,
// further out the noise pushes past the threshold and cuts the band into pieces.
//
// The cut sits at 0.19 rather than the reference's 0.08 because the reference
// uses a cellular texture, whose values cluster low; value noise centres on 0.5,
// so 0.08 would only ever paint a thin dotted line instead of a readable rim.
float torn_edge(float grain, float edge_t) {
	float cut = grain * (1.0 - clamp(edge_t, 0.0, 1.0));
	float aa = max(fwidth(cut), 0.006);
	return 1.0 - smoothstep(0.168 - aa, 0.180 + aa, cut);
}

// Same steep ramp expressed the other way round: everything above `threshold`
// becomes solid paint. Used where the shape should be a block, not a fringe.
float torn_shape(float value, float threshold) {
	float aa = max(fwidth(value), 0.006);
	return smoothstep(threshold - aa, threshold + aa, value);
}

// Contact rim driven by the water column under this pixel: full white right at a
// waterline, torn into chunks as the column deepens. The band edge is a near
// step, not a gradient, so it stays crisp at any camera tilt.
float contact_edge(vec2 p, float thickness, float view_dist) {
	// Squared falloff: a linear ramp starts tearing as soon as the column is a
	// third of `contact_depth`, which leaves a broken dotted line instead of a
	// solid rim. Squaring keeps the inner half of the band solid and confines
	// the torn fringe to its outer edge.
	float t = clamp(thickness / max(contact_depth, 0.01), 0.0, 1.0);
	float edge_t = 1.0 - t * t;
	float wobble = edge_grain(p * edge_noise_scale + vec2(u_time * 0.055, -u_time * 0.042));
	float rim = torn_edge(wobble, edge_t);
	// Without this the steep ramp keeps ~8% of the pixels white on the open sea,
	// where `edge_t` is zero and the grain alone crosses the threshold — that
	// reads as snow scattered over the water. The reference multiplies its edge
	// mask by `edge_blend` for exactly this reason.
	rim *= smoothstep(0.02, 0.22, edge_t);
	return clamp(rim * edge_strength * (1.0 - smoothstep(55.0, 130.0, view_dist)), 0.0, 1.0);
}

// The painted waterline. Driven by real metric distance to the contour so it
// hugs hulls, platforms and drowned walls even when the camera looks straight
// down, then cut by the same steep ramp so its outer edge tears instead of
// fading.
//
// `thickness` is the water column under this pixel. It only has to rule out the
// contour atlas' stray segments that lie in open water; the browser draws its
// outline from block footprints and ignores depth entirely, so a tight depth
// gate here leaves the rim patchy along one side of every platform.
float shore_rim(vec2 p, float thickness) {
	vec2 shore = shoreline_data(p);
	float d = shore.x;
	float bend = noise(p * 1.45 + vec2(u_time * 0.08, -u_time * 0.06));
	// Scale with the object, but only mildly: the contour atlas resolves ~0.13 m
	// per texel, so a width scaled down to 0.3 for small props collapses to less
	// than one texel and the ribbon disappears in the bilinear filter.
	float width = edge_thickness * clamp(shore.y, 0.55, 1.30) * (0.82 + 0.36 * bend);
	float t = clamp(d / max(width, 0.01), 0.0, 1.0);
	float edge_t = 1.0 - t * t;
	float grain = edge_grain(p * (edge_noise_scale * 0.9) + vec2(-u_time * 0.03, u_time * 0.021));
	float rim = torn_edge(grain, edge_t);
	// Fade out inside the last third of the band. `torn_edge` alone leaves ~8% of
	// the pixels white arbitrarily far out (the reference multiplies by
	// edge_blend for the same reason); this keeps the ribbon attached to the
	// waterline while its outer boundary stays broken by the grain.
	rim *= smoothstep(0.06, 0.30, edge_t);
	// Thin trims, mooring posts and handrails are real geometry in the atlas but
	// they are not shorelines; with the depth gate loosened they would paint white
	// sticks floating on open water. `shore.y` is the size of the entity that
	// seeded the contour, so a size gate separates 4 m platforms from 0.4 m rails.
	rim *= smoothstep(0.18, 0.45, shore.y);
	// No depth gate here on purpose. A platform standing in 10 m of water has no
	// shallow column beneath its edge, so any thickness test erases the rim from
	// exactly the side you look at. The browser draws its outline from footprint
	// distance alone for the same reason; the size gate above is what keeps stray
	// atlas segments out.
	float near_object = 1.0;
	return rim * edge_strength * near_object;
}

float shore_foam(vec2 p, float d) {
	float size = max(shoreline_data(p).y, 0.12);
	float bend = noise(p * 1.45 + vec2(u_time * 0.08, -u_time * 0.06));
	float fronts = 0.0;
	for (int i = 0; i < 2; i++) {
		// Two overlapping pulses. Soft Gaussian crests instead of hard contours:
		// a hard one-pixel ring reads as a scratch out on open water.
		float age = fract(u_time * 0.17 + float(i) * 0.5 + noise(p * 0.16) * 0.16);
		float radius = (0.12 + age * 1.60) * size;
		float warp = (bend - 0.5) * (0.10 + age * 0.26);
		float ridge = (d - radius + warp) / (0.10 + 0.16 * size);
		float life = smoothstep(0.02, 0.20, age) * (1.0 - smoothstep(0.35, 0.92, age));
		float breakup = smoothstep(age * 0.57, age * 0.57 + 0.21, noise(p * 0.9 + vec2(age * 1.2, -u_time * 0.06)));
		// Broad body plus a slightly tighter core, both fully soft-edged.
		float ring = exp(-ridge * ridge * 1.5) * 0.62 + exp(-ridge * ridge * 6.5) * 0.38;
		fronts += ring * life * breakup * 0.10;
	}
	return clamp(fronts * sqrt(size) * foam_grain(p, 0.25) * shore_foam_strength, 0.0, 1.0);
}

// Crest lightening, not whitecaps.
//
// At this project's scale (a harbour read from ~50 m up) a hard-cut whitecap is
// two metres of white paint on screen — a dozen of them per frame reads as paper
// scraps floating on the water. The reference's crisp white belongs to the
// waterline rim only (see `shore_rim` / `contact_edge`); open water there stays
// smooth. So this stays a soft, translucent veil on the swell tops: it adds
// body and a little brightness, and the crisp whites are reserved for edges.
//
// The gate is the COMPOSED surface height (`height`, metres, swell + chop), not
// the phase of one wave, so the veil always sits on the crests the eye sees.
float crest_foam(vec2 p, float shore_d, float view_dist, float height) {
	vec4 w = ocean_waves[0];
	vec2 direction = normalize(w.xy);
	float k = 6.2831853 / max(w.w, 0.01);
	vec2 advected = p - direction * sqrt(9.81 / k) * u_time;

	// Only the very top of a swell breaks. A loose gate here plus a hard cut
	// turns the whole open sea into slabs of white paint.
	float on_top = smoothstep(0.22, 0.34, height);
	// Break the crest into separate patches, sampled in crest-aligned
	// coordinates so they smear along the crest instead of beading.
	vec2 across = vec2(-direction.y, direction.x);
	vec2 local = vec2(dot(advected, direction) * 0.26, dot(advected, across) * 0.62);
	float patch = noise(local + vec2(u_time * 0.030, -u_time * 0.020));
	// Steep cut, not a gradient: the same painted-edge trick as the waterline,
	// so a crest is a hard white shape that drifts and dies instead of a soft
	// airbrushed haze (which read as photographic water at this scale). The
	// threshold is high because only rare crests should carry paint.
	float body = torn_shape(patch, 0.74 - 0.06 * on_top);
	// Slow thickness variation: a uniform value reads as a coat of paint.
	float grain = noise(advected * 0.55 + vec2(0.0, u_time * 0.025));

	float lod = 1.0 - smoothstep(70.0, 190.0, view_dist);
	return clamp(on_top * body * (0.72 + 0.28 * grain), 0.0, 1.0)
		* lod * smoothstep(0.35, 1.10, shore_d) * crest_foam_strength;
}
