// Stylized ocean surface.
// Depth absorption follows Beer-Lambert with a normalized curve (depth_distance / beers_law),
// so the water body saturates smoothly instead of being cut off at a hard distance.
// Reference model: godotshaders.com/shader/absorption-based-stylized-water
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/ocean_wake.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float water_level = 1.12;
uniform float u_reverse_z = 1.0;
uniform vec4 u_ripples[8];
uniform int u_ripple_count = 0;

group_uniforms color;
uniform vec3 shallow_color : source_color = vec3(0.10, 0.62, 0.58);
uniform vec3 deep_color : source_color = vec3(0.015, 0.285, 0.445);
// Absorbed colour per metre: red vanishes first, blue last. The remaining
// transmitted colour is what the seabed is seen through.
uniform vec3 absorption = vec3(0.34, 0.15, 0.075);
// Column depth that counts as "open sea"; beers_law shapes how fast it saturates.
uniform float depth_distance : hint_range(1.0, 60.0, 0.5) = 26.0;
uniform float beers_law : hint_range(0.5, 12.0, 0.1) = 4.2;
uniform float body_gain : hint_range(0.0, 1.5, 0.01) = 0.72;

group_uniforms surface;
uniform float water_roughness : hint_range(0.02, 0.8, 0.01) = 0.13;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.2546;
// Grazing sky tint. Smaller fresnel_radius packs the band closer to the horizon.
uniform vec3 fresnel_color : source_color = vec3(0.44, 0.74, 0.86);
uniform float fresnel_radius : hint_range(0.5, 8.0, 0.01) = 3.6;
uniform float fresnel_gain : hint_range(0.0, 1.5, 0.01) = 0.30;
uniform float refraction_strength : hint_range(0.0, 80.0, 0.5) = 32.0;
// How much of the ripple slope reaches the lit normal. At 1.0 every chop gets a
// real diffuse highlight and the surface reads photographic; the reference look
// keeps the water closer to flat-shaded and lets the painted waterline carry the
// shape. Refraction and reflection still use the full slope.
uniform float normal_lighting : hint_range(0.0, 1.0, 0.01) = 0.55;

group_uniforms detail;
uniform float detail_broad : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform float detail_mid : hint_range(0.0, 1.0, 0.01) = 0.58;
uniform float detail_fine : hint_range(0.0, 1.0, 0.01) = 0.24;

group_uniforms reflections;
uniform float ssr_mix : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float ssr_travel : hint_range(0.0, 200.0, 1.0) = 60.0;

varying vec3 v_world;
varying vec2 wake_slope;

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

// One anisotropic ripple layer: ridges run across `wind`, amplitude in metres.
void add_ripple(vec2 p, vec2 wind, float along_k, float across_k, float speed, float amp, float fade, inout vec2 slope) {
	vec2 across = vec2(-wind.y, wind.x);
	vec2 q = vec2(dot(p, wind) * along_k, dot(p, across) * across_k) + wind * (u_time * speed);
	vec3 g = noise_grad(q);
	slope += (wind * (g.y * along_k) + across * (g.z * across_k)) * (amp * fade);
}

vec3 view_position(vec2 uv,float raw,mat4 inverse_projection) {
	float z=u_reverse_z>0.5?raw:raw*2.0-1.0;
	vec4 v=inverse_projection*vec4(uv*2.0-1.0,z,1.0);
	return v.xyz/v.w;
}

void vertex() {
	v_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec2 p = v_world.xz;
	float wake_height = wake_sample(p);
	wake_slope = vec2(wake_sample(p + vec2(0.12, 0.0)) - wake_sample(p - vec2(0.12, 0.0)),
		wake_sample(p + vec2(0.0, 0.12)) - wake_sample(p - vec2(0.0, 0.12))) / 0.24;
	VERTEX.y += ocean_sample(p).x + bow_height(p) + wake_height + shore_height(p);
	v_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec2 p=v_world.xz;
	vec3 wave=ocean_sample(p);
	vec2 slope=wave.yz + wake_slope;
	slope += vec2(shore_height(p + vec2(0.10, 0.0)) - shore_height(p - vec2(0.10, 0.0)),
		shore_height(p + vec2(0.0, 0.10)) - shore_height(p - vec2(0.0, 0.10))) / 0.20;
	// Ripple octaves stretched across the wind, the way wind chop actually
	// forms: ridges run perpendicular to travel, not as round blobs.
	// Kept to two broad bands on purpose. Three finely-tuned octaves gave a
	// continuous light gradient across the whole surface, which reads as
	// photographic water; the stylised look wants a few large facets instead.
	// Fine detail fades much earlier so it cannot alias into sparkle.
	float view_dist = length(VERTEX);
	float fade_mid = 1.0 - smoothstep(70.0, 200.0, view_dist);
	float fade_fine = 1.0 - smoothstep(14.0, 46.0, view_dist);
	add_ripple(p, normalize(vec2(0.94, 0.34)), 0.52, 0.26, 0.08, detail_broad * 0.30, 1.0, slope);
	add_ripple(p, normalize(vec2(0.80, 0.60)), 1.30, 0.79, 0.30, detail_mid * 0.051, fade_mid, slope);
	add_ripple(p, normalize(vec2(0.99, 0.10)), 5.00, 3.50, 0.85, detail_fine * 0.0165, fade_fine, slope);
	slope += vec2(bow_height(p+vec2(0.08,0))-bow_height(p-vec2(0.08,0)),
		bow_height(p+vec2(0,0.08))-bow_height(p-vec2(0,0.08)))/0.16;
	for(int i=0;i<8;i++) {
		if(i>=u_ripple_count) break;
		vec4 rp=u_ripples[i]; float age=u_time-rp.z;
		if(age>0.0 && age<3.5) {
			vec2 rel=p-rp.xy; float dist=length(rel);
			float ring=dist-(0.15+age*0.9);
			float env=exp(-ring*ring*18.0)*(1.0-age/3.5)*rp.w;
			slope += rel/max(dist,0.01)*cos(ring*14.0)*env*0.055;
		}
	}
	vec3 normal=normalize(vec3(-slope.x*normal_lighting,1.0,-slope.y*normal_lighting));
	NORMAL=normalize((VIEW_MATRIX*vec4(normal,0.0)).xyz);
	// Composed slope magnitude: the crests the eye can see, swell + chop + wake.
	float steep = length(slope);

	// Water column under this pixel, in metres.
	float water_depth=-VERTEX.z;
	float raw=textureLod(depth_tex,SCREEN_UV,0.0).r;
	vec3 bed_view=view_position(SCREEN_UV,raw,INV_PROJECTION_MATRIX);
	float thickness=clamp(-bed_view.z-water_depth,0.0,60.0);
	vec3 bed=(INV_VIEW_MATRIX*vec4(bed_view,1.0)).xyz;
	float depth=max(0.0,v_world.y-bed.y);
	bool open_sea = thickness>59.0;
	if(open_sea) depth=60.0;

	// Normalized depth: 0 at the surface, 1 at depth_distance, then Beer-Lambert.
	float depth_n=clamp(depth/max(depth_distance,0.01),0.0,1.0);
	float depth_blend=1.0-exp(-depth_n*beers_law);

	vec2 view_slope=(VIEW_MATRIX*vec4(slope.x,0.0,slope.y,0.0)).xy;
	vec2 refract_uv=clamp(SCREEN_UV+view_slope*(refraction_strength/VIEWPORT_SIZE)*smoothstep(0.0,1.5,thickness),vec2(0.001),vec2(0.999));
	vec3 ref_view=view_position(refract_uv,textureLod(depth_tex,refract_uv,0.0).r,INV_PROJECTION_MATRIX);
	if(-ref_view.z<water_depth+0.05) refract_uv=SCREEN_UV;
	vec3 submerged=textureLod(screen_tex,refract_uv,0.0).rgb;

	// Beer-Lambert over the actual view path; the bed also fades out on the
	// same normalized curve, so deep water dissolves into the body colour.
	vec3 transmission=exp(-thickness*absorption);
	transmission*=1.0-smoothstep(0.72,1.0,depth_n);
	if(open_sea) transmission=vec3(0.0);
	vec3 body=mix(shallow_color,deep_color,depth_blend);

	// Water-air IOR 1.333 gives F0 = 0.02037 (Godot SPECULAR: F0=0.08*s).
	vec3 to_eye=normalize(CAMERA_POSITION_WORLD-v_world);
	float facing = clamp(dot(normal, to_eye), 0.0, 1.0);
	float schlick = 0.02037 + 0.97963 * pow(1.0 - facing, 5.0);
	float fres_wide = pow(1.0 - facing, fresnel_radius);

	float shore_d = shoreline_distance(p);
	float foam = max(shore_foam(p, shore_d), crest_foam(p, shore_d, view_dist, wave.x));
	// One crisp rim along every waterline: hulls, platforms, drowned walls.
	// Two sources because a top-down camera sees the metric shoreline contour
	// far better than a view-space depth band.
	float rim = max(contact_edge(p, thickness, view_dist), shore_rim(p, thickness));
	vec3 trail = wake_profile(p);
	trail.x += (noise(p * 1.15 + vec2(u_time * 0.07, 0.0)) - 0.5) * (0.14 + trail.y * 0.025);
	float trail_width = 0.035 + trail.y * 0.006;
	float trail_line = 1.0 - smoothstep(trail_width, trail_width + clamp(fwidth(trail.x), 0.025, 0.09), abs(trail.x));
	float trail_break = smoothstep(0.17 + trail.y * 0.045, 0.44 + trail.y * 0.045, noise(p * 2.1 + u_time * 0.07));
	foam = max(foam, trail_line * trail.z * trail_break * foam_grain(p, trail.y / 9.0) * 0.68);
	foam = clamp(foam, 0.0, 0.95);

	ALBEDO = body * (vec3(1.0) - transmission) * body_gain;
	EMISSION = submerged * transmission * (1.0 - schlick);
	EMISSION += fresnel_color * fres_wide * fresnel_gain;

	// Screen-space reflections: sky-only environment misses the harbour walls,
	// so trace the opaque colour buffer along the reflected view ray.
	vec3 reflection = vec3(0.0);
	float reflection_hit = 0.0;
	if (ssr_mix > 0.001) {
		vec3 view_normal = normalize(NORMAL);
		vec3 ray = reflect(-VIEW, view_normal);
		float step_len = 0.55;
		float travel = 0.0;
		vec3 probe = VERTEX;
		for (int i = 0; i < 18; i++) {
			probe += ray * step_len;
			travel += step_len;
			if (travel > ssr_travel) break;
			vec4 clip = PROJECTION_MATRIX * vec4(probe, 1.0);
			vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
			if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
			vec3 scene_view = view_position(uv, textureLod(depth_tex, uv, 0.0).r, INV_PROJECTION_MATRIX);
			float gap = scene_view.z - probe.z;
			if (gap > 0.0 && gap < step_len * 2.2) {
				vec2 edge = min(uv, vec2(1.0) - uv);
				reflection_hit = clamp(min(edge.x, edge.y) * 12.0, 0.0, 1.0)
					* (1.0 - smoothstep(0.6, 1.0, travel / max(ssr_travel, 1.0)));
				reflection = textureLod(screen_tex, uv, 1.0).rgb;
				break;
			}
			step_len *= 1.18;
		}
	}
	// Reflections only belong at grazing angles: from the default top-down camera
	// the reflected ray dives under the platforms and returns a flat, blurred
	// white slab that reads as fog lying on the water. Gate on the same grazing
	// term the sky tint uses, so up close the surface keeps its own colour.
	float ssr_grazing = smoothstep(0.06, 0.42, fres_wide);
	// Foam suppresses this later (EMISSION *= 1 - foam); do not attenuate twice.
	EMISSION += reflection * reflection_hit * ssr_mix * ssr_grazing;

	ALBEDO = mix(ALBEDO, foam_color, foam);
	// Lit foam turns grey once the sun leaves it. The reference paints white
	// straight in, so keep a floor of brightness instead of killing emission.
	EMISSION *= 1.0 - foam * 0.90;
	EMISSION = mix(EMISSION, vec3(0.88, 0.96, 0.95), foam * 0.42);
	// Stylized rim: painted white, not lit white.
	ALBEDO = mix(ALBEDO, vec3(1.0), rim * 0.92);
	EMISSION = mix(EMISSION, vec3(0.86, 0.97, 0.96), rim * 0.55);
	ROUGHNESS = mix(mix(water_roughness, 0.64, foam), 0.42, rim);
	SPECULAR = specular_strength;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
