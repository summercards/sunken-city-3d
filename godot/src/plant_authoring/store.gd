@tool
extends RefCounted
class_name PlantAuthoringStore
## 植物工坊候选保存器：只写配方、静态场景和候选 manifest。

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")

const DEFAULT_ROOT := "res://scenes/workshop_plants"
const OUTPUT_ROOT := "res://outputs/plant_editor"
const MAX_RECIPE_BYTES := 1024 * 1024
const SCHEMA_VERSION := 1

func save(recipe: Dictionary, root_dir: String = DEFAULT_ROOT) -> Dictionary:
	var result := _fail_result()
	var reason := _validate_root(root_dir)
	if not reason.is_empty():
		result.reason = reason
		return result
	var recipe_copy: Dictionary = _deep_copy(recipe)
	reason = Recipe.validate(recipe_copy)
	if not reason.is_empty():
		result.reason = reason
		return result
	var build: Dictionary = Generator.build(recipe_copy)
	var root := build.get("root") as Node3D
	if not bool(build.get("ok", false)) or root == null:
		if root != null:
			root.free()
		result.reason = str(build.get("reason", "植物生成失败"))
		return result
	var slug := _slug_for_recipe(recipe_copy)
	var directory := _join(root_dir, slug)
	if not _ensure_dir(directory):
		root.free()
		result.reason = "无法创建候选目录"
		return result
	var revision := _next_revision(directory)
	var revision_name := "revision_%04d" % revision
	var final_dir := _join(directory, revision_name)
	var temp_dir := _join(directory, ".tmp_%s_%04d_%s" % [slug, revision, str(Time.get_ticks_usec())])
	if not _ensure_dir(temp_dir):
		root.free()
		result.reason = "无法创建原子临时目录"
		return result

	_prepare_static_tree(root)
	var geometry_before := _geometry_snapshot(root)
	if not _geometry_is_non_empty(geometry_before):
		root.free()
		_remove_dir(temp_dir)
		result.reason = "生成结果没有非空几何"
		return result
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		_remove_dir(temp_dir)
		result.reason = "静态场景打包失败"
		return result

	var recipe_path := _join(temp_dir, "plant.recipe.json")
	var scene_path := _join(temp_dir, "plant.tscn")
	var manifest_path := _join(temp_dir, "plant.manifest.json")
	if not _write_json(recipe_path, recipe_copy):
		root.free()
		_remove_dir(temp_dir)
		result.reason = "配方 JSON 写入失败"
		return result
	if ResourceSaver.save(packed, scene_path) != OK:
		root.free()
		_remove_dir(temp_dir)
		result.reason = "静态场景写入失败"
		return result

	var loaded_recipe := _read_recipe_file(recipe_path)
	if not bool(loaded_recipe.get("ok", false)):
		root.free()
		_remove_dir(temp_dir)
		result.reason = str(loaded_recipe.get("reason", "配方重载失败"))
		return result
	var loaded_scene := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if loaded_scene == null:
		root.free()
		_remove_dir(temp_dir)
		result.reason = "静态场景重载失败"
		return result
	var instance := loaded_scene.instantiate()
	var geometry_after := _geometry_snapshot(instance)
	var verify_reason := _verify_static_snapshot(geometry_before, geometry_after)
	instance.free()
	if not verify_reason.is_empty():
		root.free()
		_remove_dir(temp_dir)
		result.reason = verify_reason
		return result

	var manifest := _make_manifest(recipe_copy, build, revision, geometry_after, recipe_path, scene_path)
	if not _write_json(manifest_path, manifest):
		root.free()
		_remove_dir(temp_dir)
		result.reason = "manifest 写入失败"
		return result
	root.free()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(final_dir)):
		_remove_dir(temp_dir)
		result.reason = "revision 已存在，拒绝覆盖"
		return result
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_dir), ProjectSettings.globalize_path(final_dir)) != OK:
		_remove_dir(temp_dir)
		result.reason = "原子提交 revision 失败"
		return result
	return {
		"ok": true,
		"reason": "",
		"directory": final_dir,
		"recipe_path": _join(final_dir, "plant.recipe.json"),
		"scene_path": _join(final_dir, "plant.tscn"),
		"manifest_path": _join(final_dir, "plant.manifest.json")
	}

func load_recipe(path: String) -> Dictionary:
	var result := {"ok": false, "reason": "", "recipe": {}, "recipe_path": path}
	if not _is_safe_recipe_path(path):
		result.reason = "只允许读取限定根内的 plant.recipe.json"
		return result
	var loaded := _read_recipe_file(path)
	if not bool(loaded.get("ok", false)):
		result.reason = str(loaded.get("reason", "配方读取失败"))
		return result
	result.ok = true
	result.recipe = _deep_copy(loaded.recipe)
	return result

func list_recipes(root_dir: String = DEFAULT_ROOT) -> Array:
	if not _validate_root(root_dir).is_empty():
		return []
	var paths: Array[String] = []
	_collect_recipe_paths(root_dir, 0, paths)
	paths.sort()
	var rows: Array = []
	for path in paths:
		var loaded := load_recipe(path)
		if bool(loaded.get("ok", false)):
			rows.append({
				"recipe": _deep_copy(loaded.recipe),
				"recipe_path": path,
				"directory": path.get_base_dir(),
				"scene_path": _join(path.get_base_dir(), "plant.tscn"),
				"manifest_path": _join(path.get_base_dir(), "plant.manifest.json")
			})
	return rows

func _make_manifest(recipe: Dictionary, build: Dictionary, revision: int, geometry: Dictionary, recipe_path: String, scene_path: String) -> Dictionary:
	var source_paths := [
		"res://src/plant_authoring/recipe.gd",
		"res://src/plant_authoring/generator.gd",
		"res://src/plant_authoring/geometry.gd"
	]
	var source_hashes: Dictionary = {}
	for path in source_paths:
		source_hashes[path] = _sha256_file(path)
	return {
		"schema_version": SCHEMA_VERSION,
		"status": "candidate_only",
		"candidate_only": true,
		"noMain": true,
		"formal_registry_written": false,
		"revision": revision,
		"slug": _slug_for_recipe(recipe),
		"species": recipe.species,
		"name": recipe.name,
		"recipe_sha256": _sha256_file(recipe_path),
		"scene_sha256": _sha256_file(scene_path),
		"source_path_hashes": source_hashes,
		"generator": "res://src/plant_authoring/generator.gd",
		"stats": _deep_copy(build.get("stats", {})),
		"geometry": geometry,
		"static_scene": true,
		"has_scripts": false,
		"has_camera": false,
		"has_lights": false,
		"has_collision": false,
		"wind": "static",
		"file_list": ["plant.recipe.json", "plant.tscn", "plant.manifest.json"]
	}

func _read_recipe_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "配方文件不存在"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "配方文件无法打开"}
	if file.get_length() > MAX_RECIPE_BYTES:
		file.close()
		return {"ok": false, "reason": "配方 JSON 超过 1MB"}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary:
		return {"ok": false, "reason": "配方 JSON 必须是对象"}
	var recipe: Dictionary = value
	var reason := Recipe.validate(recipe)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	return {"ok": true, "reason": "", "recipe": recipe}

func _validate_root(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.is_empty() or normalized.strip_edges() != normalized or normalized.contains(".."):
		return "候选根路径非法"
	if normalized.to_lower().contains("building"):
		return "候选根禁止使用 building 路径"
	if normalized == DEFAULT_ROOT or normalized == OUTPUT_ROOT:
		return ""
	if _is_absolute_path(normalized):
		return "" if normalized != "/" else "候选根路径非法"
	return "候选根只允许默认根、plant_editor 输出根或测试绝对根"

func _is_safe_recipe_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if normalized.get_file() != "plant.recipe.json" or normalized.contains("..") or normalized.to_lower().contains("building"):
		return false
	var base := normalized.get_base_dir()
	if base == DEFAULT_ROOT or base == OUTPUT_ROOT or base.begins_with(DEFAULT_ROOT + "/") or base.begins_with(OUTPUT_ROOT + "/"):
		return true
	return _is_absolute_path(base)

func _collect_recipe_paths(directory: String, depth: int, paths: Array[String]) -> void:
	if depth > 2:
		return
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != ".." and not name.begins_with("."):
			var child := _join(directory, name)
			if dir.current_is_dir():
				if depth < 2:
					_collect_recipe_paths(child, depth + 1, paths)
			elif name == "plant.recipe.json":
				paths.append(child)
		name = dir.get_next()
	dir.list_dir_end()

func _slug_for_recipe(recipe: Dictionary) -> String:
	var source := str(recipe.get("name", "")).to_lower()
	var slug := ""
	for index in source.length():
		var code := source.unicode_at(index)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			slug += char(code)
		else:
			slug += "-"
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	slug = slug.trim_prefix("-").trim_suffix("-")
	if slug.is_empty():
		slug = str(recipe.get("species", "plant")).to_lower()
	return slug

func _prepare_static_tree(root: Node) -> void:
	root.scene_file_path = ""
	root.set_script(null)
	_prepare_static_node(root, root)

func _prepare_static_node(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is Light3D or child is CollisionObject3D or child is CollisionShape3D:
			child.free()
			continue
		if child is Node:
			child.scene_file_path = ""
			child.owner = owner_root
			child.set_script(null)
			_prepare_static_node(child, owner_root)

func _geometry_snapshot(root: Node) -> Dictionary:
	var visual_count := 0
	var triangle_count := 0
	var scripts := 0
	var cameras := 0
	var lights := 0
	var collisions := 0
	var bounds := AABB()
	var has_bounds := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_script() != null:
			scripts += 1
		if node is Camera3D:
			cameras += 1
		if node is Light3D:
			lights += 1
		if node is CollisionObject3D:
			collisions += 1
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh != null:
				visual_count += 1
				triangle_count += _mesh_triangles(mesh)
				var box := (node as Node3D).transform * mesh.get_aabb()
				bounds = box if not has_bounds else bounds.merge(box)
				has_bounds = true
		elif node is MultiMeshInstance3D:
			var multimesh := (node as MultiMeshInstance3D).multimesh
			if multimesh != null and multimesh.mesh != null:
				visual_count += 1
				triangle_count += _mesh_triangles(multimesh.mesh) * multimesh.instance_count
				var multi_box := (node as Node3D).transform * multimesh.mesh.get_aabb()
				bounds = multi_box if not has_bounds else bounds.merge(multi_box)
				has_bounds = true
		for child in node.get_children():
			if child is Node:
				stack.push_back(child)
	return {"visual_meshes": visual_count, "triangles": triangle_count, "scripts": scripts, "cameras": cameras, "lights": lights, "collisions": collisions, "has_bounds": has_bounds, "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}

func _verify_static_snapshot(before: Dictionary, after: Dictionary) -> String:
	if not _geometry_is_non_empty(after):
		return "场景重载后几何为空"
	for key in ["visual_meshes", "triangles", "scripts", "cameras", "lights", "collisions"]:
		if int(before.get(key, -1)) != int(after.get(key, -2)):
			return "场景重载校验不一致：%s" % key
	return ""

func _geometry_is_non_empty(snapshot: Dictionary) -> bool:
	return int(snapshot.get("visual_meshes", 0)) > 0 and int(snapshot.get("triangles", 0)) > 0 and bool(snapshot.get("has_bounds", false))

func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total

func _next_revision(directory: String) -> int:
	var maximum := 0
	var dir := DirAccess.open(directory)
	if dir == null:
		return 1
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if dir.current_is_dir() and name.begins_with("revision_"):
			var number := name.trim_prefix("revision_")
			if number.is_valid_int():
				maximum = maxi(maximum, int(number))
		name = dir.get_next()
	dir.list_dir_end()
	return maximum + 1

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	var error := file.get_error()
	file.close()
	return error == OK

func _sha256_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)

func _ensure_dir(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return DirAccess.make_dir_recursive_absolute(absolute) == OK or DirAccess.dir_exists_absolute(absolute)

func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := _join(path, name)
		if dir.current_is_dir():
			_remove_dir(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _join(left: String, right: String) -> String:
	return left.trim_suffix("/") + "/" + right

func _fail_result() -> Dictionary:
	return {"ok": false, "reason": "", "directory": "", "recipe_path": "", "scene_path": "", "manifest_path": ""}

func _deep_copy(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[key] = _deep_copy(value[key])
		return result
	if value is Array:
		var result_array: Array = []
		for item in value:
			result_array.append(_deep_copy(item))
		return result_array
	return value
