extends SceneTree
## 独立结构并集验收；只审计实际引擎网格，不把生成器质量声明当作证据。
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const Generator = preload("res://src/workshop/shell_generator.gd")
const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const REPORT := "res://outputs/workshop_union_report.json"
var checks: int = 0
var failures: Array[String] = []
var cases: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not value:
		var message: String = label + " " + str(detail)
		failures.append(message)
		printerr("FAIL [workshop-union] ", message)

func run() -> void:
	var catalog: Dictionary = Catalog.definitions()
	_test_probe_controls()
	for shape: String in ["rectangle", "l", "t", "u"]:
		for flags: int in 4:
			for mode: int in 4:
				var id: String = "%s_p%d_b%d_mode%d" % [shape, flags & 1, (flags >> 1) & 1, mode]
				if not OS.get_environment("SEA_UNION_CASE").is_empty() and not id.contains(OS.get_environment("SEA_UNION_CASE")): continue
				var r: Dictionary = Recipe.authoring_defaults()
				r.merge({"building_id": id, "shape": shape, "width": 12.0, "depth": 16.0, "window_width": 0.8, "floors": 3, "taper": 0.06 if mode in [1, 2] else 0.0, "vegetation_density": 0.0, "aging": 0.0, "damage": 0.0}, true)
				r.architecture = Config.defaults()
				r.architecture.pilaster.enabled = bool(flags & 1)
				r.architecture.band.enabled = bool(flags & 2)
				if mode in [1, 3]:
					r.architecture.plan.setback_start = 1
					r.architecture.plan.setback_step = 0.18
				await _test_case(id, r, catalog)
	check(not cases.is_empty(), "筛选至少执行一个建筑案例")
	var report: Dictionary = {"suite": "workshop-union", "probe": {"source": "上传的原始ArrayMesh顶点/索引与实际变换，放大100倍建立射线BVH", "directions": 3, "decision": "逐源实体射线奇偶多数票，再求实体并集", "samples_per_face": 2, "normal_distance_m": 0.0001, "diagnostic_distance_m": 0.00003, "modes": {"0": "无收分无退台", "1": "收分加退台", "2": "仅收分", "3": "仅退台"}}, "checks": checks, "failures": failures, "cases": cases, "filter": OS.get_environment("SEA_UNION_CASE"), "visual": "未执行真实渲染；本专项仅验证真实网格、静态序列化和碰撞", "engine": Engine.get_version_info()}
	var file := FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-union] report=", ProjectSettings.globalize_path(REPORT))
	print("[workshop-union] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_case(id: String, recipe: Dictionary, catalog: Dictionary) -> void:
	var start: int = Time.get_ticks_msec()
	var built: Dictionary = Generator.build(recipe, catalog)
	var record: Dictionary = {"ok": built.ok, "reason": built.reason, "recipe": recipe.duplicate(true)}
	cases[id] = record
	check(bool(built.ok), id + " 生成", built.reason)
	if not bool(built.ok):
		print("[workshop-union] case=", id, " rejected=", built.reason)
		return
	var root: Node3D = built.root
	var structure: MeshInstance3D = root.get_node("GeneratedVisual/structure_union") as MeshInstance3D
	check(structure != null and structure.mesh != null, id + " 存在真实结构网格")
	if structure == null:
		root.free()
		return
	var faces: PackedVector3Array = structure.mesh.get_faces()
	var audit: Dictionary = _audit(faces)
	record["topology"] = audit
	check(bool(audit.valid), id + " 实际faces严格拓扑", audit)
	var sources: Array = []
	var source_ids: Array = built.semantic_sources.keys()
	for prefix: String in ["wall_shell_", "slab_", "roof_main", "belt_", "plinth_", "pilaster_", "band_"]:
		var count: int = 0
		for source_id: String in source_ids:
			if source_id.begins_with(prefix): count += 1
		var enabled: bool = recipe.architecture.pilaster.enabled if prefix == "pilaster_" else (recipe.architecture.band.enabled if prefix == "band_" else true)
		check((count > 0) == enabled, id + " 融合来源开关 " + prefix, count)
	check(structure.get_meta("source_slots").size() == source_ids.size(), id + " 来源槽全部进入结构")
	var visible_sources: int = 0
	for source_id: String in source_ids:
		if root.get_node("GeneratedVisual/" + source_id) is MeshInstance3D: visible_sources += 1
	check(visible_sources == 0, id + " 无可见源壳join")
	for source: Dictionary in built.semantic_sources.values():
		for mesh_record: Dictionary in source.mesh_records:
			var transform: Transform3D = Transform3D(Basis.IDENTITY, source.position) * mesh_record.transform
			var points := PackedVector3Array()
			# 源操作数保留上传精度；get_faces会先吸附0.1mm，不能拿它作CSG真值。
			for surface: int in mesh_record.mesh.get_surface_count():
				var arrays: Array = mesh_record.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				for index: int in indices.size() if not indices.is_empty() else vertices.size():
					points.append(transform * vertices[indices[index] if not indices.is_empty() else index])
			var triangles := TriangleMesh.new()
			var scaled := PackedVector3Array()
			for point: Vector3 in points: scaled.append(point * 100.0)
			triangles.create_from_faces(scaled)
			var bounds := AABB(points[0], Vector3.ZERO)
			for point: Vector3 in points: bounds = bounds.expand(point)
			sources.append({"bvh": triangles, "bounds": bounds, "faces": points})
	var interior: Array = []
	var outside: Array = []
	# 每个实际三角的两个内点双侧探针；0.03mm另作诊断，不用大步长跨越薄空气缝。
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		var normal: Vector3 = -(b - a).cross(c - a).normalized()
		for weights: Vector3 in [Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), Vector3(0.23, 0.31, 0.46)]:
			var center: Vector3 = a * weights.x + b * weights.y + c * weights.z
			var delta: float = 0.0001
			var inner: bool = _inside_sources(center - normal * delta, sources)
			var outer: bool = _inside_sources(center + normal * delta, sources)
			if outer:
				interior.append({"triangle": index / 3, "center": str(center), "inner": inner, "outer": outer, "vertices": str([a, b, c]), "normal": str(normal), "narrow_inner": _inside_sources(center - normal * 0.00003, sources), "narrow_outer": _inside_sources(center + normal * 0.00003, sources)})
			elif not inner:
				outside.append({"triangle": index / 3, "center": str(center), "vertices": str([a, b, c]), "normal": str(normal), "inner": inner, "outer": outer})
	record["internal_samples"] = interior
	record["outside_samples"] = outside
	check(interior.is_empty(), id + " 无内部面/朝内面", interior.slice(0, 12))
	check(outside.is_empty(), id + " 表面内侧属于源实体并集", outside.slice(0, 12))
	var shared: Dictionary = MeshBuilder.shared_materials()
	var material_errors: Array = []
	var stack: Array[Node] = [root]
	var collision_faces: PackedVector3Array = PackedVector3Array()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		check(node.get_script() == null and not node is CSGShape3D, id + " 静态无脚本/CSG " + str(node.name))
		if node is MeshInstance3D:
			for surface: int in node.mesh.get_surface_count():
				var material: Material = node.mesh.surface_get_material(surface)
				if not shared.values().has(material) or material.resource_path.is_empty(): material_errors.append(str(node.name) + " 材质非共享外链")
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
				if uv != uv2: material_errors.append(str(node.name) + " UV2不一致")
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				for offset: int in range(0, indices.size() if not indices.is_empty() else uv.size(), 3):
					var t: Array = []
					for corner: int in 3: t.append(uv[indices[offset + corner] if not indices.is_empty() else offset + corner])
					if absf((t[1] - t[0]).cross(t[2] - t[0])) <= 1.0e-10: material_errors.append(str(node.name) + " 退化UV")
					for point: Vector2 in t:
						if Vector2i(point * 8.0) != Vector2i(t[0] * 8.0) or point.x < 0.0 or point.y < 0.0 or point.x >= 1.0 or point.y >= 1.0: material_errors.append(str(node.name) + " 跨Palette格")
		if node is CollisionShape3D and str(node.get_meta("part_id", "")) == "structure_union":
			check(node.shape is ConcavePolygonShape3D, id + " 真实三角碰撞")
			if node.shape is ConcavePolygonShape3D: collision_faces.append_array(node.shape.get_faces())
		for child: Node in node.get_children(): stack.append(child)
	check(material_errors.is_empty(), id + " 四材质共享及PaletteUV", material_errors.slice(0, 12))
	check(collision_faces == faces, id + " 结构碰撞与可见faces完全一致")
	await _test_physics_rays(root, structure.mesh, id)
	for slot: Dictionary in built.slots:
		if not bool(slot.get("semantic_source_only", false)): continue
		var node: Node = root.get_node(slot.node_path)
		check(not node is MeshInstance3D and node.get_child_count() == 0, id + " 源槽仅语义 " + str(slot.id))
	var packed := PackedScene.new()
	check(packed.pack(root) == OK, id + " 可打包静态场景")
	var scene_path: String = "res://outputs/union_" + id + ".tscn"
	check(ResourceSaver.save(packed, scene_path) == OK, id + " 保存静态场景")
	var reloaded: PackedScene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var restored: Node = reloaded.instantiate()
	var restored_mesh: Mesh = restored.get_node("GeneratedVisual/structure_union").mesh
	check(bool(_audit(restored_mesh.get_faces()).valid), id + " 重载实际faces闭合")
	check(restored_mesh.get_faces() == faces, id + " 保存重载faces完全一致，保留内部面核验结论")
	var restored_collision: PackedVector3Array = PackedVector3Array()
	stack = [restored]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		check(node.get_script() == null and not node is CSGShape3D, id + " 重载静态无CSG " + str(node.name))
		if node is CollisionShape3D and str(node.get_meta("part_id", "")) == "structure_union":
			restored_collision.append_array(node.shape.get_faces())
		for child: Node in node.get_children(): stack.append(child)
	check(restored_collision == faces, id + " 重载碰撞与实际faces一致")
	for surface: int in restored_mesh.get_surface_count(): check(shared.values().has(restored_mesh.surface_get_material(surface)), id + " 重载共享材质")
	restored.free()
	root.free()
	record["milliseconds"] = Time.get_ticks_msec() - start
	print("[workshop-union] case=", id, " topology=", audit, " internal=", interior.size(), " outside=", outside.size())

func _test_physics_rays(building: Node3D, mesh: Mesh, id: String) -> void:
	# 只挂入融合结构碰撞，防止玻璃/门框等独立碰撞抢先命中而误判。
	var fixture := Node3D.new()
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 19
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = building.get_node("Spatial/Collision").find_child("Collision_structure_union_*", false, false).get_node("Shape").shape
	body.add_child(shape)
	fixture.add_child(body)
	get_root().add_child(fixture)
	await physics_frame
	await physics_frame
	var bvh := TriangleMesh.new()
	bvh.create_from_faces(mesh.get_faces())
	var bounds: AABB = mesh.get_aabb()
	for fraction: Vector2 in [Vector2(0.21, 0.29), Vector2(0.53, 0.67), Vector2(0.79, 0.41)]:
		var from := Vector3(bounds.position.x + bounds.size.x * fraction.x, bounds.end.y + 2.0, bounds.position.z + bounds.size.z * fraction.y)
		var to := Vector3(from.x, bounds.position.y - 2.0, from.z)
		var expected: Dictionary = bvh.intersect_segment(from, to)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 << 19)
		var hit: Dictionary = fixture.get_world_3d().direct_space_state.intersect_ray(query)
		check(hit.is_empty() == expected.is_empty(), id + " 物理射线命中/缺口一致 " + str(fraction))
		if not hit.is_empty() and not expected.is_empty():
			check(hit.collider == body and hit.position.distance_to(expected.position) < 0.0002, id + " 物理命中实际结构表面 " + str(fraction))
	fixture.free()

func _test_probe_controls() -> void:
	var sources: Array = []
	var joined := PackedVector3Array()
	for x: float in [-0.4, 0.4]:
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 2.0, 2.0)
		var points := PackedVector3Array()
		var scaled := PackedVector3Array()
		for point: Vector3 in box.get_faces():
			var placed: Vector3 = point + Vector3(x, 0.0, 0.0)
			points.append(placed)
			scaled.append(placed * 100.0)
		joined.append_array(points)
		var bvh := TriangleMesh.new()
		bvh.create_from_faces(scaled)
		sources.append({"bvh": bvh, "bounds": AABB(Vector3(x - 1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))})
	check(_inside_sources(Vector3.ZERO, sources), "射线阳性：交叠内部")
	check(not _inside_sources(Vector3(4.0, 0.0, 0.0), sources), "射线阴性：实体外部")
	var detected: int = 0
	for index: int in range(0, joined.size(), 3):
		var a: Vector3 = joined[index]
		var b: Vector3 = joined[index + 1]
		var c: Vector3 = joined[index + 2]
		var center: Vector3 = (a + b + c) / 3.0
		var normal: Vector3 = -(b - a).cross(c - a).normalized()
		if _inside_sources(center - normal * 0.0001, sources) and _inside_sources(center + normal * 0.0001, sources): detected += 1
	check(detected >= 4, "join负例必须抓出内部面", detected)
	check(not bool(_audit(joined).valid), "join负例不能通过最终拓扑")

func _inside_sources(point: Vector3, sources: Array) -> bool:
	for source: Dictionary in sources:
		if not source.bounds.grow(0.000001).has_point(point): continue
		var votes: int = 0
		for direction: Vector3 in [Vector3(0.61391, 0.33173, 0.71629).normalized(), Vector3(-0.43719, 0.81113, -0.38971).normalized(), Vector3(0.29131, -0.53917, -0.79031).normalized()]:
			var origin: Vector3 = point * 100.0
			var crossings: int = 0
			for step: int in 128:
				var hit: Dictionary = source.bvh.intersect_ray(origin, direction)
				if hit.is_empty(): break
				crossings += 1
				origin = hit.position + direction * 0.001
			if crossings % 2 == 1: votes += 1
		if votes >= 2: return true
	return false

func _audit(faces: PackedVector3Array) -> Dictionary:
	var edges: Dictionary = {}
	var unique: Dictionary = {}
	var adjacency: Array = []
	var degenerate: int = 0
	var duplicates: int = 0
	var volume: float = 0.0
	for start: int in range(0, faces.size(), 3):
		adjacency.append([])
		var keys: Array[String] = []
		for corner: int in 3:
			var point: Vector3 = faces[start + corner]
			if not point.is_finite(): degenerate += 1
			keys.append(str(Vector3i(roundi(point.x * 100000.0), roundi(point.y * 100000.0), roundi(point.z * 100000.0))))
		var cross: Vector3 = (faces[start + 1] - faces[start]).cross(faces[start + 2] - faces[start])
		if cross.length_squared() <= 1.0e-18 or keys[0] == keys[1] or keys[1] == keys[2] or keys[2] == keys[0]: degenerate += 1
		volume -= faces[start].dot(faces[start + 1].cross(faces[start + 2])) / 6.0
		var sorted: Array[String] = keys.duplicate()
		sorted.sort()
		var tk: String = "|".join(sorted)
		if unique.has(tk): duplicates += 1
		unique[tk] = true
		for edge: int in 3:
			var a: String = keys[edge]
			var b: String = keys[(edge + 1) % 3]
			var ek: String = a + ":" + b if a < b else b + ":" + a
			if not edges.has(ek): edges[ek] = {"faces": [], "balance": 0}
			edges[ek].faces.append(start / 3)
			edges[ek].balance += 1 if a < b else -1
	var boundary: int = 0
	var nonmanifold: int = 0
	var orientation: int = 0
	for entry: Dictionary in edges.values():
		if entry.faces.size() == 1: boundary += 1
		elif entry.faces.size() != 2: nonmanifold += 1
		if entry.balance != 0: orientation += 1
		if entry.faces.size() == 2:
			adjacency[entry.faces[0]].append(entry.faces[1])
			adjacency[entry.faces[1]].append(entry.faces[0])
	var visited: Dictionary = {}
	var components: int = 0
	for index: int in adjacency.size():
		if visited.has(index): continue
		components += 1
		var pending: Array = [index]
		visited[index] = true
		while not pending.is_empty():
			var current: int = pending.pop_back()
			for neighbor: int in adjacency[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
	return {"valid": not faces.is_empty() and boundary == 0 and nonmanifold == 0 and orientation == 0 and degenerate == 0 and duplicates == 0 and components == 1 and volume > 1.0e-8, "boundary_edges": boundary, "nonmanifold_edges": nonmanifold, "orientation_errors": orientation, "degenerate_triangles": degenerate, "duplicate_triangles": duplicates, "components": components, "signed_volume": volume, "triangles": faces.size() / 3}
