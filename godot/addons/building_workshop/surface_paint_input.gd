@tool
extends RefCounted
## 由真实预览容器 GUI 调用；中/右键和滚轮始终交还相机。

var preview: Control
var editor: Node
var pointer_inside := false
var pointer_position := Vector2.ZERO
var ghost: MeshInstance3D
var normal_line: MeshInstance3D
var _left_owned := false
var _last_input_usec := 0
var _release_guard_usec: int = 0
var _window: Window
var _green: StandardMaterial3D
var _red: StandardMaterial3D
var _last_center := Vector3.ZERO
var _has_center := false
const MAX_RAY_TRIANGLES := 131072

func configure(view: Control, paint_editor: Node) -> void:
	preview = view
	editor = paint_editor
	_green = _material(Color(0.3, 1.0, 0.5, 0.9))
	_red = _material(Color(1.0, 0.18, 0.12, 0.95))
	_window = preview.get_window()
	if _window != null and not _window.window_input.is_connected(_on_window_input):
		_window.window_input.connect(_on_window_input)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_last_input_usec = Time.get_ticks_usec()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		return _handle_release(event)
	if not editor.active or not editor.armed: return false
	if event is InputEventKey and event.pressed and event.keycode in [KEY_SHIFT, KEY_ESCAPE]:
		editor.set_armed(false)
		return event.keycode == KEY_ESCAPE
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			editor.set_armed(false)
			return false
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			editor.cancel_stroke()
			hide_ghost()
			return false
		if event.button_index != MOUSE_BUTTON_LEFT: return false
		if event.pressed:
			_left_owned = true
			pointer_position = event.position
			pointer_inside = Rect2(Vector2.ZERO, preview.size).has_point(event.position)
			preview.grab_focus()
			if event.shift_pressed: editor.set_armed(false)
			elif pointer_inside: editor.begin_stroke(event.position)
			return true
	elif event is InputEventMouseMotion:
		pointer_position = event.position
		pointer_inside = Rect2(Vector2.ZERO, preview.size).has_point(event.position)
		if event.shift_pressed:
			editor.set_armed(false)
			return false
		if event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			hide_ghost()
			return false
		update_ghost(event.position)
		return true
	return false

func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_last_input_usec = Time.get_ticks_usec()
		if event.pressed:
			# Window.push_input 可能绕过 SubViewportContainer._gui_input；
			# 先记录合成按下，避免下一帧把仍在拖动的pending误判为release。
			_left_owned = true
		else:
			_handle_release(event)

func synthetic_release_due() -> bool:
	# Editor 中 Window.push_input 的 release 可能不会回到同一个 Control，
	# 因而 _left_owned 仍为 true；真实物理左键状态才是是否仍在拖动的权威。
	# 仅在有待提交笔划、物理键已松开且输入静默一小段时间后合成一次 release。
	if editor == null or editor._pending.is_empty() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return false
	# 正常 release 仍由 _handle_release 即时处理，watchdog 只兜底丢失的窗口事件。
	# 约4帧：先给真实GUI专项观察pending，再及时提交，不让笔划卡住。
	return Time.get_ticks_usec() - _last_input_usec >= 70000

func _handle_release(event: InputEvent) -> bool:
	var now: int = Time.get_ticks_usec()
	if now < _release_guard_usec:
		_left_owned = false
		return true
	var had_stroke: bool = _left_owned or (editor != null and not editor._pending.is_empty())
	_left_owned = false
	if had_stroke and editor.active and editor.armed and not event.shift_pressed:
		_release_guard_usec = now + 100000
		editor.finish_stroke()
	else:
		editor.cancel_stroke()
	return had_stroke

func pointer_exited() -> void:
	pointer_inside = false
	if not editor.active or not preview.is_visible_in_tree(): editor.pause()
	hide_ghost()

func hide_ghost() -> void:
	if is_instance_valid(ghost): ghost.hide()
	if is_instance_valid(normal_line): normal_line.hide()

func refresh_ghost() -> void:
	update_ghost(preview.get_local_mouse_position())

func update_ghost(position: Vector2) -> Dictionary:
	pointer_position = position
	pointer_inside = Rect2(Vector2.ZERO, preview.size).has_point(position)
	if not editor.active or not editor.armed or not preview.is_visible_in_tree() or not pointer_inside:
		hide_ghost()
		return {"ok": false, "reason": "笔刷未启用或指针不在预览内"}
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		hide_ghost()
		return {"ok": false, "reason": "导航期间暂停笔刷"}
	var ray: Dictionary = preview.ray_from_local_position(position)
	if ray.is_empty():
		hide_ghost()
		return {"ok": false, "reason": "预览射线未就绪"}
	var result: Dictionary = editor.probe(ray)
	# 连同原生植被和已刷层检查最近可见遮挡；核心缓存故意排除这些层，不能穿透。
	var obstacle: Dictionary = _nearest_visible(ray, editor.brush.kind != "erase")
	if obstacle.get("budget_exceeded", false):
		result = {"ok": false, "reason": "可见遮挡射线超过预算，拒绝落笔"}
	elif obstacle.has("position") and (not result.get("ok", false) or (obstacle.position as Vector3).distance_to(ray.origin) + 0.0001 < (result.center_world as Vector3).distance_to(ray.origin)):
		result = {"ok": false, "reason": "最近可见面为玻璃、背面或植被现层，拒绝穿透刷涂",
			"center_world": obstacle.position, "normal_world": obstacle.normal}
	var normal: Vector3 = result.get("normal_world", Vector3.ZERO)
	var center: Vector3
	if result.has("center_world"):
		center = result.center_world
		_last_center = center
		_has_center = true
	else:
		# 未命中只沿当前射线放红色拒绝球，不把旧绿色落点当作有效面。
		var distance: float = (ray.origin as Vector3).distance_to(_last_center) if _has_center else preview.get_building_bounds().get_center().distance_to(ray.origin)
		center = ray.origin + ray.direction * maxf(0.1, distance)
	_show_ghost(center, normal, result.get("ok", false))
	if not result.get("ok", false): editor.report(str(result.get("reason", "未命中真实面")))
	return result

func _show_ghost(center: Vector3, normal: Vector3, allowed: bool) -> void:
	if not is_instance_valid(ghost):
		ghost = MeshInstance3D.new()
		ghost.name = "SurfacePaintSphereGhost"
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		preview.get_temporary_root().add_child(ghost)
		normal_line = MeshInstance3D.new()
		normal_line.name = "SurfacePaintNormalGhost"
		normal_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		preview.get_temporary_root().add_child(normal_line)
	var material: Material = _green if allowed else _red
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var radius: float = editor.brush.radius
	for axis: int in 3:
		for index: int in 48:
			for step: int in [index, index + 1]:
				var angle: float = TAU * float(step) / 48.0
				var vertex := Vector3.ZERO
				vertex[(axis + 1) % 3] = cos(angle) * radius
				vertex[(axis + 2) % 3] = sin(angle) * radius
				mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	ghost.mesh = mesh
	ghost.global_position = center
	ghost.show()
	var line := ImmediateMesh.new()
	if not normal.is_zero_approx():
		line.surface_begin(Mesh.PRIMITIVE_LINES, material)
		line.surface_add_vertex(Vector3.ZERO)
		line.surface_add_vertex(normal.normalized() * maxf(0.12, radius))
		line.surface_end()
	normal_line.mesh = line
	normal_line.global_position = center
	normal_line.visible = not normal.is_zero_approx()

func _nearest_visible(ray: Dictionary, include_painted: bool) -> Dictionary:
	# GeneratedVisual/玻璃已由 editor.probe() 使用同一份真实表面缓存
	# 命中；这里仅检查独立外挂。当前 SurfacePaint 层不作为遮挡物，
	# 否则第二次采样会把刚生成的草/苔藓/藤蔓当成玻璃或植被，
	# 反向阻断同一笔刷继续落点。
	var roots: Array[Node] = [preview.get_attachment_root()]
	var best := {}
	var nearest := INF
	var comparisons := 0
	var pending: Array[Node] = roots
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if not is_instance_valid(node): continue
		# 已保存层在临时整层预览期间被隐藏，但仍是本笔开始前的遮挡。
		if node is Node3D and not node.visible and node != preview.get_surface_paint_root(): continue
		pending.append_array(node.get_children())
		var mesh: Mesh
		var transforms: Array[Transform3D] = []
		if node is MeshInstance3D:
			mesh = node.mesh
			transforms.append(node.global_transform)
		elif node is MultiMeshInstance3D and node.multimesh != null:
			mesh = node.multimesh.mesh
			var count: int = node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else mini(node.multimesh.instance_count, node.multimesh.visible_instance_count)
			for index: int in count: transforms.append(node.global_transform * node.multimesh.get_instance_transform(index))
		if mesh == null: continue
		for transform: Transform3D in transforms:
			var inverse := transform.affine_inverse()
			var origin: Vector3 = inverse * ray.origin
			var direction: Vector3 = inverse.basis * ray.direction
			if mesh.get_aabb().intersects_ray(origin, direction) == null: continue
			var faces := mesh.get_faces()
			for index: int in range(0, faces.size() - 2, 3):
				comparisons += 1
				if comparisons > MAX_RAY_TRIANGLES: return {"budget_exceeded": true}
				var point: Variant = Geometry3D.ray_intersects_triangle(origin, direction, faces[index], faces[index + 1], faces[index + 2])
				if point == null: continue
				var world: Vector3 = transform * point
				var distance: float = (ray.origin as Vector3).distance_to(world)
				if distance >= nearest: continue
				var normal: Vector3 = (transform.basis.inverse().transposed() * (faces[index + 2] - faces[index]).cross(faces[index + 1] - faces[index])).normalized()
				nearest = distance
				best = {"position": world, "normal": normal}
	return best

func dispose() -> void:
	_left_owned = false
	_last_input_usec = 0
	_release_guard_usec = 0
	if _window != null and _window.window_input.is_connected(_on_window_input):
		_window.window_input.disconnect(_on_window_input)
	_window = null
	if is_instance_valid(ghost): ghost.free()
	if is_instance_valid(normal_line): normal_line.free()
	ghost = null
	normal_line = null
