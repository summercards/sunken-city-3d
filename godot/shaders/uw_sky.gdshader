shader_type sky;
// 水下背景：网页版用屏幕空间上下渐变，这里按视线高度做同样的青→深蓝。
uniform float deep : hint_range(0.0, 1.0) = 0.0;

void sky() {
	float sy = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	// 网页版这两个值是色调映射后的 sRGB，天空输出的是线性色，先平方近似转换。
	vec3 top = mix(vec3(0.12, 0.91, 0.87), vec3(0.025, 0.28, 0.49), deep);
	vec3 bottom = mix(vec3(0.025, 0.36, 0.62), vec3(0.008, 0.07, 0.20), deep);
	vec3 c = mix(bottom, top, pow(sy, 0.8));
	COLOR = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
