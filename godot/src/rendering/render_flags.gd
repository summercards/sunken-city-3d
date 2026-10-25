extends RefCounted
## 渲染后端差异集中在这里。
##
## Reverse-Z（远平面深度 = 0）只在 Vulkan / Forward+ 上成立。Web 导出走的是
## gl_compatibility（WebGL2 / OpenGL），深度是标准约定：0 = 近平面、1 = 远平面。
## 着色器里凡是拿 depth_texture 反投影求视线空间坐标的地方，都必须按这个开关换算，
## 否则整片水面会被判成「水深 0」→ 直接用屏幕色，看起来就是一片死板的亮青色。

static var _reverse_z := -1.0


static func reverse_z() -> float:
	if _reverse_z < 0.0:
		var method: String = RenderingServer.get_current_rendering_method()
		_reverse_z = 0.0 if method.begins_with("gl_compatibility") else 1.0
	return _reverse_z


## 水面是「纯自发光」的：颜色全走 EMISSION，不进光照。
## 同一个输入在 gl_compatibility 上比 Forward+ 暗得多，只在自发光材质上出现，
## 因为兼容后端对 EMISSION 的色调映射曲线与 Forward+ 不同。
## 这里给出实测补偿系数，让两个后端的水色落在同一个像素值上。
##
## 2026-10-24 水面按生产包重做后重新实测：旧系数 (3.8, 3.8, 2.7) 是按重做前的
## 着色器量的。新着色器引入 `exposure_comp` 与解析天空反射，发光量级整体上移，
## 旧系数会把水面推到接近削顶（实测水面 170/241/236，Forward+ 是 1/103/147）。
## 按 gain 0.3~3.8 逐档实测、取开阔水面像素均值拟合，1.26 处误差最小：
## 兼容后端 10/102/146 对 Forward+ 1/105/147（蓝绿误差 ≤3；红通道有约 +9 的
## 色调映射地板，任何增益都压不到 0，故三个分量取同一值）。
##
## 2026-10-25 吸收式水面加入后，系数按方案分开：那套在 Forward+ 上的发光量级
## 比原版亮一档多（水色 24/185/196 对 1/105/147），共用一个系数必然顾此失彼
## （用 1.26 时吸收式只有 11/75/123）。逐通道拟合得 (2.5, 2.8, 2.0)，误差 2.4；
## 绿要比蓝抬得更高，所以这里不能再取同值。
static func water_emission_gain(scheme := "original") -> Vector3:
	var method: String = RenderingServer.get_current_rendering_method()
	if method.begins_with("gl_compatibility"):
		if scheme == "absorption":
			return Vector3(2.5, 2.8, 2.0)
		return Vector3(1.26, 1.26, 1.26)
	return Vector3.ONE
