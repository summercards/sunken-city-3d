extends RefCounted
func execute(c) -> void:
	c._enter_t = 0.0
	c._exit_y = c.diver_pos.y
	c._route.clear()
	c._search = {}
	if c._marker_layer != null:
		c._marker_layer.visible = false
