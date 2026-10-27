extends RefCounted
func execute(c, dt: float) -> void:
	var axis = func(a: int, b: int, c: int, d: int) -> float:
		var pos = 0.0
		if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b):
			pos += 1.0
		if Input.is_physical_key_pressed(c) or Input.is_physical_key_pressed(d):
			pos -= 1.0
		return pos

	var x: float = axis.call(KEY_D, KEY_RIGHT, KEY_A, KEY_LEFT)
	var z: float = axis.call(KEY_S, KEY_DOWN, KEY_W, KEY_UP)
	var y: float = axis.call(KEY_E, KEY_SPACE, KEY_Q, KEY_Q)
	var desired = Vector3(x, y * 0.7, z)
	if desired.length() > 1.0:
		desired = desired.normalized()
	# Shift 加速：省时间，但氧气消耗乘 1.9（见 dive_air.gd）。
	var sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	desired = desired.rotated(Vector3.UP, c._yaw) * (c.SPRINT_SPEED if sprint else c.SWIM_SPEED)
	if absf(x) + absf(y) + absf(z) > 0.01:
		c.cancel_navigation()

	if not c._route.is_empty():
		var target: Vector3 = c._route[0]
		var delta_v = target - c.diver_pos
		var length = delta_v.length()
		if length < 0.25:
			c._route.pop_front()
			if c._route.is_empty() and not c._search.is_empty():
				c._search_t = 0.0
		else:
			desired = delta_v.normalized() * minf(4.5, length * 3.0)

	c._velocity = c._velocity.lerp(desired, 1.0 - exp(-dt * 7.0))
	var next = c.diver_pos + c._velocity * dt
	next.y = clampf(next.y, c.MOVE_MIN_Y, c.MOVE_MAX_Y)
	next.x = clampf(next.x, -50.0, 50.0)
	next.z = clampf(next.z, -170.5, 48.0)

	if not c.blocked(next):
		c.diver_pos = next
	else:
		# 逐轴回退：贴着台地边缘能滑过去，但不会穿下去。
		# 逐轴回退（Vector3 不支持按名字索引，只能逐个写）。
		var probe_y = Vector3(c.diver_pos.x, next.y, c.diver_pos.z)
		if not c.blocked(probe_y):
			c.diver_pos.y = next.y
		else:
			c._velocity.y = 0.0
		var probe_x = Vector3(next.x, c.diver_pos.y, c.diver_pos.z)
		if not c.blocked(probe_x):
			c.diver_pos.x = next.x
		else:
			c._velocity.x = 0.0
		var probe_z = Vector3(c.diver_pos.x, c.diver_pos.y, next.z)
		if not c.blocked(probe_z):
			c.diver_pos.z = next.z
		else:
			c._velocity.z = 0.0

	c.search_action.execute(c,dt)
