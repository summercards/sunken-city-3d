// WindData v1: COLOR.r=root/tip bend, g=leaf flex, b=leaf phase, a=AO.
// World direction is coherent across rotated/scaled instances. Base remains fixed.
global uniform float vegetation_time;
global uniform float vegetation_strength;
global uniform vec2 vegetation_direction;
vec3 vegetation_rotate(vec3 p, vec3 axis, float angle) {
	float c=cos(angle); float s=sin(angle);
	return p*c+cross(axis,p)*s+axis*dot(axis,p)*(1.0-c);
}
float vegetation_angle(vec3 root, vec4 weights, float phase, float amplitude) {
	float t=vegetation_time;
	float travel=dot(root.xz,vegetation_direction)*0.24;
	float gust=0.55+0.30*sin(travel-t*1.12)+0.15*sin(travel*0.49-t*0.63);
	float main_wave=0.55+0.45*sin(t*1.8+phase*6.283+travel*0.3);
	float detail=sin(t*3.8+weights.b*6.283+phase*4.0)*0.12*weights.g;
	return vegetation_strength*amplitude*(weights.r*weights.r*(0.32+gust*main_wave)+detail*weights.r);
}
