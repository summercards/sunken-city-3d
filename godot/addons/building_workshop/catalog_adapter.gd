@tool
extends RefCounted

const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const COMPONENT_ROOT := "res://scenes/components"
const SIZE_EPSILON := 0.0001
const SIZE_HINT := "先导出单槽模块/仅替换尺寸一致件"

static func apply_prefab(session: RefCounted, component_id: String, path: String) -> Dictionary:
	var context := _session_context(session)
	if not context.ok:
		return context
	var recipe: Dictionary = context.recipe
	var next_catalog: Dictionary = context.catalog
	var components: Dictionary = next_catalog.get("components", {})
	if not components.get(component_id) is Dictionary:
		return _failure("组件 ID 不存在：" + component_id)
	var definition: Dictionary = components[component_id].duplicate(true)
	if not bool(definition.get("replaceable", false)):
		return _failure("组件不允许替换：" + component_id)
	var inspected := inspect_static_prefab(path)
	if not inspected.ok:
		return inspected
	definition["kind"] = "prefab"
	definition["prefab"] = inspected.scene_path
	definition["nominal_size"] = inspected.nominal_size
	definition["pivot"] = inspected.pivot
	definition["front_axis"] = "-Z"
	definition["version"] = "sha256:" + str(inspected.hash)
	components[component_id] = definition
	# 所有会被生成器实例化的现有 prefab 也必须先经过更严格的静态检查。
	var reason := _inspect_catalog(next_catalog)
	if not reason.is_empty():
		return _failure(reason)
	reason = Catalog.validate(next_catalog)
	if not reason.is_empty():
		return _failure(reason + "；" + SIZE_HINT)
	var before := Generator.build(recipe, context.catalog)
	if not bool(before.get("ok", false)):
		_free_build(before)
		return _failure(str(before.get("reason", "当前配方生成失败")))
	var affected: Array = []
	for slot in before.get("slots", []):
		if str(slot.get("component_id", "")) != component_id:
			continue
		affected.append(str(slot.id))
		if not _same_vector(_vector(slot.get("bounds_size", [])), _vector(inspected.nominal_size)):
			_free_build(before)
			return _failure("槽位 %s 的实际尺寸与组件不一致；%s" % [str(slot.id), SIZE_HINT])
	var probe := Generator.build(recipe, next_catalog)
	if not bool(probe.get("ok", false)):
		_free_build(before)
		_free_build(probe)
		return _failure(str(probe.get("reason", "组件探测失败")) + "；" + SIZE_HINT)
	reason = _compare_slots(before.get("slots", []), probe.get("slots", []), component_id)
	var old_root := before.get("root") as Node3D
	var new_root := probe.get("root") as Node3D
	if reason.is_empty() and (old_root == null or new_root == null or not old_root.transform.is_equal_approx(new_root.transform)):
		reason = "替换改变了建筑根变换"
	_free_build(before)
	_free_build(probe)
	if not reason.is_empty():
		return _failure(reason + "；" + SIZE_HINT)
	if not session.has_method("replace_catalog"):
		var pending := _failure("等待主线程实现 session.replace_catalog(c: Dictionary)；当前会话未修改")
		pending["pending"] = true
		return pending
	# 仅通过会话命令提交；不以 accept_loaded 清除撤销历史或标记已保存。
	var committed: Variant = session.call("replace_catalog", next_catalog.duplicate(true))
	if not committed is Dictionary:
		return _failure("session.replace_catalog 必须返回 Dictionary")
	var result: Dictionary = committed.duplicate(true)
	if bool(result.get("ok", false)):
		result["component_id"] = component_id
		result["scene_path"] = inspected.scene_path
		result["affected_slots"] = affected
	return result

static func apply_prefab_to_slot(session: RefCounted, slot_id: String, path: String) -> Dictionary:
	var context: Dictionary = _session_context(session)
	if not context.ok:
		return context
	var inspected: Dictionary = inspect_static_prefab(path)
	if not inspected.ok:
		return inspected
	var before: Dictionary = Generator.build(context.recipe, context.catalog)
	if not bool(before.get("ok", false)):
		return _failure(str(before.get("reason", "当前配方无法生成")))
	var target: Dictionary = {}
	for slot: Dictionary in before.slots:
		if str(slot.id) == slot_id:
			target = slot
			break
	if target.is_empty():
		_free_build(before)
		return _failure("未选择有效槽位")
	if not _same_vector(_vector(target.get("bounds_size", [])), _vector(inspected.nominal_size)):
		_free_build(before)
		return _failure("替件实际尺寸不兼容；" + SIZE_HINT)
	var next_recipe: Dictionary = context.recipe.duplicate(true)
	var next_catalog: Dictionary = context.catalog.duplicate(true)
	var clone_id: String = "slot_" + (str(next_recipe.building_id) + ":" + slot_id).sha256_text().substr(0, 24)
	var definition: Dictionary = next_catalog.components[str(target.component_id)].duplicate(true)
	definition["kind"] = "prefab"
	definition["prefab"] = str(inspected.scene_path)
	definition["nominal_size"] = inspected.nominal_size
	definition["pivot"] = inspected.pivot
	definition["front_axis"] = "-Z"
	definition["version"] = "sha256:" + str(inspected.hash)
	next_catalog.components[clone_id] = definition
	var override: Dictionary = next_recipe.slot_overrides.get(slot_id, {}).duplicate(true)
	override["component_id"] = clone_id
	next_recipe.slot_overrides[slot_id] = override
	var reason: String = Catalog.validate(next_catalog)
	if not reason.is_empty():
		_free_build(before)
		return _failure(reason)
	var probe: Dictionary = Generator.build(next_recipe, next_catalog)
	if not bool(probe.get("ok", false)):
		_free_build(before)
		return _failure(str(probe.get("reason", "替换生成失败")))
	var new_target: Dictionary = {}
	for slot: Dictionary in probe.slots:
		if str(slot.id) == slot_id:
			new_target = slot
	_free_build(before)
	_free_build(probe)
	if new_target.is_empty() or not _same_vector(_vector(target.get("position", [])), _vector(new_target.get("position", []))) or not _same_vector(_vector(target.get("bounds_size", [])), _vector(new_target.get("bounds_size", []))):
		return _failure("替换改变了槽位锚点或包络")
	var committed: Dictionary = session.replace_document(next_recipe, next_catalog)
	if bool(committed.get("ok", false)):
		committed["component_id"] = clone_id
		committed["scene_path"] = path
		committed["affected_slots"] = [slot_id]
	return committed

static func inspect_static_prefab(path: String) -> Dictionary:
	var safe_path := _component_path(path)
	if safe_path.is_empty() or not safe_path.ends_with(".tscn"):
		return _failure("只允许 res://scenes/components/ 下的静态 .tscn")
	if not FileAccess.file_exists(safe_path):
		return _failure("组件场景不存在")
	var packed := ResourceLoader.load(safe_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return _failure("组件不是 PackedScene")
	var reason := _safe_state(packed.get_state())
	if not reason.is_empty():
		return _failure(reason)
	# state 与资源树检查完成后，才允许实例化；不挂入 SceneTree。
	var instance: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return _failure("组件根必须为 Node3D")
	var measured := _measure(instance as Node3D)
	var layout: Variant = instance.get_meta("workshop_module", {})
	var metadata: Dictionary = layout.duplicate(true) if layout is Dictionary else {}
	instance.free()
	if not measured.ok:
		return measured
	var bounds: AABB = measured.aabb
	var result := {
		"ok": true, "reason": "", "scene_path": safe_path,
		"bounds": _bounds(bounds), "nominal_size": _array(bounds.size),
		"pivot": _array(bounds.get_center()), "front_axis": "-Z",
		"mesh_count": measured.mesh_count, "triangle_count": measured.triangle_count,
		"hash": FileAccess.get_sha256(safe_path), "metadata": metadata
	}
	return result

static func export_slot(session: RefCounted, slot_id: String, base_dir: String = "res://scenes/components/workshop_modules") -> Dictionary:
	var context := _session_context(session)
	if not context.ok:
		return context
	var safe_base := _component_path(base_dir)
	if safe_base.is_empty() or not _safe_segment(slot_id):
		return _failure("模块导出目录或 slot_id 非法")
	var recipe: Dictionary = context.recipe
	var building_id := str(recipe.get("building_id", ""))
	if not _safe_segment(building_id):
		return _failure("building_id 非法")
	var build := Generator.build(recipe, context.catalog)
	if not bool(build.get("ok", false)):
		_free_build(build)
		return _failure(str(build.get("reason", "生成失败")))
	var slot: Dictionary = {}
	for entry in build.get("slots", []):
		if str(entry.get("id", "")) == slot_id:
			slot = entry
			break
	var building := build.get("root") as Node3D
	var source: Node3D = null
	if building != null and not slot.is_empty():
		source = building.get_node_or_null(NodePath(str(slot.get("node_path", "")))) as Node3D
	if source == null:
		_free_build(build)
		return _failure("所选槽位不存在、已排除或没有视觉节点")
	var module := Node3D.new()
	module.name = "WorkshopModule"
	var semantic_only: bool = bool(slot.get("semantic_source_only", false))
	var semantic: Dictionary = build.get("semantic_sources", {}).get(slot_id, {})
	if semantic_only and (semantic.is_empty() or str(semantic.get("component_id", "")) != str(slot.get("component_id", "")) or str(semantic.get("kind", "")) != str(slot.get("kind", "")) or int(semantic.get("floor", -1)) != int(slot.get("floor", -1))):
		module.free()
		_free_build(build)
		return _failure("语义槽缺少匹配的编辑源模块")
	var source_meshes: Array[MeshInstance3D] = []
	if not semantic_only:
		_collect_meshes(source, source_meshes)
	var component_id := "module_" + (building_id + ":" + slot_id).sha256_text().substr(0, 32)
	var kind := str(slot.get("kind", ""))
	var old_id := str(slot.get("component_id", ""))
	var definitions: Dictionary = context.catalog.get("components", {})
	var definition: Dictionary = definitions.get(old_id, {})
	var profile := str(definition.get("profile", ""))
	for source_mesh in source_meshes:
		if source_mesh.mesh == null:
			continue
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Mesh_%04d" % module.get_child_count()
		# 只复制视觉实例属性；共享 Mesh/Material 只读，不复制脚本或碰撞。
		mesh_node.mesh = source_mesh.mesh
		mesh_node.material_override = source_mesh.material_override
		mesh_node.material_overlay = source_mesh.material_overlay
		mesh_node.cast_shadow = source_mesh.cast_shadow
		mesh_node.layers = source_mesh.layers
		mesh_node.transform = Transform3D(source.basis, Vector3.ZERO) * _local_chain(source_mesh, source)
		for surface in source_mesh.get_surface_override_material_count():
			mesh_node.set_surface_override_material(surface, source_mesh.get_surface_override_material(surface))
		_copy_instance_shader_parameters(source_mesh, mesh_node)
		module.add_child(mesh_node)
	if semantic_only:
		# record.transform 已含原件轴向与局部层级；只去掉槽位平移，不重复施加轴向。
		for record: Dictionary in semantic.get("mesh_records", []):
			var mesh_node := MeshInstance3D.new()
			mesh_node.name = "Mesh_%04d" % module.get_child_count()
			mesh_node.mesh = record.get("mesh") as Mesh
			mesh_node.transform = record.get("transform", Transform3D.IDENTITY)
			module.add_child(mesh_node)
	for child: Node in module.get_children():
		child.set_meta("slot_id", slot_id)
		child.set_meta("slot_kind", kind)
		child.set_meta("component_id", component_id)
		child.owner = module
	_free_build(build)
	var before := _measure(module)
	if not before.ok:
		module.free()
		return before
	var original: AABB = before.aabb
	if semantic_only and not _same_vector(original.size, _vector(slot.get("bounds_size", []))):
		module.free()
		return _failure("编辑源模块尺寸与语义槽实际包络不一致")
	var anchor := original.get_center()
	var pivot_mode := "center"
	if kind == "plant":
		pivot_mode = "top_center" if profile == "vine" else "bottom_center"
		anchor.y = original.end.y if profile == "vine" else original.position.y
	for child in module.get_children():
		(child as Node3D).position -= anchor
	before = _measure(module)
	var actual: AABB = before.aabb
	var layout := {
		"schema": "sea.workshop.module_layout", "schema_version": 1,
		"component_id": component_id, "building_id": building_id,
		"slot_id": slot_id, "slot_kind": kind, "front_axis": "-Z",
		"origin_mode": pivot_mode, "pivot_actual": _array(actual.get_center()),
		"nominal_size": _array(actual.size), "bounds": _bounds(actual)
	}
	var export_scope := "semantic_source_module" if semantic_only else "slot_visual_module"
	var export_note := "编辑源模块，不是最终融合后的切片" if semantic_only else "独立槽位视觉模块"
	layout["geometry_scope"] = export_scope
	layout["geometry_note"] = export_note
	layout["source_component_id"] = old_id
	layout["source_component_hash"] = Catalog.fingerprint(definition)
	layout["source_component_version"] = str(definition.get("version", ""))
	layout["source_front_axis"] = str(definition.get("front_axis", "-Z"))
	layout["source_nominal_size"] = definition.get("nominal_size", []).duplicate()
	if str(definition.get("kind", "")) == "prefab":
		layout["source_prefab_hash"] = FileAccess.get_sha256(str(definition.get("prefab", "")))
	module.set_meta("component_id", component_id)
	module.set_meta("slot_id", slot_id)
	module.set_meta("slot_kind", kind)
	module.set_meta("front_axis", "-Z")
	module.set_meta("workshop_module", layout)
	var packed := PackedScene.new()
	if packed.pack(module) != OK:
		module.free()
		return _failure("模块打包失败")
	module.free()
	var unsafe_reason := _safe_state(packed.get_state())
	if not unsafe_reason.is_empty():
		return _failure(unsafe_reason)
	var parent := safe_base.path_join(building_id).path_join(slot_id)
	var absolute_parent := ProjectSettings.globalize_path(parent)
	if DirAccess.make_dir_recursive_absolute(absolute_parent) != OK:
		return _failure("无法创建模块版本父目录")
	var revision := _next_module_revision(parent)
	var final_dir := parent.path_join("revision%04d" % revision)
	var temp_dir := parent.path_join(".tmp_revision%04d_%s" % [revision, str(Time.get_ticks_usec())])
	if DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temp_dir)) != OK:
		return _failure("无法创建模块临时目录")
	var temp_scene := temp_dir.path_join("component.tscn")
	var temp_manifest := temp_dir.path_join("component_manifest.json")
	if ResourceSaver.save(packed, temp_scene) != OK:
		_remove_module_temp(temp_dir)
		return _failure("模块场景保存失败")
	var reloaded := inspect_static_prefab(temp_scene)
	if not reloaded.ok:
		_remove_module_temp(temp_dir)
		return reloaded
	if not _same_vector(_vector(reloaded.bounds.position), actual.position) or not _same_vector(_vector(reloaded.bounds.size), actual.size) or int(reloaded.triangle_count) != int(before.triangle_count) or int(reloaded.mesh_count) != int(before.mesh_count) or not _same_interface_value(reloaded.metadata, layout):
		_remove_module_temp(temp_dir)
		return _failure("模块重载不一致：before=%s after=%s metadata=%s" % [str(_bounds(actual)), str(reloaded.bounds), str(Catalog.fingerprint(reloaded.metadata) == Catalog.fingerprint(layout))])
	var manifest := {
		"schema": "sea.workshop.component_manifest", "schema_version": 1,
		"authoring_context": "editor", "noMain": true,
		"status": "candidate_only", "formal_registry_written": false,
		"component_id": component_id, "building_id": building_id,
		"source_slot_id": slot_id, "source_component_id": old_id,
		"geometry_scope": export_scope, "geometry_note": export_note,
		"revision": revision, "layout": layout, "pivot_actual": layout.pivot_actual,
		"front_axis": "-Z", "bounds": _bounds(actual),
		"mesh_count": before.mesh_count, "triangle_count": before.triangle_count,
		"scene_path": final_dir.path_join("component.tscn"),
		"source_hashes": {"component.tscn": reloaded.hash, "recipe": Catalog.fingerprint(recipe), "catalog": Catalog.fingerprint(context.catalog), "source_component": Catalog.fingerprint(definition)},
		"file_list": ["component.tscn", "component_manifest.json"]
	}
	if not _write_module_json(temp_manifest, manifest):
		_remove_module_temp(temp_dir)
		return _failure("模块 manifest 写入或重载校验失败")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(final_dir)) or FileAccess.file_exists(final_dir) or DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_dir), ProjectSettings.globalize_path(final_dir)) != OK:
		_remove_module_temp(temp_dir)
		return _failure("模块 revision 提交失败，历史版本未覆盖")
	return {"ok": true, "reason": "", "scene_path": final_dir.path_join("component.tscn"), "manifest_path": final_dir.path_join("component_manifest.json"), "component_id": component_id, "bounds": _bounds(actual)}

static func _session_context(session: RefCounted) -> Dictionary:
	if session == null or not session.has_method("snapshot"):
		return _failure("缺少有效的工坊会话")
	var recipe: Variant = session.call("snapshot")
	var catalog: Variant = session.get("catalog")
	if not recipe is Dictionary or not catalog is Dictionary:
		return _failure("会话必须提供 snapshot() 与 catalog")
	var copy: Dictionary = catalog.duplicate(true)
	var reason := _inspect_catalog(copy)
	if reason.is_empty():
		reason = Catalog.validate(copy)
	if not reason.is_empty():
		return _failure(reason)
	return {"ok": true, "reason": "", "recipe": recipe.duplicate(true), "catalog": copy}

static func _inspect_catalog(catalog: Dictionary) -> String:
	var components: Variant = catalog.get("components", {})
	if not components is Dictionary:
		return "组件目录缺少 components 对象"
	for component_id in components:
		var definition: Variant = components[component_id]
		if definition is Dictionary and str(definition.get("kind", "")) == "prefab":
			var checked := inspect_static_prefab(str(definition.get("prefab", "")))
			if not checked.ok:
				return str(component_id) + "：" + str(checked.reason)
	return ""

static func _safe_state(state: SceneState) -> String:
	if state == null or state.get_node_count() == 0:
		return "组件场景为空"
	if state.get_base_scene_state() != null or state.get_connection_count() != 0:
		return "组件不允许继承场景或信号连接"
	var visited: Dictionary = {}
	for index in state.get_node_count():
		if state.get_node_instance(index) != null or state.is_node_instance_placeholder(index):
			return "组件不允许嵌套场景或占位实例"
		if str(state.get_node_type(index)) not in ["Node3D", "MeshInstance3D"]:
			return "组件仅允许 Node3D 与 MeshInstance3D，不允许灯光、碰撞或脚本节点"
		for property_index in state.get_node_property_count(index):
			var property := str(state.get_node_property_name(index, property_index))
			var value: Variant = state.get_node_property_value(index, property_index)
			if property in ["script", "top_level", "top_level_transform", "skeleton", "skin"]:
				return "组件含非静态属性：" + property
			if _unsafe_value(value, visited):
				return "组件含脚本、嵌套场景或非 res:// 资源"
	return ""

static func _unsafe_value(value: Variant, visited: Dictionary) -> bool:
	if value is Script or value is PackedScene or value is Callable or value is Signal:
		return true
	if value is Resource:
		if visited.has(value.get_instance_id()):
			return false
		visited[value.get_instance_id()] = true
		if value.get_script() != null:
			return true
		var path := str(value.resource_path)
		if not path.is_empty() and (not path.begins_with("res://") or path.contains("..") or path.contains("\\")):
			return true
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				if _unsafe_value(value.get(str(property.name)), visited):
					return true
	elif value is Object:
		return true
	elif value is Array:
		for item in value:
			if _unsafe_value(item, visited):
				return true
	elif value is Dictionary:
		for key in value:
			if _unsafe_value(key, visited) or _unsafe_value(value[key], visited):
				return true
	return false

static func _same_interface_value(a: Variant, b: Variant) -> bool:
	# TSCN浮点文本会舍入。身份字段必须全等，尺寸字段以接口公差逐项校验。
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 0.00001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _same_interface_value(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if not _same_interface_value(a[index], b[index]):
				return false
		return true
	return a == b

static func _measure(root: Node3D) -> Dictionary:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	var has_bounds := false
	var bounds := AABB()
	var triangles := 0
	var count := 0
	for node in meshes:
		if node.mesh == null:
			continue
		var transform := root.transform * _local_chain(node, root)
		if not transform.is_finite():
			return _failure("组件变换包含非有限数值")
		var box: AABB = transform * node.mesh.get_aabb()
		if not box.position.is_finite() or not box.size.is_finite():
			return _failure("组件实际包围盒非法")
		bounds = bounds.merge(box) if has_bounds else box
		has_bounds = true
		triangles += int(node.mesh.get_faces().size() / 3)
		count += 1
	if not has_bounds or triangles <= 0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return _failure("组件必须包含有三维尺寸的静态三角网格")
	return {"ok": true, "reason": "", "aabb": bounds, "mesh_count": count, "triangle_count": triangles}

static func _copy_instance_shader_parameters(source: MeshInstance3D, target: MeshInstance3D) -> void:
	for name: String in ["sea_material_role", "sea_matte_controls", "sea_metal_controls", "sea_gloss_controls", "sea_emission_controls", "sea_matte_emission_energy", "sea_metal_emission_energy", "sea_gloss_emission_energy", "sea_emission_emission_energy"]:
		target.set_instance_shader_parameter(name, source.get_instance_shader_parameter(name))

static func _collect_meshes(node: Node3D, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		if child is Node3D:
			_collect_meshes(child as Node3D, result)

static func _local_chain(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

static func _compare_slots(before: Array, after: Array, component_id: String) -> String:
	if before.size() != after.size():
		return "替换改变了实际槽位数量"
	var by_id: Dictionary = {}
	for slot in after:
		by_id[str(slot.id)] = slot
	for slot in before:
		var next: Dictionary = by_id.get(str(slot.id), {})
		if next.is_empty():
			return "替换丢失槽位：" + str(slot.id)
		for key in ["component_id", "kind", "position", "size"]:
			if slot.get(key) != next.get(key):
				return "替换改变了槽位接口：" + str(slot.id) + "." + str(key)
		if str(slot.get("component_id", "")) == component_id:
			for key in ["bounds_position", "bounds_size"]:
				if not _same_vector(_vector(slot.get(key, [])), _vector(next.get(key, []))):
					return "替换改变了槽位实际几何接口：" + str(slot.id)
	return ""

static func _component_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if not normalized.begins_with("res://") or normalized.contains("..") or normalized.strip_edges() != normalized:
		return ""
	normalized = normalized.simplify_path().trim_suffix("/")
	if normalized != COMPONENT_ROOT and not normalized.begins_with(COMPONENT_ROOT + "/"):
		return ""
	if normalized.trim_prefix("res://").contains(":"):
		return ""
	return normalized

static func _safe_segment(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for character in value:
		var code := character.unicode_at(0)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95 or code == 45):
			return false
	return true

static func _next_module_revision(parent: String) -> int:
	var maximum := 0
	var directory := DirAccess.open(parent)
	if directory == null:
		return 1
	for name in directory.get_directories():
		if name.begins_with("revision"):
			var number := name.trim_prefix("revision")
			if number.is_valid_int():
				maximum = maxi(maximum, int(number))
	for name in directory.get_files():
		if name.begins_with("revision"):
			var number := name.trim_prefix("revision")
			if number.is_valid_int():
				maximum = maxi(maximum, int(number))
	return maximum + 1

static func _write_module_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed is Dictionary and Catalog.fingerprint(parsed) == Catalog.fingerprint(value)

static func _remove_module_temp(path: String) -> void:
	if _component_path(path).is_empty() or not path.get_file().begins_with(".tmp_revision"):
		return
	# 只清理由本次导出创建的两个文件，不递归触及其他资源。
	for name in ["component.tscn", "component_manifest.json"]:
		var file_path := path.path_join(name)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func _free_build(build: Dictionary) -> void:
	var root := build.get("root") as Node
	if root != null:
		root.free()
	build["root"] = null

static func _same_vector(a: Vector3, b: Vector3) -> bool:
	return a.is_finite() and b.is_finite() and absf(a.x - b.x) <= SIZE_EPSILON and absf(a.y - b.y) <= SIZE_EPSILON and absf(a.z - b.z) <= SIZE_EPSILON

static func _vector(value: Array) -> Vector3:
	if value.size() != 3:
		return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _bounds(value: AABB) -> Dictionary:
	return {"position": _array(value.position), "size": _array(value.size)}

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "scene_path": "", "manifest_path": "", "component_id": "", "bounds": {}}
