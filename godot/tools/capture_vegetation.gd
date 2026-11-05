extends SceneTree
## Run only through run_verification.py (isolated data and output paths).
var main: Node
var failures := 0
func _init() -> void:
	call_deferred("run")
func shot(label: String, target: Vector3, direction: Vector3, distance: float, fov := 35.0) -> void:
	main.cam.suspend_follow()
	main.cam.zoom_min = 0.8 if distance < 9.0 else 9.0
	main.cam.set_process(false)
	main.cam.target = target
	main.cam.dir = direction.normalized()
	main.cam.distance = distance
	main.cam.cam_fov = fov
	main.cam.apply_pose()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/vegetation_" + label + ".png")
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 取景工具：玩家上限是 38 m（SEA-CAMERA-R11），这里临时放开，保持整片植被/屋顶机位。
	main.cam.zoom_max = 260.0
	main._autosave_on = false
	main.set_process(false)
	for i in 20: await process_frame
	# A dummy/headless rendering server cannot read back MultiMesh transforms.
	# Compare uploaded buffers with authored transforms in the real renderer instead.
	for patch in main.find_children("VegetationTurf", "Node3D", true, false):
		for batch in patch.batches:
			var expected: Array = batch.get_meta("authored_transforms")
			# GPU readback is synchronous: sample each batch's start/middle/end.
			for i in [0, expected.size()/2, expected.size()-1]:
				if not expected[i].is_equal_approx(batch.multimesh.get_instance_transform(i)):
					failures += 1; printerr("FAIL uploaded vegetation transform ", batch.name, "/", i)
	await shot("solar", Vector3(6, 4.3, 3), Vector3(-0.60, 0.70, 1), 42)
	await shot("solar_close", Vector3(6.8, 10.25, -0.2), Vector3(-0.2, 0.8, 1), 12)
	await shot("solar_grazing", Vector3(5.6, 10.9, 0.35), Vector3(-0.2, 0.28, 1), 5.5)
	await shot("solar_terrace", Vector3(1.3, 7.6, 1.2), Vector3(-0.6, 0.7, 1), 12)
	await shot("grass_macro", Vector3(5.5,10.92,-.7), Vector3(-.1,.5,1), 2.0)
	await shot("roof", Vector3(46,4.5,-52), Vector3(-.28,.95,1),95)
	await shot("roof_far", Vector3(46,4.5,-52), Vector3(-.28,.95,1),135)
	await shot("roof_close", Vector3(63,4.7,-42), Vector3(-.3,.7,1),22)
	for patch in main.find_children("VegetationTurf", "Node3D", true, false): patch.hide()
	await shot("solar_before", Vector3(6, 4.3, 3), Vector3(-0.60, 0.70, 1), 42)
	await shot("solar_close_before", Vector3(6.8, 10.25, -0.2), Vector3(-0.2, 0.8, 1), 12)
	for patch in main.find_children("VegetationTurf", "Node3D", true, false): patch.show()
	await shot("both_far", Vector3(25, 3, -22), Vector3(-0.28, 0.95, 1), 180)
	if get_first_node_in_group("vegetation_wind_owner") != null:
		var wind = get_first_node_in_group("vegetation_wind_owner")
		wind.frozen = true
		for view in ["solar", "roof"]:
			await shot(view + "_motion_start", Vector3(6.0,10.9,.35) if view == "solar" else Vector3(61,4.8,-42), Vector3(-.2,.6,1), 12 if view == "solar" else 38)
			DirAccess.make_dir_recursive_absolute("res://outputs/motion_" + view)
			for frame in 120:
				wind.sample_at(10.0 + float(frame)/30.0)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://outputs/motion_%s/%03d.png" % [view, frame])
	var survey := []
	for mi in main.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null: continue
		var p: String = str(mi.get_path())
		if "rooftop_ranch/Models" not in p: continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if a.end.y < 4.0: continue
		survey.append({"path": p, "min": [a.position.x-46,a.position.y+55.92,a.position.z+52], "max": [a.end.x-46,a.end.y+55.92,a.end.z+52]})
	FileAccess.open("res://outputs/vegetation_survey.json", FileAccess.WRITE).store_string(JSON.stringify(survey, "  "))
	print("[vegetation-render] %d failures" % failures)
	quit(0 if failures == 0 else 1)
