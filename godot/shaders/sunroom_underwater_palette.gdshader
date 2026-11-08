shader_type spatial;
// 本地包装：保留原调色板与 PBR 角色，只补一层移动焦散。
// 旧九图不做逐材质深度染色（深度衰减全部交给统一水雾通道），这里也去掉，
// 否则会在指数雾之上再压一层青色，画面比参考图更闷。
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform bool has_palette = true;
uniform bool vertex_color = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float water_level = 101.587442;
uniform float sun_strength : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_gain : hint_range(0.0, 2.0) = 0.075;
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
 // 与 uw_common 的 uw_emission 同一条公式：焦散网纹按世界 XZ 投影，浅水区朝上的面最亮。
 vec2 p=world_position.xz*0.85+world_position.y*0.2;
 p+=vec2(sin(p.y+TIME*0.40),cos(p.x-TIME*0.32))*0.38;
 float net=abs(sin(p.x*2.1+sin(p.y*1.8)+TIME*0.48)+sin(p.y*2.2-TIME*0.37));
 float light=(1.0-smoothstep(0.035,0.16,net))*0.24;
 float shallow=1.0-smoothstep(12.0,55.0,depth);
 EMISSION=saturated*vec3(0.45,1.0,0.88)*light*shallow*caustic_gain*sun_strength;
}
