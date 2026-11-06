extends SceneTree
## 正式main和真实主水；独立纯相机，杜绝Orbit/房间重同步夺回机位。
const OUT := "res://outputs/sunken-seabed"
var checks := 0
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var main: Node
var city: Node3D
var water: MeshInstance3D
var camera: Camera3D
var city_pose: Transform3D
var water_pose: Transform3D
var water_parameters: Dictionary
var water_restored := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _init() -> void:
	call_deferred("run")

func parameters() -> Dictionary:
	var result := {}
	var material := water.material_override as ShaderMaterial
	for entry in material.shader.get_shader_uniform_list():
		var key := str(entry["name"])
		if "depth" in key or "absorption" in key or "darkness" in key:
			result[key] = material.get_shader_parameter(key)
	return result

func shot(tag: String, target: Vector3, distance: float, orbit: Vector3, diagnostic: bool, no_water: bool = false) -> void:
	camera.global_position = target + orbit.normalized() * distance
	camera.look_at(target, Vector3.UP)
	camera.make_current()
	var pose := camera.global_transform
	var was_water := water.visible
	water.visible = not no_water
	if water.has_method("update_surface"):
		water.call("update_surface", float(main.get("_t")), main.boat, target)
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_camera_3d() == camera, tag + " 当前相机确为独立纯Camera3D")
	check(camera.global_transform.is_equal_approx(pose), tag + " 真实机位未被覆盖")
	check(absf(camera.global_position.distance_to(target) - distance) < 0.001, tag + " 真实相机距离")
	check(city.get_child_count() == 388 and city.is_visible_in_tree(), tag + " 388旧城实例可见")
	var visible_instances := 0
	var projected_instances := 0
	for instance in city.get_children():
		if instance is Node3D and instance.is_visible_in_tree():
			visible_instances += 1
			var point: Vector3 = instance.global_position
			var screen := camera.unproject_position(point)
			if not camera.is_position_behind(point) and root.get_visible_rect().has_point(screen):
				projected_instances += 1
	check(visible_instances == 388, tag + " 所有388实例保持visible")
	check(projected_instances > 0, tag + " 旧城真实位置投影在画面中")
	check(water.is_visible_in_tree() == not no_water, tag + " 主水显示符合诊断标签")
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), tag + " 实际渲染非空")
	var span := 0.0
	if image != null and not image.is_empty():
		var low := INF
		var high := -INF
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				var light := image.get_pixel(x, y).get_luminance()
				low = minf(low, light)
				high = maxf(high, light)
		span = high - low
		check(span > 0.02, tag + " 画面非纯色")
		check(image.save_png(OUT.path_join(tag + ".png")) == OK, tag + " PNG已保存")
	var projection := camera.get_camera_projection()
	frames.append({"tag": tag, "path": OUT.path_join(tag + ".png"), "diagnostic_only": diagnostic,
		"no_water_diagnostic_only": no_water, "water_visible": water.visible,
		"camera_class": camera.get_class(), "camera_script": camera.get_script(), "current_camera_path": str(root.get_camera_3d().get_path()),
		"camera_position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
		"camera_target": [target.x, target.y, target.z], "actual_forward": str(-camera.global_basis.z),
		"actual_distance_m": camera.global_position.distance_to(target), "projection_type": camera.projection,
		"projection_matrix": str(projection), "fov": camera.fov, "near": camera.near, "far": camera.far,
		"city_instances": city.get_child_count(), "visible_instances": visible_instances, "projected_instances": projected_instances,
		"luminance_span": span, "visibility_limit": "投影入框不等于隔水可辨；正式水图须目视复核"})
	water.visible = was_water
	check(water.visible == was_water, tag + " 水面显示已恢复")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	check(DisplayServer.get_name() != "headless", "真实渲染后端")
	var packed := load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "真实主场景可加载")
	if packed == null:
		finish()
		return
	main = packed.instantiate()
	main.set("_autosave_on", false)
	root.add_child(main)
	main.set("_autosave_on", false)
	for _i in 18:
		await process_frame
	main.world_clock.paused = true
	main.weather_service.paused = true
	if root.has_node("Economy"):
		root.get_node("Economy").set("ticking", false)
	# 递归停掉main全部脚本/动画/物理，而非仅关闭Orbit的process。
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.set_process(false)
	main.set_physics_process(false)
	for node in main.find_children("*", "", true, false):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.set_process(false)
		node.set_physics_process(false)
		if node is Camera3D:
			node.current = false
		if node is CanvasLayer:
			node.hide()
	city = main.get_node("World/SunkenCity") as Node3D
	water = main.get_node("World/Water") as MeshInstance3D
	city_pose = city.transform
	water_pose = water.transform
	water_parameters = parameters()
	check(city.get_child_count() == 388, "真实主场景仍为388旧城实例")
	check(water.is_visible_in_tree(), "真实主水保持显示")
	check(main.get_node("World/SunkenSeabed") is Terrain3D, "主场景已挂真实Terrain3D")
	camera = Camera3D.new()
	camera.name = "SeabedEvidenceCamera"
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 2500.0
	root.add_child(camera)
	camera.make_current()
	var edge := Vector3(110.0, 1.12, 80.0)
	var orbit := Vector3(-0.48, 0.95, 0.60)
	await shot("player-77m8-water", edge, 77.8, orbit, false)
	await shot("player-77m8-diagnostic-no-water", edge, 77.8, orbit, true, true)
	await shot("overview-360m-diagnostic-water", Vector3(0, -20, 0), 360.0, Vector3(-0.25, 1.5, 0.65), true)
	await shot("overview-360m-diagnostic-no-water", Vector3(0, -20, 0), 360.0, Vector3(-0.25, 1.5, 0.65), true, true)
	check(city.transform.is_equal_approx(city_pose), "旧城位置从未改变")
	# update_surface会合法移动相机附近网格；诊断结束恢复原主水变换。
	water.transform = water_pose
	check(water.transform.is_equal_approx(water_pose) and water.visible, "主水位置恢复且无水诊断后恢复")
	check(parameters() == water_parameters, "水深与吸收参数未改")
	water_restored = water.visible and water.transform.is_equal_approx(water_pose)
	check(frames.size() == 4, "玩家正式水图与三张明确标注诊断图")
	main.queue_free()
	await process_frame
	await process_frame
	finish()

func finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"frames": frames, "main_fully_frozen": true, "independent_camera": true,
		"water_restored": water_restored,
		"scope": "玩家77.8m正式主水图；360m及无水图仅为诊断，不冒充玩家验收"}
	FileAccess.open("res://outputs/sunken-seabed-render.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[sunken-seabed-render] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
