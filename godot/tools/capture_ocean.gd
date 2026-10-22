extends SceneTree
## Reproducible full-scene ocean showcase, driven at 30 Hz; no save writes.
## --write-movie outputs/water-upgrade/ocean.avi --fixed-fps 30 --script res://tools/capture_ocean.gd
var main: Node
func _init() -> void:
	call_deferred("run")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	main.cam.distance = 35.0
	main.cam.orbit_dir = Vector3(-0.6, 0.8, 0.7)
	main.cam.target = main.boat.position
	main.cam.refresh()
	for i in 10: await process_frame
	main.grade.set_values(1.05, 1.0, 1.0, 1.0)
	var zones: Node = root.get_node("Zones")
	main._sail_to_landing(zones.landing("zone3", "main"), "zone3", "main")
	var times: Array[float] = []
	for frame in 540:
		var start := Time.get_ticks_usec()
		main.cam.target = main.boat.position + Vector3(0, 0.8, 0)
		main.ribbon.hide()
		if frame == 300:
			# Show both sides of the moving surface and the curved world-space trail.
			main.cam._orbit(0.45, -0.14)
		await process_frame
		await RenderingServer.frame_post_draw
		times.append(float(Time.get_ticks_usec()-start)/1000.0)
		if frame in [60, 180, 300, 450, 539]:
			root.get_texture().get_image().save_png("res://outputs/water-upgrade/sailing-%03d.png" % frame)
	print("[ocean-visual] wake_samples=",main.water_node.wake.samples.size()," position=",main.boat.position,
		" avg_frame_ms=",times.reduce(func(a,b): return a+b,0.0)/times.size())
	main.queue_free()
	await process_frame
	quit()
