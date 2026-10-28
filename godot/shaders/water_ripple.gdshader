shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/ocean_waves.gdshaderinc"

// 贴浪面的扩散水纹。给两处共用：
//   · 点击落点（click_reticle.gd）—— tween 把 u_progress 从 0 推到 1，散一次就收；
//   · 航行目标（route_ribbon.gd）—— 计时循环推进，目标点在原地一直轻轻荡。
// shader 自身不存状态：同一个材质既能演「点一下」，也能演「一直荡」。
//
// 造型：3 圈细白弧，整组随 `u_progress` 从中心往外推，越靠内越旧越淡。
// 2026-10-28 的几轮试错记在这里，免得下次又走回头路：
//   · floor() 数圈 → 圈边界上 fwidth 跳变，边缘裂成锯齿断点；
//   · fract() 三角波 + 角度调制 → 各圈相位沿半径错开，连成螺旋（像蚊香）；
//   · 亮脊 + 双侧暗肩 → 暗肩太宽就成了「白圈套黑盘」的霓虹灯，不是水。
// 现在回到最朴素的做法：显式 3 圈、细线、soft 边缘、只提亮不压暗。
// 圈能读出来靠三件事：比水面亮、线足够细（1-2px）、沿圆周粗细和亮度都会变。
// 尺寸必须按**真实游戏视距**反推，不能凭特写手感调。
// 默认相机 distance=54.25、FOV 31°、视口 800px 高 → 1 米 ≈ 26.6px。
// `crest_width` 是 p 空间的半宽（p 的 1.0 = 半径），所以实际线宽 = crest_width × 半径：
//   · 半径 0.72m + crest_width 0.014 → 线只有 0.27px，正常视距下根本看不见
//     （2026-10-28 一度在 7.5m 特写下验收通过，回到默认视距就消失了）；
//   · 现在 半径 1.8m + crest_width 0.034 → 线宽约 3px（全长），正常视距下是一条细纹。
uniform float u_progress : hint_range(0.0, 1.0) = 0.0;
uniform float u_opacity : hint_range(0.0, 1.0) = 0.85;
uniform vec3 ring_tint = vec3(0.94, 0.99, 1.0);
// 相邻两圈的径向间距（p 空间，1.0 = 平面半径）。0.30 × 1.8m ≈ 0.54m。
uniform float wavelength : hint_range(0.10, 0.55) = 0.30;
// 亮脊半宽（p 空间）。见上面的换算说明。
uniform float crest_width : hint_range(0.010, 0.140) = 0.034;
// 每往内一圈保留多少亮度。0.40 ≈ 第二圈四成、第三圈快看不见。
uniform float crest_decay : hint_range(0.10, 0.90) = 0.40;
// 落点在岸上时置 0：贴地而不是贴浪，避免被浪抬起来穿进地板。
uniform float follow_waves : hint_range(0.0, 1.0) = 1.0;

const int RINGS = 3;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 抬一点离水：水面顶点还叠了船头涌高与岸线小波包，贴太近会被水盖掉。
	VERTEX.y += ocean_sample(world.xz).x * follow_waves + 0.055;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// 等距镜头把水面纵向压扁，这里补一点比例，俯视才读成圆。
	p.y *= 1.05;

	float r = length(p);
	float angle = atan(p.y, p.x);

	// 波前位置：起手快、末端缓，像水面被点了一下之后迅速铺开又慢慢停住。
	float front = mix(0.07, 0.86, pow(u_progress, 0.58));

	float sum = 0.0;
	for (int i = 0; i < RINGS; i++) {
		float fi = float(i);
		// 第 0 圈就是波前，往后每圈更靠内、更旧。
		float radius = front - fi * wavelength;
		if (radius <= 0.04) {
			continue;
		}
		// 圈不是正圆：撞上别的水波会歪一点。只给薄薄一层扰动，不改半径量级。
		float shape = radius
			+ 0.024 * sin(angle * 3.0 + fi * 1.9)
			+ 0.013 * sin(angle * 5.0 - fi * 0.7);
		// 线宽也沿圆周变化：真水纹一段清楚、一段细到看不见。
		float width = crest_width * (0.80 + 0.30 * sin(angle * 4.3 + fi * 2.1));
		float sd = r - shape;
		// 高斯线，比 smoothstep 硬边柔，越往外越淡。
		float line = exp(-(sd * sd) / max(width * width, 1e-6));

		// 沿圆周的强弱：同样一段清楚一段模糊。只挂角度 —— 掺进 r 就成螺旋。
		float shade = 0.72
			+ 0.20 * sin(angle * 2.3 + fi * 2.4 + 0.6)
			+ 0.10 * sin(angle * 5.1 - fi * 1.1 + 2.2);

		// 每圈淡出：靠外最亮，往里迅速融回水里。
		sum = max(sum, line * shade * exp(-fi * 4.0 * (1.0 - crest_decay)));
	}

	// 中心收一点，免得最后缩成一个亮点。
	sum *= smoothstep(0.0, 0.10, r);
	// 一个像素跨过太多圈时已经采不准，按密度整体淡出 —— 融回水面而不是碎成虚线。
	sum *= 1.0 - smoothstep(0.35, 0.90, fwidth(r) / max(wavelength, 0.05));

	// 收尾整体淡出，不留一个硬边的最外圈。
	float life = pow(clamp(1.0 - u_progress, 0.0, 1.0), 0.65);
	// 平面四角收掉，否则波前会撞出方形边。
	float edge = smoothstep(1.0, 0.86, r);

	ALBEDO = ring_tint;
	ALPHA = clamp(sum * life * edge * u_opacity, 0.0, 1.0);
}
