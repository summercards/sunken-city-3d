extends SceneTree
## SEA-SUNROOM runtime integration: scene wiring, phase projection, real actor climb.

const Motor = preload("res://src/player/character_motor.gd")

var checks := 0
var failures := 0
var main

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main._title_active = false
	for i in 40:
		await process_frame
	var economy = root.get_node("Economy")
	var zone: Node3D = main.get_node("World/Zones/Zone1HomeHarbor")
	var surface: Node3D = zone.get_node("Models/太阳能木屋/太阳能木屋-海上区域")
	check_home_deck(zone, surface)
	var repair: Node = surface.find_child("SunroomRepair", true, false)
	var upper: Node = surface.find_child("SunroomUpperRestore", true, false)
	var bottom: Node = surface.find_child("SunroomLadderBottom", true, false)
	var top: Node = surface.find_child("SunroomLadderTop", true, false)
	var damage: Node = surface.find_child("SunroomDamage", true, false)
	check(repair != null and upper != null and bottom != null and top != null and damage != null, "runtime helpers are wired")
	check(economy.sunroom.stage == "ruined", "runtime starts in ruined phase")
	check(repair.is_in_group("interactable"), "repair helper enters interaction group")
	check(not bottom.visible and not top.visible and repair.visible, "ruined phase gates ladder and exposes repair")
	check(damage.visible, "ruined phase shows breakage")
	var plant_anchors := surface.find_children("*", "Node3D", true, false).filter(
		func(node): return node.get("component_kind") == "upgrade_attachment")
	check(plant_anchors.size() == 56, "all authored plant anchors are assembled")
	main._sync_zone_levels()
	check(visible_plants(plant_anchors) == ["daisy_158"], "zone refresh preserves the initial daisy")
	var upper_floor := surface.get_node("SurfaceCollision/UpperDeck") as CollisionShape3D
	var upper_area: Node = zone.walk_areas.filter(func(area): return area.area_id == "sunroom_upper_deck")[0]
	check(not upper_floor.disabled and not upper_area.active, "finished geometry supports the deck while the broken ladder gates access")

	economy.inventory.set_count("wood", 20)
	economy.inventory.set_count("soil", 2)
	economy.inventory.set_count("glass", 1)
	var repair_result: Dictionary = economy.sunroom.repair_ladder()
	check(repair_result.get("event", "") == "sunroom_ladder_repaired", "runtime repair command succeeds")
	await process_frame
	check(bottom.visible and top.visible and not repair.visible, "ladder phase projects ladder access")
	check(not damage.visible, "ladder repair removes breakage")
	const PLANT_SAVE := "user://sunroom-plant-stage.save"
	check(main.save_game(PLANT_SAVE, true).get("ok", false), "save the ladder-repaired stage")
	main._sync_zone_levels()
	check(visible_plants(plant_anchors) == ["daisy_158", "daisy_159", "foliage_153", "sprout_150", "sprout_151"],
		"zone refresh keeps only the ladder-phase plants")
	check(not upper_floor.disabled and upper_area.active, "ladder repair opens the complete supported deck")
	var upper_target := surface.to_global(Vector3(2.0, top.position.y, 1.7))
	var upper_route: Array[Vector3] = upper_area.path_between(top.global_position, upper_target)
	check(not upper_route.is_empty(), "second-floor walk surface routes from ladder top")
	var lower_area: Node = zone.area_at(bottom.global_position, 0.5)
	var lower_route: Array[Vector3] = lower_area.path_between(Vector3(3.0, 1.38, 8.0), bottom.global_position) if lower_area != null else []
	check(lower_area != null and not lower_route.is_empty(), "under-ladder lower deck routes to ladder foot")

	# Exercise the real ActorController climbing state, not just the service.
	main.actor_controller.reconcile_mode(0)
	main.player.reparent(main, true)
	main.player.global_position = bottom.global_position
	var request: Dictionary = main.actor_controller.climb_ladder(bottom.global_position, top.global_position, bottom)
	check(request.get("event", "") == "ladder_climb_started", "actor accepts authored ladder endpoints")
	await process_frame
	check(main.player.animation_state() == "climbing", "climb switches the visual action to climbing")
	for i in 420:
		await physics_frame
	check(not main.actor_controller.climbing(), "climb returns to ordinary ashore state")
	var deck_height: float = top.global_position.y
	check(absf(main.player.global_position.y - deck_height) < 0.03 and main.player.ground_contact,
		"actor finishes the climb grounded at the second-floor endpoint")

	var before_walk: Vector3 = main.player.global_position
	await walk(Vector3.FORWARD, 22)
	check(main.player.global_position.z < before_walk.z - 0.70 and main.player.ground_contact,
		"actor walks beyond the old ladder landing before restoring the room")
	await walk(Vector3.LEFT, 65)
	check(main.player.global_position.x < before_walk.x - 2.0 and absf(main.player.global_position.y - deck_height) < 0.03,
		"actor crosses to the left terrace at floor height")
	await walk(Vector3.BACK, 55)
	check(main.player.ground_contact and absf(main.player.global_position.y - deck_height) < 0.03,
		"front railing prevents a fall from the second floor")
	check_upper_support(surface, upper_floor, deck_height)

	check(not economy.sunroom.restore_upper().is_empty(), "upper restore returns a result")
	await physics_frame
	check(economy.sunroom.stage == "restored" and not upper_floor.disabled and upper_area.active,
		"restoration keeps the upper deck supported")
	check_upper_support(surface, upper_floor, deck_height)
	main._debug_set_clock(150, 9.0 * 3600.0)
	check(visible_plants(plant_anchors).size() == 56, "restored spring shows all authored plants")
	main._debug_set_clock(280, 9.0 * 3600.0)
	main._sync_zone_levels()
	check(visible_plants(plant_anchors).size() == 53, "autumn keeps pink flowers hidden after zone refresh")
	main._debug_set_clock(5, 9.0 * 3600.0)
	main._sync_zone_levels()
	check(visible_plants(plant_anchors).size() == 42, "winter keeps pink flowers and sprouts hidden after zone refresh")

	# Downward traversal is the same authored centerline in reverse; it must not
	# leave the actor in a hidden climbing or upper-floor state.
	main.actor_controller.set_move_intent(Vector3.ZERO)
	main.player.global_position = top.global_position
	main.actor_controller.reconcile_mode(0)
	var down_request: Dictionary = main.actor_controller.climb_ladder(top.global_position, bottom.global_position, top)
	check(down_request.get("event", "") == "ladder_climb_started", "actor accepts the downward ladder endpoint")
	for i in 420:
		await physics_frame
	check(not main.actor_controller.climbing() and main.player.global_position.y < 3.0, "actor returns to the lower deck after descending")
	check(main.load_game(PLANT_SAVE).get("ok", false), "load the ladder-repaired save")
	check(visible_plants(plant_anchors) == ["daisy_158", "daisy_159", "foliage_153", "sprout_150", "sprout_151"],
		"save restore leaves the ladder-phase plant visibility in place")

	main.queue_free()
	await process_frame
	print("[sunroom-runtime] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)

func visible_plants(anchors: Array) -> Array[String]:
	var names: Array[String] = []
	for plant in anchors:
		if plant.visible:
			names.append(str(plant.name))
	names.sort()
	return names

func walk(direction: Vector3, frames: int) -> void:
	for i in frames:
		await physics_frame
		main.actor_controller.set_move_intent(direction)
		main.actor_controller.tick(1.0 / 60.0)

func check_upper_support(surface: Node3D, floor_shape: CollisionShape3D, deck_height: float) -> void:
	for point in [Vector2(0.4, 2.2), Vector2(2.3, -2.8), Vector2(4.66, 2.48),
			Vector2(6.5, 2.2), Vector2(10.6, -2.8), Vector2(10.5, 2.65)]:
		var from := surface.to_global(Vector3(point.x, floor_shape.position.y, point.y))
		from.y = deck_height + 0.10
		var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.22, Motor.SCENE_GROUND_LAYER)
		var hit := surface.get_world_3d().direct_space_state.intersect_ray(ray)
		var own_floor := false
		if hit.get("collider") == floor_shape.get_parent():
			var body := floor_shape.get_parent() as CollisionObject3D
			own_floor = body.shape_owner_get_owner(body.shape_find_owner(hit.shape)) == floor_shape
		check(own_floor and absf(hit.position.y - deck_height) < 0.015, "upper deck supports %s at plank height" % point)

func check_home_deck(zone: Node3D, surface: Node3D) -> void:
	check(main.gather.find("zone1_shell") == null and main.gather.find("zone1_wood") == null,
		"retired sunroom gather spots are absent")
	check(main.gather.find("zone1_rope") != null, "salvage platform rope remains registered")
	var plot := main.farm_field.find("home_plot") as FarmPlot
	if not is_instance_valid(plot):
		check(false, "home_plot remains registered")
		return
	var rail := surface.get_node("SurfaceCollision/LowerLeftEdgeGuard") as CollisionShape3D
	var rail_inner_x := rail.position.x + (rail.shape as BoxShape3D).size.x * 0.5
	var plot_bounds := AABB()
	for child in plot.get_children():
		if child is MeshInstance3D:
			var bounds: AABB = surface.global_transform.affine_inverse() * child.global_transform * child.get_aabb()
			plot_bounds = bounds if not plot_bounds.has_volume() else plot_bounds.merge(bounds)
	check(plot_bounds.has_volume() and plot_bounds.position.x - rail_inner_x > 0.45,
		"planter meshes clear the left rail")
	check(zone.area_at(plot.global_position, 0.1) != null, "home_plot still stands on the registered home deck")
	check(plot.interaction_trigger().global_position.is_equal_approx(plot.focus_position()),
		"home_plot trigger follows the planter")
