extends RefCounted
func execute(c, dt: float) -> void:
	if c._diver == null:
		return
	c._diver.position = c.diver_pos
	var flat = Vector2(c._velocity.x, c._velocity.z)
	if flat.length() > 0.15:
		c._heading = atan2(-flat.y, flat.x)
	c._diver.rotation.y = lerp_angle(c._diver.rotation.y, c._heading, minf(1.0, dt * 7.0))
