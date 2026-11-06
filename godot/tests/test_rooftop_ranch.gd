extends SceneTree
## v006: original stairs stay in place; the whole building sinks, and boarding reaches the roof.
const WATER_Y := 1.12
const BOARD_Y := 1.38
const ROOF_Y := 4.13
var checks := 0
var failures := 0
var main: Node
var ranch: Node3D
var area: Node3D
var support := PackedVector3Array()

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	var authored: Transform3D = main.get_node("World/SeaStructures/rooftop_ranch").transform
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 12: await process_frame
	ranch = main._zone_nodes.get("rooftop_ranch", null)
	check(ranch != null, "ranch registered")
	if ranch == null:
		_finish(); return
	area = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	check(ranch.transform.is_equal_approx(authored), "facility retains the placement authored in main.tscn")
	check(absf(main.water_node.global_position.y - WATER_Y) < 0.01, "global sea has not moved")
	_check_original_stairs()
	_check_surfaces()
	_check_upgrades()
	_check_decoration_attachments()
	_check_roof_rail_attachments()
	await _check_formal_route()
	_finish()

func _check_original_stairs() -> void:
	var models: Node = ranch.get_node("Models")
	var flights := 0
	for child in models.get_children():
		var key := String(child.name)
		if key.begins_with("ORF3_实例_stair_flight."):
			check(child.visible, "original stair preserved " + key)
			flights += 1
	check(flights == 6, "all six original flights retained, not deleted")
	var last: Node3D = models.get_node("ORF3_实例_stair_flight.023")
	check(last.position.distance_to(Vector3(27, 57.471405, 0.9)) < 0.001, "top flight original local transform")
	var lower: Node3D = models.get_node("ORF3_实例_stair_landing.022")
	check(lower.position.distance_to(Vector3(26, 57.3, -2.1)) < 0.001, "original top boarding platform position")
	check(models.get_node("ORF3_实例_roof_entry").visible, "original roof entrance restored")
	# The previous return flight's tread end is below the waterline (rails may remain underwater silhouettes).
	check(ranch.global_position.y + 57.0 < WATER_Y, "previous flight tread is submerged")
	check(absf(ranch.global_position.y + 60.05 - WATER_Y - 3.01) < 0.01, "only 3.01m of facade below lawn is exposed")
	for key in ["ORF3_实例_stair_flight.023", "ORF3_实例_stair_landing.022", "ORF3_实例_stair_landing.024", "ORF3_实例_roof_entry", "ORF3_中央草皮基底", "ORF2_实例_roof"]:
		_collect_support(models.get_node(key))

func _collect_support(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			var data: Array = mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = data[Mesh.ARRAY_INDEX]
			var count := ix.size() if not ix.is_empty() else vs.size()
			for j in range(0, count - 2, 3):
				for k in 3:
					support.append(mi.global_transform * vs[ix[j+k] if not ix.is_empty() else j+k])

func _supported(point: Vector3, tolerance := 0.30) -> bool:
	for i in range(0, support.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(point + Vector3.UP * tolerance, Vector3.DOWN, support[i], support[i+1], support[i+2])
		if hit != null and absf(hit.y - point.y) < tolerance:
			return true
	return false

func _check_surfaces() -> void:
	var landing: Node3D = area.get_node("Landing_main")
	var stand: Vector3 = landing.stand_position()
	var park: Vector3 = landing.get_node("BoatPark").global_position
	check(absf(stand.y - BOARD_Y) < 0.02, "boarding point on actual 57.30 deck")
	check(absf(park.y - WATER_Y) < 0.02, "boat on water")
	check(absf(stand.y - park.y - 0.26) < 0.02, "boarding deck 0.26m above sea")
	check(_supported(stand, 0.06), "boarding point supported by real model, not fake elevated plane")
	check(main._is_open_water(park.x, park.z), "boat park outside geometry blockers")
	check(absf(area.surface_y - ROOF_Y) < 0.01, "roof ground aligns with grass thickness")
	var destination := ranch.to_global(Vector3(0, 60.05, 6))
	var path: Array[Vector3] = area.path_between(stand, destination)
	check(path.size() >= 4, "boarding via final flight reaches roof")
	# Check actual visual support, not just path existence. Sample each part of the last flight.
	for i in 9:
		var t := float(i) / 8.0
		var p := ranch.to_global(Vector3(27, lerpf(57.3,59.8,t),lerpf(-1.2,3,t)))
		check(_supported(p), "actual stair tread support sample %d" % i)
	for local in [Vector3(26.8,57.3,-2.1),Vector3(26.8,59.8,3.9),Vector3(23.8,60.05,3.9),Vector3(0,60.05,6),Vector3(-5,60.05,6)]:
		var p: Vector3 = ranch.to_global(local)
		check(_supported(p), "model deck support " + str(local))
		check(area.contains_world(p.x,p.z), "walk surface covers actual model " + str(local))
	for local in [Vector3(-16,60.05,-8),Vector3(-7,60.05,-9),Vector3(-17,60.05,-1),Vector3(7,60.05,-7.5),Vector3(18,60.05,-10)]:
		var p: Vector3 = ranch.to_global(local)
		check(not area.contains_world(p.x,p.z), "actual occupied footprint excluded " + str(local))
	var terrace := ranch.to_global(Vector3(-16, 60.05, 8))
	var outside := ranch.to_global(Vector3(27, 60.05, -8))
	check(area.contains_world(terrace.x, terrace.z), "old mirrored terrace footprint is walkable")
	check(not area.contains_world(outside.x, outside.z), "no ghost route outside original staircase")

func _check_upgrades() -> void:
	var m: Node = ranch.get_node("Models")
	var gu: Node3D = m.get_node("ORF4_温室_升级前_待建木料堆")
	var gc: Node3D = m.get_node("ORF4_温室_升级后_完整设施")
	var tu: Node3D = m.get_node("ORF4_水塔_升级前_卧放罐体与木支架材料")
	var tc: Node3D = m.get_node("ORF4_水塔_升级后_已搭建")
	check(gu.visible and tu.visible and not gc.visible and not tc.visible, "original default upgrade visuals retained")
	ranch.set_greenhouse_upgrade_state("complete")
	check(gc.visible and not gu.visible and tu.visible, "greenhouse switch independent")
	ranch.set_water_tower_upgrade_state("complete")
	check(tc.visible and not tu.visible, "tower switch independent")
	ranch.set_upgrade_state("unbuilt")

## Real mesh envelopes catch the scale-times-origin bug that path tests cannot see.
func _check_decoration_attachments() -> void:
	var counts := {"vine":0,"moss_cluster":0,"grass":0,"weather":0}
	var inv := ranch.global_transform.affine_inverse()
	for node in ranch.get_node("Models").get_children():
		var key := str(node.get_meta("source_instance", ""))
		var family := ""
		for candidate in counts:
			var prefix := "ORF3_实例_" + str(candidate) if candidate in ["vine","moss_cluster"] else "ORF2_实例_" + str(candidate)
			if key == prefix or key.begins_with(prefix + "."):
				family = candidate
		if family.is_empty(): continue
		counts[family] += 1
		var box := AABB()
		var first := true
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child
			if mi.mesh == null: continue
			var part: AABB = inv * mi.global_transform * mi.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
		check(not first, "decoration has real geometry " + key)
		check(box.position.x >= -25.1 and box.end.x <= 25.1 and box.position.z >= -17.2 and box.end.z <= 17.2,
			"decoration stays on building footprint " + key)
		if family == "grass":
			check(absf(box.position.y - 60.0) < 0.01 and box.end.y < 60.4, "grass rooted on roof, not scaled position " + key)
		elif family == "moss_cluster":
			check(absf(box.position.y - 60.05) < 0.01 and box.end.y < 61.2, "moss rooted on parapet " + key)
			var p: Vector3 = node.position
			var edge_gap := minf(absf(absf(p.x)-24.853),absf(absf(p.z)-16.853))
			check(edge_gap < 0.02, "moss anchor attached to actual parapet envelope " + key)
		elif family == "vine":
			check(box.end.y < 59.5 and box.position.y >= 0.0, "wall vine below roof, never floating in sky " + key)
			check(absf(node.position.z - 16.4) < 0.01, "vine follows original facade band " + key)
	for family in counts:
		var expected := {"vine":24,"moss_cluster":11,"grass":90,"weather":25}
		check(counts[family] == expected[family], "all decoration instances checked " + str(family) + "=" + str(counts[family]))

## Every roof rail must overlap a parapet segment and stay inside its end span.
func _check_roof_rail_attachments() -> void:
	var models: Node = ranch.get_node("Models")
	var rail_count := 0
	for child in models.get_children():
		var source := str(child.get_meta("source_instance", ""))
		if not source.begins_with("ORF2_实例_rail"):
			continue
		rail_count += 1
		var box := _node_local_box(child)
		var is_upper_terrace := box.position.y > 64.0
		if is_upper_terrace:
			# rail.038-.043 belong to the raised platform, not the main roof parapet.
			check(box.position.y >= 65.58 and box.position.y <= 65.62, "upper-platform rail sits on platform " + source)
			# 栏杆中心线落在平台外沿，护栏允许向外伸出；只要求与平台实体有正面积重叠。
			var overlap_x := minf(box.end.x, -10.80) - maxf(box.position.x, -21.20)
			var overlap_z := minf(box.end.z, -3.30) - maxf(box.position.z, -12.70)
			check(overlap_x > 0.0 and overlap_z > 0.0,
				"upper-platform rail base overlaps platform edge " + source)
			check(box.end.y <= 66.75, "upper-platform rail height is bounded " + source)
		else:
			check(box.position.y >= 61.09 and box.position.y <= 61.13, "roof rail sits on parapet top " + source)
			check(box.end.y <= 62.25, "roof rail height is bounded " + source)
			var near_front := absf(box.position.z - 16.25) < 0.20 or absf(box.end.z + 16.25) < 0.20
			var near_side := absf(box.position.x - 24.25) < 0.20 or absf(box.end.x + 24.25) < 0.20
			check(near_front or near_side, "roof rail touches a real roof edge " + source)
	check(rail_count == 43, "all 43 serialized rail segments audited")

func _node_local_box(node: Node) -> AABB:
	var inv := ranch.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child
		if mi.mesh == null: continue
		var part: AABB = inv * mi.global_transform * mi.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

func _check_formal_route() -> void:
	var state: Node = root.get_node("GameState")
	var landing: Node3D = area.get_node("Landing_main")
	var park: Marker3D = landing.get_node("BoatPark")
	var stand: Vector3 = landing.stand_position()
	state.enter_zone("rooftop_ranch")
	state.landing_id = "main"
	state.set_mode(state.Mode.ON_BOAT)
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	check(main._step_ashore(), "formal boarding succeeds")
	for i in 600:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking(): break
	check(main.player.global_position.distance_to(stand) < 0.6, "actual character landed on original top platform")
	for local in [Vector3(27,59.8,3.9),Vector3(0,60.05,6),Vector3(-16,60.05,8)]:
		var target: Vector3 = ranch.to_global(local)
		check(main.actor_controller.start_walk(area,target), "formal walk can start " + str(local))
		for i in 6000:
			main.actor_controller.tick(1.0/60.0)
			if not main.actor_controller.walking(): break
		check(main.player.global_position.distance_to(target) < 0.6, "actual capsule reaches model surface " + str(local) + " actual=" + str(main.player.global_position))
	# Return to the same boarding point, then board the ship through the normal interface.
	check(main.actor_controller.start_walk(area,stand), "return route exists")
	for i in 6000:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking(): break
	check(main.player.global_position.distance_to(stand) < 0.6, "actual capsule returns to boarding deck")

func _finish() -> void:
	if is_instance_valid(main): main.queue_free()
	await process_frame
	print("[rooftop-ranch] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
