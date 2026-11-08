extends SceneTree
## 只在统一 runner 的隔离副本运行；不加载 Main、不读写存档。
## headless 验行为；真实 renderer 另验 PNG 像素，不能用实例数代替可见性。
const Materials = preload("res://src/diving/uw_materials.gd")
const DT: float = 1.0 / 60.0
const PREFIX: String = "res://outputs/underwater-experience-"
const SUN: Vector3 = Vector3(0.5191, 0.7787, -0.3523)
const ZERO_TIME: float = 0.000001 # elapsed=0 在现有 shader 中表示 TIME，近零正数才是冻结的 time0。
var checks: int = 0
var failures: int = 0
var report: Dictionary = {"test": "underwater-experience", "fixed_dt": DT,
	"maps": {}, "images": [], "failure_labels": [],
	"isolation": "统一 runner 工程副本；无 Main、无存档访问",
	"time0_shader_value": ZERO_TIME}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		report.failure_labels.append(label)
		printerr("[underwater-experience] FAIL ", label)

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func freeze(map) -> void:
	map.set_process(false)
	map.set_physics_process(false)
	map.dive_controller.set_process(false)
	map.dive_controller.set_physics_process(false)
	map.dive_controller.character.set_process(false)
	for node in map.find_children("*", "", true, false):
		if node.get("autonomous") != null:
			node.set("autonomous", false)
	for layer in map.find_children("*", "CanvasLayer", true, false):
		layer.hide()

func load_map(id: String):
	var path: String = "res://scenes/underwater/sunroom_region.tscn" if id == "home" else "res://scenes/underwater/maps/zone1.tscn"
	var packed: PackedScene = load(path) as PackedScene
	check(packed != null, id + "：独立场景可加载")
	if packed == null:
		return null
	var map = packed.instantiate()
	root.add_child(map)
	current_scene = map
	if id == "zone1":
		var ready_ok: bool = map.setup([], map.get_node("WorldEnvironment"))
		check(ready_ok, "zone1：ready 后 setup([], 本地环境)")
		if not ready_ok:
			map.free()
			return null
	freeze(map)
	if id == "home":
		check(map.begin_dive(Vector3(7.0, float(map.water_level), 5.0)), "home：真实 begin_dive")
		map.dive_controller.character.set_process(false)
		for _i in 120:
			await physics_frame
			if map.entry_verified or map.phase != "enter":
				break
		check(map.entry_verified and map.phase == "enter", "home：等待真实物理 entry_verified")
		if not map.entry_verified:
			map.free()
			return null
		map.dive_controller.machine.tick(DT)
		check(absf(float(map.water_level) - 101.587442) < 0.0001
			and is_equal_approx(float(map.target_depth_m), 120.0)
			and absf(float(map.water_level) - map.dive_position().y - 1.0) < 0.001,
			"home：当前水位101.587442、target120、实际入场深度1m")
	else:
		map.dive(Vector3.ZERO, "zone1")
		check(map.phase == "enter", "zone1：公开 dive 进入 enter")
		map.dive_controller.machine.tick(float(map.ENTER_TIME))
	check(map.phase == "swim", id + "：正常入场进入 swim")
	freeze(map)
	return map

func update_view(map, id: String) -> void:
	if id == "home":
		map._update_underwater_view()
	else:
		map.dive_content_tick(0.0)

func water_node(map, id: String) -> MeshInstance3D:
	return map.get_node("Water") as MeshInstance3D if id == "home" else map.deco._ceiling as MeshInstance3D

func material_contract(map, id: String, values: Dictionary) -> void:
	var water: MeshInstance3D = water_node(map, id)
	var level: float = map.dive_water_level()
	update_view(map, id)
	check(water != null and water.is_visible_in_tree() and absf(water.global_position.y - level) < 0.001,
		id + "：水面实际可见且真实 mesh Y 等于水位")
	var env: Environment = map.get_node("WorldEnvironment").environment
	var fog_count: int = 0
	for mesh in map.find_children("*", "MeshInstance3D", true, false):
		var mat: ShaderMaterial = mesh.material_override as ShaderMaterial
		if mat != null and mat.shader != null and mat.shader.resource_path in [
			"res://shaders/uw_fog.gdshader", "res://shaders/sunroom_underwater_fog.gdshader"]:
			fog_count += 1
	check(fog_count == 1 and not env.fog_enabled, id + "：唯一屏幕 fogpass，Environment.fog_enabled=false")
	var depth: float = maxf(0.0, level - map.dive_position().y)
	var late: ShaderMaterial = Materials.from_color(Color(0.327, 0.418, 0.513))
	check(absf(float(late.get_shader_parameter("water_level")) - level) < 0.001
		and absf(float(late.get_shader_parameter("dive_depth")) - depth) < 0.001,
		id + "：晚创建材质继承绝对水位与实际水深")
	var fog: ShaderMaterial = map._fog_material
	check(absf(float(fog.get_shader_parameter("water_level")) - level) < 0.001
		and absf(float(fog.get_shader_parameter("dive_depth")) - depth) < 0.001,
		id + "：真实 fog 材质注入水位和绝对深度")
	if id == "home":
		var all_levels: bool = true
		for mat in map._palette_materials:
			all_levels = all_levels and absf(float(mat.get_shader_parameter("water_level")) - level) < 0.001
		for mat in [map._surface_material, map._sky_material]:
			all_levels = all_levels and absf(float(mat.get_shader_parameter("water_level")) - level) < 0.001
		check(all_levels, "home：水面/天空/本地实体材质均注入真实水位")
	values.environment = {"water_level": level, "mesh_y": water.global_position.y,
		"absolute_depth": depth, "fog_passes": fog_count, "environment_fog": env.fog_enabled,
		"ambient_light_source": env.ambient_light_source}
	check(env.ambient_light_source != Environment.AMBIENT_SOURCE_DISABLED,
		id + "：场景未禁用ambient，深度减光必须实际作用于实体")

func bubble_pool(node: MultiMeshInstance3D, count: int, label: String) -> void:
	check(node != null and node.multimesh != null, label + "：实际 MultiMesh 非 null")
	if node == null or node.multimesh == null:
		return
	var mm: MultiMesh = node.multimesh
	check(mm.mesh != null and mm.use_colors and mm.instance_count == count, label + "：实例池数量与实例色已装配")
	# dummy renderer不保留MultiMesh颜色/变换回读；此处只验分配，真实回读留给visual分支。
	if DisplayServer.get_name() == "headless":
		return
	var colored: int = 0
	var nonsingular: bool = true
	for i in mm.instance_count:
		var color: Color = mm.get_instance_color(i)
		colored += int(color.a > 0.001 and color.get_luminance() > 0.001)
		nonsingular = nonsingular and absf(mm.get_instance_transform(i).basis.determinant()) > 0.000000001
	check(colored > count / 2, label + "：实际实例颜色非零且大部分有透明度")
	check(nonsingular, label + "：无零scale/singular实例矩阵")

func test_atmosphere(map, values: Dictionary) -> void:
	var atmosphere = map.get_node("Atmosphere")
	var bubbles: MultiMeshInstance3D = atmosphere.get_node("Bubbles")
	var motes: MultiMeshInstance3D = atmosphere.get_node("Motes")
	atmosphere.sample(0.0)
	bubble_pool(bubbles, 192, "home环境泡")
	bubble_pool(motes, 200, "home悬浮颗粒")
	var first: PackedVector3Array = PackedVector3Array()
	var dummy: bool = DisplayServer.get_name() == "headless"
	var states0: Dictionary = atmosphere.snapshot(0.0)
	for i in bubbles.multimesh.instance_count:
		var pose: Transform3D = states0.bubbles[i].transform if dummy else bubbles.multimesh.get_instance_transform(i)
		first.append(pose.origin)
	atmosphere.sample(2.0)
	var states2: Dictionary = atmosphere.snapshot(2.0)
	var rises: int = 0
	for i in first.size():
		var pose: Transform3D = states2.bubbles[i].transform if dummy else bubbles.multimesh.get_instance_transform(i)
		var dy: float = pose.origin.y - first[i].y
		rises += int(dy > 0.1 and dy < 2.0)
	check(rises >= 180, "home：time0/2 实际环境泡 MultiMesh 上升（允许循环回底）")
	var original_level: float = atmosphere.water_level
	var old_stats: Dictionary = atmosphere.statistics()
	var old_box: AABB = bubbles.custom_aabb
	var old_beam: Transform3D = atmosphere.get_node("LightShafts").get_child(0).transform
	var old_entry_y: float = atmosphere.get_node("RayEntries").get_child(0).position.y
	var old_top: float = float(old_stats.particle_ceiling_y)
	var old_nodes: int = atmosphere.find_children("*", "", true, false).size()
	atmosphere.configure_water(original_level + 2.0)
	var raised: Dictionary = atmosphere.statistics()
	var raised_box: AABB = bubbles.custom_aabb
	var raised_beam: Transform3D = atmosphere.get_node("LightShafts").get_child(0).transform
	check(absf(float(raised.particle_ceiling_y) - old_top - 2.0) < 0.001,
		"home：configure_water(+2) 泡顶动态上移2m")
	check(absf(raised_beam.origin.y - old_beam.origin.y - 2.0) < 0.001
		and absf(atmosphere.get_node("RayEntries").get_child(0).position.y - old_entry_y - 2.0) < 0.001,
		"home：configure_water(+2) 光柱与beam顶同步上移")
	check(raised_box.end.y > old_box.end.y + 1.9
		and absf(float(bubbles.material_override.get_shader_parameter("water_level")) - original_level - 2.0) < 0.001,
		"home：configure_water(+2) 实际AABB和粒子材质更新")
	var below: bool = true
	for i in bubbles.multimesh.instance_count:
		below = below and bubbles.multimesh.get_instance_transform(i).origin.y < float(raised.particle_ceiling_y)
	check(below, "home：重采样环境泡不越过动态泡顶")
	atmosphere.configure_water(original_level)
	var restored: Dictionary = atmosphere.statistics()
	check(absf(float(restored.particle_ceiling_y) - old_top) < 0.001
		and bubbles.custom_aabb.is_equal_approx(old_box)
		and atmosphere.get_node("LightShafts").get_child(0).transform.is_equal_approx(old_beam),
		"home：configure_water恢复原水位、泡顶、beam、AABB")
	check(int(restored.bubble_instances) == 192 and int(restored.mote_instances) == 200
		and int(restored.beam_instances) == 10 and bubbles.multimesh.instance_count == 192
		and motes.multimesh.instance_count == 200
		and atmosphere.get_node("LightShafts").get_child_count() == 10
		and atmosphere.find_children("*", "", true, false).size() == old_nodes,
		"home：反复configure不膨胀192/200/10和节点数")
	values.atmosphere = {"before": old_stats, "raised": raised, "restored": restored,
		"rising_instances": rises, "aabb_before": str(old_box), "aabb_raised": str(raised_box)}

func fish_schools(map, id: String) -> Array:
	var schools: Array = []
	if id == "home":
		schools.assign(map.get_node("FishSchools").get_children())
	else:
		for item in map.deco._fish:
			schools.append(item.component)
	return schools

func test_fish(map, id: String, values: Dictionary) -> void:
	var schools: Array = fish_schools(map, id)
	var total: int = 0
	var upper_near_entry: int = 0
	var actual_parts_ok: bool = true
	var decorative: bool = true
	var animated: int = 0
	for school in schools:
		total += school.members.size()
		decorative = decorative and school.get_meta("visual_only", false)
		decorative = decorative and school.find_children("*", "CollisionObject3D", true, false).is_empty()
		school.sample(0.0)
		var first: Transform3D = school.transforms[0]
		var body: MultiMeshInstance3D = school.get_node("Body")
		actual_parts_ok = actual_parts_ok and body.multimesh.instance_count == school.members.size()
		for pose in school.transforms:
			var p: Vector3 = school.global_transform * (pose as Transform3D).origin
			if map.dive_water_level() - p.y < 20.0 and p.distance_to(map.dive_position()) < 30.0:
				upper_near_entry += 1
		school.sample(2.0)
		animated += int(not first.is_equal_approx(school.transforms[0]))
	check(decorative and actual_parts_ok, id + "：鱼为纯装饰、无碰撞且实际Body实例齐全")
	check(animated == schools.size(), id + "：所有鱼群实际变换随time0/2变化")
	if id == "home":
		check(schools.size() == 10 and total == 178, "home：原8群138+浅18+中22=10群178条")
		check(map.get_node("FishSchools/ShallowShoal").members.size() == 18
			and map.get_node("FishSchools/MidwaterShoal").members.size() == 22,
			"home：新增浅/中层数量分别18/22")
		check(upper_near_entry > 0, "home：入场附近上层有实际鱼而非仅海床鱼")
	else:
		check(total == map._fish_specs.size() * 24, "zone1：fish_specs.size*24条实际鱼")
		map.deco.update(0.0, 0.0, map.dive_position(), map.camera)
		bubble_pool(map.deco._bubbles, 96, "zone1旧deco96环境泡")
		var start: Vector3 = map.deco._bubble_mm.get_instance_transform(0).origin
		map.deco.update(0.0, 2.0, map.dive_position(), map.camera)
		if DisplayServer.get_name() != "headless":
			check(map.deco._bubble_mm.get_instance_transform(0).origin.y > start.y + 1.0,
				"zone1：旧deco实际环境泡time0/2上升")
	values.fish = {"schools": schools.size(), "actual_fish": total, "animated_schools": animated,
		"upper_near_entry": upper_near_entry, "decorative_no_collision": decorative}

func effects(runtime, frames: int, active: bool = true) -> void:
	for _i in frames:
		if active:
			runtime.sample_effects(DT)
		else:
			runtime.breath_bubbles.update_breath(DT, false, 0.0, 10.0)

func test_breath(map, id: String, values: Dictionary) -> void:
	var runtime = map.dive_controller
	var breath = runtime.breath_bubbles
	check(breath != null and runtime.has_method("sample_effects") and breath.has_method("update_breath"),
		id + "：controller.breath_bubbles已装配且固定dt公开入口存在")
	if breath == null:
		return
	var level: float = map.dive_water_level()
	breath.configure(runtime.character, level)
	var original_character: Transform3D = runtime.character.global_transform
	# 只在行为夹具中下移模型，确保浅水入场1m不会在一个burst内立即触顶。
	runtime.character.global_position.y = level - 12.0
	breath._rng.seed = 90173
	breath.configure(runtime.character, level)
	effects(runtime, 150)
	var natural: Dictionary = breath.snapshot()
	check(int(natural.active_count) > 0, id + "：2.5s固定步自然呼气出现，不直接emit_one")
	var at_2_5: int = int(natural.active_count)
	var pool: MultiMesh = breath._mm
	check(pool != null and pool.mesh != null and pool.instance_count == 48 and pool.use_colors,
		id + "：实际呼气MultiMesh固定最大48")
	# 等待当前自然burst完成，收集出生时刻，不逐帧输出check或完整状态。
	var births: Dictionary = {}
	var peak: int = 0
	var birth_error: float = 0.0
	var first_state: Dictionary = {}
	for _i in 48:
		effects(runtime, 1)
		var snap: Dictionary = breath.snapshot()
		peak = maxi(peak, int(snap.active_count))
		for bubble in snap.bubbles:
			var key: String = "%.6f" % float(bubble.birth_time)
			if not births.has(key):
				births[key] = true
				if float(snap.time) - float(bubble.birth_time) < DT * 1.5:
					var mouth: Vector3 = runtime.character.mask.to_global(Vector3(0.0, -0.10, 0.32))
					birth_error = maxf(birth_error, (bubble.position as Vector3).distance_to(mouth))
			if first_state.is_empty():
				first_state = bubble.duplicate(true)
	check(births.size() >= 4 and births.size() <= 7, id + "：单次自然burst实际4..7个出生")
	check(runtime.character.mask.is_visible_in_tree() and birth_error > 0.0 and birth_error < 0.10,
		id + "：新泡birth靠近真实mask口部而非角色原点")
	if not first_state.is_empty():
		var old_position: Vector3 = first_state.position
		var old_scale: float = float(first_state.scale)
		runtime.character.global_position += Vector3(5.0, 0.0, 0.0)
		effects(runtime, 12, false)
		var tracked: bool = false
		for bubble in breath.snapshot().bubbles:
			if is_equal_approx(float(bubble.birth_time), float(first_state.birth_time)):
				var now: Vector3 = bubble.position
				tracked = now.y > old_position.y and float(bubble.scale) > old_scale and absf(now.x - old_position.x) < 0.15
		check(tracked, id + "：呼气上升/变大，世界轨迹不随角色平移5m")
	# 固定seed的正常流持续产生多轮，验证池上限及有限矩阵；不人为塞满状态池。
	var matrices_ok: bool = true
	# 空池也要验：不能等所有槽位被历史泡填过后才检查。
	var dummy: bool = DisplayServer.get_name() == "headless"
	if not dummy:
		for j in pool.instance_count:
			matrices_ok = matrices_ok and absf(pool.get_instance_transform(j).basis.determinant()) > 0.000000000001
	for _i in 600:
		effects(runtime, 1)
		peak = maxi(peak, int(breath.snapshot().active_count))
		if not dummy:
			for j in pool.instance_count:
				var pose: Transform3D = pool.get_instance_transform(j)
				matrices_ok = matrices_ok and pose.origin.is_finite() and absf(pose.basis.determinant()) > 0.000000000001
	check(peak >= 4 and peak <= 48, id + "：持续自然生成实际峰值不超过48")
	if not dummy:
		check(matrices_ok, id + "：包括空槽在内无零scale/singular实例矩阵")
	var before_frozen: Dictionary = breath.snapshot()
	var before_air: float = runtime.air.air
	runtime.transition_frozen = true
	for _i in 90:
		runtime.machine.tick(DT)
		runtime.sample_effects(DT)
	check(breath.snapshot() == before_frozen and is_equal_approx(runtime.air.air, before_air),
		id + "：transition_frozen不推进呼气也不耗氧")
	runtime.transition_frozen = false
	# 真正暂停场景树，暂时恢复正式physics回调，以免用手动跳过冒充暂停。
	runtime.set_physics_process(true)
	paused = true
	var paused_before: Dictionary = breath.snapshot()
	var paused_air: float = runtime.air.air
	for _i in 6:
		await physics_frame
	check(breath.snapshot() == paused_before and is_equal_approx(runtime.air.air, paused_air),
		id + "：SceneTree暂停时正式physics不推进呼气或氧气")
	runtime.set_physics_process(false)
	paused = false
	effects(runtime, 360, false)
	var clear_colors: bool = true
	if not dummy:
		for i in pool.instance_count:
			clear_colors = clear_colors and pool.get_instance_color(i).a <= 0.001
	check(int(breath.snapshot().active_count) == 0 and clear_colors,
		id + "：停止发射后自然寿命结束且实际实例alpha清空")
	# 贴水面自然呼气：活泡绝不穿过水位，shader还应在waterfade带渐隐。
	breath.configure(runtime.character, level)
	var head_offset: float = runtime.character.mask.global_position.y - runtime.character.global_position.y
	runtime.character.global_position.y = level - 0.55 - head_offset
	var bounded: bool = true
	var near_surface_count: int = 0
	for _i in 240:
		effects(runtime, 1)
		for bubble in breath.snapshot().bubbles:
			var p: Vector3 = bubble.position
			bounded = bounded and p.y < level - 0.079
			near_surface_count += 1
	var particle_source: String = FileAccess.get_file_as_string("res://shaders/sunroom_underwater_particles.gdshader")
	check(near_surface_count > 0 and bounded and particle_source.contains("surface_fade")
		and float(breath._material.get_shader_parameter("water_fade")) > 0.0,
		id + "：自然呼气进入水面渐隐带且不越界")
	effects(runtime, 360, false)
	runtime.character.global_transform = original_character
	breath.configure(runtime.character, level)
	values.breath = {"natural_2_5s_count": at_2_5, "burst_births": births.size(), "peak": peak,
		"max_birth_error_m": birth_error, "finite_nonsingular_pool": matrices_ok,
		"near_surface_observations": near_surface_count}

func roi(image: Image, area: Rect2) -> Dictionary:
	var rect: Rect2i = Rect2i(Vector2i(area.position * Vector2(image.get_size())),
		Vector2i(area.size * Vector2(image.get_size()))).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var sum: float = 0.0
	var peak: float = 0.0
	var clipped: int = 0
	var count: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c: Color = image.get_pixel(x, y)
			var light: float = c.get_luminance()
			sum += light
			peak = maxf(peak, light)
			clipped += int(c.r >= 0.98 and c.g >= 0.98 and c.b >= 0.98)
			count += 1
	return {"mean_luminance": sum / maxi(count, 1), "peak": peak,
		"white_fraction": float(clipped) / maxi(count, 1), "pixels": count, "rect": str(rect)}

func difference(a: Image, b: Image, area: Rect2) -> Dictionary:
	var rect: Rect2i = Rect2i(Vector2i(area.position * Vector2(a.get_size())),
		Vector2i(area.size * Vector2(a.get_size()))).intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var sum: float = 0.0
	var peak: float = 0.0
	var changed: int = 0
	var count: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			var d: float = maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			sum += d
			peak = maxf(peak, d)
			changed += int(d > 0.008)
			count += 1
	return {"mean_abs_rgb": sum / maxi(count, 1), "peak": peak, "changed_pixels": changed,
		"changed_fraction": float(changed) / maxi(count, 1), "pixels": count, "rect": str(rect)}

func shot(tag: String) -> Image:
	# 所有调用均在renderer分支；headless绝不等待frame_post_draw。
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), tag + "：真实帧非空")
	if image != null and not image.is_empty():
		var path: String = PREFIX + tag + ".png"
		check(image.save_png(path) == OK, tag + "：PNG保存成功")
		report.images.append(path)
	return image

func optical_view(map, id: String, camera: Camera3D, time: float) -> void:
	# 光学夹具只移动相机：短暂提供view采样位置后还原逻辑坐标，绝不update_character。
	var model_pose: Transform3D = map.dive_controller.character.global_transform
	if id == "home":
		var diving: bool = map._diving
		map._diving = false
		map._update_underwater_view()
		map._diving = diving
		map._surface_material.set_shader_parameter("elapsed", time)
		map.get_node("Atmosphere").sample(time)
	else:
		var player: Vector3 = map.diver_pos
		map.diver_pos = camera.global_position
		map._update_sky(maxf(0.0, map.dive_water_level() - camera.global_position.y))
		map.deco.update(0.0, time, camera.global_position, camera)
		map.diver_pos = player
	Materials.freeze_time(time)
	assert(map.dive_controller.character.global_transform.is_equal_approx(model_pose))

func view_direction() -> Vector3:
	# 水->空气折射的逆向标定；中心视线朝太阳所在的Snell窗，不是水平拍一层蓝色。
	var sun: Vector3 = SUN.normalized()
	var xz: Vector2 = Vector2(sun.x, sun.z) / 1.333
	return Vector3(xz.x, sqrt(1.0 - xz.length_squared()), xz.y).normalized()

func clear_view(map, from: Vector3, direction: Vector3, level: float) -> bool:
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var length: float = (level - from.y) / direction.y
	for offset in [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from + offset, from + offset + direction * length, 1)
		if not space.intersect_ray(ray).is_empty():
			return false
	return true

func choose_column(map, id: String, depths: Array) -> Vector2:
	var candidates: Array = [Vector2(0, -35), Vector2(25, -35), Vector2(-25, -35),
		Vector2(0, -60), Vector2(-60, -60), Vector2(60, -60), Vector2(-180, -180), Vector2(-260, -260)]
	if id == "zone1":
		candidates = [Vector2(0, 12), Vector2(0, 0), Vector2(-5, 15)]
	for candidate in candidates:
		var safe: bool = true
		for depth in depths:
			var point: Vector3 = Vector3(candidate.x, map.dive_water_level() - float(depth), candidate.y)
			if id == "home":
				safe = safe and clear_view(map, point, view_direction(), map.dive_water_level())
			else:
				safe = safe and not map.blocked(point)
		if safe:
			return candidate
	check(false, id + "：找不到跨深度仰视净空机位")
	return candidates[0]

func test_surface_pixels(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	var depths: Array = [5.0, 30.0, 70.0, 115.0] if id == "home" else [10.0, 60.0]
	var column: Vector2 = choose_column(map, id, depths)
	var water: MeshInstance3D = water_node(map, id)
	var surface_area: Rect2 = Rect2(0.1, 0.1, 0.8, 0.8)
	var rows: Array = []
	var previous_light: float = INF
	for depth in depths:
		camera.global_position = Vector3(column.x, map.dive_water_level() - float(depth), column.y)
		camera.look_at(camera.global_position + view_direction(), Vector3.UP)
		optical_view(map, id, camera, ZERO_TIME)
		check((-camera.global_basis.z).y > 0.65, id + "：实际镜头向上仰视 depth=" + str(depth))
		var lit: Image = await shot(id + "-up-depth-" + str(int(depth)))
		water.hide()
		var hidden: Image = await shot(id + "-up-depth-" + str(int(depth)) + "-water-off")
		water.show()
		var water_delta: Dictionary = difference(lit, hidden, surface_area)
		check(float(water_delta.changed_fraction) > 0.015 and float(water_delta.mean_abs_rgb) > 0.002,
			id + "：真实仰视Water开关像素可见 depth=" + str(depth))
		var stats: Dictionary = roi(lit, surface_area)
		var brightness: float = float(stats.mean_luminance)
		check(brightness < previous_light - 0.0005, id + "：同姿态水面ROI随深度单调减光 depth=" + str(depth))
		previous_light = brightness
		var row: Dictionary = {"depth": depth, "camera": vector(camera.global_position),
			"forward": vector(-camera.global_basis.z), "surface_roi": stats, "water_on_off": water_delta}
		if depth == depths[0]:
			optical_view(map, id, camera, 2.0 + ZERO_TIME)
			var later: Image = await shot(id + "-up-wave-time2")
			var wave_delta: Dictionary = difference(lit, later, surface_area)
			check(float(wave_delta.changed_fraction) > 0.01 and float(wave_delta.mean_abs_rgb) > 0.001,
				id + "：冻结time0/2波纹真实像素变化")
			optical_view(map, id, camera, ZERO_TIME)
			map.configure_underwater_light({"direction": SUN.normalized(), "strength": 0.0})
			optical_view(map, id, camera, ZERO_TIME)
			var dark: Image = await shot(id + "-up-sun-off")
			var sun_delta: Dictionary = difference(lit, dark, Rect2(0.3, 0.25, 0.4, 0.5))
			var sun_on: Dictionary = roi(lit, Rect2(0.3, 0.25, 0.4, 0.5))
			var sun_off: Dictionary = roi(dark, Rect2(0.3, 0.25, 0.4, 0.5))
			check(float(sun_delta.changed_fraction) > 0.03 and float(sun_on.mean_luminance) > float(sun_off.mean_luminance) + 0.003,
				id + "：朝向光源configure_underwater_light强度1/0太阳ROI真实变暗")
			row.wave_time0_time2 = wave_delta
			row.sun_on_off = sun_delta
			map.configure_underwater_light({"direction": SUN.normalized(), "strength": 1.0})
		rows.append(row)
	values.surface_pixels = {"clear_column_xz": [column.x, column.y], "depths": rows}

func test_gray_sample(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	var sample: MeshInstance3D = MeshInstance3D.new()
	sample.name = "OpticalNeutralGraySample"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE * 0.9
	sample.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.35, 0.35)
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	sample.material_override = material
	sample.layers = 2
	sample.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map.add_child(sample)
	# 样板只接当前场景ambient，不接设施灯/头灯/直射，避免城市灯和相机fill污染深度比较。
	var light_masks: Dictionary = {}
	for light in map.find_children("*", "Light3D", true, false):
		light_masks[light] = light.light_cull_mask
		light.light_cull_mask = int(light.light_cull_mask) & ~2
	var depths: Array = [5.0, 30.0, 70.0, 115.0] if id == "home" else [10.0, 60.0]
	var previous_sample: float = INF
	var previous_background: float = INF
	var rows: Array = []
	for depth in depths:
		# 离开城区，在同scene/environment中保持同朝向、同物体、相机相对3m。
		camera.global_position = Vector3(360.0 if id == "home" else 140.0,
			map.dive_water_level() - float(depth), -300.0 if id == "home" else 140.0)
		camera.look_at(camera.global_position + view_direction())
		sample.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 3.0)
		optical_view(map, id, camera, ZERO_TIME)
		var image: Image = await shot(id + "-gray-depth-" + str(int(depth)))
		if depth == depths[0]:
			sample.hide()
			var without_sample: Image = await shot(id + "-gray-sample-off")
			sample.show()
			var sample_delta: Dictionary = difference(image, without_sample, Rect2(0.47, 0.47, 0.06, 0.06))
			check(float(sample_delta.mean_abs_rgb) > 0.02,
				id + "：样板ROI确实落在真实不透明box上，开关有像素差")
			values.gray_sample_on_off = sample_delta
		var sample_stats: Dictionary = roi(image, Rect2(0.47, 0.47, 0.06, 0.06))
		var background_stats: Dictionary = roi(image, Rect2(0.1, 0.08, 0.8, 0.20))
		var sample_light: float = float(sample_stats.mean_luminance)
		var background_light: float = float(background_stats.mean_luminance)
		check(sample_light > 0.005 and sample_light < previous_sample - 0.0005
			and float(sample_stats.white_fraction) < 0.001,
			id + "：不透明中性灰样板ambient单调减光且不过曝 depth=" + str(depth))
		check(background_light < previous_background - 0.0005,
			id + "：样板以外同背景ROI单调减光 depth=" + str(depth))
		previous_sample = sample_light
		previous_background = background_light
		rows.append({"depth": depth, "distance_m": 3.0, "camera": vector(camera.global_position),
			"sample_roi": sample_stats, "surface_background_roi": background_stats,
			"ambient_energy": map.get_node("WorldEnvironment").environment.ambient_light_energy})
	for light in light_masks:
		light.light_cull_mask = light_masks[light]
	sample.free()
	values.gray_optical_sample = rows

func test_particle_pixels(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	var runtime = map.dive_controller
	var breath = runtime.breath_bubbles
	var model_pose: Transform3D = runtime.character.global_transform
	# 恢复行为原点的view参数，取真实角色口部附近的自然生成泡，不替换shader。
	update_view(map, id)
	breath._rng.seed = 90173
	breath.configure(runtime.character, map.dive_water_level())
	var captured: bool = false
	for _i in 240:
		effects(runtime, 1)
		if int(breath.snapshot().active_count) > 0:
			captured = true
			break
	check(captured, id + "：近景像素夹具由自然呼气触发，不要求1m浅水同时存活4泡")
	effects(runtime, 5, false)
	var snap: Dictionary = breath.snapshot()
	if not snap.bubbles.is_empty():
		var center: Vector3 = snap.bubbles[0].position
		camera.global_position = center + runtime.character.global_basis.z.normalized() * 1.4
		camera.look_at(center)
		var on: Image = await shot(id + "-breath-on")
		breath.hide()
		var off: Image = await shot(id + "-breath-off")
		breath.show()
		var delta: Dictionary = difference(on, off, Rect2(0.15, 0.15, 0.7, 0.7))
		check(int(delta.changed_pixels) >= 8 and float(delta.peak) > 0.015,
			id + "：近距自然呼气真实on/off像素差")
		values.breath_pixels = delta
		values.breath_render_state = {"snapshot":str(snap), "camera":vector(camera.global_position),
			"mask":vector(runtime.character.mask.global_position), "bounds":str(breath._instances.custom_aabb),
			"color":str(breath._mm.get_instance_color(0)), "pose":str(breath._mm.get_instance_transform(0)),
			"uniform_water":breath._material.get_shader_parameter("water_level"),
			"uniform_depth":breath._material.get_shader_parameter("dive_depth")}
	var bubble_node: MultiMeshInstance3D
	if id == "home":
		map.get_node("Atmosphere").sample(2.0)
		bubble_node = map.get_node("Atmosphere/Bubbles")
	else:
		map.deco.update(0.0, 2.0, map.dive_position(), camera)
		bubble_node = map.deco._bubbles
	var mm: MultiMesh = bubble_node.multimesh
	var selected: int = -1
	for i in mm.instance_count:
		var position: Vector3 = bubble_node.to_global(mm.get_instance_transform(i).origin)
		if mm.get_instance_color(i).a > 0.4 and position.y < map.dive_water_level() - 2.0:
			selected = i
			break
	check(selected >= 0, id + "：环境泡近景选择实际有alpha的MultiMesh实例")
	# 即使实例色损坏也保存on/off失败证据，不能跳过视觉项后拿结构失败代替。
	if selected < 0 and mm.instance_count > 0:
		selected = 0
	if selected >= 0:
		var center: Vector3 = bubble_node.to_global(mm.get_instance_transform(selected).origin)
		camera.global_position = center + Vector3(0, 0.05, -1.6)
		camera.look_at(center)
		var on: Image = await shot(id + "-ambient-bubble-on")
		bubble_node.hide()
		var off: Image = await shot(id + "-ambient-bubble-off")
		bubble_node.show()
		var delta: Dictionary = difference(on, off, Rect2(0.2, 0.2, 0.6, 0.6))
		check(int(delta.changed_pixels) >= 6 and float(delta.peak) > 0.01,
			id + "：环境泡实际on/off像素差")
		values.ambient_bubble_pixels = delta
	var schools: Array = fish_schools(map, id)
	var school = map.get_node("FishSchools/ShallowShoal") if id == "home" else schools[0]
	school.sample(2.0)
	var fish_pose: Transform3D = school.transforms[0]
	var fish_position: Vector3 = school.global_transform * fish_pose.origin
	camera.global_position = fish_position + Vector3(0.0, 0.3, 3.0)
	camera.look_at(fish_position)
	var fish_on: Image = await shot(id + "-fish-on")
	for item in schools:
		item.hide()
	var fish_off: Image = await shot(id + "-fish-off")
	for item in schools:
		item.show()
	var fish_delta: Dictionary = difference(fish_on, fish_off, Rect2(0.2, 0.2, 0.6, 0.6))
	check(int(fish_delta.changed_pixels) >= 12 and float(fish_delta.peak) > 0.015,
		id + "：真实鱼on/off像素差而非实例计数")
	values.fish_pixels = fish_delta
	check(runtime.character.global_transform.is_equal_approx(model_pose), id + "：全部视觉取样不移动用户模型")

func render_map(map, id: String, values: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		values.visual_mode = "headless仅行为；不等待frame_post_draw，不声称视觉通过"
		return
	var camera: Camera3D = map.dive_controller.camera
	var original_camera: Transform3D = camera.global_transform
	camera.make_current()
	map.air.lamp = false
	map.configure_underwater_light({"direction": SUN.normalized(), "strength": 1.0})
	update_view(map, id)
	await test_surface_pixels(map, id, camera, values)
	await test_gray_sample(map, id, camera, values)
	await test_particle_pixels(map, id, camera, values)
	camera.global_transform = original_camera
	values.visual_mode = "真实renderer，PNG已在脚本内执行ROI验收"

func finish() -> void:
	var path: String = PREFIX + ("behavior" if DisplayServer.get_name() == "headless" else "visual") + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "隔离副本JSON可写")
	report.checks = checks
	report.failures = failures
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[underwater-experience] %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func run() -> void:
	var project: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var user_slot: String = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	if not user_slot.begins_with("sea-verification/") or not project.ends_with("/project"):
		printerr("[underwater-experience] 拒绝主工程运行；必须使用统一runner隔离副本")
		quit(2)
		return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs")) == OK,
		"副本outputs目录可用")
	var economy: Node = root.get_node_or_null("Economy")
	if economy != null:
		economy.set_process(false)
		economy.set_physics_process(false)
	for id in ["home", "zone1"]:
		var map = await load_map(id)
		if map == null:
			continue
		var values: Dictionary = {"entry": vector(map.dive_position())}
		report.maps[id] = values
		material_contract(map, id, values)
		if id == "home":
			test_atmosphere(map, values)
		test_fish(map, id, values)
		await test_breath(map, id, values)
		await render_map(map, id, values)
		current_scene = null
		map.free()
		await process_frame
		Materials.clear_cache()
	if DisplayServer.get_name() != "headless":
		check(report.maps.size() == 2 and report.images.size() == 36, "真实渲染覆盖两图六深度与光学/粒子/鱼对照PNG")
	finish()
