extends SceneTree
## 只验收正式场景；不读取坐标清单、不移动鱼群、不补注入以掩盖装配错误。

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SCENIC_SCENE: String = "res://scenes/decorations/animals/scenic_sea_fish_schools.tscn"
const FISH_SCENE: String = "res://scenes/decorations/animals/fish_school.tscn"
const GROUP_PATH: String = "World/Environment/Animals/ScenicSeaFishSchools"
const CABIN_PATH: String = "World/Zones/Zone1HomeHarbor/Models/太阳能木屋"
const OUT: String = "res://outputs/scenic-fish-distribution.json"
const FishSchool = preload("res://src/ambient/decorative_fish_school.gd")
const FishGeometry = preload("res://src/ambient/animal_mesh.gd")
const FlockScript = preload("res://src/ambient/fish_flock_group.gd")
const EXPECTED: Dictionary = {
	"StationOuter": 6, "AquaOuter": 10, "HomeSouth": 8, "RanchOuter": 12,
	"CityCanal": 14, "CityWest": 10, "CityEast": 14, "RestStopOuter": 8,
	"NeonOuter": 10, "KioskOuter": 6,
}
const SAMPLE_COUNT: int = 33
const SAMPLE_STEP: float = 1.37
const EPSILON: float = 0.002

var checks: int = 0
var failures: Array[String] = []
var main: Node3D
var water: MeshInstance3D
var group: Node3D
var school_rows: Array[Dictionary] = []
var geometry_rows: Array[Dictionary] = []
var geometry_hits: Array[Dictionary] = []
var triangle_cache: Dictionary = {}
var geometry_candidates: int = 0
var geometry_unsupported: Array[String] = []
var geometry_probes: int = 0
var geometry_intersections: int = 0
var authored: Dictionary = {}
var outside_cabin: int = 0

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

func freeze(node: Node) -> void:
	for item: Node in all_nodes(node):
		item.process_mode = Node.PROCESS_MODE_DISABLED
		item.set_process(false)
		item.set_physics_process(false)

func authored_values(school: FishSchool) -> Dictionary:
	return {"id": school.instance_id, "transform": school.transform,
		"scene": school.scene_file_path, "count": school.count,
		"palette": school.palette, "palette_index": school.palette_index,
		"profile": school.profile, "size": school.size_scale,
		"spread": school.spread_radius, "orbit": school.orbit_radius,
		"min_depth": school.submerge_min, "max_depth": school.submerge_max,
		"ride_water": school.ride_water, "seed": school.seed_value,
		"speed": school.swim_speed, "phase": school.phase, "visible": school.visible}

func remember_scene(scene: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in scene.get_children():
		if child is FishSchool:
			result[str(child.name)] = authored_values(child as FishSchool)
	return result

func verify_isolation(node: Node) -> void:
	var forbidden_properties: PackedStringArray = PackedStringArray([
		"fishery_id", "fishery", "fishery_service", "harvest_amount", "harvest_ready",
		"production_rate", "production_interval", "stored_fish", "stock", "capacity",
		"fishery_stock", "fishery_capacity", "fishery_production", "harvest_count",
		"catchable", "catch_count", "catch_radius", "catch_reward", "pickup_id",
		"resource_id", "item_id", "reward", "rewards", "hold_time", "verb",
	])
	var forbidden_methods: PackedStringArray = PackedStringArray([
		"capture", "catch_fish", "try_capture", "request_capture", "harvest", "collect",
		"pickup", "try_pickup", "request_pickup", "nearest_school", "produce",
		"request_catch", "try_catch", "capture_fish", "on_captured", "can_capture",
	])
	for item: Node in all_nodes(node):
		var label: String = str(group.get_path_to(item))
		check(not (item is CollisionObject3D or item is CollisionShape3D or item is CollisionPolygon3D), label + " 无碰撞节点")
		for membership: StringName in item.get_groups():
			var key: String = str(membership).to_lower()
			check(not ("interact" in key or "pickup" in key or "resource" in key or "fishery" in key), label + " 不入玩法组 " + key)
		for property: Dictionary in item.get_property_list():
			var key: String = str(property["name"])
			check(not forbidden_properties.has(key), label + " 无捕鱼或生产属性 " + key)
		for method: String in forbidden_methods:
			check(not item.has_method(method), label + " 无捕捞接口 " + method)
		for key: StringName in item.get_meta_list():
			var lower: String = str(key).to_lower()
			check(not ("fishery" in lower or "pickup" in lower or "reward" in lower), label + " 无捕鱼元数据 " + lower)
	var ancestor: Node = node
	while ancestor != main and ancestor != null:
		check(str(ancestor.name) != "FisherySchools" and str(ancestor.name) != "Gameplay", "观赏组不挂捕鱼/玩法树 " + str(ancestor.name))
		ancestor = ancestor.get_parent()

func verify_materials(school: FishSchool, reference: FishSchool) -> void:
	var label: String = str(school.name)
	var colors: Array = school.resolved_colors()
	var used: Dictionary = {}
	check(colors.size() == 3, label + " surface 色板恰好三色")
	for member: Dictionary in school.members:
		var swatch: Color = member["color"]
		used[swatch.to_html()] = true
		check(colors.has(swatch), label + " 个体色来自真实色板")
	check(used.size() == 3, label + " 三色确实分发到个体")
	for part_name: String in ["Body", "Eyes", "Fin"]:
		var part: MultiMeshInstance3D = school.get_node_or_null(part_name) as MultiMeshInstance3D
		var original: MultiMeshInstance3D = reference.get_node_or_null(part_name) as MultiMeshInstance3D
		check(part != null and original != null, label + " 复用阳光房部件 " + part_name)
		if part == null or original == null:
			continue
		check(part.multimesh != null and part.multimesh.instance_count == school.count, label + " 实绘实例数量 " + part_name)
		if part.multimesh == null:
			continue
		check(part.multimesh.mesh != null and original.multimesh.mesh != null, label + " 真实网格存在 " + part_name)
		if part.multimesh.mesh != null and original.multimesh.mesh != null:
			check(part.multimesh.mesh.get_faces() == original.multimesh.mesh.get_faces(), label + " 几何严格等于阳光房同款 " + part_name)
		var material: StandardMaterial3D = part.material_override as StandardMaterial3D
		var original_material: StandardMaterial3D = original.material_override as StandardMaterial3D
		check(material != null and original_material != null, label + " 水面标准材质 " + part_name)
		if material != null and original_material != null:
			check(material.albedo_color.is_equal_approx(Color.WHITE) and material.vertex_color_use_as_albedo, label + " 白底乘实例色 " + part_name)
			check(not material.emission_enabled and material.shading_mode == original_material.shading_mode, label + " 无额外发光或替换着色 " + part_name)
			check(material.cull_mode == original_material.cull_mode, label + " 保持原剔除方式 " + part_name)
		var actual_colors: Dictionary = {}
		for index: int in range(part.multimesh.instance_count):
			var actual: Color = part.multimesh.get_instance_color(index)
			actual_colors[actual.to_html()] = true
			if part_name != "Eyes":
				var member_color: Color = school.members[index]["color"]
				var color_error: float = absf(actual.r - member_color.r) + absf(actual.g - member_color.g) + absf(actual.b - member_color.b)
				check(color_error <= 3.0 / 255.0 + 0.0001, label + " GPU 实例色与个体一致，容许8bit量化 " + part_name)
		if part_name != "Eyes":
			check(part.multimesh.use_colors and actual_colors.size() == 3, label + " 身体/尾鳍真实三色 " + part_name)
	check(school.get_node_or_null("Back") == null, label + " flat 不带潜水背斑")

func include_geometry(mesh: Mesh, pose: Transform3D, path: String) -> void:
	if mesh == null:
		return
	var bounds: AABB = pose * mesh.get_aabb()
	var water_y: float = water.global_position.y
	if bounds.end.y < water_y - 0.8 or bounds.position.y > water_y + 1.0:
		return
	geometry_candidates += 1
	var key: int = mesh.get_instance_id()
	if not triangle_cache.has(key):
		var faces: PackedVector3Array = mesh.get_faces()
		if faces.is_empty():
			geometry_unsupported.append(path)
			return
		var created_triangles: TriangleMesh = TriangleMesh.new()
		if not created_triangles.create_from_faces(faces):
			geometry_unsupported.append(path)
			return
		triangle_cache[key] = created_triangles
	var triangles: TriangleMesh = triangle_cache[key] as TriangleMesh
	geometry_rows.append({"path": path, "bounds": bounds, "inverse": pose.affine_inverse(),
		"pose": pose, "triangles": triangles})

func collect_geometry(node: Node) -> void:
	# 不用 visual_only 排除建筑：旧城和基座同样是纯观赏，但必须参与避让。
	if node == water or node.is_class("Terrain3D") or "terrain" in str(node.name).to_lower():
		return
	if node == main.get_node_or_null("World/Environment/Animals") or node is FishSchool:
		return
	var asset: Variant = node.get("asset_id")
	if asset is String and str(asset).begins_with("SEA-DECO-ANIMAL"):
		return
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		include_geometry(instance.mesh, instance.global_transform, str(instance.get_path()))
	elif node is MultiMeshInstance3D:
		var instance: MultiMeshInstance3D = node as MultiMeshInstance3D
		var mm: MultiMesh = instance.multimesh
		if mm != null and mm.mesh != null:
			var count: int = mm.instance_count if mm.visible_instance_count < 0 else mini(mm.instance_count, mm.visible_instance_count)
			for index: int in range(count):
				include_geometry(mm.mesh, instance.global_transform * mm.get_instance_transform(index), "%s#%d" % [instance.get_path(), index])
	for child: Node in node.get_children():
		collect_geometry(child)

func segment_hit(a: Vector3, b: Vector3, geometry: Dictionary) -> bool:
	var bounds: AABB = geometry["bounds"]
	if not bounds.grow(0.001).has_point(a) and not bounds.grow(0.001).has_point(b) and bounds.grow(0.001).intersects_segment(a, b) == null:
		return false
	var inverse: Transform3D = geometry["inverse"]
	var local_a: Vector3 = inverse * a
	var local_b: Vector3 = inverse * b
	var length: float = local_a.distance_to(local_b)
	if length < 0.000001:
		return false
	var triangles: TriangleMesh = geometry["triangles"] as TriangleMesh
	# 正反各探一次，避免薄板背面剔除漏报；命中必须落在短段内。
	for reverse: bool in [false, true]:
		var start: Vector3 = local_b if reverse else local_a
		var end: Vector3 = local_a if reverse else local_b
		var hit: Dictionary = triangles.intersect_ray(start, (end - start).normalized())
		if not hit.is_empty():
			var point: Vector3 = hit["position"]
			if start.distance_to(point) <= length + 0.0001:
				return true
	return false

func probe_fish(school: FishSchool, index: int, pose: Transform3D, t: float) -> void:
	var center: Vector3 = pose.origin
	var body: MultiMeshInstance3D = school.get_node("Body") as MultiMeshInstance3D
	var fin: MultiMeshInstance3D = school.get_node("Fin") as MultiMeshInstance3D
	var body_bounds: AABB = body.multimesh.mesh.get_aabb()
	var fin_bounds: AABB = fin.multimesh.mesh.get_aabb()
	var head: Vector3 = pose * Vector3(0.0, 0.0, body_bounds.end.z)
	var fin_pose: Transform3D = fin.global_transform * fin.multimesh.get_instance_transform(index)
	var tail: Vector3 = fin_pose * Vector3(0.0, 0.0, fin_bounds.position.z)
	var half_height: float = FishGeometry.fish_half_height(school.profile) * pose.basis.get_scale().y
	var segments: Array[PackedVector3Array] = [PackedVector3Array([tail, head])]
	for point: Vector3 in [center, head, tail]:
		segments.append(PackedVector3Array([point - Vector3.UP * half_height, point + Vector3.UP * half_height]))
		var side: Vector3 = pose.basis.x * body_bounds.size.x * 0.5
		segments.append(PackedVector3Array([point - side, point + side]))
	for segment: PackedVector3Array in segments:
		geometry_probes += 1
		for geometry: Dictionary in geometry_rows:
			if segment_hit(segment[0], segment[1], geometry):
				geometry_intersections += 1
				if geometry_hits.size() < 80:
					geometry_hits.append({"school": str(school.name), "fish": index, "time": t,
						"mesh": geometry["path"], "from": str(segment[0]), "to": str(segment[1])})

func horizontal_box_distance(point: Vector3, bounds: AABB) -> float:
	var dx: float = maxf(bounds.position.x - point.x, maxf(0.0, point.x - bounds.end.x))
	var dz: float = maxf(bounds.position.z - point.z, maxf(0.0, point.z - bounds.end.z))
	return Vector2(dx, dz).length()

func visual_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	for child: Node in all_nodes(node):
		if child is MeshInstance3D:
			var part: MeshInstance3D = child as MeshInstance3D
			if part.mesh != null:
				var bounds: AABB = part.global_transform * part.mesh.get_aabb()
				result = bounds if first else result.merge(bounds)
				first = false
	return result

func sample_school(school: FishSchool, cabin_bounds: AABB) -> Dictionary:
	var min_depth: float = INF
	var max_depth: float = -INF
	var min_cabin_distance: float = INF
	var min_point: Vector3 = Vector3(INF, INF, INF)
	var max_point: Vector3 = Vector3(-INF, -INF, -INF)
	var depth_errors: int = 0
	var declared_depth_errors: int = 0
	var first_bodies: Array[Transform3D] = []
	var first_tails: Array[Transform3D] = []
	var original_water_time: float = float(water.get("time"))
	var bodies_changed: bool = false
	var tails_changed: bool = false
	var body_instances: MultiMesh = (school.get_node("Body") as MultiMeshInstance3D).multimesh
	var fin_instances: MultiMesh = (school.get_node("Fin") as MultiMeshInstance3D).multimesh
	var instance_mismatch: int = 0
	for step: int in range(SAMPLE_COUNT):
		var t: float = float(step) * SAMPLE_STEP
		water.set("time", t)
		school.sample(t)
		check(school.transforms.size() == school.count and school.fin_transforms.size() == school.count, "%s t=%.2f 真实身体和尾鳍实例" % [school.name, t])
		if step == 0:
			first_bodies.assign(school.transforms)
			first_tails.assign(school.fin_transforms)
		for index: int in range(school.transforms.size()):
			var local_pose: Transform3D = school.transforms[index]
			if not body_instances.get_instance_transform(index).is_equal_approx(local_pose) or not fin_instances.get_instance_transform(index).is_equal_approx(school.fin_transforms[index]):
				instance_mismatch += 1
			var pose: Transform3D = school.global_transform * local_pose
			var center: Vector3 = pose.origin
			var sampled: Vector3 = water.call("sample_surface", Vector2(center.x, center.z), t)
			# sample_surface.x 是位移，不是绝对水高；必须加真实主水的世界 Y。
			var wave_y: float = water.global_position.y + sampled.x
			var half_height: float = FishGeometry.fish_half_height(school.profile) * pose.basis.get_scale().y
			var depth: float = wave_y - (center.y + half_height)
			min_depth = minf(min_depth, depth)
			max_depth = maxf(max_depth, depth)
			if depth < 0.5 - EPSILON or depth > 1.5 + EPSILON:
				depth_errors += 1
			var member: Dictionary = school.members[index]
			if absf(depth - float(member["depth"])) > EPSILON:
				declared_depth_errors += 1
			min_point = min_point.min(center)
			max_point = max_point.max(center)
			min_cabin_distance = minf(min_cabin_distance, horizontal_box_distance(center, cabin_bounds))
			probe_fish(school, index, pose, t)
			if step > 0:
				bodies_changed = bodies_changed or not first_bodies[index].basis.is_equal_approx(local_pose.basis)
				var relative_tail: Basis = local_pose.basis.inverse() * school.fin_transforms[index].basis
				var first_relative: Basis = first_bodies[index].basis.inverse() * first_tails[index].basis
				tails_changed = tails_changed or not relative_tail.is_equal_approx(first_relative)
	water.set("time", original_water_time)
	check(depth_errors == 0, "%s %d时刻最高点沉深0.5..1.5m，越界%d" % [school.name, SAMPLE_COUNT, depth_errors])
	check(declared_depth_errors == 0, "%s 真实浪面沉深与个体声明一致，偏离%d" % [school.name, declared_depth_errors])
	check(bodies_changed and tails_changed, str(school.name) + " 身体朝向和相对身体的尾摆都改变")
	check(instance_mismatch == 0, str(school.name) + " 采样数组确实写入身体/尾鳍MultiMesh，非仅改CPU缓存")
	if min_cabin_distance >= 20.0:
		outside_cabin += 1
	return {"name": str(school.name), "instance_id": school.instance_id, "count": school.count,
		"position": str(school.global_position), "samples": SAMPLE_COUNT,
		"min_top_depth_m": min_depth, "max_top_depth_m": max_depth,
		"depth_outliers": depth_errors, "depth_mismatch": declared_depth_errors,
		"min_distance_to_cabin_bbox_m": min_cabin_distance,
		"sampled_footprint_m": [max_point.x - min_point.x, max_point.z - min_point.z],
		"body_animates": bodies_changed, "tail_animates_relative_to_body": tails_changed}

func verify_legacy(animals: Node, cabin_fish: Node) -> void:
	var counts: Dictionary = {"NearSchool": 6, "MidSchool": 10, "WideSchool": 14}
	check(cabin_fish.get_child_count() == 3, "原阳光房仍为三组")
	for name: String in counts:
		var school: FishSchool = cabin_fish.get_node_or_null(name) as FishSchool
		check(school != null and school.count == int(counts[name]), "阳光房原数量保留 " + name)
	for name: String in ["HomeSchool", "EastSchool", "WestSchool"]:
		var school: FishSchool = animals.get_node_or_null(name) as FishSchool
		check(school != null and school.count == 10 and school.members.size() == 10, "原水面鱼群各10条 " + name)

func run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	check(packed != null, "真实main可加载")
	if packed == null:
		finish()
		return
	main = packed.instantiate() as Node3D
	main.set("_autosave_on", false)
	var clock: Object = main.get("world_clock") as Object
	var weather: Object = main.get("weather_service") as Object
	clock.set("paused", true)
	weather.set("paused", true)
	var main_pose: Transform3D = main.transform
	var world_pose: Transform3D = (main.get_node("World") as Node3D).transform
	group = main.get_node_or_null(GROUP_PATH) as Node3D
	check(group != null, "main已挂ScenicSeaFishSchools，不在测试中临时创建")
	if group == null:
		main.free()
		main = null
		finish()
		return
	authored = remember_scene(group)
	check(group.visible and group.name == &"ScenicSeaFishSchools", "编辑态默认可见且根名正确")
	check(group.scene_file_path == SCENIC_SCENE and group.get_script() == FlockScript, "独立可编辑PackedScene与水递归注入脚本")
	var group_pose: Transform3D = group.transform
	var independent_packed: PackedScene = load(SCENIC_SCENE) as PackedScene
	check(independent_packed != null, "独立观赏场景可加载")
	if independent_packed != null:
		var independent: Node3D = independent_packed.instantiate() as Node3D
		check(independent.name == &"ScenicSeaFishSchools" and independent.visible, "独立场景根名及默认可见性正确")
		check(remember_scene(independent) == authored, "重新实例化仍保持场景身份、参数、局部变换与稳定ID")
		independent.free()
	root.add_child(main)
	main.set("_autosave_on", false)
	clock.set("paused", true)
	weather.set("paused", true)
	clock.set("seconds", 9.0 * 3600.0)
	clock.emit_signal("changed", clock.call("query"))
	weather.call("set_weather", "clear")
	freeze(main)
	if root.has_node("Economy"):
		root.get_node("Economy").set("ticking", false)
	water = main.get_node_or_null("World/Water") as MeshInstance3D
	var animals: Node = main.get_node("World/Environment/Animals")
	var cabin_fish: Node = animals.get_node_or_null("SolarCabinFishSchools")
	var cabin: Node3D = main.get_node_or_null(CABIN_PATH) as Node3D
	var reference: FishSchool = animals.get_node_or_null("SolarCabinFishSchools/NearSchool") as FishSchool
	check(water != null and water.has_method("sample_surface"), "正式主水与真实浪面采样接口")
	check(reference != null and cabin != null and cabin_fish != null, "阳光房参考鱼群与真实建筑存在")
	if water == null or reference == null or cabin == null or cabin_fish == null:
		finish()
		return
	check(group.is_visible_in_tree(), "默认范围中观赏组真实可见")
	check(group.get_child_count() == 10 and authored.size() == 10, "恰好10个独立鱼群子场景")
	verify_isolation(group)
	verify_legacy(animals, cabin_fish)
	collect_geometry(main.get_node("World"))
	check(not geometry_rows.is_empty(), "已收集World近水位真实网格，而非空几何假通过")
	check(geometry_unsupported.is_empty(), "近水位候选网格均可建立真实TriangleMesh")
	var cabin_bounds: AABB = visual_bounds(cabin)
	check(cabin_bounds.size.length() > 0.0, "真实阳光房网格世界bbox可用")
	var ids: Dictionary = {}
	for item: Node in all_nodes(main):
		if item.has_method("describe"):
			var description: Dictionary = item.call("describe")
			var stable_id: String = str(description.get("instance_id", ""))
			if not stable_id.is_empty():
				ids[stable_id] = int(ids.get(stable_id, 0)) + 1
	var total: int = 0
	var count_types: Dictionary = {}
	var spread_types: Dictionary = {}
	var orbit_types: Dictionary = {}
	var footprint_types: Dictionary = {}
	for name: String in EXPECTED:
		var school: FishSchool = group.get_node_or_null(name) as FishSchool
		check(school != null, "约定鱼群存在 " + name)
		if school == null:
			continue
		check(school.get_script() == reference.get_script() and school.get_script() == FishSchool, name + " Script严格等于阳光房NearSchool")
		check(school.scene_file_path == FISH_SCENE and school.owner != null, name + " 保留可编辑fish_school场景实例身份")
		check(authored_values(school) == authored.get(name, {}), name + " ready不改场景配置与稳定ID")
		check(not school.instance_id.is_empty() and int(ids.get(school.instance_id, 0)) == 1, name + " 稳定instance_id在实际鱼群中唯一")
		check(school.count == int(EXPECTED[name]) and school.members.size() == school.count, name + " 声明及实际条数")
		check(school.palette == "surface" and school.profile == "flat", name + " 阳光房同款水面扁鱼")
		check(school.size_scale >= 0.46 - EPSILON and school.size_scale <= 0.5 + EPSILON, name + " 保持真实小鱼尺寸")
		check(school.submerge_min >= 0.55 - EPSILON and school.submerge_max <= 1.5 + EPSILON and school.submerge_max >= school.submerge_min, name + " 声明沉深0.55..1.5m")
		check(school.spread_radius >= 1.8 - EPSILON and school.spread_radius <= 4.2 + EPSILON, name + " 散布半径1.8..4.2m")
		check(school.ride_water and school.get("_water") == water, name + " 已由main经父组注入同一真实主水")
		check(school.visible and school.is_visible_in_tree(), name + " 默认范围可见")
		verify_materials(school, reference)
		var row: Dictionary = sample_school(school, cabin_bounds)
		school_rows.append(row)
		var footprint: Array = row["sampled_footprint_m"]
		footprint_types[snappedf(maxf(float(footprint[0]), float(footprint[1])), 0.5)] = true
		total += school.count
		count_types[school.count] = true
		spread_types[snappedf(school.spread_radius, 0.01)] = true
		orbit_types[str(school.orbit_radius)] = true
	check(total == 98, "新增总计98条，不含原鱼群")
	check(count_types.size() >= 3 and spread_types.size() >= 3 and footprint_types.size() >= 3, "数量、配置范围及实际游动包络均至少三档")
	check(orbit_types.size() >= 3, "巡游轨道至少三种而非全部同圈")
	check(outside_cabin * 2 > EXPECTED.size(), "大部分鱼群全采样位置距阳光房真实bbox至少20m")
	check(geometry_probes > 0 and geometry_intersections == 0, "实际鱼心/头尾短段不穿近水位实体，命中%d" % geometry_intersections)
	check(main.transform.is_equal_approx(main_pose) and (main.get_node("World") as Node3D).transform.is_equal_approx(world_pose), "main与World根变换未改")
	check(group.transform.is_equal_approx(group_pose) and remember_scene(group) == authored, "观赏组保持TSCN原摆位、尺寸与身份")
	check(not bool(main.get("_autosave_on")) and bool(clock.get("paused")) and bool(weather.get("paused")), "自动存档禁用且时钟/天气冻结")
	finish()

func finish() -> void:
	var geometry_inventory: Array[Dictionary] = []
	for entry: Dictionary in geometry_rows:
		var bounds: AABB = entry["bounds"]
		geometry_inventory.append({"path": entry["path"], "world_bbox_position": str(bounds.position), "world_bbox_size": str(bounds.size)})
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"source_of_truth": "实际PackedScene及main实例；不使用源清单或硬编码世界坐标",
		"expected_schools": 10, "expected_fish": 98, "samples_per_school": SAMPLE_COUNT,
		"sample_step_seconds": SAMPLE_STEP, "schools": school_rows, "outside_cabin_20m": outside_cabin,
		"geometry": {"method": "真实mesh局部TriangleMesh+世界bbox广筛+双向限长ray；含MultiMesh实例变换",
			"water_relative_band_m": [-0.8, 1.0], "candidate_instances": geometry_candidates,
			"triangle_instances": geometry_rows.size(), "unique_triangle_meshes": triangle_cache.size(),
			"unsupported": geometry_unsupported, "actual_geometry_inventory": geometry_inventory, "fish_segments": geometry_probes,
			"intersections": geometry_intersections, "first_hits": geometry_hits,
			"limits": "抽样短段表面相交检测，不冒充连续时间扫掠、封闭体内部判定或全体积无碰撞证明"},
		"art_review": "pending；逻辑与几何探针不代表可见性或美术通过"}
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	check(directory_error == OK, "报告目录可创建")
	var file: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	check(file != null, "报告文件可写")
	report["checks"] = checks
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[scenic-fish-distribution] %d checks, %d failures" % [checks, failures.size()])
	if is_instance_valid(main):
		main.free()
	quit(0 if failures.is_empty() else 1)
