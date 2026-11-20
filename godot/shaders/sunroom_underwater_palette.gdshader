shader_type spatial;
// 保留原调色板与 PBR；只在受日照的表面加投影焦散，不把水体染色写入材质。
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform bool has_palette = true;
uniform bool vertex_color = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float caustic_gain : hint_range(0.0, 2.0) = 0.24;
uniform float elapsed = 0.0;
uniform float saturation_gain : hint_range(0.0, 2.0) = 1.0;
varying vec3 world_position;
varying vec3 world_normal;
varying vec4 mesh_color;
void vertex() {
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 mesh_color=COLOR;
}
void fragment() {
 vec3 original=base_color.rgb;
 if(has_palette) { original*=texture(palette,UV).rgb; }
 if(vertex_color) { original*=mesh_color.rgb; }
 float depth=max(0.0,water_level-world_position.y);
 float luminance=dot(original,vec3(0.2126,0.7152,0.0722));
 vec3 saturated=mix(vec3(luminance),original,saturation_gain);
 ALBEDO=saturated;
 ROUGHNESS=roughness_value;
 METALLIC=metallic_value;
 SPECULAR=0.5;
 // Back-project to the same waterline and refracted sun as the shafts.
 vec3 toward_sun = region_refracted_sun();
 vec2 p = region_sun_footprint(world_position, toward_sun) * 1.35;
 vec2 warp = vec2(sin(p.y * 1.12 - elapsed * 0.50), cos(p.x * 0.77 + elapsed * 0.44));
 p += warp * 0.71;
 float a = cos(dot(p, vec2(1.0, 0.39)) + elapsed * 0.32);
 float b = cos(dot(p, vec2(-0.44, 1.25)) - elapsed * 0.27);
 float c = cos(dot(p, vec2(0.56, 1.64)) + elapsed * 0.17);
 float ridge = abs(a + b + c * 0.65 - 0.38);
 float pixel_span = length(dFdx(p)) + length(dFdy(p));
 float detail = 1.0 - smoothstep(0.20, 0.85, pixel_span);
 float ink = 1.0 - smoothstep(0.045, 0.23, ridge);
 float incidence = max(dot(normalize(world_normal), toward_sun), 0.0);
 float solar_path = depth / toward_sun.y;
 float daylight = sun_strength * smoothstep(0.01, 0.20, sun_direction.y);
 float shallow = exp(-solar_path * 0.042) * (1.0 - smoothstep(44.0, 72.0, depth));
 float submerged = smoothstep(0.08, 0.60, water_level - world_position.y);
 EMISSION = saturated * vec3(0.56, 0.91, 1.0) * sun_color * ink * detail * incidence
     * shallow * submerged * daylight * caustic_gain;
}
