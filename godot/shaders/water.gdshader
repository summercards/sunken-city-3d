// 手绘水面：屏幕空间折射 + 水深吸收 + 岸线/船体泡沫 + 手绘高光。
//
// 对应网页版 water.js 的 fragmentShader。差异：
//  - 网页版单独渲染一张不带水面的 HDR 场景做折射；这里用 Godot 的
//    screen texture + depth texture，观感一致且少一个 pass。
//  - 波纹池保留 8 个（够靠岸/落水用），随玩法扩展。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform float u_time = 0.0;
uniform float water_level = 1.12;
uniform vec3 fog_color : source_color = vec3(0.09, 0.427, 0.604);
uniform vec2 fog_range = vec2(200.0, 520.0);
uniform float surface_contrast = 0.25;

uniform vec4 u_boat = vec4(0.0, 0.0, 0.0, 0.0);

uniform vec4 u_shore_a[32];
uniform vec4 u_shore_b[32];
uniform int u_shore_count = 0;

uniform vec4 u_ripples[8];
uniform int u_ripple_count = 0;

varying vec3 v_world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float broad(vec2 p) {
	return noise(p) * 0.65 + noise(p * 2.03 + 13.2) * 0.25 + noise(p * 4.01) * 0.1;
}

float box_sdf(vec2 p, vec2 b) {
	vec2 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

vec2 turn(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float shore(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < 32; i++) {
		if (float(i) >= float(u_shore_count)) {
			break;
		}
		vec4 a = u_shore_a[i];
		vec4 b = u_shore_b[i];
		vec2 q = turn(p - a.xy, -b.x);
		d = min(d, mix(box_sdf(q, a.zw), length(q) - max(a.z, a.w), b.y));
	}
	return d;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 drift = vec2(u_time * 0.032, -u_time * 0.024);
	float swell = broad(p * 0.12 + drift);
	float wash = broad(p * 0.25 + vec2(-u_time * 0.027, u_time * 0.019));

	float water_view_depth = -VERTEX.z;

	// 屏幕深度 → 视线空间 → 世界坐标
	float raw_depth = textureLod(depth_tex, SCREEN_UV, 0.0).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float scene_view_depth = -view_pos.z;
	float thickness = clamp(scene_view_depth - water_view_depth, 0.0, 45.0);
	vec3 bed = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;
	float depth = max(0.0, water_level - bed.y);

	// 波浪法线
	float a = dot(p, vec2(0.63, 0.38)) + u_time * 0.72;
	float b = dot(p, vec2(-0.29, 0.91)) - u_time * 0.56;
	float c = dot(p, vec2(1.41, -0.73)) + u_time * 0.93;
	vec2 slope = vec2(0.63, 0.38) * cos(a) * 0.065
		+ vec2(-0.29, 0.91) * cos(b) * 0.045
		+ vec2(1.41, -0.73) * cos(c) * 0.015;
	vec3 normal = normalize(vec3(-slope.x, 1.0, -slope.y));

	float refraction_depth = smoothstep(0.15, 2.5, thickness) * (1.0 - smoothstep(24.0, 45.0, thickness));
	vec2 refract_uv = clamp(SCREEN_UV + slope * (64.0 / VIEWPORT_SIZE) * refraction_depth, vec2(0.001), vec2(0.999));
	float refract_depth_raw = textureLod(depth_tex, refract_uv, 0.0).x;
	vec3 refract_ndc = vec3(refract_uv * 2.0 - 1.0, refract_depth_raw);
	vec4 refract_view = INV_PROJECTION_MATRIX * vec4(refract_ndc, 1.0);
	refract_view.xyz /= refract_view.w;
	if (-refract_view.z < water_view_depth + 0.08) {
		refract_uv = SCREEN_UV;
	}
	vec3 submerged = texture(screen_tex, refract_uv).rgb;

	// 水体本身
	// 屏幕深度为 1.0 表示水面下没有任何几何体（开阔水道）。这时反投影出来的
	// 海底点落在无穷远，y 不可靠，depth 会被算成接近 0，整片水面误判成浅水青绿。
	// 原版只把这种情况用于 transmission，这里必须同时把 deep 置满。
	// Godot 用反向 Z（远平面 = 0），不能用 Three.js 的 rawDepth>.9999 判断。
	// 这里改看 thickness：水面下没有任何几何体时它会被 clamp 到上限。
	if (thickness > 44.0) {
		depth = 45.0;
	}
	float deep = smoothstep(2.0, 13.0, depth);
	// 数值对齐网页版实测：开阔水道 sRGB 约 (16,122,158)。
	// Godot 的 ACES 比 three 的 ACESFilmic 亮一档，同样输入会偏亮，
	// 所以这里的线性基色要压低到 0.83 左右。
	vec3 body = mix(vec3(0.008, 0.250, 0.210), vec3(0.008, 0.104, 0.202), deep);
	body *= 1.0 + (smoothstep(0.30, 0.70, swell) - 0.5) * 0.17 * surface_contrast;
	float wave_light = smoothstep(0.10, 0.85, sin(a) * 0.45 + sin(b) * 0.35 + sin(c) * 0.20);
	body += vec3(0.002, 0.018, 0.020) * wave_light * surface_contrast;
	vec2 wave_domain = p * 0.27 + vec2(sin(p.y * 0.17 + u_time * 0.18), cos(p.x * 0.13 - u_time * 0.14)) * 0.55;
	float facet = smoothstep(0.44, 0.56, broad(wave_domain + drift));
	body += vec3(0.002, 0.036, 0.034) * facet * surface_contrast;

	vec3 transmission = exp(-thickness * vec3(0.125, 0.064, 0.046));
	transmission *= 1.0 - smoothstep(4.0, 13.0, depth);
	if (thickness > 44.0) {
		transmission = vec3(0.0);
	}

	// 水底焦散
	vec2 cp = bed.xz * 0.80 + vec2(sin(bed.z * 0.32 + u_time * 0.6), cos(bed.x * 0.28 - u_time * 0.5)) * 0.42;
	float cells = abs(sin(cp.x + u_time * 0.30) * cos(cp.y - u_time * 0.24));
	float caustic = (1.0 - smoothstep(0.025, 0.085, cells)) * smoothstep(0.3, 1.2, depth) * (1.0 - smoothstep(3.0, 15.0, depth));
	submerged += vec3(0.025, 0.12, 0.10) * caustic;

	vec3 color = submerged * transmission + body * (1.0 - transmission);

	// 菲涅尔 + 太阳高光
	vec3 eye = normalize(CAMERA_POSITION_WORLD - v_world);
	float fresnel = 0.02 + 0.98 * pow(1.0 - max(dot(normal, eye), 0.0), 5.0);
	color = mix(color, vec3(0.16, 0.39, 0.51), fresnel * 0.65);
	vec3 half_light = normalize(eye + normalize(vec3(0.42, 0.78, -0.46)));
	float sun = pow(max(dot(normal, half_light), 0.0), 650.0);
	color += vec3(0.26, 0.45, 0.42) * sun * 0.018 * smoothstep(0.52, 0.72, wash);

	float fleck = smoothstep(0.83, 0.94, noise(p * 1.25 + drift * 2.0)) * smoothstep(0.55, 0.74, swell);
	color += vec3(0.025, 0.055, 0.052) * fleck * surface_contrast;

	// 岸线泡沫
	float edge = shore(p);
	float scallop = sin(p.x * 1.5 + p.y * 1.1 - u_time * 0.75) * 0.11
		+ sin(p.y * 2.4 - p.x * 0.8 + u_time * 0.45) * 0.045;
	float contact = 0.10 + sin(u_time * 1.1 + p.x * 0.28 + p.y * 0.23) * 0.055;
	float breakup = smoothstep(0.31, 0.58, noise(p * 0.7 + drift * 2.0));
	float edge_foam = (1.0 - smoothstep(0.035, 0.115, abs(edge - contact + scallop))) * breakup * step(-0.03, edge) * 0.74;

	float outgoing = 0.0;
	for (int band = 0; band < 2; band++) {
		float age = fract(u_time * 0.23 + float(band) * 0.5 + sin(p.x * 0.25 + p.y * 0.32) * 0.10);
		float front = 0.25 + age * 1.6;
		float crest = 1.0 - smoothstep(0.035, 0.095, abs(edge - front + scallop * (1.0 + age)));
		float envelope = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.42, 1.0, age));
		outgoing = max(outgoing, crest * envelope * breakup * 0.34);
	}
	float foam = max(edge_foam, outgoing * step(0.0, edge));

	// 船体接触泡沫 + 船首波
	vec2 forward = vec2(sin(u_boat.z), cos(u_boat.z));
	vec2 side = vec2(forward.y, -forward.x);
	vec2 rel = p - u_boat.xy;
	float along = dot(rel, forward);
	float across = dot(rel, side);
	float hull = length(vec2(across / 1.32, along / 2.65));
	float hull_lap = (1.0 - smoothstep(0.035, 0.15, abs(hull - 1.03))) * (0.18 + 0.16 * sin(u_time * 1.4 + along * 2.0));
	foam = max(foam, hull_lap);

	float speed = clamp(u_boat.w / 3.6, 0.0, 1.0);
	float tail = -along;
	float width = 1.15 + tail * 0.23;
	float bow = (1.0 - smoothstep(0.05, 0.23, abs(abs(across) - width)))
		* smoothstep(-0.4, 0.4, tail) * (1.0 - smoothstep(3.0, 7.5, tail));
	foam = max(foam, bow * speed * 0.42 * smoothstep(0.24, 0.6, noise(p * 1.5 - vec2(u_time * 0.15))));

	// 靠岸 / 落水涟漪
	for (int i = 0; i < 8; i++) {
		if (float(i) >= float(u_ripple_count)) {
			break;
		}
		vec4 rp = u_ripples[i];
		float age = u_time - rp.z;
		if (age >= 0.0 && age < 3.2) {
			float radius = 0.18 + age * 0.55;
			float ring = 1.0 - smoothstep(radius * 0.55, radius, length(p - rp.xy));
			foam = max(foam, ring * (1.0 - age / 3.2) * 0.55);
		}
	}

	color = mix(color, vec3(0.96, 1.0, 0.99), foam * 0.92);

	// 远处融进雾色（水面是 unshaded，需要手动混合）
	float dist = length(VERTEX);
	float fog = clamp((dist - fog_range.x) / max(0.001, fog_range.y - fog_range.x), 0.0, 1.0);
	color = mix(color, fog_color, fog);

	ALBEDO = color;
	ALPHA = 1.0;
}
