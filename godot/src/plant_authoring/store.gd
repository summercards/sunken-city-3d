@tool
extends RefCounted
class_name PlantAuthoringStore
## 植物工坊候选保存器：只写配方、静态场景和候选 manifest。

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")

const DEFAULT_ROOT := "res://outputs/plant_editor"
const OUTPUT_ROOT := DEFAULT_ROOT
const SCENE_ROOT := "res://scenes/workshop_plants"
const MAX_RECIPE_BYTES := 1024 * 1024
const SCHEMA_VERSION := 2
const RELOAD_TOLERANCE := 0.0002

var _test_root := ""
var _owned_temps: Dictionary = {}

## 测试根必须显式注入且以 plant_authoring_test_ 命名；从不递归删除该根或旧 revision。
func _init(test_root: String = "") -> void:
	if _external_test_root(test_root):
		_test_root = test_root

func save(recipe: Dictionary, root_dir: String = DEFAULT_ROOT) -> Dictionary:
	var result := _fail_result()
	var reason := _validate_root(root_dir)
	if not reason.is_empty():
		result.reason = reason
		return result
	var recipe_copy: Dictionary = Recipe.normalized(recipe)
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
	if _has_link_ancestor(ProjectSettings.globalize_path(directory)) or not _ensure_dir(directory):
		root.free()
		result.reason = "无法创建候选目录"
		return result
	var revision := _next_revision(directory)
	var revision_name := "revision_%04d" % revision
	var final_dir := _join(directory, revision_name)
	var temp_dir := _join(directory, ".tmp_%s_%04d_%s" % [slug, revision, str(Time.get_ticks_usec())])
	if DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temp_dir)) != OK:
		root.free()
		result.reason = "无法创建独占原子临时目录"
		return result
	_owned_temps[temp_dir] = true

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
	if not bool(loaded_recipe.get("ok", false)) or Recipe.fingerprint(loaded_recipe.get("recipe", {})) != Recipe.fingerprint(recipe_copy):
		root.free()
		_remove_dir(temp_dir)
		var differences: Array[String] = []
		for key: String in recipe_copy:
			var saved_value: Variant = loaded_recipe.get("recipe", {}).get(key)
			if Recipe._stable_json(recipe_copy[key]) != Recipe._stable_json(saved_value):
				differences.append(key + ": " + Recipe._stable_json(recipe_copy[key]) + " -> " + Recipe._stable_json(saved_value))
		result.reason = "配方重载失败或指纹不一致：" + str(loaded_recipe.get("reason", "")) + "; ".join(differences)
		return result
	var loaded_scene := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
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
	_owned_temps.erase(temp_dir)
	return {
		"ok": true,
		"reason": "",
		"revision": revision,
		"fingerprint": Recipe.fingerprint(recipe_copy),
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
		"res://src/plant_authoring/geometry.gd",
		"res://src/plant_authoring/species.gd",
		"res://src/plant_authoring/leaf.gdshader",
		"res://src/plant_authoring/store.gd",
		"res://src/ambient/vegetation/library.gd",
		"res://data/vegetation/catalog.json",
		"res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
	]
	if recipe.grass_enabled:
		var catalog: Dictionary = Generator.Library.catalog()
		var grass: Dictionary = catalog[recipe.grass_asset]
		source_paths.append(grass.model)
		source_paths.append(grass.material)
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
		"candidate_id": "%s/revision_%04d" % [_slug_for_recipe(recipe), revision],
		"recipe_fingerprint": Recipe.fingerprint(recipe),
		"geometry_fingerprint": geometry.geometry_fingerprint,
		"uv_fingerprint": geometry.uv_fingerprint,
		"material_fingerprint": geometry.material_fingerprint,
		"reload_tolerance": RELOAD_TOLERANCE,
		"species": recipe.species,
		"name": recipe.name,
		"recipe_sha256": _sha256_file(recipe_path),
		"scene_sha256": _sha256_file(scene_path),
		"source_path_hashes": source_hashes,
		"generator": "res://src/plant_authoring/generator.gd",
		"stats": _deep_copy(build.get("stats", {})),
		"geometry": _snapshot_manifest(geometry),
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
	return {"ok": true, "reason": "", "recipe": Recipe.normalized(recipe)}

func _validate_root(path: String) -> String:
	if path not in [DEFAULT_ROOT, SCENE_ROOT] and (_test_root.is_empty() or path != _test_root):
		return "候选根只允许plant_editor输出根、workshop_plants场景根或显式指定的工程外测试根"
	if _has_link_ancestor(ProjectSettings.globalize_path(path)):
		return "候选根不能经过符号链接"
	return ""

func _external_test_root(path: String) -> bool:
	if path.is_empty() or not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"):
		return false
	if path != path.simplify_path() or path.contains("\\") or path.strip_edges() != path:
		return false
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if path == project or path.begins_with(project + "/") or project.begins_with(path + "/"):
		return false
	return path.get_file().begins_with("plant_authoring_test_") and not _has_link_ancestor(path)

func _has_link_ancestor(path: String) -> bool:
	var current := path.trim_suffix("/")
	while not current.is_empty() and current != current.get_base_dir():
		var parent := DirAccess.open(current.get_base_dir())
		if parent != null and parent.is_link(current.get_file()):
			return true
		current = current.get_base_dir()
	return false

func _is_safe_recipe_path(path: String) -> bool:
	if path.get_file() != "plant.recipe.json" or path != path.simplify_path() or path.contains("\\"):
		return false
	var revision := path.get_base_dir()
	var candidate := revision.get_base_dir()
	var root := candidate.get_base_dir()
	return _validate_root(root).is_empty() and revision.get_file().begins_with("revision_") and not _has_link_ancestor(ProjectSettings.globalize_path(path))

func _collect_recipe_paths(directory: String, depth: int, paths: Array[String]) -> void:
	if depth > 2:
		return
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name != "." and name != ".." and not name.begins_with(".") and not dir.is_link(name):
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
	_prepare_static_node(root, root, {})

func _prepare_static_node(node: Node, owner_root: Node, materials: Dictionary) -> void:
	node.scene_file_path = ""
	node.set_script(null)
	if node != owner_root:
		node.owner = owner_root
	if node is GeometryInstance3D:
		node.material_override = _static_material(node.material_override, materials)
		node.material_overlay = _static_material(node.material_overlay, materials)
	if node is MeshInstance3D and node.mesh != null:
		node.mesh = node.mesh.duplicate()
		for surface in node.mesh.get_surface_count():
			var material := _static_material(node.get_active_material(surface), materials)
			node.mesh.surface_set_material(surface, material)
			node.set_surface_override_material(surface, material)
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		node.multimesh = node.multimesh.duplicate()
		node.multimesh.mesh = node.multimesh.mesh.duplicate()
		for surface in node.multimesh.mesh.get_surface_count():
			node.multimesh.mesh.surface_set_material(surface, _static_material(node.multimesh.mesh.surface_get_material(surface), materials))
	for child in node.get_children():
		if child is Camera3D or child is Light3D or child is CollisionObject3D or child is CollisionShape3D or child is CollisionPolygon3D:
			child.free()
		else:
			_prepare_static_node(child, owner_root, materials)

func _static_material(material: Material, cache: Dictionary) -> Material:
	if material == null:
		return null
	if not cache.has(material):
		var copy := material.duplicate() as Material
		copy.resource_local_to_scene = true
		if copy is ShaderMaterial:
			copy.set_shader_parameter("local_time", 0.0)
			copy.set_shader_parameter("preview_wind", false)
		cache[material] = copy
	return cache[material]

func _geometry_snapshot(root: Node) -> Dictionary:
	var result := {"visual_meshes": 0, "triangles": 0, "scripts": 0, "cameras": 0, "lights": 0, "collisions": 0,
		"has_bounds": false, "bounds": AABB(), "nodes": {}, "materials": {}, "unreadable_multimeshes": 0}
	_snapshot_node(root, root, Transform3D.IDENTITY, result)
	var geometry: Dictionary = {}
	var uv: Dictionary = {}
	for path in result.nodes:
		var entry: Dictionary = result.nodes[path].duplicate(true)
		var uv_surfaces: Array = []
		for surface: Dictionary in entry.get("surfaces", []):
			uv_surfaces.append([surface.uv, surface.uv2])
			surface.erase("uv")
			surface.erase("uv2")
		geometry[path] = entry
		uv[path] = uv_surfaces
	result.geometry_fingerprint = _data_hash(geometry)
	result.uv_fingerprint = _data_hash(uv)
	result.material_fingerprint = _data_hash(result.materials)
	var bounds: AABB = result.bounds
	result.bounds_position = [bounds.position.x, bounds.position.y, bounds.position.z]
	result.bounds_size = [bounds.size.x, bounds.size.y, bounds.size.z]
	return result

func _snapshot_node(node: Node, root: Node, parent: Transform3D, result: Dictionary) -> void:
	if node.get_script() != null: result.scripts += 1
	if node is Camera3D: result.cameras += 1
	if node is Light3D: result.lights += 1
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D: result.collisions += 1
	var world: Transform3D = parent * node.transform if node is Node3D else parent
	if node is Node3D and node.top_level:
		world = node.transform
	var path := str(root.get_path_to(node))
	var entry := {"class": node.get_class(), "transform": world, "visible": node.visible if node is Node3D else true}
	var mesh: Mesh = null
	var instances: Array[Transform3D] = []
	if node is MeshInstance3D:
		mesh = node.mesh
		instances.append(Transform3D.IDENTITY)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var multi: MultiMesh = node.multimesh
		mesh = multi.mesh
		entry.instance_count = multi.instance_count
		entry.visible_instance_count = multi.visible_instance_count
		entry.transform_format = multi.transform_format
		entry.colors = []
		entry.custom_data = []
		# Dummy 后端可吞掉 set_instance_transform 并返回单位阵；此时不能签发保存校验。
		if multi.instance_count > 0 and multi.buffer.is_empty():
			result.unreadable_multimeshes += 1
		for index in multi.instance_count:
			var transform := Transform3D.IDENTITY
			if multi.transform_format == MultiMesh.TRANSFORM_3D:
				transform = multi.get_instance_transform(index)
			else:
				var flat := multi.get_instance_transform_2d(index)
				transform = Transform3D(Basis(Vector3(flat.x.x, flat.x.y, 0), Vector3(flat.y.x, flat.y.y, 0), Vector3.BACK), Vector3(flat.origin.x, flat.origin.y, 0))
			instances.append(transform)
			if multi.use_colors: entry.colors.append(multi.get_instance_color(index))
			if multi.use_custom_data: entry.custom_data.append(multi.get_instance_custom_data(index))
	if mesh != null:
		result.visual_meshes += 1
		result.triangles += _mesh_triangles(mesh) * instances.size()
		entry.instances = instances
		entry.surfaces = []
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			entry.surfaces.append({"primitive": mesh.surface_get_primitive_type(surface),
				"vertices": arrays[Mesh.ARRAY_VERTEX], "indices": arrays[Mesh.ARRAY_INDEX],
				"normals": arrays[Mesh.ARRAY_NORMAL], "uv": arrays[Mesh.ARRAY_TEX_UV], "uv2": arrays[Mesh.ARRAY_TEX_UV2]})
			var material: Material = node.get_active_material(surface) if node is MeshInstance3D else mesh.surface_get_material(surface)
			if node is MultiMeshInstance3D and node.material_override != null: material = node.material_override
			result.materials[path + "/surface_%d" % surface] = _material_identity(material)
		result.materials[path + "/overlay"] = _material_identity(node.material_overlay)
		for transform in instances:
			var box: AABB = world * transform * mesh.get_aabb()
			result.bounds = result.bounds.merge(box) if result.has_bounds else box
			result.has_bounds = true
	result.nodes[path] = entry
	for child in node.get_children():
		_snapshot_node(child, root, world, result)

func _material_identity(material: Material) -> Dictionary:
	if material == null: return {}
	var result := {"class": material.get_class(), "name": material.resource_name, "local": material.resource_local_to_scene,
		"external": _external_identity(material), "properties": {}}
	if material is ShaderMaterial:
		result.shader = _external_identity(material.shader)
		result.shader_code_hash = material.shader.code.sha256_text() if material.shader != null else ""
		if material.shader != null:
			for uniform: Dictionary in material.shader.get_shader_uniform_list():
				var key: String = uniform.name
				var value: Variant = material.get_shader_parameter(key)
				result.properties[key] = _external_identity(value) if value is Resource else value
	else:
		for property: Dictionary in material.get_property_list():
			var key: String = property.name
			if int(property.usage) & PROPERTY_USAGE_STORAGE and not key.begins_with("resource_") and key != "script":
				var value: Variant = material.get(key)
				result.properties[key] = _external_identity(value) if value is Resource else value
	return result

func _external_identity(resource: Resource) -> Dictionary:
	if resource == null: return {}
	var path := resource.resource_path
	# 场景内 subresource 的随机 ID 不属于外链身份。
	if path.contains("::"): path = ""
	return {"class": resource.get_class(), "path": path, "sha256": _sha256_file(path)}

func _data_hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(_hash_value(value)))
	return context.finish().hex_encode()

func _hash_value(value: Variant) -> Variant:
	# TSCN 数值往返会有 float32 尾差；指纹按声明容差以下的固定精度编码，不哈希内存尾位。
	if value is float:
		return "%.4f" % (0.0 if absf(value) < 0.00005 else value)
	if value is Dictionary:
		var sorted: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys: sorted[key] = _hash_value(value[key])
		return sorted
	if value is Array or value is PackedVector3Array or value is PackedVector2Array or value is PackedFloat32Array or value is PackedInt32Array:
		var result: Array = []
		for item in value: result.append(_hash_value(item))
		return result
	if value is Vector3: return _hash_value([value.x, value.y, value.z])
	if value is Vector2: return _hash_value([value.x, value.y])
	if value is Color: return _hash_value([value.r, value.g, value.b, value.a])
	if value is Transform3D: return _hash_value([value.basis.x, value.basis.y, value.basis.z, value.origin])
	return value

func _snapshot_manifest(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate()
	result.erase("bounds")
	result.erase("nodes")
	result.erase("materials")
	var node_hashes: Dictionary = {}
	for path in snapshot.nodes:
		node_hashes[path] = _data_hash(snapshot.nodes[path])
	result.node_fingerprints = node_hashes
	result.materials = snapshot.materials
	return result

func _verify_static_snapshot(before: Dictionary, after: Dictionary) -> String:
	if int(before.get("unreadable_multimeshes", 0)) > 0 or int(after.get("unreadable_multimeshes", 0)) > 0:
		return "渲染后端无法读回 MultiMesh 实例数据，必须在真实后端验证"
	if not _geometry_is_non_empty(after):
		return "场景重载后几何为空"
	for key in ["scripts", "cameras", "lights", "collisions"]:
		if int(before.get(key, -1)) != 0 or int(after.get(key, -1)) != 0:
			return "静态场景含禁止节点：%s" % key
	for key in ["visual_meshes", "triangles", "nodes", "materials", "bounds_position", "bounds_size"]:
		if not _equivalent(before.get(key), after.get(key)):
			return "场景重载逐数据校验不一致：%s" % key
	return ""

func _equivalent(left: Variant, right: Variant) -> bool:
	if left is float or left is int:
		return (right is float or right is int) and is_finite(float(left)) and is_finite(float(right)) and absf(float(left) - float(right)) <= RELOAD_TOLERANCE
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not _equivalent(left[key], right[key]): return false
		return true
	if left is Array or left is PackedVector3Array or left is PackedVector2Array or left is PackedFloat32Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _equivalent(left[index], right[index]): return false
		return true
	if left is Vector3: return left.is_finite() and right.is_finite() and left.distance_to(right) <= RELOAD_TOLERANCE
	if left is Vector2: return left.is_finite() and right.is_finite() and left.distance_to(right) <= RELOAD_TOLERANCE
	if left is Color: return _equivalent([left.r, left.g, left.b, left.a], [right.r, right.g, right.b, right.a])
	if left is Transform3D: return _equivalent([left.basis.x, left.basis.y, left.basis.z, left.origin], [right.basis.x, right.basis.y, right.basis.z, right.origin])
	return left == right

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
	file.store_string(JSON.stringify(value, "\t", true, true))
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
	if not _owned_temps.has(path) or not path.get_file().begins_with(".tmp_") or _has_link_ancestor(ProjectSettings.globalize_path(path)):
		return
	var candidate := path.get_base_dir()
	if not _validate_root(candidate.get_base_dir()).is_empty():
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	# 只清理由本次 save 创建的三个平面文件；未知目录或链接一律保留。
	for name in ["plant.recipe.json", "plant.tscn", "plant.manifest.json"]:
		if dir.file_exists(name) and not dir.is_link(name):
			dir.remove(name)
	if dir.get_files().is_empty() and dir.get_directories().is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_owned_temps.erase(path)

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
