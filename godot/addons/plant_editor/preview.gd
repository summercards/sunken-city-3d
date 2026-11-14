@tool
extends VBoxContainer

signal branch_selected(id: String)

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
var _orbiting := false
var _press := Vector2.ZERO
var _moved := false
var _surface: SubViewportContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tools := HBoxContainer.new()
	add_child(tools)
	for entry in [["正面", "front"], ["俯视", "top"], ["透视", "perspective"], ["适配", "fit"]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(set_view.bind(entry[1]))
		tools.add_child(button)
	var hint := Label.new()
	hint.text = "拖动旋转 · 滚轮缩放 · 单击选枝"
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(hint)
	_surface = SubViewportContainer.new()
	_surface.stretch = true
	_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_surface.custom_minimum_size = Vector2(160, 120)
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
	_highlight = MeshInstance3D.new()
	_highlight.name = "EditorBranchBounds"
	viewport.add_child(_highlight)
	_surface.gui_input.connect(_on_input)
	_update_camera()
	set_process(false)

func set_active(value: bool) -> void:
	active = value
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	set_process(value)
	_set_material_clock()

func set_build(result: Dictionary) -> void:
	var next := result.get("root") as Node3D
	if next == null:
		return
	if model != next:
		if is_instance_valid(model):
			model.get_parent().remove_child(model)
			model.free()
		model = next
		viewport.add_child(model)
		_materials.clear()
		_collect_materials(model)
	branches = result.get("branches", []).duplicate(true)
	_set_material_clock()
	if not _initialized_camera:
		fit_model()
		_initialized_camera = true
	select_branch(selected_id)

func _collect_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material is ShaderMaterial and not _materials.has(material):
				_materials.append(material)
	for child in node.get_children():
		_collect_materials(child)

func _process(delta: float) -> void:
	if not active or not is_visible_in_tree():
		return
	local_time += delta
	_set_material_clock()

func _set_material_clock() -> void:
	for material in _materials:
		material.set_shader_parameter("preview_wind", active)
		material.set_shader_parameter("local_time", local_time)

func materials() -> Array[ShaderMaterial]:
	return _materials.duplicate()

func fit_model() -> void:
	if not is_instance_valid(model):
		return
	var bounds := _bounds(model)
	focus_bounds(bounds)

func focus_bounds(bounds: AABB, factor: float = 1.0) -> void:
	target = bounds.get_center()
	var aspect := float(maxi(viewport.size.x, 1)) / float(maxi(viewport.size.y, 1))
	var radius := maxf(bounds.size.length() * 0.5, 0.2)
	distance = radius / sin(deg_to_rad(camera.fov * 0.5)) * maxf(1.0, 1.0 / aspect) * factor
	camera.size = radius * 2.3 * maxf(1.0, 1.0 / aspect)
	_update_camera()

func _bounds(node: Node3D) -> AABB:
	var result := AABB(node.position, Vector3.ZERO)
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if child.mesh != null:
			var box: AABB = node.global_transform.affine_inverse() * child.global_transform * child.mesh.get_aabb()
			result = result.merge(box) if found else box
			found = true
	return result

func set_view(mode: String) -> void:
	if mode == "fit":
		fit_model()
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if mode == "perspective" else Camera3D.PROJECTION_ORTHOGONAL
	yaw = 0.65 if mode == "perspective" else 0.0
	pitch = 0.18 if mode == "perspective" else PI * 0.499 if mode == "top" else 0.0
	_update_camera()

func _update_camera() -> void:
	if camera == null:
		return
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target, Vector3.UP)

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_orbiting = true
				_press = event.position
				_moved = false
			else:
				if event.button_index == MOUSE_BUTTON_LEFT and not _moved:
					pick_branch(event.position)
				_orbiting = false
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
			distance = clampf(distance * factor, 0.15, 250)
			camera.size = clampf(camera.size * factor, 0.1, 200)
			_update_camera()
		_surface.accept_event()
	elif event is InputEventMouseMotion and _orbiting:
		if event.position.distance_to(_press) > 3.0:
			_moved = true
		if _moved:
			yaw -= event.relative.x * 0.008
			pitch = clampf(pitch + event.relative.y * 0.008, -1.5, 1.5)
			_update_camera()
		_surface.accept_event()

func pick_branch(point: Vector2) -> String:
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
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
		_highlight.visible = true
		return

func selection_visible() -> bool:
	return _highlight.visible
