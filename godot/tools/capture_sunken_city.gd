extends SceneTree
## 真实 main + 真实水面；无水帧只作同机位诊断，不调整水深、吸收或旧城摆位。
## 由统一隔离 runner 注册为 visual-sunken-city 后调用；headless 不冒充渲染通过。

const MANIFEST := "res://assets/models/scenery/sunken_city/runtime_manifest.json"
const OUTPUT := "res://outputs/sunken-city-"
const RUNTIME_VERSION := "v004"
const WATER_Y := 1.12
const SETTLE_FRAMES := 14
const DEPTH_KEYS := ["depth_half_distance", "depth_distance", "absorption", "absorption_color", "deep_darkness", "caustics_depth_near", "caustics_depth_far", "night_depth_distance", "night_shallow_opacity"]

var main: Node
var city: Node3D
var water: MeshInstance3D
var camera: Camera3D
var checks: int = 0
var failures: int = 0
var errors: Array[String] = []
var saved: Dictionary = {}
var hidden_layers: Array[Dictionary] = []
var frame_records: Array[Dictionary] = []
var roof_candidates: Array[Dictionary] = []
var road_point: Vector3 = Vector3.ZERO
var road_found: bool = false
var bridge_point: Vector3 = Vector3.ZERO
var bridge_found: bool = false
var curve_bridge_point: Vector3 = Vector3.ZERO
var curve_bridge_found: bool = false
var depth_before: Dictionary = {}
var original_depth: Dictionary = {}
var frames_by_tag: Dictionary = {}
var water_shapes_before: Array = []
var city_root_lift_m: float = 0.0
var source_max_height_m: float = 59.6591835
var height_cap_m: float = 14.9147959


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		errors.append(label)
		printerr("FAIL ", label)


func depth_snapshot() -> Dictionary:
	var result: Dictionary = {}
	var material: ShaderMaterial = water.material_override as ShaderMaterial
	if material == null:
		return result
	for key in DEPTH_KEYS:
		var value: Variant = material.get_shader_parameter(key)
		if value != null:
			result[key] = value
	return result


func save_state() -> void:
	city_root_lift_m = city.position.y
	saved = {
		"main_process": main.is_processing(), "main_physics": main.is_physics_processing(),
		"city_transform": city.transform, "city_root_lift_m": city.position.y,
		"clock": main.world_clock.to_dict().duplicate(true), "clock_paused": main.world_clock.paused,
		"weather": main.weather_service.to_dict().duplicate(true), "weather_paused": main.weather_service.paused,
		"camera_target": camera.get("target"), "camera_distance": camera.get("distance"),
		"camera_orbit": camera.get("orbit_dir"), "camera_transform": camera.global_transform,
		"camera_process": camera.is_processing(), "camera_follow": camera.get("follow_enabled"),
		"camera_fov": camera.fov, "water_visible": water.visible, "water_transform": water.transform,
		"boat_process": main.boat.is_processing(), "boat_physics": main.boat.is_physics_processing(),
		"boat_transform": main.boat.transform, "economy_ticking": root.get_node("Economy").get("ticking")
	}
	water_shapes_before = main.call("_water_shapes").duplicate(true)
	depth_before = depth_snapshot()
	original_depth = depth_before.duplicate(true)


func sweep_enabled() -> bool:
	return OS.get_environment("SEA_CITY_SWEEP") == "1"


func set_city_lift(lift_m: float) -> void:
	city.position.y = lift_m
	var box: Dictionary = geometry_summary(city)
	check(bool(box["valid"]), "sweep lift %.1f 几何包络有效" % lift_m)
	if bool(box["valid"]):
		check(float(box["max"].y) <= water.global_position.y - 1.0, "sweep lift %.1f 最高实际顶点至少低于水面1m" % lift_m)


func freeze_scene() -> void:
	main.set("_autosave_on", false)
	main.set_process(false)
	main.set_physics_process(false)
	main.world_clock.paused = true
	main.weather_service.paused = true
	root.get_node("Economy").set("ticking", false)
	main.boat.set_process(false)
	main.boat.set_physics_process(false)
	camera.call("suspend_follow")
	camera.set_process(false)
	for node in main.find_children("*", "CanvasLayer", true, false):
		var layer: CanvasLayer = node as CanvasLayer
		hidden_layers.append({"node": layer, "visible": layer.visible})
		layer.hide()
	check(main.weather_service.set_weather("clear"), "使用已有天气服务固定晴天")
	check(water.is_visible_in_tree(), "正式实景保持真实水面可见")


func set_hour(hour: float) -> void:
	var clock: Dictionary = main.world_clock.to_dict().duplicate(true)
	clock["seconds"] = hour * 3600.0
	main.world_clock.from_dict(clock)
	main.daylight_rig.apply(hour)
	# Existing daylight rig owns night depth settings. Record that legitimate time-state baseline;
	# this capture never sets any depth/absorption uniform itself.
	depth_before = depth_snapshot()
	check(main.world_clock.paused and absf(float(main.world_clock.query().get("hour", -1.0)) - hour) < 0.0001, "既有时间服务冻结于 %.2f 小时" % hour)


## 顶点求最高屋顶，不拿 62 米深的街面当默认 pan 的可见目标。
func geometry_summary(node: Node3D) -> Dictionary:
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	var top: Vector3 = Vector3.ZERO
	var count: int = 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = child as MeshInstance3D
		if visual.mesh == null:
			continue
		for surface in range(visual.mesh.get_surface_count()):
			var arrays: Array = visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = visual.global_transform * vertex
				if count == 0 or point.y > high.y:
					top = point
				low = low.min(point)
				high = high.max(point)
				count += 1
	return {"valid": count > 0, "top": top, "center": (low + high) * 0.5, "min": low, "max": high}


func select_targets(instances: Array) -> void:
	for value in instances:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var id: String = str(entry.get("instance_id", ""))
		var key: String = str(entry.get("key", ""))
		var child: Node3D = city.get_node_or_null(NodePath(id)) as Node3D
		if child == null:
			continue
		# 用高楼本体，不把电线/路灯或家园已有基座误当成旧城屋顶。
		if key in ["slender_tower", "terraced_tower", "half_tower", "tram_tenement", "balcony_tenement"]:
			var box: Dictionary = geometry_summary(child)
			if bool(box["valid"]):
				roof_candidates.append({"instance_id": id, "top": box["top"], "center": box["center"]})
		# A genuine marked road junction, not the first plaza tile in manifest order.
		if key == "junction" and id == "junction_instance_003":
			var road_box: Dictionary = geometry_summary(child)
			if bool(road_box["valid"]):
				road_point = road_box["center"]
				road_point.y = road_box["max"].y
				road_found = true
		if key == "viaduct_broken" and (not bridge_found or str(entry.get("urban_role", "")) == "rail_extension"):
			var box: Dictionary = geometry_summary(child)
			if bool(box["valid"]):
				bridge_point = box["center"]
				bridge_found = true
		if key == "viaduct_curve" and not curve_bridge_found:
			var curve_box: Dictionary = geometry_summary(child)
			if bool(curve_box["valid"]):
				curve_bridge_point = curve_box["center"]
				curve_bridge_found = true
	roof_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var top_a: Vector3 = a["top"]
		var top_b: Vector3 = b["top"]
		return top_a.y > top_b.y)
	check(roof_candidates.size() >= 3, "至少三个实际高楼屋顶可供隔水取景")
	check(road_found, "真实道路组件可供水面焦点取景")
	check(bridge_found, "真实冻结断桥可供取景")
	check(curve_bridge_found, "真实弯桥组件可供取景")


func image_stats(image: Image) -> Dictionary:
	var count: int = 0
	var luminance_sum: float = 0.0
	var low: float = 1.0
	var high: float = 0.0
	var black: int = 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color: Color = image.get_pixel(x, y)
			var luminance: float = color.get_luminance()
			low = minf(low, luminance)
			high = maxf(high, luminance)
			luminance_sum += luminance
			if luminance < 0.005:
				black += 1
			count += 1
	return {"samples": count, "mean_luminance": luminance_sum / maxf(float(count), 1.0), "luminance_span": high - low, "black_fraction": float(black) / maxf(float(count), 1.0)}


func shot(tag: String, target: Vector3, distance: float, orbit: Vector3, focus: Vector3, diagnostic: bool = false) -> void:
	check(water.visible == (not diagnostic), tag + " 水面状态与标签一致")
	camera.set("target", target)
	camera.set("distance", distance)
	camera.set("orbit_dir", orbit)
	camera.call("refresh")
	# Main 已冻结；仍经水面既有方法同步相机附近细分/接触信息，不改任何水深参数。
	if water.has_method("update_surface"):
		water.call("update_surface", float(main.get("_t")), main.boat, target)
	for _frame in range(SETTLE_FRAMES):
		await process_frame
	await RenderingServer.frame_post_draw
	check(camera.global_position.y > water.global_position.y, tag + " 相机仍在海面上，不切入潜水视角")
	var screen: Vector2 = camera.unproject_position(focus)
	check(not camera.is_position_behind(focus) and root.get_visible_rect().has_point(screen), tag + " 真实目标投影在画面内（不等于隔水可见）")
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), tag + " 真实渲染帧非空")
	if image == null or image.is_empty():
		return
	check(image.get_width() >= 640 and image.get_height() >= 360, tag + " 截图分辨率有效")
	var stats: Dictionary = image_stats(image)
	check(float(stats["luminance_span"]) > 0.01, tag + " 画面不是空白纯色")
	var path: String = OUTPUT + tag + ".png"
	check(image.save_png(path) == OK, tag + " PNG 保存成功")
	var depth_unchanged: bool = depth_snapshot() == depth_before
	check(depth_unchanged, tag + " 水深/吸收参数未改变")
	frames_by_tag[tag] = image
	frame_records.append({"tag": tag, "path": path, "diagnostic_only": diagnostic,
		"hour": main.world_clock.query().get("hour"), "settle_frames": SETTLE_FRAMES,
		"water_visible": water.visible, "camera_position": str(camera.global_position),
		"capture_type": "diagnostic_no_water" if diagnostic else "water_real_main",
		"camera_target": str(target), "camera_distance": camera.get("distance"), "orbit": str(orbit),
			"focus": str(focus), "focus_depth_m": water.global_position.y - focus.y,
		"lift_m": city.position.y, "road_depth": water.global_position.y - (road_point.y + city.position.y - city_root_lift_m),
		"roof_clearance": water.global_position.y - (geometry_summary(city)["max"].y if bool(geometry_summary(city)["valid"]) else 0.0),
		"global_depth_parameters_unchanged": depth_unchanged,
		"focus_pixel": str(screen), "stats": stats,
		"visibility_verdict": "待目视复核；投影入框或无水诊断不代表隔水可辨"})
	print("[sunken-city-frame] ", tag, " ", image.get_width(), "x", image.get_height(), " diagnostic=", diagnostic)


func road_focus() -> Vector3:
	return road_point + Vector3(0.0, city.position.y - city_root_lift_m, 0.0)


func paired_road_shot(tag: String, distance: float) -> void:
	var focus: Vector3 = road_focus()
	var target: Vector3 = Vector3(focus.x, WATER_Y, focus.z)
	await paired_diagnostic(tag, target, distance, Vector3(-0.35, 1.25, 0.55), focus)


func sweep_road_shots(lift_m: float) -> void:
	set_city_lift(lift_m)
	await paired_road_shot("road-sweep-%d-38m" % int(lift_m), 38.0)
	await paired_road_shot("road-sweep-%d-110m" % int(lift_m), 110.0)


func paired_diagnostic(tag: String, target: Vector3, distance: float, orbit: Vector3, focus: Vector3) -> void:
	await shot(tag, target, distance, orbit, focus)
	var pose: Transform3D = camera.global_transform
	var was_visible: bool = water.visible
	water.visible = false
	await shot(tag + "-diagnostic-no-water", target, distance, orbit, focus, true)
	check(camera.global_transform.is_equal_approx(pose), tag + " 无水诊断严格同机位")
	if frames_by_tag.has(tag) and frames_by_tag.has(tag + "-diagnostic-no-water"):
		var wet: Image = frames_by_tag[tag]
		var dry: Image = frames_by_tag[tag + "-diagnostic-no-water"]
		var delta_sum: float = 0.0
		var samples: int = 0
		for y in range(0, mini(wet.get_height(), dry.get_height()), 8):
			for x in range(0, mini(wet.get_width(), dry.get_width()), 8):
				var wet_color: Color = wet.get_pixel(x, y)
				var dry_color: Color = dry.get_pixel(x, y)
				delta_sum += (absf(wet_color.r - dry_color.r) + absf(wet_color.g - dry_color.g) + absf(wet_color.b - dry_color.b)) / 3.0
				samples += 1
		frame_records[frame_records.size() - 1]["paired_mean_rgb_difference"] = delta_sum / maxf(float(samples), 1.0)
		frame_records[frame_records.size() - 1]["paired_with"] = tag
	water.visible = was_visible
	check(water.visible and water.is_visible_in_tree(), tag + " 无水诊断后恢复水面")
	print("[sunken-city-render-restore] ", tag, " water=", water.visible, " same-camera=", camera.global_transform.is_equal_approx(pose))


func restore_state() -> void:
	if saved.is_empty():
		return
	water.visible = bool(saved["water_visible"])
	water.transform = saved["water_transform"]
	main.world_clock.from_dict(saved["clock"])
	main.weather_service.from_dict(saved["weather"])
	main.daylight_rig.apply(float(main.world_clock.query().get("hour", 9.0)))
	main.world_clock.paused = saved["clock_paused"]
	main.weather_service.paused = saved["weather_paused"]
	for entry in hidden_layers:
		var layer: CanvasLayer = entry["node"]
		layer.visible = bool(entry["visible"])
		check(layer.visible == bool(entry["visible"]), "恢复 CanvasLayer " + String(layer.name))
	camera.set("target", saved["camera_target"])
	camera.set("distance", saved["camera_distance"])
	camera.set("orbit_dir", saved["camera_orbit"])
	camera.call("refresh")
	camera.global_transform = saved["camera_transform"]
	camera.fov = float(saved["camera_fov"])
	camera.set("follow_enabled", saved["camera_follow"])
	camera.set_process(bool(saved["camera_process"]))
	main.boat.set_process(bool(saved["boat_process"]))
	main.boat.set_physics_process(bool(saved["boat_physics"]))
	root.get_node("Economy").set("ticking", saved["economy_ticking"])
	main.set_process(bool(saved["main_process"]))
	main.set_physics_process(bool(saved["main_physics"]))
	# 即将销毁测试实例，自动保存始终关闭，不在清理阶段碰玩家数据。
	main.set("_autosave_on", false)
	check(water.visible == bool(saved["water_visible"]) and water.transform.is_equal_approx(saved["water_transform"]), "恢复原水面显示/变换")
	check(main.world_clock.to_dict() == saved["clock"] and main.weather_service.to_dict() == saved["weather"], "恢复原时间/天气快照")
	check(camera.global_transform.is_equal_approx(saved["camera_transform"]), "恢复原相机变换")
	city.transform = saved["city_transform"]
	check(city.transform.is_equal_approx(saved["city_transform"]) and absf(city.position.y - float(saved["city_root_lift_m"])) < 0.0001, "恢复旧城原始变换/根 Y")
	check(main.boat.transform.is_equal_approx(saved["boat_transform"]), "船体从未被挪动")
	check(depth_snapshot() == original_depth, "清理后水深/吸收参数恢复原时间状态")
	var shapes_after: Array = main.call("_water_shapes").duplicate(true)
	check(shapes_after == water_shapes_before, "抓图不改变水面形状收集结果")
	print("[sunken-city-render-restore] water/time/weather/camera/UI restored; autosave=false")


func finish() -> void:
	if not saved.is_empty():
		restore_state()
	var output_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	check(output_error == OK, "渲染证据目录可用")
	var file: FileAccess = FileAccess.open(OUTPUT + "render.json", FileAccess.WRITE)
	check(file != null, "渲染报告可写")
	if file != null:
		file.store_string(JSON.stringify({"suite": "sunken_city", "version": RUNTIME_VERSION, "checks": checks,
			"failures": failures, "errors": errors, "frames": frame_records,
				"restoration_attempted": not saved.is_empty(), "depth_parameters_before": original_depth,
			"global_depth_parameters_unchanged": depth_snapshot() == original_depth,
			"root_lift_m": city_root_lift_m, "source_max_height_m": source_max_height_m, "height_cap_m": height_cap_m,
		"height_cap_rule": "global_max_div4_cap",
			"scope": "真实海上主场景，正式图保留水面；无水图仅作同机位诊断",
			"limits": "地面约在水下62米，断桥也处于深水；不擅自调整水深/吸收，实际可辨性与shader稳定性仍需查看输出帧"}, "\t"))
		file.close()
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	print("[sunken-city-render] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func run() -> void:
	check(DisplayServer.get_name() != "headless", "必须使用真实渲染后端")
	if DisplayServer.get_name() == "headless":
		await finish()
		return
	preload("res://tools/lighting_capture_profile.gd").prepare()
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "加载真实 main")
	if packed == null:
		await finish()
		return
	main = packed.instantiate()
	main.set("_autosave_on", false)
	root.add_child(main)
	# 取景工具：旧城隔水可见性需要 72–190 m 的远机位；玩家上限是 38 m
	# （SEA-CAMERA-R11 的 77.8 m），不抬高会被静默夹回，截出来的就不是远景。
	var cam_node: Node = main.get("cam") as Node
	if cam_node != null:
		cam_node.set("zoom_max", 260.0)
	main.set("_autosave_on", false)
	city = main.get_node_or_null("World/SunkenCity") as Node3D
	water = main.get_node_or_null("World/Water") as MeshInstance3D
	camera = main.get("cam") as Camera3D
	check(city != null and water != null and camera != null, "主场景具备旧城/真实水面/既有相机")
	if city == null or water == null or camera == null:
		await finish()
		return
	check(city.is_visible_in_tree() and city.get_child_count() == 388, "默认可见的 388 实例旧城")
	check(city.get_meta("building_class", "") == "underwater", "旧城仅水下观赏")
	check(FileAccess.file_exists(MANIFEST), "runtime manifest 已生成")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
	check(parsed is Dictionary, "读取 runtime manifest")
	if not parsed is Dictionary:
		await finish()
		return
	var manifest: Dictionary = parsed as Dictionary
	var placements: Variant = manifest.get("instances", null)
	check(manifest.get("suite", "") == "sunken_city" and manifest.get("version", "") == RUNTIME_VERSION and placements is Array, "只拍 sunken_city/v004")
	var height_contract: Dictionary = manifest.get("height_cap_contract", {}) as Dictionary
	source_max_height_m = float(height_contract.get("source_max_height_m", source_max_height_m))
	height_cap_m = float(height_contract.get("height_cap_m", height_cap_m))
	if not placements is Array:
		await finish()
		return
	var output_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	check(output_error == OK, "PNG 输出目录可用")
	save_state()
	freeze_scene()
	select_targets(placements)
	set_hour(9.0)
	# 默认 pan 高度：诚实记录真实观感，不为了看见62米深地面而改水。
	await shot("surface-day", Vector3(0.0, WATER_Y, 0.0), 110.0, Vector3(-0.5, 0.85, 0.7), Vector3(0.0, WATER_Y, 0.0))
	await shot("high-overview-day", Vector3(0.0, WATER_Y, 0.0), 190.0, Vector3(-0.1, 1.6, 0.3), Vector3(0.0, WATER_Y, 0.0))
	if road_found:
		await paired_road_shot("road-focus-water", 110.0)
		await paired_road_shot("road-focus-player-38m", 38.0)
	for index in range(mini(3, roof_candidates.size())):
		var roof: Dictionary = roof_candidates[index]
		var top: Vector3 = roof["top"]
		var target: Vector3 = Vector3(top.x, 1.12, top.z)
		await shot("near-surface-roof-%d-day" % (index + 1), target, 72.0, Vector3(-0.4, 1.35, 0.45), top)
	if not roof_candidates.is_empty():
		var top: Vector3 = roof_candidates[0]["top"]
		await paired_diagnostic("roof-through-water", Vector3(top.x, 1.12, top.z), 84.0, Vector3(-0.4, 1.5, 0.4), top)
	if bridge_found:
		# 以断桥真实高度为瞄准点，但眼点仍高于海面；保留当前镜头190米上限。
		await paired_diagnostic("bridge-through-water", bridge_point, 150.0, Vector3(-0.25, 1.6, 0.3), bridge_point)
	if curve_bridge_found:
		await paired_diagnostic("curved-bridge-through-water", curve_bridge_point, 110.0, Vector3(-0.3, 1.35, 0.45), curve_bridge_point)
	set_hour(19.5)
	var night_focus: Vector3 = Vector3(0.0, 1.12, 0.0)
	if not roof_candidates.is_empty():
		night_focus = roof_candidates[0]["top"]
	await shot("night-1930", Vector3(night_focus.x, WATER_Y, night_focus.z), 96.0, Vector3(-0.4, 1.2, 0.5), night_focus)
	if sweep_enabled() and road_found:
		set_hour(9.0)
		for lift_m in [42.0, 44.0, 45.0]:
			await sweep_road_shots(float(lift_m))
		city.transform = saved["city_transform"]
	check(frame_records.size() >= 8, "正式日景/屋顶/高空/断桥/无水诊断/夜景均有帧")
	check(frame_records.size() >= 14, "v004 正式日景/屋顶/道路/高空/断桥/弯桥/38m/无水诊断/夜景均有帧")
	await finish()
