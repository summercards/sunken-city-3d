@tool
extends Control

const Generator = preload("res://src/building_attachments/generator.gd")
var assembly: EditorPlugin
var viewport_index: int
var _ghost: Node3D
var _ghost_build: Dictionary = {}
var _ghost_key := ""
var _cursor := Vector2.ZERO
var _preview_ok := false
var _last_preview_reason := ""

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	set_meta("can_drop_seen", true)
	if not data is Dictionary: return false
	if data.get("type", "") == "sea_building_attachment":
		if not data.get("recipe") is Dictionary: return false
		var valid: Dictionary = assembly.attachment_controller.validate_arm(int(data.get("arm_token", -1)), false)
		if not valid.ok: return false
		if data.recipe != assembly.attachment_controller.armed_recipe:
			assembly.attachment_controller.cancel_arm(false)
			assembly.attachment_controller.message.emit("拖放配方与已锁定事务不一致，已拒绝并取消")
			return false
		_preview(data.recipe, at_position)
		return assembly.can_insert() and is_instance_valid(assembly.attachment_controller.host_container)
	return data.get("type", "") == "sea_scene_candidate" and assembly.can_insert()

func _ray(at_position: Vector2) -> Dictionary:
	var viewport := EditorInterface.get_editor_viewport_3d(viewport_index)
	if viewport == null or size.x <= 0 or size.y <= 0: return {}
	var camera := viewport.get_camera_3d()
	if camera == null: return {}
	var point := at_position * Vector2(viewport.size) / size
	return {"origin": camera.project_ray_origin(point), "direction": camera.project_ray_normal(point), "camera": camera}

func _drop_data(at_position: Vector2, data: Variant) -> void:
	set_meta("drop_seen", true)
	if not _can_drop_data(at_position, data): return
	var ray := _ray(at_position)
	if ray.is_empty(): return
	if data.get("type", "") == "sea_building_attachment":
		var valid: Dictionary = assembly.attachment_controller.validate_arm(int(data.get("arm_token", -1)))
		if valid.ok: assembly.attachment_controller.viewportclick_place(ray.origin, ray.direction)
		clear_attachment_preview()
		return
	var hit: Variant = Plane(Vector3.UP, assembly.drop_height.value).intersects_ray(ray.origin, ray.direction)
	if hit == null:
		assembly.report("视线与放置平面平行或背向，请调整视角。")
		return
	assembly.insert_candidate(data.entry, hit)

func _gui_input(event: InputEvent) -> void:
	var controller: Node = assembly.attachment_controller
	if not controller.armed: return
	if event is InputEventMouseMotion:
		_preview(controller.armed_recipe, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var ray := _ray(event.position)
		if not ray.is_empty(): controller.viewportclick_place(ray.origin, ray.direction)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		controller.cancel_arm()
		accept_event()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(assembly) or not is_instance_valid(assembly.attachment_controller): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and assembly.attachment_controller.armed:
		assembly.attachment_controller.cancel_arm()
		get_viewport().set_input_as_handled()

func _preview(recipe: Dictionary, at_position: Vector2) -> void:
	_cursor = at_position
	_preview_ok = false
	var ray := _ray(at_position)
	if ray.is_empty(): return
	var controller: Node = assembly.attachment_controller
	var valid: Dictionary = controller.validate_arm(0, false)
	if not valid.ok:
		clear_attachment_preview()
		return
	var hit: Dictionary = controller.preview_at_ray(recipe, ray.origin, ray.direction)
	if not hit.ok:
		if is_instance_valid(_ghost): _ghost.hide()
		tooltip_text = str(hit.reason)
		if _last_preview_reason != str(hit.reason): controller.message.emit(str(hit.reason))
		_last_preview_reason = str(hit.reason)
		queue_redraw()
		return
	var key := JSON.stringify(recipe).sha256_text()
	if key != _ghost_key or not is_instance_valid(_ghost):
		clear_attachment_preview()
		_ghost_build = controller._build_trusted(recipe)
		if not _ghost_build.ok:
			controller.message.emit(str(_ghost_build.reason))
			return
		_ghost = _ghost_build.root
		_ghost_key = key
		# 临时预览不进入编辑场景；仅禁用预览体碰撞层，保留 Generator 层级与实际场景碰撞。
		for node in _ghost.find_children("*", "StaticBody3D", true, false):
			node.collision_layer = 0
			node.collision_mask = 0
		for mesh in _ghost.find_children("*", "MeshInstance3D", true, false):
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(0.2, 0.9, 0.8, 0.4)
			material.no_depth_test = false
			mesh.material_override = material
		EditorInterface.get_editor_viewport_3d(viewport_index).add_child(_ghost)
	_last_preview_reason = ""
	_ghost.global_transform = hit.pose
	_ghost.show()
	_preview_ok = true
	tooltip_text = "真实表面有效，点击放置；Escape 取消"
	queue_redraw()

func clear_attachment_preview() -> void:
	if is_instance_valid(_ghost): _ghost.free()
	_ghost = null
	_ghost_key = ""
	_ghost_build.clear()
	_preview_ok = false
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(assembly) or not is_instance_valid(assembly.attachment_controller) or not assembly.attachment_controller.armed: return
	var color := Color(0.2, 0.95, 0.75) if _preview_ok else Color(1.0, 0.5, 0.25)
	draw_arc(_cursor, 9, 0, TAU, 24, color, 2)
	draw_line(_cursor - Vector2(14, 0), _cursor + Vector2(14, 0), color)
	draw_line(_cursor - Vector2(0, 14), _cursor + Vector2(0, 14), color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_attachment_preview()
		if is_instance_valid(assembly) and is_instance_valid(assembly.attachment_controller):
			if bool(assembly.attachment_controller.get_meta("dragging", false)): assembly.attachment_controller.cancel_arm(false)
		if not is_instance_valid(assembly) or not is_instance_valid(assembly.attachment_controller) or not assembly.attachment_controller.armed: hide()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		clear_attachment_preview()
	elif what == NOTIFICATION_EXIT_TREE:
		clear_attachment_preview()
