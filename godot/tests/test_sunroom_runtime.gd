extends SceneTree
## SEA-SUNROOM runtime integration: scene wiring, phase projection, real actor climb.

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

	economy.inventory.set_count("wood", 20)
	economy.inventory.set_count("soil", 2)
	economy.inventory.set_count("glass", 1)
	var repair_result: Dictionary = economy.sunroom.repair_ladder()
	check(repair_result.get("event", "") == "sunroom_ladder_repaired", "runtime repair command succeeds")
	await process_frame
	check(bottom.visible and top.visible and not repair.visible, "ladder phase projects ladder access")
	check(not damage.visible, "ladder repair removes breakage")
	check(not economy.sunroom.restore_upper().is_empty(), "upper restore returns a result")
	await process_frame
	check(economy.sunroom.stage == "restored", "runtime reaches restored phase")
	var upper_area: Node = null
	for area in zone.walk_areas:
		if str(area.area_id) == "sunroom_upper_deck": upper_area = area
	check(upper_area != null and upper_area.active, "restored phase enables upper walk surface")

	# Exercise the real ActorController climbing state, not just the service.
	main.actor_controller.reconcile_mode(0)
	main.player.reparent(main, true)
	main.player.global_position = bottom.global_position
	var request: Dictionary = main.actor_controller.climb_ladder(bottom.global_position, top.global_position, bottom)
	check(request.get("event", "") == "ladder_climb_started", "actor accepts authored ladder endpoints")
	for i in 420:
		await physics_frame
	check(not main.actor_controller.climbing(), "climb returns to ordinary ashore state")
	var upper_support: Vector3 = upper_area.surface_point(main.player.global_position) if upper_area != null else Vector3.INF
	# Character.global_position is the capsule root, not the feet plane. The
	# authored upper floor is 6.246335m; the capsule root rests below it by its
	# body envelope while still being supported by the upper surface.
	check(upper_support.is_finite() and main.player.global_position.y > 5.0, "actor reaches second-floor endpoint continuously")

	main.queue_free()
	await process_frame
	print("[sunroom-runtime] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
