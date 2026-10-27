extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.world_clock.paused=true
	main.weather_service.paused=true
	for entry in [["clear",43200.0],["rain",72000.0]]:
		main.weather_service.set_weather(entry[0])
		main.world_clock.seconds=entry[1]
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		var path: String="res://outputs/weather_"+entry[0]+".png"
		get_root().get_texture().get_image().save_png(path)
		print("[weather-frame] ",path)
	main.queue_free()
	await process_frame
	print("[visual-weather] complete")
	quit()
