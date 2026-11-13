@tool
extends RefCounted
class_name WorkshopStore
## 仅管理工坊候选根；不写玩家存档、主场景或正式资产账本。

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")

const SCHEMA_VERSION := 1
const GENERATOR_VERSION := "SEA-WORKSHOP-GENERATOR-V1"
const DEFAULT_BASE_DIR := "user://building_workshop"

func export_revision(recipe: Dictionary, catalog: Dictionary = {}, base_dir: String = DEFAULT_BASE_DIR) -> Dictionary:
	var fail: Dictionary = _fail_result()
	var reason: String = _validate_base_dir(base_dir)
	if not reason.is_empty():
		fail.reason = reason
		return fail
	var recipe_copy: Dictionary = _deep_copy(recipe)
	var catalog_copy: Dictionary = _deep_copy(catalog)
	if catalog_copy.is_empty():
		catalog_copy = _deep_copy(Catalog.definitions())
	reason = Recipe.validate(recipe_copy, catalog_copy)
	if not reason.is_empty():
		fail.reason = reason
		return fail
	if not _catalog_is_valid(catalog_copy):
		fail.reason = "组件目录校验失败"
		return fail
	if _contains_forbidden_reference(recipe_copy):
		fail.reason = "配方含有禁止保存的脚本或资源路径"
		return fail
	var building_id: String = str(recipe_copy.get("building_id", ""))
	reason = _validate_segment(building_id, "building_id")
	if not reason.is_empty():
		fail.reason = reason
		return fail
	var building_dir: String = _join(base_dir, building_id)
	if not _ensure_dir(building_dir):
		fail.reason = "无法创建候选目录：%s" % building_dir
		return fail
	var revision: int = _next_revision(building_dir)
	recipe_copy["revision"] = revision
	reason = Recipe.validate(recipe_copy, catalog_copy)
	if not reason.is_empty():
		fail.reason = reason
		return fail
	var final_dir: String = _join(building_dir, "revision_%04d" % revision)
	var temp_dir: String = _join(building_dir, ".tmp_revision_%04d_%s" % [revision, str(Time.get_ticks_usec())])
	if not _ensure_dir(temp_dir):
		fail.reason = "无法创建临时导出目录"
		return fail

	var mesh_builder = preload("res://src/workshop/mesh_builder.gd")
	var build: Dictionary = mesh_builder.apply_build_palette(Generator.build(recipe_copy, catalog_copy), recipe_copy, catalog_copy)
	build = mesh_builder.apply_build_shading(build, recipe_copy, catalog_copy)
	if not bool(build.get("ok", false)):
		_remove_temp_dir(temp_dir, building_dir)
		fail.reason = str(build.get("reason", "生成失败"))
		return fail
	var root: Node3D = build.get("root") as Node3D
	if root == null:
		_remove_temp_dir(temp_dir, building_dir)
		fail.reason = "生成器未返回静态根节点"
		return fail
	var before_snapshot: Dictionary = _tree_snapshot(root)
	_prepare_static_tree(root)
	var packed: PackedScene = PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		_remove_temp_dir(temp_dir, building_dir)
		fail.reason = "静态场景打包失败"
		return fail

	var recipe_path: String = _join(temp_dir, "building.recipe.json")
	var catalog_path: String = _join(temp_dir, "catalog_snapshot.json")
	var scene_path: String = _join(temp_dir, "building.tscn")
	var manifest_path: String = _join(temp_dir, "candidate_manifest.json")
	var ledger_path: String = _join(temp_dir, "ledger.json")
	if not _write_json(recipe_path, recipe_copy) or not _write_json(catalog_path, catalog_copy):
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = "JSON 写入失败"; return fail
	if ResourceSaver.save(packed, scene_path) != OK:
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = "场景资源写入失败"; return fail
	var loaded_scene: Resource = ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded_scene is PackedScene:
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = "场景资源重载失败"; return fail
	var instance: Node = (loaded_scene as PackedScene).instantiate()
	var after_snapshot: Dictionary = _tree_snapshot(instance)
	var verify_reason: String = _compare_tree_snapshots(before_snapshot, after_snapshot)
	if verify_reason.is_empty():
		verify_reason = _verify_static_instance(instance)
	instance.free()
	if not verify_reason.is_empty():
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = verify_reason; return fail
	if not _verify_json(recipe_path, recipe_copy) or not _verify_json(catalog_path, catalog_copy):
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = "JSON 重载校验失败"; return fail
	var source_hashes: Dictionary = {
		"building.recipe.json": _sha256_file(recipe_path),
		"catalog_snapshot.json": _sha256_file(catalog_path),
		"building.tscn": _sha256_file(scene_path)
	}
	var manifest: Dictionary = _make_manifest(recipe_copy, catalog_copy, build, revision, before_snapshot, source_hashes)
	if not _write_json(manifest_path, manifest):
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = "manifest 写入失败"; return fail
	var ledger: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"building_id": building_id,
		"revision": revision,
		"status": "candidate_only",
		"candidate_ledger_status": "exported_pending_project_registration",
		"formal_registration_owner": "SEA-ASSET",
		"note": "工坊候选记录；不会自动写入仓库正式账本。"
	}
	if not _write_json(ledger_path, ledger):
		root.free(); _remove_temp_dir(temp_dir, building_dir); fail.reason = "独立账本写入失败"; return fail
	build["root"] = null
	root.free()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_dir), ProjectSettings.globalize_path(final_dir)) != OK:
		_remove_temp_dir(temp_dir, building_dir)
		fail.reason = "提交 revision 失败，旧版本未改动"
		return fail
	return {
		"ok": true,
		"reason": "",
		"directory": final_dir,
		"recipe_path": _join(final_dir, "building.recipe.json"),
		"scene_path": _join(final_dir, "building.tscn"),
		"manifest_path": _join(final_dir, "candidate_manifest.json"),
		"ledger_path": _join(final_dir, "ledger.json"),
		"catalog_path": _join(final_dir, "catalog_snapshot.json"),
		"catalog": catalog_copy,
		"recipe": Recipe.normalized(recipe_copy)
	}

func load_recipe(path: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "recipe": {}, "catalog": {}}
	if not _is_safe_recipe_path(path):
		result.reason = "只允许读取限定目录内的 .recipe.json"
		return result
	if not FileAccess.file_exists(path):
		result.reason = "配方文件不存在"
		return result
	var recipe_value: Variant = _read_json(path)
	if not recipe_value is Dictionary:
		result.reason = "配方 JSON 不是对象"
		return result
	var catalog_path: String = _join(path.get_base_dir(), "catalog_snapshot.json")
	if not FileAccess.file_exists(catalog_path):
		result.reason = "缺少 catalog 快照"
		return result
	var catalog_value: Variant = _read_json(catalog_path)
	if not catalog_value is Dictionary:
		result.reason = "catalog 快照不是对象"
		return result
	var catalog_snapshot: Dictionary = catalog_value as Dictionary
	if not _catalog_is_valid(catalog_snapshot):
		result.reason = "catalog 快照校验失败"
		return result
	var reason: String = Recipe.validate(recipe_value as Dictionary, catalog_snapshot)
	if not reason.is_empty():
		result.reason = reason
		return result
	result.ok = true
	result.recipe = Recipe.normalized(recipe_value)
	result.catalog = _deep_copy(catalog_snapshot)
	return result

func list_documents(base_dir: String = DEFAULT_BASE_DIR) -> Array:
	var rows: Array = []
	if not _validate_base_dir(base_dir).is_empty():
		return rows
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return rows
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if dir.current_is_dir() and not name.begins_with(".") and _validate_segment(name, "building_id").is_empty():
			var building_dir: String = _join(base_dir, name)
			var latest: String = _latest_revision(building_dir)
			if not latest.is_empty():
				var path: String = _join(_join(building_dir, latest), "building.recipe.json")
				var loaded: Dictionary = load_recipe(path)
				if loaded.ok:
					rows.append({"building_id": name, "display_name": loaded.recipe.get("display_name", name), "revision": latest, "recipe_path": path, "catalog": loaded.catalog})
		name = dir.get_next()
	dir.list_dir_end()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("building_id", "")) < str(b.get("building_id", "")))
	return rows

func _make_manifest(recipe: Dictionary, catalog: Dictionary, build: Dictionary, revision: int, tree_snapshot: Dictionary, source_hashes: Dictionary) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"building_id": recipe.get("building_id", ""),
		"revision": revision,
		"display_name": recipe.get("display_name", ""),
		"catalog_id": catalog.get("catalog_id", "sea_workshop_v1"),
		"catalog_fingerprint": Catalog.fingerprint(catalog),
		"catalog_snapshot": "catalog_snapshot.json",
		"seed": {"structure": recipe.get("structure_seed", 0), "damage": recipe.get("damage_seed", 0), "vegetation": recipe.get("vegetation_seed", 0)},
		"generator": str((build.get("root") as Node).get_meta("generator_version", GENERATOR_VERSION)),
		"construction_mode": str(recipe.get("construction_mode", "modular_v1")),
		"model_quality": build.get("quality", {}),
		"hash": source_hashes.get("building.tscn", ""),
		"recipe_fingerprint": Recipe.fingerprint(recipe),
		"source_hashes": source_hashes,
		"instances": _manifest_instances(build.get("slots", [])),
		"stats": build.get("stats", {}),
		"geometry": tree_snapshot,
		"file_list": ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json"],
		"space_mode": recipe.get("spatial_profile", "above_water"),
		"spatial_declarations": {"walk_surfaces": build.get("walk_surfaces", []), "water_blockers": build.get("water_blockers", [])},
		"candidate_ledger_status": "exported_pending_project_registration",
		"static_scene": true,
		"has_workshop_rebuild_script": false,
		"preview_camera_lights_packed": false
	}

func _manifest_instances(slots: Array) -> Array:
	var instances: Array = []
	for slot in slots:
		if slot is Dictionary:
			instances.append({"id": slot.get("id", ""), "kind": slot.get("kind", ""), "component_id": slot.get("component_id", ""), "node_path": slot.get("node_path", "")})
	return instances

func _catalog_is_valid(value: Dictionary) -> bool:
	return Catalog.validate(value).is_empty()

func _prepare_static_tree(root: Node3D) -> void:
	root.set_script(null)
	_prepare_static_node(root, root)

func _prepare_static_node(node: Node, owner_root: Node) -> void:
	# 烘焙是自足静态快照。外部替件身份留在catalog/metadata，打包时取消嵌套场景继承，
	# 否则owner重设会让实例的原生子网格与本地覆盖重复保存。
	node.scene_file_path = ""
	if node != owner_root:
		node.owner = owner_root
	if node is Camera3D or node is Light3D:
		node.free()
		return
	if node.get_script() != null:
		node.set_script(null)
	for child in node.get_children():
		if child is Node:
			_prepare_static_node(child, owner_root)

func _tree_snapshot(root: Node) -> Dictionary:
	var meshes := 0
	var collisions := 0
	var nodes := 0
	var metadata := 0
	var scripts := 0
	var owners := 0
	var bounds := AABB()
	var collision_bounds := AABB()
	var has_collision_bounds := false
	var has_bounds := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		nodes += 1
		if node.get_script() != null: scripts += 1
		if node != root and node.owner == null: owners += 1
		if node is MeshInstance3D:
			meshes += 1
			if (node as MeshInstance3D).has_meta("slot_id") and (node as MeshInstance3D).has_meta("component_id"): metadata += 1
			var mesh: Mesh = (node as MeshInstance3D).mesh
			if mesh != null:
				var local_box: AABB = mesh.get_aabb()
				var node_box: AABB = _transform_aabb(_root_relative_transform(node, root), local_box)
				bounds = node_box if not has_bounds else bounds.merge(node_box)
				has_bounds = true
		if node is CollisionShape3D:
			collisions += 1
			var collision_shape: CollisionShape3D = node as CollisionShape3D
			var collision_box: AABB = _collision_shape_aabb(collision_shape, root)
			if collision_box.size.length_squared() > 0.0:
				collision_bounds = collision_box if not has_collision_bounds else collision_bounds.merge(collision_box)
				has_collision_bounds = true
		for child in node.get_children():
			if child is Node: stack.push_back(child)
	return {"nodes": nodes, "visual_meshes": meshes, "collision_shapes": collisions, "metadata_meshes": metadata, "scripts": scripts, "unowned_nodes": owners, "has_bounds": has_bounds, "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z], "has_collision_bounds": has_collision_bounds, "collision_bounds_position": [collision_bounds.position.x, collision_bounds.position.y, collision_bounds.position.z], "collision_bounds_size": [collision_bounds.size.x, collision_bounds.size.y, collision_bounds.size.z]}

func _root_relative_transform(node: Node, root: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var current: Node = node
	while current is Node3D and current != root:
		chain.push_back(current as Node3D)
		current = current.get_parent()
	if current != root:
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	for index in range(chain.size() - 1, -1, -1):
		result = result * chain[index].transform
	return result

func _collision_shape_aabb(shape_node: CollisionShape3D, root: Node) -> AABB:
	var transform := _root_relative_transform(shape_node, root)
	if shape_node.shape is BoxShape3D:
		var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
		return _transform_aabb(transform, AABB(-box_shape.size * 0.5, box_shape.size))
	if shape_node.shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (shape_node.shape as ConcavePolygonShape3D).get_faces()
		var result := AABB()
		var initialized := false
		for face in faces:
			var point: Vector3 = transform * face
			if not initialized:
				result = AABB(point, Vector3.ZERO)
				initialized = true
			else:
				result = result.expand(point)
		return result
	return AABB()

func _verify_static_instance(root: Node) -> String:
	var snapshot: Dictionary = _tree_snapshot(root)
	if int(snapshot.get("scripts", 0)) != 0:
		return "导出场景包含脚本"
	if int(snapshot.get("metadata_meshes", 0)) != int(snapshot.get("visual_meshes", 0)):
		return "导出场景缺少 MeshInstance slot/component metadata"
	if int(snapshot.get("unowned_nodes", 0)) != 0:
		return "导出场景存在未归属节点"
	return ""

func _compare_tree_snapshots(before: Dictionary, after: Dictionary) -> String:
	for key in ["visual_meshes", "collision_shapes", "metadata_meshes"]:
		if int(before.get(key, -1)) != int(after.get(key, -2)):
			return "场景重载几何计数不一致：%s (%s -> %s)" % [key, str(before.get(key)), str(after.get(key))]
	if bool(before.get("has_bounds", false)) != bool(after.get("has_bounds", false)):
		return "场景重载包围盒状态不一致"
	if bool(before.get("has_collision_bounds", false)) != bool(after.get("has_collision_bounds", false)):
		return "场景重载碰撞包围盒状态不一致"
	if before.get("has_bounds", false):
		for key in ["bounds_position", "bounds_size"]:
			var a: Array = before[key]
			var b: Array = after[key]
			for index in 3:
				if not is_equal_approx(float(a[index]), float(b[index])):
					return "场景重载包围盒不一致"
	if before.get("has_collision_bounds", false):
		for key in ["collision_bounds_position", "collision_bounds_size"]:
			var collision_a: Array = before[key]
			var collision_b: Array = after[key]
			for index in 3:
				if not is_equal_approx(float(collision_a[index]), float(collision_b[index])):
					return "场景重载碰撞包围盒不一致"
	return ""

func _transform_aabb(transform: Transform3D, box: AABB) -> AABB:
	return transform * box

func _verify_json(path: String, expected: Dictionary) -> bool:
	var actual: Variant = _read_json(path)
	return actual is Dictionary and str(Recipe.fingerprint(actual)) == str(Recipe.fingerprint(expected))

func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value, "\t"))
	var error := file.get_error()
	file.close()
	return error == OK

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	file.close()
	return FileAccess.get_sha256(path)

func _validate_base_dir(path: String) -> String:
	if path.is_empty() or path.contains("..") or path.contains("\\"):
		return "候选根路径非法"
	if path == DEFAULT_BASE_DIR or path.begins_with("user://building_workshop/"):
		return ""
	if path == "res://outputs" or path.begins_with("res://outputs/"):
		return ""
	return "候选根只允许 user://building_workshop 或测试 res://outputs"

func _validate_segment(value: String, label: String) -> String:
	if value.is_empty() or value == "." or value == ".." or value.contains("/") or value.contains("\\") or value.contains(":"):
		return "%s 含有非法路径字符" % label
	if value.strip_edges() != value:
		return "%s 不能首尾带空格" % label
	return ""

func _is_safe_recipe_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if not normalized.ends_with(".recipe.json"):
		return false
	for segment in normalized.split("/"):
		if segment == "..":
			return false
	var user_root := ProjectSettings.globalize_path("user://building_workshop").replace("\\", "/").trim_suffix("/")
	var output_root := ProjectSettings.globalize_path("res://outputs").replace("\\", "/").trim_suffix("/")
	return _under_path(normalized, "user://building_workshop") or _under_path(normalized, "res://outputs") or _under_path(normalized, user_root) or _under_path(normalized, output_root)

func _under_path(path: String, root: String) -> bool:
	return path == root or path.begins_with(root + "/")

func _contains_forbidden_reference(value) -> bool:
	if value is Dictionary:
		for key in value.keys():
			if str(key).to_lower() in ["script", "script_path", "resource_path", "scene_path", "mesh_path", "material_path"]:
				return true
			if _contains_forbidden_reference(value[key]): return true
	elif value is Array:
		for item in value:
			if _contains_forbidden_reference(item): return true
	elif value is String:
		return value.begins_with("res://") or value.begins_with("user://") or value.begins_with("file://")
	return false

func _ensure_dir(path: String) -> bool:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) == OK or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))

func _remove_temp_dir(path: String, parent: String) -> void:
	if path.get_base_dir() != parent or not path.get_file().begins_with(".tmp_revision_"):
		return
	_remove_dir(path)

func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := _join(path, name)
		if dir.current_is_dir(): _remove_dir(child)
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _next_revision(building_dir: String) -> int:
	var maximum := 0
	var dir := DirAccess.open(building_dir)
	if dir == null: return 1
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if dir.current_is_dir() and name.begins_with("revision_"):
			var number := name.trim_prefix("revision_")
			if number.is_valid_int(): maximum = maxi(maximum, int(number))
		name = dir.get_next()
	dir.list_dir_end()
	return maximum + 1

func _latest_revision(building_dir: String) -> String:
	var maximum := 0
	var result := ""
	var dir := DirAccess.open(building_dir)
	if dir == null: return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if dir.current_is_dir() and name.begins_with("revision_"):
			var number: String = name.trim_prefix("revision_")
			if number.is_valid_int() and int(number) > maximum:
				maximum = int(number)
				result = name
		name = dir.get_next()
	dir.list_dir_end()
	return result

func _join(a: String, b: String) -> String:
	return a.trim_suffix("/") + "/" + b

func _fail_result() -> Dictionary:
	return {"ok": false, "reason": "", "directory": "", "recipe_path": "", "scene_path": "", "manifest_path": "", "ledger_path": ""}

func _deep_copy(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys(): result[key] = _deep_copy(value[key])
		return result
	if value is Array:
		var result_array: Array = []
		for item in value: result_array.append(_deep_copy(item))
		return result_array
	return value
