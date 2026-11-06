extends SceneTree
## Run only through run_verification.py (isolated data and output paths).
var main: Node
var solar_surface: Node3D
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

func roof_shot(label: String, target: Vector3, distance: float) -> void:
	var roof: Node3D = main._zone_nodes["rooftop_ranch"]
	await shot(label, roof.to_global(target), roof.global_basis * Vector3(-.28,.95,1), distance)
func find_solar_surface() -> Node3D:
	for patch in main.find_children("VegetationTurf", "Node3D", true, false):
		if patch.layout_path.ends_with("solar_cabin.json"):
			return patch.get_parent()
	return null

func solar_shot(label: String, target: Vector3, direction: Vector3, distance: float) -> void:
	await shot(label, solar_surface.to_global(target), solar_surface.global_basis * direction, distance)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 取景工具：玩家上限是 77.8 m（SEA-CAMERA-R11），这里临时放开，保持整片植被/屋顶机位。
	main.cam.zoom_max = 260.0
	main._autosave_on = false
	main.set_process(false)
	for i in 20: await process_frame
	solar_surface = find_solar_surface()
	# A dummy/headless rendering server cannot read back MultiMesh transforms.
	# Compare uploaded buffers with authored transforms in the real renderer instead.
	for patch in main.find_children("VegetationTurf", "Node3D", true, false):
		for batch in patch.batches:
			var expected: Array = batch.get_meta("authored_transforms")
			# GPU readback is synchronous: sample each batch's start/middle/end.
			for i in [0, expected.size()/2, expected.size()-1]:
				if not expected[i].is_equal_approx(batch.multimesh.get_instance_transform(i)):
					failures += 1; printerr("FAIL uploaded vegetation transform ", batch.name, "/", i)
	await solar_shot("solar", Vector3(6, 5.07, 3), Vector3(-0.60, 0.70, 1), 42)
	await solar_shot("solar_close", Vector3(6.8, 11.02, -0.2), Vector3(-0.2, 0.8, 1), 12)
	await solar_shot("solar_grazing", Vector3(5.6, 11.67, 0.35), Vector3(-0.2, 0.28, 1), 5.5)
	await solar_shot("solar_terrace", Vector3(1.3, 8.37, 1.2), Vector3(-0.6, 0.7, 1), 12)
	await solar_shot("grass_macro", Vector3(5.5,11.69,-.7), Vector3(-.1,.5,1), 2.0)
	await roof_shot("roof", Vector3(0,60.42,0), 95)
	await roof_shot("roof_far", Vector3(0,60.42,0), 135)
	await roof_shot("roof_close", Vector3(17,60.62,10), 22)
	for patch in main.find_children("VegetationTurf", "Node3D", true, false): patch.hide()
	await solar_shot("solar_before", Vector3(6, 5.07, 3), Vector3(-0.60, 0.70, 1), 42)
	await solar_shot("solar_close_before", Vector3(6.8, 11.02, -0.2), Vector3(-0.2, 0.8, 1), 12)
	for patch in main.find_children("VegetationTurf", "Node3D", true, false): patch.show()
	var roof: Node3D = main._zone_nodes["rooftop_ranch"]
	await shot("both_far", roof.to_global(Vector3(0,60.42,0)).lerp(solar_surface.to_global(Vector3(6,5.07,3)), 0.5), Vector3(-0.28, 0.95, 1), 180)
	if get_first_node_in_group("vegetation_wind_owner") != null:
		var wind = get_first_node_in_group("vegetation_wind_owner")
		wind.frozen = true
		for view in ["solar", "roof"]:
			if view == "solar":
				await solar_shot("solar_motion_start", Vector3(6.0,11.67,.35), Vector3(-.2,.6,1), 12)
			else:
				await roof_shot("roof_motion_start", Vector3(15,60.72,10), 38)
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
		var a: AABB = roof.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		if a.end.y < 59.92: continue
		survey.append({"path": p, "min": [a.position.x,a.position.y,a.position.z], "max": [a.end.x,a.end.y,a.end.z]})
	FileAccess.open("res://outputs/vegetation_survey.json", FileAccess.WRITE).store_string(JSON.stringify(survey, "  "))
	print("[vegetation-render] %d failures" % failures)
	quit(0 if failures == 0 else 1)
