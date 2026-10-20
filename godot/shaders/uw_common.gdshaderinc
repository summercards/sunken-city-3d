// 水下世界共用的着色逻辑（主材质与透明材质都 include 这段）。
//
// 对齐网页版 underwater-art.js 里 onBeforeCompile 注入的三段效果：
//   1. 焦散网纹：世界坐标上移动的干涉条纹，只照亮朝上的面；
//   2. 深度衰减：越深越暗、越偏青绿；
//   3. 顶部微光：浅水区朝上的面有一层缓慢闪动的高光。
// 深度雾交给 Environment（指数雾），不在这里做。

// 注意：不能用 source_color —— manifest 里的颜色已经是线性值（three 的 material.color），
// 再加 sRGB→线性会二次压暗，帆布会变成墨绿。
uniform vec3 albedo_color = vec3(1.0);
uniform vec3 emissive_color = vec3(0.0);
uniform float emissive_strength : hint_range(0.0, 4.0) = 0.0;
uniform bool use_vertex_color = false;
uniform float water_level = 1.12;
uniform float caustic_gain : hint_range(0.0, 2.0) = 0.6;
// 相机所在深度的水柱高度（由 world 每帧推给所有材质）。
uniform float dive_depth = 10.0;

vec3 srgb2lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

varying vec3 v_world;
varying vec3 v_normal_w;
// Godot 4 的 COLOR 只在 vertex() 里可读，fragment 必须走 varying。
varying vec4 v_color;
varying float v_view_depth;

vec3 uw_base() {
	vec3 base = albedo_color;
	if (use_vertex_color) {
		base *= v_color.rgb;
	}
	return base;
}

float uw_light() {
	vec2 p = v_world.xz * 0.85 + v_world.y * 0.2;
	p += vec2(sin(p.y + TIME * 0.4), cos(p.x - TIME * 0.32)) * 0.38;
	float net = abs(sin(p.x * 2.1 + sin(p.y * 1.8) + TIME * 0.48)
		+ sin(p.y * 2.2 - TIME * 0.37));
	return (1.0 - smoothstep(0.035, 0.16, net)) * 0.24;
}

float uw_sparkle() {
	vec2 p = v_world.xz * 0.85 + v_world.y * 0.2;
	p += vec2(sin(p.y + TIME * 0.4), cos(p.x - TIME * 0.32)) * 0.38;
	return pow(max(0.0, sin(p.x * 2.1 + TIME * 0.65) * cos(p.y * 1.9 - TIME * 0.4)), 18.0);
}

// 网页版是 screen-space 的上下渐变，这里用世界高度近似：越深越暗越蓝。
vec3 uw_emission(vec3 base) {
	float depth = max(0.0, water_level - v_world.y);
	float atten = mix(1.0, 0.18, smoothstep(65.0, 170.0, depth));
	float shallow = 1.0 - smoothstep(12.0, 55.0, depth);
	float lit_top = max(v_normal_w.y, 0.0);
	float light = uw_light() * caustic_gain;
	return emissive_color * emissive_strength
		+ base * vec3(0.70, 1.0, 0.92) * light * 0.25 * atten
		+ vec3(0.5, 0.65, 0.5) * uw_sparkle() * lit_top * shallow * 0.16 * caustic_gain;
}

// 网页版的"雾"不是环境雾，而是屏幕空间的上下渐变 + 按视深度衰减。
// Godot 的 Environment 雾只有单一颜色，做不出上亮下暗的水柱，
// 所以这里照搬网页版的做法：按 SCREEN_UV 取整屏水色，再按视深度混合。
// 网页版的雾色是「色调映射之后」的 sRGB 值，直接混进线性 albedo 会整体发白，
// 所以先转线性再混。
vec3 uw_water_color(vec2 screen_uv) {
    float d = clamp((dive_depth - 8.0) / 72.0, 0.0, 1.0);
    vec3 top = mix(vec3(0.12, 0.91, 0.87), vec3(0.025, 0.28, 0.49), d);
    vec3 bottom = mix(vec3(0.025, 0.36, 0.62), vec3(0.008, 0.07, 0.20), d);
    // Godot 的 SCREEN_UV.y 顶部为 0，网页版的 screenY 顶部为 1。
    vec3 water = mix(bottom, top, pow(clamp(1.0 - screen_uv.y, 0.0, 1.0), 0.8));
    return srgb2lin(water);
}

float uw_fog_amount() {
    float density = mix(0.017, 0.009, smoothstep(65.0, 210.0, dive_depth));
    return clamp(1.0 - exp(-pow(v_view_depth * density, 1.8)), 0.0, 1.0);
}
