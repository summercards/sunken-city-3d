// Absorption-based stylized water — the second water scheme, kept beside the
// painterly one in `water.gdshader`. Neither replaces the other: the P panel
// switches the Water node's material between the two at runtime.
//
// Method follows "Absorption Based Stylized Water" by Malido (godotshaders.com).
// The surface does not compose a body colour of its own; it takes what is
// already on screen behind it and eats the absorbed wavelengths out of it by the
// Beer-Lambert law, then puts the complementary colour back as it deepens:
//
//   depth_blend = 1 - exp(-clamp(depth / depth_distance) * beers_law)
//   color       = screen - absorption_color * depth_blend
//   color       = mix(color, 1 - absorption_color, depth_blend^2)
//
// Why a second material instead of a branch inside the old shader: these are not
// two presets of one look. The old body is an opaque shallow/deep pair painted
// from authored colours; this one can never be brighter than the scene behind
// it, so every value's meaning depends on the other model's. Behind an `if`,
// "reset to factory" would have no single answer, and the P panel could not show
// one honest set of sliders.
//
// Deliberately shared with the old shader, because gameplay reads them:
//   * the wave field (`ocean_sample` + `bow_height`) — the boat samples the same
//     functions for its draft, so a different wave model would float the hull;
//   * the boat wake and the oar-ring normals;
//   * the vertical water column for depth (not the axial one), so a shallow
//     shelf stays readable at grazing angles instead of turning opaque;
//   * EMISSION output with zero albedo — gl_compatibility composites
//     ALBEDO + `unshaded` as pure black (see `render_flags.gd`).
//
// Deliberately dropped from the reference implementation:
//   * global shader uniforms for wind / player position — this project already
//     owns those quantities in gameplay code;
//   * the screen-space reflection loop — it marches the depth buffer and the
//     project's reflection probes already cover the visible band;
//   * displacement / edge / ramp textures — the wave field is analytic and the
//     edge foam is procedural, so this scheme adds no texture slots beyond the
//     normal strip it shares with the other one.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float water_level = 1.12;
uniform float u_reverse_z = 1.0;
uniform vec4 u_ripples[8];
uniform int u_ripple_count = 0;

// Shoreline distance atlas, written by `shore_distance.gd` — the same one the
// painterly scheme reads, so both schemes foam against the same waterline.
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform vec4 shore_bounds = vec4(0.0);
uniform float shore_texel = 0.0009765625;
uniform bool shore_enabled = false;

uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap;

#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/ocean_wake.gdshaderinc"

group_uniforms absorb;
// The wavelengths the water takes out of the scene behind it. Deep water shows
// the complement, so author this warm when the water should read teal: the
// reference ships (1.0, 0.35, 0.0) against a blue body.
uniform vec3 absorption_color : source_color = vec3(1.0, 0.45, 0.2);
// Water depth that ends the absorption ramp. The reference tunes this for a
// pool a couple of metres deep; here it has to sit *past* the drowned city's
// roof line, or the scheme paints over the one thing the game is about. 14 m
// keeps the ruins legible out to the middle distance and still saturates on
// open sea (no bottom in view is treated as 60 m).
uniform float depth_distance : hint_range(0.1, 50.0, 0.1) = 14.0;
// Beer-Lambert slope: how fast the ramp saturates inside `depth_distance`.
// Low on purpose — with the reference's 3+ the shallow shelf goes opaque
// inside two metres and the bed plateaus into one flat colour.
uniform float beers_law : hint_range(0.0, 20.0, 0.1) = 2.2;
// Screen colour multiplier before absorbing (the reference uses 0.9).
uniform float screen_gain : hint_range(0.0, 1.5, 0.01) = 0.9;
// 这里的深水要比参考实现暗。参考实现的互补色是它的池底本色（亮的青蓝），
// 直接照搬会让整片海面在俯视时都是浅青，沉没城市失去纵深。0.65 是「深水
// 压到六成半」；1.0 等于关掉，退回参考实现的样子。
uniform float deep_darkness : hint_range(0.1, 1.0, 0.01) = 0.65;
uniform float refraction_strength : hint_range(0.0, 80.0, 0.5) = 22.0;
group_uniforms;

group_uniforms fresnel;
// `1 - dot(normal, view)` raised to this power. Large = only near-grazing angles
// pick up the colour; small = the whole sheet washes out.
uniform float fresnel_radius : hint_range(0.0, 6.0, 0.01) = 6.0;
uniform vec3 fresnel_color : source_color = vec3(0.36, 0.62, 0.68);
uniform float fresnel_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
group_uniforms;

group_uniforms surface;
// The strip is samplers-only detail: it never carries the silhouette.
uniform float normal_map_strength : hint_range(0.0, 2.0, 0.01) = 0.45;
uniform float normal_repeat_metres : hint_range(0.5, 20.0, 0.1) = 15.3;
uniform float normal_lighting : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float scroll_speed : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform vec2 scroll_offset = vec2(0.1, -0.3);
// Second strip layer runs at this multiple of the first one's world scale, which
// keeps the two from locking into a visible single tiling.
uniform float scroll_scale_offset : hint_range(0.1, 3.0, 0.01) = 1.6;
group_uniforms;

group_uniforms sun;
uniform vec3 sun_direction = vec3(0.42, 0.51, -0.35);
uniform vec3 sun_color : source_color = vec3(0.242, 0.508, 0.389);
uniform float sun_highlight_strength : hint_range(0.0, 3.0, 0.01) = 0.06;
uniform float sun_glossiness : hint_range(100.0, 12000.0, 50.0) = 10850.0;
uniform float sun_lobe_gain : hint_range(5.0, 400.0, 1.0) = 5.0;
group_uniforms;

group_uniforms edge;
// Water column this close to a solid counts as "touching" it. This is the
// reference's `edge_thickness`, but measured against vertical depth, which is
// what the depth buffer gives us for free.
uniform float edge_thickness : hint_range(0.0, 2.0, 0.001) = 0.10;
uniform float edge_speed : hint_range(0.0, 1.0, 0.001) = 0.35;
uniform float edge_noise_scale : hint_range(0.05, 4.0, 0.01) = 0.9;
uniform vec3 edge_color : source_color = vec3(0.95, 0.99, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0, 0.01) = 0.40;
group_uniforms;

group_uniforms shore;
// Share of the shoreline band that foams, in metres from the contour.
uniform float shore_foam_width : hint_range(0.0, 3.0, 0.01) = 0.80;
uniform float shore_foam_strength : hint_range(0.0, 1.5, 0.01) = 0.9;
uniform vec3 shore_foam_color : source_color = vec3(0.93, 0.99, 0.97);
group_uniforms;

group_uniforms ripples;
// Oar-stroke rings brighten instead of inking the surface: the reference paints
// its ripple mask toward white, which is also what reads as foam here.
uniform float ripple_ring_strength : hint_range(0.0, 1.5, 0.01) = 0.55;
uniform float ripple_ring_radius : hint_range(0.2, 3.0, 0.01) = 1.0;
group_uniforms;

group_uniforms caustics;
uniform bool caustics_enabled = false;
uniform float caustic_size : hint_range(0.0, 8.0, 0.01) = 2.0;
// Depth over which the caustic net fades out.
uniform float caustic_range : hint_range(1.0, 256.0, 0.1) = 40.0;
uniform float caustic_strength : hint_range(0.0, 1.0, 0.01) = 0.08;
group_uniforms;

group_uniforms output;
uniform float exposure_comp : hint_range(0.2, 2.5, 0.01) = 0.66;
// gl_compatibility resolves an emission-only surface far darker than Forward+;
// `render_flags.gd` supplies the measured factor for both schemes.
uniform vec3 emission_gain = vec3(1.0);
uniform float dither_strength : hint_range(0.0, 4.0, 0.05) = 1.0;
group_uniforms;

varying vec3 v_world;
varying vec2 wake_slope;
varying vec2 v_normal_uv;
varying flat vec3 v_sun_dir;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

vec2 shoreline_data(vec2 p) {
	vec2 uv = (p - shore_bounds.xy) / max(shore_bounds.zw, vec2(1.0));
	if (!shore_enabled || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec2(100.0, 1.0);
	}
	return textureLod(shore_distance, uv * (1.0 - shore_texel) + shore_texel * 0.5, 0.0).rg;
}

vec3 view_position(vec2 uv, float raw, mat4 inverse_projection) {
	float z = u_reverse_z > 0.5 ? raw : raw * 2.0 - 1.0;
	vec4 v = inverse_projection * vec4(uv * 2.0 - 1.0, z, 1.0);
	return v.xyz / v.w;
}

// Sun glitter, same filtered lobe as the painterly scheme so the two schemes
// agree on where the light is. The pixel footprint widens the lobe instead of
// letting it alias.
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

// Cheap caustic web: three noise octaves warped into each other, thresholded
// into thin bright veins. The reference uses a BCC lattice noise with analytic
// derivatives; that is ~40 lines and several texture-free fetches per pixel, and
// this project only needs the veins to move convincingly at knee depth.
float caustic_net(vec2 p, float t) {
	vec2 q = p * max(caustic_size, 0.01) * 0.6;
	float a = noise(q + vec2(t * 0.11, t * 0.07));
	float b = noise(q * 1.7 - vec2(t * 0.09, t * 0.13) + a * 1.2);
	float c = noise(q * 2.9 + vec2(b * 1.6 - t * 0.05, a * 0.7));
	float v = abs(c - 0.5) * 4.0;
	return pow(clamp(1.0 - v, 0.0, 1.0), 6.0);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = v_world.xz;
	// Height and slope are sampled before displacement, exactly as the boat does.
	float wake_height = wake_sample(p);
	wake_slope = vec2(
		wake_sample(p + vec2(0.12, 0.0)) - wake_sample(p - vec2(0.12, 0.0)),
		wake_sample(p + vec2(0.0, 0.12)) - wake_sample(p - vec2(0.0, 0.12))) / 0.24;
	VERTEX.y += ocean_sample(p).x + bow_height(p) + wake_height;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	v_normal_uv = v_world.xz / max(normal_repeat_metres, 0.1);
	v_sun_dir = normalize(sun_direction + vec3(0.0, 0.000001, 0.0));
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 wave = ocean_sample(p);
	vec2 slope = wave.yz + wake_slope;

	// Oar strokes: same ring geometry as the other scheme, so the boat's wake
	// looks the same whichever water is active.
	float ring = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= u_ripple_count) break;
		vec4 rp = u_ripples[i];
		float age = u_time - rp.z;
		if (age > 0.0 && age < 3.5) {
			vec2 rel = p - rp.xy;
			float dist = length(rel);
			float front = dist - (0.15 + age * 0.9) * ripple_ring_radius;
			float envelope = exp(-front * front * 18.0) * (1.0 - age / 3.5) * rp.w;
			slope += rel / max(dist, 0.01) * cos(front * 14.0) * envelope * 0.055;
			ring = max(ring, envelope);
		}
	}
	vec3 normal = normalize(vec3(-slope.x * normal_lighting, 1.0, -slope.y * normal_lighting));

	// Two scrolling samples of the strip, moving apart. A single layer reads as
	// a conveyor belt. Neutral 0.5/0.5 decodes to zero tilt.
	if (normal_map_strength > 0.0) {
		vec2 drift = vec2(u_time * scroll_speed * 0.06, u_time * scroll_speed * 0.025);
		vec2 a = texture(normal_map, v_normal_uv - drift).rg;
		vec2 b = texture(normal_map, v_normal_uv * scroll_scale_offset + scroll_offset + drift * 0.73).rg;
		vec2 tilt = (a + b - vec2(1.0)) * normal_map_strength;
		normal = normalize(normal + vec3(tilt.x, 0.0, tilt.y));
	}

	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - v_world);
	float normal_view = clamp(dot(normal, to_eye), 0.0, 1.0);

	// ---- water column ------------------------------------------------------
	//
	// Vertical depth, not the axial path: at grazing angles the axial path is
	// many times longer, and the reference's model would turn the whole surface
	// into its absorbed colour exactly when the player looks across the sea —
	// which would hide the drowned city. The axial length still drives
	// refraction and the contact band.
	float water_depth = -VERTEX.z;
	float raw = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 bed_view = view_position(SCREEN_UV, raw, INV_PROJECTION_MATRIX);
	float thickness = clamp(-bed_view.z - water_depth, 0.0, 45.0);
	vec3 bed_world = (INV_VIEW_MATRIX * vec4(bed_view, 1.0)).xyz;
	float vertical_depth = max(0.0, v_world.y - bed_world.y);
	// No bottom in view (open sea): treat it as bottomless.
	if (thickness > 44.0) vertical_depth = 60.0;

	float refract_fade = smoothstep(0.15, 2.5, thickness) * (1.0 - smoothstep(24.0, 45.0, thickness));
	vec2 view_slope = (VIEW_MATRIX * vec4(slope.x, 0.0, slope.y, 0.0)).xy;
	vec2 refract_uv = clamp(SCREEN_UV + view_slope * (refraction_strength / VIEWPORT_SIZE) * refract_fade,
		vec2(0.001), vec2(0.999));
	vec3 ref_view = view_position(refract_uv, textureLod(depth_tex, refract_uv, 0.0).r, INV_PROJECTION_MATRIX);
	if (-ref_view.z < water_depth + 0.08) refract_uv = SCREEN_UV;
	vec3 behind = textureLod(screen_tex, refract_uv, 0.0).rgb * screen_gain;

	// ---- absorption: the whole body model ----------------------------------
	vec3 opposing = vec3(1.0) - absorption_color;
	float depth_blend = clamp(vertical_depth / max(depth_distance, 0.001), 0.0, 1.0);
	depth_blend = 1.0 - exp(-depth_blend * beers_law);
	vec3 color = clamp(behind - absorption_color * depth_blend, vec3(0.0), vec3(1.0));
	color = mix(color, opposing, depth_blend * depth_blend);
	// 深度压暗：吸收只管色相，亮度还得单独压，否则深海和浅滩一样亮。
	color *= mix(1.0, deep_darkness, depth_blend);

	// ---- fresnel -----------------------------------------------------------
	float fresnel_value = pow(clamp(1.0 - normal_view, 0.0, 1.0), max(fresnel_radius, 0.001));
	color = mix(color, fresnel_color, clamp(fresnel_value * fresnel_strength, 0.0, 1.0));

	if (sun_highlight_strength > 0.0) {
		color += sun_color * sun_lobe(normal, to_eye, normal_view) * sun_highlight_strength;
	}

	// ---- caustics, only where the water is shallow -------------------------
	if (caustics_enabled && caustic_strength > 0.0 && caustic_range > 0.0) {
		float range_mod = 1.0 - smoothstep(caustic_range * 0.5, caustic_range, vertical_depth);
		if (range_mod > 0.001) {
			color += caustic_net(p, u_time) * caustic_strength * (1.0 - depth_blend) * range_mod;
		}
	}

	color = clamp(color, vec3(0.0), vec3(1.0));

	// ---- edge foam: the reference's `edge_thickness` band -------------------
	float edge_mask = 0.0;
	if (edge_strength > 0.0 && edge_thickness > 0.0) {
		float edge_blend = clamp(1.0 - vertical_depth / edge_thickness, 0.0, 1.0);
		if (edge_blend > 0.001) {
			vec2 euv = p * edge_noise_scale + vec2(u_time * edge_speed * 0.35, -u_time * edge_speed * 0.22);
			float n = noise(euv) * 0.62 + noise(euv * 2.7 + vec2(3.1, 1.7)) * 0.38;
			// The closer to the solid, the more of the noise passes the threshold.
			float ramp = smoothstep(0.30, 0.75 - edge_blend * 0.35, n);
			edge_mask = clamp(ramp * edge_blend * edge_strength, 0.0, 1.0);
		}
	}
	color = mix(color, edge_color, edge_mask);

	// ---- shoreline band ----------------------------------------------------
	vec2 shore = shoreline_data(p);
	if (shore_foam_strength > 0.0 && shore_foam_width > 0.0) {
		float band = 1.0 - smoothstep(0.0, shore_foam_width, shore.x);
		float n = noise(p * 2.1 + vec2(u_time * 0.15, -u_time * 0.11));
		float mask = clamp(band * band * (0.55 + 0.45 * n) * shore_foam_strength, 0.0, 1.0);
		color = mix(color, shore_foam_color, mask);
	}

	color = mix(color, edge_color, clamp(ring * ripple_ring_strength, 0.0, 1.0));

	// Albedo stays zero so no light can reach the surface: the absorbed screen
	// colour is the whole shading model. Emission carries it.
	ALBEDO = vec3(0.0);
	vec3 emission = color * exposure_comp * emission_gain;
	// Static interleaved gradient noise: an animated dither boils in motion.
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	emission += (ign - 0.5) * 0.0045 * dither_strength;
	EMISSION = emission;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
