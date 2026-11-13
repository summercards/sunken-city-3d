@tool
extends SubViewportContainer
## 独立编辑器预览；不加载运行版预览、主场景或 Autoload。

signal slot_selected(slot_id: String)
signal view_changed

var viewport: SubViewport
var camera: Camera3D
var _world: Node3D
var _model_root: Node3D
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
var _selected_id: String = ""
var _dragging: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _yaw: float = 0.65
var _pitch: float = -0.42
var _distance: float = 26.0
var _target: Vector3 = Vector3.ZERO
var _wireframe: bool = false
var _collision_overlay: bool = false
var _screen_visible: bool = false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 260)
	viewport = SubViewport.new()
	viewport.name = "EditorWorkshopViewport"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
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
	_sync_update_mode()

func set_screen_visible(value: bool) -> void:
	_screen_visible = value
	_dragging = false
	_sync_update_mode()

func _on_visibility_changed() -> void:
	_dragging = false
	_sync_update_mode()

func _sync_update_mode() -> void:
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _screen_visible and is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func set_build_result(result: Dictionary) -> void:
	_clear_children(_model_root)
	_clear_children(_highlight_root)
	_clear_children(_wireframe_root)
	_clear_children(_collision_root)
	_slots = result.get("slots", []) as Array
	_semantic_sources = result.get("semantic_sources", {}) as Dictionary
	_selected_id = ""
	var root: Node3D = result.get("root") as Node3D
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
		"perspective":
			_yaw = 0.65
			_pitch = -0.42
		_:
			return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if kind == "perspective" else Camera3D.PROJECTION_ORTHOGONAL
	_fit_camera(true)
	view_changed.emit()

func select_slot(slot_id: String, notify: bool = true) -> void:
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
	if not _screen_visible or not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
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
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var delta: Vector2 = motion.position - _last_mouse
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
	if reset_distance and box.size.length_squared() > 0.0001 and viewport.size.x > 0 and viewport.size.y > 0:
		_camera_fitted = true

func _frame_camera(view_camera: Camera3D, dimensions: Vector2i, model_box: AABB, reset_distance: bool) -> void:
	if reset_distance and model_box.size.length_squared() > 0.0001:
		_target = model_box.get_center()
	var horizontal: Vector3 = Vector3(sin(_yaw), 0.0, -cos(_yaw))
	var direction: Vector3 = (horizontal * cos(_pitch) + Vector3.UP * sin(-_pitch)).normalized()
	var up: Vector3 = Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
	view_camera.position = _target + direction * _distance
	view_camera.look_at(_target, up)
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
	view_camera.position = _target + direction * _distance
	view_camera.far = maxf(500.0, _distance * 4.0)

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
	for overlay: Node3D in [_highlight_root, _wireframe_root, _collision_root]:
		var copied_overlay: Node = capture_world.get_node(_world.get_path_to(overlay))
		copied_overlay.free()
	var capture_camera: Camera3D = capture_world.get_node(_world.get_path_to(camera)) as Camera3D
	capture_camera.current = true
	var saved_distance: float = _distance
	var saved_target: Vector3 = _target
	_frame_camera(capture_camera, dimensions, _model_aabb(), true)
	_distance = saved_distance
	_target = saved_target
	for frame: int in range(3):
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image: Image = capture_viewport.get_texture().get_image()
	capture_viewport.free()
	return image

func _model_aabb() -> AABB:
	var result: AABB = AABB()
	var initialized: bool = false
	for node: Node in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var box: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
		result = box if not initialized else result.merge(box)
		initialized = true
	return result

func _on_viewport_size_changed() -> void:
	if not _camera_fitted:
		_fit_camera(true)

func _slot_aabb(slot: Dictionary) -> AABB:
	var building_transform: Transform3D = _model_root.global_transform
	if _model_root.get_child_count() == 1:
		building_transform = (_model_root.get_child(0) as Node3D).global_transform
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
