extends RefCounted
func execute(c,dyaw: float, dpitch: float) -> void:
	var radius = Vector2(c.dir.x, c.dir.z).length()
	var pitch = atan2(c.dir.y, maxf(radius, 0.0001))
	var yaw = atan2(c.dir.x, c.dir.z)
	yaw += dyaw
	pitch = clampf(pitch + dpitch, deg_to_rad(c.pitch_min_deg), deg_to_rad(c.pitch_max_deg))
	c.dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	c.orbit_dir = c.dir
	c._update_pose()
