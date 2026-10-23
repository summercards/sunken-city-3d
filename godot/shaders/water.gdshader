// Stylized ocean surface — ported from the browser build's water.js.
//
// The web version paints the surface instead of lighting it: a depth-weighted
// blend of the refracted scene and a flat two-colour body, then a fresnel tint,
// a few additive painterly facets and hard white foam. Nothing is shaded by the
// sun or the ambient, which is why its water reads as one flat turquoise sheet
// while a lit material picks up a bright rim, a vertical gradient and specular
// smudges that the web version simply does not have.
//
// So this shader writes the composed colour straight into EMISSION with a zero
// albedo. Keep it that way: anything that reintroduces lighting (albedo > 0,
// specular > 0) will drift away from the browser look again.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/ocean_wake.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float water_level = 1.12;
uniform float u_reverse_z = 1.0;
uniform vec4 u_ripples[8];
uniform int u_ripple_count = 0;

group_uniforms color;
// Straight from water.js: `body=mix(vec3(.008,.30,.25), vec3(.008,.125,.24), deep)`.
// Linear values, no red at all — the browser water is a cyan with the red channel
// absorbed away, which is what makes it look like water instead of blue paint.
uniform vec3 body_shallow = vec3(0.008, 0.300, 0.250);
uniform vec3 body_deep = vec3(0.008, 0.125, 0.240);
// Where the body has fully turned into `body_deep`, in metres of water column.
uniform float depth_near : hint_range(0.0, 20.0, 0.1) = 2.0;
uniform float depth_far : hint_range(1.0, 40.0, 0.1) = 13.0;
// Per-metre absorption (water.js: vec3(.125,.064,.046)). Much gentler than the
// previous 0.34/0.15/0.075, which is what kept the drowned blocks readable.
uniform vec3 absorption = vec3(0.125, 0.064, 0.046);
// How fast the seabed stops being visible with depth.
uniform float transmission_near : hint_range(0.0, 20.0, 0.1) = 4.0;
uniform float transmission_far : hint_range(1.0, 40.0, 0.1) = 13.0;
// Strength of the painterly variation (swell shading, light facets, flecks).
uniform float surface_contrast : hint_range(0.0, 1.0, 0.01) = 0.25;
// The browser renders at exposure 1.1, this project at 1.63. ACES is what turns
// a linear colour into the final pixel, so the body has to be pre-scaled by the
// same ratio or the water comes out a stop too pale.
uniform float exposure_comp : hint_range(0.2, 2.5, 0.01) = 0.55;
// The gl_compatibility renderer (web export) resolves an emission-only surface far
// darker than Forward+ at the same input. render_flags.gd supplies the measured
// factor so both backends land on the same water colour.
uniform vec3 emission_gain = vec3(1.0);

group_uniforms surface;
// Grazing sky tint (water.js mixes toward vec3(.16,.39,.51) at fresnel*.65).
uniform vec3 fresnel_color = vec3(0.16, 0.39, 0.51);
uniform float fresnel_radius : hint_range(1.0, 8.0, 0.01) = 5.0;
uniform float fresnel_gain : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float refraction_strength : hint_range(0.0, 80.0, 0.5) = 26.0;
// How much of the ripple slope reaches the optical normal. The browser builds its
// normal from three low-frequency sines only, so this stays low on purpose:
// the surface is meant to read as a sheet with slow facets, not as chop.
uniform float normal_lighting : hint_range(0.0, 1.0, 0.01) = 0.40;

group_uniforms detail;
uniform float detail_broad : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform float detail_mid : hint_range(0.0, 1.0, 0.01) = 0.58;
uniform float detail_fine : hint_range(0.0, 1.0, 0.01) = 0.24;

group_uniforms reflections;
// The browser has no screen-space reflection at all. Left switchable, default off.
uniform float ssr_mix : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float ssr_travel : hint_range(0.0, 200.0, 1.0) = 60.0;

varying vec3 v_world;
varying vec2 wake_slope;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
// water.js `broad()`: three noise octaves, used for the swell and the facets.
float broad(vec2 p) { return noise(p)*0.65 + noise(p*2.03+13.2)*0.25 + noise(p*4.01)*0.1; }
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

	// Water column under this pixel, in metres.
	float water_depth=-VERTEX.z;
	float raw=textureLod(depth_tex,SCREEN_UV,0.0).r;
	vec3 bed_view=view_position(SCREEN_UV,raw,INV_PROJECTION_MATRIX);
	float thickness=clamp(-bed_view.z-water_depth,0.0,45.0);
	vec3 bed=(INV_VIEW_MATRIX*vec4(bed_view,1.0)).xyz;
	float depth=max(0.0,v_world.y-bed.y);
	bool open_sea = thickness>44.0;
	if(open_sea) depth=60.0;

	// Refraction fades out at the waterline and again once the bed is too far to
	// resolve; the browser tapers it over exactly this range.
	float refract_fade = smoothstep(0.15,2.5,thickness)*(1.0-smoothstep(24.0,45.0,thickness));
	vec2 view_slope=(VIEW_MATRIX*vec4(slope.x,0.0,slope.y,0.0)).xy;
	vec2 refract_uv=clamp(SCREEN_UV+view_slope*(refraction_strength/VIEWPORT_SIZE)*refract_fade,vec2(0.001),vec2(0.999));
	vec3 ref_view=view_position(refract_uv,textureLod(depth_tex,refract_uv,0.0).r,INV_PROJECTION_MATRIX);
	if(-ref_view.z<water_depth+0.08) refract_uv=SCREEN_UV;
	vec3 submerged=textureLod(screen_tex,refract_uv,0.0).rgb;
	// The bed that the caustics actually land on is the refracted one.
	vec3 caustic_bed=(INV_VIEW_MATRIX*vec4(view_position(refract_uv,textureLod(depth_tex,refract_uv,0.0).r,INV_PROJECTION_MATRIX),1.0)).xyz;

	// ---- body: flat two-colour water, modulated by moving swell -------------
	vec2 drift=vec2(u_time*0.032,-u_time*0.024);
	float swell=broad(p*0.12+drift);
	float wash=broad(p*0.25+vec2(-u_time*0.027,u_time*0.019));
	float deep=smoothstep(depth_near,depth_far,depth);
	vec3 body=mix(body_shallow,body_deep,deep);
	body*=1.0+(smoothstep(0.30,0.70,swell)-0.5)*0.17*surface_contrast;
	// Slow facets of light that follow the wave field instead of a texture.
	float a=dot(p,vec2(0.63,0.38))+u_time*0.72;
	float b=dot(p,vec2(-0.29,0.91))-u_time*0.56;
	float c=dot(p,vec2(1.41,-0.73))+u_time*0.93;
	float wave_light=smoothstep(0.10,0.85,sin(a)*0.45+sin(b)*0.35+sin(c)*0.20);
	body+=vec3(0.002,0.018,0.020)*wave_light*surface_contrast;
	vec2 wave_domain=p*0.27+vec2(sin(p.y*0.17+u_time*0.18),cos(p.x*0.13-u_time*0.14))*0.55;
	float facet=smoothstep(0.44,0.56,broad(wave_domain+drift));
	body+=vec3(0.002,0.036,0.034)*facet*surface_contrast;

	// ---- transmission: what is left of the drowned geometry ---------------
	vec3 transmission=exp(-thickness*absorption);
	transmission*=1.0-smoothstep(transmission_near,transmission_far,depth);
	if(open_sea) transmission=vec3(0.0);
	// Caustics sit on the submerged geometry, they are not painted on the surface.
	vec2 cp=caustic_bed.xz*0.80+vec2(sin(caustic_bed.z*0.32+u_time*0.6),cos(caustic_bed.x*0.28-u_time*0.5))*0.42;
	float cells=abs(sin(cp.x+u_time*0.30)*cos(cp.y-u_time*0.24));
	float caustic=(1.0-smoothstep(0.025,0.085,cells))*smoothstep(0.3,1.2,depth)*(1.0-smoothstep(3.0,15.0,depth));
	submerged+=vec3(0.025,0.12,0.10)*caustic;

	vec3 color=submerged*transmission+body*(1.0-transmission);

	// ---- grazing tint ----------------------------------------------------
	vec3 to_eye=normalize(CAMERA_POSITION_WORLD-v_world);
	float facing=clamp(dot(normal,to_eye),0.0,1.0);
	float fres=pow(1.0-facing,fresnel_radius);
	color=mix(color,fresnel_color,fres*fresnel_gain);

	// ---- sun sparkle and flecks -------------------------------------------
	vec3 half_light=normalize(to_eye+normalize(vec3(0.42,0.78,-0.46)));
	float sparkle=pow(max(dot(normal,half_light),0.0),650.0);
	color+=vec3(0.26,0.45,0.42)*sparkle*0.018*smoothstep(0.52,0.72,wash);
	float fleck=smoothstep(0.83,0.94,noise(p*1.25+drift*2.0))*smoothstep(0.55,0.74,swell);
	color+=vec3(0.025,0.055,0.052)*fleck*surface_contrast;

	// ---- painterly foam ---------------------------------------------------
	float shore_d=shoreline_distance(p);
	float foam=max(shore_foam(p,shore_d),crest_foam(p,shore_d,view_dist,wave.x));
	float rim=max(contact_edge(p,thickness,view_dist),shore_rim(p,thickness));
	vec3 trail=wake_profile(p);
	trail.x+=(noise(p*1.15+vec2(u_time*0.07,0.0))-0.5)*(0.14+trail.y*0.025);
	float trail_width=0.035+trail.y*0.006;
	float trail_line=1.0-smoothstep(trail_width,trail_width+clamp(fwidth(trail.x),0.025,0.09),abs(trail.x));
	float trail_break=smoothstep(0.17+trail.y*0.045,0.44+trail.y*0.045,noise(p*2.1+u_time*0.07));
	foam=max(foam,max(rim,trail_line*trail.z*trail_break*foam_grain(p,trail.y/9.0)*0.68));
	// water.js paints foam as flat near-white (vec3(.96,.985,1.0)).
	color=mix(color,vec3(0.96,0.985,1.0),clamp(foam,0.0,0.96));

	// Albedo stays zero so no light can reach the surface: the composed colour is
	// the whole shading model, exactly like water.js. Emission carries it. Do not
	// switch this to `render_mode unshaded` + ALBEDO — the gl_compatibility
	// renderer behind the web export composites that combination as pure black.
	ALBEDO=vec3(0.0);
	EMISSION=color*exposure_comp*emission_gain;
	SPECULAR=0.0;
	ROUGHNESS=1.0;
	METALLIC=0.0;
	ALPHA=1.0;
}
