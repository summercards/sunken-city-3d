shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, world_vertex_coords;
#include "res://shaders/vegetation/wind.gdshaderinc"
uniform sampler2D botanical_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool moss_layer = false;
uniform float atlas_row = 0.0;
uniform float wind_displacement = 0.055;
uniform vec3 tint : source_color = vec3(0.87,0.97,0.82);
varying vec2 atlas_uv;
varying float root_shade;
varying float patch_variation;
varying float canopy_distance;
varying float wind_band;
void vertex() {
	vec3 pivot=MODEL_MATRIX[3].xyz;
	float phase=INSTANCE_CUSTOM.x*6.2831853;
	float travel=dot(pivot.xz,vegetation_direction)*0.65;
	float t=vegetation_time;
	float gust=pow(0.5+0.5*sin(travel-t*1.8),2.0);
	float weight=COLOR.r;
	float movement=min(0.44,wind_displacement*vegetation_strength)*weight*weight;
	float flex=0.20+gust*1.05+sin(t*2.3+phase)*0.10;
	VERTEX.xz+=vegetation_direction*movement*flex;
	VERTEX.xz+=vec2(-vegetation_direction.y,vegetation_direction.x)*sin(t*3.1+phase+UV.x*1.7)*movement*0.10;
	VERTEX.y-=movement*flex*0.14;
	// A soft upwards canopy normal avoids dark intersecting card seams.
	NORMAL=normalize(mix(NORMAL,vec3(0.0,1.0,0.0),moss_layer ? 0.95 : 0.87));
	NORMAL=normalize(NORMAL+vec3(-vegetation_direction.x,0.0,-vegetation_direction.y)*movement*flex*0.8);
	atlas_uv=UV*0.5+vec2(INSTANCE_CUSTOM.y<0.5 ? 0.0 : 0.5,moss_layer ? 0.5 : atlas_row);
	root_shade=moss_layer ? 1.0 : mix(0.70,1.0,smoothstep(0.0,0.55,COLOR.r));
	patch_variation=mix(0.94,1.04,INSTANCE_CUSTOM.y);
	canopy_distance=distance(CAMERA_POSITION_WORLD,pivot);
	wind_band=gust;
}
void fragment() {
	vec4 tex=texture(botanical_atlas,atlas_uv);
	vec3 painted=tex.rgb*tint*root_shade*patch_variation;
	// Keep the readable canopy color when a whole fan is only a few pixels wide.
	// Close views retain the original painted veins and softly shaded roots.
	float distant=smoothstep(3.0,14.0,canopy_distance);
	vec3 canopy=moss_layer ? vec3(0.12,0.26,0.055) : vec3(0.22,0.36,0.10);
	ALBEDO=mix(painted,canopy*patch_variation,distant*0.65);
	// Broad light response reinforces the same traveling bend in distant views.
	ALBEDO*=1.0-(moss_layer ? 0.0 : 0.06)*wind_band;
	ALPHA=tex.a;
	ALPHA_SCISSOR_THRESHOLD=0.38;
	ROUGHNESS=1.0;
	SPECULAR=0.0;
	BACKLIGHT=ALBEDO*0.18;
}
