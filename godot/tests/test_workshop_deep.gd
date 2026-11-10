extends SceneTree

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Session = preload("res://src/workshop/session.gd")
const Store = preload("res://src/workshop/store.gd")

var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL [workshop-deep] ", message)

func finite_reason(data: Dictionary, catalog: Dictionary) -> String:
	return Recipe.validate(data, catalog)

func copy_recipe(recipe: Dictionary) -> Dictionary:
	return recipe.duplicate(true)

func slot_map(slots: Array) -> Dictionary:
	var result: Dictionary = {}
	for item: Dictionary in slots:
		result[str(item.get("id", ""))] = item
	return result

func mesh_triangle_count(node: Node) -> int:
	var total: int = 0
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				total += vertices.size() / 3
			else:
				total += indices.size() / 3
	return total

func mesh_uv_contract(node: Node) -> bool:
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index: int in mesh_instance.mesh.get_surface_count():
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			if uvs.is_empty() or indices.is_empty() or indices.size() % 3 != 0:
				return false
			for triangle_start: int in range(0, indices.size(), 3):
				var first_uv: Vector2 = uvs[int(indices[triangle_start])]
				var cell: Vector2i = Vector2i(int(floor(first_uv.x * 8.0)), int(floor(first_uv.y * 8.0)))
				var triangle_uvs: Array[Vector2] = [first_uv, uvs[int(indices[triangle_start + 1])], uvs[int(indices[triangle_start + 2])]]
				var area: float = absf((triangle_uvs[1] - triangle_uvs[0]).cross(triangle_uvs[2] - triangle_uvs[0])) * 0.5
				if area <= 0.00000001:
					return false
				for uv: Vector2 in triangle_uvs:
					if not is_finite(uv.x) or not is_finite(uv.y):
						return false
					if Vector2i(int(floor(uv.x * 8.0)), int(floor(uv.y * 8.0))) != cell:
						return false
					var pixel: Vector2 = uv * 512.0
					var cell_min: Vector2 = Vector2(cell) * 64.0
					var cell_max: Vector2 = cell_min + Vector2.ONE * 64.0
					if pixel.x < cell_min.x + 8.0 or pixel.x > cell_max.x - 8.0 or pixel.y < cell_min.y + 8.0 or pixel.y > cell_max.y - 8.0:
						return false
	return true

func copied_mesh_with_bad_uv(source: MeshInstance3D) -> Node3D:
	var result: Node3D = Node3D.new()
	var copy: MeshInstance3D = MeshInstance3D.new()
	var copied_mesh: ArrayMesh = ArrayMesh.new()
	for surface_index: int in source.mesh.get_surface_count():
		var arrays: Array = source.mesh.surface_get_arrays(surface_index)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if surface_index == 0 and not uvs.is_empty():
			uvs[0] = Vector2(1.2, -0.1)
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		copied_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	copy.mesh = copied_mesh
	result.add_child(copy)
	return result

func collision_slot_ids(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for body_node: Node in node.find_children("*", "StaticBody3D", true, false):
		var body: StaticBody3D = body_node as StaticBody3D
		if body != null:
			result[str(body.get_meta("slot_id", ""))] = true
	return result

func mesh_aabb_at_height(mesh: ArrayMesh, top: bool) -> float:
	var points: PackedVector3Array = PackedVector3Array()
	for surface_index: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		points.append_array(vertices)
	if points.is_empty():
		return 0.0
	var y_limit: float = -INF if top else INF
	for point: Vector3 in points:
		if top:
			y_limit = maxf(y_limit, point.y)
		else:
			y_limit = minf(y_limit, point.y)
	var extent: float = 0.0
	for point: Vector3 in points:
		if absf(point.y - y_limit) < 0.0001:
			extent = maxf(extent, absf(point.x))
	return extent

func read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value

func run() -> void:
	var catalog: Dictionary = Catalog.definitions()
	var recipe: Dictionary = Recipe.defaults()
	check(Catalog.validate(catalog).is_empty(), "catalog 可用")
	check(Recipe.validate(recipe, catalog).is_empty(), "默认配方可用")

	var bad: Dictionary = copy_recipe(recipe)
	bad["future_field"] = true
	check(not finite_reason(bad, catalog).is_empty(), "未知字段返回拒绝原因")
	bad = copy_recipe(recipe)
	bad["schema_version"] = 1.5
	check(not finite_reason(bad, catalog).is_empty(), "浮点未来版本返回拒绝原因")
	bad = copy_recipe(recipe)
	bad["catalog_id"] = "future_catalog"
	check(not finite_reason(bad, catalog).is_empty(), "配方 catalog mismatch 返回拒绝原因")
	bad = copy_recipe(recipe)
	bad["width"] = NAN
	check(not finite_reason(bad, catalog).is_empty(), "NaN 返回非有限原因")
	bad = copy_recipe(recipe)
	bad["growth_weights"] = [INF, 0.0, 0.0]
	check(not finite_reason(bad, catalog).is_empty(), "Infinity 返回非有限原因")
	bad = copy_recipe(recipe)
	var mismatched_bindings: Dictionary = bad["component_bindings"].duplicate(true)
	mismatched_bindings["wall"] = "glass_blue"
	bad["component_bindings"] = mismatched_bindings
	check(not finite_reason(bad, catalog).is_empty(), "catalog family mismatch 返回原因")
	var unsafe_catalog: Dictionary = catalog.duplicate(true)
	var unsafe_wall: Dictionary = unsafe_catalog["components"]["wall_warm"].duplicate(true)
	unsafe_wall["kind"] = "prefab"
	unsafe_wall["prefab"] = "res://unsafe/workshop_wall.tscn"
	unsafe_catalog["components"]["wall_warm"] = unsafe_wall
	check(not Catalog.validate(unsafe_catalog).is_empty(), "unsafe prefab 返回白名单拒绝原因")
	var bad_catalog: Dictionary = catalog.duplicate(true)
	bad_catalog["catalog_id"] = "other_catalog"
	check(not Catalog.validate(bad_catalog).is_empty(), "catalog mismatch 返回原因")

	var session: RefCounted = Session.new(catalog)
	var original: Dictionary = session.snapshot()
	var external_copy: Dictionary = session.snapshot()
	external_copy["component_bindings"]["wall"] = "wall_sun"
	check(str(session.snapshot()["component_bindings"]["wall"]) == "wall_warm", "session snapshot 是深拷贝")
	check(bool(session.apply_patch({"width": 15.0}).get("ok", false)), "session 修改成功")
	check(session.is_dirty(), "session 修改进入 dirty")
	check(session.undo() and session.snapshot()["width"] == original["width"], "session 撤销恢复原配方")
	check(session.redo() and session.snapshot()["width"] == 15.0, "session 重做恢复修改")
	var loaded_recipe: Dictionary = copy_recipe(original)
	loaded_recipe["building_id"] = "loaded_workshop"
	var loaded_catalog: Dictionary = catalog.duplicate(true)
	loaded_catalog["components"]["wall_sun"]["color"] = "timber_dark"
	var accepted: Dictionary = session.accept_loaded(loaded_recipe, loaded_catalog)
	check(bool(accepted.get("ok", false)) and str(session.snapshot()["building_id"]) == "loaded_workshop", "session 载入配方")
	loaded_catalog["components"]["wall_sun"]["color"] = "mutated_after_load"
	check(str(session.catalog["components"]["wall_sun"]["color"]) == "timber_dark", "session 保存独立 catalog 快照")
	check(not session.undo(), "载入 catalog 后撤销栈清空")

	var base_build: Dictionary = Generator.build(recipe, catalog)
	check(bool(base_build.get("ok", false)), "默认结构生成")
	if bool(base_build.get("ok", false)):
		var base_root: Node3D = base_build["root"] as Node3D
		var base_slots: Array = base_build["slots"] as Array
		var deterministic_build: Dictionary = Generator.build(recipe, catalog)
		check(JSON.stringify(base_slots) == JSON.stringify(deterministic_build["slots"] as Array), "生成槽位确定性")
		check(int(base_build["stats"].get("triangles", 0)) == mesh_triangle_count(base_root), "triangle stats 等于真实 loop triangles")
		var bad_uv_caught: bool = false
		var mesh_nodes: Array[Node] = base_root.find_children("*", "MeshInstance3D", true, false)
		if not mesh_nodes.is_empty():
			var first_mesh: MeshInstance3D = mesh_nodes[0] as MeshInstance3D
			if first_mesh != null and first_mesh.mesh != null:
				var bad_uv_node: Node3D = copied_mesh_with_bad_uv(first_mesh)
				bad_uv_caught = not mesh_uv_contract(bad_uv_node)
				bad_uv_node.free()
		check(mesh_uv_contract(base_root) and bad_uv_caught, "每个 UV 三角落在单个64px色板格、边缘留8px且同谓词捕获越界 UV")
		if bool(deterministic_build.get("ok", false)):
			var deterministic_root: Node3D = deterministic_build["root"] as Node3D
			deterministic_root.free()
		var wall_id: String = ""
		for slot: Variant in base_slots:
			if slot is Dictionary and str(slot.get("kind", "")) == "wall":
				wall_id = str(slot.get("id", ""))
				break
		var overridden: Dictionary = copy_recipe(recipe)
		var slot_overrides: Dictionary = overridden["slot_overrides"].duplicate(true)
		slot_overrides[wall_id] = {"component_id": "wall_sun", "offset": [0.25, 0.0, 0.0]}
		overridden["slot_overrides"] = slot_overrides
		var replacement_build: Dictionary = Generator.build(overridden, catalog)
		var replacement_slots: Dictionary = slot_map(replacement_build.get("slots", []))
		check(bool(replacement_build.get("ok", false)) and replacement_slots.has(wall_id)
			and str(replacement_slots[wall_id].get("component_id", "")) == "wall_sun"
			and float(replacement_slots[wall_id]["position"][0]) != float(slot_map(base_slots)[wall_id]["position"][0]), "slot override 替换 wall_warm->wall_sun 且保留 slot 身份")
		if bool(replacement_build.get("ok", false)):
			var replacement_root: Node3D = replacement_build["root"] as Node3D
			replacement_root.free()
		var excluded: Dictionary = copy_recipe(recipe)
		excluded["excluded_slots"] = [wall_id]
		var missing_build: Dictionary = Generator.build(excluded, catalog)
		var missing_root: Node3D = missing_build["root"] as Node3D
		var missing_visual_ids: Dictionary = slot_map(missing_build["slots"] as Array)
		var missing_collision_ids: Dictionary = collision_slot_ids(missing_root)
		check(bool(missing_build.get("ok", false)) and not missing_visual_ids.has(wall_id) and not missing_collision_ids.has(wall_id), "缺件的视觉与静态 collision 同步移除")
		missing_root.free()
		base_root.free()

	var l_recipe: Dictionary = copy_recipe(recipe)
	l_recipe["shape"] = "l"
	l_recipe["vegetation_density"] = 0.0
	var l_build: Dictionary = Generator.build(l_recipe, catalog)
	check(bool(l_build.get("ok", false)), "L 形结构生成")
	if bool(l_build.get("ok", false)):
		var l_root: Node3D = l_build["root"] as Node3D
		root.add_child(l_root)
		await physics_frame
		var space: PhysicsDirectSpaceState3D = l_root.get_world_3d().direct_space_state
		var courtyard_x: float = float(l_recipe["width"]) * 0.25
		var courtyard_z: float = float(l_recipe["depth"]) * 0.25
		var courtyard_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(courtyard_x, 18.0, courtyard_z), Vector3(courtyard_x, -1.0, courtyard_z), 0xFFFFFFFF)
		var courtyard_hit: Dictionary = space.intersect_ray(courtyard_query)
		check(courtyard_hit.is_empty(), "L 形院落由实际缺角坐标 ray collision 保持开口而非 bbox 假绿")
		var door_x: float = 0.0
		for slot: Variant in l_build["slots"] as Array:
			if slot is Dictionary and str(slot.get("id", "")).contains("door_left"):
				door_x = float((slot as Dictionary)["position"][0]) + float((slot as Dictionary)["size"][0])
				break
			# door_left 的 size 包含左门框；中心线直接取 front door slot 的中心。
		var door_slot_found: bool = false
		for slot: Variant in l_build["slots"] as Array:
			if slot is Dictionary and str(slot.get("id", "")).contains("door_header"):
				door_x = float((slot as Dictionary)["position"][0])
				door_slot_found = true
				break
		var door_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(door_x, 1.0, -5.5), Vector3(door_x, 1.0, -3.5), 0xFFFFFFFF)
		var door_hit: Dictionary = space.intersect_ray(door_query)
		check(door_slot_found and door_hit.is_empty(), "真实门洞脚部无遮挡")
		var glass_collision: bool = true
		var collision_ids: Dictionary = collision_slot_ids(l_root)
		for slot: Variant in l_build["slots"] as Array:
			if slot is Dictionary and str(slot.get("kind", "")) == "glass":
				glass_collision = glass_collision and not collision_ids.has(str(slot.get("id", "")))
		check(glass_collision, "窗玻璃视觉存在但不进入 collision")
		l_root.free()

	var damaged: Dictionary = copy_recipe(recipe)
	damaged["damage"] = 1.0
	var damaged_build: Dictionary = Generator.build(damaged, catalog)
	check(bool(damaged_build.get("ok", false)), "损坏配方仍生成受控结构")
	if bool(damaged_build.get("ok", false)):
		var damaged_root: Node3D = damaged_build["root"] as Node3D
		var damaged_visual_ids: Dictionary = slot_map(damaged_build["slots"] as Array)
		var damaged_collision_ids: Dictionary = collision_slot_ids(damaged_root)
		var synced: bool = true
		for collision_id: String in damaged_collision_ids.keys():
			synced = synced and damaged_visual_ids.has(collision_id)
		check(synced, "随机损坏不留下孤立 collision 缺件")
		damaged_root.free()

	var taper_zero: Dictionary = copy_recipe(recipe)
	taper_zero["taper"] = 0.0
	var taper_full: Dictionary = copy_recipe(recipe)
	taper_full["taper"] = 0.1
	var taper_a: Dictionary = Generator.build(taper_zero, catalog)
	var taper_b: Dictionary = Generator.build(taper_full, catalog)
	var taper_id: String = ""
	if bool(taper_a.get("ok", false)):
		for slot: Variant in taper_a["slots"] as Array:
			if slot is Dictionary and str(slot.get("kind", "")) == "wall":
				taper_id = str(slot.get("id", ""))
				break
	var taper_mesh_a: ArrayMesh = null
	var taper_mesh_b: ArrayMesh = null
	if bool(taper_a.get("ok", false)) and bool(taper_b.get("ok", false)):
		var node_a: Node = (taper_a["root"] as Node).find_child(taper_id, true, false)
		var node_b: Node = (taper_b["root"] as Node).find_child(taper_id, true, false)
		if node_a is MeshInstance3D and node_b is MeshInstance3D:
			taper_mesh_a = (node_a as MeshInstance3D).mesh as ArrayMesh
			taper_mesh_b = (node_b as MeshInstance3D).mesh as ArrayMesh
	check(taper_mesh_a != null and taper_mesh_b != null and mesh_aabb_at_height(taper_mesh_b, true) < mesh_aabb_at_height(taper_mesh_a, true), "taper 实际改变顶部几何")
	if bool(taper_a.get("ok", false)): (taper_a["root"] as Node).free()
	if bool(taper_b.get("ok", false)): (taper_b["root"] as Node).free()

	var growth_stats: Array[int] = []
	for growth_key: String in ["small", "medium", "large"]:
		var growth_recipe: Dictionary = copy_recipe(recipe)
		growth_recipe["vegetation_density"] = 1.0
		growth_recipe["growth_weights"] = [1.0, 0.0, 0.0] if growth_key == "small" else ([0.0, 1.0, 0.0] if growth_key == "medium" else [0.0, 0.0, 1.0])
		var growth_build: Dictionary = Generator.build(growth_recipe, catalog)
		check(bool(growth_build.get("ok", false)), "植物 %s 生成" % growth_key)
		if bool(growth_build.get("ok", false)):
			growth_stats.append(int(growth_build["stats"].get("triangles", 0)))
			(growth_build["root"] as Node).free()
	check(growth_stats.size() == 3 and growth_stats[0] != growth_stats[1] and growth_stats[1] != growth_stats[2], "small/medium/large 使用不同真实拓扑")
	var tree_recipe: Dictionary = copy_recipe(recipe)
	tree_recipe["vegetation_density"] = 1.0
	tree_recipe["component_bindings"]["plant"] = "plant_tree"
	var tree_build: Dictionary = Generator.build(tree_recipe, catalog)
	var tree_grounded: bool = bool(tree_build.get("ok", false))
	if tree_grounded:
		var tree_root: Node3D = tree_build["root"] as Node3D
		var roof_y: float = float(recipe["floors"]) * float(recipe["floor_height"]) + float(recipe["slab_thickness"])
		for plant_node: Node in tree_root.find_children("*", "MeshInstance3D", true, false):
			if not str(plant_node.name).begins_with("plant_"):
				continue
			var plant_mesh: Mesh = (plant_node as MeshInstance3D).mesh
			var plant_aabb: AABB = plant_mesh.get_aabb()
			var bottom: float = (plant_node as MeshInstance3D).position.y + plant_aabb.position.y
			tree_grounded = tree_grounded and is_equal_approx(bottom, roof_y)
	check(tree_grounded, "植物底心贴合实际屋顶且无悬空")
	if bool(tree_build.get("ok", false)): (tree_build["root"] as Node).free()

	var metadata_build: Dictionary = Generator.build(recipe, catalog)
	var metadata_ok: bool = bool(metadata_build.get("ok", false))
	if metadata_ok:
		var metadata_root: Node3D = metadata_build["root"] as Node3D
		for node: Node in metadata_root.find_children("*", "Node", true, false):
			if node != metadata_root:
				metadata_ok = metadata_ok and node.owner == metadata_root and node.get_script() == null
		for mesh_node: Node in metadata_root.find_children("*", "MeshInstance3D", true, false):
			metadata_ok = metadata_ok and mesh_node.has_meta("slot_id") and mesh_node.has_meta("component_id")
	check(metadata_ok, "实例 owner 独立且无 runtime rebuild script")
	if bool(metadata_build.get("ok", false)): (metadata_build["root"] as Node).free()

	var store: RefCounted = Store.new()
	var base_dir: String = "user://building_workshop/deep_%d" % Time.get_ticks_usec()
	var export_a: Dictionary = store.export_revision(recipe, catalog, base_dir)
	var export_b: Dictionary = store.export_revision(recipe, catalog, base_dir)
	check(bool(export_a.get("ok", false)) and bool(export_b.get("ok", false)), "store 两次导出成功")
	check(str(export_a.get("directory", "")) != str(export_b.get("directory", "")), "重复导出保留不同 revision")
	if bool(export_a.get("ok", false)) and bool(export_b.get("ok", false)):
		var loaded: Dictionary = store.load_recipe(str(export_b["recipe_path"]))
		var manifest: Variant = read_json(str(export_b["manifest_path"]))
		var exported_catalog: Variant = read_json(str(export_b["catalog_path"]))
		var hashes_ok: bool = manifest is Dictionary and exported_catalog is Dictionary and bool(loaded.get("ok", false))
		if hashes_ok:
			var source_hashes: Dictionary = manifest.get("source_hashes", {})
			for filename: String in ["building.recipe.json", "catalog_snapshot.json", "building.tscn"]:
				var file_path: String = str(export_b["directory"]) + "/" + filename
				hashes_ok = hashes_ok and FileAccess.file_exists(file_path) and str(source_hashes.get(filename, "")) == FileAccess.get_sha256(file_path)
			hashes_ok = hashes_ok and Catalog.fingerprint(exported_catalog as Dictionary) == Catalog.fingerprint(loaded["catalog"] as Dictionary)
		check(hashes_ok, "JSON、catalog snapshot 与 manifest 文件 sha/hash 读回一致")
		check(store.list_documents(base_dir).size() == 1, "store 能从重复 revision 读回一个最新文档")
	else:
		check(false, "导出结果缺少可读路径")

	print("[workshop-deep] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
