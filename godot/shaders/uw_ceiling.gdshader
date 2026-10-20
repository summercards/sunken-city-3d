shader_type spatial;
// 从水下仰视的水面：顶点起伏 + 菲涅尔 + 太阳反光。
render_mode unshaded, cull_disabled, fog_disabled;

varying vec3 v_world;

float uw_wave(vec2 p) {
	return sin(p.x * 0.72 + TIME * 0.85) * 0.10
		+ sin(p.y * 0.93 - TIME * 0.69) * 0.07
		+ sin((p.x + p.y) * 1.8 + TIME * 1.1) * 0.025;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w.y += uw_wave(w.xz);
	v_world = w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 slope = vec2(
		0.072 * cos(p.x * 0.72 + TIME * 0.85) + 0.045 * cos((p.x + p.y) * 1.8 + TIME * 1.1),
		0.065 * cos(p.y * 0.93 - TIME * 0.69) + 0.045 * cos((p.x + p.y) * 1.8 + TIME * 1.1));
	vec3 n = normalize(vec3(-slope.x, -1.0, -slope.y));
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	float fres = 0.035 + 0.965 * pow(1.0 - abs(dot(n, v)), 5.0);
	vec3 sky = vec3(0.12, 0.62, 0.68);
	sky = sky * sky * 1.4;
	float glint = pow(max(0.0, dot(reflect(-normalize(vec3(0.25, -1.0, 0.15)), n), v)), 90.0);
	ALBEDO = mix(sky * 0.72, sky, fres * 0.6) + vec3(1.0, 0.96, 0.77) * glint * 0.65;
}
