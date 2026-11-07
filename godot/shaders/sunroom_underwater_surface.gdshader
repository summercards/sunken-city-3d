shader_type spatial;
// Same local waterline/extent; no fog bypass. At long distances the water ceiling
// meets exactly the environment's teal water, never a dark horizontal cut line.
render_mode cull_disabled, unshaded, depth_draw_opaque;
uniform float elapsed = 0.0;
float wave(vec2 p) {
 return sin(p.x*1.43+p.y*0.71+elapsed*0.32)*0.44
  +sin(p.x*-0.63+p.y*1.87-elapsed*0.23)*0.31
  +sin(p.x*2.79-p.y*1.31+sin(p.y*0.81)*0.8+elapsed*0.18)*0.16;
}
void fragment() {
 vec2 p=UV*190.0;
 vec2 warp=vec2(wave(p*0.41),wave(p.yx*0.37+vec2(5.1,2.7)));
 float line=pow(1.0-smoothstep(0.015,0.20,abs(wave(p+warp))),3.0);
 float broad=wave(p*0.19)*0.5+0.5;
 float near_fade=1.0-smoothstep(18.0,65.0,length(VERTEX));
 ALBEDO=mix(vec3(0.055,0.26,0.29),vec3(0.12,0.37,0.37),broad)+vec3(0.08,0.13,0.10)*line*near_fade*0.18;
}
