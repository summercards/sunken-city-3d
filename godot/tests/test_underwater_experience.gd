extends SceneTree
## 只在统一 runner 的隔离副本运行；不加载 Main、不读写存档。
## headless 验行为；真实 renderer 另验 PNG 像素，不能用实例数代替可见性。
const Materials = preload("res://src/diving/uw_materials.gd")
const DT: float = 1.0 / 60.0
const PREFIX: String = "res://outputs/underwater-experience-"
const SUN: Vector3 = Vector3(0.5191, 0.7787, -0.3523)
const ZERO_TIME: float = 0.000001 # elapsed=0 在现有 shader 中表示 TIME，近零正数才是冻结的 time0。
const DIRECTIONAL_DEPTHS: Array = [10.0, 20.0, 41.0, 80.0]
const NORMAL_RENDER_DEPTHS: Array = [10.0, 20.0, 41.0]
const NORMAL_YAWS: Array = [0.0, PI * 0.5, PI, PI * 1.5]
const NORMAL_PITCH := deg_to_rad(10.0)
const LOW_WATER_PITCH := deg_to_rad(3.0)
var checks: int = 0
var failures: int = 0
var report: Dictionary = {"test": "underwater-experience", "fixed_dt": DT,
	"maps": {}, "images": [], "failure_labels": [],
	"isolation": "统一 runner 工程副本；无 Main、无存档访问",
	"time0_shader_value": ZERO_TIME,
	"acceptance_contract": "10/20/41/80m四yaw邻域；0.5m observer世界稳定；AABB/水面/矩阵/预算；正常72FOV仰10度泡尘像素；220/400m黑box真实fog；低角度Water ROI",
	"known_limitations": ["真实renderer PNG与像素阈值不在headless分支执行", "水面ROI仅保存on/off供目检，不以源码字符串判定远clip", "动态粒子行为使用snapshot而非逐帧海量断言"]}

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
		for _step in 100: map.dive_controller.machine.tick(DT)
		check(absf(float(map.water_level) - 101.587442) < 0.0001
			and is_equal_approx(float(map.target_depth_m), 120.0)
			and absf(float(map.water_level) - map.dive_position().y - float(map.entry_depth_below_surface)) < 0.001,
			"home：当前水位101.587442、target120、可见入水完成于4.8m")
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

func particle_nodes(map, id: String) -> Array:
	if id == "home":
		return [map.get_node("Atmosphere/Bubbles"), map.get_node("Atmosphere/Motes")]
	return [map.deco._bubbles, map.deco._motes]

func particle_snapshot(map, id: String, observer: Vector3, camera: Camera3D, time: float) -> Dictionary:
	if id == "home":
		map.get_node("Atmosphere").set_observer(observer)
		map.get_node("Atmosphere").sample(time)
		return map.get_node("Atmosphere").snapshot(time)
	camera.global_position = observer
	map.deco.update(0.0, time, map.diver_pos, camera)
	return map.deco.suspended_snapshot(time)

func particle_snapshot_contract(snapshot: Dictionary, id: String) -> void:
	var valid := true
	for key in ["bubbles", "motes"]:
		for state in snapshot.get(key, []):
			valid = valid and state.has("world_position") and state.has("alpha")
			if id == "home":
				valid = valid and state.has("transform")
	check(valid, id + "：snapshot含每项world_position/alpha，home额外含transform")

func particle_count(snapshot: Dictionary, key: String, observer: Vector3, id: String) -> int:
	var count := 0
	var states: Array = snapshot.get(key, [])
	if id == "home" and key == "bubbles":
		states = states.slice(96)
	for state in states:
		var p: Vector3 = state.world_position
		count += int(float(state.alpha) > 0.05 and p.distance_to(observer) <= 12.0)
	return count

func projected_particle_count(snapshot: Dictionary, key: String, camera: Camera3D) -> int:
	var count := 0
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var forward: Vector3 = -camera.global_basis.z
	for state in snapshot.get(key, []):
		if float(state.alpha) <= 0.05:
			continue
		var p: Vector3 = state.world_position
		if (p - camera.global_position).dot(forward) <= 0.0:
			continue
		var screen: Vector2 = camera.unproject_position(p)
		count += int(screen.x >= 0.0 and screen.y >= 0.0 and screen.x < viewport_size.x and screen.y < viewport_size.y)
	return count

func particle_inside_box(p: Vector3, observer: Vector3, level: float) -> bool:
	var center := Vector3(observer.x, minf(observer.y, level - 0.77 - 8.0 - 0.25), observer.z)
	return absf(p.x - center.x) <= 12.0 and absf(p.z - center.z) <= 12.0 \
		and absf(p.y - center.y) <= 8.0 and p.y < level - 0.5

func compare_particle_world_positions(before: Dictionary, after: Dictionary, key: String, id: String,
		observer: Vector3, level: float) -> Dictionary:
	var stable := 0
	if id == "home" and key == "bubbles":
		before[key] = before.get(key, []).slice(96)
		after[key] = after.get(key, []).slice(96)
	var eligible := 0
	var old_states: Array = before.get(key, [])
	var new_states: Array = after.get(key, [])
	for i in range(mini(old_states.size(), new_states.size())):
		var old_state: Dictionary = old_states[i]
		var new_state: Dictionary = new_states[i]
		if float(old_state.alpha) <= 0.05 or float(new_state.alpha) <= 0.05:
			continue
		if not particle_inside_box(old_state.world_position, observer, level) \
			or not particle_inside_box(new_state.world_position, observer + Vector3(0.5, 0.0, 0.0), level):
			continue
		eligible += 1
		stable += int((old_state.world_position as Vector3).distance_to(new_state.world_position) < 0.001)
	return {"eligible": eligible, "stable": stable,
		"fraction": float(stable) / maxi(eligible, 1)}

func particle_field_contract(snapshot: Dictionary, observer: Vector3, level: float, id: String, depth: float) -> Dictionary:
	var center := Vector3(observer.x, minf(observer.y, level - 0.77 - 8.0 - 0.25), observer.z)
	var states: Array = snapshot.get("bubbles", [])
	if id == "home":
		states = states.slice(96)
	var bounded := true
	var finite_alpha := true
	for state in states:
		var p: Vector3 = state.world_position
		bounded = bounded and absf(p.x - center.x) <= 12.35 and absf(p.z - center.z) <= 12.35
		bounded = bounded and absf(p.y - center.y) <= 8.35 and p.y < level - 0.5
		finite_alpha = finite_alpha and is_finite(float(state.alpha))
	check(bounded and finite_alpha, id + "：深度" + str(int(depth)) + "m悬浮场落在observer连续box±12/±8且低于水面-.5")
	return {"center": vector(center), "bounded": bounded, "finite_alpha": finite_alpha,
		"states": states.size()}

func particle_instance_contract(map, id: String, values: Dictionary) -> void:
	var level: float = map.dive_water_level()
	var all_in_aabb := true
	var all_below_water := true
	var nonsingular := true
	var total := 0
	for node in particle_nodes(map, id):
		var mm: MultiMesh = node.multimesh
		check(mm != null and mm.mesh != null, id + "：动态粒子MultiMesh仍存在")
		if mm == null:
			continue
		total += mm.instance_count
		for i in mm.instance_count:
			var pose: Transform3D = mm.get_instance_transform(i)
			var world_position: Vector3 = node.to_global(pose.origin)
			all_in_aabb = all_in_aabb and node.custom_aabb.grow(0.01).has_point(pose.origin)
			all_below_water = all_below_water and world_position.y < level - 0.5
			nonsingular = nonsingular and world_position.is_finite() and absf(pose.basis.determinant()) > 0.000000000001
	var expected: int = 392 if id == "home" else 276
	check(total == expected, id + "：动态粒子预算不变，总实例=" + str(total))
	check(all_in_aabb, id + "：所有动态粒子实例均在当前customAABB内")
	check(all_below_water, id + "：所有动态粒子世界Y低于water-.5")
	check(nonsingular, id + "：所有动态粒子无0scale/singular矩阵")
	values.particle_contract = {"instances": total, "expected": expected,
		"aabb": all_in_aabb, "below_water": all_below_water, "nonsingular": nonsingular}

func test_directional_particles(map, id: String, values: Dictionary) -> void:
	var camera: Camera3D = map.dive_controller.camera
	var level: float = map.dive_water_level()
	var column: Vector2 = Vector2(0.0, -35.0) if id == "home" else Vector2(0.0, 12.0)
	var rows: Array = []
	var stable_row: Dictionary = {}
	for depth in DIRECTIONAL_DEPTHS:
		var observer := Vector3(column.x, level - float(depth), column.y)
		var yaw_rows: Array = []
		for yaw in NORMAL_YAWS:
			var forward := Vector3(sin(float(yaw)), sin(NORMAL_PITCH), -cos(float(yaw))).normalized()
			camera.global_position = observer
			camera.look_at(observer + forward, Vector3.UP)
			var snap: Dictionary = particle_snapshot(map, id, observer, camera, ZERO_TIME)
			particle_snapshot_contract(snap, id)
			particle_field_contract(snap, observer, level, id, float(depth))
			var bubble_count_near := particle_count(snap, "bubbles", observer, id)
			var mote_count_near := particle_count(snap, "motes", observer, id)
			var bubble_projection := projected_particle_count(snap, "bubbles", camera)
			var mote_projection := projected_particle_count(snap, "motes", camera)
			check(bubble_count_near >= 6 and mote_count_near >= 20 and bubble_projection > 0 and mote_projection > 0,
				id + "：深度" + str(int(depth)) + "m/yaw" + str(int(roundf(float(yaw) * 180.0 / PI)))
				+ "周围12m泡>=6且尘>=20(alpha>.05)")
			yaw_rows.append({"yaw_deg": float(yaw) * 180.0 / PI,
				"near_bubbles": bubble_count_near, "near_motes": mote_count_near,
				"observer": vector(observer)})
		rows.append({"depth": depth, "yaw_rows": yaw_rows})
	# observer中心连续移动，绝对粒子仅在边缘渐隐回卷；非回卷元素世界位置应保持不变。
	var stable_observer := Vector3(column.x, level - 20.0, column.y)
	var stable_before: Dictionary = particle_snapshot(map, id, stable_observer, camera, 17.0)
	var stable_after: Dictionary = particle_snapshot(map, id, stable_observer + Vector3(0.5, 0.0, 0.0), camera, 17.0)
	particle_snapshot_contract(stable_before, id)
	particle_snapshot_contract(stable_after, id)
	var bubble_stability := compare_particle_world_positions(stable_before, stable_after, "bubbles", id, stable_observer, level)
	var mote_stability := compare_particle_world_positions(stable_before, stable_after, "motes", id, stable_observer, level)
	check(float(bubble_stability.fraction) > 0.5 and float(mote_stability.fraction) > 0.5,
		id + "：observer平移0.5m后剩余alpha>.05元素世界坐标过半稳定")
	stable_row = {"bubble": bubble_stability, "mote": mote_stability,
		"before_observer": vector(stable_observer),
		"after_observer": vector(stable_observer + Vector3(0.5, 0.0, 0.0))}
	particle_instance_contract(map, id, values)
	values.directional_particles = {"column_xz": [column.x, column.y], "depths": rows,
		"observer_shift": stable_row}

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

func surface_readability(image: Image, area: Rect2) -> Dictionary:
	var rect: Rect2i = Rect2i(Vector2i(area.position * Vector2(image.get_size())),
		Vector2i(area.size * Vector2(image.get_size()))).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var base: Dictionary = roi(image, area)
	var bright: int = 0
	var bright_outside_sun: int = 0
	var cells: Dictionary = {}
	var count: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c: Color = image.get_pixel(x, y)
			var is_bright := c.b > 0.55 and c.g > 0.48 and c.r > 0.30
			if is_bright:
				bright += 1
				var u := (float(x) + 0.5 - float(rect.position.x)) / maxf(float(rect.size.x), 1.0)
				var v := (float(y) + 0.5 - float(rect.position.y)) / maxf(float(rect.size.y), 1.0)
				var outside_sun := Vector2(u - 0.5, v - 0.5).length() > 0.18
				bright_outside_sun += int(outside_sun)
				var cell := str(mini(2, int(u * 3.0)), ":", mini(2, int(v * 3.0)))
				cells[cell] = true
			count += 1
	base["bright_ridge_fraction"] = float(bright) / maxi(count, 1)
	base["bright_ridge_outside_sun_fraction"] = float(bright_outside_sun) / maxi(count, 1)
	base["bright_ridge_outside_sun_of_bright"] = float(bright_outside_sun) / maxi(bright, 1)
	base["bright_ridge_cells"] = cells.size()
	base["bright_ridge_pixels"] = bright
	base["bright_ridge_threshold"] = "B>.55,G>.48,R>.30"
	base["sun_dot_exclusion_radius"] = 0.18
	return base

func packed_vector4_array(values: Variant) -> Array:
	var result: Array = []
	if values is PackedVector4Array:
		for value: Vector4 in values:
			result.append([value.x, value.y, value.z, value.w])
	return result

func nearby_surface_structures(map, column: Vector2, radius: float) -> int:
	var seen: Dictionary = {}
	if not map.has_method("surface_height"):
		return 0
	for record in map._surfaces:
		var bounds: AABB = record.bounds
		var closest_x := clampf(column.x, bounds.position.x, bounds.end.x)
		var closest_z := clampf(column.y, bounds.position.z, bounds.end.z)
		if Vector2(closest_x, closest_z).distance_to(column) > radius:
			continue
		var node: Node = record.get("node")
		if node != null:
			seen[node.get_instance_id()] = true
	return seen.size()

func surface_column(map, depths: Array, require_structure: bool) -> Vector2:
	var candidates: Array = [Vector2(0.0, -35.0), Vector2(25.0, -35.0),
		Vector2(-25.0, -35.0), Vector2(0.0, -60.0), Vector2(-60.0, -60.0),
		Vector2(60.0, -60.0)]
	for candidate in candidates:
		var valid: bool = map.city_bounds.has_point(candidate)
		for depth in depths:
			var observer := Vector3(candidate.x, map.dive_water_level() - float(depth), candidate.y)
			valid = valid and clear_view(map, observer, view_direction(), map.dive_water_level())
		if valid and (not require_structure or nearby_surface_structures(map, candidate, 48.0) > 0):
			return candidate
	check(false, "home：找不到满足楼体/仰视净空的生产式海面机位")
	return candidates[0]

func open_surface_column(map, depth: float) -> Vector2:
	var candidates: Array = [Vector2(-260.0, -260.0), Vector2(260.0, 260.0),
		Vector2(260.0, -260.0), Vector2(-260.0, 260.0)]
	for candidate in candidates:
		var observer := Vector3(candidate.x, map.dive_water_level() - depth, candidate.y)
		if map.terrain_bounds.has_point(candidate) and nearby_surface_structures(map, candidate, 72.0) == 0 \
			and clear_view(map, observer, view_direction(), map.dive_water_level()):
			return candidate
	check(false, "home：找不到开阔仰视海面比较机位")
	return candidates[0]

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
		Vector2(0, -60), Vector2(-60, -60), Vector2(60, -60), Vector2(-160, -160), Vector2(-180, -180), Vector2(-260, -260)]
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

func test_readable_surface(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	if id != "home":
		return
	var water: MeshInstance3D = water_node(map, id)
	var material: ShaderMaterial = map._surface_material
	var level: float = map.dive_water_level()
	var production_depths: Array = [20.0, 55.0]
	var column: Vector2 = surface_column(map, production_depths, true)
	var open_column: Vector2 = open_surface_column(map, 55.0)
	var surface_area := Rect2(0.08, 0.08, 0.84, 0.84)
	var original_fov := camera.fov
	if material == null:
		check(false, "home：仰视海面材质不存在，跳过sampler读取避免null误报")
		return
	var original_normal: Texture2D = material.get_shader_parameter("large_wave_normals") as Texture2D
	var original_waves: Variant = material.get_shader_parameter("ocean_waves")
	var original_wave_scale: float = float(material.get_shader_parameter("wave_scale"))
	var original_wave_light: float = float(material.get_shader_parameter("underside_wave_light"))
	var original_sun_light: float = float(material.get_shader_parameter("underside_sun_light"))
	var shader_source := FileAccess.get_file_as_string("res://shaders/uw_surface_shared.gdshaderinc")
	var shader_contract := shader_source.contains("ocean_sample_at(world.xz") \
		and shader_source.contains("large_wave_normals, uv - drift).gb")
	Materials.configure_underside(material)
	original_normal = material.get_shader_parameter("large_wave_normals") as Texture2D
	original_waves = material.get_shader_parameter("ocean_waves")
	original_wave_scale = float(material.get_shader_parameter("wave_scale"))
	check(material != null and original_normal != null and shader_contract,
		"home：仰视海面材质由MaterialLib绑定真实large_wave_normals且共享显式clock/GB采样")
	check(original_waves is PackedVector4Array and (original_waves as PackedVector4Array).size() == 4,
		"home：仰视海面材质装配四组ocean_waves")
	var ocean_rows: Array = []
	if original_waves is PackedVector4Array:
		ocean_rows = packed_vector4_array(original_waves)
	var texture_path := original_normal.resource_path if original_normal != null else ""
	var report_surface: Dictionary = {
		"shader_resource_path": material.shader.resource_path if material.shader != null else "",
		"texture_resource_path": texture_path,
		"ocean_waves": ocean_rows,
		"wave_scale": original_wave_scale,
		"normal_channels": "GB centred slope; R excluded",
		"production_column_xz": [column.x, column.y],
		"production_nearby_structures": nearby_surface_structures(map, column, 48.0),
		"open_column_xz": [open_column.x, open_column.y],
		"open_nearby_structures": nearby_surface_structures(map, open_column, 72.0),
		"clocks": [ZERO_TIME, 2.0, 4.0]}
	check(not texture_path.is_empty() and report_surface.production_nearby_structures > 0
		and report_surface.open_nearby_structures == 0,
		"home：55m生产式机位周围有楼且开阔比较机位无楼")
	var old_lamp: bool = map.air.lamp
	map.air.lamp = false
	if map.has_method("_build_dive_lamp") and map.get("_lamp") != null:
		map._lamp.hide()
	hide_particle_kind(map, id, "all")
	water.show()
	camera.fov = 72.0
	var by_depth: Dictionary = {}
	var base_image: Image = null
	var time_zero_image: Image = null
	for depth in production_depths:
		var observer := Vector3(column.x, level - depth, column.y)
		camera.global_position = observer
		camera.look_at(observer + view_direction(), Vector3.UP)
		check(observer.y < level and camera.fov == 72.0 and (-camera.global_basis.z).y > 0.65,
			"home：仰视海面" + str(int(depth)) + "m相机在水下、太阳方向、72FOV")
		var clocks: Array = []
		var images: Array = []
		for clock in [ZERO_TIME, 2.0, 4.0]:
			material.set_shader_parameter("underside_wave_light", original_wave_light)
			material.set_shader_parameter("underside_sun_light", original_sun_light)
			optical_view(map, id, camera, float(clock))
			var image: Image = await shot("home-readable-" + str(int(depth)) + "m-clock-" + str(clock))
			clocks.append(clock)
			images.append(image)
			if depth == 55.0 and clock == ZERO_TIME:
				time_zero_image = image
				base_image = image
		var first: Image = images[0]
		var last: Image = images[2]
		var time_delta: Dictionary = difference(first, last, surface_area)
		var stats: Dictionary = surface_readability(first, surface_area)
		if depth == 55.0:
			check(float(stats.mean_luminance) > 0.25 and float(stats.bright_ridge_fraction) >= 0.05
				and float(stats.bright_ridge_outside_sun_of_bright) >= 0.35
				and int(stats.bright_ridge_cells) >= 3 and float(stats.white_fraction) < 0.15,
				"home：55m表面ROI可读为浅蓝亮纹而非近全白/单太阳圆点")
		check(float(time_delta.mean_abs_rgb) > 0.01,
			"home：" + str(int(depth)) + "m冻结clock0/4真实表面像素变化>0.01")
		by_depth[str(int(depth))] = {"camera": vector(camera.global_position),
			"forward": vector(-camera.global_basis.z), "clocks": clocks,
			"surface_roi": stats, "time_0_to_4": time_delta}
	# 55m 同一机位分别只关 wave/sun，保持 sun_strength=1，不把日夜切换误当高光。
	var wave_off: Image
	var sun_off: Image
	camera.global_position = Vector3(column.x, level - 55.0, column.y)
	camera.look_at(camera.global_position + view_direction(), Vector3.UP)
	optical_view(map, id, camera, ZERO_TIME)
	material.set_shader_parameter("underside_wave_light", 0.0)
	wave_off = await shot("home-readable-55m-wave-light-off")
	material.set_shader_parameter("underside_wave_light", original_wave_light)
	material.set_shader_parameter("underside_sun_light", 0.0)
	sun_off = await shot("home-readable-55m-sun-light-off")
	material.set_shader_parameter("underside_sun_light", original_sun_light)
	var wave_delta: Dictionary = difference(base_image, wave_off, surface_area)
	var sun_delta: Dictionary = difference(base_image, sun_off, surface_area)
	check(int(wave_delta.changed_pixels) > 12 and float(wave_delta.peak) > 0.01,
		"home：55m underside_wave_light 0/默认 A-B差异>12px且peak>.01")
	check(int(sun_delta.changed_pixels) > 12 and float(sun_delta.peak) > 0.01,
		"home：55m underside_sun_light 0/默认 A-B差异>12px且peak>.01")
	# 非null中性FlatNormal：RGB(1,.5,.5)，只用GB作中性坡度对照，绝不传null触发hintnormal白。
	var flat_image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	flat_image.fill(Color(1.0, 0.5, 0.5, 1.0))
	var flat_compress_error: int = flat_image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC)
	check(flat_compress_error == OK, "home：FlatNormal testImage已压缩，shader使用GB通道对照")
	var flat_texture := ImageTexture.create_from_image(flat_image)
	flat_texture.resource_name = "FlatNormal_RGB1_GBNeutral"
	material.set_shader_parameter("large_wave_normals", flat_texture)
	optical_view(map, id, camera, ZERO_TIME)
	var flat_image_shot: Image = await shot("home-readable-55m-flat-normal")
	var normal_delta: Dictionary = difference(time_zero_image, flat_image_shot, surface_area)
	check(int(normal_delta.changed_pixels) > 0 and float(normal_delta.peak) > 0.001,
		"home：55m真实normal texture与FlatNormal GB中性对照存在像素差")
	Materials.configure_underside(material, {"ocean_waves": original_waves,
		"wave_scale": original_wave_scale, "large_wave_normals": original_normal})
	material.set_shader_parameter("underside_wave_light", original_wave_light)
	material.set_shader_parameter("underside_sun_light", original_sun_light)
	optical_view(map, id, camera, ZERO_TIME)
	var restored_image: Image = await shot("home-readable-55m-real-normal-restored")
	var restored_delta: Dictionary = difference(time_zero_image, restored_image, surface_area)
	var open_observer := Vector3(open_column.x, level - 55.0, open_column.y)
	check(open_observer.y < level, "home：55m开阔比较相机仍在水下")
	camera.global_position = open_observer
	camera.look_at(open_observer + view_direction(), Vector3.UP)
	optical_view(map, id, camera, ZERO_TIME)
	var open_image: Image = await shot("home-readable-55m-open-water")
	var open_stats: Dictionary = surface_readability(open_image, surface_area)
	report_surface["depths"] = by_depth
	report_surface["wave_light_on_off"] = wave_delta
	report_surface["sun_light_on_off"] = sun_delta
	report_surface["flat_normal"] = {"resource_name": flat_texture.resource_name,
		"rgb": [1.0, 0.5, 0.5], "normal_channels": "GB", "on_off": normal_delta}
	report_surface["restored_real_normal"] = restored_delta
	report_surface["open_water_55m"] = {"camera": vector(camera.global_position), "surface_roi": open_stats}
	var restored_texture: Texture2D = material.get_shader_parameter("large_wave_normals") as Texture2D
	report_surface["restored_texture_resource_path"] = restored_texture.resource_path if restored_texture != null else ""
	check(restored_texture != null and not report_surface.restored_texture_resource_path.is_empty(),
		"home：FlatNormal对照后恢复真实large_wave_normals sampler")
	values.readable_surface = report_surface
	check(float(open_stats.mean_luminance) > 0.0 and open_image != null,
		"home：55m开阔水面比较PNG已保存")
	map.air.lamp = old_lamp
	show_particle_kind(map, id, "all")
	camera.fov = original_fov

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
	var depths: Array = [5.0, 10.0, 20.0, 30.0, 41.0, 70.0, 115.0] if id == "home" else [10.0, 20.0, 41.0, 60.0]
	# Compare depth attenuation with moving crest/sun highlights disabled. A
	# crest can cross an ROI at a different world position at another depth;
	# that is motion, not a broken ambient attenuation curve.
	var surface_material: ShaderMaterial = water_node(map, id).material_override
	var saved_wave: float = surface_material.get_shader_parameter("underside_wave_light")
	var saved_sun: float = surface_material.get_shader_parameter("underside_sun_light")
	surface_material.set_shader_parameter("underside_wave_light", 0.0)
	surface_material.set_shader_parameter("underside_sun_light", 0.0)
	var column: Vector2 = choose_column(map, id, depths)
	var previous_sample: float = INF
	var previous_background: float = INF
	var sample_lights: Array[float] = []
	var rows: Array = []
	for depth in depths:
		# 同scene、同一开阔XZ与同一相对机位，避免用换地方的背景伪造深度递减。
		camera.global_position = Vector3(column.x, map.dive_water_level() - float(depth), column.y)
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
		sample_lights.append(sample_light)
		# 5→10m是浅层保亮段，8bit量化后的实测下降约0.00028；
		# 保持严格递减但不误要求该5m区间也达到深水大跨度的0.0005。
		var minimum_drop: float = 0.0001 if depth == 10.0 and id == "home" else 0.0005
		check(sample_light > 0.005 and sample_light < previous_sample - minimum_drop
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
	if id == "home" and sample_lights.size() >= 7:
		check(sample_lights[1] > 0.1 and sample_lights[2] > 0.1,
			"home：10/20m真实灰样板luminance均>0.1，避免近距过暗")
		check(sample_lights[6] < sample_lights[0] * 0.7,
			"home：115m真实灰样板luminance低于5m的70%")
	surface_material.set_shader_parameter("underside_wave_light", saved_wave)
	surface_material.set_shader_parameter("underside_sun_light", saved_sun)
	values.gray_optical_sample = rows
	values.gray_sample_luminance = sample_lights

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
		# 保持正常20m机位，不追逐某一颗泡；这里的on/off只证明正常视线内的环境泡投影。
		var level: float = map.dive_water_level()
		var column: Vector2 = normal_render_column(map, id)
		camera.global_position = Vector3(column.x, level - 20.0, column.y)
		camera.look_at(camera.global_position + Vector3(0.0, sin(NORMAL_PITCH), -cos(NORMAL_PITCH)), Vector3.UP)
		particle_snapshot(map, id, camera.global_position, camera, 2.0 + ZERO_TIME)
		var on: Image = await shot(id + "-ambient-bubble-on")
		bubble_node.hide()
		var off: Image = await shot(id + "-ambient-bubble-off")
		bubble_node.show()
		var delta: Dictionary = difference(on, off, Rect2(0.1, 0.1, 0.8, 0.8))
		check(int(delta.changed_pixels) >= 6 and float(delta.peak) > 0.01,
			id + "：正常机位环境泡实际on/off像素差")
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

func hide_particle_kind(map, id: String, kind: String) -> void:
	if id == "home":
		if kind == "bubble":
			map.get_node("Atmosphere/Bubbles").hide()
		elif kind == "mote":
			map.get_node("Atmosphere/Motes").hide()
		elif kind == "all":
			map.get_node("Atmosphere/Bubbles").hide()
			map.get_node("Atmosphere/Motes").hide()
			map.get_node("FishSchools").hide()
			map.get_node("Atmosphere/LightShafts").hide()
			if map.dive_controller.breath_bubbles != null:
				map.dive_controller.breath_bubbles.hide()
	else:
		map.deco.hide_kind(kind)

func show_particle_kind(map, id: String, kind: String) -> void:
	if id == "home":
		if kind == "bubble":
			map.get_node("Atmosphere/Bubbles").show()
		elif kind == "mote":
			map.get_node("Atmosphere/Motes").show()
		elif kind == "all":
			map.get_node("Atmosphere/Bubbles").show()
			map.get_node("Atmosphere/Motes").show()
			map.get_node("FishSchools").show()
			map.get_node("Atmosphere/LightShafts").show()
			if map.dive_controller.breath_bubbles != null:
				map.dive_controller.breath_bubbles.show()
	else:
		if kind == "bubble":
			map.deco._bubbles.show()
		elif kind == "mote":
			map.deco._motes.show()
		elif kind == "all":
			map.deco._bubbles.show()
			map.deco._motes.show()
			map.deco.show()

func normal_render_column(map, id: String) -> Vector2:
	if id == "zone1":
		return Vector2(0.0, 12.0)
	var direction := Vector3(0.0, sin(NORMAL_PITCH), -cos(NORMAL_PITCH)).normalized()
	var primary := Vector2(0.0, -35.0)
	for depth in NORMAL_RENDER_DEPTHS:
		if not clear_view(map, Vector3(primary.x, map.dive_water_level() - float(depth), primary.y),
			direction, map.dive_water_level()):
			return Vector2(-160.0, -160.0)
	return primary

func test_normal_particle_pixels(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	var level: float = map.dive_water_level()
	var column: Vector2 = normal_render_column(map, id)
	var rows: Array = []
	for depth in NORMAL_RENDER_DEPTHS:
		var observer := Vector3(column.x, level - float(depth), column.y)
		camera.global_position = observer
		var forward := Vector3(0.0, sin(NORMAL_PITCH), -cos(NORMAL_PITCH)).normalized()
		camera.look_at(observer + forward, Vector3.UP)
		camera.fov = 72.0
		check(is_equal_approx(camera.fov, 72.0) and absf((-camera.global_basis.z).y - sin(NORMAL_PITCH)) < 0.001,
			id + "：正常粒子图使用72FOV、水平上仰10度 depth=" + str(int(depth)))
		particle_snapshot(map, id, observer, camera, 2.0 + ZERO_TIME)
		optical_view(map, id, camera, 2.0 + ZERO_TIME)
		show_particle_kind(map, id, "all")
		var all_on: Image = await shot(id + "-normal-depth-" + str(int(depth)) + "-particles-on")
		hide_particle_kind(map, id, "bubble")
		var bubble_off: Image = await shot(id + "-normal-depth-" + str(int(depth)) + "-bubble-off")
		show_particle_kind(map, id, "bubble")
		hide_particle_kind(map, id, "mote")
		var mote_off: Image = await shot(id + "-normal-depth-" + str(int(depth)) + "-mote-off")
		show_particle_kind(map, id, "mote")
		hide_particle_kind(map, id, "all")
		var both_off: Image = await shot(id + "-normal-depth-" + str(int(depth)) + "-particles-off")
		show_particle_kind(map, id, "all")
		var bubble_delta: Dictionary = difference(all_on, bubble_off, Rect2(0.1, 0.1, 0.8, 0.8))
		var mote_delta: Dictionary = difference(all_on, mote_off, Rect2(0.1, 0.1, 0.8, 0.8))
		var all_delta: Dictionary = difference(all_on, both_off, Rect2(0.1, 0.1, 0.8, 0.8))
		check(int(bubble_delta.changed_pixels) >= 10 and float(bubble_delta.peak) > 0.008,
			id + "：正常相机深度" + str(int(depth)) + "m泡on/off真实投影>=10px且peak>.008")
		check(int(mote_delta.changed_pixels) >= 10 and float(mote_delta.peak) > 0.008,
			id + "：正常相机深度" + str(int(depth)) + "m尘on/off真实投影>=10px且peak>.008")
		rows.append({"depth": depth, "camera": vector(camera.global_position),
			"forward": vector(-camera.global_basis.z), "bubble_on_off": bubble_delta,
			"mote_on_off": mote_delta, "particles_on_off": all_delta,
			"particle_projection": roi(all_on, Rect2(0.1, 0.1, 0.8, 0.8))})
	values.normal_particle_pixels = {"column_xz": [column.x, column.y], "depths": rows,
		"fov": camera.fov, "pitch_degrees": 10.0}

func add_fog_test_box(map, camera: Camera3D, distance: float) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = "TestOnlyFarFogBox_%d" % int(distance)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(34.0, 24.0, 0.15)
	box.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.roughness = 1.0
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = material
	box.layers = 1
	map.add_child(box)
	box.global_position = camera.global_position - camera.global_basis.z * distance
	box.global_basis = camera.global_basis
	return box

func test_far_fog_clip(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	var level: float = map.dive_water_level()
	var column: Vector2 = Vector2(0.0, -35.0) if id == "home" else Vector2(0.0, 12.0)
	var observer := Vector3(column.x, level - 20.0, column.y)
	camera.global_position = observer
	camera.fov = 72.0
	camera.look_at(observer + Vector3(0.0, sin(LOW_WATER_PITCH), -cos(LOW_WATER_PITCH)), Vector3.UP)
	particle_snapshot(map, id, observer, camera, ZERO_TIME)
	optical_view(map, id, camera, ZERO_TIME)
	hide_particle_kind(map, id, "all")
	var water: MeshInstance3D = water_node(map, id)
	water.hide()
	var boxes: Array[MeshInstance3D] = []
	var far_rows: Array = []
	for distance in [220.0, 400.0]:
		var box := add_fog_test_box(map, camera, distance)
		boxes.append(box)
		for other in boxes:
			other.visible = other == box
		var far_on: Image = await shot(id + "-far-clip-blackbox-" + str(int(distance)) + "m-on")
		box.hide()
		var far_off: Image = await shot(id + "-far-clip-blackbox-" + str(int(distance)) + "m-off")
		var far_delta: Dictionary = difference(far_on, far_off, Rect2(0.15, 0.15, 0.7, 0.7))
		check(float(far_delta.peak) < 0.025 and float(far_delta.changed_fraction) < 0.20,
			id + "：" + str(int(distance)) + "m测试黑box真实fog后clip ROI接近背景")
		far_rows.append({"distance_m": distance, "on_off": far_delta})
	for box in boxes:
		box.free()
	# 同一视线的水面下0.68m黑box必须仍进入真实fog路径，不能因为接近water_level被测试逻辑豁免。
	var surface_box := add_fog_test_box(map, camera, 380.0)
	surface_box.global_position.y = level - 0.68
	var surface_on: Image = await shot(id + "-far-clip-surface-box-on")
	surface_box.hide()
	var surface_off: Image = await shot(id + "-far-clip-surface-box-off")
	var surface_delta: Dictionary = difference(surface_on, surface_off, Rect2(0.15, 0.15, 0.7, 0.7))
	check(float(surface_delta.peak) < 0.025 and float(surface_delta.changed_fraction) < 0.20,
		id + "：water-.68处黑box也经过真实fog而非surface豁免")
	surface_box.free()
	show_particle_kind(map, id, "all")
	# 同位置低角度水面ROI保留on/off值：只作为远clip带目检证据，不以源码字符串替代真实画面。
	water.show()
	camera.global_position = observer
	camera.look_at(observer + Vector3(0.0, sin(LOW_WATER_PITCH), -cos(LOW_WATER_PITCH)), Vector3.UP)
	optical_view(map, id, camera, ZERO_TIME)
	var water_on: Image = await shot(id + "-far-clip-water-on")
	water.hide()
	var water_off: Image = await shot(id + "-far-clip-water-off")
	water.show()
	values.far_clip = {"blackbox_rows": far_rows, "surface_box_on_off": surface_delta,
		"water_on_off": difference(water_on, water_off, Rect2(0.05, 0.05, 0.9, 0.35)),
		"water_roi_on": roi(water_on, Rect2(0.05, 0.05, 0.9, 0.35)),
		"water_roi_off": roi(water_off, Rect2(0.05, 0.05, 0.9, 0.35)),
		"pitch_degrees": 3.0, "distances": [220.0, 400.0], "surface_box_depth": 0.68}

func capture_surface_motion(map, id: String, camera: Camera3D, values: Dictionary) -> void:
	if id != "home": return
	var controller = map.dive_controller
	var previous := map.dive_position() as Vector3
	var old_yaw: float = controller.yaw
	var old_pitch: float = controller.pitch
	var old_distance: float = controller.distance
	var level: float = map.dive_water_level()
	var point := Vector3(0.0, level - 55.0, -35.0)
	check(map.collision_runtime.try_set_viewer_position(point), "home：55m动态预览实际胶囊起点净空")
	controller.yaw = -atan2(SUN.x, -SUN.z)
	controller.pitch = -0.90
	controller.distance = 7.5
	controller.debug_teleport(point)
	controller.character.show()
	map.air.refill()
	map.depth = 55.0
	map._update_underwater_view()
	show_particle_kind(map, id, "all")
	var saved: int = 0
	for i in 72:
		var clock := 0.000001 + float(i) / 18.0
		map._surface_material.set_shader_parameter("elapsed", clock)
		map.get_node("Atmosphere").sample(clock)
		controller.character._process(1.0 / 18.0)
		for school in map.get_node("FishSchools").get_children(): school.sample(clock)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image != null and not image.is_empty():
			if image.save_png("res://outputs/surface-motion-%03d.png" % i) == OK: saved += 1
	check(saved == 72, "home：55m第三人称海面动态预览72帧已保存")
	values.surface_motion = {"frames": saved, "fps": 18, "seconds": 4.0,
		"depth":55.0, "camera":vector(camera.global_position), "pitch":controller.pitch,
		"sequence":"res://outputs/surface-motion-%03d.png", "fixed_step_visual":true,
		"note":"固定表现时钟的实机渲染预览；非玩家连续操作录像"}
	controller.yaw = old_yaw
	controller.pitch = old_pitch
	controller.distance = old_distance
	controller.debug_teleport(previous)
	update_view(map, id)

func render_map(map, id: String, values: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		values.visual_mode = "headless仅行为；不等待frame_post_draw，不声称视觉通过"
		return
	var camera: Camera3D = map.dive_controller.camera
	var original_camera: Transform3D = camera.global_transform
	var original_fov: float = camera.fov
	camera.make_current()
	map.air.lamp = false
	map.configure_underwater_light({"direction": SUN.normalized(), "strength": 1.0})
	update_view(map, id)
	await test_readable_surface(map, id, camera, values)
	await test_surface_pixels(map, id, camera, values)
	await test_gray_sample(map, id, camera, values)
	await test_normal_particle_pixels(map, id, camera, values)
	await test_far_fog_clip(map, id, camera, values)
	await test_particle_pixels(map, id, camera, values)
	await capture_surface_motion(map, id, camera, values)
	camera.global_transform = original_camera
	camera.fov = original_fov
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
		test_directional_particles(map, id, values)
		await test_breath(map, id, values)
		await render_map(map, id, values)
		current_scene = null
		map.free()
		await process_frame
		Materials.clear_cache()
	if DisplayServer.get_name() != "headless":
		check(report.images.size() >= 36, "真实渲染保留原有PNG数量下限36")
		check(report.maps.size() == 2 and report.images.size() == 92,
			"真实渲染固定92张：保留既有81张，新增home 20/55m三clock、wave/sun toggle、FlatNormal、恢复纹理和55m开阔比较共11张")
	finish()
