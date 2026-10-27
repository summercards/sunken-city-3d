extends RefCounted
func execute(c, dt: float, snap: bool) -> void:
	var forward = Vector3(-sin(c._yaw), 0, -cos(c._yaw))
	var target = c.diver_pos + Vector3(0, 0.5, 0) + forward * 1.6
	var cam = c.diver_pos + forward * (-c._distance) + Vector3(0, c._distance * c._pitch, 0)
	cam.y = minf(cam.y, c.WATER_LEVEL - 0.4)
	for i in 24:
		if not c.blocked(cam, 0.15):
			break
		cam = cam.lerp(c.diver_pos, 0.2)
	if snap:
		c.camera.global_position = cam
	else:
		c.camera.global_position = c.camera.global_position.lerp(cam, 1.0 - exp(-dt * 6.0))
	c.camera.look_at(target, Vector3.UP)
