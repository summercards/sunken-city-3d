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
## 同一个输入在 gl_compatibility 上比 Forward+ 暗得多（实测 0.25 线性值 → 89 对 212），
## 只在自发光材质上出现，因为兼容后端对 EMISSION 的色调映射曲线与 Forward+ 不同。
## 这里给出实测补偿系数，让两个后端的水色落在同一个像素值上。
## 逐通道实测：兼容后端对蓝通道压缩得比绿通道厉害，单标量无法同时对上
## （增益 3.0 时绿偏低 40，增益 4.0 时蓝偏高 60），所以给三个分量。
static func water_emission_gain() -> Vector3:
	var method: String = RenderingServer.get_current_rendering_method()
	if method.begins_with("gl_compatibility"):
		return Vector3(3.8, 3.8, 2.7)
	return Vector3.ONE
