@tool
extends Node
## 独立外挂层的唯一场景写入端；生成成功后才提交编辑器场景历史。

signal changed
signal message(text: String)

const Recipe = preload("res://src/building_attachments/recipe.gd")
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const Store = preload("res://src/building_attachments/store.gd")
const Surface = preload("res://addons/scene_assembly/attachment_surface.gd")
const META := "sea_attachment"
const CLEARANCE := 0.012
# 只开放已有可重复对接的实体接口；落水管斜出口、成束管错台不冒充标准接头。
const CHAIN_PORTS := {
	"pipe_elbow": [["elbow_left_flange", 1], ["elbow_top_flange", 1]],
	"pipe_t_valve": [["valve_left", -1], ["valve_right", 1]],
}
const CHAIN_SHELTERS := ["awning_slope", "awning_barrel", "canopy_entry"]
const CHAIN_SNAP_RADIUS := 0.85
var chain_active := false
var _chain_has_anchor := false
var _chain_ports_cache: Dictionary = {}

var assembly: EditorPlugin
var host_container: Node3D
var host_asset: Node3D
var selected: Node3D
var host_scene: Node
var mount_mode := "wall"
var offset := 0.0
var angle_degrees := 0.0
var armed := false
var armed_recipe: Dictionary = {}
var _candidate_id := ""
var _candidate_source := ""
var _arm_context: Dictionary = {}
var _arm_serial := 0
var _confirming := false
var _installation_profiles: Dictionary = {}
var workshop_context: Dictionary = {}
var _ui_active := true

func configure_workshop(context: Dictionary) -> Dictionary:
	if not context.is_empty():
		for key: String in ["root", "host_asset", "selection_get", "selection_set", "arm", "cancel"]:
			if not context.get(key) is Callable or not context[key].is_valid(): return _fail("工坊上下文缺少有效 Callable：" + key)
		var history: Variant = context.get("history")
		if not history is Object or not is_instance_valid(history) or history is EditorUndoRedoManager: return _fail("工坊必须使用文档本地历史，不能写编辑场景历史")
		for method: String in ["create_action", "add_do_method", "add_undo_method", "add_do_reference", "add_undo_reference", "commit_action"]:
			if not history.has_method(method): return _fail("工坊历史缺少方法：" + method)
	cancel_arm(false)
	workshop_context = context.duplicate()
	host_container = null
	host_asset = null
	host_scene = null
	selected = null
	changed.emit()
	return {"ok": true, "reason": ""}

func set_active(active: bool) -> void:
	_ui_active = active
	if not active: cancel_arm(false)

func _selected_nodes() -> Array:
	if not workshop_context.is_empty():
		var nodes: Variant = workshop_context.selection_get.call()
		var result: Array = []
		if nodes is Array:
			for node: Variant in nodes:
				var target := attachment_for(node) if node is Node and is_instance_valid(node) else null
				if target != null and not result.has(target): result.append(target)
		return result
	return EditorInterface.get_selection().get_selected_nodes()

func _select_nodes(nodes: Array) -> void:
	if workshop_context.is_empty():
		assembly._select_nodes(nodes)
		return
	var targets: Array = []
	for node: Variant in nodes:
		var target := attachment_for(node) if node is Node and is_instance_valid(node) else null
		if target != null and not targets.has(target): targets.append(target)
	workshop_context.selection_set.call(targets)
	# 本地选择回调不必模拟 EditorSelection 信号；历史执行也走同一同步入口。
	select_attachment(targets[0] if targets.size() == 1 else null)

func _history() -> Object:
	return workshop_context.history if not workshop_context.is_empty() else assembly.get_undo_redo()

func _request_arm() -> void:
	if not workshop_context.is_empty(): workshop_context.arm.call()
	else: assembly.arm_attachment_drop()

func _cancel_arm_ui() -> void:
	if not workshop_context.is_empty(): workshop_context.cancel.call()
	elif is_instance_valid(assembly): assembly.cancel_attachment_drop()

func _workshop_asset(root: Node) -> Node3D:
	var asset: Variant = workshop_context.host_asset.call()
	if not is_instance_valid(root) or not root is Node3D or root.get_class() != "Node3D" or root.get_script() != null: return null
	if not asset is Node3D or not is_instance_valid(asset) or asset.get_class() != "Node3D" or asset.get_script() != null or asset.get_parent() != root: return null
	return asset

func _profile_for(recipe: Dictionary, mode: String, built: Dictionary = {}) -> Dictionary:
	var key := JSON.stringify(recipe).sha256_text() + "/" + mode
	if _installation_profiles.has(key): return _installation_profiles[key]
	var generated := built.is_empty()
	var source: Dictionary = _build_trusted(recipe) if generated else built
	if not source.ok: return source
	var profile: Dictionary = Surface.installation_profile(source, mode)
	profile.source = {"mount_anchor": source.mount_anchor.duplicate(true), "stats": {"bounds": source.stats.bounds.duplicate(true)}}
	if generated: source.root.free()
	if _installation_profiles.size() >= 8: _installation_profiles.erase(_installation_profiles.keys()[0])
	_installation_profiles[key] = profile
	return profile

func validate_installation(recipe: Dictionary, hit: Dictionary, built: Dictionary = {}) -> Dictionary:
	var reason := _check_host()
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var profile := _profile_for(recipe, str(hit.mode), built)
	if not profile.ok: return profile
	# profile 只缓存原生安装几何；每次命中仍只读当前宿主三角面，不缓存旧支撑结果。
	var source: Dictionary = built
	if source.is_empty(): source = profile.source
	var pose := _pose(source, hit, offset, float(hit.get("chain_angle", angle_degrees)))
	var result: Dictionary = Surface.validate_installation(host_asset, profile, pose, hit.normal, hit.mode, CLEARANCE + offset)
	if result.ok and chain_active:
		var layer := host_container.get_node_or_null("Attachments")
		if layer != null and layer.get_child_count() >= 256:
			result = {"ok": false, "reason": "作品最多保存256件外挂，不能再接长"}
		elif layer != null:
			for neighbor: Node in layer.get_children():
				if not neighbor is Node3D: continue
				# 重合的实体面可能共面，不能只靠三角穿插识别重复段。
				if neighbor.global_position.distance_to(pose.origin) < 0.005:
					result = {"ok": false, "reason": "该接头已占用，不能重复接长"}
				else:
					var neighbor_check: Dictionary = Surface.validate_neighbor(neighbor, profile.triangles, pose)
					if not neighbor_check.ok: result = neighbor_check
				if not result.ok: break
	result.pose = pose
	return result

func _process(_delta: float) -> void:
	if armed and _ui_active and not _confirming:
		# 工坊每帧只检查锁定节点和查询端口；完整几何门禁留在预览与确认入口。
		var reason := _context_reason(false, workshop_context.is_empty())
		if not reason.is_empty():
			cancel_arm(false)
			message.emit("贴面上下文已过期并取消：" + reason + "；原节点和未应用输入保持")

func _root() -> Node:
	if not workshop_context.is_empty():
		var root: Variant = workshop_context.root.call()
		return root if root is Node and is_instance_valid(root) else null
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(assembly) or assembly.is_queued_for_deletion() or not assembly.is_inside_tree(): return null
	var editor: Control = EditorInterface.get_base_control()
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return null
	return EditorInterface.get_edited_scene_root()

func _fail(reason: String) -> Dictionary:
	message.emit(reason)
	return {"ok": false, "reason": reason}

func _success(result: Dictionary, text: String) -> Dictionary:
	message.emit(text)
	return result

func attachment_for(node: Node) -> Node3D:
	if not workshop_context.is_empty():
		var root := _root()
		var layer: Node = root.get_node_or_null("Attachments") if is_instance_valid(root) else null
		if not is_instance_valid(layer) or not is_instance_valid(node) or not layer.is_ancestor_of(node): return null
		while node.get_parent() != layer: node = node.get_parent()
		return node if node is Node3D and node.has_meta(META) and node.owner == root else null
	while is_instance_valid(node):
		if node is Node3D and node.has_meta(META): return node
		if node == _root(): break
		node = node.get_parent()
	return null

func _inherited_or_imported_scene(scene: Node) -> bool:
	var path := scene.scene_file_path
	if path.is_empty(): return false
	if not path.begins_with("res://") or path.contains("..") or path.contains("\\") or not path.ends_with(".tscn"): return true
	if not FileAccess.file_exists(path): return true
	# 只读文本头，绝不 load 场景；根节点带 instance 表示继承包装。
	var expression := RegEx.new()
	expression.compile("(?s)\\[node\\s+[^\\]]*\\]")
	var header := expression.search(FileAccess.get_file_as_string(path))
	if header == null: return true
	var inherited := RegEx.new()
	inherited.compile("\\binstance\\s*=")
	return inherited.search(header.get_string()) != null

func set_host(node: Node) -> Dictionary:
	if not workshop_context.is_empty():
		var root := _root() as Node3D
		if node != root or not is_instance_valid(root) or not root.is_inside_tree(): return _fail("工坊只允许明确传入当前预览 root")
		var asset := _workshop_asset(root)
		if asset == null: return _fail("预览 root/Asset 必须是无脚本的真实 Node3D，且 Asset 直接属于预览 root")
		var layer := root.get_node_or_null("Attachments")
		if layer != null and (not layer is Node3D or layer.get_script() != null or not layer.scene_file_path.is_empty() or layer.owner != root): return _fail("预览 Attachments 不是安全本地层")
		if not Surface.valid_transform(root.global_transform) or not Surface.valid_transform(asset.global_transform): return _fail("预览宿主含奇异、镜像或非有限变换")
		host_container = root
		host_asset = asset
		host_scene = root
		if is_instance_valid(selected) and attachment_for(selected) == null: selected = null
		cancel_arm(false)
		changed.emit()
		return _success({"ok": true, "reason": "", "host": root, "asset": asset}, "当前工坊房屋已就绪；外挂随建筑作品保存")
	if not node is Node3D or attachment_for(node) != null: return _fail("请选择建筑 Placement/Asset 或安全的本地 Node3D 宿主")
	var scene := _root()
	if not scene is Node3D or not node.is_inside_tree() or (node != scene and not scene.is_ancestor_of(node)): return _fail("宿主必须属于当前 Node3D 编辑场景")
	if _inherited_or_imported_scene(scene): return _fail("继承或导入场景不可安全追加外挂，请先创建本地包装")
	var placement: Node3D = node if node.has_meta("sea_placement") else assembly.placement_for(node)
	var container: Node3D = placement if placement != null else node
	var asset: Node3D = node
	if placement != null:
		var data: Dictionary = placement.get_meta("sea_placement", {})
		if data.get("kind", "") != "building": return _fail("外挂宿主只支持建筑 Placement，不支持植物")
		asset = placement.get_node_or_null("Asset") as Node3D
		if asset == null: return _fail("建筑缺少 Asset")
	elif node != scene and node.owner != scene:
		return _fail("外链内部节点或非本地节点不能追加外挂，请先创建本地包装")
	if container != scene and container.owner != scene: return _fail("宿主容器位于外链内部，请先创建本地包装")
	var instance_path := container.scene_file_path
	if container != scene and not instance_path.is_empty() and (not instance_path.begins_with("res://") or instance_path.contains("..") or instance_path.contains("\\") or not FileAccess.file_exists(instance_path)):
		return _fail("独立宿主外链根路径不安全或文件不存在；请先创建有效本地包装，不会重挂房屋")
	var declared_class := str(container.get_meta("building_class", ""))
	if not declared_class.is_empty() and not ["above_water", "underwater"].has(declared_class): return _fail("不支持的宿主 building_class：" + declared_class + "；请先创建显式本地包装")
	var current: Node = container
	while current != null:
		if current != scene and current.get_script() != null: return _fail("脚本设施或内部宿主不安全，请先创建无脚本的本地包装")
		if current != container and current != scene and not current.scene_file_path.is_empty(): return _fail("不能修改外链内部，请先创建本地包装")
		if current == scene: break
		current = current.get_parent()
	if asset.get_script() != null: return _fail("脚本设施宿主不安全，请先创建本地包装")
	if not Surface.valid_transform(container.global_transform) or not Surface.valid_transform(asset.global_transform): return _fail("宿主含奇异、镜像或非有限变换")
	var layer := container.get_node_or_null("Attachments")
	if layer != null and (not layer is Node3D or layer.get_script() != null or not layer.scene_file_path.is_empty() or layer.owner != scene): return _fail("现有 Attachments 不是安全本地层，请先整理本地包装")
	host_container = container
	host_asset = asset
	host_scene = scene
	cancel_arm(false)
	changed.emit()
	return _success({"ok": true, "reason": "", "host": container, "asset": asset}, "已锁定宿主：%s；只读真实可见三角面，非均匀父缩放以逆矩阵补偿保持世界尺寸" % container.name)

func _check_host() -> String:
	if not is_instance_valid(host_container) or not host_container.is_inside_tree() or not is_instance_valid(host_scene) or host_scene != _root(): return "宿主已删除或场景已切换，请重新锁定"
	if not workshop_context.is_empty():
		if host_container != host_scene: return "工坊宿主不属于当前预览 root"
		host_asset = _workshop_asset(host_scene)
		var layer := host_container.get_node_or_null("Attachments")
		if layer != null and (not layer is Node3D or layer.get_script() != null or not layer.scene_file_path.is_empty() or layer.owner != host_scene): return "预览 Attachments 已失效"
	elif host_container.has_meta("sea_placement"):
		host_asset = host_container.get_node_or_null("Asset") as Node3D
	if not is_instance_valid(host_asset) or not host_asset.is_inside_tree(): return "宿主 Asset 已失效"
	if not Surface.valid_transform(host_container.global_transform) or not Surface.valid_transform(host_asset.global_transform): return "宿主为奇异、镜像或非有限变换"
	return ""

func set_mount_options(mode: String, distance: float = 0.0, angle: float = 0.0) -> Dictionary:
	if not ["wall", "roof"].has(mode): return _fail("挂载面仅支持 wall/roof")
	if not is_finite(distance) or distance < 0.0 or distance > 0.5 or not is_finite(angle) or absf(angle) > 180.0: return _fail("离墙偏移限0..0.5m，绕法线角度限-180..180°")
	if armed and (mount_mode != mode or offset != distance or angle_degrees != angle):
		cancel_arm(false)
		message.emit("挂载设置已改变，贴面事务已取消；当前输入保留，请重新贴到宿主")
	mount_mode = mode
	offset = distance
	angle_degrees = angle
	return {"ok": true, "reason": ""}

func _mode(recipe: Dictionary) -> String:
	var entry: Dictionary = Catalog.get_entry(str(recipe.get("type_id", "")))
	return mount_mode if entry.get("mount_mode", "any") == "any" else str(entry.mount_mode)

func _hit(recipe: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	var reason := _check_host()
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	return Surface.raycast(host_asset, origin, direction, _mode(recipe))

func _uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func anchor_error(built: Dictionary) -> String:
	var values: Variant = built.get("mount_anchor", {}).get("basis")
	if not values is Array or values.size() != 9: return "mount_anchor.basis 缺失或不是9项矩阵，拒绝挂载"
	var identity := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	for index: int in 9:
		if not Recipe.number(values[index]) or float(values[index]) != identity[index]: return "当前仅支持单位 mount_anchor.basis；非单位锚点明确拒绝，未修改模型"
	return ""

func _build_trusted(recipe: Dictionary) -> Dictionary:
	var built: Dictionary = Generator.build(recipe)
	if not built.ok: return built
	var reason := anchor_error(built)
	if not reason.is_empty():
		built.root.free()
		return {"ok": false, "reason": reason}
	return built

func _anchor(built: Dictionary, mode: String) -> Vector3:
	var anchor: Dictionary = built.mount_anchor
	var native := _vector(anchor.position)
	if (mode == "wall" and anchor.name == "mount_back") or (mode == "roof" and anchor.name != "mount_back"): return native
	var bounds: Dictionary = built.stats.bounds
	var bottom := _vector(bounds.position)
	var size := _vector(bounds.size)
	return Vector3(bottom.x + size.x * 0.5, bottom.y + size.y * 0.5, bottom.z + size.z) if mode == "wall" else Vector3(bottom.x + size.x * 0.5, bottom.y, bottom.z + size.z * 0.5)

func _pose(built: Dictionary, hit: Dictionary, distance: float, angle: float) -> Transform3D:
	var normal: Vector3 = hit.normal
	var basis: Basis
	if hit.mode == "wall":
		var up := (Vector3.UP - normal * normal.dot(Vector3.UP)).normalized()
		var z := -normal
		basis = Basis(up.cross(z).normalized(), up, z)
	else:
		var forward := Vector3.FORWARD - normal * Vector3.FORWARD.dot(normal)
		if forward.length_squared() < 0.001: forward = Vector3.RIGHT - normal * Vector3.RIGHT.dot(normal)
		var z := -forward.normalized()
		basis = Basis(normal.cross(z).normalized(), normal, z)
	basis = Basis(normal, deg_to_rad(angle)) * basis
	return Transform3D(basis, hit.position + normal * (CLEARANCE + distance) - basis * _anchor(built, hit.mode))

func _metadata(recipe: Dictionary, built: Dictionary, hit: Dictionary, id: String) -> Dictionary:
	var inverse := host_asset.global_transform.affine_inverse()
	var normal: Vector3 = hit.normal
	return {"schema_version": 1, "recipe": recipe.duplicate(true), "instance_id": id, "instanceid": id,
		"host_path": str(host_scene.get_path_to(host_container)), "host_instance_id": str(host_container.get_meta("sea_placement", {}).get("instance_id", "")),
		"host_revision": str(host_container.get_meta("sea_placement", {}).get("revision", "local")),
		"anchor": {"mode": hit.mode, "mesh_path": str(hit.mesh_path), "surface": hit.surface, "triangle": hit.triangle,
			"host_position": _array(inverse * hit.position), "host_normal": _array((host_asset.global_basis.transposed() * normal).normalized()),
			"local_position": _array(_anchor(built, hit.mode)), "native": built.mount_anchor.duplicate(true),
			"declared_clearance_m": CLEARANCE, "offset_m": offset, "angle_degrees": float(hit.get("chain_angle", angle_degrees))}, "stats": built.stats.duplicate(true)}

func insert_at_ray(recipe: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty(): return _fail(reason)
	var hit: Dictionary = _chain_hit(recipe, origin, direction) if chain_active else _hit(recipe, origin, direction)
	if not hit.ok: return _fail(hit.reason)
	var built: Dictionary = _build_trusted(recipe)
	if not built.ok: return _fail(built.reason)
	var node: Node3D = built.root
	var installation := validate_installation(recipe, hit, built)
	if not installation.ok:
		node.free()
		return _fail(str(installation.reason))
	var id := _uuid()
	node.name = "Attachment_" + id
	node.set_meta(META, _metadata(recipe, built, hit, id))
	var layer := host_container.get_node_or_null("Attachments") as Node3D
	var new_layer := layer == null
	if new_layer:
		layer = Node3D.new()
		layer.name = "Attachments"
		layer.set_meta("visual_only", true)
	var parent_world := host_container.global_transform if new_layer else layer.global_transform
	if not Surface.valid_transform(parent_world):
		node.free()
		if new_layer: layer.free()
		return _fail("Attachments 层变换不可逆")
	node.transform = parent_world.affine_inverse() * (installation.pose as Transform3D)
	var previous := _selected_nodes()
	var undo: Object = _history()
	undo.create_action("新增建筑外挂", UndoRedo.MERGE_DISABLE, host_scene)
	if new_layer:
		layer.add_child(node)
		undo.add_do_method(self, "_attach", host_container, layer, host_scene, host_container.get_child_count())
		undo.add_undo_method(self, "_detach", host_container, layer)
		undo.add_do_reference(layer)
	else:
		undo.add_do_method(self, "_attach", layer, node, host_scene, layer.get_child_count())
		undo.add_undo_method(self, "_detach", layer, node)
		undo.add_do_reference(node)
	undo.add_do_method(self, "_select_nodes", [node])
	undo.add_undo_method(self, "_select_nodes", previous)
	undo.commit_action()
	return _success({"ok": true, "reason": "", "attachment": node, "root": node, "hit": hit, "stats": built.stats}, "外挂已贴到真实宿主面；随建筑作品保存" if not workshop_context.is_empty() else "外挂已贴到真实宿主面；场景由 Ctrl+S 手动保存")

func select_attachment(node: Node) -> Dictionary:
	var target := attachment_for(node)
	selection_will_change(target)
	if target == null:
		selected = null
		changed.emit()
		return {"ok": false, "reason": "未选中外挂"}
	var changed_target := selected != target
	selected = target
	if changed_target:
		var anchor: Dictionary = target.get_meta(META).anchor
		mount_mode = str(anchor.mode)
		offset = float(anchor.offset_m)
		angle_degrees = float(anchor.angle_degrees)
	var container := target.get_parent().get_parent()
	if container != host_container or host_scene != _root():
		var result := set_host(container)
		if not result.ok: return result
	changed.emit()
	return {"ok": true, "reason": "", "attachment": target, "recipe": target.get_meta(META).recipe.duplicate(true)}

func _check_selected() -> String:
	if not is_instance_valid(selected) or not selected.is_inside_tree() or attachment_for(selected) != selected or not selected.has_meta(META): return "请先选择一个独立外挂"
	if selected.owner != _root(): return "外挂不属于当前本地场景"
	if selected.get_parent() == null or selected.get_parent().name != "Attachments" or selected.get_parent().get_parent() != host_container: return "所选外挂与锁定宿主不一致，请重新锁定"
	if not Surface.valid_transform(selected.get_parent().global_transform): return "外挂层含奇异、镜像或非有限变换"
	return _check_host()

func _merge_recipe(base: Dictionary, patch: Dictionary) -> Dictionary:
	var candidate := base.duplicate(true)
	for key: Variant in patch:
		if key == "dimensions" and patch[key] is Dictionary:
			candidate.dimensions.merge(patch[key], true)
		else: candidate[key] = patch[key]
	return candidate

func edit_selected_recipe(patch: Dictionary) -> Dictionary:
	var reason := _check_selected()
	if not reason.is_empty(): return _fail(reason)
	var data: Dictionary = selected.get_meta(META).duplicate(true)
	var candidate := _merge_recipe(data.recipe, patch)
	if Catalog.get_entry(str(candidate.get("type_id", ""))).get("mount_mode", "") == "any" and mount_mode != str(data.anchor.mode):
		return _fail("挂载面已改变，请重新贴合选择新表面；当前输入与原模型保持")
	var built: Dictionary = _build_trusted(candidate)
	if not built.ok: return _fail(built.reason)
	var next: Node3D = built.root
	next.name = selected.name
	var mode: String = str(data.anchor.mode)
	if Catalog.get_entry(candidate.type_id).mount_mode != "any" and Catalog.get_entry(candidate.type_id).mount_mode != mode:
		next.free()
		return _fail("更改类型需重新选择真实挂载面；请使用图库新增")
	var world := selected.global_transform
	if not Surface.valid_transform(world):
		next.free()
		return _fail("外挂当前变换不可逆或镜像")
	var old_anchor := _vector(data.anchor.local_position)
	var new_anchor := _anchor(built, mode)
	var normal := (-world.basis.z if mode == "wall" else world.basis.y).normalized()
	var old_angle := float(data.anchor.angle_degrees)
	var delta_rotation := Basis(normal, deg_to_rad(angle_degrees - old_angle))
	var next_basis := delta_rotation * world.basis
	var anchor_world := world * old_anchor
	world = Transform3D(next_basis, anchor_world + normal * (offset - float(data.anchor.offset_m)) - next_basis * new_anchor)
	var profile := _profile_for(candidate, mode, built)
	var installation: Dictionary = Surface.validate_installation(host_asset, profile, world, normal, mode, CLEARANCE + offset)
	if not installation.ok:
		next.free()
		return _fail(str(installation.reason))
	next.transform = selected.get_parent().global_transform.affine_inverse() * world
	data.recipe = candidate.duplicate(true)
	data.stats = built.stats.duplicate(true)
	data.anchor.local_position = _array(new_anchor)
	data.anchor.native = built.mount_anchor.duplicate(true)
	data.anchor.offset_m = offset
	data.anchor.angle_degrees = angle_degrees
	next.set_meta(META, data)
	return _replace_selected(next, "编辑建筑外挂")

func _replace_selected(next: Node3D, action: String) -> Dictionary:
	var old := selected
	var parent := old.get_parent()
	var scene := _root()
	var index := old.get_index()
	var undo: Object = _history()
	undo.create_action(action, UndoRedo.MERGE_DISABLE, scene)
	undo.add_do_method(self, "_replace", parent, old, next, scene, index)
	undo.add_undo_method(self, "_replace", parent, next, old, scene, index)
	undo.add_do_reference(next)
	undo.add_undo_reference(old)
	undo.commit_action()
	return _success({"ok": true, "reason": "", "attachment": next, "root": next, "recipe": next.get_meta(META).recipe.duplicate(true), "stats": next.get_meta(META).stats.duplicate(true)}, "已更新独立外挂；撤销恢复原节点，不重新生成")

func duplicate_selected() -> Dictionary:
	var reason := _check_selected()
	if not reason.is_empty(): return _fail(reason)
	var node := selected.duplicate() as Node3D
	var data: Dictionary = selected.get_meta(META).duplicate(true)
	var id := _uuid()
	node.name = "Attachment_" + id
	data.instance_id = id
	data.instanceid = id
	node.set_meta(META, data)
	var parent := selected.get_parent()
	var previous := selected
	var undo: Object = _history()
	undo.create_action("复制建筑外挂", UndoRedo.MERGE_DISABLE, _root())
	undo.add_do_method(self, "_attach", parent, node, _root(), parent.get_child_count())
	undo.add_do_method(self, "_select_nodes", [node])
	undo.add_undo_method(self, "_detach", parent, node)
	undo.add_undo_method(self, "_select_nodes", [previous])
	undo.add_do_reference(node)
	undo.commit_action()
	return _success({"ok": true, "reason": "", "attachment": node}, "已复制，保持变换；可用原生 gizmo 移动后显式重新贴合")

func delete_selected() -> Dictionary:
	var reason := _check_selected()
	if not reason.is_empty(): return _fail(reason)
	var node := selected
	var parent := node.get_parent()
	var index := node.get_index()
	var undo: Object = _history()
	undo.create_action("删除建筑外挂", UndoRedo.MERGE_DISABLE, _root())
	undo.add_do_method(self, "_detach", parent, node)
	undo.add_do_method(self, "_select_nodes", [])
	undo.add_undo_method(self, "_attach", parent, node, _root(), index)
	undo.add_undo_method(self, "_select_nodes", [node])
	undo.add_undo_reference(node)
	undo.commit_action()
	return _success({"ok": true, "reason": ""}, "已删除外挂，可撤销")

func reproject_selected(origin: Vector3, direction: Vector3) -> Dictionary:
	var reason := _check_selected()
	if not reason.is_empty(): return _fail(reason)
	var data: Dictionary = selected.get_meta(META)
	var hit := _hit(data.recipe, origin, direction)
	if not hit.ok: return _fail(hit.reason)
	var built: Dictionary = _build_trusted(data.recipe)
	if not built.ok: return _fail(built.reason)
	var next: Node3D = built.root
	var installation := validate_installation(data.recipe, hit, built)
	if not installation.ok:
		next.free()
		return _fail(str(installation.reason))
	next.name = selected.name
	next.transform = selected.get_parent().global_transform.affine_inverse() * installation.pose
	next.set_meta(META, _metadata(data.recipe, built, hit, data.instance_id))
	return _replace_selected(next, "重新贴合建筑外挂")

func supports_chain(recipe: Dictionary) -> bool:
	var kind: String = str(recipe.get("type_id", ""))
	return not workshop_context.is_empty() and (kind in CHAIN_SHELTERS or (CHAIN_PORTS.has(kind) and recipe.get("condition") == "fresh"))

func arm_chain(recipe: Dictionary, from_selected: bool = true) -> Dictionary:
	if not supports_chain(recipe): return _fail("此组件没有可连续衔接的边或完整管口")
	var result := arm(recipe)
	if result.ok:
		chain_active = true
		_chain_has_anchor = from_selected and is_instance_valid(selected)
		message.emit("连续衔接：将指针移向选中件的可用端口或侧边；点击确认，Esc 结束。" if _chain_has_anchor else "连续衔接：先点实面放首段，随后可连续接长。Esc 或右键结束。")
	return result

# 端点取可信原生生成的收心后局部几何，不用 nominal 尺寸模拟管口。
func chain_ports(recipe: Dictionary) -> Array:
	if not supports_chain(recipe): return []
	var key := JSON.stringify(recipe).sha256_text()
	if _chain_ports_cache.has(key): return _chain_ports_cache[key]
	var built := _build_trusted(recipe)
	if not built.ok: return []
	var result: Array = []
	if str(recipe.type_id) in CHAIN_SHELTERS:
		var bounds: Dictionary = built.stats.bounds
		var lo := _vector(bounds.position)
		var dim := _vector(bounds.size)
		for side: int in [-1, 1]:
			result.append({"position": Vector3(lo.x if side < 0 else lo.x + dim.x, lo.y, 0), "direction": Vector3.RIGHT * side, "size": 0.0})
	else:
		for descriptor: Array in CHAIN_PORTS[recipe.type_id]:
			for part: Dictionary in built.source_parts:
				if part.name != descriptor[0] or int(part.get("missing_sectors", 0)) != 0: continue
				var side: int = descriptor[1]
				var axis := Basis.from_euler(_vector(part.rotation_euler)).y.normalized() * side
				result.append({"position": _vector(part.center) + axis * float(part.dimensions[1]) * 0.5,
					"direction": axis, "size": float(part.d_bottom if side < 0 else part.d_top)})
				break
	built.root.free()
	if _chain_ports_cache.size() >= 16: _chain_ports_cache.erase(_chain_ports_cache.keys()[0])
	_chain_ports_cache[key] = result
	return result

func _chain_hit(recipe: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	if not _chain_has_anchor: return _hit(recipe, origin, direction)
	if not is_instance_valid(selected): return {"ok": false, "reason": "续接起点已失效，请重新选择"}
	var data: Dictionary = selected.get_meta(META, {})
	var anchor: Dictionary = data.get("anchor", {})
	var source: Dictionary = data.get("recipe", {})
	var mode: String = _mode(recipe)
	var shelter: bool = str(recipe.type_id) in CHAIN_SHELTERS
	if anchor.get("mode") != mode or (shelter and source.get("type_id") != recipe.type_id) or (not shelter and not CHAIN_PORTS.has(source.get("type_id"))):
		return {"ok": false, "reason": "选中件与待接组件的挂载面或接口不兼容"}
	var profile := _profile_for(recipe, mode)
	if not profile.ok: return profile
	var hit := _hit(recipe, origin, direction)
	if not hit.ok: return hit
	var normal: Vector3 = (host_asset.global_basis.inverse().transposed() * _vector(anchor.host_normal)).normalized()
	var surface_point: Vector3 = host_asset.global_transform * _vector(anchor.host_position)
	if normal.dot(hit.normal) < 0.999 or absf(normal.dot(hit.position - surface_point)) > 0.004:
		return {"ok": false, "reason": "接长只沿同一连续实墙或屋面，不能跨转角或台阶"}
	var ports: Array = chain_ports(source)
	var candidate_ports: Array = chain_ports(recipe)
	var best: Dictionary = {}
	var best_score := INF
	var zero_pose := _pose(profile.source, hit, offset, 0.0)
	for target: Dictionary in ports:
		var world_port: Vector3 = selected.global_transform * (target.position as Vector3)
		var outward: Vector3 = (selected.global_basis * (target.direction as Vector3)).normalized()
		var outward_flat: Vector3 = outward.slide(normal).normalized()
		if outward_flat.length_squared() < 0.5: continue
		var pointer: Vector3 = hit.position - (world_port - normal * normal.dot(world_port - surface_point))
		# 以指向哪一侧为主；允许将鼠标移动到下一段所在处，而非必须点中管口像素。
		if pointer.dot(outward_flat) < -0.07 or pointer.length() > 12.0 or (pointer - outward_flat * pointer.dot(outward_flat)).length() > CHAIN_SNAP_RADIUS: continue
		for incoming: Dictionary in candidate_ports:
			var angle := float(anchor.angle_degrees)
			if not shelter:
				var port_size: float = float(target.size)
				if absf(port_size - float(incoming.size)) > port_size * 0.14: continue
				var inward_zero: Vector3 = zero_pose.basis * (incoming.direction as Vector3)
				var flat: Vector3 = inward_zero.slide(normal).normalized()
				if flat.length_squared() < 0.5: continue
				angle = rad_to_deg(flat.signed_angle_to(-outward_flat, normal))
			var basis := Basis(normal, deg_to_rad(angle)) * zero_pose.basis
			if (basis * (incoming.direction as Vector3)).dot(outward) > -0.998: continue
			var attachment_origin: Vector3 = world_port + outward * (0.002 if shelter else 0.001) - basis * (incoming.position as Vector3)
			var center: Vector3 = attachment_origin + basis * _anchor(profile.source, mode) - normal * (CLEARANCE + offset)
			if absf(normal.dot(center - surface_point)) > 0.003: continue
			var score: float = pointer.length_squared() + absf(wrapf(angle - float(anchor.angle_degrees), -180.0, 180.0)) * 0.0001
			if score >= best_score: continue
			best_score = score
			best = {"center": center, "angle": angle}
	if best.is_empty(): return {"ok": false, "reason": "没有对齐的接口；请移向可用管口或同一棚侧，尺寸、离面距离和方向不得自动改动"}
	var snapped: Dictionary = Surface.raycast(host_asset, (best.center as Vector3) + normal * 0.005, -normal, mode)
	if not snapped.ok or snapped.normal.dot(normal) < 0.999 or absf(float(snapped.distance) - 0.005) > 0.003:
		return {"ok": false, "reason": "接头位置没有连续实面支承；不能跨洞口、玻璃或转角"}
	snapped.chain_angle = best.angle
	return snapped

func preview_at_ray(recipe: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var hit: Dictionary = _chain_hit(recipe, origin, direction) if chain_active else _hit(recipe, origin, direction)
	if not hit.ok: return hit
	var installation := validate_installation(recipe, hit)
	if not installation.ok: return installation
	hit.pose = installation.pose
	hit.support_checks = installation.support_checks
	return hit

func _selection_token() -> Array[int]:
	var ids: Array[int] = []
	for node: Node in _selected_nodes():
		var attachment_node := attachment_for(node)
		ids.append((attachment_node if attachment_node != null else node).get_instance_id())
	ids.sort()
	return ids

func _node_token(node: Node) -> Dictionary:
	return {"ref": weakref(node), "path": _root().get_path_to(node), "local": node.transform if node is Node3D else Transform3D.IDENTITY,
		"world": node.global_transform if node is Node3D else Transform3D.IDENTITY, "placement": node.get_meta("sea_placement", {}).duplicate(true),
		"attachment": node.get_meta(META, {}).duplicate(true), "scene_path": node.scene_file_path, "owner_id": node.owner.get_instance_id() if node.owner != null else 0}

func _geometry_state(node: Node, state: Array, full: bool) -> void:
	state.append([node.get_instance_id(), str(node.name), node.transform if node is Node3D else Transform3D.IDENTITY, node.visible if node is Node3D else true, node.get_meta("geometry_fingerprint", "")])
	if node is MeshInstance3D and node.mesh != null:
		state.append([node.mesh.get_instance_id(), node.mesh.get_surface_count(), node.material_override.get_instance_id() if node.material_override != null else 0])
		for surface: int in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			state.append(material.get_instance_id() if material != null else 0)
			if full: state.append(node.mesh.surface_get_arrays(surface))
	for child: Node in node.get_children(): _geometry_state(child, state, full)

func _geometry_token(node: Node, full: bool) -> String:
	var state: Array = []
	_geometry_state(node, state, full)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(state))
	return context.finish().hex_encode()

func _context_reason(full: bool = false, check_geometry: bool = true) -> String:
	if _arm_context.is_empty(): return "没有有效的贴面事务"
	var host_reason := _check_host()
	if not host_reason.is_empty(): return host_reason
	var scene: Node = _arm_context.scene.get_ref()
	if scene == null or scene != _root() or not scene.is_inside_tree() or scene.scene_file_path != _arm_context.scene_path: return "场景已切换、关闭或路径改变"
	for token: Dictionary in _arm_context.nodes:
		var node: Node = token.ref.get_ref()
		if node == null or not node.is_inside_tree() or (node != scene and not scene.is_ancestor_of(node)): return "宿主或目标已删除/移出场景"
		if scene.get_path_to(node) != token.path or node.scene_file_path != token.scene_path: return "宿主或目标路径/外链改变"
		if (node.owner.get_instance_id() if node.owner != null else 0) != token.owner_id: return "节点所有者已改变"
		if node is Node3D and (node.transform != token.local or node.global_transform != token.world): return "宿主或目标变换已改变"
		if node.get_meta("sea_placement", {}) != token.placement or node.get_meta(META, {}) != token.attachment: return "宿主 revision 或外挂 metadata 已改变"
	if host_container != _arm_context.host.get_ref() or host_asset != _arm_context.asset.get_ref(): return "锁定宿主或预览生成根已改变"
	if host_container.get_node_or_null("Attachments") != (_arm_context.layer.get_ref() if _arm_context.layer != null else null): return "外挂层已新增、删除或替换"
	if _selection_token() != _arm_context.selection: return "编辑器选择已改变，请重新启用贴面"
	if selected != (_arm_context.target.get_ref() if _arm_context.target != null else null): return "选择已改变，请重新启用贴面"
	if mount_mode != _arm_context.mode or offset != _arm_context.offset or angle_degrees != _arm_context.angle: return "挂载选项已改变，请重新启用贴面"
	if armed_recipe != _arm_context.recipe: return "待放置配方已改变，请重新启用贴面"
	if check_geometry and _geometry_token(host_asset, false) != _arm_context.quick_geometry: return "宿主层级、可见性、网格或变换已改变"
	if full and _geometry_token(host_asset, true) != _arm_context.geometry: return "宿主真实网格数据已改变"
	if _arm_context.target != null:
		var target: Node = _arm_context.target.get_ref()
		if full and _geometry_token(target, true) != _arm_context.target_geometry: return "原选中外挂几何已改变"
	return ""

func validate_arm(token: int = 0, full: bool = true) -> Dictionary:
	if not armed: return {"ok": false, "reason": "贴面已取消或未启用"}
	# 旧拖放事件不得取消用户随后新启用的事务。
	if token != 0 and token != _arm_serial: return {"ok": false, "reason": "拖放事务已失效"}
	var reason := _context_reason(full)
	if not reason.is_empty():
		cancel_arm(false)
		return _fail("贴面上下文已过期并取消：" + reason + "；原节点和输入保持")
	return {"ok": true, "reason": "", "token": _arm_serial}

func arm(recipe: Dictionary, reproject: bool = false) -> Dictionary:
	if not _ui_active: return _fail("外挂界面已隐藏，请返回工坊后再贴面")
	var reason: String = _check_selected() if reproject else _check_host()
	if reason.is_empty(): reason = Recipe.validate(recipe)
	if not reason.is_empty(): return _fail(reason)
	if reproject and recipe != selected.get_meta(META).recipe: return _fail("重新贴合只接受目标已提交配方；请先应用或放弃输入")
	cancel_arm(false)
	_arm_serial += 1
	var scene := _root()
	var nodes: Array[Dictionary] = [_node_token(scene), _node_token(host_container), _node_token(host_asset)]
	var layer: Node = host_container.get_node_or_null("Attachments")
	if layer != null: nodes.append(_node_token(layer))
	if is_instance_valid(selected): nodes.append(_node_token(selected))
	_arm_context = {"scene": weakref(scene), "scene_path": scene.scene_file_path, "selection": _selection_token(), "nodes": nodes, "host": weakref(host_container), "asset": weakref(host_asset),
		"target": weakref(selected) if is_instance_valid(selected) else null, "layer": weakref(layer) if layer != null else null, "mode": mount_mode, "offset": offset, "angle": angle_degrees,
		"recipe": recipe.duplicate(true), "geometry": _geometry_token(host_asset, true), "quick_geometry": _geometry_token(host_asset, false),
		"target_geometry": _geometry_token(selected, true) if is_instance_valid(selected) else ""}
	armed_recipe = recipe.duplicate(true)
	armed = true
	set_meta("reproject", reproject)
	set_meta("dragging", false)
	_request_arm()
	return _success({"ok": true, "reason": "", "token": _arm_serial}, "已锁定贴面事务；另选会取消。点击真实宿主面确认，Escape/右键取消")

func viewportclick_place(origin: Vector3, direction: Vector3) -> Dictionary:
	var valid := validate_arm()
	if not valid.ok: return valid
	var continuing := chain_active and not bool(get_meta("dragging", false))
	var next_recipe := armed_recipe.duplicate(true) if continuing else {}
	_confirming = true
	var result := reproject_selected(origin, direction) if bool(get_meta("reproject", false)) else insert_at_ray(armed_recipe, origin, direction)
	_confirming = false
	if result.ok:
		cancel_arm(false)
		if continuing and arm_chain(next_recipe).ok:
			message.emit("已接上一段；指向新段的另一端继续，Esc 或右键结束。")
	return result

func cancel_arm(announce: bool = true) -> void:
	var was_chain := chain_active
	chain_active = false
	_chain_has_anchor = false
	armed = false
	armed_recipe.clear()
	_arm_context.clear()
	set_meta("dragging", false)
	_cancel_arm_ui()
	if announce: message.emit("已结束衔接；已确认段保留，末段可撤销。" if was_chain else "已取消贴面，场景未改动")

func selection_will_change(target: Node3D) -> void:
	if armed and not _confirming and target != selected:
		cancel_arm(false)
		message.emit("选择已改变，原贴面事务已取消；未应用输入与场景保持")

func bind_candidate_defaults(type_id: String) -> Dictionary:
	var recipe: Dictionary = Recipe.defaults(type_id)
	if recipe.is_empty(): return _fail("未知外挂类型")
	_candidate_id = type_id + "_" + _uuid().substr(0, 16)
	_candidate_source = ""
	recipe.attachment_id = _candidate_id
	return {"ok": true, "reason": "", "recipe": recipe}

func save_candidate(recipe: Dictionary, base_dir: String = Store.DEFAULT_BASE) -> Dictionary:
	var checked := _build_trusted(recipe)
	if not checked.ok: return _fail(str(checked.reason))
	checked.root.free()
	var result: Dictionary = Store.export_revision(recipe, base_dir)
	if result.ok:
		_candidate_id = recipe.attachment_id
		_candidate_source = result.recipe_path
		message.emit("候选另存新修订：%s；未覆盖、未正式登记，场景仍需手动保存" % result.directory)
	else: message.emit(str(result.reason))
	return result

func load_candidate(path: String) -> Dictionary:
	var result: Dictionary = Store.load_recipe(path)
	if not result.ok: return _fail(str(result.reason))
	var built: Dictionary = _build_trusted(result.recipe)
	if not built.ok: return _fail(str(built.reason))
	built.root.free()
	_candidate_id = result.recipe.attachment_id
	_candidate_source = path
	return _success(result, "已校验候选 hashes 并从 JSON 重建；未加载候选 TSCN，尚未修改场景")

func revision_warning(node: Node3D) -> String:
	var layer := node.get_node_or_null("Attachments")
	if layer == null or layer.get_child_count() == 0: return ""
	return "\n宿主已换版：外挂层及全部子变换保持；请检查贴合，必要时显式重新贴合。"

func _attach(parent: Node, node: Node, scene: Node, index: int) -> void:
	parent.add_child(node)
	parent.move_child(node, mini(index, parent.get_child_count() - 1))
	_owners(node, scene)

func _owners(node: Node, scene: Node) -> void:
	node.owner = scene
	for child in node.get_children(): _owners(child, scene)

func _detach(parent: Node, node: Node) -> void:
	parent.remove_child(node)

func _replace(parent: Node, old: Node3D, next: Node3D, scene: Node, index: int) -> void:
	parent.remove_child(old)
	_attach(parent, next, scene, index)
	_select_nodes([next])
