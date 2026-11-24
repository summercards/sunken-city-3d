extends SceneTree

const Transfer := preload("res://src/navigation/berth_transfer.gd")
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const REPAIRS := [&"west", &"center", &"east", &"greenhouse_floor", &"tower_floor", &"house", &"greenhouse", &"tower"]
var checks := 0
var failures := 0
var ranch: Node3D
var main: Node
var actor: CharacterBody3D
var pieces := {}
var drop := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	main._autosave_on = false
	main.set_physics_process(false)
	actor = main.player
	ranch = main.get_node("World/SeaStructures/rooftop_ranch")
	_check(ranch.get_meta("asset_id") == "SEA-SCENE-ORF7-ASSEMBLY" and ranch.get_meta("asset_version") == "v014", "official v014 assembly")
	drop = ranch.get_meta("lowered_m")
	for node: Node3D in ranch.get_node("Models").get_children():
		if node.has_meta("component_key"):
			pieces[node.get_meta("placement")] = node
	_check(pieces.size() == 453, "453 separate placements, with the new shell and furnishings")
	_check(ranch.find_children("*", "*", true, false).all(
		func(node: Node) -> bool:
			return not node.name.begins_with("ORF") and not node.scene_file_path.ends_with("ranch_collision.scn") \
				and not node.scene_file_path.ends_with("ranch_hull_collision.scn")), "legacy shed, structure and collision removed")
	_verify_assets()
	_verify_submerged_levels()
	var growth := ranch.get_node("Models/RuinVegetation")
	var regions := growth.get_node("Regions")
	_check(growth.placement_count >= 500 and regions.get_child_count() == REPAIRS.size(), "workshop plants batch by repair region")
	_check(growth.find_children("*", "CollisionObject3D", true, false).is_empty(), "wild growth owns no blockers or interactions")
	var plant_keys := {}
	for batch: MultiMeshInstance3D in growth.batches:
		plant_keys[batch.get_meta("asset_key")] = true
	_check(plant_keys.size() == 3, "three shared workshop plant assets")
	var planter: Node3D = pieces["Planter.006"]
	_check(not planter.visible and planter.get_node("Solid").collision_layer == 0, "entry planter absent in starting ruin")
	_check(not pieces["Greenhouse Base"].visible and not pieces["Greenhouse Glazing"].visible, "greenhouse begins collapsed")
	var visual := DisplayServer.get_name() != "headless"
	await physics_frame
	await physics_frame
	if visual:
		await _shot("01_damaged", Vector3(0, 61.1, 0), Vector3(-26, 26, 37), 40.0)
		await _shot("02_damaged_access", Vector3(17.6, 59.7, 2.9), Vector3(11, 7, 13), 12.0)
		await _shot("10_wild_growth_close", Vector3(1, 62.4, -0.3), Vector3(-10, 16, 22), 27.0)
	var berth: Node3D = ranch.landing_point("main")
	var park := berth.get_node("BoatPark") as Node3D
	main.boat.place_at(park.global_position, park.global_rotation.y)
	var transfer := Transfer.new()
	for frame in 12:
		await physics_frame
		if transfer.hull_at_berth(main.boat, berth):
			break
	var boarding := transfer.inspect(main.boat, actor, berth, true, true)
	_check(boarding.has("point"), "real hull, docking trigger and capsule landing " + str(boarding))
	var stand: Vector3 = boarding.get("point", berth.global_position)
	_check(absf(park.global_position.y - 1.12) < .01 and absf(stand.y - 1.43) < .03,
		"boat and dock stay at sea-level transfer heights")
	var old_step := ranch.to_global(Vector3(-5.37, 62.24, 5.65))
	main.restore_world_state({"zone":"rooftop_ranch","landing":"main","mode":0,"boat":[],
		"player":[old_step.x,old_step.y,old_step.z]})
	_check(actor.global_position.distance_to(old_step - Vector3.UP * drop) < .05
		or actor.global_position.distance_to(stand) < .05, "previous roof save recovers a supported landing")
	var old_collapsed := ranch.to_global(Vector3(-9.675, 62.60, 3.435))
	main.restore_world_state({"zone":"rooftop_ranch","landing":"main","mode":0,"boat":[],
		"player":[old_collapsed.x,old_collapsed.y,old_collapsed.z]})
	_check(actor.global_position.distance_to(stand) < .05, "save above a collapsed tile recovers the berth")
	var boat_pose := Transform3D(park.global_basis, park.global_position)
	var contact := KinematicCollision3D.new()
	_check(main.boat.test_move(boat_pose, -ranch.global_basis.z * 4.0, contact)
		and ranch.is_ancestor_of(contact.get_collider()), "hull hits the new waterline structure")
	_place_actor(stand)
	var path_points := [
		Vector3(17.83, 57.35 + drop, 5.59), Vector3(17.83, 57.53 + drop, 4.58),
		Vector3(17.83, 58.97871 + drop, 0.00), Vector3(19.27, 58.97871 + drop, 0.00),
		Vector3(19.27, 62.24, 4.52), Vector3(16.05, 62.24, 4.55),
		Vector3(16.05, 62.24, 5.65), Vector3(-11.825, 62.60, 5.65),
		Vector3(-11.825, 62.60, 1.72),
	]
	for point: Vector3 in path_points:
		if not await _walk_to(point):
			break
	for index in range(path_points.size() - 2, -1, -1):
		if not await _walk_to(path_points[index]):
			break
	var stations := ranch.get_node("NpcStations")
	var anchors: Dictionary = stations.anchor_snapshot()
	_check(anchors.size() == 25, "25 resident markers resolve on persistent paving")
	for key: String in anchors:
		var at: Vector3 = anchors[key].position
		# Resident capsules can occupy their own markers. Check the building
		# layer separately so occupant presence doesn't invalidate the floor.
		var capsule := actor.get_node("BodyCollision") as CollisionShape3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule.shape
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.02) * capsule.transform
		query.collision_mask = 8192
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.12, at - Vector3.UP * 0.1, 8192)
		var space := root.world_3d.direct_space_state
		var hit := space.intersect_ray(ray)
		_check(not hit.is_empty() and hit.normal.y > 0.96 and space.intersect_shape(query, 1).is_empty(),
			"resident footing " + key)
	var west: Node3D = pieces["Paving 04.02"]
	var west_floor := west.get_node("Solid") as StaticBody3D
	var west_final := ranch.to_global(Vector3(-9.675, 62.60 - drop, 3.435))
	var walk: Node3D = berth.get_parent()
	for key: StringName in REPAIRS:
		var target: Vector3 = ranch.get_node("RepairPrompts/" + key).global_position
		_check(not ranch.ground_space.native_route(stand, target).is_empty(), str(key) + " connects to dock navigation before repair")
	_check(west_floor.collision_layer == 0 and not walk.surface_point(west_final).is_finite(),
		"sunken tile has no invisible roof support")
	var house: Node3D = pieces["House Shell"]
	_check(absf(house.rotation_degrees.y - 5.0) < 0.02, "damaged house preserves rotation")
	var wall := house.get_node("Solid") as StaticBody3D
	_check(wall.get_child_count() >= 8, "house walls have separate collision segments")
	var fallen: Node3D = pieces["Water tank lying on its side"]
	var debris: Node3D = pieces["Greenhouse Debris"]
	var tower: Node3D = pieces["Replacement upright water tank"]
	_check(fallen.visible and absf(fallen.basis.y.normalized().dot(Vector3.UP)) < 0.4
		and debris.visible and not tower.visible, "collapsed greenhouse and sideways tank at entry")
	var door: Node3D = pieces["Entry Assembly"]
	_check(door.get_node("Solid").collision_layer == 0, "damaged doorway stays open")
	var animation := ranch.get_node("BuildingAnimation") as AnimationPlayer
	_check(animation.get_animation_list().size() == 9 and not ranch.can_repair(&"construction"), "eight repairs gate one construction")
	for key: StringName in REPAIRS:
		await _verify_repair(key, animation)
		for other: Node3D in regions.get_children():
			_check(other.visible == (ranch.repair_progress(other.name) != &"complete"),
				"only repaired areas clear vegetation " + str(key) + "/" + str(other.name))
	_check(west_floor.collision_layer == 8192 and walk.surface_point(west_final).distance_to(west_final) < 0.03,
		"settled tile restores support and walking surface")
	_check(not fallen.visible and not debris.visible and not tower.visible, "clearance clips leave bases ready for construction")
	_check(absf(house.rotation_degrees.y - 7.0) < 0.02, "repaired house preserves authored angle")
	if visual:
		await _shot("03_repaired", Vector3(0, 62.6, 0), Vector3(-26, 30, 36), 41.0)
	await _start_prompt(&"construction")
	animation.pause()
	animation.seek(0.25, true, true)
	var greenhouse: Node3D = pieces["Greenhouse Base"]
	_check(greenhouse.visible and greenhouse.position.y > 10.45
		and greenhouse.get_node("Solid").collision_layer == 0, "greenhouse descends before its solids engage")
	if visual:
		await _shot("04_construction", Vector3(2, 63, 0), Vector3(-22, 26, 35), 40.0)
	_complete_clip(animation, &"construction")
	await physics_frame
	await physics_frame
	_check(ranch.repair_progress(&"construction") == &"complete" and not ranch.can_repair(&"construction"),
		"construction completes once in this scene")
	_check(tower.visible and pieces["Greenhouse Glazing"].visible and pieces["Windmill"].visible
		and door.get_node("Solid").collision_layer == 8192, "upright tank, greenhouse, windmill and installed door")
	_check(planter.visible and planter.get_node("Solid").collision_layer == 8192 and planter.position.x < 13.5,
		"planter lands beside the path with its own solid")
	for plant: Node3D in [pieces["Greens.008"], pieces["Greens.009"]]:
		_check(plant.visible and absf(plant.position.x - planter.position.x) < 0.46
			and absf(plant.position.z - planter.position.z) < 0.17, "foliage lands in relocated planter")
	_check(greenhouse.get_node("Solid").get_child_count() >= 20
		and greenhouse.get_node("Solid").collision_layer == 8192, "plinth segments engage at completion")
	for point: Vector3 in [Vector3(1.0, 62.24, 5.65), Vector3(16.05, 62.24, 5.65),
			Vector3(16.05, 62.24, 4.55), Vector3(19.27, 62.24, 4.52)]:
		if not await _walk_to(point):
			break
	var before_move: Vector3 = wall.global_position
	house.position.x += 0.4
	_check(wall.global_position.distance_to(before_move) > 0.38, "wall collider follows its own component")
	house.position.x -= 0.4
	if visual:
		await _shot("05_finished", Vector3(0, 62.6, 0), Vector3(-26, 30, 36), 41.0)
		await _shot("06_house", Vector3(-11, 64.5, -1.9), Vector3(-10, 9, 15), 13.0)
		await _shot("07_main_facade", Vector3(3.0, 59.4, 6.0), Vector3(-11, 8, 24), 34.0)
		await _shot("08_corner_and_stair", Vector3(15.6, 60.0, 4.1), Vector3(15, 8, 12), 15.0)
		await _shot("09_greenhouse_paving", Vector3(10.3, 63.4, 1.9), Vector3(-9, 8, 12), 14.0)
	current_scene = null
	root.remove_child(main)
	main.free()
	print("[rooftop-ranch] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _verify_assets() -> void:
	var catalog := {}
	var colors := {}
	for instance: Node3D in pieces.values():
		var key: String = instance.get_meta("component_key")
		if catalog.has(key):
			continue
		catalog[key] = true
		var visual := instance.get_node("Visual")
		var structural := key.begins_with("facade_bay") or key in ["base_slab", "edge_beam", "beam_corner", "corner_pier"]
		var version := "v011" if structural else "v010"
		if key in ["deck_tile_c", "greenhouse_base"]:
			version = "v012"
		if key == "access_stairs":
			version = "v014"
		_check(instance.scene_file_path.ends_with("/" + version + "/" + key + ".tscn")
			and visual.scene_file_path.ends_with("/" + key + ".glb"), "independent prefab and GLB " + key)
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			for surface in node.mesh.get_surface_count():
				var material := node.get_active_material(surface) as StandardMaterial3D
				_check(material != null and material.albedo_texture != null
					and material.albedo_texture.resource_path == PALETTE
					and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "common palette " + key)
				if material != null:
					colors[material.resource_path] = true
	_check(catalog.size() == 50 and colors.size() == 4, "50 models use four shared material roles")

func _verify_submerged_levels() -> void:
	var extension := ranch.get_node("SubmergedLevels") as Node3D
	_check(extension.get_child_count() == 7 and extension.get_meta("visual_only"), "seven visual-only storeys")
	_check(extension.find_children("*", "CollisionObject3D", true, false).is_empty(), "lower storeys have no physics bodies or triggers")
	var types := {}
	var count := 0
	var highest := -INF
	for floor_node: Node3D in extension.get_children():
		var damage := 0
		for piece: Node3D in floor_node.get_children():
			count += 1
			var key: String = piece.get_meta("component_key")
			types[key] = true
			if key.ends_with("_broken") or key.ends_with("_open") or key.ends_with("_spalled"):
				damage += 1
			_check(piece.get_meta("visual_only") and piece.get_meta("building_class") == "underwater",
				"submerged module remains a separate visual resource")
			for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
				var bounds: AABB = mesh.global_transform * mesh.get_aabb()
				highest = maxf(highest, bounds.end.y)
		_check(damage >= 7, str(floor_node.name) + " has genuine missing and fractured components")
	_check(types.size() == 9 and count == 674 and highest < 1.12, "all lower-storey geometry stays submerged")

func _place_actor(point: Vector3) -> void:
	main.actor_controller.restore_pose({"mode": 0, "player": [point.x, point.y, point.z]})
	actor.set_scene_ground(true)
	var state := root.get_node("GameState")
	state.landing_id = "main"
	state.enter_zone("rooftop_ranch")

func _walk_to(local_goal: Vector3) -> bool:
	var goal := ranch.to_global(local_goal - Vector3.UP * drop)
	var phys_delta := 1.0 / float(Engine.physics_ticks_per_second)
	for frame in 960:
		var offset := goal - actor.global_position
		var horizontal := Vector3(offset.x, 0, offset.z)
		if horizontal.length() < 0.065 and absf(offset.y) < 0.16:
			_check(true, "real capsule reaches " + str(local_goal))
			return true
		actor.move_on_scene(horizontal.limit_length(2.8 * phys_delta) / phys_delta, phys_delta)
		if frame % 12 == 0:
			await physics_frame
	_check(false, "capsule goal %s stopped at %s" % [str(local_goal), str(ranch.to_local(actor.global_position))])
	return false

func _start_prompt(key: StringName) -> void:
	var prompt := ranch.get_node("RepairPrompts/" + key)
	_check(Transfer.new().safe_feet(actor, prompt.global_position, 0.20, 0.15).is_finite(), str(key) + " prompt has capsule clearance")
	_place_actor(prompt.global_position + Vector3.UP * 0.01)
	main.interactor.active = true
	main.interactor.set_interaction_context("shore")
	await physics_frame
	await physics_frame
	_check(main.interactor.candidates().has(prompt) and prompt.can_interact(), str(key) + " shore trigger")
	_check(main.actor_controller.interact_here(prompt), str(key) + " player repair command")
	for i in 6:
		if ranch.repair_progress(key) == &"playing":
			break
		main.interactor.update(1.0 / 60.0, main.interactor.auto_hold)
	_check(ranch.repair_progress(key) == &"playing" and not ranch.play_repair(key), str(key) + " starts just once")

func _verify_repair(key: StringName, animation: AnimationPlayer) -> void:
	await _start_prompt(key)
	_complete_clip(animation, key)
	await physics_frame
	_check(ranch.repair_progress(key) == &"complete" and not ranch.can_repair(key), str(key) + " independent clip completes")

func _complete_clip(animation: AnimationPlayer, key: StringName) -> void:
	if animation.current_animation != key:
		animation.play(key)
	animation.advance(animation.get_animation(key).length + 0.04)

func _shot(name: String, target: Vector3, offset: Vector3, size: float) -> void:
	var camera := root.get_node_or_null("RanchReviewCamera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "RanchReviewCamera"
		root.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.make_current()
	camera.size = size
	var framed := target - Vector3.UP * drop
	camera.position = ranch.to_global(framed + offset)
	camera.look_at(ranch.to_global(framed))
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://outputs/rooftop_ranch_v014")
	DirAccess.make_dir_recursive_absolute(output)
	_check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "render " + name)

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)
