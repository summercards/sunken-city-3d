// 水下世界共用的着色逻辑（主材质与透明材质都 include 这段）。
//
// 对齐网页版 underwater-art.js 里 onBeforeCompile 注入的三段效果：
//   1. 焦散网纹：世界坐标上移动的干涉条纹，只照亮朝上的面；
//   2. 深度衰减：越深越暗、越偏青绿；
//   3. 顶部微光：浅水区朝上的面有一层缓慢闪动的高光。
// 表面属性 → 引擎 PBR 光照/阴影 → 自发光 → FOG，禁止把雾混入 ALBEDO。

// 注意：不能用 source_color —— manifest 里的颜色已经是线性值（three 的 material.color），
// 再加 sRGB→线性会二次压暗，帆布会变成墨绿。
uniform vec3 albedo_color = vec3(1.0);
uniform vec3 emissive_color = vec3(0.0);
uniform float emissive_strength : hint_range(0.0, 4.0) = 0.0;
uniform bool use_vertex_color = false;
uniform float roughness = 0.58;
uniform float metallic = 0.06;
uniform float water_level = 1.12;
uniform float caustic_gain : hint_range(0.0, 2.0) = 1.0;
// 潜水员深度 -diver.y（与网页版一致，由 world 每帧推给所有材质）。
uniform float dive_depth = 10.0;
// 焦散/闪光的相位。默认 -1 = 用引擎 TIME；给非负值就等于把水面冻住，
// 调试「闪动到底来自时间动画还是深度竞争」时用（--uwfreeze）。
uniform float time_override = -1.0;

// 头灯作为统一的附加散射项，在所有水下实体上使用同一规则。
uniform bool lamp_on = false;
uniform vec3 lamp_pos = vec3(0.0);
uniform vec3 lamp_dir = vec3(0.0, 0.0, -1.0);
uniform float lamp_range = 34.0;
// 内外角的余弦：内圈之外开始衰减，外圈之外完全照不到。
uniform float lamp_inner = 0.90;
uniform float lamp_outer = 0.70;
uniform vec3 lamp_color = vec3(0.80, 1.0, 0.98);
uniform float lamp_gain = 2.4;

float uw_time() {
	return time_override < 0.0 ? TIME : time_override;
}

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

// 头灯照到这个片元有多亮。`n_w` 是（双面材质已按 FRONT_FACING 修正过的）法线。
float uw_lamp(vec3 n_w) {
	if (!lamp_on) {
		return 0.0;
	}
	vec3 d = v_world - lamp_pos;
	float dist = length(d);
	if (dist <= 0.001 || dist > lamp_range) {
		return 0.0;
	}
	vec3 dir = d / dist;
	float cone = dot(dir, normalize(lamp_dir));
	if (cone <= lamp_outer) {
		return 0.0;
	}
	float spot = smoothstep(lamp_outer, lamp_inner, cone);
	float fall = pow(1.0 - dist / lamp_range, 1.5);
	// 正对灯的面最亮；背光面留一点散射，否则石头背面会硬切成黑块。
	float facing = 0.18 + 0.82 * max(dot(n_w, -dir), 0.0);
	return spot * fall * facing;
}

float uw_light() {
	vec2 p = v_world.xz * 0.85 + v_world.y * 0.2;
	p += vec2(sin(p.y + uw_time() * 0.4), cos(p.x - uw_time() * 0.32)) * 0.38;
	float net = abs(sin(p.x * 2.1 + sin(p.y * 1.8) + uw_time() * 0.48)
		+ sin(p.y * 2.2 - uw_time() * 0.37));
	return (1.0 - smoothstep(0.035, 0.16, net)) * 0.24;
}

float uw_sparkle() {
	vec2 p = v_world.xz * 0.85 + v_world.y * 0.2;
	p += vec2(sin(p.y + uw_time() * 0.4), cos(p.x - uw_time() * 0.32)) * 0.38;
	return pow(max(0.0, sin(p.x * 2.1 + uw_time() * 0.65) * cos(p.y * 1.9 - uw_time() * 0.4)), 18.0);
}

// 焦散按潜水员深度衰减，表面微光按世界高度衰减。
//
// `n_w` 由调用方给出：单面材质直接用插值法线，双面材质在背面要取反
// （three 的 MeshStandardMaterial 对 DoubleSide 也做 `gl_FrontFacing ? n : -n`）。
// 不取反的话，双面的海床/岩盆从内侧看会让「只有朝上的面才有焦散高光」整片失效，
// 岩壁会变成一块没有明暗变化的灰板。
vec3 uw_emission(vec3 base, vec3 n_w) {
	float depth = max(0.0, -v_world.y);
	float atten = mix(1.0, 0.18, smoothstep(65.0, 170.0, dive_depth));
	float shallow = 1.0 - smoothstep(12.0, 55.0, depth);
	float lit_top = max(n_w.y, 0.0);
	float light = uw_light() * caustic_gain;
	// 头灯不受深度衰减影响（否则深沟里开灯也看不见），反而在深处更明显。
	float lamp = uw_lamp(n_w) * lamp_gain * mix(0.85, 1.35, smoothstep(25.0, 150.0, depth));
	return emissive_color * emissive_strength
		+ base * vec3(0.45, 1.0, 0.88) * light * atten
		+ vec3(0.5, 0.65, 0.5) * uw_sparkle() * lit_top * shallow * 0.16 * caustic_gain
		+ base * lamp_color * lamp;
}

// 双面法线：背面翻转，正面原样。
// FRONT_FACING 是 fragment() 的内建量，helper 函数里读不到，必须由调用方传进来
// （和 uw_water_color(SCREEN_UV) 同一个原因）。
vec3 uw_face_normal(bool front) {
	return front ? normalize(v_normal_w) : -normalize(v_normal_w);
}

#include "res://shaders/uw_water_color.gdshaderinc"
vec3 uw_water_color(vec2 screen_uv) {
    return uw_gradient(screen_uv, dive_depth);
}

float uw_fog_amount() {
    float density = mix(0.026, 0.012, smoothstep(65.0, 210.0, dive_depth));
    return clamp(1.0 - exp(-pow(max(v_view_depth, 0.0) * density, 1.8)), 0.0, 1.0);
}
