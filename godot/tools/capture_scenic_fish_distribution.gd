extends SceneTree
## 正式主水、独立Camera3D、真实尺寸；像素差仅证明鱼被渲染，不签署美术通过。

const OUT: String = "res://outputs/scenic-fish-distribution"
const REPORT: String = OUT + "/render-report.json"
const GROUP_PATH: String = "World/Environment/Animals/ScenicSeaFishSchools"
const SCENIC_SCENE: String = "res://scenes/decorations/animals/scenic_sea_fish_schools.tscn"
const FishSchool = preload("res://src/ambient/decorative_fish_school.gd")
const FIXED_TIME: float = 4.25
const PIXEL_DELTA: float = 0.02
const MIN_PIXELS: int = 3
const CLOSE_DISTANCES: Array[float] = [12.0, 18.0]
const NAMES: Array[String] = ["StationOuter", "AquaOuter", "HomeSouth", "RanchOuter",
	"CityCanal", "CityWest", "CityEast", "RestStopOuter", "NeonOuter", "KioskOuter"]

var checks: int = 0
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var main: Node3D
var water: MeshInstance3D
var group: Node3D
var camera: Camera3D
var main_pose: Transform3D
var world_pose: Transform3D
var water_pose: Transform3D
var default_camera_pose: Transform3D
var default_camera_distance: float = 0.0
var water_parameters: Dictionary = {}
var school_poses: Dictionary = {}
var school_sizes: Dictionary = {}
var shader_time_frozen: bool = false
var original_time_scale: float = 1.0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.get_children():
		result.append_array(all_nodes(child))
	return result

func freeze_world() -> void:
	for tween: Tween in get_processed_tweens():
		tween.pause()
	for node: Node in all_nodes(main):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.set_process(false)
		node.set_physics_process(false)
		if node is Camera3D:
			(node as Camera3D).current = false
		if node is CanvasLayer:
			(node as CanvasLayer).hide()
		if node is AnimationPlayer:
			var animation: AnimationPlayer = node as AnimationPlayer
			if not animation.current_animation.is_empty():
				animation.seek(FIXED_TIME, true)
			animation.pause()
		if node is GPUParticles3D:
			(node as GPUParticles3D).speed_scale = 0.0
		if node is CPUParticles3D:
			(node as CPUParticles3D).speed_scale = 0.0
	# 停掉shader内置TIME，防止两帧间水纹/植被变化被误算成鱼。
	original_time_scale = Engine.time_scale
	Engine.time_scale = 0.0
	shader_time_frozen = true

func material_parameters() -> Dictionary:
	var result: Dictionary = {}
	var material: ShaderMaterial = water.material_override as ShaderMaterial
	if material != null and material.shader != null:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var name: String = str(uniform["name"])
			# update_surface合法刷新时间、接触与尾迹，不把它们当美术参数。
			if name in ["u_time", "u_boat", "u_ripples", "u_ripple_count", "runtime_contact_rects", "runtime_contact_count",
				"boat_hull_points", "boat_hull_count", "boat_blade_points", "boat_blade_count", "wake_points", "wake_strengths", "wake_count"]:
				continue
			result[name] = material.get_shader_parameter(name)
	return result

func fixed_sample(target: Vector3) -> void:
	main.set("_t", FIXED_TIME)
	var boat: Node3D = main.get("boat") as Node3D
	water.call("update_surface", FIXED_TIME, boat, target)
	for node: Node in all_nodes(main):
		if node is FishSchool:
			(node as FishSchool).sample(FIXED_TIME)
		elif node.has_method("describe") and node.has_method("sample"):
			var description: Dictionary = node.call("describe")
			if str(description.get("asset_id", "")).begins_with("SEA-DECO-ANIMAL"):
				node.call("sample", FIXED_TIME)
	RenderingServer.global_shader_parameter_set("vegetation_time", FIXED_TIME)

func settle() -> void:
	for index: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw

func image_now() -> Image:
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return image.duplicate() as Image

func rgb_difference(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)

func fish_rois(school: FishSchool, image_size: Vector2i) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	var screen_size: Vector2 = root.get_visible_rect().size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return result
	var factor: Vector2 = Vector2(image_size) / screen_size
	var image_rect: Rect2i = Rect2i(Vector2i.ZERO, image_size)
	for index: int in range(school.count):
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		var projected: bool = false
		for part_name: String in ["Body", "Eyes", "Fin"]:
			var part: MultiMeshInstance3D = school.get_node_or_null(part_name) as MultiMeshInstance3D
			if part == null or part.multimesh == null or part.multimesh.mesh == null:
				continue
			if index >= part.multimesh.instance_count:
				continue
			var pose: Transform3D = part.global_transform * part.multimesh.get_instance_transform(index)
			var bounds: AABB = part.multimesh.mesh.get_aabb()
			for corner_index: int in range(8):
				var point: Vector3 = pose * bounds.get_endpoint(corner_index)
				if camera.is_position_behind(point):
					continue
				var screen: Vector2 = camera.unproject_position(point) * factor
				low = low.min(screen)
				high = high.max(screen)
				projected = true
		if projected:
			# 仅围住真实鱼体与尾鳍；8px余量覆盖抗锯齿及浅水折射，不用整幅非空代替。
			var top_left: Vector2i = Vector2i(int(floor(low.x)) - 8, int(floor(low.y)) - 8)
			var bottom_right: Vector2i = Vector2i(int(ceil(high.x)) + 9, int(ceil(high.y)) + 9)
			var roi: Rect2i = Rect2i(top_left, bottom_right - top_left).intersection(image_rect)
			if roi.has_area():
				result.append(roi)
	return result

func roi_mask(rois: Array[Rect2i], size: Vector2i) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(size.x * size.y)
	mask.fill(0)
	for roi: Rect2i in rois:
		for y: int in range(roi.position.y, roi.end.y):
			for x: int in range(roi.position.x, roi.end.x):
				mask[y * size.x + x] = 1
	return mask

func difference_evidence(on: Image, baseline: Image, off: Image, off_repeat: Image, rois: Array[Rect2i]) -> Dictionary:
	var size: Vector2i = on.get_size()
	var mask: PackedByteArray = roi_mask(rois, size)
	var changed: int = 0
	var roi_pixels: int = 0
	var background_changed: int = 0
	var baseline_changed: int = 0
	var peak_delta: float = 0.0
	var total_delta: float = 0.0
	var per_roi: Array[int] = []
	for roi: Rect2i in rois:
		var count: int = 0
		for y: int in range(roi.position.y, roi.end.y):
			for x: int in range(roi.position.x, roi.end.x):
				var noise: float = maxf(rgb_difference(on.get_pixel(x, y), baseline.get_pixel(x, y)), rgb_difference(off.get_pixel(x, y), off_repeat.get_pixel(x, y)))
				var delta: float = rgb_difference(on.get_pixel(x, y), off.get_pixel(x, y))
				if delta >= maxf(PIXEL_DELTA, noise * 4.0 + 0.004):
					count += 1
		per_roi.append(count)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var noise: float = maxf(rgb_difference(on.get_pixel(x, y), baseline.get_pixel(x, y)), rgb_difference(off.get_pixel(x, y), off_repeat.get_pixel(x, y)))
			var delta: float = rgb_difference(on.get_pixel(x, y), off.get_pixel(x, y))
			var significant: bool = delta >= maxf(PIXEL_DELTA, noise * 4.0 + 0.004)
			if noise >= PIXEL_DELTA:
				baseline_changed += 1
			if mask[y * size.x + x] != 0:
				roi_pixels += 1
				if significant:
					changed += 1
					peak_delta = maxf(peak_delta, delta)
					total_delta += delta
			elif significant:
				background_changed += 1
	return {"visible_pixels": changed, "roi_area_pixels": roi_pixels,
		"per_fish_envelope_pixels": per_roi, "background_changed_pixels": background_changed,
		"baseline_unstable_pixels": baseline_changed, "peak_rgb_delta": peak_delta,
		"total_rgb_delta": total_delta, "rgb_l1_threshold": PIXEL_DELTA,
		"noise_rule": "delta >= max(0.02, 4*max(on/on, off/off噪声)+0.004)",
		"minimum_pixels_per_school": MIN_PIXELS,
		"limit": "ROI像素量为union去重；各鱼ROI可能重叠，不能相加冒充可见鱼数"}

func focus_of(schools: Array[FishSchool]) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	for school: FishSchool in schools:
		for local_pose: Transform3D in school.transforms:
			sum += school.global_transform * local_pose.origin
			count += 1
	return sum / float(count) if count > 0 else group.global_position

func unchanged_school_sizes() -> bool:
	for node: Node in group.get_children():
		if node is FishSchool:
			var school: FishSchool = node as FishSchool
			if not school.transform.is_equal_approx(school_poses[str(school.name)]):
				return false
			if not is_equal_approx(school.size_scale, float(school_sizes[str(school.name)])):
				return false
	return true

func context_geometry_in_frame(context: Node3D) -> bool:
	var viewport_rect: Rect2 = root.get_visible_rect()
	for node: Node in all_nodes(context):
		if node is MeshInstance3D:
			var part: MeshInstance3D = node as MeshInstance3D
			if part.mesh == null or not part.is_visible_in_tree():
				continue
			var bounds: AABB = part.mesh.get_aabb()
			for index: int in range(9):
				var local: Vector3 = bounds.get_center() if index == 8 else bounds.get_endpoint(index)
				var point: Vector3 = part.global_transform * local
				if not camera.is_position_behind(point) and viewport_rect.has_point(camera.unproject_position(point)):
					return true
	return false

func shot(tag: String, schools: Array[FishSchool], distance: float, context_path: String = "") -> void:
	var target: Vector3 = focus_of(schools)
	camera.global_position = target + Vector3(-0.40, 0.92, 0.60).normalized() * distance
	camera.look_at(target, Vector3.UP)
	camera.make_current()
	var camera_pose: Transform3D = camera.global_transform
	fixed_sample(target)
	var water_shot_pose: Transform3D = water.transform
	var water_time: float = float(water.get("time"))
	var context: Node3D = null
	if not context_path.is_empty():
		context = main.get_node_or_null(context_path) as Node3D
	if not context_path.is_empty():
		check(context != null and context.is_visible_in_tree(), tag + " 对应真实环境建筑存在且可见")
	check(water.is_visible_in_tree(), tag + " 正式图保留真实主水")
	for school: FishSchool in schools:
		check(school.is_visible_in_tree(), tag + " fish-on默认可见 " + str(school.name))
	await settle()
	var baseline: Image = image_now()
	await settle()
	var on: Image = image_now()
	check(on != null and baseline != null, tag + " fish-on实际图像可读")
	if on == null or baseline == null:
		return
	var rois: Array[Rect2i] = []
	var per_school_rois: Array[Dictionary] = []
	for school: FishSchool in schools:
		var school_rois: Array[Rect2i] = fish_rois(school, on.get_size())
		check(not school_rois.is_empty(), tag + " 真实鱼体包络投影入框 " + str(school.name))
		per_school_rois.append({"rois": school_rois})
		rois.append_array(school_rois)
	var file_path: String = OUT.path_join(tag + ".png")
	check(on.save_png(file_path) == OK, tag + " 保存正式fish-on PNG")
	var prior_visibility: Array[bool] = []
	for school: FishSchool in schools:
		prior_visibility.append(school.visible)
		school.hide()
	await settle()
	var off: Image = image_now()
	await settle()
	var off_repeat: Image = image_now()
	for index: int in range(schools.size()):
		schools[index].visible = prior_visibility[index]
	check(off != null and off_repeat != null, tag + " fish-off诊断图像可读")
	if off == null or off_repeat == null:
		return
	check(on.get_size() == off.get_size() and baseline.get_size() == on.get_size() and off_repeat.get_size() == on.get_size(), tag + " 差分图尺寸一致")
	if on.get_size() != off.get_size() or baseline.get_size() != on.get_size() or off_repeat.get_size() != on.get_size():
		return
	var evidence: Dictionary = difference_evidence(on, baseline, off, off_repeat, rois)
	check(int(evidence["baseline_unstable_pixels"]) <= maxi(32, int(float(on.get_width() * on.get_height()) * 0.0001)), tag + " 固定时刻重复帧稳定，噪声不得充当鱼贡献")
	var school_evidence: Array[Dictionary] = []
	for index: int in range(schools.size()):
		var typed_rois: Array[Rect2i] = []
		typed_rois.assign(per_school_rois[index]["rois"])
		var single: Dictionary = difference_evidence(on, baseline, off, off_repeat, typed_rois)
		school_evidence.append({"name": str(schools[index].name), "visible_pixels": single["visible_pixels"], "rois": str(typed_rois)})
		if context_path.is_empty():
			check(int(single["visible_pixels"]) >= MIN_PIXELS, "%s %s ROI内真实鱼差分至少%d像素，实际%d" % [tag, schools[index].name, MIN_PIXELS, int(single["visible_pixels"])])
	# 远景只记录像素，不要求小鱼在77.8m仍可辨；近景必须逐群证明实际渲染。
	var background_limit: int = maxi(32, int(float(evidence["visible_pixels"]) * 0.10))
	check(int(evidence["background_changed_pixels"]) <= background_limit, tag + " ROI外背景稳定，排除全画面变化假阳性")
	check(root.get_camera_3d() == camera and camera.get_script() == null, tag + " 独立无脚本Camera3D当前生效")
	check(camera.global_transform.is_equal_approx(camera_pose), tag + " 同机位未被main/房间相机覆盖")
	check(absf(camera.global_position.distance_to(target) - distance) < 0.001, tag + " 实际相机距离正确")
	check(water.is_visible_in_tree() and water.transform.is_equal_approx(water_shot_pose) and is_equal_approx(float(water.get("time")), water_time), tag + " on/off主水显示、变换、相位相同")
	check(unchanged_school_sizes(), tag + " 鱼未放大、未移位")
	for school: FishSchool in schools:
		check(is_equal_approx(school.elapsed, FIXED_TIME) and school.visible, tag + " 动画固定且显隐恢复 " + str(school.name))
	var context_in_frame: bool = false
	if context != null:
		context_in_frame = context_geometry_in_frame(context)
		check(context_in_frame, tag + " 真实环境建筑几何入框，非空海面环境图")
	frames.append({"tag": tag, "path": file_path, "formal_fish_on": true,
		"fish_off_saved": false, "fixed_animation_time": FIXED_TIME, "day_hour": 9.0,
		"weather": "clear", "water_visible": water.is_visible_in_tree(),
		"camera": {"class": camera.get_class(), "script": "none", "position": str(camera.global_position),
			"target": str(target), "distance_m": camera.global_position.distance_to(target),
			"fov": camera.fov, "projection": str(camera.get_camera_projection()), "same_pose_verified": camera.global_transform.is_equal_approx(camera_pose)},
		"image_size": str(on.get_size()), "pixel_evidence": evidence, "schools": school_evidence,
		"context_path": context_path, "context_geometry_projected": context_in_frame,
		"scope": "近景逐群渲染证据" if context_path.is_empty() else "77.8m环境构图；不承诺远景逐鱼可辨",
		"art_review": "pending；像素差和画面非空不等于美术passed"})

func run() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	check(directory_error == OK, "截图目录可创建")
	check(DisplayServer.get_name() != "headless", "必须使用真实渲染后端，不接受headless空图")
	if DisplayServer.get_name() == "headless":
		finish()
		return
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	check(packed != null, "真实main场景可加载")
	if packed == null:
		finish()
		return
	main = packed.instantiate() as Node3D
	main.set("_autosave_on", false)
	var clock: Object = main.get("world_clock") as Object
	var weather: Object = main.get("weather_service") as Object
	clock.set("paused", true)
	weather.set("paused", true)
	main_pose = main.transform
	world_pose = (main.get_node("World") as Node3D).transform
	root.add_child(main)
	main.set("_autosave_on", false)
	clock.set("paused", true)
	weather.set("paused", true)
	for index: int in range(18):
		await process_frame
	if bool(main.get("_title_active")):
		var title_camera: Object = main.get("title_camera") as Object
		title_camera.call("finish", main.get("cam"))
		main.call("_resume_after_avatar_or_title")
	main.set("_autosave_on", false)
	clock.set("paused", true)
	weather.set("paused", true)
	clock.set("seconds", 9.0 * 3600.0)
	clock.emit_signal("changed", clock.call("query"))
	weather.call("set_weather", "clear")
	var rig: Object = main.get("daylight_rig") as Object
	rig.call("apply", 9.0)
	if root.has_node("Economy"):
		root.get_node("Economy").set("ticking", false)
	check(not bool(main.get("_title_active")), "已退出title并恢复正式游戏可见性")
	var world: Node3D = main.get_node("World") as Node3D
	check(world.is_visible_in_tree(), "正式World可见")
	group = main.get_node_or_null(GROUP_PATH) as Node3D
	water = main.get_node_or_null("World/Water") as MeshInstance3D
	check(group != null and water != null, "正式主水和观赏鱼组已实际挂载")
	if group == null or water == null:
		finish()
		return
	check(group.scene_file_path == SCENIC_SCENE and group.get_child_count() == 10 and group.is_visible_in_tree(), "真实独立场景10群默认可见")
	var default_camera: Camera3D = main.get("cam") as Camera3D
	default_camera_pose = default_camera.transform
	default_camera_distance = float(default_camera.get("distance"))
	water_pose = water.transform
	water_parameters = material_parameters()
	freeze_world()
	var schools: Array[FishSchool] = []
	var total: int = 0
	for name: String in NAMES:
		var school: FishSchool = group.get_node_or_null(name) as FishSchool
		check(school != null, "正式鱼群存在 " + name)
		if school != null:
			schools.append(school)
			school_poses[name] = school.transform
			school_sizes[name] = school.size_scale
			total += school.count
			check(school.size_scale >= 0.46 and school.size_scale <= 0.5, name + " 真实小鱼尺寸未放大")
			check(school.get("_water") == water, name + " 使用main已注入的主水")
	check(total == 98 and schools.size() == 10, "真实10群98条")
	if schools.size() != 10:
		finish()
		return
	camera = Camera3D.new()
	camera.name = "ScenicFishEvidenceCamera"
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 2500.0
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(camera)
	camera.make_current()
	fixed_sample(group.global_position)
	for school: FishSchool in schools:
		var selected: Array[FishSchool] = [school]
		for distance: float in CLOSE_DISTANCES:
			await shot("%s-close-%dm" % [school.name, int(distance)], selected, distance)
	var context_views: Array[Dictionary] = [
		{"tag": "ranch-environment-77m8", "names": ["RanchOuter"], "path": "World/SeaStructures/rooftop_ranch"},
		{"tag": "city-environment-77m8", "names": ["CityCanal"], "path": "World/SunkenCity"},
		{"tag": "rest-stop-environment-77m8", "names": ["RestStopOuter"], "path": "World/SeaStructures/floating_rest_stop"},
	]
	for view: Dictionary in context_views:
		var selected: Array[FishSchool] = []
		for name: String in view["names"]:
			var school: FishSchool = group.get_node(name) as FishSchool
			selected.append(school)
		await shot(str(view["tag"]), selected, 77.8, str(view["path"]))
	check(frames.size() == 23, "20幅逐群12/18m近景与3幅77.8m环境图")
	check(main.transform.is_equal_approx(main_pose) and world.transform.is_equal_approx(world_pose), "main/World根transform未改")
	check(default_camera.transform.is_equal_approx(default_camera_pose) and is_equal_approx(float(default_camera.get("distance")), default_camera_distance), "默认相机姿态与距离未改；从未调用apply_pose")
	check(material_parameters() == water_parameters, "未修改全局主水美术参数或替换水材质")
	check(unchanged_school_sizes(), "全部鱼群保持真实尺寸和TSCN摆位")
	check(not bool(main.get("_autosave_on")) and bool(clock.get("paused")) and bool(weather.get("paused")), "无自动存档且晴天9点冻结")
	water.transform = water_pose
	finish()

func finish() -> void:
	if shader_time_frozen:
		Engine.time_scale = original_time_scale
		shader_time_frozen = false
	var report: Dictionary = {"render_checks_passed": failures.is_empty(), "checks": checks,
		"failures": failures, "frames": frames, "art_review": "pending",
		"scope": "真实main/主水；10群各12m和18m同机位fish-on/off差分；牧场/旧城/补给站77.8m环境图",
		"minimum_visible_pixels_per_close_school": MIN_PIXELS,
		"fixed_animation_time": FIXED_TIME, "independent_camera": true,
		"limits": "至少3个鱼相关像素仅证明渲染贡献，不证明每条鱼可辨、配色审美或性能通过；远景不强制小鱼像素阈值"}
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	check(file != null, "渲染证据报告可写")
	report["checks"] = checks
	report["failures"] = failures
	report["render_checks_passed"] = failures.is_empty()
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[scenic-fish-render] %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(camera):
		camera.free()
	if is_instance_valid(main):
		main.free()
	quit(0 if failures.is_empty() else 1)
