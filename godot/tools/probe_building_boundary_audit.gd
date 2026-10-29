extends SceneTree
## Characterizes the current limits and reproduces gaps. A successful probe is
## evidence of those gaps, NOT acceptance that SEA-BUILDING-R04/R06 are satisfied.
const Catalog = preload("res://src/building/building_catalog.gd")
const Service = preload("res://src/building/building_service.gd")
var checks := 0
var failures := 0
var findings := {}
var main: Node

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func deck(x: int, z: int) -> Dictionary:
	return {"kind":"deck", "x":x, "z":z}

func support_at(service: RefCounted, x: int, z: int) -> String:
	for row in service.query():
		if row.kind == "deck" and row.x == x and row.z == z: return row.id
	return ""

func planter(support: String, px: float, pz: float) -> Dictionary:
	return {"kind":"planter", "support":support, "px":px, "pz":pz, "turn":0}

func fill_decks(service: RefCounted) -> void:
	while not service.candidates().is_empty():
		var result: Dictionary = service.begin(service.candidates()[0])
		if not result.ok:
			check(false, "fill deck: " + str(result))
			return
		service.tick(3.0)

func audit_capacity() -> void:
	var service := Service.new()
	service.configure({"eligibility":func(): return "", "space_reason":func(_r): return "", "pay":func(_c): return true})
	fill_decks(service)
	check(service.query().size() == 24, "two-ring envelope allows exactly 24 added decks")
	check(service.candidates().is_empty(), "full envelope has no further ghosts")
	check(Service.validate_snapshot(service.to_dict()) == "", "24 decks restore")
	# 15 planters in each 10.75 x 5.15 m strip, plus 6 in the east strip.
	# All use the public placement command; no private rows or malformed records.
	var accepted := 0
	var first_invalid_count := 0
	for band in 3:
		for x in (2 if band == 2 else 5):
			for z in 3:
				var px: float = snappedf((4.2 if band == 2 else -2.2) + x * 1.9,0.1)
				var pz: float = snappedf((-1.5 if band == 2 else (-6.7 if band == 0 else 3.6)) + z * 1.6,0.1)
				var support := ""
				for row in service.query():
					if row.kind == "deck" and Catalog.tile_rect(row.x, row.z).has_point(Vector2(px, pz)):
						support = row.id
				var result: Dictionary = service.begin(planter(support, px, pz))
				if not result.ok:
					check(false, "dense layout accepted: " + str(result))
					continue
				accepted += 1
				service.tick(4.0)
				if first_invalid_count == 0 and Service.validate_snapshot(service.to_dict()) != "":
					first_invalid_count = service.query().size()
	findings.capacity = {"decks":24, "accepted_planters":accepted, "total_instances":service.query().size(),
		"first_invalid_count":first_invalid_count, "snapshot_rejection":Service.validate_snapshot(service.to_dict())}
	check(accepted == 36, "public service accepts 36 nonoverlapping planters")
	check(first_invalid_count == 55, "GAP: accepted layout first becomes unrestorable at instance 55")

func audit_access() -> void:
	main.building.from_dict(Service.empty_snapshot())
	main.actor_controller.restore_pose({"mode":0, "player":[21.0,1.48,16.0]})
	root.get_node("GameState").enter_zone("zone5")
	for z in 4:
		check(main.building.begin(deck(3,z)).ok, "branch deck accepted")
		main.building.tick(3.0)
	var ground: Node = main._zone_nodes.zone5.walk_areas[0]
	var goal := Catalog.ORIGIN + Vector3(4.3,0.0,7.3)
	check(not ground.path_between(main.player.global_position,goal).is_empty(), "branch tip reachable before planting")
	var branch: Dictionary = main.building.to_dict()
	# First use positions that the actual 0.1 m UI grid can produce. The point
	# path survives, but the player is sent through a 2.8 cm wide walking strip.
	var grid_a: Dictionary = planter(support_at(main.building,3,2),4.2,3.9)
	var grid_b: Dictionary = planter(support_at(main.building,3,3),4.4,5.5)
	check(main.building.begin(grid_a).ok,"UI-grid first planter accepted")
	main.building.tick(4.0)
	check(main.building.begin(grid_b).ok,"UI-grid second planter accepted")
	main.building.tick(4.0)
	var started: bool = main.actor_controller.start_walk(ground,goal)
	var closest := INF
	for i in 900:
		main.actor_controller.tick(1.0/60.0)
		var at := Vector2(main.player.global_position.x-Catalog.ORIGIN.x,main.player.global_position.z-Catalog.ORIGIN.z)
		for row in [grid_a,grid_b]:
			var rect: Rect2 = Catalog.plot_rect(row)
			var q := Vector2(clampf(at.x,rect.position.x,rect.end.x),clampf(at.y,rect.position.y,rect.end.y))
			closest = minf(closest,at.distance_to(q))
		if not main.actor_controller.walking(): break
	var arrived: bool = main.player.global_position.distance_to(goal)<0.1
	findings.ui_grid_access = {"positions":[[4.2,3.9],[4.4,5.5]],"walk_started":started,"arrived":arrived,
		"minimum_actor_center_distance_to_box":closest,"walking_strip_width":0.028,
		"qualification":"Point route stays connected; no character-width check."}
	check(started and arrived,"GAP: runtime lets actor walk through the narrow UI-grid layout")
	check(closest<0.08,"GAP: actor center comes within 8 cm of a planter footprint")
	main.actor_controller.cancel()
	main.building.from_dict(branch)
	main.actor_controller.restore_pose({"mode":0,"player":[21.0,1.48,16.0]})
	# Leave 4 cm at the outline and 2.5 cm between boxes. Geometry permits this;
	# the walking projection expands each obstacle 5 cm, sealing the branch.
	# These exact coordinates are accepted by the public service/snapshot, but
	# are NOT on the current UI snap grid. Keep this port-level case distinct.
	var a: Dictionary = planter(support_at(main.building,3,2),4.162,3.8625)
	var b: Dictionary = planter(support_at(main.building,3,3),4.438,5.4625)
	var reason_a: String = main.building.can_place(a)
	var made_a: Dictionary = main.building.begin(a)
	main.building.tick(4.0)
	var reason_b: String = main.building.can_place(b)
	var made_b: Dictionary = main.building.begin(b)
	main.building.tick(4.0)
	var reachable: bool = not ground.path_between(main.player.global_position,goal).is_empty()
	findings.access = {"scope":"Public service/snapshot accepts off-grid positions; not a current UI click reproduction.",
		"first_reason":reason_a, "second_reason":reason_b, "both_paid_commands_accepted":made_a.ok and made_b.ok,
		"branch_tip_reachable_after":reachable, "new_request_near_disconnected_tip_reason":main.building.can_place(deck(4,3))}
	check(made_a.ok and made_b.ok, "GAP: runtime accepts planters that seal an existing route")
	check(not reachable, "GAP: previously reachable branch tip becomes disconnected")
	var next: Dictionary = deck(4,3)
	findings.access.construction_stand = str(main._construction_stand_point(main.building_world.position_for(next)))
	main.building_controller.open()
	main.building_controller.select_recipe("deck")
	main.building_controller.update_preview(main.cam.unproject_position(main.building_world.position_for(next)))
	findings.access.unreachable_preview_hint = main.building_controller.hint.text
	main.building_controller.close()

func screenshot_fixture() -> void:
	main.building.from_dict(Service.empty_snapshot())
	# Reconstruct the twelve-instance stage visible in the supplied screenshot.
	for cell in [Vector2i(0,2),Vector2i(1,2),Vector2i(2,2),Vector2i(3,2),Vector2i(4,2),Vector2i(3,3),Vector2i(3,1),Vector2i(2,-1)]:
		check(main.building.begin(deck(cell.x,cell.y)).ok, "screenshot stage deck")
		main.building.tick(3.0)
	for p in [Vector3(-2.1,4.0,0),Vector3(1.5,4.0,2),Vector3(4.2,6.2,3),Vector3(6.2,3.8,4)]:
		var row: Dictionary = planter(support_at(main.building,int(p.z),3 if int(p.z)==3 else 2),p.x,p.y)
		check(main.building.begin(row).ok, "screenshot stage planter")
		main.building.tick(4.0)
	main.actor_controller.restore_pose({"mode":0, "player":[26.3,1.48,17.2875]})
	root.get_node("GameState").enter_zone("zone5")
	var controller: Node = main.building_controller
	controller.open()
	controller.select_recipe("deck")
	var outside := deck(3,4)
	var outside_center: Vector3 = main.building_world.position_for(outside)
	controller.update_preview(main.cam.unproject_position(outside_center))
	findings.boundary = {"allowed_x":[0,4], "allowed_z":[-2,3], "base_size":[3,2], "max_added_decks":24,
		"beyond_south_limit_reason":main.building.can_place(outside), "outside_preview_empty":controller.preview.is_empty(),
		"outside_hint":controller.hint.text, "candidate_count":main.building.candidates().size()}
	check(not Catalog.allowed_cell(3,4) and Catalog.allowed_cell(3,3), "z=3 is last row; z=4 forbidden")
	check(controller.preview.is_empty(), "outside envelope gives no selectable ghost")
	check(controller.hint.text.begins_with("选择绿色虚影"), "GAP: outside hover gives generic hint, not range reason")
	if DisplayServer.get_name() != "headless":
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/building-boundary-audit.png")
	controller.close()

func run() -> void:
	audit_capacity()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.interactor.set_process(false)
	main.boat.set_process(false)
	root.get_node("Economy").set_process(false)
	await process_frame
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0, "player":[21.0,1.48,16.0]})
	root.get_node("GameState").enter_zone("zone5")
	root.get_node("Economy").inventory.set_count("wood",300)
	root.get_node("Economy").inventory.set_count("soil",100)
	main.cam.global_position = Vector3(18,24,38)
	main.cam.look_at(Vector3(20,1.4,16))
	main.cam.fov = 40
	audit_access()
	await screenshot_fixture()
	var output := FileAccess.open("res://outputs/building-boundary-audit.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(findings,"  "))
	output.close()
	print("[audit-findings] ",JSON.stringify(findings))
	main.queue_free()
	await process_frame
	print("[building-boundary-audit] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
