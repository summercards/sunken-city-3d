extends Node3D
## 仅由独立水下区域创建；不回写组件、网格或 Terrain3D 资源。

const STATIC_LAYER := 1
const VIEWER_RADIUS := 0.35
const VIEWER_HEIGHT := 1.6
const SWEEP_MARGIN := 0.001
const MAX_SLIDES := 8
const MAX_SWEEP_DISTANCE := 0.75
const MAX_SWEEP_STEPS := 2048
const MAX_MOTION_TESTS := 4096
const TERRAIN_FULL_GAME := 3

var stats: Dictionary = {}
var viewer: CharacterBody3D
var _region: Node3D
var _camera: Camera3D
var _mesh_faces: Dictionary = {}
var _shapes: Dictionary = {}
var _proxies: Array[StaticBody3D] = []


func setup(region: Node3D) -> void:
	_region = region
	_camera = region.get_node("Camera") as Camera3D
	stats = {"mesh_instances": 0, "multimesh_instances": 0, "triangles": 0,
		"unique_meshes": 0, "cached_shapes": 0, "proxy_count": 0,
		"empty_meshes": 0, "roles": {}, "assemblies": {}, "terrain_mode": TERRAIN_FULL_GAME}
	for assembly in region.get_node("ExistingModels/SunkenCity").get_children():
		_add_assembly(assembly, _city_role(assembly))
	_add_assembly(region.get_node("ExistingModels/SolarCabinBase"), "solar_base")
	for assembly in region.get_node("Ecology/FacilityLights").get_children():
		_add_assembly(assembly, "facility_light")
	for assembly in region.get_node("Ecology/CoralClusters").get_children():
		_add_assembly(assembly, "coral")
	_setup_terrain(region.get_node("ExistingModels/SunkenSeabed"))
	stats["unique_meshes"] = _mesh_faces.size()
	stats["cached_shapes"] = _shapes.size()
	stats["proxy_count"] = _proxies.size()
	set_meta("collision_policy", "per_mesh_concave_backface_scaled_geometry")
	set_meta("collision_role_stats", stats.duplicate(true))
	set_meta("proxy_source_paths", PackedStringArray([
		"ExistingModels/SunkenCity", "ExistingModels/SolarCabinBase",
		"Ecology/FacilityLights", "Ecology/CoralClusters", "ExistingModels/SunkenSeabed"]))
	_region.set_meta("collision", true)
	_region.set_meta("collision_role_stats", stats.duplicate(true))
	_create_viewer()


func _city_role(assembly: Node) -> String:
	var key := str(assembly.get_meta("key", assembly.name))
	if key.begins_with("viaduct") or key.begins_with("stair_link"):
		return "city_bridge"
	if key in ["street_intact", "street_split", "junction", "canal_segment", "plaza_tile", "terrain_ramp"]:
		return "city_road"
	if key in ["corrosion_patch", "moss_patch", "kelp_clump"]:
		return "city_decoration"
	if key in ["car_sedan", "car_van", "tram_wreck", "scooter", "utility_pole", "leaning_pole", "cable_span", "street_lamp", "traffic_light", "vending", "bus_shelter", "sign_board", "rubble_cluster", "pump_cabinet", "bench"]:
		return "city_fixture"
	return "city_structure"


func _add_assembly(assembly: Node, role: String) -> void:
	var assemblies: Dictionary = stats["assemblies"]
	assemblies[role] = int(assemblies.get(role, 0)) + 1
	_add_meshes(assembly, assembly, role)


func _add_meshes(node: Node, assembly: Node, role: String) -> void:
	if node is MeshInstance3D:
		var visual := node as MeshInstance3D
		if visual.mesh != null:
			_add_proxy(visual.mesh, visual.global_transform, visual, assembly, role, -1)
	elif node is MultiMeshInstance3D:
		var visual := node as MultiMeshInstance3D
		var multi := visual.multimesh
		if multi != null and multi.mesh != null:
			var count := multi.instance_count
			if multi.visible_instance_count >= 0:
				count = mini(count, multi.visible_instance_count)
			for index in count:
				_add_proxy(multi.mesh, visual.global_transform * multi.get_instance_transform(index), visual, assembly, role, index)
	for child in node.get_children():
		_add_meshes(child, assembly, role)


func _add_proxy(mesh: Mesh, pose: Transform3D, visual: Node, assembly: Node, role: String, instance_index: int) -> void:
	var mesh_id := mesh.get_instance_id()
	if not _mesh_faces.has(mesh_id):
		_mesh_faces[mesh_id] = mesh.get_faces()
	var faces: PackedVector3Array = _mesh_faces[mesh_id]
	if faces.is_empty():
		stats["empty_meshes"] += 1
		return
	# 物理刚体只带正交旋转；非均匀缩放/剪切烘入本区域形状，避免物理端丢失缩放。
	var rotation := pose.basis.orthonormalized()
	if rotation.determinant() < 0.0:
		rotation.x = -rotation.x
	var deformation := rotation.inverse() * pose.basis
	if deformation.is_equal_approx(Basis.IDENTITY):
		deformation = Basis.IDENTITY
	var shape_key := [mesh_id, deformation]
	if not _shapes.has(shape_key):
		var scaled_faces := PackedVector3Array()
		scaled_faces.resize(faces.size())
		for index in faces.size():
			scaled_faces[index] = deformation * faces[index]
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(scaled_faces)
		_shapes[shape_key] = shape
	var body := StaticBody3D.new()
	body.name = "Proxy%05d" % _proxies.size()
	body.collision_layer = STATIC_LAYER
	body.collision_mask = 0
	add_child(body)
	body.global_transform = Transform3D(rotation, pose.origin)
	var collider := CollisionShape3D.new()
	collider.name = "ExactMesh"
	collider.shape = _shapes[shape_key]
	body.add_child(collider)
	var source_path := str(_region.get_path_to(visual))
	body.set_meta("collision_role", role)
	body.set_meta("proxy_source_path", source_path)
	body.set_meta("proxy_source_scene", _source_scene(visual))
	body.set_meta("proxy_assembly_path", str(_region.get_path_to(assembly)))
	body.set_meta("proxy_mesh_resource", mesh.resource_path)
	body.set_meta("proxy_multimesh_index", instance_index)
	body.set_meta("collision_policy", "exact_triangles_backface")
	collider.set_meta("proxy_source_path", source_path)
	_proxies.append(body)
	stats["mesh_instances"] += 1
	stats["multimesh_instances"] += int(instance_index >= 0)
	stats["triangles"] += int(faces.size() / 3)
	var roles: Dictionary = stats["roles"]
	roles[role] = int(roles.get(role, 0)) + 1


func _source_scene(node: Node) -> String:
	var current := node
	while current != null and current != _region:
		if not current.scene_file_path.is_empty():
			return current.scene_file_path
		current = current.get_parent()
	return "res://src/ambient/sunroom_underwater_ecology.gd"


func _setup_terrain(terrain: Node) -> void:
	# Terrain3D 节点属性：0 Disabled / 1 DynamicGame / 2 DynamicEditor / 3 FullGame / 4 FullEditor。
	# 只改本区域实例，不触碰 data/material/assets，也不调用保存或生成高度图。
	terrain.set("collision_layer", STATIC_LAYER)
	terrain.set("collision_mask", 0)
	terrain.set("collision_mode", TERRAIN_FULL_GAME)
	terrain.set_meta("collision", true)
	terrain.set_meta("collision_role", "seabed")
	terrain.set_meta("proxy_source_path", "res://terrain/sunken_seabed")
	stats["terrain_source"] = "res://terrain/sunken_seabed"
	stats["terrain_regions"] = terrain.get("data").get_region_count()
	stats["terrain_vertex_spacing"] = terrain.get("vertex_spacing")


func _create_viewer() -> void:
	viewer = CharacterBody3D.new()
	viewer.name = "ViewerBody"
	viewer.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	viewer.collision_layer = 0
	viewer.collision_mask = STATIC_LAYER
	viewer.safe_margin = SWEEP_MARGIN
	viewer.set_meta("collision_role", "preview_viewer")
	add_child(viewer)
	var capsule := CapsuleShape3D.new()
	capsule.radius = VIEWER_RADIUS
	capsule.height = VIEWER_HEIGHT
	var collider := CollisionShape3D.new()
	collider.name = "ViewerCapsule"
	collider.shape = capsule
	viewer.add_child(collider)
	set_viewer_position(_camera.global_position)
	viewer.set_meta("spawn_validation", "pending")
	call_deferred("_validate_viewer_spawn", viewer.global_position)


func _validate_viewer_spawn(spawn_position: Vector3) -> void:
	# 等待新增静态形状与 Terrain3D 提交到物理空间，再验证真实出生净空。
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not viewer.global_position.is_equal_approx(spawn_position):
		viewer.set_meta("spawn_validation", "position_changed_before_validation")
		return
	if try_set_viewer_position(spawn_position):
		viewer.set_meta("spawn_validation", "valid")
	else:
		viewer.set_meta("spawn_validation", "rejected")
		_region.set_physics_process(false)
		push_error("独立水下预览出生点越界或胶囊净空不足；已停用预览移动，请调整 Camera 出生位置")


func try_set_viewer_position(world_position: Vector3) -> bool:
	if not world_position.is_finite():
		return false
	var local_position := _region.to_local(world_position)
	var bounds: Rect2 = _region.get("terrain_bounds")
	if local_position.x < bounds.position.x + 1.0 or local_position.x > bounds.end.x - 1.0:
		return false
	if local_position.z < bounds.position.y + 1.0 or local_position.z > bounds.end.y - 1.0:
		return false
	if local_position.y < float(_region.get("lowest_seabed_y")) + 0.8 or local_position.y > float(_region.get("water_level")) - VIEWER_HEIGHT * 0.5 - 0.02:
		return false
	var collider := viewer.get_node("ViewerCapsule") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	var target_pose := viewer.global_transform
	target_pose.origin = world_position
	query.transform = target_pose * collider.transform
	query.margin = SWEEP_MARGIN
	query.collision_mask = STATIC_LAYER
	query.exclude = [viewer.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	set_viewer_position(world_position)
	return true


func set_viewer_position(world_position: Vector3) -> void:
	viewer.global_position = world_position
	viewer.velocity = Vector3.ZERO
	_camera.global_position = world_position


func move_viewer(displacement: Vector3) -> Vector3:
	var start := viewer.global_position
	var local_target := _region.to_local(start + displacement)
	var bounds: Rect2 = _region.get("terrain_bounds")
	local_target.x = clampf(local_target.x, bounds.position.x + 1.0, bounds.end.x - 1.0)
	local_target.z = clampf(local_target.z, bounds.position.y + 1.0, bounds.end.y - 1.0)
	local_target.y = clampf(local_target.y, float(_region.get("lowest_seabed_y")) + 0.8, float(_region.get("water_level")) - VIEWER_HEIGHT * 0.5 - 0.02)
	var requested := _region.to_global(local_target) - start
	var distance := requested.length()
	var step_count := mini(ceili(distance / MAX_SWEEP_DISTANCE), MAX_SWEEP_STEPS)
	var segment := requested.normalized() * minf(distance, MAX_SWEEP_DISTANCE)
	var motion_tests := 0
	for step in step_count:
		var segment_start := viewer.global_position
		var remaining := segment.limit_length(maxf(0.0, distance - step * MAX_SWEEP_DISTANCE))
		for slide in MAX_SLIDES:
			if remaining.length_squared() < 0.00000001 or motion_tests >= MAX_MOTION_TESTS:
				break
			motion_tests += 1
			var hit := viewer.move_and_collide(remaining, false, SWEEP_MARGIN)
			if hit == null:
				break
			remaining = hit.get_remainder().slide(hit.get_normal())
		# 只在整段无进展时停止；法向被挡但切向能滑动的斜切仍推进下一段。
		if viewer.global_position.distance_squared_to(segment_start) < 0.00000001 or motion_tests >= MAX_MOTION_TESTS:
			break
	_camera.global_position = viewer.global_position
	return viewer.global_position - start


func surface_samples(role: String, limit := 16, normal_axis := Vector3.ZERO, min_alignment := 0.8) -> Array[Dictionary]:
	# 测试按真实三角面获取世界坐标/法线；不是包围盒点，也不保证面外探针净空。
	var result: Array[Dictionary] = []
	for body in _proxies:
		if body.get_meta("collision_role") != role:
			continue
		var collider := body.get_child(0) as CollisionShape3D
		var shape := collider.shape as ConcavePolygonShape3D
		var faces := shape.get_faces()
		var best: Dictionary = {}
		for index in range(0, faces.size(), 3):
			var a := body.global_transform * faces[index]
			var b := body.global_transform * faces[index + 1]
			var c := body.global_transform * faces[index + 2]
			# Godot 三角面为顺时针，反向叉积得到视觉外法线。
			var cross_product := (c - a).cross(b - a)
			var area := cross_product.length() * 0.5
			if normal_axis != Vector3.ZERO and cross_product.normalized().dot(normal_axis.normalized()) < min_alignment:
				continue
			if area <= float(best.get("area", 0.0)):
				continue
			best = {"position": (a + b + c) / 3.0, "normal": cross_product.normalized(),
				"area": area, "triangle": PackedVector3Array([a, b, c]),
				"proxy_path": str(_region.get_path_to(body)),
				"source_path": body.get_meta("proxy_source_path"), "triangle_index": index / 3}
		if not best.is_empty():
			result.append(best)
		if result.size() >= limit:
			break
	return result
