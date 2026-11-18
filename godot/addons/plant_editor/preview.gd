@tool
extends VBoxContainer

signal branch_selected(id: String)

const WindRuntime = preload("res://src/plant_authoring/wind_runtime.gd")

var viewport: SubViewport
var camera: Camera3D
var model: Node3D
var branches: Array = []
var local_time := 0.0
var active := false
var target := Vector3(0, 3.5, 0)
var distance := 13.0
var yaw := 0.65
var pitch := 0.18
var selected_id := ""
var _materials: Array[ShaderMaterial] = []
var _highlight: MeshInstance3D
var _initialized_camera := false
var _drag_button := MOUSE_BUTTON_NONE
var _input_surface: Control
var _tools: HBoxContainer
var _press := Vector2.ZERO
var _moved := false
var _surface: SubViewportContainer
var host_reference: Node3D
var plant_transform := Transform3D.IDENTITY
var _plant_space: Node3D
var _render_active: bool = false
var _ensuring_navigation: bool = false
var _first_fit_queued: bool = false
var _focus_box := AABB()

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_meta("cozy_skip", true)
	_surface = SubViewportContainer.new()
	_surface.stretch = true
	add_child(_surface)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	_surface.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202d36")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5e5db")
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.6
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 140, 0)
	fill.light_energy = 0.65
	viewport.add_child(fill)
	camera = Camera3D.new()
	camera.near = 0.02
	camera.far = 500.0
	camera.current = true
	viewport.add_child(camera)
	_plant_space = Node3D.new()
	_plant_space.name = "PlantPreviewSpace"
	viewport.add_child(_plant_space)
	_highlight = MeshInstance3D.new()
	_highlight.name = "EditorBranchBounds"
	viewport.add_child(_highlight)
	_ensure_navigation()
	_update_camera()
	_sync_activity()

func _ensure_navigation() -> void:
	if _ensuring_navigation or not is_inside_tree() or not is_instance_valid(_surface):
		return
	_ensuring_navigation = true
	# 热重载仅补导航层，不重跑 _ready，也不触碰 World3D、模型和机位。
	if not is_instance_valid(_tools):
		for child: Node in get_children():
			if child is HBoxContainer:
				for item: Node in child.get_children():
					if item is Button and item.text == "正面":
						_tools = child
						break
			if is_instance_valid(_tools):
				break
	if not is_instance_valid(_tools):
		_tools = HBoxContainer.new()
		add_child(_tools)
		for entry: Array in [["正面", "front"], ["俯视", "top"], ["透视", "perspective"], ["适配", "fit"]]:
			var button: Button = Button.new()
			button.text = str(entry[0])
			button.pressed.connect(set_view.bind(str(entry[1])))
			_tools.add_child(button)
		var hint: Label = Label.new()
		hint.clip_text = true
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tools.add_child(hint)
	_tools.name = "PreviewTools"
	_tools.z_index = 2
	for child: Node in _tools.get_children():
		if child is Label:
			child.text = "左/右拖旋转 · 中键/Shift拖平移 · 滚轮缩放 · F聚焦"
			child.tooltip_text = "左键单击选枝，双击聚焦；F 聚焦选枝（无选择时适配全部）。仅预览获得焦点时响应。"
	var frame: Control = _surface.get_parent() as Control
	if frame == null:
		_ensuring_navigation = false
		return
	if frame == self:
		frame = Control.new()
		frame.name = "PreviewFrame"
		add_child(frame)
		_surface.reparent(frame, false)
	if _tools.get_index() > frame.get_index():
		move_child(_tools, frame.get_index())
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(160, 120)
	frame.clip_contents = true
	_surface.custom_minimum_size = Vector2.ZERO
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _surface.gui_input.is_connected(_on_input):
		_surface.gui_input.disconnect(_on_input)
	if not is_instance_valid(_input_surface):
		_input_surface = frame.get_node_or_null("PreviewNavigation") as Control
	if not is_instance_valid(_input_surface):
		_input_surface = Control.new()
		_input_surface.name = "PreviewNavigation"
		frame.add_child(_input_surface)
	_input_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_surface.focus_mode = Control.FOCUS_ALL
	_input_surface.z_index = 1
	if not _input_surface.focus_exited.is_connected(_cancel_drag):
		_input_surface.focus_exited.connect(_cancel_drag)
	if not _input_surface.gui_input.is_connected(_on_input):
		_input_surface.gui_input.connect(_on_input)
	if visibility_changed.is_connected(_cancel_drag):
		visibility_changed.disconnect(_cancel_drag)
	if not visibility_changed.is_connected(_sync_activity):
		visibility_changed.connect(_sync_activity)
	if not _surface.resized.is_connected(_queue_first_fit):
		_surface.resized.connect(_queue_first_fit)
	if is_instance_valid(viewport):
		viewport.gui_disable_input = true
		if not viewport.size_changed.is_connected(_queue_first_fit):
			viewport.size_changed.connect(_queue_first_fit)
	var window: Window = get_window()
	if window != null and not window.focus_exited.is_connected(_cancel_drag):
		window.focus_exited.connect(_cancel_drag)
	_ensuring_navigation = false

func set_active(value: bool) -> void:
	active = value
	_ensure_navigation()
	_sync_activity()

func _sync_activity() -> void:
	_render_active = active and is_visible_in_tree() and is_instance_valid(viewport)
	if not _render_active:
		_cancel_drag()
		if is_instance_valid(_input_surface) and _input_surface.has_focus():
			_input_surface.release_focus()
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _render_active else SubViewport.UPDATE_DISABLED
	set_process(_render_active)
	_set_material_clock()
	_queue_first_fit()

func _queue_first_fit() -> void:
	if _first_fit_queued or _initialized_camera or not _render_active or not is_instance_valid(model):
		return
	_first_fit_queued = true
	_finish_first_fit.call_deferred()

func _finish_first_fit() -> void:
	# 容器排序与 SubViewport 拉伸先完成；尺寸连续两帧一致才消费首次取景。
	await get_tree().process_frame
	if not is_inside_tree():
		_first_fit_queued = false
		return
	var surface_size: Vector2 = _surface.size if is_instance_valid(_surface) else Vector2.ZERO
	var render_size: Vector2i = viewport.size if is_instance_valid(viewport) else Vector2i.ZERO
	await get_tree().process_frame
	_first_fit_queued = false
	if not is_inside_tree() or not _render_active or not is_visible_in_tree() or _initialized_camera:
		return
	if not is_instance_valid(_surface) or not is_instance_valid(viewport):
		return
	if surface_size != _surface.size or render_size != viewport.size:
		_queue_first_fit()
		return
	if surface_size.x <= 1.0 or surface_size.y <= 1.0 or render_size.x <= 1 or render_size.y <= 1:
		return
	var expected_size: Vector2i = Vector2i(surface_size / float(maxi(_surface.stretch_shrink, 1)))
	if render_size != expected_size:
		return
	_fit_model_now()

# 仅准备独立预览候选；不挂载、不采样时钟、不改当前模型或其材质列表。
func prepare_candidate(result: Dictionary) -> Dictionary:
	var next: Node3D = result.get("root") as Node3D
	if not is_instance_valid(next):
		return {"ok": false, "reason": "预览候选 root 无效"}
	var next_materials: Array[ShaderMaterial] = WindRuntime.prepare(next)
	var nodes: Array[Node] = [next]
	nodes.append_array(next.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		if node.has_meta("plant_wind_prepare_rejected"):
			return {"ok": false, "reason": "树木预览风准备失败：" + str(node.get_meta("plant_wind_prepare_rejected"))}
	return {"ok": true, "reason": "", "materials": next_materials}

func set_build(result: Dictionary) -> bool:
	var next: Node3D = result.get("root") as Node3D
	if not is_instance_valid(next) or not is_instance_valid(_plant_space):
		return false
	if model != next:
		# Session 已在提交前准备；重复 prepare 只校验并收集同一批材质。
		var prepared := prepare_candidate(result)
		if not bool(prepared.ok):
			push_warning(str(prepared.reason))
			return false
		if next.get_parent() != null:
			next.reparent(_plant_space, false)
		else:
			_plant_space.add_child(next)
		var previous: Node3D = model
		model = next
		_materials = prepared.materials
		if is_instance_valid(previous):
			previous.get_parent().remove_child(previous)
			previous.free()
	branches = result.get("branches", []).duplicate(true)
	_set_material_clock()
	_queue_first_fit()
	select_branch(selected_id)
	return true

func _collect_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material is ShaderMaterial and not _materials.has(material):
				_materials.append(material)
	for child in node.get_children():
		_collect_materials(child)

func _process(delta: float) -> void:
	if not _render_active or not is_visible_in_tree():
		_sync_activity()
		return
	local_time += delta
	_set_material_clock()

func _set_material_clock() -> void:
	WindRuntime.apply_sample(_materials, local_time, 1.1, Vector2(0.86, 0.5), _render_active)

func materials() -> Array[ShaderMaterial]:
	return _materials.duplicate()

func fit_model() -> void:
	if not is_instance_valid(model) or not is_instance_valid(camera):
		return
	if not _initialized_camera:
		_queue_first_fit()
		return
	if not _render_active or not is_visible_in_tree():
		return
	_fit_model_now()

func _fit_model_now() -> void:
	if not is_instance_valid(model) or not is_instance_valid(camera):
		return
	focus_bounds(get_plant_bounds())

## 当前树的世界包络；宿主参考、高亮和预览 ghost 不属于树。
func get_plant_bounds() -> AABB:
	return _bounds(model, true) if is_instance_valid(model) else AABB()

func set_host_reference(node: Node3D) -> void:
	clear_host_reference()
	host_reference = node
	# 保留宿主原始根变换，植物通过独立预览父节点放到宿主根局部空间。
	viewport.add_child(host_reference)
	set_plant_transform(plant_transform)

func clear_host_reference() -> void:
	if is_instance_valid(host_reference):
		host_reference.get_parent().remove_child(host_reference)
		host_reference.free()
	host_reference = null

func set_plant_transform(value: Transform3D) -> void:
	plant_transform = value
	_plant_space.transform = host_reference.transform * value if is_instance_valid(host_reference) else value
	select_branch(selected_id)

## bounds 位于 PlantPreviewSpace 局部域；branch bounds 则位于 model 根局部域。
func focus_plant_bounds(bounds: AABB) -> void:
	_plant_space.force_update_transform()
	focus_bounds(_plant_space.global_transform * bounds)

func focus_selection() -> void:
	if not focus_branch(selected_id): fit_model()

func focus_bounds(bounds: AABB, factor: float = 1.0) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(viewport):
		return
	if not _render_active or not is_visible_in_tree():
		_queue_first_fit()
		return
	_cancel_drag()
	_initialized_camera = true
	_focus_box = bounds
	target = bounds.get_center()
	_update_camera()
	var aspect := float(maxi(viewport.size.x, 1)) / float(maxi(viewport.size.y, 1))
	var tangent := tan(deg_to_rad(camera.fov * 0.5))
	var tangent_x := tangent if camera.keep_aspect == Camera3D.KEEP_WIDTH else tangent * aspect
	var tangent_y := tangent / aspect if camera.keep_aspect == Camera3D.KEEP_WIDTH else tangent
	var inverse: Basis = camera.global_basis.inverse()
	var half_width := 0.0
	var half_height := 0.0
	var fitted_distance := 0.15
	for index: int in 8:
		var corner: Vector3 = inverse * (bounds.get_endpoint(index) - target)
		half_width = maxf(half_width, absf(corner.x))
		half_height = maxf(half_height, absf(corner.y))
		fitted_distance = maxf(fitted_distance, corner.z + maxf(absf(corner.x) / tangent_x, absf(corner.y) / tangent_y) * 1.12 + camera.near)
	distance = fitted_distance * maxf(factor, 1.0)
	camera.size = maxf(0.1, maxf(half_width * 2.0, half_height * 2.0 * aspect) * 1.12) if camera.keep_aspect == Camera3D.KEEP_WIDTH else maxf(0.1, maxf(half_height * 2.0, half_width * 2.0 / aspect) * 1.12)
	camera.size *= maxf(factor, 1.0)
	_update_camera()

func _bounds(node: Node3D, world_space: bool = false) -> AABB:
	var result := AABB()
	var found := false
	node.force_update_transform()
	var space: Transform3D = Transform3D.IDENTITY if world_space else node.global_transform.affine_inverse()
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		if child is Node3D and not child.is_visible_in_tree(): continue
		pending.append_array(child.get_children())
		var boxes: Array[AABB] = []
		if child is MeshInstance3D and child.mesh != null:
			child.force_update_transform()
			boxes.append(space * child.global_transform * child.mesh.get_aabb())
		elif child is MultiMeshInstance3D and child.multimesh != null and child.multimesh.mesh != null:
			child.force_update_transform()
			var multi: MultiMesh = child.multimesh
			var count: int = multi.instance_count if multi.visible_instance_count < 0 else mini(multi.instance_count, multi.visible_instance_count)
			for index: int in count:
				boxes.append(space * child.global_transform * multi.get_instance_transform(index) * multi.mesh.get_aabb())
		for box: AABB in boxes:
			result = result.merge(box) if found else box
			found = true
	return result

func set_view(mode: String) -> void:
	_ensure_navigation()
	if not is_instance_valid(camera) or not active or not is_visible_in_tree():
		return
	if mode == "fit":
		fit_model()
		return
	if mode not in ["front", "back", "top", "bottom", "perspective"]: return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if mode == "perspective" else Camera3D.PROJECTION_ORTHOGONAL
	yaw = 0.65 if mode == "perspective" else PI if mode == "back" else 0.0
	pitch = 0.18 if mode == "perspective" else PI * 0.5 if mode == "top" else -PI * 0.5 if mode == "bottom" else 0.0
	_fit_model_now()

func _update_camera() -> void:
	if camera == null:
		return
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
	camera.global_position = target + direction * distance
	camera.force_update_transform()
	camera.look_at(target, up)
	camera.force_update_transform()
	var inverse := camera.global_transform.affine_inverse()
	var nearest := INF
	var farthest := 0.0
	for index: int in 8:
		var depth: float = -(inverse * _focus_box.get_endpoint(index)).z
		if depth > 0.0: nearest = minf(nearest, depth)
		farthest = maxf(farthest, depth)
	camera.near = clampf(nearest * 0.25, 0.001, 0.02) if is_finite(nearest) else 0.001
	camera.far = maxf(500.0, farthest + maxf(10.0, _focus_box.size.length()))

func _cancel_drag() -> void:
	_drag_button = MOUSE_BUTTON_NONE
	_moved = false

func _on_input(event: InputEvent) -> void:
	_ensure_navigation()
	_sync_activity()
	if not active or not is_visible_in_tree() or not is_instance_valid(_input_surface) or not is_instance_valid(camera) or not is_instance_valid(viewport):
		_cancel_drag()
		return
	if event is InputEventKey and not _input_surface.has_focus():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F and not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed:
		focus_selection()
		_input_surface.accept_event()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_input_surface.grab_focus()
				_drag_button = event.button_index
				_press = event.position
				_moved = false
				if event.double_click and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed:
					focus_branch(pick_branch(event.position))
					_moved = true
			elif _drag_button == event.button_index:
				if event.button_index == MOUSE_BUTTON_LEFT and not _moved and not event.shift_pressed:
					pick_branch(event.position)
				_cancel_drag()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_initialized_camera = true
			_input_surface.grab_focus()
			var factor := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
			distance = clampf(distance * factor, 0.15, 250)
			camera.size = clampf(camera.size * factor, 0.1, 200)
			_update_camera()
		_input_surface.accept_event()
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var mask := 1 << (_drag_button - 1)
		if (event.button_mask & mask) == 0:
			_cancel_drag()
			return
		if event.position.distance_to(_press) > 3.0:
			_moved = true
		if _moved:
			_initialized_camera = true
			if _drag_button == MOUSE_BUTTON_MIDDLE or event.shift_pressed:
				var span := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * distance * tan(deg_to_rad(camera.fov * 0.5))
				var pixels: float = _input_surface.size.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else _input_surface.size.y
				target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * span / maxf(pixels, 1.0)
			else:
				yaw -= event.relative.x * 0.008
				pitch = clampf(pitch + event.relative.y * 0.008, -1.5, 1.5)
			_update_camera()
		_input_surface.accept_event()

func focus_branch(id: String) -> bool:
	# 合批后 node_path 可只剩元数据节点；选择与聚焦只消费根局部 bounds。
	if not is_instance_valid(model): return false
	for branch: Dictionary in branches:
		if str(branch.id) == id:
			model.force_update_transform()
			focus_bounds(model.global_transform * branch.bounds)
			return true
	return false

func pick_branch(point: Vector2) -> String:
	if not is_instance_valid(model) or not is_instance_valid(camera): return ""
	var inverse := model.global_transform.affine_inverse()
	var origin := inverse * camera.project_ray_origin(point)
	var direction := (inverse.basis * camera.project_ray_normal(point)).normalized()
	var nearest := INF
	var id := ""
	for branch: Dictionary in branches:
		if not bool(branch.get("enabled", true)):
			continue
		var bounds: AABB = branch.bounds
		var hit: Variant = bounds.grow(0.04).intersects_ray(origin, direction)
		if hit is Vector3:
			var d: float = origin.distance_squared_to(hit)
			if d < nearest:
				nearest = d
				id = str(branch.id)
	select_branch(id)
	branch_selected.emit(id)
	return id

func select_branch(id: String) -> void:
	selected_id = id
	if not is_instance_valid(_highlight) or not is_instance_valid(model):
		return
	_highlight.visible = false
	for branch: Dictionary in branches:
		if branch.id != id:
			continue
		var box: AABB = branch.bounds
		box = box.grow(0.035)
		var mesh := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("f4d47b")
		material.no_depth_test = true
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		for edge in [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3], [2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7]]:
			mesh.surface_add_vertex(box.get_endpoint(edge[0]))
			mesh.surface_add_vertex(box.get_endpoint(edge[1]))
		mesh.surface_end()
		_highlight.mesh = mesh
		_highlight.global_transform = model.global_transform
		_highlight.visible = true
		return

func selection_visible() -> bool:
	return is_instance_valid(_highlight) and _highlight.visible
