extends SceneTree
func _init() -> void:
	print("has_method=", RenderingServer.has_method("get_current_rendering_method"))
	print("method=", RenderingServer.get_current_rendering_method())
	quit()
