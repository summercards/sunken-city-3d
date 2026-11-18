@tool
extends SubViewportContainer
## 独立编辑器预览；不加载运行版预览、主场景或 Autoload。

signal slot_selected(slot_id: String)
signal view_changed

var viewport: SubViewport
var camera: Camera3D
var _world: Node3D
var _model_root: Node3D
var _work_root: Node3D
var _attachment_root: Node3D
var _temporary_root: Node3D
var _attachment_highlight: Node3D
var _selected_attachment: Node3D
var attachment_input: RefCounted
var surface_paint_input: RefCounted
var _surface_paint_root: Node3D
var _surface_paint_space: Node3D
var attachment_receiver: Control
var _attachment_drag_trace: Array[Dictionary] = []
var _attachment_drag_checks := 0
var _highlight_root: Node3D
var _wireframe_root: Node3D
var _collision_root: Node3D
var _wire_material_instance: StandardMaterial3D
var _overlay_material_instance: StandardMaterial3D
var _slots: Array = []
# 仅供射线精筛的内存几何，不创建源壳节点或写入 metadata。
var _semantic_sources: Dictionary = {}
var _building_id: String = ""
var _camera_fitted: bool = false
var _initial_frame_pending: bool = false
var _selected_id: String = ""
var _dragging: bool = false
var _navigation_button: int = 0
var _move_keys: Dictionary = {}
var _last_mouse: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _yaw: float = 0.65
var _pitch: float = -0.42
var _distance: float = 26.0
var _target: Vector3 = Vector3.ZERO
var _focus_box := AABB()
var _wireframe: bool = false
var _collision_overlay: bool = false
var _screen_visible: bool = false

func _ready() -> void:
	stretch = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	ensure_navigation_focus()
	custom_minimum_size = Vector2(300, 260)
	viewport = SubViewport.new()
	viewport.name = "EditorWorkshopViewport"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	add_child(viewport)
	# 普通 Control 是编辑器 GUI 拖放目标，不让 SubViewport 的 hover 改写 section target。
	attachment_receiver = Control.new()
	attachment_receiver.name = "WorkshopPreviewInputReceiver"
	attachment_receiver.set_meta("cozy_skip", true)
	attachment_receiver.mouse_filter = Control.MOUSE_FILTER_PASS
	attachment_receiver.focus_mode = Control.FOCUS_NONE
	add_child(attachment_receiver)
	attachment_receiver.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attachment_receiver.set_drag_forwarding(Callable(), _receiver_can_drop, _receiver_drop)
	attachment_receiver.mouse_exited.connect(func() -> void:
		if attachment_input != null: attachment_input.hide_ghost()
		if surface_paint_input != null: surface_paint_input.pointer_exited())
	_world = Node3D.new()
	_world.name = "PreviewWorld"
	viewport.add_child(_world)
	_work_root = Node3D.new()
	_work_root.name = "Work"
	_world.add_child(_work_root)
	_model_root = Node3D.new()
	_model_root.name = "Asset"
	_work_root.add_child(_model_root)
	_model_root.owner = _work_root
	_attachment_root = Node3D.new()
	_attachment_root.name = "Attachments"
	_work_root.add_child(_attachment_root)
	_attachment_root.owner = _work_root
	_temporary_root = Node3D.new()
	_temporary_root.name = "AttachmentTemporary"
	_world.add_child(_temporary_root)
	_attachment_highlight = Node3D.new()
	_attachment_highlight.name = "AttachmentHighlight"
	_world.add_child(_attachment_highlight)
	_highlight_root = Node3D.new()
	_highlight_root.name = "SlotHighlights"
	_world.add_child(_highlight_root)
	_wireframe_root = Node3D.new()
	_wireframe_root.name = "WireframeOverlay"
	_world.add_child(_wireframe_root)
	_collision_root = Node3D.new()
	_collision_root.name = "CollisionOverlay"
	_world.add_child(_collision_root)
	_wire_material_instance = _make_overlay_material(Color(0.40, 0.92, 0.88, 0.92))
	_overlay_material_instance = _make_overlay_material(Color(0.95, 0.48, 0.32, 0.92))
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.current = true
	camera.fov = 38.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	_world.add_child(camera)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_world.add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "PreviewFill"
	fill.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	fill.light_energy = 0.45
	_world.add_child(fill)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#20252c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9fb8c4")
	environment.ambient_light_energy = 0.7
	var camera_env: WorldEnvironment = WorldEnvironment.new()
	camera_env.environment = environment
	_world.add_child(camera_env)
	viewport.size_changed.connect(_on_viewport_size_changed)
	visibility_changed.connect(_on_visibility_changed)
	mouse_exited.connect(func() -> void:
		if attachment_input != null: attachment_input.hide_ghost()
		if surface_paint_input != null: surface_paint_input.pointer_exited())
	_sync_update_mode()

## 为热重载前已就绪的实例补挂焦点能力，不重建 viewport 或镜头。
func ensure_navigation_focus() -> void:
	focus_mode = Control.FOCUS_ALL
	if not focus_exited.is_connected(_cancel_navigation):
		focus_exited.connect(_cancel_navigation)

func set_screen_visible(value: bool) -> void:
	ensure_navigation_focus()
	if _screen_visible != value or not value:
		_cancel_navigation()
	_screen_visible = value
	_sync_update_mode()

func _on_visibility_changed() -> void:
	ensure_navigation_focus()
	if not is_visible_in_tree():
		_cancel_navigation()
	_sync_update_mode()

func _sync_update_mode() -> void:
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _screen_visible and is_visible_in_tree() else SubViewport.UPDATE_DISABLED
		if _screen_visible and is_visible_in_tree() and not _camera_fitted and not _initial_frame_pending:
			_initial_frame_pending = true
			_fit_after_layout()

func _fit_after_layout() -> void:
	# Recovery can build while hidden, before containers receive their final size.
	await get_tree().process_frame
	await get_tree().process_frame
	_initial_frame_pending = false
	if is_inside_tree() and _screen_visible and is_visible_in_tree() and not _camera_fitted:
		_fit_camera(true)

func get_work_root() -> Node3D:
	return _work_root

func get_host_asset() -> Node3D:
	return _model_root

func get_building_root() -> Node3D:
	return _model_root.get_child(0) as Node3D if _model_root.get_child_count() == 1 else null

func get_attachment_root() -> Node3D:
	return _attachment_root

func get_temporary_root() -> Node3D:
	return _temporary_root

func get_surface_paint_root() -> Node3D:
	return _surface_paint_root

func sync_surface_paint_host() -> void:
	var host := get_building_root()
	if is_instance_valid(_surface_paint_space) and is_instance_valid(host):
		_surface_paint_space.global_transform = host.global_transform

func replace_surface_paint_root(root: Node3D) -> void:
	if not is_instance_valid(root) or root.get_parent() != null: return
	if not is_instance_valid(_surface_paint_space):
		_surface_paint_space = Node3D.new()
		_surface_paint_space.name = "SurfacePaintSpace"
		_work_root.add_child(_surface_paint_space)
		_surface_paint_space.owner = _work_root
	sync_surface_paint_host()
	if is_instance_valid(_surface_paint_root): _surface_paint_root.free()
	_surface_paint_root = root
	_surface_paint_space.add_child(root)
	_set_work_owner(root)

func replace_attachment_root(root: Node3D) -> void:
	if not is_instance_valid(root) or root.get_parent() != null: return
	highlight_attachment(null)
	_attachment_root.free()
	_attachment_root = root
	root.name = "Attachments"
	_work_root.add_child(root)
	_set_work_owner(root)

func _set_work_owner(node: Node) -> void:
	node.owner = _work_root
	for child: Node in node.get_children(): _set_work_owner(child)

func ray_from_local_position(position: Vector2) -> Dictionary:
	if camera == null or viewport == null or size.x <= 0 or size.y <= 0: return {}
	var point := position * Vector2(viewport.size) / size
	return {"origin": camera.project_ray_origin(point), "direction": camera.project_ray_normal(point)}

func highlight_attachment(node: Node3D) -> void:
	_selected_attachment = node
	_clear_children(_attachment_highlight)
	if not is_instance_valid(node): return
	select_slot("", false)
	var box := AABB()
	var initialized := false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null: continue
		var bounds: AABB = node.global_transform.affine_inverse() * child.global_transform * child.mesh.get_aabb()
		box = box.merge(bounds) if initialized else bounds
		initialized = true
	if initialized:
		_add_box_geometry(_attachment_highlight, box.grow(0.012), node.global_transform, Color.WHITE, "SelectedAttachment")

func _receiver_position(position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * (attachment_receiver.get_global_transform_with_canvas() * position)

func _receiver_can_drop(position: Vector2, data: Variant) -> bool:
	var local_position := _receiver_position(position)
	var allowed := _can_drop_data(local_position, data)
	_attachment_drag_checks += 1
	if _attachment_drag_checks == 1 or _attachment_drag_checks % 30 == 0:
		record_attachment_drag("receiver_can_drop", {"allowed": allowed, "position": local_position, "checks": _attachment_drag_checks})
	return allowed

func _receiver_drop(position: Vector2, data: Variant) -> void:
	record_attachment_drag("receiver_drop", {"position": _receiver_position(position)})
	_drop_data(_receiver_position(position), data)

func record_attachment_drag(stage: String, details: Dictionary = {}) -> void:
	var entry := {"stage": stage, "ticks_usec": Time.get_ticks_usec(), "preview_rect": get_global_rect(),
		"receiver_rect": attachment_receiver.get_global_rect() if is_instance_valid(attachment_receiver) else Rect2(),
		"viewport_rect": get_viewport().get_visible_rect()}
	entry.merge(details, true)
	_attachment_drag_trace.append(entry)
	if _attachment_drag_trace.size() > 32: _attachment_drag_trace.pop_front()
	set_meta("attachment_drag_trace", _attachment_drag_trace.duplicate(true))

func get_attachment_drag_diagnostics() -> Array[Dictionary]:
	return _attachment_drag_trace.duplicate(true)

func _can_drop_data(position: Vector2, data: Variant) -> bool:
	return _screen_visible and is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(position) and attachment_input != null and attachment_input.can_drop(position, data)

func _drop_data(position: Vector2, data: Variant) -> void:
	record_attachment_drag("drop_enter", {"position": position})
	if attachment_input != null:
		var result: Dictionary = attachment_input.drop(position, data)
		set_meta("attachment_last_drop", {"ok": result.get("ok", false), "reason": result.get("reason", "")})
		record_attachment_drag("drop_finished", get_meta("attachment_last_drop"))

func set_build_result(result: Dictionary) -> void:
	var root: Node3D = result.get("root") as Node3D
	if not is_instance_valid(root) or root.get_parent() != null:
		return
	_clear_children(_model_root)
	_clear_children(_highlight_root)
	_clear_children(_wireframe_root)
	_clear_children(_collision_root)
	_slots = result.get("slots", []) as Array
	_semantic_sources = result.get("semantic_sources", {}) as Dictionary
	_selected_id = ""
	if root != null:
		_model_root.add_child(root)
		root.owner = _model_root
		var next_id: String = str(root.get_meta("workshop_building_id", ""))
		if not _camera_fitted or next_id != _building_id:
			_camera_fitted = false
			_fit_camera(true)
		_building_id = next_id
	if _wireframe:
		_rebuild_wireframe()
	if _collision_overlay:
		_rebuild_collision_overlay()

func set_wireframe(enabled: bool) -> void:
	_wireframe = enabled
	_rebuild_wireframe()
	view_changed.emit()

func set_collision_overlay(enabled: bool) -> void:
	_collision_overlay = enabled
	_rebuild_collision_overlay()
	view_changed.emit()

func set_view(kind: String) -> void:
	match kind:
		"front":
			_yaw = 0.0
			_pitch = 0.0
		"back":
			_yaw = PI
			_pitch = 0.0
		"top":
			_yaw = 0.0
			_pitch = -PI * 0.5
		"bottom":
			_yaw = 0.0
			_pitch = PI * 0.5
		"perspective":
			_yaw = 0.65
			_pitch = -0.42
		_:
			return
	_cancel_navigation()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if kind == "perspective" else Camera3D.PROJECTION_ORTHOGONAL
	_fit_camera(true)
	view_changed.emit()

func select_slot(slot_id: String, notify: bool = true) -> void:
	if not slot_id.is_empty():
		_selected_attachment = null
		_clear_children(_attachment_highlight)
	if _selected_id == slot_id:
		return
	_selected_id = slot_id
	_clear_children(_highlight_root)
	for raw: Variant in _slots:
		var slot: Dictionary = raw as Dictionary
		if str(slot.get("id", "")) == slot_id:
			var box: AABB = _slot_aabb(slot)
			if box.has_volume():
				_add_box_geometry(_highlight_root, box, Transform3D.IDENTITY, Color(1.0, 0.76, 0.26, 0.92), "SelectedSlot")
			break
	if notify:
		slot_selected.emit(slot_id)

func selected_slot() -> String:
	return _selected_id

func _gui_input(event: InputEvent) -> void:
	ensure_navigation_focus()
	if not _screen_visible or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and attachment_input != null and attachment_input.controller.armed:
		record_attachment_drag("gui_button", {"pressed": event.pressed, "button": event.button_index, "position": event.position})
	if surface_paint_input != null and surface_paint_input.handle_input(event):
		_dragging = false
		accept_event()
		return
	if attachment_input != null and attachment_input.handle_input(event):
		_dragging = false
		accept_event()
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed:
			grab_focus()
		if button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_navigation_button = button.button_index if button.pressed else 0
			_move_keys.clear()
			_last_mouse = button.position
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_drag_moved = false
				_last_mouse = button.position
			else:
				_dragging = false
				if not _drag_moved:
					_try_select(button.position)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = clampf(_distance * 0.9, 2.0, 400.0)
			if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
				camera.size = clampf(camera.size * 0.9, 1.0, 400.0)
			_fit_camera(false)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = clampf(_distance * 1.1, 2.0, 400.0)
			if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
				camera.size = clampf(camera.size * 1.1, 1.0, 400.0)
			_fit_camera(false)
			accept_event()
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_F and key.pressed and not key.echo:
			focus_selection()
			accept_event()
		elif _navigation_button == MOUSE_BUTTON_RIGHT and key.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
			_move_keys[key.physical_keycode] = key.pressed
			accept_event()
	elif event is InputEventMouseMotion and (_dragging or _navigation_button != 0):
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var delta: Vector2 = motion.position - _last_mouse
		_last_mouse = motion.position
		if delta.length_squared() > 1.0:
			_drag_moved = true
		if _navigation_button == MOUSE_BUTTON_MIDDLE and motion.shift_pressed:
			_pan_camera(delta)
		else:
			var previous_position: Vector3 = camera.global_position
			_yaw -= delta.x * 0.008
			_pitch = clampf(_pitch - delta.y * 0.008, -1.55, 1.55)
			_fit_camera(false)
			if _navigation_button == MOUSE_BUTTON_RIGHT:
				_target += previous_position - camera.global_position
				_fit_camera(false)
		accept_event()

func _cancel_navigation() -> void:
	_dragging = false
	_navigation_button = 0
	_move_keys.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		if has_meta("attachment_last_drop"): remove_meta("attachment_last_drop")
		_attachment_drag_trace.clear()
		_attachment_drag_checks = 0
		record_attachment_drag("drag_begin")
	if what == NOTIFICATION_DRAG_END and attachment_input != null:
		var successful := get_viewport().gui_is_drag_successful()
		record_attachment_drag("drag_end", {"gui_successful": successful, "last_drop": get_meta("attachment_last_drop", {})})
		attachment_input.drag_finished(successful)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_navigation()
		if surface_paint_input != null: surface_paint_input.editor.set_armed(false)
		if attachment_input != null: attachment_input.controller.cancel_arm(false)

func _process(delta: float) -> void:
	# Window.push_input 的合成 release 在 Godot Editor 主窗口可能不经过
	# SubViewportContainer._gui_input；若笔划已有pending且物理左键已释放，
	# 在主线程下一帧提交一次，避免临时印记永远停在未提交状态。
	if surface_paint_input != null and surface_paint_input.editor != null:
		var paint_editor: Node = surface_paint_input.editor
		if surface_paint_input.synthetic_release_due() and not Input.is_key_pressed(KEY_SHIFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not paint_editor._pending.is_empty():
			paint_editor.finish_stroke()
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	if _navigation_button == MOUSE_BUTTON_MIDDLE and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_cancel_navigation()
	if not _screen_visible or not is_visible_in_tree() or _navigation_button != MOUSE_BUTTON_RIGHT:
		return
	# Release outside the preview must not leave navigation stuck.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_cancel_navigation()
		return
	var movement := Vector3(float(_move_keys.get(KEY_D, false)) - float(_move_keys.get(KEY_A, false)), float(_move_keys.get(KEY_E, false)) - float(_move_keys.get(KEY_Q, false)), float(_move_keys.get(KEY_S, false)) - float(_move_keys.get(KEY_W, false)))
	if not movement.is_zero_approx():
		_target += camera.global_basis * movement.normalized() * maxf(2.0, _distance * 0.4) * minf(delta, 0.1) * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_fit_camera(false)

func _pan_camera(delta: Vector2) -> void:
	var span: float = camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * _distance * tan(deg_to_rad(camera.fov * 0.5))
	var pixels: float = maxf(1.0, size.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else size.y)
	_target += (-camera.global_basis.x * delta.x + camera.global_basis.y * delta.y) * span / pixels
	_fit_camera(false)

func focus_object(whole_building: bool = false) -> void:
	if camera == null or viewport == null:
		return
	_cancel_navigation()
	var box: AABB = _model_aabb()
	if not whole_building and is_instance_valid(_selected_attachment):
		box = _visual_bounds(_selected_attachment)
	elif not whole_building:
		for slot: Dictionary in _slots:
			if str(slot.get("id", "")) == _selected_id:
				var building: Node3D = get_building_root()
				var source: Node3D = building.get_node_or_null(str(slot.get("node_path", ""))) as Node3D if building != null else null
				var selected_box: AABB = _visual_bounds(source) if is_instance_valid(source) and not bool(slot.get("semantic_source_only", false)) else _slot_aabb(slot)
				if selected_box.size.length_squared() > 0.0001:
					box = selected_box
				break
	_frame_camera(camera, viewport.size, box, true)
	_camera_fitted = box.has_volume()
	view_changed.emit()

## F 使用当前选件；工具栏房屋聚焦应显式调用 focus_object(true)。
func focus_selection() -> void:
	focus_object(false)

## 完整作品总览与房屋结构中心分离，不污染建筑包围盒。
func focus_work() -> void:
	if camera == null or viewport == null: return
	_cancel_navigation()
	_frame_camera(camera, viewport.size, get_work_bounds(), true)
	view_changed.emit()

func _try_select(screen_position: Vector2) -> void:
	if attachment_input != null and attachment_input.pick(screen_position): return
	if camera == null or viewport == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var viewport_position: Vector2 = screen_position * Vector2(viewport.size) / size
	var origin: Vector3 = camera.project_ray_origin(viewport_position)
	var direction: Vector3 = camera.project_ray_normal(viewport_position)
	var best_id: String = ""
	var best_distance: float = INF
	for raw: Variant in _slots:
		var slot: Dictionary = raw as Dictionary
		var box: AABB = _slot_aabb(slot)
		if not box.has_volume():
			continue
		var hit: float = _ray_box(origin, direction, box)
		if hit >= 0.0:
			hit = _ray_slot_surface(slot, origin, direction)
		if hit >= 0.0 and hit < best_distance:
			best_distance = hit
			best_id = str(slot.get("id", ""))
	if not best_id.is_empty():
		select_slot(best_id, true)

func _ray_slot_surface(slot: Dictionary, origin: Vector3, direction: Vector3) -> float:
	if _model_root.get_child_count() != 1:
		return -1.0
	var building: Node3D = _model_root.get_child(0) as Node3D
	if bool(slot.get("semantic_source_only", false)):
		var semantic: Dictionary = _semantic_sources.get(str(slot.get("id", "")), {})
		var placement: Transform3D = building.global_transform * Transform3D(Basis.IDENTITY, semantic.get("position", Vector3.ZERO))
		var semantic_nearest: float = INF
		for record: Dictionary in semantic.get("mesh_records", []):
			var record_transform: Transform3D = record.get("transform", Transform3D.IDENTITY)
			var semantic_hit: float = _ray_mesh_surface(record.get("mesh") as Mesh, placement * record_transform, origin, direction)
			if semantic_hit >= 0.0:
				semantic_nearest = minf(semantic_nearest, semantic_hit)
		return semantic_nearest if is_finite(semantic_nearest) else -1.0
	var source: Node3D = building.get_node_or_null(str(slot.get("node_path", ""))) as Node3D
	if source == null:
		return -1.0
	var meshes: Array[Node] = source.find_children("*", "MeshInstance3D", true, false)
	if source is MeshInstance3D:
		meshes.push_front(source)
	var nearest: float = INF
	for child: Node in meshes:
		var instance: MeshInstance3D = child as MeshInstance3D
		var hit: float = _ray_mesh_surface(instance.mesh, instance.global_transform, origin, direction)
		if hit >= 0.0:
			nearest = minf(nearest, hit)
	return nearest if is_finite(nearest) else -1.0

func _ray_mesh_surface(mesh: Mesh, transform: Transform3D, origin: Vector3, direction: Vector3) -> float:
	if mesh == null:
		return -1.0
	var inverse: Transform3D = transform.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = inverse.basis * direction
	var faces: PackedVector3Array = mesh.get_faces()
	var nearest: float = INF
	for i: int in range(0, faces.size() - 2, 3):
		var point: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction, faces[i], faces[i + 1], faces[i + 2])
		if point != null:
			nearest = minf(nearest, origin.distance_to(transform * (point as Vector3)))
	return nearest if is_finite(nearest) else -1.0

func _fit_camera(reset_distance: bool = false) -> void:
	if camera == null or viewport == null:
		return
	var box: AABB = _model_aabb()
	_frame_camera(camera, viewport.size, box, reset_distance)
	if reset_distance and box.size.length_squared() > 0.0001 and not _initial_frame_pending and _screen_visible and is_visible_in_tree() and viewport.size.x >= 300 and viewport.size.y >= 260:
		_camera_fitted = true

func _frame_camera(view_camera: Camera3D, dimensions: Vector2i, model_box: AABB, reset_distance: bool) -> void:
	if reset_distance and model_box.size.length_squared() > 0.0001:
		_focus_box = model_box
		_target = model_box.get_center()
	var horizontal: Vector3 = Vector3(sin(_yaw), 0.0, -cos(_yaw))
	var direction: Vector3 = (horizontal * cos(_pitch) + Vector3.UP * sin(-_pitch)).normalized()
	var up: Vector3 = Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
	view_camera.global_position = _target + direction * _distance
	view_camera.force_update_transform()
	view_camera.look_at(_target, up)
	# 切视图后立即适配时，不能读取上一机位的延迟 global_basis。
	view_camera.force_update_transform()
	if reset_distance and model_box.size.length_squared() > 0.0001:
		var aspect: float = float(maxi(1, dimensions.x)) / float(maxi(1, dimensions.y))
		var tangent: float = tan(deg_to_rad(view_camera.fov * 0.5))
		var tangent_x: float = tangent if view_camera.keep_aspect == Camera3D.KEEP_WIDTH else tangent * aspect
		var tangent_y: float = tangent / aspect if view_camera.keep_aspect == Camera3D.KEEP_WIDTH else tangent
		var inverse: Basis = view_camera.global_basis.inverse()
		var half_width: float = 0.0
		var half_height: float = 0.0
		var fitted_distance: float = 2.0
		for index: int in range(8):
			var corner: Vector3 = inverse * (model_box.get_endpoint(index) - _target)
			half_width = maxf(half_width, absf(corner.x))
			half_height = maxf(half_height, absf(corner.y))
			fitted_distance = maxf(fitted_distance, corner.z + maxf(absf(corner.x) / tangent_x, absf(corner.y) / tangent_y) * 1.12 + view_camera.near)
		_distance = fitted_distance
		# KEEP_WIDTH 的正交 size 是宽；不使用透视 FOV 冒充正立面。
		view_camera.size = maxf(1.0, maxf(half_width * 2.0, half_height * 2.0 * aspect) * 1.12) if view_camera.keep_aspect == Camera3D.KEEP_WIDTH else maxf(1.0, maxf(half_height * 2.0, half_width * 2.0 / aspect) * 1.12)
	view_camera.global_position = _target + direction * _distance
	view_camera.force_update_transform()
	view_camera.look_at(_target, up)
	view_camera.force_update_transform()
	_update_camera_clip(view_camera, model_box.merge(_focus_box))

func _update_camera_clip(view_camera: Camera3D, box: AABB) -> void:
	var inverse: Transform3D = view_camera.global_transform.affine_inverse()
	var nearest: float = INF
	var farthest: float = 0.0
	for index: int in range(8):
		var depth: float = -(inverse * box.get_endpoint(index)).z
		if depth > 0.0: nearest = minf(nearest, depth)
		farthest = maxf(farthest, depth)
	view_camera.near = clampf(nearest * 0.25, 0.001, 0.05) if is_finite(nearest) else 0.001
	view_camera.far = maxf(500.0, farthest + maxf(10.0, box.size.length()))

# 仅验证器调用：复制真实预览世界离屏渲染，不改变主屏容器尺寸、伸缩或灯光。
func capture_model_image(dimensions: Vector2i = Vector2i(1400, 1100)) -> Image:
	if not is_inside_tree() or viewport == null or camera == null or _model_root.get_child_count() == 0 or dimensions.x < 600 or dimensions.y < 600 or DisplayServer.get_name() == "headless":
		return null
	var capture_viewport: SubViewport = SubViewport.new()
	capture_viewport.name = "WorkshopModelCapture"
	capture_viewport.own_world_3d = true
	capture_viewport.size = dimensions
	capture_viewport.gui_disable_input = true
	capture_viewport.msaa_3d = viewport.msaa_3d
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(capture_viewport)
	var capture_world: Node3D = _world.duplicate(0) as Node3D
	capture_viewport.add_child(capture_world)
	# 高亮和调试叠加不是模型；原始材质、相机投影和有阴影灯光原样复制。
	for overlay: Node3D in [_highlight_root, _wireframe_root, _collision_root, _temporary_root, _attachment_highlight]:
		var copied_overlay: Node = capture_world.get_node(_world.get_path_to(overlay))
		copied_overlay.free()
	var capture_camera: Camera3D = capture_world.get_node(_world.get_path_to(camera)) as Camera3D
	capture_camera.current = true
	var saved_distance: float = _distance
	var saved_target: Vector3 = _target
	var saved_focus_box: AABB = _focus_box
	_frame_camera(capture_camera, dimensions, get_work_bounds(), true)
	_distance = saved_distance
	_target = saved_target
	_focus_box = saved_focus_box
	for frame: int in range(3):
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image: Image = capture_viewport.get_texture().get_image()
	capture_viewport.free()
	return image

## 世界坐标下的实际建筑包络；不从语义槽或 Work 原点猜中心。
func get_building_bounds() -> AABB:
	var building: Node3D = get_building_root()
	if building == null: return AABB()
	return _visual_bounds(building.get_node_or_null("GeneratedVisual") as Node3D)

func get_work_bounds() -> AABB:
	return _visual_bounds(_work_root)

func _model_aabb() -> AABB:
	return get_building_bounds()

func _visual_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	if not is_instance_valid(root): return result
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Node3D and not node.is_visible_in_tree(): continue
		pending.append_array(node.get_children())
		var boxes: Array[AABB] = []
		if node is MeshInstance3D and node.mesh != null:
			node.force_update_transform()
			boxes.append(node.global_transform * node.mesh.get_aabb())
		elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			node.force_update_transform()
			var multi: MultiMesh = node.multimesh
			var count: int = multi.instance_count if multi.visible_instance_count < 0 else mini(multi.instance_count, multi.visible_instance_count)
			for index: int in count:
				boxes.append(node.global_transform * multi.get_instance_transform(index) * multi.mesh.get_aabb())
		for box: AABB in boxes:
			result = result.merge(box) if initialized else box
			initialized = true
	return result

func _on_viewport_size_changed() -> void:
	if not _camera_fitted:
		_fit_camera(true)

func _slot_aabb(slot: Dictionary) -> AABB:
	var building_transform: Transform3D = _model_root.global_transform
	if _model_root.get_child_count() == 1:
		var building: Node3D = _model_root.get_child(0) as Node3D
		building.force_update_transform()
		building_transform = building.global_transform
	# 生成器给出的实际 mesh bounds 已包含植物底部 / 藤蔓顶部 pivot 偏差。
	if slot.has("bounds_position") and slot.has("bounds_size"):
		var actual_bounds: AABB = AABB(_vec3(slot["bounds_position"]), _vec3(slot["bounds_size"]))
		return building_transform * actual_bounds
	# 没有实际 bounds 的旧槽只允许居中硬表面使用 size 回退，不猜植物 pivot。
	if str(slot.get("kind", "")) == "plant":
		return AABB()
	var position: Vector3 = _vec3(slot.get("position", [0.0, 0.0, 0.0]))
	var dimensions: Vector3 = _vec3(slot.get("size", [1.0, 1.0, 1.0]))
	return building_transform * AABB(position - dimensions * 0.5, dimensions)

func _ray_box(origin: Vector3, direction: Vector3, box: AABB) -> float:
	var t_min: float = 0.0
	var t_max: float = INF
	for axis: int in 3:
		var o: float = origin[axis]
		var d: float = direction[axis]
		var low: float = box.position[axis]
		var high: float = box.end[axis]
		if absf(d) < 0.00001:
			if o < low or o > high:
				return -1.0
		else:
			var a: float = (low - o) / d
			var b: float = (high - o) / d
			if a > b:
				var swap: float = a
				a = b
				b = swap
			t_min = maxf(t_min, a)
			t_max = minf(t_max, b)
			if t_min > t_max:
				return -1.0
	return t_min

func _rebuild_wireframe() -> void:
	_clear_children(_wireframe_root)
	if not _wireframe:
		return
	for node: Node in _model_root.find_children("*", "MeshInstance3D", true, false):
		var source: MeshInstance3D = node as MeshInstance3D
		if source == null or source.mesh == null:
			continue
		var mesh: ImmediateMesh = ImmediateMesh.new()
		for surface_index: int in source.mesh.get_surface_count():
			var arrays: Array = source.mesh.surface_get_arrays(surface_index)
			var raw_vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not raw_vertices is PackedVector3Array:
				continue
			var vertices: PackedVector3Array = raw_vertices as PackedVector3Array
			var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = raw_indices as PackedInt32Array if raw_indices is PackedInt32Array else PackedInt32Array()
			var faces: PackedVector3Array = PackedVector3Array()
			if not indices.is_empty():
				for index: int in indices:
					faces.append(vertices[index])
			else:
				faces = vertices
			_add_triangle_lines(mesh, faces, Color.WHITE, _wire_material_instance)
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wireframe_root.add_child(instance)
		instance.global_transform = source.global_transform

func _rebuild_collision_overlay() -> void:
	_clear_children(_collision_root)
	if not _collision_overlay:
		return
	for node: Node in _model_root.find_children("*", "CollisionShape3D", true, false):
		var shape_node: CollisionShape3D = node as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		if shape_node.shape is BoxShape3D:
			var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
			_add_box_geometry(_collision_root, AABB(-box_shape.size * 0.5, box_shape.size), shape_node.global_transform, Color.WHITE, "CollisionBox")
		elif shape_node.shape is ConcavePolygonShape3D:
			var shape: ConcavePolygonShape3D = shape_node.shape as ConcavePolygonShape3D
			var mesh: ImmediateMesh = ImmediateMesh.new()
			_add_triangle_lines(mesh, shape.get_faces(), Color.WHITE, _overlay_material_instance)
			var instance: MeshInstance3D = MeshInstance3D.new()
			instance.mesh = mesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_collision_root.add_child(instance)
			instance.global_transform = shape_node.global_transform

func _add_triangle_lines(mesh: ImmediateMesh, faces: PackedVector3Array, color: Color, material: Material) -> void:
	if faces.size() < 3:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index: int in range(0, faces.size() - 2, 3):
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(faces[index]); mesh.surface_add_vertex(faces[index + 1])
		mesh.surface_add_vertex(faces[index + 1]); mesh.surface_add_vertex(faces[index + 2])
		mesh.surface_add_vertex(faces[index + 2]); mesh.surface_add_vertex(faces[index])
	mesh.surface_end()
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

func _add_box_geometry(parent: Node3D, box: AABB, transform: Transform3D, color: Color, node_name: String) -> void:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var p: Vector3 = box.position
	var e: Vector3 = box.end
	var corners: Array[Vector3] = [Vector3(p.x,p.y,p.z), Vector3(e.x,p.y,p.z), Vector3(e.x,p.y,e.z), Vector3(p.x,p.y,e.z), Vector3(p.x,e.y,p.z), Vector3(e.x,e.y,p.z), Vector3(e.x,e.y,e.z), Vector3(p.x,e.y,e.z)]
	for edge: Array in [[0,1], [1,2], [2,3], [3,0], [4,5], [5,6], [6,7], [7,4], [0,4], [1,5], [2,6], [3,7]]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(corners[edge[0]])
		mesh.surface_add_vertex(corners[edge[1]])
	mesh.surface_end()
	mesh.surface_set_material(0, _overlay_material_instance)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	instance.global_transform = transform

func _make_overlay_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.no_depth_test = true
	return material

func _clear_children(node: Node) -> void:
	if node != null:
		for child: Node in node.get_children():
			child.free()

func _vec3(value: Variant) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
