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
