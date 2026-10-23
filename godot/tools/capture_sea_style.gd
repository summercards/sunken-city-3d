extends SceneTree
## Native visual evidence; run through scripts/run_verification.py.
var main: Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func _init() -> void:
	call_deferred("run")
func shot(label: String, target: Vector3, distance: float) -> void:
	main.cam.target = target
	main.cam.distance = distance
	main.cam.refresh()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/sea-style-" + label + ".png")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	main.cam.orbit_dir = Vector3(-0.6, 0.8, 0.7)
	await shot("harbor", Vector3(0, 1.12, 4), 43.0)
	await shot("channel", Vector3(-8, 1.12, 2), 45.0)
	await shot("aqua", Vector3(29, 1.12, 15), 24.0)
	var school: Dictionary = main.props.nearest_school(Vector3(0, 1.12, 4), 200.0)
	await shot("fish", school.root.global_position, 12.0)
	var positions: Array[Vector3] = []
	check(main.props.schools.size() == 7, "seven schools")
	for s in main.props.schools:
		check(s.fish.size() >= 3 and s.fish.size() <= 6, "web school size 3–6")
		check(main.props._school_water(Vector2(s.base.x, s.base.z)), "school in navigable water")
		for fish in s.fish: positions.append(fish.position)
		print("[sea-style] school=",s.base," fish=",s.fish.size())
	for i in 90: await process_frame
	await shot("fish-later", school.root.global_position, 12.0)
	var n := 0
	for s in main.props.schools:
		for fish in s.fish:
			check(fish.position.distance_to(positions[n]) > 0.04, "every fish participates in animation")
			n += 1
	# Legacy batch pads/rings must not enter the shoreline atlas again.
	var batch := main.get_node("World/Environment/StaticBatch")
	for child in batch.get_children():
		check(int(child.get_meta("source_geometry", -1)) not in batch.retired_geometries, "no baked fish duplicates")
	print("[sea-style] animated_fish=", n, " failures=", failures)
	print("[sea-style] complete")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
