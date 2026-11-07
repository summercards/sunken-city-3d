extends SceneTree
## Actual shop entry/exit, moving support, local footprint and material isolation.
var main: Node
var shop: Node3D
var area: Node3D
var reveal: Node3D
var checks := 0
var failures := 0
var evidence := {}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func pose(x: float, z: float, height := 0.3) -> void:
	var p: Vector3 = shop.get_node("Visual").to_global(Vector3(x, height, z))
	main.actor_controller.restore_pose({"mode":0,"player":[p.x,p.y,p.z]})
	main.actor_controller.walk_area = area

func settle(seconds: float, fps := 60) -> void:
	for i in ceili(seconds * fps):
		reveal.advance(1.0 / fps)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.boat.set_process(false)
	root.get_node("Economy").ticking = false
	for i in 8: await process_frame
	shop = main.get_node("World/SeaStructures/floating_shop")
	shop.set_physics_process(false)
	shop.set_motion_time(0)
	area = shop.walk_areas[0]
	reveal = shop.get_node("RoofReveal")
	reveal.set_process(false)
	pose(0, 7.4)
	settle(1)
	var initial: Dictionary = reveal.snapshot()
	check(initial.roof_roots == 78 and initial.bindings > 78, "roof slab and all overhead attachments are registered")
	check(initial.visible_roofs == 78 and initial.amount == 0, "outside has intact original roof")
	check(reveal._subject == main.player and reveal._ashore_query.is_valid(), "main injects actual actor and mode query")
	var original_materials := []
	for binding in reveal._bindings:
		original_materials.append(binding.mesh.get_active_material(binding.surface))
	var independent: Node = load("res://scenes/components/facilities/gift_kiosk/roof.tscn").instantiate()
	root.add_child(independent)
	var independent_mesh: MeshInstance3D = independent.find_children("*", "MeshInstance3D", true, false)[0]
	var independent_material := independent_mesh.get_active_material(0)
	var independent_override := independent_mesh.get_surface_override_material(0)
	var camera_transform: Transform3D = main.cam.transform
	var facility_transform := shop.transform
	var floor_before: float = area.surface_y
	var collider_count := shop.find_children("*", "CollisionObject3D", true, false).size()
	for fps in [30, 60, 120]:
		pose(0, 7.4)
		settle(1, fps)
		pose(0, 0)
		settle(0.5, fps)
		check(reveal.snapshot().inside and reveal.snapshot().amount > 0.50 and reveal.snapshot().amount < 0.60, "entry progresses by elapsed time at %s fps" % fps)
		settle(0.5, fps)
		check(reveal.snapshot().amount == 1 and reveal.snapshot().visible_roofs == 0, "full interior visible at %s fps" % fps)
		check(shop.get_node("Visual/Structure/deck_001").is_visible_in_tree(), "deck remains visible")
		check(shop.get_node("Visual/Furnishings/roof_pipe_003").is_visible_in_tree(), "back-wall pipe remains visible")
		var goods := 0
		for n in shop.get_node("Visual/Furnishings").get_children():
			if str(n.name).begins_with("shelf_") or str(n.name).begins_with("gift_"):
				goods += 1
				check(n.is_visible_in_tree(), "interior shelf/goods retained " + str(n.name))
		check(goods > 10, "real interior furnishings present")
		pose(0.5, 1.5)
		reveal.advance(0)
		check((reveal.snapshot().center as Vector2).distance_to(Vector2(0.5,1.5)) < 0.001, "opening follows actor in room")
		pose(0, 7.4)
		settle(0.4, fps)
		check(reveal.snapshot().amount > 0.4 and reveal.snapshot().amount < 0.5, "exit closes smoothly at %s fps" % fps)
		settle(0.4, fps)
		check(reveal.snapshot().amount == 0 and reveal.snapshot().visible_roofs == 78, "exit fully restores at %s fps" % fps)
	for i in reveal._bindings.size():
		var b: Dictionary = reveal._bindings[i]
		check(b.mesh.get_active_material(b.surface) == original_materials[i], "exact original per-instance material restored")
	check(independent_mesh.get_active_material(0) == independent_material and independent_mesh.get_surface_override_material(0) == independent_override, "shared component outside this facility remains unchanged")
	# Entry boundary: only inside opens, a small exit margin suppresses door jitter.
	pose(0, 5.2)
	reveal.advance(0.1)
	check(not reveal.snapshot().inside, "outside front threshold stays closed")
	pose(0, 5.0)
	reveal.advance(0.2)
	var half_open: float = reveal.snapshot().amount
	pose(0, 5.3)
	reveal.advance(0)
	check(reveal.snapshot().inside, "door hysteresis keeps inside state near threshold")
	pose(0, 5.5)
	reveal.advance(0.05)
	check(not reveal.snapshot().inside and reveal.snapshot().amount < half_open and reveal.snapshot().amount > 0, "leaving mid-transition reverses continuously")
	pose(0, 4.9)
	var reversal: float = reveal.snapshot().amount
	reveal.advance(0.05)
	check(reveal.snapshot().amount > reversal and reveal.snapshot().amount < 1, "re-entering reverses from current amount")
	pose(0, 7.4)
	settle(1)
	pose(5, 5)
	reveal.advance(0.1)
	check(not reveal.snapshot().inside, "rounded exterior corner is outside interior")
	pose(0, 0, 20)
	reveal.advance(0.1)
	check(not reveal.snapshot().inside, "another elevation cannot hide roof")
	pose(0, 0)
	main.actor_controller.reconcile_mode(1)
	reveal.advance(0.1)
	check(not reveal.snapshot().inside, "boat mode cannot open roof")
	pose(0, 0)
	shop.set_motion_time(2.3)
	main._update_walk(0)
	reveal.advance(1)
	check(reveal.snapshot().inside and reveal.snapshot().amount == 1, "floating actor and roof use same facility-local space")
	shop.set_motion_time(0)
	check(main.cam.transform == camera_transform and shop.transform == facility_transform, "reveal leaves camera and manual placement untouched")
	check(is_equal_approx(area.surface_y, floor_before) and collider_count == shop.find_children("*", "CollisionObject3D", true, false).size(), "reveal does not alter support height or collision membership")
	# Real capsule/path enters and leaves through the authored shop door.
	pose(0, 7.4)
	settle(1)
	var route_results := []
	for z in [0.0, 7.4]:
		var goal := shop.to_global(Vector3(0, 0.3, z))
		goal.y = area.surface_y
		check(main._start_walk(area, goal), "real walk starts across entrance")
		for i in 500:
			await physics_frame
			main._update_walk(1.0 / 60.0)
			reveal.advance(1.0 / 60.0)
			if main.actor_controller.state_id() == "ashore_idle": break
		settle(1)
		check(main.player.global_position.distance_to(goal) < 0.18, "real actor reaches entry/interior goal")
		check(reveal.snapshot().inside == (z == 0.0), "actual walking drives reveal state")
		route_results.append({"goal":str(goal),"actor":str(main.player.global_position),"roof":reveal.snapshot()})
	evidence = {"initial":initial,"routes":route_results,"final":reveal.snapshot(),"expected_faults":[],"not_run":["full unrelated feature suite"]}
	var file := FileAccess.open("res://outputs/roof-reveal-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	file.close()
	independent.queue_free()
	main.queue_free()
	await process_frame
	print("[roof-reveal] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
