extends SceneTree

const Catalog = preload("res://src/building/building_catalog.gd")
const Save = preload("res://src/save/save_game.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func place_actor(main: Node, point: Vector3) -> void:
	main.actor_controller.restore_pose({"mode":0, "player":[point.x, point.y, point.z]})

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main._autosave_on = false
	main._title_active = false
	main.set_process(false)
	main.set_physics_process(false)
	var state := root.get_node("GameState")
	var economy := root.get_node("Economy")
	var service = main.building
	var world = main.building_world
	var zone: Node3D = main._zone_nodes.zone5
	state.enter_zone("zone5")
	state.landing_id = "main"
	economy.inventory.set_count("wood", 100)
	economy.inventory.set_count("soil", 10)
	var dock: Node3D = zone.landing_point("main")
	var park: Marker3D = dock.get_node("BoatPark")
	main.boat.place_at(park.global_position, park.global_rotation.y)
	place_actor(main, Catalog.ORIGIN + Vector3(5.725, .01, 10.925))
	await physics_frame
	await physics_frame
	check(service.query().size() == 6 and service.layout().size() == 11, "five fixed starter pieces and six saved planters")
	check_packed_beds(service.query())
	for item: Dictionary in Catalog.starter_rows():
		var component: Node3D = world.node_for(item.id)
		var shape: CollisionShape3D = component.get_node("SurfaceCollision/Deck")
		check(shape.shape.size == (Vector3(5,.5,2.5) if item.kind == "workshop_dock" else Vector3(5,.5,5)), "authored dimensions " + item.id)
		check(not service.remove(item.id).ok and not service.move(item.id, {}).ok, "starter cannot be removed or moved " + item.id)
	check(zone.landing_points().size() == 1 and main.building_access.berth_ids().is_empty(), "only initial berth exists")
	check(zone.get_node_or_null("Models") == null and main.farm_field.find("platform_plot") == null, "retired platform and fixed beds are gone")
	var model := dock.get_parent().get_parent().get_node("Model")
	var planks := model.find_children("Plank*", "MeshInstance3D", true, false)
	check(planks.size() == 3, "three independent dock planks")
	var platform: Node3D = world.node_for("@starter/DeckSW").get_node("Model")
	var platform_widths: Array[float] = []
	for mesh: MeshInstance3D in platform.find_children("*", "MeshInstance3D", true, false):
		var size: Vector3 = (mesh.global_transform * mesh.get_aabb()).size
		if size.z > 4.99: platform_widths.append(size.x)
	for plank: MeshInstance3D in planks:
		var size: Vector3 = (plank.global_transform * plank.get_aabb()).size
		check(size.x > 4.99 and platform_widths.any(func(width): return absf(size.z - width) < .001),
			"plank runs along the five-metre edge and matches the adjacent platform width")
	var tires := model.find_children("Fender*_Tire", "MeshInstance3D", true, false)
	var posts := model.find_children("Bollard*", "MeshInstance3D", true, false)
	check(tires.size() == 4 and posts.size() == 2, "four fenders and two bollards")
	var tire_positions: Array[float] = []
	for tire: MeshInstance3D in tires:
		var bounds := tire.global_transform * tire.get_aabb()
		tire_positions.append(bounds.get_center().x)
		check(is_equal_approx(bounds.size.x, 1.09 * 1.15) and is_equal_approx(bounds.size.y, 1.09 * 1.15), "solar cabin tire diameter")
		check(tire.get_active_material(0) == preload("res://assets/materials/solar_cabin/sunny_matte.tres"), "solar cabin fender finish")
	tire_positions.sort()
	for i in range(1, tire_positions.size()):
		check(is_equal_approx(tire_positions[i] - tire_positions[i - 1], 1.28), "even fender spacing")
	for post: MeshInstance3D in posts:
		var size := (post.global_transform * post.get_aabb()).size
		check(size.is_equal_approx(Vector3(.53, .82, .53) * 1.725), "solar cabin bollard dimensions")
	check(main.boat.hull_clear(), "initial vessel clears the four fenders")
	check(not main._formal_berth_result(false).has("point"), "ordinary deck cannot board parked vessel")
	place_actor(main, dock.stand_position() + Vector3.UP * .01)
	await physics_frame
	main._surface_has_focus = true
	main._boat_wait_for_neutral = false
	check(main._formal_berth_result(false).has("point"), "starter dock boards " + str(main._formal_berth_result(false)))
	check(main.actor_controller.transfer_berth(false), "initial boarding command succeeds")
	main._boat_key_left = 0.0
	check(main.actor_controller.transfer_berth(true), "initial disembarking command succeeds")

	var loose := {"kind":"workshop_dock", "px":60.0, "pz":60.0, "py":0.0, "turn":0, "origin":"boat"}
	check(not service.begin(loose).ok, "dock needs a finished platform")
	var planter := {"kind":"planter_small", "px":.725, "pz":13.675, "py":0.0, "turn":0, "support":"@starter/Dock"}
	check(service.can_place(planter).contains("码头"), "protected starter deck rejects a planter")
	var adjacent := {"kind":"workshop_dock", "px":5.725, "pz":13.675, "py":0.0, "turn":0}
	check(service.can_place(adjacent).contains("停船水面"), "neighboring berths need independent water")

	var target := Vector2(9.475, 9.925)
	var request := Catalog.snap_foundation("workshop_dock", target, 1, service.layout())
	check(Catalog.footprint_rect(request).get_center().is_equal_approx(target), "dock snaps with water side facing out")
	place_actor(main, Catalog.ORIGIN + Vector3(7.425, .01, 9.925))
	check(main._construction_in_reach(request), "dock is reachable through the existing editor")
	check(main.building_controller.book.recipe_buttons.has("workshop_dock"), "dock has a build card")
	var built: Dictionary = service.begin(request)
	check(built.ok, "paid dock construction accepted " + str(built))
	if not built.ok:
		finish(main)
		return
	var id: String = built.id
	var berth_id := "built:" + id + ":dock"
	check(economy.inventory.count("wood") == 90, "dock costs 10 wood once")
	check(main.building_access.landing_node(berth_id) == null and main.building_access.berth_ids().is_empty(), "unfinished dock cannot board")
	check(not world.node_for(id).get_node("DockWalk/Berth/DockEdge/DockingArea").monitoring, "unfinished dock trigger is off")
	planter.px = request.px
	planter.pz = request.pz
	planter.support = id
	check(service.can_place(planter).contains("码头"), "unfinished dock already reserves the deck")
	service.tick(4.0)
	check(world.node_for(id).has_node("Construction"), "new dock assembles on completion")
	check(main.building_access.berth_ids() == [berth_id], "finished dock registers one berth")
	var berth: Node3D = main.building_access.landing_node(berth_id)
	var new_park: Marker3D = berth.get_node("BoatPark")
	var shore: Vector3 = berth.stand_position()
	main.boat.place_at(new_park.global_position, new_park.global_rotation.y)
	var basin := Catalog.dock_water(service.row(id))
	var extension := {"kind":"platform_5x5", "px":basin.position.x + 2.75, "pz":basin.get_center().y, "py":0.0, "turn":0, "origin":"boat"}
	check(service.can_place(extension).contains("停船水面"), "ordinary expansion cannot block a basin " + service.can_place(extension))
	check(service.can_remove(id).contains("船"), "occupied dock cannot be demolished")
	place_actor(main, Catalog.ORIGIN + Vector3(8.22, .01, 9.925))
	await physics_frame
	await physics_frame
	main._boat_wait_for_neutral = false
	main._boat_key_left = 0.0
	main._surface_has_focus = true
	check(not main._formal_berth_result(false).has("point"), "nearby body on the adjoining deck still cannot board")
	place_actor(main, shore + Vector3.UP * .01)
	await physics_frame
	check(main._formal_berth_result(false).get("landing") == berth_id, "new berth uses its own component")
	check(main.actor_controller.transfer_berth(false), "new berth boards")
	main._boat_key_left = 0.0
	check(main.actor_controller.transfer_berth(true), "new berth disembarks")
	var snapshot := Save.encode(main)
	var restored := Save.restore(main, snapshot)
	check(restored.ok, "built dock persists " + str(restored))
	check(main.building_access.berth_ids() == [berth_id] and not world.node_for(id).has_node("Construction"), "restore brings back the berth in finished pose")
	var old_main := snapshot.duplicate(true)
	var starter_feet := Catalog.ORIGIN + Vector3(.725, .01, 4.925)
	old_main.game.merge({"landing":"main", "boat":[16.42, 1.12, 15.91, 0.0],
		"player":[starter_feet.x, starter_feet.y, starter_feet.z]}, true)
	var legacy_restore := Save.restore(main, old_main)
	check(legacy_restore.ok and main.boat.global_position.is_equal_approx(park.global_position), "old fixed berth restores boat to starter dock " + str(legacy_restore))
	check(main.actor_controller.mode() == 0 and main.player.global_position.distance_to(starter_feet) < .05, "connected old shore retains player position")
	var before_move := old_main.duplicate(true)
	var prior_feet := Catalog.ORIGIN + Vector3(-4.275, .01, -.075)
	before_move.game.merge({"boat":[17.725, 1.12, 27.725, PI/2],
		"player":[prior_feet.x, prior_feet.y, prior_feet.z]}, true)
	var migrated := Save.restore(main, before_move)
	check(migrated.ok and main.player.global_position.distance_to(prior_feet + Catalog.STARTER_MOVE) < .05
		and main.boat.global_position.is_equal_approx(park.global_position), "relocated deck and berth restore legacy player and boat " + str(migrated))
	var old_edge := old_main.duplicate(true)
	old_edge.building = {"version":1, "next_id":3, "instances":[
		{"id":"built_2", "kind":"platform_5x5", "x":0, "z":0, "px":58.0, "pz":58.0, "py":0.0, "turn":0, "support":"", "left":0.0}]}
	for key: String in old_edge.economy.farm.plots.keys():
		if key.begins_with("dynamic/"): old_edge.economy.farm.plots.erase(key)
	old_edge.game.merge({"landing":"built:built_2:3", "boat":[80.0,1.12,78.3,PI/2],
		"player":[80.0,1.49,74.0]}, true)
	var old_island := Save.restore(main, old_edge)
	check(old_island.ok and main.actor_controller.mode() == 1 and main.building_access.berth_ids().is_empty(),
		"old isolated platform returns the player to their boat without reopening an edge berth " + str(old_island))
	var legacy_crop := {"crop":"lettuce", "remaining":2.0, "total":3.0, "water":1.0, "harvests":0}
	var old_beds := old_main.duplicate(true)
	old_beds.building = service.empty_snapshot()
	old_beds.economy.farm.plots["platform_plot:4"] = legacy_crop
	for key: String in old_beds.economy.farm.plots.keys():
		if key.begins_with("dynamic/"): old_beds.economy.farm.plots.erase(key)
	var garden_restore := Save.restore(main, old_beds)
	check(garden_restore.ok and service.query().size() == 6, "legacy save gains six complete planters " + str(garden_restore))
	check(economy.farm.state("dynamic/built_1") == legacy_crop and economy.farm.is_empty("platform_plot:4"), "legacy crop moves into an initial bed")
	var scattered := Save.encode(main)
	scattered.building.erase("starter_planters_packed")
	var index := 0
	for z: float in [6.375, 9.575]:
		for x: float in [-.175, 3.225, 6.625]:
			var row: Dictionary = scattered.building.instances[index]
			row.px = x
			row.pz = z
			row.support = "@starter/Deck%s" % (("N" if z < 7.425 else "S") + ("W" if x <= 3.225 else "E"))
			index += 1
	check(Save.restore(main, scattered).ok, "old scattered beds migrate into the packed layout")
	check_packed_beds(service.query())
	check(economy.farm.state("dynamic/built_1") == legacy_crop, "moved starter bed keeps its crop")
	var edited := scattered.duplicate(true)
	edited.building.instances.remove_at(5)
	edited.economy.farm.plots.erase("dynamic/built_6")
	edited.building.instances[4].px = -.6
	edited.building.instances[4].pz = 11.45
	edited.building.instances[4].support = "@starter/DeckSW"
	check(Save.restore(main, edited).ok and service.row("built_6").is_empty()
		and is_equal_approx(service.row("built_5").pz, 11.45), "migration preserves removed and manually moved beds")
	check(Save.restore(main, scattered).ok, "restore all six beds before dismantling")
	var wood_before: int = economy.inventory.count("wood")
	check(service.remove("built_6").ok, "initial empty planter can be demolished")
	check(economy.inventory.count("wood") == wood_before + int(Catalog.RECIPES.planter.cost.wood), "initial planter uses normal dismantle refund")
	var garden := Save.encode(main)
	check(Save.restore(main, garden).ok and service.query().size() == 5 and service.row("built_6").is_empty(), "removed planter stays removed on restore")
	check(Save.restore(main, old_beds).ok, "capture the complete starter layout")
	if DisplayServer.get_name() != "headless":
		await capture(main, park)
	finish(main)

func check_packed_beds(rows: Array) -> void:
	if rows.size() != 6: return
	var west := Catalog.footprint_rect(rows[0])
	var east := Catalog.footprint_rect(rows[1])
	for i in rows.size():
		var rect := Catalog.footprint_rect(rows[i])
		var expected := west.position + Vector2((i % 2) * west.size.x, (i >> 1) * west.size.y)
		check(rect.position.is_equal_approx(expected) and rect.size.is_equal_approx(west.size), "six beds tile edge to edge in two columns")
	check(west.position.x > 3.225 and east.end.x < 8.225, "beds sit on the right half of the deck")

func capture(main: Node, initial_park: Marker3D) -> void:
	main.boat.place_at(initial_park.global_position, initial_park.global_rotation.y)
	main.hud.hide()
	main.cam.set_process(false)
	var camera: Camera3D = main.cam
	var target := Catalog.ORIGIN + Vector3(2.75, 0, 7.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.global_position = target + Vector3(13, 18, 18)
	camera.look_at(target)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/workshop-dock.png") == OK, "Godot rendered workshop and starter dock")
	main.boat.place_at(initial_park.global_position + Vector3(0, 0, 6), initial_park.global_rotation.y)
	var detail := Catalog.ORIGIN + Vector3(.725, 0, 13.675)
	camera.size = 7.0
	camera.global_position = detail + Vector3(3.5, 4, 8)
	camera.look_at(detail)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/workshop-dock-detail.png") == OK, "Godot rendered lengthwise deck and fender close up")

func finish(main: Node) -> void:
	current_scene = null
	root.remove_child(main)
	main.free()
	print("[workshop-dock] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
