// 卡通材质公共部分：水下深度消光 + 焦散 + 柔和色彩融合。
// 与网页版 enhanceWithUnderwaterDepthShader 的四层色彩梯度一致。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform bool depth_tint = false;
uniform float water_level = 1.12;
uniform float u_time = 0.0;
uniform vec3 albedo_tint = vec3(1.0, 1.0, 1.0);
uniform float ambient_boost = 0.0;
// Emissive water/underwater fill follows the sole DaylightRig writer.
global uniform float world_daylight;
// 深度染色的强度倍数。默认 1.0 = 网页版那股 absorb×0.56 的力度，所有既有
// 材质不受影响。近黑的 albedo 用 1.0 会几乎看不出来，这类物件可以单独调高。
uniform float depth_tint_strength = 1.0;
// 水下自发光补偿的强度。默认 1.0 是给沉没城市的建筑用的：它们要穿过水雾还看得见
// 体量。但把它套到"本来就该是深色剪影"的物件上（比如巨鲸），深色会被抬成一块
// 发亮的青板 —— 所以允许关掉。0 = 只吃水色混色，不加任何补偿光。
uniform float uw_glow_amount = 1.0;

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
	vec3 c_rim = srgb2lin(vec3(0.46, 0.98, 0.88));
	vec3 c_shallow = srgb2lin(vec3(0.24, 0.86, 0.84));
	vec3 c_mid = srgb2lin(vec3(0.14, 0.64, 0.80));
	vec3 c_abyss = srgb2lin(vec3(0.06, 0.36, 0.62));

	float t1 = smoothstep(0.0, 2.8, depth);
	float t2 = smoothstep(2.8, 8.2, depth);
	float t3 = smoothstep(8.2, 16.5, depth);

	vec3 tint = mix(c_rim, c_shallow, t1);
	tint = mix(tint, c_mid, t2);
	tint = mix(tint, c_abyss, t3);

	float absorb = clamp(depth / 11.5, 0.0, 0.92);
	albedo = mix(albedo, tint, clamp(absorb * 0.56 * depth_tint_strength, 0.0, 1.0));

	// 浅水区柔和焦散光晕 + 水下漫射天光自发光补偿（对应网页版出光后再叠 depthTint）
	float cw1 = sin(wp.x * 1.35 + u_time * 1.6 + sin(wp.z * 1.1));
	float cw2 = cos(wp.z * 1.45 - u_time * 1.3 + cos(wp.x * 1.0));
	float caustic = smoothstep(0.58, 0.88, (cw1 + cw2) * 0.5);
	float shallow_mask = (1.0 - smoothstep(0.3, 7.5, depth)) * smoothstep(0.0, 0.35, depth);
	float uw_glow = smoothstep(0.0, 0.4, depth) * (1.0 - smoothstep(4.5, 13.5, depth));
	emit = tint * uw_glow * 0.24 * uw_glow_amount
		+ srgb2lin(vec3(0.32, 0.94, 0.86)) * caustic * shallow_mask * 0.055 * uw_glow_amount;

	return albedo;
}
