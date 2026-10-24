// Object-contact foam — the "water meets solid" layer.
//
// Ported from the production package `stylized_water_prod`
// (demos/stylized_water_prod/): only its ContactFoam subsystem. Everything the
// package does for the open sheet (depth transmission, sky cubemap reflection,
// sun lobe, ripple network) is deliberately NOT taken over — this project's
// water is already its own painterly composite.
//
// The package bakes a fixed water-level signed distance field offline from a
// hand-picked obstacle selection (tools/contact_baker.gd, GPU compute). This
// project already derives the same kind of field on every startup:
// rendering/shore_distance.gd rasterises the water-level cross-section of all
// visible geometry into an RG atlas (R = metres to the waterline, G = per-solid
// scale). So the foam layer reads that atlas and no second bake step, editor
// tool, or extra texture memory is needed.
//
// Reference frame, as in the package:
//   d        metres from the waterline along world XZ
//   width    outer travel range of the foam in metres
//   v        d / width — 0 at the contact, 1 at the outer reach
//   age      0..1 lifecycle: birth, hold, retreat, then an optional wait
//
// Two art modes, chosen by whether `contact_foam_pattern` is assigned:
//   procedural  one expanding, breaking ring
//   texture     a hand-painted grayscale strip (V runs contact -> outward),
//               eroded by growing the sampling footprint as the lifecycle ages
//
// ONE DELIBERATE DIVERGENCE. The package draws its crisp waterline *inside* the
// strip (a solid ribbon in the first 5% of V) and its field is 0.08 m/cell. Our
// contour atlas is 0.133 m/cell, so that ribbon would land inside the first
// texel and bilateral filtering would erase it — measured: the whole band
// vanished. The line is therefore drawn metrically (`contact_rim`, in metres of
// real distance) and the strip only supplies the mid/outer eroded blobs. The
// strip's own sub-texel ribbon happens to sit at the same place, so together
// they read as one band.
//
// The package's contact field is also signed (negative inside a solid) so it can
// reject the interior of a wall. Our atlas is unsigned, which is equivalent
// here: the solid itself occludes the water surface above the waterline, so only
// the exterior band is ever visible.

uniform vec4 contact_foam_color : source_color = vec4(0.93, 0.99, 0.97, 1.0);
// Metric width of the crisp line hugging the solid. Must exceed the atlas texel
// (0.133 m) or it cannot survive interpolation.
uniform float contact_foam_rim_width : hint_range(0.0, 0.6, 0.005) = 0.17;
// Outer travel range of the eroded blobs, in metres.
uniform float contact_foam_width : hint_range(0.0, 3.0, 0.01) = 1.90;
uniform float contact_foam_strength : hint_range(0.0, 1.5, 0.01) = 1.0;
uniform float contact_foam_animation_speed : hint_range(0.0, 4.0, 0.01) = 1.0;
// Extra waiting after a complete lifecycle, in real seconds at nonzero speed.
uniform float contact_foam_interval_seconds : hint_range(0.0, 4.0, 0.1) = 0.5;
// Grayscale strip: U repeats, V runs from contact to the outer boundary.
// Blank (1x1) falls back to the procedural ring.
uniform sampler2D contact_foam_pattern : hint_default_black, repeat_enable, filter_linear_mipmap;
uniform float contact_foam_repeat_metres : hint_range(1.0, 15.0, 0.1) = 5.0;

// Three world-space carriers, same basis as the package so the two can be
// compared side by side without the foam shifting position.
vec3 contact_phases(vec2 p) {
	return vec3(dot(p, vec2(2.7, 1.9)), dot(p, vec2(0.71, 0.39)), dot(p, vec2(-0.23, 1.13)));
}

// Self-contained value noise: this include must not depend on the host shader
// having declared a `noise` helper first.
float contact_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float contact_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(contact_hash(i), contact_hash(i + vec2(1.0, 0.0)), f.x),
		mix(contact_hash(i + vec2(0.0, 1.0)), contact_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The crisp hand-painted waterline. Metric, so it holds up against a coarse
// contour atlas: our field is 0.133 m/texel, so the band has to be several
// decimetres wide before interpolation can hold it. The wobble is applied in
// metres too — a sub-texel wobble would vanish into the field's own rounding.
float contact_rim(vec2 p, float d, float t) {
	if (contact_foam_rim_width <= 0.0) return 0.0;
	vec3 ph = contact_phases(p);
	// Two slow carriers widen and thin the band, one medium one roughens it.
	float width = contact_foam_rim_width
		* (0.82 + 0.20 * sin(ph.x * 0.55 + t * 0.55) + 0.13 * sin(ph.z * 1.17 - t * 0.35));
	width += (contact_noise(p * 1.35 + vec2(t * 0.05, 0.0)) - 0.5) * 0.15;
	width += (contact_noise(p * 3.10 - vec2(0.0, t * 0.07)) - 0.5) * 0.06;
	float edge = d - width;
	float aa = max(fwidth(edge), 0.006);
	return 1.0 - smoothstep(-aa, aa, edge);
}

// Expanding ring that breaks into open arcs. `v` is normalized distance.
float contact_ring(vec2 p, float v, float aa, float t) {
	vec3 ph = contact_phases(p);
	float phase = sin(ph.y) * 0.19 + sin(ph.z) * 0.11;
	float travel = fract(t * 0.28 + phase);
	float centre = 0.18 + travel * 0.95;
	float width = 0.045 * (1.0 - travel);
	float ring = (1.0 - smoothstep(width, width + aa, abs(v - centre)))
		* (smoothstep(0.0, 0.1, travel) - smoothstep(0.65, 1.0, travel));
	// A travelling triangle replaces a fourth sine: its extremes and its wrap
	// land in the flat part of the threshold, so the ring reads as open arcs
	// instead of a closed target ring.
	float break_phase = sin(ph.y) * 0.55 - sin(ph.z) * 0.35 + t * (0.3 / TAU);
	float break_wave = 1.0 - 4.0 * abs(fract(break_phase) - 0.5);
	float breaks = smoothstep(-0.4, 0.15, break_wave);
	return ring * breaks;
}

float contact_foam_procedural(vec2 p, float d, float width, float t) {
	float rim = contact_rim(p, d, t);
	float v = d / max(width, 0.001);
	float aa = max(fwidth(v) * 0.5, 0.002);
	// Bound at 1.2 plus the AA footprint; every derivative is evaluated above.
	if (v > 1.2 + aa) return rim;
	return max(rim, contact_ring(p, v, aa, t));
}

// Min-filtered five-tap lookup. Growing `radius` eats the strip's ink inward
// from every side, which turns the same painted strip into foam that visibly
// erodes instead of a texture that fades out.
float erode_contact_pattern(vec2 uv, float radius, vec2 uv_dx, vec2 uv_dy) {
	vec2 image_size = vec2(textureSize(contact_foam_pattern, 0));
	vec2 r = vec2(radius * image_size.y / image_size.x, radius);
	float inset = 0.5 / image_size.y;
	uv.y = clamp(uv.y, inset, 1.0 - inset);
	float ink = textureGrad(contact_foam_pattern, uv, uv_dx, uv_dy).r;
	ink = min(ink, textureGrad(contact_foam_pattern, uv + vec2(r.x, 0.0), uv_dx, uv_dy).r);
	ink = min(ink, textureGrad(contact_foam_pattern, uv - vec2(r.x, 0.0), uv_dx, uv_dy).r);
	ink = min(ink, textureGrad(contact_foam_pattern,
		vec2(uv.x, clamp(uv.y + r.y, inset, 1.0 - inset)), uv_dx, uv_dy).r);
	ink = min(ink, textureGrad(contact_foam_pattern,
		vec2(uv.x, clamp(uv.y - r.y, inset, 1.0 - inset)), uv_dx, uv_dy).r);
	return ink;
}

float contact_foam_texture(vec2 p, float d, float width, float t) {
	float rim = contact_rim(p, d, t);
	float v = d / max(width, 0.001);
	float aa = max(fwidth(v) * 0.5, 0.002);

	// Break the field's own quantization contours so the strip is read as paint
	// and not as a stack of offset bands.
	float v_paint = v + (contact_noise(p * 0.95 + vec2(0.0, t * 0.04)) - 0.5) * 0.20;

	// Continuous world projection along the package's diagonal (0.73, 0.68) so
	// the strip repeats along the waterline without a baked contour coordinate.
	// Orientation-dependent stretching is the package's known limitation too.
	float u = dot(p, vec2(0.73, 0.68)) / max(contact_foam_repeat_metres, 0.1);
	float local_phase = sin(dot(p, vec2(0.71, 0.39))) * 0.17
		+ sin(dot(p, vec2(-0.23, 1.13))) * 0.11;

	float wait_units = max(contact_foam_interval_seconds, 0.0) * 0.16 * contact_foam_animation_speed;
	float schedule = mod(t * 0.16 + local_phase * 0.71, 0.71 + wait_units);
	float waiting = step(0.71, schedule);
	float active = min(schedule, 0.71);

	// Birth is quick, the hold is long, the retreat spends the rest; the phase
	// derivative is analytic so the erosion keeps mip filtering without
	// treating the cycle reset as a texture footprint.
	float age;
	float age_derivative;
	if (active < 0.08) {
		age = active * 2.0;
		age_derivative = 1.42;
	} else if (active < 0.50) {
		age = 0.16 + active - 0.08;
		age_derivative = 0.71;
	} else {
		age = 0.58 + (active - 0.50) * 2.0;
		age_derivative = 1.42;
	}
	age_derivative *= 1.0 - waiting;

	float birth = smoothstep(0.0, 0.18, age);
	float retreat = smoothstep(0.40, 0.94, age);
	// The whole painted shape grows away from the anchored contact origin.
	float expansion = mix(0.42, 1.30, smoothstep(0.0, 1.0, age));
	float source_v = max(v_paint, 0.0) / expansion;
	float attachment = smoothstep(0.0, 0.25, max(v, 0.0));
	float lateral = 0.035 * sin(t * 0.35 + local_phase * TAU) * attachment;
	vec2 uv = vec2(u + lateral, clamp(source_v, 0.0, 1.0));

	float expansion_derivative = 0.88 * 6.0 * age * (1.0 - age);
	vec2 uv_dx = vec2(dFdx(u + lateral),
		dFdx(v_paint) / expansion - max(v_paint, 0.0) * expansion_derivative * age_derivative
			* dFdx(local_phase) / (expansion * expansion));
	vec2 uv_dy = vec2(dFdy(u + lateral),
		dFdy(v_paint) / expansion - max(v_paint, 0.0) * expansion_derivative * age_derivative
			* dFdy(local_phase) / (expansion * expansion));

	// Erode near the contact too: a non-eroding base reads as a decal.
	float root_retreat = smoothstep(0.30, 0.85, age) * (1.0 - smoothstep(0.08, 0.30, source_v));
	float radius = 0.030 * (1.0 - birth) + 0.023 * retreat + 0.070 * root_retreat;
	float life = birth * (1.0 - smoothstep(0.84, 1.0, age));
	// Only U repeats. Sampling V=1 with the repeating sampler wraps into the
	// white contact ribbon, so reject the evolved strip's out-of-bounds tail.
	float support = 1.0 - smoothstep(0.94, 1.0, source_v);
	// Start the mid-field fade later than the package (0.15) because our band is
	// physically wider than the 0.08 m demo field; 0.15 would clip the blobs.
	float outer_fade = 1.0 - smoothstep(0.10, 0.74, v);

	// Every derivative has been evaluated above; reject only exact zeros so the
	// antialiased fade survives.
	if (support == 0.0 || waiting == 1.0) return rim;
	float blobs = support * (1.0 - waiting) * life * outer_fade;
	if (blobs == 0.0) return rim;
	return max(rim, blobs * erode_contact_pattern(uv, radius, uv_dx, uv_dy));
}

// `t` is the material clock (u_time). The texture mode scales it by
// `contact_foam_animation_speed`; the procedural ring runs on raw time, as in
// the package. `width` is in metres and already carries the per-solid scale.
float sample_contact_foam(vec2 p, float d, float width, float t) {
	ivec2 art = textureSize(contact_foam_pattern, 0);
	if (art.x <= 4 || art.y <= 4) {
		return contact_foam_procedural(p, d, width, t);
	}
	return contact_foam_texture(p, d, width, t * contact_foam_animation_speed);
}
