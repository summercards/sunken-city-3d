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

	// The water shader handles absorption and the actual geometric intersection.
	// Do not paint emissive foam or caustic lines on the submerged wall.

	return albedo;
}
