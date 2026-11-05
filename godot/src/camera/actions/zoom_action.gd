extends RefCounted
func execute(c,factor: float, screen: Vector2) -> void:
	# 缩放区间随模式变：室外 9–38 米、室内 8–24 米（见 OrbitCam._zoom_low/_high）。
	if c.follow_enabled:
		c.distance = clampf(c.distance*factor, c._zoom_low(), c._zoom_high())
		return
	if c.orbit_only:
		# 室内只改远近，不做「朝光标缩放」：那一步会 `target += shift`，
		# 而室内的 target 是钉在房间上的，漂一点就整屋出画。
		c.distance = clampf(c.distance*factor, c._zoom_low(), c._zoom_high())
		return
	var before = c._ray_plane(screen)
	var want = clampf(c.distance * factor, c._zoom_low(), c._zoom_high())
	if is_equal_approx(want, c.distance):
		return
	c.distance = want
	# 算「缩放后」指针落在哪：临时按新距离摆一次算完立刻还原，
	# 这样距离本身仍然由 _process 平滑过去（不然滚轮会「啪」地跳一档）。
	var old_dist = c._cur_distance
	c._cur_distance = clampf(c.distance, c._zoom_low(), c._zoom_high())
	c._update_pose()
	var after = c._ray_plane(screen)
	c._cur_distance = old_dist
	c._update_pose()
	if before != Vector3.INF and after != Vector3.INF:
		var shift = before - after
		shift.y = 0.0
		# 目标修正也平滑收敛，避免缩放时瞬间侧跳。
		c.target += shift
		c._clamp_target()
		c._update_pose()
