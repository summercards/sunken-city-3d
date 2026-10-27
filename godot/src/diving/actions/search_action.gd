extends RefCounted
func execute(c, dt: float) -> void:
	# 搜索进度
	if not c._search.is_empty():
		var chest: Dictionary = c._search
		if not c._route.is_empty():
			c._search_t = 0.0
		elif c.diver_pos.distance_to(chest.pos) > c.SEARCH_RADIUS:
			c._search = {}
			c._search_t = 0.0
			c.message.emit("离宝箱太远了")
		else:
			c._search_t += dt
			if c._search_t >= c.SEARCH_TIME:
				c._open_chest(chest)
