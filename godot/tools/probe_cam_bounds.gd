extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	print("[cam] node=", main.cam.get_path(), " script=", main.cam.get_script().resource_path if main.cam.get_script() else "-")
	print("[cam] pan_bounds=", main.cam.pan_bounds, " has_area=", main.cam.pan_bounds.has_area())
	print("[cam] distance min/max=", main.cam.min_distance, "/", main.cam.max_distance)
	print("[cam] target=", main.cam.target, " distance=", main.cam.distance)
	quit(0)
