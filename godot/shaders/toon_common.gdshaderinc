// 卡通材质公共部分：水下深度消光 + 焦散 + 柔和色彩融合。
// 与网页版 enhanceWithUnderwaterDepthShader 的四层色彩梯度一致。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform bool depth_tint = false;
uniform float water_level = 1.12;
uniform float u_time = 0.0;

varying vec3 v_world;

vec3 srgb2lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 world_pos() {
	return v_world;
}

vec3 apply_depth_tint(vec3 albedo, vec3 wp, out vec3 emit) {
	emit = vec3(0.0);
	float depth = water_level - wp.y;
	if (depth <= 0.0) {
		return albedo;
	}
	vec3 c_rim = srgb2lin(vec3(0.38, 0.96, 0.86));
	vec3 c_shallow = srgb2lin(vec3(0.15, 0.78, 0.80));
	vec3 c_mid = srgb2lin(vec3(0.07, 0.44, 0.74));
	vec3 c_abyss = srgb2lin(vec3(0.03, 0.20, 0.48));

	float t1 = smoothstep(0.0, 2.4, depth);
	float t2 = smoothstep(2.4, 7.2, depth);
	float t3 = smoothstep(7.2, 15.8, depth);

	vec3 tint = mix(c_rim, c_shallow, t1);
	tint = mix(tint, c_mid, t2);
	tint = mix(tint, c_abyss, t3);

	float absorb = clamp(depth / 12.0, 0.0, 0.92);
	albedo = mix(albedo, tint, absorb * 0.50);

	// 浅水区柔和焦散光晕
	float cw1 = sin(wp.x * 1.35 + u_time * 1.6 + sin(wp.z * 1.1));
	float cw2 = cos(wp.z * 1.45 - u_time * 1.3 + cos(wp.x * 1.0));
	float caustic = smoothstep(0.58, 0.88, (cw1 + cw2) * 0.5);
	float shallow_mask = (1.0 - smoothstep(0.3, 6.5, depth)) * smoothstep(0.0, 0.35, depth);
	emit = srgb2lin(vec3(0.28, 0.90, 0.84)) * caustic * shallow_mask * 0.035;

	return albedo;
}
