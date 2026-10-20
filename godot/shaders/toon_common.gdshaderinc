// 卡通材质公共部分：水下深度消光 + 焦散 + 吃水线泡沫。
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
	vec3 c_rim = srgb2lin(vec3(0.35, 0.96, 0.85));
	vec3 c_shallow = srgb2lin(vec3(0.12, 0.75, 0.78));
	vec3 c_mid = srgb2lin(vec3(0.06, 0.34, 0.72));
	vec3 c_abyss = srgb2lin(vec3(0.03, 0.14, 0.42));

	float t1 = smoothstep(0.0, 2.2, depth);
	float t2 = smoothstep(2.2, 6.8, depth);
	float t3 = smoothstep(6.8, 15.5, depth);

	vec3 tint = mix(c_rim, c_shallow, t1);
	tint = mix(tint, c_mid, t2);
	tint = mix(tint, c_abyss, t3);

	// 网页版是在色调映射之后混 48%，这里在线性空间用更高的权重补偿。
	float absorb = clamp(depth / 12.5, 0.0, 0.92);
	// 网页版是在色调映射之后按 0.48 混色，等于把水下部分整体「提亮 + 褪色」。
	// 这里在线性空间直接混 ALBEDO，后面还要过光照与 ACES，所以不能再额外压暗
	// （以前挂了 albedo *= 0.88，深水里的墙比网页暗一档）。
	albedo = mix(albedo, tint, absorb * 0.46);

	// 浅水焦散
	float cw1 = sin(wp.x * 1.45 + u_time * 2.1 + sin(wp.z * 1.2));
	float cw2 = cos(wp.z * 1.55 - u_time * 1.7 + cos(wp.x * 1.1));
	float net = smoothstep(0.62, 0.86, (cw1 + cw2) * 0.5);
	float shallow_mask = (1.0 - smoothstep(0.2, 6.5, depth)) * smoothstep(0.0, 0.35, depth);
	emit += srgb2lin(vec3(0.28, 0.92, 0.85)) * net * shallow_mask * 0.30;

	// 吃水线泡沫
	float edge_noise = sin(wp.x * 3.8 + wp.z * 3.2 + u_time * 2.4) * 0.045;
	float thick = 0.16 + edge_noise;
	float primary = 1.0 - smoothstep(0.02, max(0.05, thick), depth);
	float sub = (1.0 - smoothstep(0.0, 0.045, abs(depth - (0.32 + edge_noise * 1.3))))
		* step(0.15, sin(wp.x * 2.2 - wp.z * 2.6 + u_time * 1.8));
	float mask = clamp(primary * 0.92 + sub * 0.58, 0.0, 1.0);
	albedo = mix(albedo, vec3(0.96, 1.0, 0.99), mask);
	emit += vec3(0.55, 0.72, 0.68) * mask * 0.55;

	return albedo;
}
