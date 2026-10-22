// Displaced stylized ocean. Real scene lights/shadows, sky reflection and depth absorption.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/ocean_waves.gdshaderinc"
#include "res://shaders/ocean_wake.gdshaderinc"
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float water_level = 1.12;
uniform vec3 deep_color : source_color = vec3(0.035, 0.38, 0.49);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.64, 0.58);
uniform vec3 absorption = vec3(0.32, 0.14, 0.085);
uniform float water_roughness : hint_range(0.05,0.8) = 0.17;
uniform float u_reverse_z = 1.0;
uniform vec4 u_ripples[8];
uniform int u_ripple_count = 0;
varying vec3 v_world;
varying vec2 wake_slope;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
#include "res://shaders/ocean_foam.gdshaderinc"
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
	// Two-dimensional micro ripples, rather than two infinite sine gratings.
	vec2 micro_p = p * 1.9 + vec2(-0.12, 0.09) * u_time;
	float micro = noise(micro_p);
	float detail = 1.0 - smoothstep(35.0, 110.0, length(VERTEX));
	slope += vec2(noise(micro_p + vec2(0.08, 0.0)) - micro,
		noise(micro_p + vec2(0.0, 0.08)) - micro) * 0.35 * detail;
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
	vec3 normal=normalize(vec3(-slope.x,1.0,-slope.y));
	NORMAL=normalize((VIEW_MATRIX*vec4(normal,0.0)).xyz);
	float water_depth=-VERTEX.z;
	float raw=textureLod(depth_tex,SCREEN_UV,0.0).r;
	vec3 bed_view=view_position(SCREEN_UV,raw,INV_PROJECTION_MATRIX);
	float thickness=clamp(-bed_view.z-water_depth,0.0,60.0);
	vec3 bed=(INV_VIEW_MATRIX*vec4(bed_view,1.0)).xyz;
	float depth=max(0.0,v_world.y-bed.y);
	if(thickness>59.0) depth=60.0;
	vec2 view_slope=(VIEW_MATRIX*vec4(slope.x,0.0,slope.y,0.0)).xy;
	vec2 refract_uv=clamp(SCREEN_UV+view_slope*(28.0/VIEWPORT_SIZE)*smoothstep(0.0,1.5,thickness),vec2(0.001),vec2(0.999));
	vec3 ref_view=view_position(refract_uv,textureLod(depth_tex,refract_uv,0.0).r,INV_PROJECTION_MATRIX);
	if(-ref_view.z<water_depth+0.05) refract_uv=SCREEN_UV;
	vec3 submerged=textureLod(screen_tex,refract_uv,0.0).rgb;
	vec3 transmission=exp(-thickness*absorption);
	transmission*=1.0-smoothstep(5.0,20.0,depth);
	if(thickness>59.0) transmission=vec3(0.0);
	float deep=smoothstep(0.6,12.0,depth);
	vec3 body=mix(shallow_color,deep_color,deep);
	// Transmission is already lit in screen_tex; do not light it a second time.
	// Water-air IOR 1.333 gives F0 = 0.02037 (Godot SPECULAR: F0=0.08*s).
	float facing = clamp(dot(normal, normalize(CAMERA_POSITION_WORLD - v_world)), 0.0, 1.0);
	float fresnel = 0.02037 + 0.97963 * pow(1.0 - facing, 5.0);
	float shore_d = shoreline_distance(p);
	float foam = max(shore_foam(p, shore_d), crest_foam(p, shore_d));
	// Depth contact follows moving hulls and other geometry at the current frame.
	float contact_aa = clamp(fwidth(thickness), 0.02, 0.06);
	float hull_contact = (1.0 - smoothstep(0.035, 0.11 + contact_aa, thickness))
		* foam_grain(p, 0.3) * 0.60 * (1.0 - smoothstep(3.0, 4.0, length(p - u_boat.xy)))
		* step(water_depth, -bed_view.z);
	foam = max(foam, hull_contact);
	vec3 trail = wake_profile(p);
	trail.x += (noise(p * 1.15 + vec2(u_time * 0.07, 0.0)) - 0.5) * (0.14 + trail.y * 0.025);
	float trail_width = 0.035 + trail.y * 0.006;
	float trail_line = 1.0 - smoothstep(trail_width, trail_width + clamp(fwidth(trail.x), 0.025, 0.09), abs(trail.x));
	float trail_break = smoothstep(0.17 + trail.y * 0.045, 0.44 + trail.y * 0.045, noise(p * 2.1 + u_time * 0.07));
	foam = max(foam, trail_line * trail.z * trail_break * foam_grain(p, trail.y / 9.0) * 0.68);
	foam = clamp(foam, 0.0, 0.95);
	ALBEDO = body * (vec3(1.0) - transmission) * 0.72;
	EMISSION = submerged * transmission * (1.0 - fresnel);
	ALBEDO = mix(ALBEDO, foam_color, foam);
	EMISSION *= 1.0 - foam;
	ROUGHNESS = mix(water_roughness, 0.64, foam);
	SPECULAR = 0.2546;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
