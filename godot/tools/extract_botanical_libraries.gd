extends SceneTree
## 从当前 Godot 运行资源导出两个 Blender 归档库所需的真实网格快照。
## 只读实例化必要资源；不加载 main.tscn，不写回工程内资产或玩家存档。

const HarvestVisualLib = preload("res://src/crops/harvest_visual.gd")
const BakeStoreLib = preload("res://src/world/bake_store.gd")
const LilyScene = preload("res://scenes/decorations/water/lily_leaf.tscn")
const FarmCellScene = preload("res://scenes/props/farm_cell.tscn")
const DeckScene = preload("res://scenes/props/cultivation_deck.tscn")

const STAGES := ["seed", "sprout", "leaf", "harvest"]
const STAGE_NODES := ["Stage0Seed", "Stage1Sprout", "Stage2Leaf", "Stage3Harvest"]
const TRANSFORM_LAYOUT := "Godot12float: [basis.x.x,basis.y.x,basis.z.x,origin.x,basis.x.y,basis.y.y,basis.z.y,origin.y,basis.x.z,basis.y.z,basis.z.z,origin.z]"

var checks := 0
var failures := 0
var entries: Array = []
var protected_hashes: Dictionary = {}
var ledger_rows: Dictionary = {}
var repo_root := ""
var work_root := ""
var output_path := ""


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[botanical-library-extract] %s%s" % ["FAIL " if not ok else "PASS ", label])


func _run() -> void:
	repo_root = OS.get_environment("SEA_SOURCE_ROOT")
	if repo_root.is_empty():
		repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	repo_root = repo_root.simplify_path()
	work_root = OS.get_environment("SEA_WORK_ROOT")
	if work_root.is_empty():
		work_root = repo_root.get_base_dir().path_join("sea-work")
	work_root = work_root.simplify_path()
	output_path = work_root.path_join("botanical_libraries/v001/native_meshes.json")

	_load_ledgers()
	var plan: Dictionary = _read_json(repo_root.path_join("art_source/vegetation/libraries/v001/component_plan.json"))
	check(not plan.is_empty(), "冻结组件计划可读取")
	if plan.is_empty():
		_finish()
		return

	for library in plan.get("libraries", []):
		for spec in library.get("components", []):
			var mode := str(spec.get("mode", ""))
			match mode:
				"native_binary":
					_extract_binary_plant(spec)
				"native_lily":
					await _extract_lily(spec)
				"native_flower":
					await _extract_flower(spec)
				"native_facility":
					await _extract_facility(spec)
				"blend_crop":
					# Blender 直接从冻结的 Blend 源提取三种旧作物四阶段；
					# 这里仅负责它们的六品种 HarvestVisual 手持副本。
					pass
				"blend_component":
					pass
				_:
					check(false, "未知组件模式 %s" % mode)

	await _extract_harvest_visuals(plan)
	_write_output(plan)
	_finish()


func _finish() -> void:
	print("[botanical-library-extract] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		check(false, "缺少输入 JSON: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		check(false, "JSON 不是对象: " + path)
		return {}
	return parsed


func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		check(false, "缺少账本: " + path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		return parsed
	if parsed is Dictionary and parsed.has("assets") and parsed.assets is Array:
		return parsed.assets
	check(false, "账本不是数组: " + path)
	return []


func _load_ledgers() -> void:
	for row in _read_json_array(repo_root.path_join("assets/registry/ledgers/scenes.json")):
		if row is Dictionary and row.has("asset_id"):
			ledger_rows[str(row.asset_id)] = row
	for row in _read_json_array(repo_root.path_join("assets/registry/ledgers/crops.json")):
		if row is Dictionary and row.has("asset_id"):
			ledger_rows[str(row.asset_id)] = row
	check(ledger_rows.size() > 0, "场景/作物账本已建立索引")


func _ledger(spec: Dictionary) -> Dictionary:
	var aid := str(spec.get("asset_id", ""))
	var row: Dictionary = ledger_rows.get(aid, {})
	check(not row.is_empty(), "%s 在主账本中存在" % aid)
	return row


func _path(rel: String) -> String:
	if rel.begins_with("res://") or rel.is_absolute_path():
		return rel
	return repo_root.path_join(rel).simplify_path()


func _rel(path: String) -> String:
	var normalized := path.replace("\\", "/")
	var root := repo_root.replace("\\", "/").trim_suffix("/") + "/"
	if normalized.begins_with(root):
		return normalized.trim_prefix(root)
	return normalized


func _source_paths(spec: Dictionary, row: Dictionary, extra: Array = []) -> Array:
	var result: Array = []
	for value in [spec.get("source", ""), spec.get("ledger_source", ""), row.get("source", ""), row.get("runtime_path", ""), row.get("prefab", "")]:
		var p := str(value)
		if not p.is_empty() and not result.has(p):
			result.append(p)
	for value in extra:
		var p := str(value)
		if not p.is_empty() and not result.has(p):
			result.append(p)
	return result


func _record_hashes(paths: Array) -> Dictionary:
	var result: Dictionary = {}
	for rel in paths:
		var p := _path(str(rel))
		if not FileAccess.file_exists(p):
			check(false, "输入文件存在: " + str(rel))
			continue
		var digest := _sha256(p)
		result[str(rel)] = digest
		protected_hashes[str(rel)] = digest
	return result


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	file.close()
	return context.finish().hex_encode()


func _identity_transform() -> Array:
	return _transform_array(Transform3D.IDENTITY)


func _transform_array(xf: Transform3D) -> Array:
	return [
		xf.basis.x.x, xf.basis.y.x, xf.basis.z.x, xf.origin.x,
		xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y,
		xf.basis.x.z, xf.basis.y.z, xf.basis.z.z, xf.origin.z,
	]


func _entry(spec: Dictionary, key: String, name: String, group: String, source_paths: Array, variant := "", kind := "") -> Dictionary:
	var row := _ledger(spec)
	var result := {
		"key": key,
		"asset_id": str(spec.get("asset_id", "")),
		"group": group,
		"name": name,
		"source_paths": source_paths,
		"input_hashes": _record_hashes(source_paths),
		"mesh_transform_layout": TRANSFORM_LAYOUT,
		"meshes": [],
		"triangles": 0,
		"bounds": {"min": [], "max": [], "size": []},
		"variant": variant,
	}
	if not kind.is_empty():
		result["kind"] = kind
	if row.has("source_sha256"):
		result["ledger_source_sha256"] = row.source_sha256
	if spec.has("source_sha256"):
		result["plan_source_sha256"] = spec.source_sha256
	return result


func _append_entry(result: Dictionary) -> void:
	var bounds := _bounds_for_entry(result.meshes)
	result["bounds"] = bounds
	var triangles := 0
	for mesh_data in result.meshes:
		triangles += int(mesh_data.get("triangles", 0))
	result["triangles"] = triangles
	check(result.meshes.size() > 0, "%s 至少有一个真实网格" % result.key)
	entries.append(result)


func _bounds_for_entry(meshes: Array) -> Dictionary:
	var has_point := false
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	for mesh_data in meshes:
		var verts: Array = mesh_data.get("vertices", [])
		var values: Array = mesh_data.get("transform", _identity_transform())
		var xf := _transform_from_array(values)
		for raw in verts:
			var point := xf * Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
			if not has_point:
				minimum = point
				maximum = point
				has_point = true
			else:
				minimum.x = minf(minimum.x, point.x)
				minimum.y = minf(minimum.y, point.y)
				minimum.z = minf(minimum.z, point.z)
				maximum.x = maxf(maximum.x, point.x)
				maximum.y = maxf(maximum.y, point.y)
				maximum.z = maxf(maximum.z, point.z)
	if not has_point:
		return {"min": [], "max": [], "size": []}
	var size := maximum - minimum
	return {"min": [minimum.x, minimum.y, minimum.z], "max": [maximum.x, maximum.y, maximum.z], "size": [size.x, size.y, size.z]}


func _transform_from_array(values: Array) -> Transform3D:
	if values.size() == 16:
		return Transform3D(
			Basis(Vector3(float(values[0]), float(values[4]), float(values[8])), Vector3(float(values[1]), float(values[5]), float(values[9])), Vector3(float(values[2]), float(values[6]), float(values[10]))),
			Vector3(float(values[3]), float(values[7]), float(values[11])))
	if values.size() != 12:
		return Transform3D.IDENTITY
	return Transform3D(
		Basis(Vector3(float(values[0]), float(values[4]), float(values[8])), Vector3(float(values[1]), float(values[5]), float(values[9])), Vector3(float(values[2]), float(values[6]), float(values[10]))),
		Vector3(float(values[3]), float(values[7]), float(values[11])))


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func _vec3_array(values: PackedVector3Array) -> Array:
	var result: Array = []
	for value in values:
		result.append([value.x, value.y, value.z])
	return result


func _vec2_array(values: PackedVector2Array) -> Array:
	var result: Array = []
	for value in values:
		result.append([value.x, value.y])
	return result


func _color_array(values: PackedColorArray) -> Array:
	var result: Array = []
	for value in values:
		result.append([value.r, value.g, value.b, value.a])
	return result


func _material_for(node: MeshInstance3D, mesh: Mesh, surface: int) -> Material:
	# material_override replaces every surface and has priority over per-surface materials.
	if node.material_override != null:
		return node.material_override
	var override := node.get_surface_override_material(surface)
	if override != null:
		return override
	return mesh.surface_get_material(surface)


func _color_product(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)


func _material_data(material: Material) -> Dictionary:
	var result := {
		"base_color": [1.0, 1.0, 1.0, 1.0],
		"roughness": 0.96,
		"metallic": 0.0,
		"texture": "",
		"category": "unknown",
	}
	if material == null:
		return result
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		result["base_color"] = [standard.albedo_color.r, standard.albedo_color.g, standard.albedo_color.b, standard.albedo_color.a]
		result["roughness"] = standard.roughness
		result["metallic"] = standard.metallic
		if standard.albedo_texture != null:
			result["texture"] = _rel(standard.albedo_texture.resource_path)
		result["category"] = "StandardMaterial3D"
		return result
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		var shader_path := ""
		if shader_material.shader != null:
			shader_path = _rel(shader_material.shader.resource_path)
		result["category"] = "ShaderMaterial"
		result["shader"] = shader_path
		var tint: Variant = shader_material.get_shader_parameter("albedo_tint")
		if tint is Color:
			result["base_color"] = [tint.r, tint.g, tint.b, tint.a]
		var texture: Variant = shader_material.get_shader_parameter("albedo_tex")
		if texture is Texture2D and not texture.resource_path.is_empty():
			result["texture"] = _rel(texture.resource_path)
		result["shader_parameters"] = {
			"use_texture": shader_material.get_shader_parameter("use_texture"),
			"depth_tint": shader_material.get_shader_parameter("depth_tint"),
			"double_side": shader_material.get_shader_parameter("double_side"),
			"color_channel": "vertex_color_and_multimesh_instance_color",
		}
		return result
	result["category"] = material.get_class()
	return result


func _surface_data(node: MeshInstance3D, surface: int, transform: Transform3D, color_multiplier := Color.WHITE) -> Dictionary:
	var mesh: Mesh = node.mesh
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
	if vertices.is_empty():
		return {}
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	if not color_multiplier.is_equal_approx(Color.WHITE):
		var effective := PackedColorArray()
		effective.resize(vertices.size())
		for i in vertices.size():
			effective[i] = _color_product(colors[i], color_multiplier) if i < colors.size() else color_multiplier
		colors = effective
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size():
			indices[i] = i
	var tri_count := int(indices.size() / 3)
	return {
		"name": "%s_surface_%02d" % [node.name, surface],
		"transform": _transform_array(transform),
		"vertices": _vec3_array(vertices),
		"indices": Array(indices),
		"normals": _vec3_array(normals),
		"uv": _vec2_array(uv),
		"colors": _color_array(colors),
		"material": _material_data(_material_for(node, mesh, surface)),
		"surface": surface,
		"triangles": tri_count,
	}


func _extract_node_meshes(root: Node3D, result: Dictionary, skip_names: Array = [], color_multiplier := Color.WHITE) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mesh_node := current as MeshInstance3D
			if not skip_names.has(str(mesh_node.name)) and mesh_node.mesh != null:
				var xf := _relative_transform(mesh_node, root)
				for surface in mesh_node.mesh.get_surface_count():
					var data := _surface_data(mesh_node, surface, xf, color_multiplier)
					if not data.is_empty():
						result.meshes.append(data)
		for child in current.get_children():
			stack.append(child)


func _extract_multimesh(node: MultiMeshInstance3D, root: Node3D, result: Dictionary) -> void:
	if node.multimesh == null or node.multimesh.mesh == null:
		return
	var instance_transform := node.multimesh.get_instance_transform(0) if node.multimesh.instance_count > 0 else Transform3D.IDENTITY
	var instance_color := node.multimesh.get_instance_color(0) if node.multimesh.instance_count > 0 and node.multimesh.use_colors else Color.WHITE
	var xf := _relative_transform(node, root) * instance_transform
	for surface in node.multimesh.mesh.get_surface_count():
		var arrays: Array = node.multimesh.mesh.surface_get_arrays(surface)
		var temporary := MeshInstance3D.new()
		temporary.name = node.name
		temporary.mesh = node.multimesh.mesh
		temporary.material_override = node.material_override
		var data := _surface_data(temporary, surface, xf, instance_color)
		temporary.free()
		if not data.is_empty():
			data["color_source"] = "vertex_color multiplied by MultiMesh instance color"
			result.meshes.append(data)


func _extract_lily(spec: Dictionary) -> void:
	var row := _ledger(spec)
	var data_path := _path("godot/assets/data/lily_components.json")
	var components: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path)) if FileAccess.file_exists(data_path) else null
	check(components is Array and not components.is_empty(), "lily_components.json 有真实荷叶实例")
	if not components is Array or components.is_empty():
		return
	var selected: Dictionary = components[0]
	var root := Node3D.new()
	root.name = "BotanicalLilyExtraction"
	var leaf := LilyScene.instantiate()
	leaf.geometry_id = int(selected.get("geometry_id", 679))
	var color: Array = selected.get("color", [1, 1, 1, 1])
	leaf.leaf_color = Color(float(color[0]), float(color[1]), float(color[2]), float(color[3]))
	root.add_child(leaf)
	self.root.add_child(root)
	await process_frame
	var result := _entry(spec, "lily_leaf_geometry_%d" % int(selected.get("geometry_id", 679)), "真实荷叶·geometry_%d" % int(selected.get("geometry_id", 679)), str(spec.get("group", "04_水生与水下植物")), _source_paths(spec, row, ["godot/assets/data/lily_components.json", "godot/src/ambient/lily_leaf.gd", "godot/src/world/bake_store.gd", "godot/scenes/decorations/water/lily_leaf.tscn"]))
	result["native_source"] = {"geometry_id": int(selected.get("geometry_id", 679)), "color": color, "instance_transform": selected.get("transform", [])}
	_extract_node_meshes_from_tree(root, result)
	_append_entry(result)
	root.queue_free()


func _extract_node_meshes_from_tree(root: Node3D, result: Dictionary) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MultiMeshInstance3D:
			_extract_multimesh(current as MultiMeshInstance3D, root, result)
		elif current is MeshInstance3D:
			var mesh_node := current as MeshInstance3D
			if mesh_node.mesh != null:
				var xf := _relative_transform(mesh_node, root)
				for surface in mesh_node.mesh.get_surface_count():
					var data := _surface_data(mesh_node, surface, xf)
					if not data.is_empty():
						result.meshes.append(data)
		for child in current.get_children():
			stack.append(child)


func _extract_binary_plant(spec: Dictionary) -> void:
	var row := _ledger(spec)
	var source := _path(str(spec.get("source", "")))
	var file := FileAccess.open(source, FileAccess.READ)
	check(file != null, "%s mesh.bin 可读取" % spec.asset_id)
	if file == null:
		return
	var vertex_count := file.get_32()
	var index_count := file.get_32()
	var vertices: Array = []
	for i in vertex_count:
		vertices.append([file.get_float(), file.get_float(), file.get_float()])
	var normals: Array = []
	for i in vertex_count:
		normals.append([file.get_float(), file.get_float(), file.get_float()])
	var colors: Array = []
	for i in vertex_count:
		colors.append([file.get_float(), file.get_float(), file.get_float(), 1.0])
	var indices: Array = []
	for i in index_count:
		indices.append(file.get_32())
	file.close()
	check(vertex_count > 0 and index_count > 0 and index_count % 3 == 0, "%s 网格计数有效" % spec.asset_id)
	var paths := _source_paths(spec, row, [str(spec.get("source", "")), "godot/src/ambient/mesh_io.gd", "godot/src/ambient/plant.gd", "godot/src/world/bake_store.gd"])
	var result := _entry(spec, str(spec.get("asset_id", "")).to_lower(), str(spec.get("name", spec.asset_id)), str(spec.get("group", "05_原版升级植物")), paths)
	result["mesh_format"] = "mesh.bin: [vcount u32][icount u32][position f32*3v][normal f32*3v][color RGB f32*3v][index u32*i]"
	result.meshes.append({
		"name": str(spec.get("asset_id", "")) + "_surface_00",
		"transform": _identity_transform(),
		"vertices": vertices,
		"indices": indices,
		"normals": normals,
		"uv": [],
		"colors": colors,
		"material": {
			"base_color": [1.0, 1.0, 1.0, 1.0],
			"roughness": 0.96,
			"metallic": 0.0,
			"texture": "",
			"category": "ShaderMaterial:toon vertex-color channel",
			"shader": "godot/shaders/toon.gdshader",
			"shader_parameters": {"use_texture": false, "depth_tint": true, "double_side": true, "color_channel": "vertex_color"},
		},
		"triangles": int(indices.size() / 3),
	})
	_append_entry(result)


func _instantiate_scene(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		check(false, "场景资源存在: " + path)
		return null
	var packed := load(path)
	if packed == null or not packed is PackedScene:
		check(false, "场景资源可实例化: " + path)
		return null
	var node: Node = packed.instantiate()
	check(node is Node3D, "场景根是 Node3D: " + path)
	return node as Node3D


func _extract_flower(spec: Dictionary) -> void:
	var row := _ledger(spec)
	var crop_id := str(spec.get("asset_id", "")).to_lower().replace("sea-crop-", "").replace("-", "_")
	var scene_path := "res://scenes/crops/%s.tscn" % crop_id
	var source := _instantiate_scene(scene_path)
	if source == null:
		return
	if source.has_method("ensure_built"):
		source.ensure_built()
	var holder := Node3D.new()
	holder.name = "FlowerExtractionRoot"
	holder.add_child(source)
	self.root.add_child(holder)
	await process_frame
	var paths := _source_paths(spec, row, ["godot/src/crops/flower_view.gd", "godot/scenes/crops/%s.tscn" % crop_id, "godot/assets/data/crops.json"])
	for index in 4:
		var stage := source.get_node_or_null(STAGE_NODES[index]) as Node3D
		check(stage != null, "%s stage_%d 节点存在" % [crop_id, index])
		if stage == null:
			continue
		var key := "%s_stage_%d_%s" % [crop_id, index, STAGES[index]]
		var result := _entry(spec, key, "%s·stage_%d_%s" % [str(spec.get("name", crop_id)), index, STAGES[index]], str(spec.get("group", "01_六品种四阶段")), paths, "stage_%d_%s" % [index, STAGES[index]])
		_extract_node_meshes(stage, result, ["ContactShadow", "HeatPreview", "Blockers"])
		_append_entry(result)
	holder.queue_free()


func _extract_facility(spec: Dictionary) -> void:
	var row := _ledger(spec)
	var aid := str(spec.get("asset_id", ""))
	var result := _entry(spec, "farm_soil_cell" if aid == "SEA-FARM-SOIL-CELL" else "cultivation_deck", str(spec.get("name", aid)), str(spec.get("group", "02_种植设施")), _source_paths(spec, row, ["godot/scenes/props/farm_cell.tscn" if aid == "SEA-FARM-SOIL-CELL" else "godot/scenes/props/cultivation_deck.tscn"]))
	var scene: Node3D = FarmCellScene.instantiate() if aid == "SEA-FARM-SOIL-CELL" else DeckScene.instantiate()
	check(scene != null, "%s 场景实例化" % aid)
	if scene == null:
		return
	self.root.add_child(scene)
	await process_frame
	var skip := ["ContactShadow", "HeatPreview", "Blockers", "Collision", "InteractionHelper"]
	_extract_node_meshes(scene, result, skip)
	if aid == "SEA-FARM-SOIL-CELL":
		result["exclusions"] = ["Crop", "default preview crop", "ContactShadow", "HeatPreview", "interaction helpers", "collision"]
	else:
		result["plank_count"] = 13
		result["exclusions"] = ["interaction helpers", "collision"]
	_append_entry(result)
	scene.queue_free()


func _harvest_spec(asset_id: String, plan: Dictionary) -> Dictionary:
	for library in plan.get("libraries", []):
		for spec in library.get("components", []):
			if str(spec.get("asset_id", "")) == asset_id:
				return spec
	return {"asset_id": asset_id, "name": asset_id, "group": "harvest_visuals", "source": "godot/src/crops/harvest_visual.gd", "mode": "native_harvest"}


func _extract_harvest_visuals(plan: Dictionary) -> void:
	var crop_ids := ["lettuce", "tomato", "pumpkin", "flower_blue", "flower_sun", "flower_coral"]
	for crop_id in crop_ids:
		var asset_id: String = "SEA-CROP-" + crop_id.to_upper().replace("_", "-")
		var spec: Dictionary = _harvest_spec(asset_id, plan)
		if not ledger_rows.has(asset_id):
			# 账本中的花卉/旧作物 ID 是主记录；失败必须阻断而不是猜 AssetID。
			check(false, "手持物主记录存在: " + asset_id)
			continue
		var row := _ledger(spec)
		var visual := HarvestVisualLib.create(crop_id)
		check(visual != null, "%s HarvestVisual.create" % crop_id)
		if visual == null:
			continue
		var holder := Node3D.new()
		holder.name = "HarvestExtractionRoot"
		holder.add_child(visual)
		self.root.add_child(holder)
		await process_frame
		var paths := _source_paths(spec, row, ["godot/src/crops/harvest_visual.gd", "godot/assets/data/crops.json"])
		var prefab := str(row.get("prefab", ""))
		if not prefab.is_empty() and not paths.has(prefab):
			paths.append(prefab)
		var result := _entry(spec, "%s_harvest_visual" % crop_id, "%s·HarvestVisual 手持物" % str(row.get("name", crop_id)), "harvest_visuals", paths, "harvest_visual", "harvest_visual")
		result["kind"] = "harvest_visual"
		result["selection_policy"] = "HarvestVisual.create(%s); visual-only; no soil, seed, collision, or planted node" % crop_id
		_extract_node_meshes(visual, result, ["ContactShadow", "HeatPreview", "Blockers"])
		_append_entry(result)
		holder.queue_free()


func _write_output(plan: Dictionary) -> void:
	var directory := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var document := {
		"schema_version": 1,
		"coordinate_system": "Godot metres; transform is Godot12float column-basis+origin; Blender builder applies Godot(x,y,z)->Blender(x,-z,y)",
		"transform_layout": TRANSFORM_LAYOUT,
		"entries": entries,
		"protected_inputs": protected_hashes,
		"summary": {
			"entry_count": entries.size(),
			"mesh_count": entries.reduce(func(total, item): return total + item.meshes.size(), 0),
			"triangle_count": entries.reduce(func(total, item): return total + int(item.triangles), 0),
			"source_plan": "art_source/vegetation/libraries/v001/component_plan.json",
			"scope": "visual geometry only; no collision or interaction helper geometry",
		},
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	check(file != null, "输出文件可写: " + output_path)
	if file != null:
		file.store_string(JSON.stringify(document, "\t") + "\n")
		file.close()
		check(FileAccess.file_exists(output_path), "native_meshes.json 已落盘")
		print("[botanical-library-extract] output=", output_path, " entries=", entries.size())
