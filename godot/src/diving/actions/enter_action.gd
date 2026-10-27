extends RefCounted
func execute(c, payload: Dictionary) -> void:
	c.air.refill()
	c._surface_zone = str(payload.get("zone",""))
	c.active = true
	c._enter_t = 0.0
	c.diver_pos = Vector3(0, c.WATER_LEVEL, 12)
	c._yaw = 0.0
	c._pitch = 1.21
	c._distance = 10.0
	c._velocity = Vector3.ZERO
	c._route.clear()
	c._search = {}
	c._refresh_chest_visibility()

	c.visible = true
	c._set_surface_visible(false)
	c._world_env.environment = c._uw_env
	c.camera.fov = 55.0
	c.camera.near = 0.12
	c.camera.current = true
	c.deco.visible = true
	c.chests_root.visible = true
	if c._marker_layer != null:
		c._marker_layer.visible = true
	c._update_camera(0.0, true)
	c._update_lamp()
	c.depth_changed.emit(0.0)
	c._emit_air()
