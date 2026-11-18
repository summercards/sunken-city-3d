@tool
extends RefCounted
## 预览输入只协调放置、拾取和临时显示，不写作品节点。

const Generator = preload("res://src/building_attachments/generator.gd")
const Surface = preload("res://addons/scene_assembly/attachment_surface.gd")
var preview: Control
var controller: Node
var select: Callable
var ghost: Node3D
var _green: StandardMaterial3D
var _red: StandardMaterial3D
var _armed_press := false

func configure(view: Control, target: Node, selection: Callable) -> void:
	preview = view
	controller = target
	select = selection
	_green = _material(Color(0.25, 0.95, 0.55, 0.42))
	_red = _material(Color(1.0, 0.23, 0.19, 0.42))

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material

func cancel() -> void:
	_armed_press = false
	if is_instance_valid(ghost): ghost.free()
	ghost = null

func arm() -> void:
	cancel()
	var built: Dictionary = Generator.build(controller.armed_recipe)
	if not built.get("ok", false): return
	ghost = built.root
	ghost.name = "AttachmentGhost"
	preview.get_temporary_root().add_child(ghost)
	ghost.hide()
	for node: Node in ghost.find_children("*", "CollisionShape3D", true, false):
		node.disabled = true
	_paint(_red)

func _paint(material: Material) -> void:
	if not is_instance_valid(ghost): return
	for node: Node in ghost.find_children("*", "MeshInstance3D", true, false):
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_ghost(position: Vector2) -> Dictionary:
	var ray: Dictionary = preview.ray_from_local_position(position)
	if ray.is_empty(): return {"ok": false, "reason": "预览射线尚未就绪"}
	var result: Dictionary = controller.preview_at_ray(controller.armed_recipe, ray.origin, ray.direction)
	if is_instance_valid(ghost):
		var pose: Variant = result.get("pose")
		# 无支撑但有候选姿态时显示红色；完全未命中则隐藏，不沿用旧绿色。
		ghost.visible = pose is Transform3D
		if pose is Transform3D: ghost.global_transform = pose
		_paint(_green if result.get("ok", false) else _red)
	return result

func drag_finished(successful: bool) -> void:
	if not bool(controller.get_meta("dragging", false)): return
	controller.set_meta("dragging", false)
	if successful:
		if controller.armed: controller.cancel_arm(false)
	else:
		# 引擎先尝试 drop 再广播结束；失败不重放、不插入，也不把失败伪装成取消成功。
		_armed_press = false
		hide_ghost()
		controller.message.emit("拖放未被视口接受，作品未改动；输入保持，可重新拖放、点击真实表面或显式取消。")

func hide_ghost() -> void:
	if is_instance_valid(ghost): ghost.hide()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and controller.armed:
		controller.cancel_arm()
		return true
	if event is InputEventMouseMotion and controller.armed:
		update_ghost(event.position)
		return false
	if not event is InputEventMouseButton: return false
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and controller.armed:
		controller.cancel_arm()
		# 取消不吞右键，继续进入原有飞行导航。
		return false
	if event.button_index != MOUSE_BUTTON_LEFT: return false
	if event.pressed and controller.armed:
		_armed_press = true
		return true
	if not event.pressed and _armed_press:
		_armed_press = false
		if controller.armed:
			var ray: Dictionary = preview.ray_from_local_position(event.position)
			if not ray.is_empty(): controller.viewportclick_place(ray.origin, ray.direction)
		return true
	return false

func pick(position: Vector2) -> bool:
	var ray: Dictionary = preview.ray_from_local_position(position)
	if ray.is_empty(): return false
	var nearest := _distance(preview.get_host_asset(), ray.origin, ray.direction)
	var chosen: Node3D
	var layer: Node3D = preview.get_attachment_root()
	for node: Node in layer.get_children():
		var distance := _distance(node, ray.origin, ray.direction)
		if distance < nearest:
			nearest = distance
			chosen = node as Node3D
	if chosen != null:
		select.call([chosen])
		return true
	select.call([])
	return false

func _distance(root: Node3D, origin: Vector3, direction: Vector3) -> float:
	var nearest := INF
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: meshes.push_front(root)
	for node: Node in meshes:
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree(): continue
		var inverse := instance.global_transform.affine_inverse()
		var local_origin := inverse * origin
		var local_direction := inverse.basis * direction
		if instance.get_aabb().intersects_ray(local_origin, local_direction) == null: continue
		for surface: int in instance.mesh.get_surface_count():
			if instance.mesh is ArrayMesh and instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var cull: Dictionary = Surface.material_cull(instance.get_active_material(surface))
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			if arrays.is_empty(): continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for index: int in range(0, count - 2, 3):
				var a: Vector3 = vertices[indices[index] if not indices.is_empty() else index]
				var b: Vector3 = vertices[indices[index + 1] if not indices.is_empty() else index + 1]
				var c: Vector3 = vertices[indices[index + 2] if not indices.is_empty() else index + 2]
				var normal: Vector3 = instance.global_basis.inverse().transposed() * (c - a).cross(b - a)
				var facing := normal.dot(direction)
				if cull.get("ok", false) and ((cull.mode == "back" and facing >= 0.0) or (cull.mode == "front" and facing <= 0.0)): continue
				var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction, a, b, c)
				if hit != null: nearest = minf(nearest, origin.distance_to(instance.global_transform * (hit as Vector3)))
	return nearest

func can_drop(position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type") != "sea_building_attachment": return false
	if not controller.armed or data.get("recipe") != controller.armed_recipe: return false
	var valid: Dictionary = controller.validate_arm(int(data.get("arm_token", 0)), false)
	return valid.get("ok", false) and update_ghost(position).get("ok", false)

func drop(position: Vector2, data: Variant) -> Dictionary:
	if not can_drop(position, data): return {"ok": false, "reason": "落点或拖放事务无效；作品保持"}
	var ray: Dictionary = preview.ray_from_local_position(position)
	return controller.viewportclick_place(ray.origin, ray.direction)
