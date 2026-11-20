extends SceneTree
## Matched comparison: scene, time, anchor, heading and viewport stay fixed.
func _initialize() -> void:
	call_deferred("run")

func snap(cam: OrbitCam, label: String) -> void:
	var view := root.get_visible_rect().size
	var pitch := rad_to_deg(asin(clampf(cam.dir.y, -1.0, 1.0)))
	var hfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(cam.fov * 0.5)) * view.aspect()))
	print("[surface-camera-metrics] ", label, " viewport=", view, " aspect=", view.aspect(), " projection=", cam.projection, " keep=", cam.keep_aspect, " vfov=", cam.fov, " hfov=", hfov, " near=", cam.near, " distance=", cam.distance, " actual=", cam.position.distance_to(cam._cur_target), " pitch=", pitch, " limits=", Vector2(cam.zoom_min, cam.zoom_max), " ratio=", cam.zoom_ratio(), " subject=", cam.follow_subject.name if is_instance_valid(cam.follow_subject) else "none")

func shot(name: String) -> bool:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var ok := image != null and not image.is_empty() and image.save_png("res://outputs/" + name + ".png") == OK
	for i in 4: await process_frame
	return ok

func wheel(cam: OrbitCam, button: int) -> void:
	for i in 18:
		var event := InputEventMouseButton.new()
		event.position = cam.unproject_position(cam._cur_target)
		event.button_index = button
		event.pressed = true
		root.push_input(event, true)
		await process_frame
	for i in 65: await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"):
		quit(1); return
	for type in ["main", "main_minimal"]:
		if change_scene_to_file("res://scenes/" + type + ".tscn") != OK:
			quit(1); return
		await scene_changed
		var main = current_scene
		if type == "main":
			main._autosave_on = false
			main.world_clock.paused = true
		var cam: OrbitCam = main.get_node("Camera")
		for i in 22: await process_frame
		snap(cam, type + "-start")
		if not await shot(type + "-start"): quit(1); return
		if type == "main":
			# The established home berth: dock/house foreground, station across the sea.
			var dock: Node3D = main.get_node("World/Zones/Zone1HomeHarbor").landing_point("main")
			var shore: Vector3 = dock.stand_position()
			main.actor_controller.restore_pose({"mode":0, "player":[shore.x, shore.y, shore.z - 1.4]})
			cam.restore_follow(main.player)
			for i in 22: await process_frame
			snap(cam, "main-shore")
			if not await shot("main-shore"): quit(1); return
		await wheel(cam, MOUSE_BUTTON_WHEEL_DOWN)
		snap(cam, type + "-max")
		if not is_equal_approx(cam.distance,cam.zoom_max) or not await shot(type + "-max"): quit(1); return
		await wheel(cam, MOUSE_BUTTON_WHEEL_UP)
		snap(cam, type + "-min")
		if not is_equal_approx(cam.distance,cam.zoom_min) or not await shot(type + "-min"): quit(1); return
		if type == "main":
			# Same actual shop berth, same direction as the normal camera, both lens runs.
			var dock: Node3D = main.get_node("World/SeaStructures/floating_shop").landing_point("main")
			var park: Node3D = dock.get_node("BoatPark")
			main.boat.place_at(park.global_position,park.global_rotation.y)
			main.actor_controller.restore_pose({"mode":1})
			cam.set_distance(float(cam.get("surface_profile").start_distance) if "surface_profile" in cam and cam.get("surface_profile") != null else 27.9)
			cam.restore_follow(main.player)
			for i in 30: await process_frame
			snap(cam, "main-shop")
			if not await shot("main-shop"): quit(1); return
	print("[surface-camera] done")
	quit()
