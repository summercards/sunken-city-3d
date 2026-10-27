extends RefCounted
func execute(c,screen: Vector2) -> void:
	# 每次输入只累计像素增量；由指数阻尼消化余量，与网页 OrbitControls 一致。
	c.target += c._screen_delta_to_world(screen-c._drag_last)
	c._drag_last = screen
	c._clamp_target()
