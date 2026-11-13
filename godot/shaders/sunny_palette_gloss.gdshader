shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float roughness_value = 0.62;
uniform float metallic_value = 0.0;
uniform float emission_value = 0.0;
// 玻璃的透光率与压色。默认 0.81 / 纯白 = 室外玻璃原样（太阳房、前厅外框都不动）；
// 室内房间的窗与前厅玻璃用另一个实例（alpha 更低、偏冷灰），
// 因为房间外面是黑的 —— 玻璃若还留着 sky 蓝，就还是「看得到天」的读法。
uniform float alpha_value = 0.81;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 室内玻璃：玻璃后面什么都没有（房间是室内），所以不能再用色盘里的 ice 格
// 去乘天空环境光 —— 那样白天就是一格浅蓝的「天空」。置 true 时颜色固定取
// tint，只留高光。室外玻璃（太阳房、前厅外框）保持 false，一点不变。
uniform bool interior_glass = false;
uniform bool grid_role = false;
uniform bool home_window = false;
uniform bool home_window_recessed = false;
varying vec3 home_local;
void vertex() { home_local = VERTEX; }
uniform int home_window_column = 3;
instance uniform int sea_material_role = 2;
instance uniform vec4 sea_gloss_controls = vec4(-1.0, -1.0, -1.0, -1.0);
instance uniform float sea_gloss_emission_energy = -1.0;
global uniform float world_home_lights;
vec3 rgb2hsv(vec3 c) {
 vec4 K=vec4(0.0,-1.0/3.0,2.0/3.0,-1.0);
 vec4 p=mix(vec4(c.bg,K.wz),vec4(c.gb,K.xy),step(c.b,c.g));
 vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
 float d=q.x-min(q.w,q.y);float e=1e-10;
 return vec3(abs(q.z+(q.w-q.y)/(6.0*d+e)),d/(q.x+e),q.x);
}
vec3 hsv2rgb(vec3 c) {
 vec3 p=abs(fract(c.xxx+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);
 return c.z*mix(vec3(1.0),clamp(p-1.0,0.0,1.0),c.y);
}
void fragment() {
 float sea_roughness = sea_gloss_controls.x >= 0.0 ? sea_gloss_controls.x : roughness_value;
 float sea_metallic = sea_gloss_controls.y >= 0.0 ? sea_gloss_controls.y : metallic_value;
 float sea_specular = sea_gloss_controls.z >= 0.0 ? sea_gloss_controls.z : 0.25;
 float sea_alpha = sea_gloss_controls.w >= 0.0 ? sea_gloss_controls.w : alpha_value;
 float sea_emission = sea_gloss_emission_energy >= 0.0 ? sea_gloss_emission_energy : emission_value;
 vec3 base=texture(palette,UV).rgb;
 vec3 hsv=rgb2hsv(base);
 bool solar=ivec2(floor(UV*8.0))==ivec2(5,2);
 hsv.x=fract(hsv.x+(solar?0.02:0.0));
 hsv.y=clamp(hsv.y*(solar?0.94:1.12),0.0,1.0);
 hsv.z*=solar&&grid_role?1.30:1.0;
 ALBEDO=hsv2rgb(hsv);
 if (ivec2(floor(UV*8.0))==ivec2(5,5)) {
  vec3 wine=rgb2hsv(ALBEDO);wine.x=fract(wine.x+0.067);wine.y*=0.95;wine.z*=0.75;
  ALBEDO=hsv2rgb(wine);
 }
 ROUGHNESS=sea_roughness;METALLIC=sea_metallic;SPECULAR=sea_specular;
 EMISSION=mix(base,vec3(0.55,0.24,0.055),world_home_lights)*sea_emission;
 if (home_window && ivec2(floor(UV*8.0))==ivec2(home_window_column,2)
  && (!home_window_recessed || (home_local.z < -0.006 && home_local.z > -0.043))) {
  ALBEDO=mix(ALBEDO,vec3(1.0,0.58,0.19),world_home_lights);
  EMISSION+=vec3(0.42,0.16,0.025)*world_home_lights;
 }
 if (interior_glass) {
  ALBEDO=tint.rgb;
  ROUGHNESS=sea_roughness;
  SPECULAR=sea_specular;
 } else {
  ALBEDO*=tint.rgb;
 }
 ALPHA=sea_alpha;
}
