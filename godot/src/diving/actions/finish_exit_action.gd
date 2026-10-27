extends RefCounted
func execute(c) -> void:
	c.active = false
	# 灯必须关掉：海面材质与水下材质不是一套，但 uniform 会留在同一个
	# ShaderMaterial 缓存里，下次进水前如果没重设就会「灯没开却亮着」。
	c.MaterialLib.set_lamp(false, Vector3.ZERO, Vector3(0, 0, -1))
	c.visible = false
	c._set_surface_visible(true)
	c._world_env.environment = c._saved_env
	c.camera.current = false
	c.deco.visible = false
	c.chests_root.visible = false
	c.depth = 0.0
	c.exited.emit()
