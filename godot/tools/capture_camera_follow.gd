extends SceneTree
var main: Node
func _init() -> void: call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main._on_destination("zone3")
	for frame in 360:
		if frame==90:
			main.cam._begin_pan(Vector2(600,400))
		if frame>=90 and frame<120:
			main.cam._drag_pan(Vector2(600+(frame-89)*4,400))
		if frame==120: main.cam._end_drag()
		if frame==210: main._on_click_command("follow")
		await process_frame
		if frame in [60,170,310]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/camera-follow-%d.png" % frame)
	print("[camera-visual] default=",main.cam.zoom_ratio()," follow=",main.cam.follow_enabled)
	main.queue_free()
	await process_frame
	quit()
