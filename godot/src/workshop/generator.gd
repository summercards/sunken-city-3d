@tool
extends RefCounted
## SEA-WORKSHOP V1 原生参数生成器。
## 只生成静态节点；不访问Main/autoload，不写文件，不把根节点挂入场景树。

const GENERATOR_VERSION := "sea_workshop_generator_v1"
const MAX_NODES := 2000
const MAX_TRIANGLES := 180000
const ROLE_NAMES := ["wall", "slab", "frame", "glass", "pillar", "plant"]
const FACADE_NAMES := ["front", "back", "left", "right"]
const MeshBuilder = preload("res://src/workshop/mesh_builder.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const STANDARDS_PATH := "res://data/workshop/standards_v1.json"
const DIVE_COLLISION_LAYER := 1024

static func build(recipe: Dictionary, catalog: Dictionary = {}) -> Dictionary:
	var empty := {"ok": false, "reason": "", "root": null, "slots": [], "stats": {}, "walk_surfaces": [], "water_blockers": [], "warnings": []}
	var source_catalog: Dictionary = catalog.duplicate(true) if not catalog.is_empty() else Catalog.definitions()
	var normalized := Recipe.normalized(recipe)
	var catalog_reason := Catalog.validate(source_catalog)
	if not catalog_reason.is_empty():
		empty.reason = catalog_reason
		return empty
	var recipe_reason := Recipe.validate(normalized, source_catalog)
	if not recipe_reason.is_empty():
		empty.reason = recipe_reason
		return empty
	var standards_reason := _validate_standards()
	if not standards_reason.is_empty():
		empty.reason = standards_reason
		return empty
	# 关闭随机时，密度阈值和生长权重仍有效，但抽样固定为旧默认seed，不随用户seed变化。
	var source_fingerprint := Recipe.fingerprint(normalized)
	if not bool(normalized.vegetation_random_enabled):
		normalized.vegetation_seed = 11012
	if str(normalized.get("construction_mode", "modular_v1")) == "shell_v2":
		var shell: Dictionary = preload("res://src/workshop/shell_generator.gd").build(normalized, source_catalog)
		if bool(shell.ok):
			_apply_vegetation_variation(shell, normalized, source_catalog)
			shell.root.set_meta("recipe_fingerprint", source_fingerprint)
		return shell
	var root := Node3D.new()
	root.name = "WorkshopBuilding_" + str(normalized.building_id)
	root.set_meta("workshop_building_id", str(normalized.building_id))
	root.set_meta("asset_id", "SEA-WORKSHOP-" + str(normalized.building_id).to_upper())
	root.set_meta("spatial_profile", str(normalized.spatial_profile))
	root.set_meta("generator_version", GENERATOR_VERSION)
	root.set_meta("recipe_fingerprint", source_fingerprint)
	root.set_meta("catalog_fingerprint", Catalog.fingerprint(source_catalog))
	root.set_meta("standards_fingerprint", _standards_fingerprint())
	var generated := Node3D.new()
	generated.name = "GeneratedVisual"
	root.add_child(generated)
	generated.owner = root
	var vegetation := Node3D.new()
	vegetation.name = "Vegetation"
	root.add_child(vegetation)
	vegetation.owner = root
	var spatial := Node3D.new()
	spatial.name = "Spatial"
	root.add_child(spatial)
	spatial.owner = root
	var collision_root := Node3D.new()
	collision_root.name = "Collision"
	spatial.add_child(collision_root)
	collision_root.owner = root
	var material_cache: Dictionary = {}
	var slots: Array = []
	var walk_surfaces: Array = []
	var water_blockers: Array = []
	var warnings: Array = []
	var stats := {"nodes": 4, "triangles": 0, "visual_meshes": 0, "collision_shapes": 0, "plant_meshes": 0}
	var occupied := _occupied_cells(normalized)
	if occupied.is_empty():
		root.free()
		empty.reason = "shape没有有效占用单元"
		return empty
	var facade_segments := _boundary_segments(occupied, normalized)
	var front_door_segment_id := _front_door_segment_id(facade_segments)
	var emitted_pillars: Dictionary = {}
	for floor in range(int(normalized.floors)):
		var floor_height := _floor_value(normalized, floor, "floor_height")
		var slab_thickness := _floor_value(normalized, floor, "slab_thickness")
		var floor_base := _floor_base(normalized, floor)
		for cell in occupied:
			var cell_key := str(cell.x) + "_" + str(cell.y)
			var slab_id := "slab_" + str(floor) + "_" + cell_key
			if _is_disabled(slab_id, normalized):
				continue
			var cell_size := _plate_size(cell, normalized, occupied)
			var cell_center := _cell_center(cell, normalized)
			var slab_position := Vector3(cell_center.x, floor_base - slab_thickness * 0.5, cell_center.y)
			_add_box_slot(root, generated, collision_root, slots, stats, normalized, source_catalog, material_cache, slab_id, "slab", floor, "", _component_for_slot("slab", slab_id, normalized), slab_position, Vector3(cell_size.x, slab_thickness, cell_size.y), true)
			var actual_slab := _slot_by_id(slots, slab_id)
			if str(normalized.spatial_profile) != "scenic_underwater" and not actual_slab.is_empty():
				walk_surfaces.append({"id": "walk_" + str(floor) + "_" + cell_key, "floor": floor, "position": _surface_position(actual_slab), "size": _surface_size(actual_slab, normalized), "source_slots": [slab_id]})
	for floor in range(int(normalized.floors)):
		var floor_height := _floor_value(normalized, floor, "floor_height")
		if floor + 1 < int(normalized.floors):
			floor_height -= _floor_value(normalized, floor + 1, "slab_thickness")
		var floor_base := _floor_base(normalized, floor)
		for segment in facade_segments:
			var facade := str(segment.facade)
			var facade_settings: Dictionary = normalized.facade_overrides.get(facade, {})
			var windows := bool(facade_settings.get("windows", true))
			var window_width := float(facade_settings.get("width", _floor_value(normalized, floor, "window_width")))
			var window_height := float(facade_settings.get("height", _floor_value(normalized, floor, "window_height")))
			var sill := float(facade_settings.get("sill", _floor_value(normalized, floor, "window_sill")))
			if floor == 0 and facade == "front" and int(segment.id) == front_door_segment_id:
				_add_door_segment(root, generated, collision_root, slots, stats, normalized, source_catalog, material_cache, segment, floor, floor_base, floor_height)
			else:
				_add_wall_segment(root, generated, collision_root, slots, stats, normalized, source_catalog, material_cache, segment, floor, floor_base, floor_height, windows, window_width, window_height, sill)
		# Corner pillars preserve explicit support sockets and don't close openings by AABB.
		for pillar_segment in facade_segments:
			var pillar_facade := str(pillar_segment.facade)
			for pillar in pillar_segment.pillars:
				var pillar_key := str(pillar.key)
				if emitted_pillars.has(str(floor) + "_" + pillar_key):
					continue
				emitted_pillars[str(floor) + "_" + pillar_key] = true
				var pillar_id := "pillar_" + str(floor) + "_" + pillar_key
				if _is_disabled(pillar_id, normalized):
					continue
				var pillar_position := Vector3(pillar.position.x, floor_base + floor_height * 0.5, pillar.position.y)
				_add_box_slot(root, generated, collision_root, slots, stats, normalized, source_catalog, material_cache, pillar_id, "pillar", floor, pillar_facade, _component_for_slot("pillar", pillar_id, normalized), pillar_position, Vector3(normalized.column_width, floor_height, normalized.column_width), true)
	var roof_height := _total_floor_height(normalized)
	var roof_thickness := _floor_value(normalized, int(normalized.floors) - 1, "slab_thickness")
	var roof_cells: Array[Vector2i] = []
	for cell in occupied:
		var roof_id := "roof_" + str(cell.x) + "_" + str(cell.y)
		if _is_disabled(roof_id, normalized) or _damage_hit(normalized, roof_id):
			continue
		roof_cells.append(cell)
		var roof_size := _plate_size(cell, normalized, occupied)
		var roof_center := _cell_center(cell, normalized)
		_add_box_slot(root, generated, collision_root, slots, stats, normalized, source_catalog, material_cache, roof_id, "slab", int(normalized.floors), "", _component_for_slot("slab", roof_id, normalized), Vector3(roof_center.x, roof_height + roof_thickness * 0.5, roof_center.y), Vector3(roof_size.x, roof_thickness, roof_size.y), str(normalized.spatial_profile) != "scenic_underwater")
		var actual_roof := _slot_by_id(slots, roof_id)
		if str(normalized.spatial_profile) != "scenic_underwater" and not actual_roof.is_empty():
			walk_surfaces.append({"id": "walk_roof_" + str(cell.x) + "_" + str(cell.y), "floor": int(normalized.floors), "position": _surface_position(actual_roof), "size": _surface_size(actual_roof, normalized), "source_slots": [roof_id]})
	_add_vegetation(root, vegetation, slots, stats, normalized, source_catalog, material_cache, occupied, roof_cells, warnings)
	water_blockers = _make_water_blockers(root, slots, normalized)
	if str(normalized.spatial_profile) == "scenic_underwater":
		walk_surfaces.clear()
		water_blockers.clear()
	var generation_error := str(root.get_meta("workshop_generation_error", ""))
	if not generation_error.is_empty():
		root.free()
		empty.reason = generation_error
		return empty
	var node_count := _count_nodes(root)
	if node_count > MAX_NODES or int(stats.triangles) > MAX_TRIANGLES:
		root.free()
		empty.reason = "生成预算超限: nodes=" + str(node_count) + ", tris=" + str(stats.triangles)
		return empty
	for child in root.find_children("*", "Node", true, false):
		if child != root and child.owner == null:
			child.owner = root
	stats.nodes = node_count
	var result := {"ok": true, "reason": "", "root": root, "slots": slots, "stats": stats, "walk_surfaces": walk_surfaces, "water_blockers": water_blockers, "warnings": warnings}
	_apply_vegetation_variation(result, normalized, source_catalog)
	return result

## 幅度只改变实例姿态，不改变密度阈值、生长档抽样或玩法随机流。
## 最大幅度：平面偏移±0.25m、等比尺寸±20%、绕竖轴±180°；不倾斜根部。
static func _apply_vegetation_variation(build: Dictionary, recipe: Dictionary, catalog: Dictionary) -> void:
	var amount := float(recipe.vegetation_variation) if bool(recipe.vegetation_random_enabled) else 0.0
	if amount <= 0.0: return
	var root: Node3D = build.root
	var roof_faces := PackedVector3Array()
	# 连续模式屋顶已融合；直接取最终可见网格的水平顶面，绝不按整楼AABB假定支撑。
	for node in root.get_node("GeneratedVisual").find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var transform := _local_transform_to_ancestor(mesh_node, root)
		var faces := mesh_node.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var a: Vector3 = transform * faces[index]
			var b: Vector3 = transform * faces[index + 1]
			var c: Vector3 = transform * faces[index + 2]
			if absf(a.y - b.y) < 0.0001 and absf(a.y - c.y) < 0.0001 and -(b - a).cross(c - a).y > 0.000001:
				roof_faces.append_array(PackedVector3Array([a, b, c]))
	for slot: Dictionary in build.slots:
		if str(slot.kind) != "plant": continue
		var node := root.get_node(str(slot.node_path)) as Node3D
		var rng := RandomNumberGenerator.new()
		rng.seed = (str(recipe.vegetation_seed) + ":" + str(slot.id) + ":pose_v1").sha256_text().substr(0, 15).hex_to_int()
		var delta := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25)) * amount
		var scale_factor := 1.0 + rng.randf_range(-0.2, 0.2) * amount
		var yaw := rng.randf_range(-PI, PI) * amount
		var locked := false
		for entry: Dictionary in recipe.locked_vegetation:
			if str(entry.slot_id) == str(slot.id): locked = true
		# 藤蔓必须留在檐边；锁定只固定位置，仍可调整体量与朝向。
		var is_vine := str(catalog.components[str(slot.component_id)].get("profile", "")) == "vine"
		var candidate := node.position + delta
		if not locked and not is_vine and _vegetation_supported(candidate, roof_faces):
			node.position = candidate
		node.basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor) * node.basis
		var bounds := AABB()
		var has_bounds := false
		var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D: meshes.push_front(node)
		for child in meshes:
			var mesh_child := child as MeshInstance3D
			if mesh_child.mesh == null: continue
			var actual: AABB = _local_transform_to_ancestor(mesh_child, root) * mesh_child.mesh.get_aabb()
			bounds = bounds.merge(actual) if has_bounds else actual
			has_bounds = true
		slot.position = [node.position.x, node.position.y, node.position.z]
		slot.size = [bounds.size.x, bounds.size.y, bounds.size.z]
		slot.bounds_position = [bounds.position.x, bounds.position.y, bounds.position.z]
		slot.bounds_size = slot.size.duplicate()
		slot["vegetation_scale"] = scale_factor
		slot["vegetation_yaw"] = yaw

static func _vegetation_supported(point: Vector3, faces: PackedVector3Array) -> bool:
	for index in range(0, faces.size(), 3):
		if absf(point.y - faces[index].y) > 0.0002: continue
		var triangle := PackedVector2Array()
		for offset in 3:
			triangle.append(Vector2(faces[index + offset].x, faces[index + offset].z))
		if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), triangle): return true
	return false

static func _occupied_cells(recipe: Dictionary) -> Array[Vector2i]:
	var nx := maxi(1, int(ceil(float(recipe.width) / float(recipe.bay_width))))
	var nz := maxi(1, int(ceil(float(recipe.depth) / float(recipe.bay_width))))
	var result: Array[Vector2i] = []
	for x in range(nx):
		for z in range(nz):
			if str(recipe.shape) == "l" and x >= int(ceil(float(nx) * 0.5)) and z >= int(ceil(float(nz) * 0.5)):
				continue
			result.append(Vector2i(x, z))
	return result

static func _cell_size(cell: Vector2i, recipe: Dictionary) -> Vector2:
	return Vector2(float(recipe.width) / ceil(float(recipe.width) / float(recipe.bay_width)), float(recipe.depth) / ceil(float(recipe.depth) / float(recipe.bay_width)))

static func _plate_size(cell: Vector2i, recipe: Dictionary, occupied: Array[Vector2i]) -> Vector2:
	var base := _cell_size(cell, recipe)
	# 独立闭合板之间保留4mm接缝，不再用相叠盒子掩盖倒角缝。
	return base - Vector2(0.004, 0.004)

static func _cell_center(cell: Vector2i, recipe: Dictionary) -> Vector2:
	var size := _cell_size(cell, recipe)
	var x_start := float(cell.x) * size.x - float(recipe.width) * 0.5
	var z_start := float(cell.y) * size.y - float(recipe.depth) * 0.5
	return Vector2(x_start + size.x * 0.5, z_start + size.y * 0.5)

static func _boundary_segments(cells: Array[Vector2i], recipe: Dictionary) -> Array:
	var present: Dictionary = {}
	for cell in cells:
		present[cell] = true
	var result: Array = []
	for cell in cells:
		var center := _cell_center(cell, recipe)
		var size := _cell_size(cell, recipe)
		var sides := [["front", Vector2i(0, -1), Vector2(center.x, center.y - size.y * 0.5), Vector2(size.x, 0.0)], ["back", Vector2i(0, 1), Vector2(center.x, center.y + size.y * 0.5), Vector2(size.x, 0.0)], ["left", Vector2i(-1, 0), Vector2(center.x - size.x * 0.5, center.y), Vector2(0.0, size.y)], ["right", Vector2i(1, 0), Vector2(center.x + size.x * 0.5, center.y), Vector2(0.0, size.y)]]
		for side in sides:
			if present.has(cell + side[1]):
				continue
			var facade: String = str(side[0])
			var side_center: Vector2 = side[2]
			var segment_size: Vector2 = side[3]
			var pillar_a := Vector2(center.x - size.x * 0.5, side_center.y) if facade == "front" or facade == "back" else Vector2(side_center.x, center.y - size.y * 0.5)
			var pillar_b := Vector2(center.x + size.x * 0.5, side_center.y) if facade == "front" or facade == "back" else Vector2(side_center.x, center.y + size.y * 0.5)
			var grid_a := cell + (Vector2i(0, 1) if facade == "back" else (Vector2i(1, 0) if facade == "right" else Vector2i.ZERO))
			var grid_b := grid_a + (Vector2i(1, 0) if facade in ["front", "back"] else Vector2i(0, 1))
			var stable_segment_id := cell.x * 1024 + cell.y * 4 + FACADE_NAMES.find(facade)
			result.append({"id": stable_segment_id, "facade": facade, "center": side_center, "size": segment_size, "pillars": [{"key": str(grid_a.x) + "_" + str(grid_a.y), "position": pillar_a}, {"key": str(grid_b.x) + "_" + str(grid_b.y), "position": pillar_b}]})
	return result

static func _add_wall_segment(root: Node3D, generated: Node3D, collision_root: Node3D, slots: Array, stats: Dictionary, recipe: Dictionary, catalog: Dictionary, material_cache: Dictionary, segment: Dictionary, floor: int, floor_base: float, floor_height: float, windows: bool, window_width: float, window_height: float, sill: float) -> void:
	var facade := str(segment.facade)
	var center: Vector2 = segment.center
	var length := float(segment.size.x if facade == "front" or facade == "back" else segment.size.y)
	var wall_thickness := float(recipe.wall_thickness)
	length = maxf(0.05, length - float(recipe.column_width))
	var opening_width := minf(window_width, length - 0.22)
	if windows and (opening_width < 0.24 or window_height < 0.24 or sill < 0.12):
		root.set_meta("workshop_generation_error", "有效立面段无法容纳窗框与窗洞")
		return
	var wall_axis := Vector3(length, floor_height, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, floor_height, length)
	if not windows or opening_width <= wall_thickness:
		_add_if_alive(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "wall_" + facade + "_" + str(floor) + "_" + str(segment.id), "wall", floor, facade, _component_for_slot("wall", "", recipe), Vector3(center.x, floor_base + floor_height * 0.5, center.y), wall_axis, true)
		return
	var opening_center := 0.0
	var lower_height := maxf(0.05, sill - 0.06)
	var upper_height := maxf(0.05, floor_height - sill - window_height - 0.06)
	var side_length := maxf(0.05, (length - opening_width - 0.12) * 0.5)
	var side_axis := Vector3(side_length, floor_height, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, floor_height, side_length)
	for part in ["lower_a", "lower_b"]:
		var local_axis := -length * 0.5 + side_length * 0.5 if part == "lower_a" else length * 0.5 - side_length * 0.5
		_add_if_alive(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "wall_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_" + part, "wall", floor, facade, _component_for_slot("wall", "", recipe), _segment_position(center, facade, local_axis, floor_base + floor_height * 0.5), side_axis, true)
	var lower_axis := Vector3(opening_width - 0.12, lower_height, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, lower_height, opening_width - 0.12)
	_add_if_alive(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "wall_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_lower", "wall", floor, facade, _component_for_slot("wall", "", recipe), _segment_position(center, facade, 0.0, floor_base + lower_height * 0.5), lower_axis, true)
	var upper_axis := Vector3(opening_width - 0.12, upper_height, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, upper_height, opening_width - 0.12)
	_add_if_alive(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "wall_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_upper", "wall", floor, facade, _component_for_slot("wall", "", recipe), _segment_position(center, facade, opening_center, floor_base + sill + window_height + 0.06 + upper_height * 0.5), upper_axis, true)
	var sill_axis := Vector3(opening_width - 0.12, 0.12, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, 0.12, opening_width - 0.12)
	_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "frame_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_sill", "frame", floor, facade, _component_for_slot("frame", "", recipe), _segment_position(center, facade, opening_center, floor_base + sill), sill_axis, false)
	var side_frame_axis := Vector3(0.12, window_height, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, window_height, 0.12)
	for frame_side in ["a", "b"]:
		var frame_offset := -opening_width * 0.5 if frame_side == "a" else opening_width * 0.5
		_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "frame_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_" + frame_side, "frame", floor, facade, _component_for_slot("frame", "", recipe), _segment_position(center, facade, frame_offset, floor_base + sill + window_height * 0.5), side_frame_axis, false)
	var header_axis := Vector3(opening_width - 0.12, 0.12, wall_thickness) if facade == "front" or facade == "back" else Vector3(wall_thickness, 0.12, opening_width - 0.12)
	_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "frame_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_header", "frame", floor, facade, _component_for_slot("frame", "", recipe), _segment_position(center, facade, opening_center, floor_base + sill + window_height), header_axis, false)
	var glass_id := "glass_" + facade + "_" + str(floor) + "_" + str(segment.id)
	var glass_axis := Vector3(opening_width - 0.12, window_height - 0.12, 0.03) if facade == "front" or facade == "back" else Vector3(0.03, window_height - 0.12, opening_width - 0.12)
	_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, glass_id, "glass", floor, facade, _component_for_slot("glass", glass_id, recipe), _segment_position(center, facade, opening_center, floor_base + sill + window_height * 0.5), glass_axis, false)

static func _add_door_segment(root: Node3D, generated: Node3D, collision_root: Node3D, slots: Array, stats: Dictionary, recipe: Dictionary, catalog: Dictionary, material_cache: Dictionary, segment: Dictionary, floor: int, floor_base: float, floor_height: float) -> void:
	var facade := str(segment.facade)
	var center: Vector2 = segment.center
	var length := float(segment.size.x) - float(recipe.column_width)
	var opening_width := minf(float(recipe.door_width) + 0.12, length - float(recipe.wall_thickness) * 2.0)
	var side_length := maxf(0.05, (length - opening_width - 0.12) * 0.5)
	var side_axis := Vector3(side_length, floor_height, recipe.wall_thickness) if facade == "front" or facade == "back" else Vector3(recipe.wall_thickness, floor_height, side_length)
	for part in ["left", "right"]:
		var local_axis := -length * 0.5 + side_length * 0.5 if part == "left" else length * 0.5 - side_length * 0.5
		_add_if_alive(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "wall_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_door_" + part, "wall", floor, facade, _component_for_slot("wall", "", recipe), _segment_position(center, facade, local_axis, floor_base + floor_height * 0.5), side_axis, true)
	var lintel_height := maxf(0.05, floor_height - float(recipe.door_height) - 0.12)
	var lintel_axis := Vector3(opening_width - 0.12, lintel_height, recipe.wall_thickness) if facade == "front" or facade == "back" else Vector3(recipe.wall_thickness, lintel_height, opening_width - 0.12)
	_add_if_alive(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "wall_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_door_lintel", "wall", floor, facade, _component_for_slot("wall", "", recipe), _segment_position(center, facade, 0.0, floor_base + float(recipe.door_height) + 0.12 + lintel_height * 0.5), lintel_axis, true)
	var jamb_axis := Vector3(0.12, float(recipe.door_height), recipe.wall_thickness) if facade == "front" or facade == "back" else Vector3(recipe.wall_thickness, float(recipe.door_height), 0.12)
	for frame_side in ["left", "right"]:
		var frame_offset := -opening_width * 0.5 if frame_side == "left" else opening_width * 0.5
		_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "frame_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_door_" + frame_side, "frame", floor, facade, _component_for_slot("frame", "", recipe), _segment_position(center, facade, frame_offset, floor_base + float(recipe.door_height) * 0.5), jamb_axis, false)
	var door_header_axis := Vector3(opening_width - 0.12, 0.12, recipe.wall_thickness) if facade == "front" or facade == "back" else Vector3(recipe.wall_thickness, 0.12, opening_width - 0.12)
	_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, "frame_" + facade + "_" + str(floor) + "_" + str(segment.id) + "_door_header", "frame", floor, facade, _component_for_slot("frame", "", recipe), _segment_position(center, facade, 0.0, floor_base + float(recipe.door_height) + 0.06), door_header_axis, false)

static func _segment_position(center: Vector2, facade: String, local_axis: float, y: float) -> Vector3:
	if facade == "front" or facade == "back":
		return Vector3(center.x + local_axis, y, center.y)
	return Vector3(center.x, y, center.y + local_axis)

static func _add_if_alive(root: Node3D, generated: Node3D, collision_root: Node3D, slots: Array, stats: Dictionary, recipe: Dictionary, catalog: Dictionary, material_cache: Dictionary, slot_id: String, kind: String, floor: int, facade: String, component_id: String, position: Vector3, size: Vector3, collidable: bool) -> void:
	if _is_disabled(slot_id, recipe):
		return
	if kind == "wall" and _damage_hit(recipe, slot_id):
		return
	_add_box_slot(root, generated, collision_root, slots, stats, recipe, catalog, material_cache, slot_id, kind, floor, facade, component_id, position, size, collidable)

static func _add_box_slot(root: Node3D, generated: Node3D, collision_root: Node3D, slots: Array, stats: Dictionary, recipe: Dictionary, catalog: Dictionary, material_cache: Dictionary, slot_id: String, kind: String, floor: int, facade: String, component_id: String, position: Vector3, size: Vector3, collidable: bool, growth_key: String = "") -> void:
	var override: Dictionary = recipe.slot_overrides.get(slot_id, {})
	if bool(override.get("disabled", false)) or recipe.excluded_slots.has(slot_id):
		return
	if override.has("component_id"):
		component_id = str(override.component_id)
	if (kind == "glass" or slot_id.begins_with("roof_")) and _damage_hit(recipe, slot_id):
		return
	var offset: Array = override.get("offset", [0.0, 0.0, 0.0])
	var locked_position := false
	if kind == "plant":
		for entry in recipe.locked_vegetation:
			if str(entry.slot_id) == slot_id: locked_position = true
	if not locked_position:
		position += Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
	var component: Dictionary = catalog.components.get(component_id, {})
	var component_kind := str(component.get("kind", "parametric"))
	if component_kind == "prefab":
		_add_prefab_slot(root, generated, collision_root, slots, stats, recipe, catalog, slot_id, kind, floor, facade, component_id, position, size, collidable)
		return
	var mesh_data: Dictionary
	var applied_bevel := 0.0
	if kind == "plant":
		growth_key = str(override.get("growth_key", growth_key if not growth_key.is_empty() else "medium"))
		mesh_data = MeshBuilder.plant_mesh(str(component.get("profile", "shrub")), growth_key, str(component.get("color", "cozy")), float(recipe.aging), material_cache)
		size = mesh_data.mesh.get_aabb().size
	else:
		var palette := str(component.get("color", "timber"))
		if kind == "wall" and int(recipe.structure_seed) % 2 == 1:
			palette = "timber_dark"
		var joint_gap := 0.004
		var mesh_size := (size - Vector3(joint_gap, joint_gap, joint_gap)).max(Vector3(0.01, 0.01, 0.01)) if kind != "slab" else size
		var bevel := float(recipe.bevel_width)
		var profile_bevel := ""
		if kind == "slab": profile_bevel = "platform_board"
		elif kind == "pillar": profile_bevel = "main_column"
		if not profile_bevel.is_empty() and is_equal_approx(bevel, 0.06):
			if not material_cache.has("__standards"):
				var standard_file := FileAccess.open(STANDARDS_PATH, FileAccess.READ)
				material_cache["__standards"] = JSON.parse_string(standard_file.get_as_text())
				standard_file.close()
			var standard_data: Dictionary = material_cache["__standards"]
			bevel = float(standard_data.authoring_defaults.bevels_final_centimetres[profile_bevel]) * 0.01
		applied_bevel = minf(bevel, minf(mesh_size.x, minf(mesh_size.y, mesh_size.z)) * 0.45)
		mesh_data = MeshBuilder.rounded_box(mesh_size, applied_bevel, int(recipe.bevel_segments), palette, float(recipe.aging), material_cache, float(recipe.taper))
	if component.has("material_role"):
		mesh_data.mesh.surface_set_material(0, MeshBuilder.material(str(component.get("color", "cozy")), float(recipe.aging), material_cache, str(component.material_role)))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = slot_id
	mesh_instance.mesh = mesh_data.mesh
	mesh_instance.position = position
	mesh_instance.set_meta("slot_id", slot_id)
	mesh_instance.set_meta("component_id", component_id)
	mesh_instance.set_meta("slot_kind", kind)
	generated.add_child(mesh_instance)
	mesh_instance.owner = root
	stats.triangles += _mesh_triangle_count(mesh_data.mesh)
	stats.visual_meshes += 1
	if kind == "plant":
		stats.plant_meshes += 1
	var node_path := str(root.get_path_to(mesh_instance))
	var bounds: AABB = mesh_instance.transform * mesh_instance.mesh.get_aabb()
	var slot := {"id": slot_id, "kind": kind, "floor": floor, "facade": facade, "component_id": component_id, "position": [position.x, position.y, position.z], "size": [size.x, size.y, size.z], "node_path": node_path, "bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z], "bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]}
	if kind == "plant": slot["growth_key"] = growth_key
	else: slot["bevel_width"] = applied_bevel
	slots.append(slot)
	if collidable and str(recipe.spatial_profile) != "scenic_underwater" and kind != "plant":
		var body := StaticBody3D.new()
		body.name = "Collision_" + slot_id
		body.collision_layer = 256 if str(recipe.spatial_profile) == "above_water" else DIVE_COLLISION_LAYER
		body.collision_mask = 0
		body.set_meta("slot_id", slot_id)
		body.set_meta("component_id", component_id)
		collision_root.add_child(body)
		body.owner = root
		var shape_node := CollisionShape3D.new()
		shape_node.name = "Shape"
		var shape: Shape3D = mesh_data.mesh.create_trimesh_shape()
		shape_node.shape = shape
		body.add_child(shape_node)
		shape_node.owner = root
		body.position = position
		stats.collision_shapes += 1
		stats.nodes += 2

static func _add_prefab_slot(root: Node3D, generated: Node3D, collision_root: Node3D, slots: Array, stats: Dictionary, recipe: Dictionary, catalog: Dictionary, slot_id: String, kind: String, floor: int, facade: String, component_id: String, position: Vector3, size: Vector3, collidable: bool) -> void:
	var definition: Dictionary = catalog.components.get(component_id, {})
	var prefab_path := str(definition.get("prefab", ""))
	var packed := load(prefab_path) as PackedScene
	if packed == null:
		return
	if not prefab_path.begins_with(Catalog.PREFAB_ROOT) or prefab_path.contains("..") or Catalog._state_contains_script(packed.get_state()):
		root.set_meta("workshop_generation_error", "prefab包含脚本节点: " + component_id)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		root.set_meta("workshop_generation_error", "prefab根必须为Node3D: " + component_id)
		return
	var source_transform := instance.transform
	var prefab_meshes: Array[MeshInstance3D] = []
	if instance is MeshInstance3D:
		prefab_meshes.append(instance)
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		prefab_meshes.append(node)
	var actual_aabb := AABB()
	var has_aabb := false
	for mesh_node in prefab_meshes:
		if mesh_node.mesh == null:
			continue
		var mesh_transform := source_transform * _local_transform_to_ancestor(mesh_node, instance)
		var mesh_aabb: AABB = mesh_transform * mesh_node.mesh.get_aabb()
		actual_aabb = mesh_aabb if not has_aabb else actual_aabb.merge(mesh_aabb)
		has_aabb = true
	var nominal: Array = definition.get("nominal_size", [])
	var yaw: float = float({"-Z": 0.0, "+Z": PI, "+X": PI * 0.5, "-X": -PI * 0.5}.get(str(definition.front_axis), 0.0))
	var orientation := Basis(Vector3.UP, float(yaw))
	var oriented_aabb: AABB = Transform3D(orientation, Vector3.ZERO) * actual_aabb
	if not has_aabb or nominal.size() != 3 or not _size_matches(Vector3(float(nominal[0]), float(nominal[1]), float(nominal[2])), actual_aabb.size) or not _size_matches(size, oriented_aabb.size):
		instance.free()
		root.set_meta("workshop_generation_error", "prefab尺寸接口不兼容: " + component_id)
		return
	instance.name = slot_id
	var pivot: Array = definition.pivot
	instance.transform = Transform3D(orientation, position - orientation * Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))) * source_transform
	generated.add_child(instance)
	instance.owner = root
	instance.set_meta("slot_id", slot_id)
	instance.set_meta("component_id", component_id)
	instance.set_meta("slot_kind", kind)
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		node.set_meta("slot_id", slot_id)
		node.set_meta("component_id", component_id)
		node.owner = root
	if collidable and str(recipe.spatial_profile) != "scenic_underwater" and collision_root != null:
		for node in prefab_meshes:
			if node.mesh == null:
				continue
			var body := StaticBody3D.new()
			body.name = "Collision_" + slot_id
			body.collision_layer = 256 if str(recipe.spatial_profile) == "above_water" else DIVE_COLLISION_LAYER
			body.collision_mask = 0
			body.set_meta("slot_id", slot_id)
			body.set_meta("component_id", component_id)
			collision_root.add_child(body)
			body.owner = root
			var shape_node := CollisionShape3D.new()
			shape_node.shape = node.mesh.create_trimesh_shape()
			body.add_child(shape_node)
			shape_node.owner = root
			body.transform = instance.transform * _local_transform_to_ancestor(node, instance)
			stats.collision_shapes += 1
			stats.nodes += 2
	var node_path := str(root.get_path_to(instance))
	var prefab_bounds: AABB = Transform3D(orientation, position - orientation * Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))) * actual_aabb
	slots.append({"id": slot_id, "kind": kind, "floor": floor, "facade": facade, "component_id": component_id, "position": [position.x, position.y, position.z], "size": [size.x, size.y, size.z], "node_path": node_path, "bounds_position": [prefab_bounds.position.x, prefab_bounds.position.y, prefab_bounds.position.z], "bounds_size": [prefab_bounds.size.x, prefab_bounds.size.y, prefab_bounds.size.z]})
	for mesh_node in prefab_meshes:
		if mesh_node.mesh != null:
			stats.triangles += _mesh_triangle_count(mesh_node.mesh)
	stats.visual_meshes += prefab_meshes.size()
	if kind == "plant": stats.plant_meshes += prefab_meshes.size()
	stats.nodes += _count_nodes(instance)

static func _add_vegetation(root: Node3D, vegetation: Node3D, slots: Array, stats: Dictionary, recipe: Dictionary, catalog: Dictionary, material_cache: Dictionary, occupied: Array[Vector2i], roof_cells: Array[Vector2i], warnings: Array) -> void:
	var locked: Dictionary = {}
	for entry in recipe.locked_vegetation:
		locked[str(entry.slot_id)] = entry
	var emitted: Dictionary = {}
	for cell in occupied:
		var slot_id := "plant_roof_" + str(cell.x) + "_" + str(cell.y)
		var roof := _slot_by_id(slots, "roof_" + str(cell.x) + "_" + str(cell.y))
		if roof.is_empty(): continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _sha256_text(str(recipe.vegetation_seed) + ":" + slot_id).substr(0, 8).hex_to_int()
		var entry: Dictionary = locked.get(slot_id, {})
		if rng.randf() >= float(recipe.vegetation_density) and entry.is_empty(): continue
		var override: Dictionary = recipe.slot_overrides.get(slot_id, {})
		var component_id := str(override.get("component_id", recipe.component_bindings.plant))
		var profile := str(catalog.components[component_id].get("profile", "shrub"))
		var growth := str(override.get("growth_key", entry.get("growth_key", _choose_growth(recipe.growth_weights, rng))))
		var roof_min: Array = roof.get("bounds_position", roof.position)
		var roof_extent: Array = roof.get("bounds_size", roof.size)
		var position := Vector3(float(roof_min[0]) + float(roof_extent[0]) * 0.5, float(roof_min[1]) + float(roof_extent[1]), float(roof_min[2]) + float(roof_extent[2]) * 0.5)
		if entry.is_empty() and profile == "vine":
			var direction := Vector2i.ZERO
			for neighbor in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				if not roof_cells.has(cell + neighbor):
					direction = neighbor
					break
			if direction == Vector2i.ZERO: continue
			var roof_taper := 1.0 - float(recipe.taper)
			position.x += direction.x * (float(roof.size[0]) * 0.5 - float(roof.get("bevel_width", recipe.bevel_width))) * roof_taper
			position.z += direction.y * (float(roof.size[2]) * 0.5 - float(roof.get("bevel_width", recipe.bevel_width))) * roof_taper
		if not entry.is_empty():
			position = Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2]))
		_add_box_slot(root, vegetation, null, slots, stats, recipe, catalog, material_cache, slot_id, "plant", int(recipe.floors), "roof", component_id, position, _growth_size(growth, profile), false, growth)
		emitted[slot_id] = true
	for slot_id in locked:
		if not emitted.has(slot_id): warnings.append("锁定植物的支撑屋顶不存在或已排除: " + str(slot_id))

static func _growth_size(growth: String, profile: String) -> Vector3:
	var base := Vector3(0.9, 1.25, 0.9)
	if profile == "tree":
		base = Vector3(1.8, 4.8, 1.8)
	elif profile == "vine":
		base = Vector3(0.22, 2.4, 0.22)
	elif profile == "moss":
		base = Vector3(1.6, 0.25, 1.6)
	var scale := 1.0
	if growth == "small": scale = 0.72
	elif growth == "large": scale = 1.28
	return base * scale

static func _choose_growth(weights: Array, rng: RandomNumberGenerator) -> String:
	var total := float(weights[0]) + float(weights[1]) + float(weights[2])
	var pick := rng.randf() * total
	if pick < float(weights[0]): return "small"
	if pick < float(weights[0]) + float(weights[1]): return "medium"
	return "large"

static func _floor_value(recipe: Dictionary, floor: int, field: String) -> float:
	var override: Dictionary = recipe.floor_overrides.get(str(floor), {})
	return float(override.get(field, recipe.get(field, 0.0)))

static func _floor_base(recipe: Dictionary, floor: int) -> float:
	var result := 0.0
	for index in range(floor):
		result += _floor_value(recipe, index, "floor_height")
	return result

static func _total_floor_height(recipe: Dictionary) -> float:
	return _floor_base(recipe, int(recipe.floors))

static func _component_for_slot(kind: String, slot_id: String, recipe: Dictionary) -> String:
	var family := kind
	if kind == "slab": family = "slab"
	var override: Dictionary = recipe.slot_overrides.get(slot_id, {})
	return str(override.get("component_id", recipe.component_bindings.get(family, "")))

static func _is_disabled(slot_id: String, recipe: Dictionary) -> bool:
	if recipe.excluded_slots.has(slot_id): return true
	var override: Dictionary = recipe.slot_overrides.get(slot_id, {})
	return bool(override.get("disabled", false))

static func _front_door_segment_id(segments: Array) -> int:
	var best_id := -1
	var best_x := INF
	for segment in segments:
		if str(segment.get("facade", "")) != "front":
			continue
		var center: Vector2 = segment.get("center", Vector2.ZERO)
		if absf(center.x) < best_x:
			best_x = absf(center.x)
			best_id = int(segment.get("id", -1))
	return best_id

static func _make_water_blockers(root: Node3D, slots: Array, recipe: Dictionary) -> Array:
	var result: Array = []
	if str(recipe.spatial_profile) != "above_water": return result
	for slot in slots:
		if str(slot.kind) not in ["wall", "pillar", "slab"] or str(slot.id).begins_with("roof_"): continue
		var node := root.get_node_or_null(str(slot.node_path)) as Node3D
		if node == null: continue
		var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D: meshes.push_front(node)
		for mesh_node in meshes:
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance.mesh == null: continue
			var transform := _local_transform_to_ancestor(mesh_instance, root)
			var faces := mesh_instance.mesh.get_faces()
			var points: Array[Vector3] = []
			for start in range(0, faces.size(), 3):
				var triangle := [transform * faces[start], transform * faces[start + 1], transform * faces[start + 2]]
				for edge in 3:
					var a: Vector3 = triangle[edge]
					var b: Vector3 = triangle[(edge + 1) % 3]
					if absf(a.y) <= 0.00001: points.append(a)
					if a.y * b.y < 0.0: points.append(a.lerp(b, -a.y / (b.y - a.y)))
			if points.is_empty(): continue
			var bounds := AABB(points[0], Vector3.ZERO)
			for point in points: bounds = bounds.expand(point)
			if bounds.size.x <= 0.00001 or bounds.size.z <= 0.00001: continue
			result.append({"kind": "local_waterline_slice", "source_slots": [str(slot.id)], "source_node_path": str(slot.node_path), "waterline_y": 0.0, "position": [bounds.get_center().x, bounds.get_center().z], "size": [bounds.size.x, bounds.size.z]})
	return result

static func _surface_position(slot: Dictionary) -> Vector3:
	var minimum: Array = slot.get("bounds_position", slot.position)
	var extent: Array = slot.get("bounds_size", slot.size)
	return Vector3(float(minimum[0]) + float(extent[0]) * 0.5, float(minimum[1]) + float(extent[1]), float(minimum[2]) + float(extent[2]) * 0.5)

static func _surface_size(slot: Dictionary, recipe: Dictionary) -> Array:
	var extent: Array = slot.get("bounds_size", slot.size)
	var inset := float(slot.get("bevel_width", minf(float(recipe.bevel_width), float(extent[1]) * 0.45)))
	return [maxf(0.0, float(extent[0]) * (1.0 - float(recipe.taper)) - inset * 2.0), maxf(0.0, float(extent[2]) * (1.0 - float(recipe.taper)) - inset * 2.0)]

static func _slot_by_id(slots: Array, slot_id: String) -> Dictionary:
	for slot in slots:
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}

static func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

static func _damage_hit(recipe: Dictionary, slot_id: String) -> bool:
	var damage := float(recipe.damage)
	if damage <= 0.0:
		return false
	var digest := _sha256_text(str(recipe.damage_seed) + ":" + slot_id)
	var sample := digest.substr(0, 8).hex_to_int()
	return float(sample) / 4294967295.0 < damage * 0.18

static func _local_transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

static func _size_matches(expected: Vector3, actual: Vector3) -> bool:
	var tolerance := 0.05
	return absf(expected.x - actual.x) <= tolerance and absf(expected.y - actual.y) <= tolerance and absf(expected.z - actual.z) <= tolerance

static func _mesh_triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	return int(mesh.get_faces().size() / 3)

static func _validate_standards() -> String:
	var file := FileAccess.open(STANDARDS_PATH, FileAccess.READ)
	if file == null:
		return "缺少标准文件"
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return "标准文件不是对象"
	if str(parsed.get("schema", "")) != "sea.workshop.building_standards" or int(parsed.get("schema_version", -1)) != 1:
		return "标准文件版本不匹配"
	if str(parsed.get("standards_id", "")) != "sea_building_v1" or str(parsed.get("source", "")) != "skill_machine_table":
		return "标准文件来源或ID不匹配"
	if str(parsed.get("source_path", "")) != ".agents/skills/sea-scene-component-authoring/references/building_scale.json" or str(parsed.get("runtime_mirror_path", "")) != STANDARDS_PATH:
		return "标准文件未绑定skill机器表运行镜像"
	if str(parsed.get("source_sha256", "")) != "265ce13585b118addb6bd32c932983d5d08768aee6f0ae4818a222ab969dd13f":
		return "skill机器表哈希不匹配"
	var raw_version: Variant = parsed.get("schema_version", null)
	if not (raw_version is int or raw_version is float) or float(raw_version) != 1.0:
		return "标准文件版本不匹配"
	if not parsed.get("limits", null) is Dictionary or int(parsed.limits.get("max_nodes", 0)) != MAX_NODES or int(parsed.limits.get("max_triangles", 0)) != MAX_TRIANGLES:
		return "标准文件预算不匹配"
	var bevel_policy: Dictionary = parsed.get("bevel_policy", {})
	if float(bevel_policy.get("wall_default", -1.0)) <= 0.0 or float(bevel_policy.get("slab_default", -1.0)) <= 0.0:
		return "标准文件倒角策略缺失"
	if str(bevel_policy.get("status", "")) != "v1_skill_profiles_with_local_thickness_validation":
		return "标准文件倒角策略未声明V1简化"
	return ""

static func _standards_fingerprint() -> String:
	var file := FileAccess.open(STANDARDS_PATH, FileAccess.READ)
	if file == null:
		return ""
	file.close()
	return FileAccess.get_sha256(STANDARDS_PATH)

static func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count
