extends SceneTree
## Fixed-camera detail shots: irregular whitecaps, then geometry-driven shore waves.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	main.cam.distance = 33.0
	main.cam.orbit_dir = Vector3(0.1, 1.0, 0.85)
	main.cam.target = Vector3(19.0, 1.12, -20.0)
	main.cam.refresh()
	for i in 10: await process_frame
	main.grade.set_values(1.05, 1.0, 1.0, 1.0)
	for frame in 420:
		main.ribbon.hide()
		if frame == 240:
			main.cam.distance = 35.0
			main.cam.orbit_dir = Vector3(-0.6, 0.8, 0.7)
			main.cam.target = main.boat.position
			main.cam.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [30, 90, 150, 210, 270, 330, 390]:
			root.get_texture().get_image().save_png("res://outputs/water-upgrade/detail-%03d.png" % frame)
	print("[wave-detail] completed 420 frames; fixed cameras; no save writes")
	main.queue_free()
	await process_frame
	quit()
