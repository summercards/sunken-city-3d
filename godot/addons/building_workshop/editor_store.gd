@tool
extends "res://src/workshop/store.gd"

const EDITOR_ROOT := "res://scenes/workshop_buildings"
const EDITOR_OUTPUT_ROOT := "res://outputs/workshop_editor"
const AttachmentData = preload("res://addons/building_workshop/attachment_work_data.gd")
const WORK_FILES := ["building.attachments.json", "building.attachments.tscn", "building.work.tscn"]
const SurfacePaintData = preload("res://addons/building_workshop/surface_paint_data.gd")
const SurfacePaintOutput = preload("res://addons/building_workshop/surface_paint_output.gd")
const SURFACE_FILES := ["building.surface_paint.json", "building.surface_paint.tscn"]
var surface_paint_textures: Dictionary = {}
var _surface_export := false
var _surface_snapshot: Dictionary = {}
var _surface_host: Node3D
var _work_export := false
var _work_snapshot: Dictionary = {}
var _work_failure := ""

func export_surface_paint_work_revision(recipe: Dictionary, catalog: Dictionary, attachments_snapshot: Dictionary, surface_paint_snapshot: Dictionary, base_dir: String = EDITOR_ROOT) -> Dictionary:
	if _work_export or _surface_export: return {"ok": false, "reason": "作品保存正在进行"}
	var reason := SurfacePaintData.validate(surface_paint_snapshot)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	_surface_export = true
	_surface_snapshot = surface_paint_snapshot.duplicate(true)
	var result := export_work_revision(recipe, catalog, attachments_snapshot, base_dir)
	if result.get("ok", false):
		result["surface_paint_snapshot"] = _surface_snapshot.duplicate(true)
		result["surface_paint_path"] = str(result.directory).path_join(SURFACE_FILES[0])
		result["surface_paint_scene_path"] = str(result.directory).path_join(SURFACE_FILES[1])
	_surface_export = false
	_surface_snapshot = {}
	_surface_host = null
	return result

func export_work_revision(recipe: Dictionary, catalog: Dictionary, snapshot: Dictionary, base_dir: String = EDITOR_ROOT) -> Dictionary:
	if _work_export: return {"ok": false, "reason": "作品保存正在进行"}
	var reason := AttachmentData.validate(snapshot)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	_work_snapshot = snapshot.duplicate(true)
	_work_failure = ""
	_work_export = true
	# 父类唯一提交点仍是临时目录rename；旁车在manifest写入前准备与验证。
	var result := export_revision(recipe, catalog, base_dir)
	_work_export = false
	if result.get("ok", false):
		result["attachments_snapshot"] = _work_snapshot.duplicate(true)
		result["attachments_path"] = str(result.directory).path_join(WORK_FILES[0])
		result["work_scene_path"] = str(result.directory).path_join(WORK_FILES[2])
	elif not _work_failure.is_empty():
		result.reason = _work_failure
	_work_snapshot = {}
	_work_failure = ""
	return result

func export_revision(recipe: Dictionary, catalog: Dictionary = {}, base_dir: String = EDITOR_ROOT) -> Dictionary:
	var reason := _validate_base_dir(base_dir)
	if not reason.is_empty():
		var result := _fail_result()
		result.reason = reason
		return result
	return super.export_revision(recipe, catalog, _editor_resource_path(base_dir))

func load_recipe(path: String) -> Dictionary:
	var normalized := _editor_resource_path(path)
	# 仍由父类强制读取同目录 catalog_snapshot.json，不回退到全局目录。
	var result := super.load_recipe(normalized)
	if not result.get("ok", false): return result
	var directory := normalized.get_base_dir()
	var manifest_path := directory.path_join("candidate_manifest.json")
	var manifest_exists := FileAccess.file_exists(manifest_path)
	var manifest_value: Variant = _read_json(manifest_path)
	if manifest_exists and not manifest_value is Dictionary:
		return {"ok": false, "reason": "作品manifest JSON损坏或超过容量，拒绝降级为空作品"}
	var manifest: Dictionary = manifest_value if manifest_value is Dictionary else {}
	if manifest_exists:
		var header_reason := _manifest_header_reason(manifest)
		if not header_reason.is_empty(): return {"ok": false, "reason": header_reason}
	var surface_declared := _surface_is_declared(manifest)
	if not surface_declared:
		for name: String in SURFACE_FILES:
			if FileAccess.file_exists(directory.path_join(name)):
				return {"ok": false, "reason": "存在未声明的表面植被旁车，拒绝降级为空作品"}
	result["surface_paint_snapshot"] = SurfacePaintData.empty_snapshot()
	result["surface_paint_path"] = ""
	result["surface_paint_scene_path"] = ""
	var declared: bool = surface_declared or manifest.has("attachments_snapshot") or manifest.has("attachments_scene") or manifest.has("work_scene") or manifest.has("attachments_fingerprint")
	for file: String in WORK_FILES:
		if manifest.get("source_hashes", {}) is Dictionary and manifest.get("source_hashes", {}).has(file): declared = true
		if manifest.get("file_list", []) is Array and manifest.get("file_list", []).has(file): declared = true
	var has_sidecar := false
	for file: String in WORK_FILES:
		if FileAccess.file_exists(directory.path_join(file)): has_sidecar = true
	if not declared:
		if has_sidecar:
			return {"ok": false, "reason": "存在未声明的作品外挂旁车，拒绝降级为空作品"}
		result["attachments_snapshot"] = AttachmentData.empty_snapshot()
		return result
	var reason := _verify_work_files(directory, manifest)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var snapshot: Dictionary = _read_json(directory.path_join(WORK_FILES[0]))
	var built := AttachmentData.build(snapshot)
	if not built.ok: return {"ok": false, "reason": built.reason}
	built.root.free()
	result["attachments_snapshot"] = snapshot.duplicate(true)
	result["attachments_path"] = directory.path_join(WORK_FILES[0])
	result["work_scene_path"] = directory.path_join(WORK_FILES[2])
	if surface_declared:
		result["surface_paint_snapshot"] = _read_json(directory.path_join(SURFACE_FILES[0])).duplicate(true)
		result["surface_paint_path"] = directory.path_join(SURFACE_FILES[0])
		result["surface_paint_scene_path"] = directory.path_join(SURFACE_FILES[1])
	return result

func list_documents(base_dir: String = EDITOR_ROOT) -> Array:
	if not _validate_base_dir(base_dir).is_empty():
		return []
	return super.list_documents(_editor_resource_path(base_dir))

func _validate_base_dir(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if not normalized.begins_with("res://") or _editor_resource_path(normalized).is_empty():
		return "编辑器候选根只允许 res://scenes/workshop_buildings 或 res://outputs/workshop_editor 子树"
	return ""

func _is_safe_recipe_path(path: String) -> bool:
	var normalized := _editor_resource_path(path)
	return not normalized.is_empty() and normalized.to_lower().ends_with(".recipe.json")

func _editor_resource_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.is_empty() or normalized.contains("..") or normalized.strip_edges() != normalized:
		return ""
	normalized = normalized.simplify_path().trim_suffix("/")
	for root in [EDITOR_ROOT, EDITOR_OUTPUT_ROOT]:
		var absolute := ProjectSettings.globalize_path(root).replace("\\", "/").simplify_path().trim_suffix("/")
		for prefix in [root, absolute]:
			var folded := normalized.to_lower()
			var folded_prefix := str(prefix).to_lower()
			if folded == folded_prefix:
				return root
			if folded.begins_with(folded_prefix + "/"):
				var suffix := normalized.substr(str(prefix).length())
				if suffix.contains(":"):
					return ""
				return str(root) + suffix
	return ""

func _catalog_is_valid(value: Dictionary) -> bool:
	var adapter = preload("res://addons/building_workshop/catalog_adapter.gd")
	var components: Variant = value.get("components", {})
	if not components is Dictionary:
		return false
	for component_id in components:
		var component: Variant = components[component_id]
		if component is Dictionary and str(component.get("kind", "")) == "prefab":
			var inspected: Dictionary = adapter.inspect_static_prefab(str(component.get("prefab", "")))
			if not bool(inspected.get("ok", false)):
				return false
	return super._catalog_is_valid(value)

func _make_manifest(recipe: Dictionary, catalog: Dictionary, build: Dictionary, revision: int, tree_snapshot: Dictionary, source_hashes: Dictionary) -> Dictionary:
	var manifest := super._make_manifest(recipe, catalog, build, revision, tree_snapshot, source_hashes)
	manifest["authoring_context"] = "editor"
	manifest["noMain"] = true
	manifest["candidate_ledger"] = "ledger.json"
	manifest["formal_registry_written"] = false
	var sources: Dictionary = {}
	for path in ["res://src/workshop/recipe.gd", "res://src/workshop/catalog.gd", "res://src/workshop/generator.gd", "res://src/workshop/mesh_builder.gd", "res://src/workshop/store.gd", "res://src/workshop/shell_geometry.gd", "res://src/workshop/shell_damage_geometry.gd", "res://src/workshop/shell_generator.gd", "res://src/workshop/shell_union_geometry.gd", "res://src/workshop/architecture_config.gd", "res://src/workshop/shell_window_geometry.gd", "res://src/workshop/roof_edge_geometry.gd", "res://addons/building_workshop/editor_store.gd", "res://addons/building_workshop/catalog_adapter.gd", "res://data/workshop/catalog_v1.json", "res://data/workshop/standards_v1.json", "res://data/workshop/palette_cells_v1.json"]:
		sources[path] = _sha256_file(path)
	var components: Dictionary = catalog.get("components", {})
	for component_id in components:
		var component: Dictionary = components[component_id]
		if str(component.get("kind", "")) == "prefab":
			var path := str(component.get("prefab", ""))
			if path.begins_with("res://"):
				sources[path] = _sha256_file(path)
	var material_paths: Dictionary = {}
	var builder = preload("res://src/workshop/mesh_builder.gd")
	for role: String in builder.shared_materials():
		var material: ShaderMaterial = builder.shared_materials()[role]
		material_paths[role] = material.resource_path
		sources[material.resource_path] = _sha256_file(material.resource_path)
		sources[material.shader.resource_path] = _sha256_file(material.shader.resource_path)
	sources[builder.TEXTURE_PATH] = _sha256_file(builder.TEXTURE_PATH)
	manifest["shading_contract"] = {"palette": builder.TEXTURE_PATH, "size": [512, 512], "uv": "PaletteUV", "shared_materials": material_paths, "embedded_material_copies": false}
	if _work_export:
		manifest["attachments_snapshot"] = WORK_FILES[0]
		manifest["attachments_scene"] = WORK_FILES[1]
		manifest["work_scene"] = WORK_FILES[2]
		manifest["attachments_fingerprint"] = AttachmentData.fingerprint(_work_snapshot)
		for file: String in WORK_FILES: manifest.file_list.append(file)
		for path: String in ["res://addons/building_workshop/attachment_work_data.gd", "res://src/building_attachments/recipe.gd", "res://src/building_attachments/catalog.gd", "res://src/building_attachments/generator.gd", "res://src/building_attachments/geometry.gd", "res://src/building_attachments/signage.gd", "res://src/building_attachments/hvac.gd", "res://src/building_attachments/water.gd", "res://src/building_attachments/shelter.gd", "res://src/building_attachments/forms.gd", "res://src/building_attachments/glyphs.gd", "res://data/building_attachments/catalog_v1.json"]:
			sources[path] = _sha256_file(path)
	if _surface_export:
		_surface_host = build.get("root") as Node3D
		manifest["surface_paint_snapshot"] = SURFACE_FILES[0]
		manifest["surface_paint_scene"] = SURFACE_FILES[1]
		manifest["surface_paint_fingerprint"] = SurfacePaintData.fingerprint(_surface_snapshot)
		for file: String in SURFACE_FILES: manifest.file_list.append(file)
		for path: String in ["res://addons/building_workshop/surface_paint_data.gd", "res://addons/building_workshop/surface_paint_output.gd", "res://addons/building_workshop/surface_paint_surface.gd", "res://src/ambient/vegetation/library.gd"]:
			sources[path] = _sha256_file(path)
		var texture_sources: Dictionary = {}
		for key: String in surface_paint_textures:
			var texture: Variant = surface_paint_textures[key]
			if texture is Texture2D and texture.resource_path.begins_with("res://"):
				texture_sources[key] = texture.resource_path
				sources[texture.resource_path] = _sha256_file(texture.resource_path)
		var vegetation = preload("res://src/ambient/vegetation/library.gd")
		sources[vegetation.CATALOG] = _sha256_file(vegetation.CATALOG)
		var grass: Dictionary = vegetation.catalog().get("grass_soft", {})
		texture_sources["grass_soft"] = grass.duplicate(true)
		for key: String in ["model", "material"]:
			var path := str(grass.get(key, ""))
			if path.begins_with("res://"): sources[path] = _sha256_file(path)
		var grass_material := vegetation.material("grass_soft") as ShaderMaterial if not grass.is_empty() else null
		if grass_material != null:
			var atlas: Variant = grass_material.get_shader_parameter("botanical_atlas")
			if atlas is Texture2D and atlas.resource_path.begins_with("res://"): sources[atlas.resource_path] = _sha256_file(atlas.resource_path)
		for path: String in ["res://shaders/vegetation/soft_cards.gdshader", "res://addons/building_workshop/plugin.gd", "res://addons/building_workshop/editor_screen.gd"]:
			sources[path] = _sha256_file(path)
		manifest["surface_paint_sources"] = texture_sources
	manifest["authoring_source_hashes"] = sources
	return manifest

func _read_json(path: String):
	var normalized := _editor_resource_path(path)
	if normalized.is_empty() or not FileAccess.file_exists(normalized): return null
	var file := FileAccess.open(normalized, FileAccess.READ)
	if file == null: return null
	if file.get_length() > AttachmentData.MAX_JSON_BYTES:
		file.close()
		return null
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK and error != ERR_FILE_EOF: return null
	var parser := JSON.new()
	if parser.parse(text) != OK: return null
	return parser.data

func _write_json(path: String, value: Dictionary) -> bool:
	if _editor_resource_path(path).is_empty(): return false
	if JSON.stringify(value, "\t").to_utf8_buffer().size() > AttachmentData.MAX_JSON_BYTES:
		if _work_export: _work_failure = "作品JSON超过8MiB容量：" + path.get_file()
		return false
	if _work_export and path.get_file() == "candidate_manifest.json":
		_work_failure = _prepare_work_files(path.get_base_dir(), value)
		if not _work_failure.is_empty(): return false
		if not super._write_json(path, value): return false
		var stored: Variant = _read_json(path)
		if not stored is Dictionary:
			_work_failure = "作品manifest重读失败"
			return false
		_work_failure = _verify_work_files(path.get_base_dir(), stored)
		return _work_failure.is_empty()
	var written := super._write_json(path, value)
	if _work_export and written:
		var read_back: Variant = _read_json(path)
		written = read_back is Dictionary and _json_values_equal(value, read_back)
		if not written: _work_failure = "作品JSON重读校验失败：" + path.get_file()
	return written

func _json_values_equal(expected: Variant, actual: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or expected.size() != actual.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not _json_values_equal(expected[key], actual[key]): return false
		return true
	if expected is Array:
		if not actual is Array or expected.size() != actual.size(): return false
		for index in expected.size():
			if not _json_values_equal(expected[index], actual[index]): return false
		return true
	if expected is int or expected is float:
		if not actual is int and not actual is float: return false
		if not is_finite(float(expected)) or not is_finite(float(actual)): return false
		# 与Data指纹共用1e-9十进制定点；不改输入，也不放宽为相对1e-5。
		return AttachmentData._canonical(expected) == AttachmentData._canonical(actual)
	if typeof(expected) != typeof(actual): return false
	return expected == actual

func _prepare_work_files(directory: String, manifest: Dictionary) -> String:
	var header_reason := _manifest_header_reason(manifest)
	if not header_reason.is_empty(): return header_reason
	var snapshot_path := directory.path_join(WORK_FILES[0])
	if not _write_json(snapshot_path, _work_snapshot): return "外挂快照写入失败"
	var read_back: Variant = _read_json(snapshot_path)
	if not read_back is Dictionary or AttachmentData.fingerprint(read_back) != AttachmentData.fingerprint(_work_snapshot):
		return "外挂快照重读不一致"
	var built := AttachmentData.build(read_back)
	if not built.ok: return str(built.reason)
	var root: Node3D = built.root
	var before := _tree_snapshot(root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, directory.path_join(WORK_FILES[1]), ResourceSaver.FLAG_RELATIVE_PATHS)
	root.free()
	if error != OK: return "外挂静态场景打包或写入失败"
	# 只重载刚由可信Generator打包的临时资源，不重载外部已保存旁车。
	var reloaded := ResourceLoader.load(directory.path_join(WORK_FILES[1]), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if reloaded == null: return "外挂静态场景重载失败"
	var instance := reloaded.instantiate() as Node3D
	if instance == null: return "外挂静态根不可读取"
	instance.scene_file_path = ""
	var captured := AttachmentData.capture(instance)
	var after := _tree_snapshot(instance)
	var geometry_reason := _compare_tree_snapshots(before, after)
	instance.free()
	if not geometry_reason.is_empty(): return geometry_reason
	if int(after.scripts) != 0 or int(after.unowned_nodes) != 0: return "外挂静态场景脚本或owner校验失败"
	if not _static_snapshot_matches(captured, _work_snapshot): return "外挂静态重载快照不一致"
	if _surface_export:
		var surface_reason := _prepare_surface_files(directory)
		if not surface_reason.is_empty(): return surface_reason
	# 固定原生包装使用最终目录内相对外链，不把.tmp绝对路径写入资源。
	var wrapper := _work_wrapper_text(_surface_export)
	var wrapper_path := directory.path_join(WORK_FILES[2])
	var file := FileAccess.open(wrapper_path, FileAccess.WRITE)
	if file == null: return "完整作品包装不可写"
	file.store_string(wrapper)
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(wrapper_path) != wrapper: return "完整作品包装写入校验失败"
	var work := ResourceLoader.load(wrapper_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if work == null: return "完整作品包装重载失败"
	var work_root := work.instantiate() as Node3D
	if work_root == null: return "完整作品根不可读取"
	var valid := work_root.name == &"Work" and work_root.get_child_count() == (3 if _surface_export else 2) and work_root.get_node_or_null("Asset") is Node3D and work_root.get_node_or_null("Attachments") is Node3D
	if _surface_export: valid = valid and work_root.get_node_or_null("SurfacePaint") is Node3D
	work_root.free()
	if not valid: return "完整作品层级校验失败"
	for name: String in WORK_FILES + (SURFACE_FILES if _surface_export else []): manifest.source_hashes[name] = _sha256_file(directory.path_join(name))
	return _verify_work_files(directory, manifest)

func _prepare_surface_files(directory: String) -> String:
	var path := directory.path_join(SURFACE_FILES[0])
	if not _write_json(path, _surface_snapshot): return "表面植被快照写入失败"
	var read_back: Variant = _read_json(path)
	if not read_back is Dictionary or SurfacePaintData.fingerprint(read_back) != SurfacePaintData.fingerprint(_surface_snapshot):
		return "表面植被快照重读不一致"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not is_instance_valid(_surface_host) or _surface_host.get_parent() != null:
		return "表面植被导出缺少可信生成宿主或场景树"
	# 父类仍持有纯建筑；只临时入树满足真实面缓存，不挂任何派生层到宿主。
	var staging := Node3D.new()
	tree.root.add_child(staging)
	staging.add_child(_surface_host)
	var built := SurfacePaintOutput.build_from_snapshot(read_back, _surface_host, surface_paint_textures)
	staging.remove_child(_surface_host)
	staging.free()
	if not built.ok: return str(built.reason)
	var root: Node3D = built.root
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, directory.path_join(SURFACE_FILES[1]), ResourceSaver.FLAG_RELATIVE_PATHS)
	if error != OK:
		root.free()
		return "表面植被静态场景打包或写入失败"
	# 只实例化本次可信 Output 生成的临时场景，load_recipe 从不执行旁车。
	var reloaded := ResourceLoader.load(directory.path_join(SURFACE_FILES[1]), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if reloaded == null:
		root.free()
		return "表面植被静态场景重载失败"
	var instance := reloaded.instantiate() as Node3D
	if instance == null:
		root.free()
		return "表面植被静态根不可读取"
	instance.scene_file_path = ""
	var reason := _surface_static_reason(instance, root)
	var metadata: Variant = instance.get_meta(SurfacePaintData.META, null)
	if reason.is_empty() and (not metadata is Dictionary or SurfacePaintData.fingerprint(metadata) != SurfacePaintData.fingerprint(_surface_snapshot)):
		reason = "表面植被静态快照不一致"
	instance.free()
	root.free()
	return reason

func _surface_static_reason(actual: Node3D, expected: Node3D) -> String:
	if not SurfacePaintData._static_tree(actual): return "表面植被静态层含脚本、外部场景或非白名单节点"
	if actual.get_class() != expected.get_class() or actual.name != expected.name or actual.get_child_count() != expected.get_child_count():
		return "表面植被静态层级不一致"
	var a := SurfacePaintData.encode_transform(actual.transform)
	var b := SurfacePaintData.encode_transform(expected.transform)
	for index in 12:
		if not _native_transform_number_equal(float(a[index]), float(b[index])): return "表面植被静态变换不一致"
	if actual is MeshInstance3D:
		var expected_mesh := (expected as MeshInstance3D).mesh
		if actual.mesh == null or expected_mesh == null or actual.mesh.get_surface_count() != expected_mesh.get_surface_count(): return "表面植被贴面网格不一致"
		for surface in expected_mesh.get_surface_count():
			var actual_arrays: Array = actual.mesh.surface_get_arrays(surface)
			var expected_arrays := expected_mesh.surface_get_arrays(surface)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
				if actual_arrays[channel] == null or actual_arrays[channel].size() != expected_arrays[channel].size(): return "表面植被贴面几何数量不一致"
				for vertex in expected_arrays[channel].size():
					if not actual_arrays[channel][vertex].is_equal_approx(expected_arrays[channel][vertex]): return "表面植被贴面几何重载不一致"
	if actual is GeometryInstance3D:
		var material := actual.material_override as StandardMaterial3D
		var expected_material := (expected as GeometryInstance3D).material_override as StandardMaterial3D
		if expected_material != null and (material == null or material.albedo_texture == null or material.albedo_texture.resource_path != expected_material.albedo_texture.resource_path): return "表面植被图集重载不一致"
	if actual is MultiMeshInstance3D:
		var expected_multi := (expected as MultiMeshInstance3D).multimesh
		if actual.multimesh == null or expected_multi == null or actual.multimesh.instance_count != expected_multi.instance_count or actual.multimesh.mesh == null or not actual.multimesh.use_custom_data: return "表面植被草实例数不一致"
		var grass_material := actual.material_override as ShaderMaterial
		if grass_material == null or grass_material.shader == null or grass_material.shader.resource_path != "res://shaders/vegetation/soft_cards.gdshader": return "表面植被草原材质契约不一致"
		for index in expected_multi.instance_count:
			if not actual.multimesh.get_instance_transform(index).is_equal_approx(expected_multi.get_instance_transform(index)): return "表面植被草实例变换不一致"
			if not actual.multimesh.get_instance_custom_data(index).is_equal_approx(expected_multi.get_instance_custom_data(index)): return "表面植被草实例自定义数据不一致"
	for index in expected.get_child_count():
		var child := actual.get_child(index) as Node3D
		if child.owner == null: return "表面植被静态层存在未归属节点"
		var reason := _surface_static_reason(child, expected.get_child(index) as Node3D)
		if not reason.is_empty(): return reason
	return ""

func _static_snapshot_matches(actual: Dictionary, expected: Dictionary) -> bool:
	if not AttachmentData.validate(actual).is_empty() or actual.instances.size() != expected.instances.size(): return false
	# Godot文本资源按引擎real_t精度重载；JSON原值和冲突指纹仍严格保留1e-9。
	for index in 12:
		if not _native_transform_number_equal(float(actual.layer_transform[index]), float(expected.layer_transform[index])): return false
	for index in actual.instances.size():
		var a: Dictionary = actual.instances[index]
		var b: Dictionary = expected.instances[index]
		if not _json_values_equal(a.sea_attachment, b.sea_attachment): return false
		for axis in 12:
			if not _native_transform_number_equal(float(a.transform[axis]), float(b.transform[axis])): return false
	return true

func _native_transform_number_equal(actual: float, expected: float) -> bool:
	# 仅用于TSCN的Transform3D；原生文本序列化与float32回读留8个机器epsilon。
	# JSON及metadata不走此相对容差，始终比较Data的1e-9canonical。
	return is_finite(actual) and is_finite(expected) and absf(actual - expected) <= maxf(1.0, absf(expected)) * 0.00000095367431640625

func _work_wrapper_text(with_surface: bool = false) -> String:
	var text := '[gd_scene load_steps=%d format=3]\n\n[ext_resource type="PackedScene" path="building.tscn" id="1"]\n[ext_resource type="PackedScene" path="building.attachments.tscn" id="2"]\n' % (4 if with_surface else 3)
	if with_surface: text += '[ext_resource type="PackedScene" path="building.surface_paint.tscn" id="3"]\n'
	text += '\n[node name="Work" type="Node3D"]\n\n[node name="Asset" parent="." instance=ExtResource("1")]\n\n[node name="Attachments" parent="." instance=ExtResource("2")]\n'
	if with_surface: text += '\n[node name="SurfacePaint" parent="." instance=ExtResource("3")]\n'
	return text

func _surface_is_declared(manifest: Dictionary) -> bool:
	for key: String in ["surface_paint_snapshot", "surface_paint_scene", "surface_paint_fingerprint", "surface_paint_sources"]:
		if manifest.has(key): return true
	for name: String in SURFACE_FILES:
		if manifest.get("source_hashes", {}) is Dictionary and manifest.get("source_hashes", {}).has(name): return true
		if manifest.get("file_list", []) is Array and manifest.get("file_list", []).has(name): return true
	return false

func _manifest_header_reason(manifest: Dictionary) -> String:
	var version: Variant = manifest.get("schema_version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) != 1.0: return "作品manifest版本不支持或缺失"
	if not manifest.get("building_id") is String or str(manifest.building_id).is_empty(): return "作品manifest缺少字符串building_id"
	var revision: Variant = manifest.get("revision")
	if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision) < 1.0 or float(revision) != floor(float(revision)):
		return "作品manifest.revision必须为正整数"
	var hashes: Variant = manifest.get("source_hashes")
	var files: Variant = manifest.get("file_list")
	if not hashes is Dictionary or not files is Array: return "作品manifest缺少hash对象或文件数组"
	for key: Variant in hashes:
		if not key is String or not hashes[key] is String or not _is_sha256(hashes[key]): return "作品manifest含非法hash字段"
	for file: Variant in files:
		if not file is String: return "作品manifest.file_list只允许字符串"
	return ""

func _is_sha256(value: String) -> bool:
	if value.length() != 64: return false
	for character: String in value:
		if not "0123456789abcdef".contains(character): return false
	return true

func _verify_work_files(directory: String, manifest: Dictionary) -> String:
	var header_reason := _manifest_header_reason(manifest)
	if not header_reason.is_empty(): return header_reason
	for key: String in ["attachments_snapshot", "attachments_scene", "work_scene", "attachments_fingerprint"]:
		if not manifest.get(key) is String: return "作品manifest缺少字符串声明：" + key
	if manifest.attachments_snapshot != WORK_FILES[0] or manifest.attachments_scene != WORK_FILES[1] or manifest.work_scene != WORK_FILES[2]:
		return "作品manifest固定文件声明不合法"
	if not _is_sha256(manifest.attachments_fingerprint): return "作品manifest外挂指纹格式不合法"
	var hashes: Dictionary = manifest.source_hashes
	var files: Array = manifest.file_list
	var with_surface := _surface_is_declared(manifest)
	if with_surface:
		if manifest.get("surface_paint_snapshot") != SURFACE_FILES[0] or manifest.get("surface_paint_scene") != SURFACE_FILES[1] or not manifest.get("surface_paint_fingerprint") is String:
			return "作品manifest表面植被固定声明不合法"
		if not _is_sha256(manifest.surface_paint_fingerprint): return "作品manifest表面植被指纹格式不合法"
		var expected_files: Array = ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json"] + WORK_FILES + SURFACE_FILES
		if files.size() != expected_files.size(): return "表面植被完整作品必须声明固定10件文件"
		for name: String in expected_files:
			if files.count(name) != 1: return "表面植被完整作品文件声明缺失或重复：" + name
	for name: String in ["building.recipe.json", "catalog_snapshot.json", "building.tscn"] + WORK_FILES + (SURFACE_FILES if with_surface else []):
		var path := directory.path_join(name)
		if not files.has(name) or not FileAccess.file_exists(path) or not hashes.get(name) is String or str(hashes[name]).is_empty() or _sha256_file(path) != hashes[name]:
			return "作品文件缺失或hash不符：" + name
	var snapshot: Variant = _read_json(directory.path_join(WORK_FILES[0]))
	if not snapshot is Dictionary: return "作品外挂JSON损坏"
	var reason := AttachmentData.validate(snapshot)
	if not reason.is_empty(): return reason
	if manifest.get("attachments_fingerprint") != AttachmentData.fingerprint(snapshot): return "作品外挂指纹不符"
	if with_surface:
		var painted: Variant = _read_json(directory.path_join(SURFACE_FILES[0]))
		if not painted is Dictionary: return "作品表面植被JSON损坏"
		reason = SurfacePaintData.validate(painted)
		if not reason.is_empty(): return reason
		if SurfacePaintData.fingerprint(painted) != manifest.surface_paint_fingerprint: return "作品表面植被指纹不符"
	else:
		for name: String in SURFACE_FILES:
			if FileAccess.file_exists(directory.path_join(name)): return "存在未声明的表面植被旁车"
	if FileAccess.get_file_as_string(directory.path_join(WORK_FILES[2])) != _work_wrapper_text(with_surface): return "作品包装不是固定原生层级"
	return ""

func _remove_temp_dir(path: String, parent: String) -> void:
	if path.get_base_dir() != parent or not path.get_file().begins_with(".tmp_revision_"): return
	# 只清理本次导出的固定文件；未知文件不触碰。
	for name: String in ["building.recipe.json", "building.tscn", "catalog_snapshot.json", "candidate_manifest.json", "ledger.json"] + WORK_FILES + SURFACE_FILES:
		var file := path.path_join(name)
		if FileAccess.file_exists(file): DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
