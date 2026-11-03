extends SceneTree
## 实机取景：确认横滨铁道在默认范围里真的显示。
##
##   godot --path godot --resolution 1280x800 --fixed-fps 60 --script res://tools/capture_yokohama.gd -- --skip-title --nosave

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 10:
		await process_frame
	var zone: Node3D = main._zone_nodes.get("zone2", null)
	if zone == null:
		print("[yokohama-shot] FAIL zone2 not registered")
		quit(1)
		return
	print("[yokohama-shot] zone2 visible=", zone.is_visible_in_tree(), " pos=", zone.global_position,
		" children=", zone.get_child_count())
	var landing: Node3D = zone.landing_point("main")
	var park: Vector3 = landing.get_node("BoatPark").global_position
	main.boat.place_at(park, landing.get_node("BoatPark").global_rotation.y)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.cam.target = Vector3(park.x, park.y + 2.0, park.z)
	main.cam.dir = Vector3(-0.75, 0.55, 0.62).normalized()
	main.cam.distance = 30.0
	main.cam.cam_fov = 34.0
	main.cam.apply_pose()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/yokohama_default_scope.png")
	print("[yokohama-shot] saved")
	quit(0)
