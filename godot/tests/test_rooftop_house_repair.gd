extends SceneTree

const HOUSE := "World/SeaStructures/rooftop_ranch/Models/RooftopHouse"
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const Transfer := preload("res://src/navigation/berth_transfer.gd")

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)

func run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if main == null:
		check(false, "Main loads")
		finish()
		return
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	var house := main.get_node_or_null(HOUSE) as Node3D
	check(house != null, "official Main has the house")
	if house == null:
		main.queue_free()
		await process_frame
		finish()
		return
	var ranch := house.get_parent().get_parent() as Node3D
	var prompt := house.get_node("RepairPrompt") as Node3D
	var wall: Node3D
	var door: Node3D
	var bricks: Array[Node3D] = []
	var hues := {}
	var model_count := 0
	for piece in house.get_children():
		var key := str(piece.get_meta("component_key", ""))
		if key.is_empty():
			continue
		model_count += 1
		var visual := piece.get_node("Visual")
		check(visual.scene_file_path.ends_with(key + ".glb"), "object imports separately " + key)
		if key == "house_shell": wall = piece
		if key == "entry_assembly": door = piece
		if key.begins_with("wall_stone_"):
			bricks.append(piece)
			hues[key] = true
			check(not piece.has_node("Solid"), "wall finish follows wall collision")
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				check(material != null and material.albedo_texture != null
					and material.albedo_texture.resource_path == PALETTE
					and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "shared palette " + key)
	check(model_count == 41 and bricks.size() == 13 and hues.size() == 3, "41 placements, 13 independent stones and 3 colors")
	check(house.repair_state == &"damaged" and prompt.can_interact(), "damaged house offers repair")
	await physics_frame
	await physics_frame
	var actor := main.player as CharacterBody3D
	check(Transfer.new().safe_feet(actor, prompt.global_position, 0.22, 0.16).is_finite(), "real support and capsule clearance in front of house")
	var area: Node3D = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	check(area.surface_point(prompt.global_position).is_finite(), "repair prompt reachable on roof walk surface")
	var berth: Node3D = ranch.landing_point("main")
	var path: Array = ranch.ground_space.native_route(berth.stand_position(), prompt.global_position)
	check(path.size() >= 4, "current roof navigation connects the berth and repair prompt")
	var stations: Node3D = ranch.get_node("NpcStations")
	check(not stations.anchor_snapshot().is_empty(), "current rooftop NPC anchors still resolve on the roof")

	var wall_body := wall.get_node("Solid") as StaticBody3D
	var door_body := door.get_node("Solid") as StaticBody3D
	check(wall_body.get_child_count() >= 8 and wall_body.collision_layer == 8192,
		"individual wall segments provide physical blocking")
	check(door_body.collision_layer == 0, "damaged doorway has no closed door collider")
	var threshold := house.to_global(Vector3(2, 0.62, 3.23))
	var interior := house.to_global(Vector3(2, 0.62, 1.48))
	check(ray(threshold, interior).is_empty(), "open damaged doorway passes physical ray")
	var original_wall := wall_body.global_transform
	house.position.x += 0.45
	check(wall_body.global_position.distance_to(original_wall.origin) > 0.44, "moving house moves wall solids")
	house.position.x -= 0.45
	await physics_frame

	var player := house.get_node("BuildingAnimation") as AnimationPlayer
	var visual_run := DisplayServer.get_name() != "headless"
	if visual_run:
		await shot(house, "01_damaged")
	var stand := prompt.global_position
	main.actor_controller.restore_pose({"mode": 0, "player": [stand.x, stand.y, stand.z]})
	main.interactor.active = true
	main.interactor.set_interaction_context("shore")
	await physics_frame
	check(main.interactor.candidates().has(prompt), "shore interaction sensor finds repair prompt")
	check(main.actor_controller.interact_here(prompt), "normal player command accepts repair")
	for i in 5:
		main.interactor.update(1.0 / 60.0, main.interactor.auto_hold)
		if house.repair_state == &"repairing":
			break
	check(house.repair_state == &"repairing" and not house.play_repair(), "interaction starts one repair")
	player.pause()
	player.seek(0.43, true)
	check(bricks.any(func(piece: Node3D) -> bool: return piece.visible)
		and bricks.any(func(piece: Node3D) -> bool: return not piece.visible), "brick placements stagger in time")
	check(door_body.collision_layer == 0, "still no door blocker during early repair")
	if visual_run:
		await shot(house, "02_bricks_in_motion")
	player.play(&"repair")
	player.seek(player.get_animation(&"repair").length - 0.04, true)
	for i in 15:
		await process_frame
	check(house.repair_state == &"restored", "animation reaches restored state")
	check(bricks.all(func(piece: Node3D) -> bool: return piece.visible), "all masonry remains installed at final frame")
	check(not prompt.can_interact() and door_body.collision_layer == 8192, "finished door has its own collider")
	await physics_frame
	await physics_frame
	check(ray(threshold, interior).get("collider") == door_body, "physical ray hits restored door segment")
	if visual_run:
		await shot(house, "03_restored")
	main.queue_free()
	await process_frame
	finish()

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 8192)
	return root.world_3d.direct_space_state.intersect_ray(query)

func shot(house: Node3D, name: String) -> void:
	var camera := root.get_node_or_null("HouseReviewCamera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "HouseReviewCamera"
		root.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8.0
		camera.make_current()
	camera.position = house.to_global(Vector3(-11, 10, 16))
	camera.look_at(house.to_global(Vector3(0, 1.83, 0.65)))
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://outputs/rooftop_house")
	DirAccess.make_dir_recursive_absolute(output)
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "render " + name)

func finish() -> void:
	print("[rooftop-house-repair] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
