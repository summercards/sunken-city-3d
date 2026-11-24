extends SceneTree
## Offline collision authoring. Outputs go to the isolated project's outputs.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var zones := scene.get_node("World/Zones")
	var home := zones.get_node("Zone1HomeHarbor")
	var station := zones.get_node("Zone2YokohamaStation")
	var aqua := zones.get_node("Zone5AquaPlatform")
	var sites := scene.get_node("World/SeaStructures")
	var shop := sites.get_node("floating_shop")
	var arcade := sites.get_node("rooftop_arcade")
	var neon := sites.get_node("neon_garden_quarter")
	var ranch := sites.get_node("rooftop_ranch")
	var bedroom := scene.get_node("World/Interior")
	_export("salvage_collision", home.get_node("Models/绞盘打捞台"), ["salvage_station/绞盘打捞台-海上区域-01_001"], [], 12288)
	_export("fishery_collision", home.get_node("Models/绞盘打捞台/WildFishery"), ["Land"], [], 12288)
	for unit: String in ["unit_01", "unit_02", "unit_03"]:
		var platform := station.find_child(unit, true, false) as Node3D
		_export("station_" + unit + "_collision", platform, ["."], [], 12288)
	_export("station_gangway_collision", station.get_node("Gangway"), ["Deck", "ShimEast", "RailNorth", "RailSouth", "PostNW", "PostNE", "PostSW", "PostSE"], [], 8192)
	_export("aqua_collision", aqua.find_child("unit_01", true, false), ["."], [], 12288)
	_export("shop_deck_collision", shop.get_node("Visual"), ["Structure/deck_001"], [], 8192, true)
	_export("shop_walls_collision", shop.get_node("Visual"), [], ["glass_bay_", "back_panel_", "back_door_", "rail_bar_", "rail_corner_"], 8192, true)
	_export("arcade_deck_collision", arcade, ["Visual/deck_surface_002", "Visual/arcade_blue_333", "Visual/arcade_yellow_334", "Visual/heater_339"], ["brick_mortar_", "window_", "loft_deck_"], 8192)
	_export("arcade_hull_collision", arcade, ["Visual/float_base_001"], [], 4096)
	var stair_foot := neon.get_node("Visual/StairFoot")
	_export("neon_stair_foot_collision", stair_foot, ["Deck"], [], 12288)
	var left := neon.get_node("Visual/LeftBuilding")
	_export("neon_left_collision", left, ["street_deck_119"], ["parapet_", "broken_parapet_", "roof_room_", "left_storey_", "left_damaged_"], 12288)
	var rear := neon.get_node("Visual/RearBuilding")
	_export("neon_rear_collision", rear, ["street_deck_292"], ["parapet_", "roof_room_", "back_storey_", "back_damaged_"], 12288)
	var right := neon.get_node("Visual/RightBuilding")
	_export("neon_right_collision", right, ["round_roof_291"], ["parapet_", "roof_room_", "round_storey_", "round_damaged_"], 12288)
	var bridge := neon.get_node("Visual/GardenBridge")
	_export("neon_bridge_collision", bridge, ["garden_bridge_394", "roof_soil_395"], ["crop_bed_", "planter_"], 8192)
	_export("ranch_collision", ranch, [], ["ORF2_实例_parapet.", "ORF3_实例_stair_landing.022"], 8192)
	_export("ranch_hull_collision", ranch, ["Models/ORF2_实例_shell"], [], 4096)
	_export("rest_stop_hull_collision", sites.get_node("floating_rest_stop"), ["Visual"], [], 4096)
	_export("water_building_001_hull_collision", sites.get_node("water_building_001"), ["Visual"], [], 4096)
	_export("water_building_002_hull_collision", sites.get_node("water_building_002"), ["Visual/Structure"], [], 4096)
	_export("room_wall_collision", bedroom.get_node("Shell"), ["WallWindow/Visual/后墙", "WallDoor/Visual/前墙", "WallEast/Visual/东墙", "WallWest/Visual/西墙", "Porch/Visual/前厅玻璃_东", "Porch/Visual/前厅玻璃_西", "Porch/Visual/前厅正面玻璃_右", "Porch/Visual/前厅正面玻璃_左"], [], 8192)
	for name in DirAccess.get_files_at("res://scenes/buildables/kit"):
		if not name.ends_with(".tscn"): continue
		var item := (load("res://scenes/buildables/kit/" + name) as PackedScene).instantiate() as Node3D
		if item.content_id not in ["stairs", "stairs_5m", "windmill", "flag", "wind_chime", "raft_4x4", "raft_2x4", "platform_5x5"]:
			_export("kit_" + item.content_id, item, ["Model"], [], 8192)
		item.free()
	scene.free()
	print("[surface-collision-authoring] complete")
	quit()

func _export(label: String, source: Node3D, paths: Array, prefixes: Array, layer: int, moving := false) -> void:
	var faces := PackedVector3Array()
	for path: String in paths:
		var node := source.get_node_or_null(path) as Node3D
		if node == null:
			push_error(label + " missing " + path)
			continue
		faces.append_array(_faces(node, _pose(source, node)))
	for node: Node3D in source.find_children("*", "Node3D", true, false):
		for prefix: String in prefixes:
			if str(node.name).begins_with(prefix):
				faces.append_array(_faces(node, _pose(source, node)))
				break
	if faces.is_empty():
		push_error(label + " no geometry")
		return
	var body: StaticBody3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
	body.name = label.to_pascal_case()
	body.collision_layer = layer
	body.collision_mask = 0
	if moving: body.sync_to_physics = false
	var collider := CollisionShape3D.new()
	collider.name = "Mesh"
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	collider.shape = shape
	body.add_child(collider)
	collider.owner = body
	var packed := PackedScene.new()
	packed.pack(body)
	ResourceSaver.save(packed, "res://outputs/" + label + ".scn", ResourceSaver.FLAG_COMPRESS)
	body.free()
	print(label, " faces=", faces.size() / 3)

func _pose(root_node: Node3D, node: Node3D) -> Transform3D:
	var pose := Transform3D.IDENTITY
	while node != root_node:
		pose = node.transform * pose
		node = node.get_parent()
	return pose

func _faces(node: Node3D, pose: Transform3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if node is MeshInstance3D:
		var local: PackedVector3Array = node.mesh.get_faces()
		for i in range(0, local.size(), 3):
			var a := pose * local[i]
			var b := pose * local[i + 1]
			var c := pose * local[i + 2]
			if (b - a).cross(c - a).length_squared() < 0.0000000001: continue
			faces.append_array(PackedVector3Array([a, b, c]))
	for child in node.get_children():
		if child is Node3D:
			faces.append_array(_faces(child, pose * child.transform))
	return faces

