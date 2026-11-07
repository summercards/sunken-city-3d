shader_type spatial;
// Local wrapper only: preserves original palette and PBR role, adds quiet moving
// caustics on upward surfaces. Engine depth fog owns the one common horizon.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform bool has_palette = true;
uniform bool vertex_color = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float caustic_gain = 0.075;
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
 float depth=max(0.0,1.12-world_position.y);
 vec3 absorb=mix(vec3(1.0),vec3(0.55,0.81,0.85),smoothstep(12.0,65.0,depth)*0.55);
 ALBEDO=original*absorb;
 ROUGHNESS=roughness_value;
 METALLIC=metallic_value;
 SPECULAR=0.35;
 vec2 p=world_position.xz*0.54+world_position.y*0.08;
 p+=vec2(sin(p.y*0.67+TIME*0.19),cos(p.x*0.71-TIME*0.14))*0.52;
 float net=abs(sin(p.x*2.1+sin(p.y*1.8)+TIME*0.30)+sin(p.y*2.2-TIME*0.24));
 float caustic=(1.0-smoothstep(0.035,0.18,net))*max(world_normal.y,0.0);
 float shallow=1.0-smoothstep(10.0,52.0,depth);
 EMISSION=original*vec3(0.58,0.94,0.83)*caustic*shallow*caustic_gain;
}
