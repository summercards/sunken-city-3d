extends SubViewportContainer
## 独立工坊预览：自己的 SubViewport、相机、灯光和高亮。

signal slot_selected(slot_id: String)
signal view_changed

var viewport: SubViewport
var camera: Camera3D
var _world: Node3D
var _model_root: Node3D
var _highlight_root: Node3D
var _wireframe_root: Node3D
var _collision_root: Node3D
var _highlight_material_instance: StandardMaterial3D
var _wire_material_instance: StandardMaterial3D
var _overlay_material_instance: StandardMaterial3D
var _slots: Array = []
var _selected_id := ""
var _dragging := false
var _last_mouse := Vector2.ZERO
var _drag_moved := false
var _yaw := 0.0
var _pitch := -0.30
var _distance := 26.0
var _target := Vector3.ZERO
var _wireframe := false
var _collision_overlay := false

func _ready() -> void:
	set_meta("cozy_skip", true)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.name = "WorkshopPreviewViewport"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	add_child(viewport)
	_world = Node3D.new()
	_world.name = "PreviewWorld"
	viewport.add_child(_world)
	_model_root = Node3D.new()
	_model_root.name = "PreviewModel"
	_world.add_child(_model_root)
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
	_world.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "PreviewFill"
	fill.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	fill.light_energy = 0.45
	_world.add_child(fill)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111b25")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9fb8c4")
	environment.ambient_light_energy = 0.7
	var camera_env := WorldEnvironment.new()
	camera_env.name = "PreviewEnvironment"
	camera_env.environment = environment
	_world.add_child(camera_env)
	viewport.size_changed.connect(_on_viewport_size_changed)
	call_deferred("_fit_camera", true)

func set_build_result(result: Dictionary) -> void:
	_clear_children(_model_root)
	_clear_children(_highlight_root)
	_clear_children(_wireframe_root)
	_clear_children(_collision_root)
	_slots = result.get("slots", []) as Array
	_selected_id = ""
	var root: Variant = result.get("root")
	if root is Node3D:
		_model_root.add_child(root)
		root.owner = _model_root
	_fit_camera(true)
	if _wireframe:
		_rebuild_wireframe()
	if _collision_overlay:
		_rebuild_collision_overlay()
	queue_redraw()

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
			# front_axis=-Z：相机位于建筑 -Z 侧，镜头朝 +Z。
			_yaw = 0.0
			_pitch = -0.18
		"back":
			_yaw = PI
			_pitch = -0.18
		"top":
			_yaw = 0.0
			_pitch = -1.35
		"perspective":
			_yaw = 0.65
			_pitch = -0.42
	_fit_camera(false)
	view_changed.emit()

func select_slot(slot_id: String, notify: bool = true) -> void:
	if _selected_id == slot_id:
		return
	_selected_id = slot_id
	_clear_children(_highlight_root)
	for slot in _slots:
		if str(slot.get("id", "")) == slot_id:
			_add_box(_highlight_root, slot, Color(1.0, 0.76, 0.26, 0.92))
			break
	if notify:
		slot_selected.emit(slot_id)

func selected_slot() -> String:
	return _selected_id

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
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
			_distance = clampf(_distance * 0.9, 5.0, 120.0)
			_fit_camera(false)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = clampf(_distance * 1.1, 5.0, 120.0)
			_fit_camera(false)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var delta := motion.position - _last_mouse
		_last_mouse = motion.position
		if delta.length_squared() > 1.0:
			_drag_moved = true
		_yaw -= delta.x * 0.008
		_pitch = clampf(_pitch - delta.y * 0.008, -1.48, 0.35)
		_fit_camera(false)
		accept_event()

func _try_select(screen_position: Vector2) -> void:
	if camera == null or viewport == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var viewport_position := screen_position * Vector2(viewport.size) / size
	var origin := camera.project_ray_origin(viewport_position)
	var direction := camera.project_ray_normal(viewport_position)
	var best_id := ""
	var best_distance := INF
	for slot in _slots:
		var hit := _ray_box(origin, direction, _slot_aabb(slot))
		if hit >= 0.0 and hit < best_distance:
			best_distance = hit
			best_id = str(slot.get("id", ""))
	if not best_id.is_empty():
		select_slot(best_id, true)

func _fit_camera(reset_distance: bool = false) -> void:
	if camera == null:
		return
	var model_box: AABB = _model_aabb()
	if model_box.size.length_squared() > 0.0001:
		_target = model_box.position + model_box.size * 0.5
		if reset_distance:
			var radius := maxf(model_box.size.x, maxf(model_box.size.y, model_box.size.z)) * 0.5
			_distance = maxf(8.0, radius / tan(deg_to_rad(camera.fov * 0.5)) * 1.35)
	# front_axis=-Z means the camera is on -Z and looks toward +Z.
	var horizontal := Vector3(sin(_yaw), 0.0, -cos(_yaw))
	var offset := horizontal * cos(_pitch) * _distance + Vector3.UP * sin(-_pitch) * _distance
	camera.position = _target + offset
	camera.look_at(_target, Vector3.UP)

func _model_aabb() -> AABB:
	var result := AABB()
	var initialized := false
	for node in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var box: AABB = _transform_aabb(mesh_node.global_transform, mesh_node.mesh.get_aabb())
		if not initialized:
			result = box
			initialized = true
		else:
			result = result.merge(box)
	return result

func _transform_aabb(transform: Transform3D, box: AABB) -> AABB:
	var result := AABB()
	var initialized := false
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			for z in [box.position.z, box.end.z]:
				var point := transform * Vector3(x, y, z)
				if not initialized:
					result = AABB(point, Vector3.ZERO)
					initialized = true
				else:
					result = result.expand(point)
	return result

func _on_viewport_size_changed() -> void:
	_fit_camera(false)

func _slot_aabb(slot: Dictionary) -> AABB:
	var position: Vector3 = _vec3(slot.get("position", [0.0, 0.0, 0.0]))
	var size: Vector3 = _vec3(slot.get("size", [1.0, 1.0, 1.0]))
	return AABB(position - size * 0.5, size)

func _ray_box(origin: Vector3, direction: Vector3, box: AABB) -> float:
	var t_min := 0.0
	var t_max := INF
	for axis in 3:
		var o := origin[axis]
		var d := direction[axis]
		var low := box.position[axis]
		var high := box.end[axis]
		if absf(d) < 0.00001:
			if o < low or o > high: return -1.0
		else:
			var a := (low - o) / d
			var b := (high - o) / d
			if a > b:
				var swap := a; a = b; b = swap
			t_min = maxf(t_min, a)
			t_max = minf(t_max, b)
			if t_min > t_max: return -1.0
	return t_min

func _add_box(parent: Node3D, slot: Dictionary, color: Color) -> void:
	_add_box_geometry(parent, _slot_aabb(slot), Transform3D.IDENTITY, color, "SlotBox_%s" % str(slot.get("id", "")))

func _rebuild_wireframe() -> void:
	_clear_children(_wireframe_root)
	if not _wireframe:
		return
	for node in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		_add_mesh_edges(_wireframe_root, mesh_node, "Wireframe_%s" % mesh_node.get_path())

func _add_mesh_edges(parent: Node3D, source: MeshInstance3D, node_name: String) -> void:
	var edge_mesh := ImmediateMesh.new()
	for surface_index: int in source.mesh.get_surface_count():
		var arrays: Array = source.mesh.surface_get_arrays(surface_index)
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not vertices is PackedVector3Array:
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		edge_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
			var indexed: PackedInt32Array = indices as PackedInt32Array
			for triangle_start in range(0, indexed.size(), 3):
				if triangle_start + 2 >= indexed.size():
					break
				var a: Vector3 = (vertices as PackedVector3Array)[indexed[triangle_start]]
				var b: Vector3 = (vertices as PackedVector3Array)[indexed[triangle_start + 1]]
				var c: Vector3 = (vertices as PackedVector3Array)[indexed[triangle_start + 2]]
				edge_mesh.surface_set_color(Color.WHITE)
				edge_mesh.surface_add_vertex(a); edge_mesh.surface_add_vertex(b)
				edge_mesh.surface_add_vertex(b); edge_mesh.surface_add_vertex(c)
				edge_mesh.surface_add_vertex(c); edge_mesh.surface_add_vertex(a)
		else:
			var unindexed: PackedVector3Array = vertices as PackedVector3Array
			for triangle_start in range(0, unindexed.size(), 3):
				if triangle_start + 2 >= unindexed.size():
					break
				edge_mesh.surface_set_color(Color.WHITE)
				edge_mesh.surface_add_vertex(unindexed[triangle_start]); edge_mesh.surface_add_vertex(unindexed[triangle_start + 1])
				edge_mesh.surface_add_vertex(unindexed[triangle_start + 1]); edge_mesh.surface_add_vertex(unindexed[triangle_start + 2])
				edge_mesh.surface_add_vertex(unindexed[triangle_start + 2]); edge_mesh.surface_add_vertex(unindexed[triangle_start])
		edge_mesh.surface_end()
		edge_mesh.surface_set_material(edge_mesh.get_surface_count() - 1, _wire_material_instance)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = edge_mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	instance.global_transform = source.global_transform

func _rebuild_collision_overlay() -> void:
	_clear_children(_collision_root)
	if not _collision_overlay:
		return
	for node in _model_root.find_children("*", "CollisionShape3D", true, false):
		var shape_node: CollisionShape3D = node as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		if shape_node.shape is BoxShape3D:
			var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
			_add_box_geometry(_collision_root, AABB(-box_shape.size * 0.5, box_shape.size), shape_node.global_transform, Color(0.95, 0.48, 0.32, 0.92), "CollisionOverlay_%s" % shape_node.get_path(), _overlay_material_instance)
		elif shape_node.shape is ConcavePolygonShape3D:
			_add_concave_geometry(_collision_root, shape_node.shape as ConcavePolygonShape3D, shape_node.global_transform, Color(0.95, 0.48, 0.32, 0.92), "CollisionOverlay_%s" % shape_node.get_path())

func _add_concave_geometry(parent: Node3D, shape: ConcavePolygonShape3D, transform: Transform3D, color: Color, node_name: String) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var faces: PackedVector3Array = shape.get_faces()
	for index in range(0, faces.size(), 3):
		if index + 2 >= faces.size():
			break
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(a); mesh.surface_add_vertex(b)
		mesh.surface_add_vertex(b); mesh.surface_add_vertex(c)
		mesh.surface_add_vertex(c); mesh.surface_add_vertex(a)
	mesh.surface_end()
	mesh.surface_set_material(0, _overlay_material_instance)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.transform = transform
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _add_box_geometry(parent: Node3D, box: AABB, transform: Transform3D, color: Color, node_name: String, material: Material = null) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var p := box.position
	var e := box.end
	var corners := [Vector3(p.x,p.y,p.z),Vector3(e.x,p.y,p.z),Vector3(e.x,p.y,e.z),Vector3(p.x,p.y,e.z),Vector3(p.x,e.y,p.z),Vector3(e.x,e.y,p.z),Vector3(e.x,e.y,e.z),Vector3(p.x,e.y,e.z)]
	for edge in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(corners[edge[0]])
		mesh.surface_add_vertex(corners[edge[1]])
	mesh.surface_end()
	mesh.surface_set_material(0, material if material != null else _overlay_material_instance)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.transform = transform
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _make_overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.no_depth_test = true
	return material

func _clear_children(node: Node) -> void:
	for child in node.get_children(): child.free()

func _vec3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
