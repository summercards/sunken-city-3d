#include "res://shaders/uw_water_color.gdshaderinc"
uniform float region_view_depth = 10.0;
vec3 region_water_display(vec3 direction) {
 float deep=smoothstep(14.0,60.0,region_view_depth);
 vec3 high=mix(vec3(0.18,0.72,0.70),vec3(0.075,0.41,0.53),deep);
 vec3 low=mix(vec3(0.025,0.30,0.49),vec3(0.012,0.15,0.30),deep);
 return mix(low,high,smoothstep(-0.62,0.38,direction.y));
}
float region_fog_amount(float distance_m,vec2 world_xz) {
 float distant=pow(smoothstep(6.0,110.0,distance_m),1.3);
 // Hide the finite original heightmap before its literal outer row. This is
 // visual-only absorption, not a smaller movement region or a new terrain.
 float edge=smoothstep(448.0,500.0,max(abs(world_xz.x),abs(world_xz.y)));
 return max(distant,edge);
}
