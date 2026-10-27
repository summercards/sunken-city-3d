// Stylized ocean surface — rebuilt on the production water package's model.
//
// The previous version painted the sheet: a flat two-colour body, additive
// "facets of light" made by thresholding a low-frequency noise field, hard white
// foam. Those facets were textureless, so on a wide flat surface every threshold
// contour read as a panel seam — the pattern was the problem, not its edge
// softness, and two rounds of softening the contours could not remove it.
//
// This version keeps the painterly body but puts the surface detail where the
// package puts it, in texture space:
//
//   normal map        two scrolling samples of a tiling normal strip supply the
//                     high-frequency tilt the surface never had, so the eye has
//                     something finer than the swell to read as "water";
//   sky reflection    an analytic gradient built from this project's own sky
//                     colours (no cubemap asset), screen-blended by a steep
//                     fresnel so it only shows at grazing angles;
//   sun lobe          one filtered highlight; the pixel footprint from screen
//                     derivatives widens the lobe instead of aliasing it;
//   ripple strip      a signed-distance contour texture drives an ink-like
//                     network that thins, breaks and regrows on its own clock;
//   contact foam      unchanged: the existing atlas-driven waterline band.
//
// Project layers the package does not have are kept, because gameplay reads them:
// the shared wave field (`ocean_sample`, which the boat also samples for its
// draft), the boat wake, the oar rings, the shore contour, crest foam and the
// facility glints.
//
// Output still goes through EMISSION with a zero albedo. Do not move it into
// ALBEDO + `unshaded`: the gl_compatibility renderer behind the web export
// composites that combination as pure black. See `render_flags.gd`.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float water_level = 1.12;
uniform float u_reverse_z = 1.0;
uniform vec4 u_ripples[8];
uniform int u_ripple_count = 0;

#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/ocean_wake.gdshaderinc"

group_uniforms body;
// Authored in the same space as the browser build: a cyan with the red channel
// absorbed away. `source_color` converts these to linear on the way in.
uniform vec3 body_shallow : source_color = vec3(0.128, 0.618, 0.584);
uniform vec3 body_deep : source_color = vec3(0.070, 0.399, 0.549);
// Axial water column at which the deep colour reaches half strength.
uniform float depth_half_distance : hint_range(0.1, 14.0, 0.05) = 7.0;
// How much the shallow body brightens the bed it is seen through. 1 leaves the
// bed untinted; the package's 3 is a flood of colour and reads as milk here.
uniform float shallow_tint_strength : hint_range(0.0, 4.0, 0.05) = 1.3;
// Grazing-angle occlusion of the bed, 0 disables it.
uniform float view_occlusion_strength : hint_range(0.0, 0.5, 0.01) = 0.10;
// Per-metre absorption of the transmitted bed colour, so drowned geometry reads
// as teal before it disappears entirely.
uniform vec3 absorption = vec3(0.088, 0.036, 0.028);
uniform float refraction_strength : hint_range(0.0, 80.0, 0.5) = 22.0;
group_uniforms;

group_uniforms caustics;
// Sunlight that has already passed through the surface, landing on the seabed and
// on the drowned walls. Sampled at the submerged geometry's own world position, so
// the web of light belongs to the geometry and stays put while the water moves
// over it — painting it on the water plane instead would make it slide over the
// waterline and stick to the camera.
uniform bool caustics_enabled = true;
uniform vec3 caustics_color : source_color = vec3(0.55, 1.0, 0.92);
uniform float caustics_strength : hint_range(0.0, 1.0, 0.005) = 0.42;
// Cell size. Above 1 the cells get smaller and denser; it multiplies the whole
// pattern frequency, so 2 gives four times the cells.
uniform float caustics_scale : hint_range(0.2, 4.0, 0.01) = 1.0;
// How fast the pattern crawls. 0 freezes it, which is useful when tuning.
uniform float caustics_speed : hint_range(0.0, 3.0, 0.01) = 1.0;
// Weight of the second, finer octave. It breaks the single lattice up so the
// cells do not read as a printed grid; 0 leaves the bare sin*cos web.
uniform float caustics_detail : hint_range(0.0, 1.0, 0.01) = 0.35;
// Caustics fade in over the first quarter of this distance and are at full
// strength by it. Below the range nothing shows: that close to the surface the
// light has not had room to focus yet.
uniform float caustics_depth_near : hint_range(0.05, 4.0, 0.01) = 1.2;
// Fade-out distance. Past this the pattern is gone: it would alias into noise
// long before, and physically the light is too diffuse to focus that deep.
uniform float caustics_depth_far : hint_range(2.0, 40.0, 0.1) = 15.0;
group_uniforms;

group_uniforms surface;
// How much of the geometric slope reaches the optical normal. The swell carries
// the silhouette, the normal map carries the detail; both are needed.
uniform float normal_lighting : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform sampler2D large_wave_normals : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float surface_normal_strength : hint_range(0.0, 1.0, 0.01) = 0.45;
// World-space repeat of the normal strip, in metres.
uniform float normal_repeat_metres : hint_range(0.5, 20.0, 0.1) = 2.5;
uniform float detail_broad : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform float detail_mid : hint_range(0.0, 1.0, 0.01) = 0.58;
uniform float detail_fine : hint_range(0.0, 1.0, 0.01) = 0.24;
group_uniforms;

group_uniforms relief;
// The sheet does not take light: `ALBEDO` stays zero and the whole colour is
// composed here. That is what keeps the backends matching, but it also means a
// top-down camera sees no shading at all — every facet of a swell resolves to
// the same pixel, and the sea reads as a printed blue plane. This layer puts
// the relief back as pure colour modulation. It never touches geometry, the
// shared wave field, the boat's draft or the shoreline atlas.
uniform bool relief_enabled = true;
// Contrast on the relief field. 1.0 is calibrated against the reference frame's
// measured spread; higher pushes the patches toward cloud shadow.
uniform float relief_gain : hint_range(0.2, 3.0, 0.01) = 1.0;
// How far a lit patch lifts. Additive on purpose: the red channel is pinned at
// zero in the body colour, and a multiply could never bring it back.
// The range runs past 1.0 because the octaves are summed, not averaged: their
// individual peaks rarely align, so the field lands well inside ±1 and needs the
// extra headroom to reach the calibrated spread.
uniform float relief_light : hint_range(0.0, 3.0, 0.01) = 0.34;
// How far a shaded patch is pulled toward the deep colour. Mixing rather than
// multiplying: a multiply drains the green channel and reads as soot.
uniform float relief_shade : hint_range(0.0, 3.0, 0.01) = 0.42;
// Tint lifted into the lit patches, so a crest reads as thin translucent water
// rather than as grey paint.
uniform vec3 relief_color : source_color = vec3(0.62, 0.95, 1.0);
group_uniforms;

group_uniforms sky;
// Mirrors assets/materials/ocean_sky.tres so the reflection cannot drift away
// from the sky the player actually sees.
uniform vec3 sky_top_color : source_color = vec3(0.12, 0.36, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.61, 0.79, 0.84);
uniform vec3 sky_ground_color : source_color = vec3(0.10, 0.26, 0.32);
uniform float sky_curve : hint_range(0.05, 1.0, 0.01) = 0.35;
uniform float sky_sun_glow : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float reflection_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
// Steep on purpose: flat water is almost all body colour, and the reflection is
// a rim that only appears as the surface turns away from the eye.
uniform float fresnel_power : hint_range(1.0, 12.0, 0.1) = 6.0;
group_uniforms;

group_uniforms sun;
// World direction from the water toward the sun, kept in sync with the scene's
// Sun by hand (the shader does not follow the light node).
uniform vec3 sun_direction = vec3(0.5191, 0.7787, -0.3523);
uniform vec3 sun_color : source_color = vec3(1.0, 0.955, 0.8);
uniform float sun_highlight_strength : hint_range(0.0, 3.0, 0.01) = 0.30;
uniform float sun_glossiness : hint_range(100.0, 12000.0, 50.0) = 7000.0;
// Peak gain of the filtered lobe. The package ships 250 against its own wave set;
// this project's swell is gentler and its camera far higher, so the same number
// paints a cloud instead of a sparkle.
uniform float sun_lobe_gain : hint_range(5.0, 400.0, 1.0) = 60.0;
group_uniforms;

group_uniforms ripples;
uniform bool ripples_enabled = true;
// RGB is the ink colour, A the layer opacity. A is not the water's transparency.
uniform vec4 ripple_color : source_color = vec4(0.85, 0.95, 0.90, 0.45);
// How much of the network stays alive at once. Not the white-pixel fraction.
uniform float ripple_coverage : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float ripple_width_multiplier : hint_range(0.0, 1.5, 0.01) = 0.35;
uniform float ripple_dissipation_speed : hint_range(0.25, 4.0, 0.01) = 1.0;
uniform float ripple_scale : hint_range(0.3, 3.0, 0.01) = 1.0;
// World size of one tile of the strip. The package tunes this for a 34 m pond;
// on a kilometre of open sea the same tile paints metre-wide ribbons, so the
// project ships a smaller one and lets `ripple_scale` stay an art control.
uniform vec2 ripple_tile_metres = vec2(6.0, 4.5);
// Where the network stops being legible. Past this it only aliases.
uniform float ripple_fade_near : hint_range(0.0, 60.0, 0.5) = 6.0;
uniform float ripple_fade_far : hint_range(1.0, 120.0, 0.5) = 28.0;
// Linear L8 contour strip: R = 0.5 on the contour, brighter inside, normalised by
// the local half-width. A plain black-and-white mask will not work.
uniform sampler2D ripple_pattern : repeat_enable, filter_linear_mipmap;
uniform float flow_speed : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float flow_direction_degrees : hint_range(0.0, 360.0, 0.1) = 180.0;
group_uniforms;

group_uniforms glints;
// Luminous motes drifting on the water ring around structures. They sit inside
// the shoreline distance band, so they only appear near built-up areas — open
// sea stays clean.
uniform bool glints_enabled = true;
uniform vec3 glint_color : source_color = vec3(0.88, 0.99, 0.96);
// Multiplies the final coverage. 1.0 is the original look.
uniform float glint_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
// Fraction of hash cells that host a mote. 0 turns them off without the toggle.
uniform float glint_density : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float glint_size : hint_range(0.2, 3.0, 0.01) = 1.0;
uniform float glint_speed : hint_range(0.0, 3.0, 0.01) = 1.0;
// How far a mote wanders from its cell centre, in cells.
uniform float glint_drift : hint_range(0.0, 3.0, 0.01) = 1.0;
// Exponent of the fade in/out curve. Small values keep motes lit almost always,
// large ones make them blink briefly.
uniform float glint_twinkle : hint_range(0.5, 8.0, 0.01) = 2.4;
// Distance from the shoreline where the band starts / ends, in metres. Fades
// use fixed fractions of each radius (in from 43%, out from 52.5%), which
// reproduces the hard-coded 0.95 / 2.2 / 6.2 / 11.8 exactly.
uniform float glint_zone_inner : hint_range(0.5, 20.0, 0.1) = 2.2;
uniform float glint_zone_outer : hint_range(2.0, 40.0, 0.1) = 11.8;
group_uniforms;

group_uniforms output;
// The project renders at a different exposure than the package's demo, and ACES
// is what turns a linear colour into the final pixel, so the composed colour is
// pre-scaled by the same ratio.
uniform float exposure_comp : hint_range(0.2, 2.5, 0.01) = 0.66;
// The gl_compatibility renderer resolves an emission-only surface far darker than
// Forward+ at the same input. render_flags.gd supplies the measured factor.
uniform vec3 emission_gain = vec3(1.0);
// One output level of screen-space dither: the body gradient is slow enough that
// an 8-bit framebuffer would otherwise quantise it into contour bands.
uniform float dither_strength : hint_range(0.0, 4.0, 0.05) = 1.0;
group_uniforms;

varying vec3 v_world;
varying vec2 wake_slope;
// Static carriers only. Every clock stays in the fragment so a long-running
// time does not lose precision in an interpolant.
varying vec2 v_normal_uv;
varying vec2 v_ripple_uv;
varying vec2 v_ripple_phase;
varying flat vec2 v_flow_forward;
varying flat vec3 v_sun_dir;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
// Value noise together with its analytic gradient (value, d/dx, d/dz).
// One evaluation gives a full slope instead of three finite differences.
vec3 noise_grad(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k3 = a - b - c + d;
	float value = a + k1 * u.x + k2 * u.y + k3 * u.x * u.y;
	return vec3(value, (k1 + k3 * u.y) * du.x, (k2 + k3 * u.x) * du.y);
}
#include "res://shaders/ocean_foam.gdshaderinc"
#include "res://shaders/contact_foam.gdshaderinc"

vec2 flow_forward() {
	float angle = radians(mod(flow_direction_degrees, 360.0));
	return vec2(cos(angle), sin(angle));
}

vec3 view_position(vec2 uv, float raw, mat4 inverse_projection) {
	float z = u_reverse_z > 0.5 ? raw : raw * 2.0 - 1.0;
	vec4 v = inverse_projection * vec4(uv * 2.0 - 1.0, z, 1.0);
	return v.xyz / v.w;
}

// One anisotropic ripple layer: ridges run across `wind`, amplitude in metres.
void add_ripple(vec2 p, vec2 wind, float along_k, float across_k, float speed, float amp, float fade, inout vec2 slope) {
	vec2 across = vec2(-wind.y, wind.x);
	vec2 q = vec2(dot(p, wind) * along_k, dot(p, across) * across_k) + wind * (u_time * speed);
	vec3 g = noise_grad(q);
	slope += (wind * (g.y * along_k) + across * (g.z * across_k)) * (amp * fade);
}

// Height for the relief pass only — deliberately NOT added to `slope`.
//
// Same three anisotropic octaves as `add_ripple`, but the noise *value* instead
// of its gradient. The relief layer needs a field that is low-frequency in both
// axes, bounded, and non-repeating; the analytic wave sum cannot give that
// (four sines at 12/7.6/4.9/2.55 m stack into a fixed interference lattice, which
// at this camera reads as parallel bands), and a single sine is worse still.
void add_relief(vec2 p, vec2 wind, float along_k, float across_k, float speed, float amp, float fade, inout float h) {
	vec2 across = vec2(-wind.y, wind.x);
	vec2 q = vec2(dot(p, wind) * along_k, dot(p, across) * across_k) + wind * (u_time * speed);
	h += (noise_grad(q).x - 0.5) * 2.0 * amp * fade;
}
vec3 sky_at(vec3 d) {
	float up = d.y;
	vec3 colour = mix(sky_horizon_color, sky_top_color, pow(clamp(up, 0.0, 1.0), sky_curve));
	colour = mix(colour, sky_ground_color, pow(clamp(-up, 0.0, 1.0), sky_curve * 2.0));
	// Warm halo toward the sun. Kept wide and weak: the sparkle is the sun lobe's
	// job, this only keeps the reflection from being uniformly cold.
	colour += sun_color * sky_sun_glow * pow(max(dot(d, v_sun_dir), 0.0), 12.0);
	return colour;
}

// Sun glitter. The normal is flattened on Y before reflecting so the lobe covers
// a believable patch of water instead of a single facet, and the reflection
// direction's own screen-space footprint widens it wherever a pixel would
// otherwise alias into noise.
float sun_lobe(vec3 n, vec3 view_dir, float normal_view) {
	vec3 flattened = n * vec3(1.0, 3.0, 1.0);
	float view_dot = normal_view + 2.0 * n.y * view_dir.y;
	vec3 reflected = (2.0 * view_dot / (1.0 + 8.0 * n.y * n.y)) * flattened - view_dir;
	float alignment = clamp(dot(v_sun_dir, reflected), 0.0, 1.0);
	vec3 dx = dFdx(reflected);
	vec3 dy = dFdy(reflected);
	float variance = (dot(dx, dx) + dot(dy, dy)) * (1.0 / 24.0);
	float inverse_width = 1.0 / (1.0 + sun_glossiness * variance);
	float lobe = exp2(-1.44269504089 * sun_glossiness * (1.0 - alignment) * inverse_width);
	return clamp(lobe * inverse_width * sun_lobe_gain, 0.0, 1.0);
}

// Rising pulse erodes the contour, falling pulse regrows it. Slower retreat
// spends longer below full width; recovery always takes PI phase units.
float ripple_lifecycle(float phase, float direction, float retreat_duration) {
	float recovery_start = max(retreat_duration, PI);
	float cycle = mod(direction * (phase + PI * 0.5), recovery_start + PI);
	float shaped = cycle < retreat_duration
		? cycle * (PI / retreat_duration)
		: PI + max(cycle - recovery_start, 0.0);
	return 0.5 - 0.5 * cos(shaped);
}

// Ink network from the contour strip. Decoded distance is normalised by the local
// half-width, so `1 - retreat` shrinks every stroke proportionally: thin links
// and broad junctions retreat together instead of the broad ones lingering.
float sample_ripples(vec2 pattern_uv, float t) {
	vec2 uv = pattern_uv - vec2(0.0, t * 1.1 * ripple_scale / 18.0);
	float signed_distance = texture(ripple_pattern, uv).r * 2.0 - 1.0;

	// Two overlapping phases with periods that do not divide the tile, so
	// neighbouring copies of the network cannot share one lifecycle silhouette.
	vec2 phase = v_ripple_phase
		+ t * (vec2(1.313, -1.389) - ripple_scale * vec2(0.803, 1.529)) + vec2(0.0, 2.1);
	float pulse_a;
	float pulse_b;
	if (ripple_dissipation_speed == 1.0) {
		pulse_a = 0.5 + 0.5 * sin(phase.x);
		pulse_b = 0.5 + 0.5 * sin(phase.y);
	} else {
		float retreat_duration = PI / clamp(ripple_dissipation_speed, 0.25, 4.0);
		pulse_a = ripple_lifecycle(phase.x, 1.0, retreat_duration);
		pulse_b = ripple_lifecycle(phase.y, -1.0, retreat_duration);
	}
	// Coverage biases the lifecycle, never a static spatial mask. 0.7 is neutral;
	// at 1 the deepest retreat stays below the contour's medial value.
	float coverage = clamp(ripple_coverage, 0.001, 1.0);
	float retreat = min(1.2 * pulse_a * pulse_a * pulse_b * (0.7 / coverage), 2.0);

	float contour = signed_distance - 1.0
		+ clamp(ripple_width_multiplier, 0.0, 1.5) * (1.0 - retreat);
	float aa = max(fwidth(contour) * 0.5, 1.0 / 255.0);
	return smoothstep(-aa, aa, contour);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = v_world.xz;
	// Height and slope are sampled before displacement, as the boat does.
	float wake_height = wake_sample(p);
	wake_slope = vec2(
		wake_sample(p + vec2(0.12, 0.0)) - wake_sample(p - vec2(0.12, 0.0)),
		wake_sample(p + vec2(0.0, 0.12)) - wake_sample(p - vec2(0.0, 0.12))) / 0.24;
	VERTEX.y += ocean_sample(p).x + bow_height(p) + wake_height + shore_height(p);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Affine world projections belong here; only clocks stay in the fragment.
	vec2 forward = flow_forward();
	vec2 across = vec2(-forward.y, forward.x);
	vec2 flow_position = vec2(dot(v_world.xz, across), dot(v_world.xz, forward));
	v_flow_forward = forward;
	v_ripple_uv = flow_position * ripple_scale / max(ripple_tile_metres, vec2(0.5));
	v_ripple_phase = vec2(
		dot(flow_position, ripple_scale * vec2(1.17, 0.73) + vec2(0.37, -0.53)),
		dot(flow_position, ripple_scale * vec2(-0.61, 1.39) + vec2(-0.47, 0.29)));
	v_normal_uv = vec2(dot(v_world.xz, forward), dot(v_world.xz, across))
		/ max(normal_repeat_metres, 0.1);
	v_sun_dir = normalize(sun_direction + vec3(0.0, 0.000001, 0.0));
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 wave = ocean_sample(p);
	vec2 slope = wave.yz + wake_slope;
	slope += vec2(shore_height(p + vec2(0.10, 0.0)) - shore_height(p - vec2(0.10, 0.0)),
		shore_height(p + vec2(0.0, 0.10)) - shore_height(p - vec2(0.0, 0.10))) / 0.20;
	// Ripple octaves stretched across the wind, the way wind chop actually forms:
	// ridges run perpendicular to travel, not as round blobs. Fine detail fades
	// much earlier so it cannot alias into sparkle.
	float view_dist = length(VERTEX);
	float fade_mid = 1.0 - smoothstep(70.0, 200.0, view_dist);
	float fade_fine = 1.0 - smoothstep(14.0, 46.0, view_dist);
	add_ripple(p, normalize(vec2(0.94, 0.34)), 0.52, 0.26, 0.08, detail_broad * 0.30, 1.0, slope);
	add_ripple(p, normalize(vec2(0.80, 0.60)), 1.30, 0.79, 0.30, detail_mid * 0.051, fade_mid, slope);
	add_ripple(p, normalize(vec2(0.99, 0.10)), 5.00, 3.50, 0.85, detail_fine * 0.0165, fade_fine, slope);
	// Relief field: the same octaves at the same spatial frequencies, read as
	// height. Because it is noise rather than a wave sum there is no lattice to
	// alias into banding at any camera angle.
	float relief_h = 0.0;
	add_relief(p, normalize(vec2(0.94, 0.34)), 0.52, 0.26, 0.08, detail_broad * 0.30, 1.0, relief_h);
	add_relief(p, normalize(vec2(0.80, 0.60)), 1.30, 0.79, 0.30, detail_mid * 0.051, fade_mid, relief_h);
	add_relief(p, normalize(vec2(0.99, 0.10)), 5.00, 3.50, 0.85, detail_fine * 0.0165, fade_fine, relief_h);
	slope += vec2(bow_height(p + vec2(0.08, 0.0)) - bow_height(p - vec2(0.08, 0.0)),
		bow_height(p + vec2(0.0, 0.08)) - bow_height(p - vec2(0.0, 0.08))) / 0.16;
	for (int i = 0; i < 8; i++) {
		if (i >= u_ripple_count) break;
		vec4 rp = u_ripples[i];
		float age = u_time - rp.z;
		if (age > 0.0 && age < 3.5) {
			vec2 rel = p - rp.xy;
			float dist = length(rel);
			float ring = dist - (0.15 + age * 0.9);
			float envelope = exp(-ring * ring * 18.0) * (1.0 - age / 3.5) * rp.w;
			slope += rel / max(dist, 0.01) * cos(ring * 14.0) * envelope * 0.055;
		}
	}
	vec3 normal = normalize(vec3(-slope.x * normal_lighting, 1.0, -slope.y * normal_lighting));

	// The normal strip is sampled twice, moving apart: a single scrolling layer
	// would read as a conveyor belt. Neutral 0.5/0.5 decodes to zero tilt.
	if (surface_normal_strength > 0.0) {
		vec2 drift = vec2(u_time * flow_speed * 0.06, u_time * flow_speed * 0.025);
		vec2 a = texture(large_wave_normals, v_normal_uv - drift).rg;
		vec2 b = texture(large_wave_normals, v_normal_uv + drift * 0.73 + vec2(0.37, 0.61)).rg;
		vec2 strip = a + b - vec2(1.0);
		vec2 across = vec2(-v_flow_forward.y, v_flow_forward.x);
		vec2 tilt = (v_flow_forward * strip.x + across * strip.y) * surface_normal_strength;
		normal = normalize(normal + vec3(tilt.x, 0.0, tilt.y) * normal.y);
	}

	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - v_world);
	float normal_view = clamp(dot(normal, to_eye), 0.0, 1.0);
	float grazing = 1.0 - normal_view;

	// ---- water column ------------------------------------------------------
	float water_depth = -VERTEX.z;
	float raw = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 bed_view = view_position(SCREEN_UV, raw, INV_PROJECTION_MATRIX);
	// Axial path length, used for the refraction taper and the absorption.
	float thickness = clamp(-bed_view.z - water_depth, 0.0, 45.0);
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_view, 1.0)).xyz;

	// Refraction fades out at the waterline and again once the bed is too far to
	// resolve; the browser tapers it over exactly this range.
	float refract_fade = smoothstep(0.15, 2.5, thickness) * (1.0 - smoothstep(24.0, 45.0, thickness));
	vec2 view_slope = (VIEW_MATRIX * vec4(slope.x, 0.0, slope.y, 0.0)).xy;
	vec2 refract_uv = clamp(SCREEN_UV + view_slope * (refraction_strength / VIEWPORT_SIZE) * refract_fade, vec2(0.001), vec2(0.999));
	vec3 ref_view = view_position(refract_uv, textureLod(depth_tex, refract_uv, 0.0).r, INV_PROJECTION_MATRIX);
	if (-ref_view.z < water_depth + 0.08) refract_uv = SCREEN_UV;
	vec3 submerged = textureLod(screen_tex, refract_uv, 0.0).rgb;

	// ---- body: bed seen through water, then the deep colour -----------------
	//
	// This uses the VERTICAL water column, not the axial one the package uses.
	// At grazing angles the axial path through water is many times longer, so the
	// package's model turns the surface opaque exactly when the player is looking
	// across it — which would hide the drowned city this game is about. Vertical
	// depth keeps a shallow shelf readable from any angle, which is the project's
	// established look; the axial length still drives absorption and refraction.
	// True vertical depth of the geometry under this pixel. Kept separately
	// because `vertical_depth` below gets inflated for open sea, and the caustics
	// fade must use the real depth or it would light up the empty ocean floor.
	float bed_depth = max(0.0, v_world.y - bed_world.y);
	float vertical_depth = bed_depth;
	// No bottom in view (open sea): treat it as bottomless — but ease into it.
	//
	// This used to be a hard `if (thickness > 44.0) vertical_depth = 60.0;`, and
	// that single step was visible as a straight seam across open water. The
	// reason it reads as a *cut* rather than as water: `thickness` is an axial
	// path length, so its 44 m contour is a plane in world space. An isometric
	// camera projects a plane to a straight line, and the body colour on either
	// side of it differs by the whole shallow-to-deep range. Easing the same
	// transition over 26~44 m keeps both ends and removes the edge: the contour
	// is still there, it just no longer has a step across it.
	float open_sea = smoothstep(26.0, 44.0, thickness);
	vertical_depth = mix(vertical_depth, 60.0, open_sea);
	float depth_amount = vertical_depth / max(depth_half_distance, 0.001);
	float depth_blend = 1.0 - exp2(-depth_amount);
	float body_opacity = clamp(depth_amount, 0.0, 1.0);
	float clear_view = 1.0 - smoothstep(0.15, 0.85, grazing) * view_occlusion_strength;
	float shallow_visibility = (1.0 - depth_blend) * clear_view;
	float bottom_visibility = (1.0 - body_opacity) * clear_view;
	float transmission = 1.0 - bottom_visibility;
	vec3 shallow_tint = body_shallow * shallow_tint_strength;
	float caustic_term = 0.0;

	// ---- caustics on the submerged geometry --------------------------------
	// The web build paints these onto the refracted scene sample, and that is the
	// right place for them: caustics are light that has ALREADY passed through the
	// surface, so they belong on the seabed and on the drowned walls, not on the
	// water plane. Adding them after the bed is sampled means they also inherit
	// the refraction wobble and the absorption falloff for free, which is what
	// makes them read as light in water rather than as a decal.
	//
	// The pattern is the zero set of sin(x)·cos(y). |sin·cos| is dark everywhere
	// except along the lines where either term crosses zero, so inverting a
	// narrow band around 0 gives the thin bright cell walls caustics actually
	// look like. Everything is sampled at `bed_world.xz`, so the web of light is
	// welded to the geometry: it stays put while the water moves over it. That is
	// also why it must not use `v_world` — the surface scrolls and snaps, the
	// seabed does not.
	if (caustics_enabled && caustics_strength > 0.0) {
		// Broad soft patches, not a lattice. The first version used the classic
		// `1 - smoothstep(a, b, |sin x · cos y|)` web; even widened it read as a
		// regular grid of scratches, because a lattice is a lattice. What the
		// reference frame actually shows is irregular light patches with softly
		// scalloped edges, which is what low-frequency noise gives for free.
		//
		// Two octaves at very different scales: the coarse one decides where the
		// big patches are, the fine one frays their edges so they do not look like
		// blobs of paint.
		vec2 drift = vec2(u_time * 0.055, -u_time * 0.041) * caustics_speed;
		vec2 p1 = bed_world.xz * (0.42 * caustics_scale) + drift;
		float patch = noise(p1);
		// Narrow-ish top band: light lands where the field peaks, not everywhere.
		float caustic = smoothstep(0.46, 0.74, patch);
		if (caustics_detail > 0.0) {
			vec2 p2 = bed_world.xz * (1.35 * caustics_scale) - drift * 1.7;
			float fray = noise(p2 + noise(p1 * 1.8) * 0.9);
			// Multiply rather than add: the fine octave should carve the coarse
			// patches into lobes, not sprinkle extra light of its own.
			caustic *= mix(1.0, smoothstep(0.30, 0.70, fray) * 1.35, caustics_detail);
		}
		// Screen-space fade. Past a few metres the patches shrink below a pixel and
		// would shimmer into noise; `fwidth` measures exactly that footprint.
		float resolved = 1.0 - smoothstep(0.35, 1.40, length(fwidth(p1)));
		// Only where there is actually something down there. Open water has no bed
		// for the light to land on, and without this guard the pattern spreads
		// across the whole sea as floating stains.
		//
		// Sign depends on the depth convention, and getting it backwards silently
		// masks out exactly the geometry that should be lit — that cost one full
		// round of "the effect does nothing" here. Under Reverse-Z the far plane
		// reads 0 and solid geometry reads near 1, so `raw` must be *high* to count
		// as geometry; the normal convention is the other way round.
		float on_geometry = u_reverse_z > 0.5
			? smoothstep(0.0, 0.0005, raw)
			: 1.0 - smoothstep(0.9975, 1.0, raw);
		// Depth band. Near the surface the light has not had room to focus; deep
		// down it has scattered too much. Both ends are soft so the pattern never
		// terminates on a visible contour.
		float depth_band = smoothstep(caustics_depth_near * 0.25, caustics_depth_near, bed_depth)
			* (1.0 - smoothstep(caustics_depth_far * 0.20, caustics_depth_far, bed_depth));
		// Parked in its own variable, applied after the body composite below.
		// Adding it into `submerged` looked right and did nothing: at 3 m the body
		// is already ~97% opaque, so `bottom_visibility` scales the bed — and every
		// caustic in it — down to 3%. Measured at strength 2.5 the pattern was
		// still invisible. Caustics are light on a surface the eye can see, so they
		// belong at the end of the chain, guarded by `on_geometry` instead.
		caustic_term = caustic * caustics_strength * depth_band * resolved * on_geometry;
	}

	vec3 bed = submerged * exp(-vertical_depth * absorption);
	vec3 color = bed * (bottom_visibility + shallow_tint * transmission * shallow_visibility)
		+ body_deep * (transmission * (1.0 - shallow_visibility));
	color = clamp(color, vec3(0.0), vec3(1.0));

	// Caustics land on whatever the light reaches under the surface. Applied here,
	// after the body composite, so the depth-based body opacity cannot swallow
	// them (see the note where `caustic_term` is computed).
	//
	// The pattern darkens the gaps instead of brightening the peaks, and that is
	// not a stylistic choice — it is the only thing that works on this scene. The
	// drowned walls are near-white (0.9+), so any additive term is clamped away:
	// measured at strength 2.5 the additive version was completely invisible.
	// Physically it is also the right reading: caustics are focused light *with
	// dimmer surroundings*, so the walls between the bright folds genuinely are
	// darker than ambient. Keeping the peaks at full brightness and pulling the
	// gaps down makes the web visible on a white wall and on a dark window alike.
	if (caustic_term > 0.0) {
		color *= 1.0 - caustic_term;
		color = clamp(color, vec3(0.0), vec3(1.0));
	}

	// ---- sky and sun, screen-blended so they cannot wash the body out -------
	vec3 reflected_surface = sky_at(reflect(-to_eye, normal))
		* (pow(grazing, fresnel_power) * reflection_strength);
	if (sun_highlight_strength > 0.0) {
		reflected_surface += sun_color * sun_lobe(normal, to_eye, normal_view) * sun_highlight_strength;
	}
	color += (vec3(1.0) - color) * clamp(reflected_surface, vec3(0.0), vec3(1.0));

	// ---- swell relief ------------------------------------------------------
	// The sheet takes no light: `ALBEDO` stays zero and the whole colour is
	// composed here. That is what keeps the two backends matching, but it also
	// means a top-down camera sees the sea as a printed flat colour — no swell,
	// no chop, nothing that says the surface is water. This layer puts that
	// reading back as colour only. It never touches geometry, the shared wave
	// field, the boat's draft or the shoreline atlas.
	//
	// The field is noise, not the analytic wave sum, and that distinction is the
	// whole point. Four sines at fixed wavelengths and directions interfere into
	// a lattice: from above it renders as evenly spaced parallel bands — the
	// "条条" the players reported. Two earlier versions tried exactly that
	// (banding on `wave.x`, then banding on one 4.9 m wave) and both produced
	// visible stripes; the second was worse, because a single sine is a perfect
	// grating. Anisotropic noise has no period, so it cannot band at any angle.
	//
	// Amplitude is set so the result lands on the reference frame's measured
	// spread — open-water green channel std 5.0 at 8 bit. Below ~4 the sea reads
	// as flat paper, above ~7 the patches start reading as cloud shadow. This is
	// measured, not guessed: `tools/probe_water_stats.gd` reports it on clean
	// all-water cells only (a whole-frame average includes buildings and foam and
	// overstates the spread by roughly 2x).
	if (relief_enabled) {
		// At grazing angles the reflection term already does this job, and adding
		// to it reads as film grain over the horizon.
		float relief_fade = 1.0 - smoothstep(60.0, 170.0, view_dist);
		float h = clamp(relief_h / 0.55 * relief_gain, -1.0, 1.0);
		float lit = smoothstep(0.02, 0.90, h);
		float trough = smoothstep(0.02, 0.90, -h);
		color += relief_color * (lit * relief_light * 0.10 * relief_fade);
		color = mix(color, body_deep * 0.94, trough * relief_shade * 0.16 * relief_fade);
		color = clamp(color, vec3(0.0), vec3(1.0));
	}

	// ---- ripple network ----------------------------------------------------
	if (ripples_enabled && ripple_coverage > 0.0 && ripple_width_multiplier > 0.0
		&& ripple_color.a > 0.0) {
		float ripple = sample_ripples(v_ripple_uv, u_time * flow_speed);
		// The strip repeats over a fixed world area; past the near field it would
		// only be a moire, so it is faded out well before the body takes over.
		float distance_fade = 1.0 - smoothstep(ripple_fade_near, max(ripple_fade_far, ripple_fade_near + 0.5), view_dist);
		color = mix(color, ripple_color.rgb, ripple * distance_fade * ripple_color.a);
	}

	// ---- facility-vicinity water glints (gentle shimmering particles) ------
	// Restores the web build's luminous motes around structures.
	// `shore` is shared with the contact-foam block below, so it stays out here.
	vec2 shore = shoreline_data(p);
	float shore_d = shore.x;
	if (glints_enabled && glint_strength > 0.0 && glint_density > 0.0) {
		float inner = max(glint_zone_inner, 0.1);
		float outer = max(glint_zone_outer, inner + 0.5);
		float glint_zone = smoothstep(inner * 0.4318, inner, shore_d)
			* (1.0 - smoothstep(outer * 0.5254, outer, shore_d));
		float glint_sum = 0.0;
		// Early out on open sea: the band is empty for most of the surface and
		// the loop below is the expensive part.
		if (glint_zone > 0.001) {
			for (int layer = 0; layer < 2; layer++) {
				float sc = layer == 0 ? 0.62 : 0.88;
				vec2 gp = p * sc + vec2(float(layer) * 19.7, float(layer) * 31.3);
				vec2 cell = floor(gp);
				vec2 f = fract(gp) - 0.5;
				float h1 = hash(cell);
				float h2 = hash(cell + vec2(37.2, 17.9));
				float h3 = hash(cell + vec2(71.3, 53.1));
				// Sparse distribution: only `glint_density` of the cells host a mote.
				if (h1 > 1.0 - glint_density) {
					float ph = u_time * glint_speed * (0.85 + h2 * 0.75) + h1 * TAU * 3.0;
					vec2 wander = vec2(sin(ph * 0.55 + h3 * TAU), cos(ph * 0.48 - h2 * TAU))
						* 0.16 * glint_drift;
					vec2 center = (vec2(h2, h3) - 0.5) * 0.52 + wander;
					float d = length(f - center);
					float tw = pow(max(0.0, sin(ph)), max(glint_twinkle, 0.1));
					float r = (0.042 + 0.022 * h3) * (0.65 + 0.35 * tw) * glint_size;
					float aa = max(fwidth(d), 0.012);
					float dot_mask = (1.0 - smoothstep(r - aa, r + aa, d)) * tw;
					glint_sum = max(glint_sum, dot_mask);
				}
			}
			// 0.86 is the original per-mote gain at strength 1.0; the old 0.88
			// ceiling was never reached, so clamping at 1.0 leaves the default
			// look untouched.
			float glint_a = clamp(glint_sum * glint_zone * 0.86 * glint_strength, 0.0, 1.0);
			color = mix(color, glint_color, glint_a);
		}
	}

	// ---- contact foam: the waterline where the sheet meets a solid ---------
	float contact = 0.0;
	if (contact_foam_strength > 0.0 && contact_foam_width > 0.0 && contact_foam_color.a > 0.0) {
		// Large docks get a slightly wider band than a thin post.
		float contact_width = contact_foam_width * clamp(shore.y, 0.55, 1.25);
		contact = sample_contact_foam(p, shore_d, contact_width, u_time);
	}
	color = mix(color, contact_foam_color.rgb,
		clamp(contact * contact_foam_strength * contact_foam_color.a, 0.0, 1.0));

	// ---- remaining foam: swell tops, thin solids, boat wake ---------------
	float foam = max(crest_foam(p, shore_d, view_dist, wave.x),
		contact_edge(p, thickness, view_dist));
	vec3 trail = wake_profile(p);
	trail.x += (noise(p * 1.15 + vec2(u_time * 0.07, 0.0)) - 0.5) * (0.14 + trail.y * 0.025);
	float trail_width = 0.035 + trail.y * 0.006;
	float trail_line = 1.0 - smoothstep(trail_width, trail_width + clamp(fwidth(trail.x), 0.025, 0.09), abs(trail.x));
	float trail_break = smoothstep(0.17 + trail.y * 0.045, 0.44 + trail.y * 0.045, noise(p * 2.1 + u_time * 0.07));
	foam = max(foam, trail_line * trail.z * trail_break * foam_grain(p, trail.y / 9.0) * 0.68);
	// Foam is flat near-white, as in water.js. The value lives in the shared
	// `foam_color` uniform (declared by ocean_foam.gdshaderinc) so the P panel can
	// tune it; it is `source_color`, so the resource stores the sRGB form of the
	// linear 0.96/0.985/1.0 that was hard-coded here.
	color = mix(color, foam_color, clamp(foam, 0.0, 0.96));

	// Albedo stays zero so no light can reach the surface: the composed colour is
	// the whole shading model. Emission carries it.
	ALBEDO = vec3(0.0);
	vec3 emission = color * exposure_comp * emission_gain;
	// Interleaved gradient noise: a stable, high-frequency, camera-static pattern
	// that costs four instructions. Static rather than time-animated on purpose —
	// an animated dither boils in motion and reads as grain.
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	emission += (ign - 0.5) * 0.0045 * dither_strength;
	EMISSION = emission;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
