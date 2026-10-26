shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float roughness_value = 0.62;
uniform float metallic_value = 0.0;
uniform float emission_value = 0.0;
uniform bool grid_role = false;
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
 ROUGHNESS=roughness_value;METALLIC=metallic_value;SPECULAR=0.25;
 EMISSION=base*emission_value;
 ALPHA=0.81;
}
