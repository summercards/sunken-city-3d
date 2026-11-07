extends SceneTree
## Reference kiosk: real scene, collision/nav, normal landing flow and support carry.
var main: Node
var shop: Node3D
var area: Node3D
var checks := 0
var failures := 0
var evidence := {}
const PREFIX := "res://scenes/components/facilities/gift_kiosk/"

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func local_point(x: float, z: float) -> Vector3:
	var point := shop.to_global(Vector3(x, 0.3, z))
	point.y = area.surface_y
	return point

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.boat.set_process(false)
	root.get_node("Economy").ticking = false
	for i in 8:
		await process_frame
	shop = main.get_node("World/SeaStructures/floating_shop")
	shop.set_physics_process(false)
	shop.set_motion_time(0)
	area = shop.walk_areas[0]
	_check_art_and_registration()
	_check_source_transforms()
	_check_walk_and_water()
	await _check_normal_landing()
	_check_idle_carry()
	_check_restore_at_another_phase()
	await _check_real_walking()
	_check_save_and_departure()
	var file := FileAccess.open("res://outputs/gift-kiosk-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "  "))
	file.close()
	print("[gift-kiosk] evidence ", JSON.stringify(evidence))
	print("[gift-kiosk] ", checks, " checks, ", failures, " failures")
	# Stable historical runner names now verify the replacement contract as well.
	print("[floating-shop] ", checks, " checks, ", failures, " failures")
	print("[sea-supply] ", checks, " checks, ", failures, " failures")
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _check_art_and_registration() -> void:
	check(shop.get_meta("asset_id", "") == "SEA-SCENE-GKS-ASSEMBLY", "new shop asset identity")
	check(shop.get_meta("deck_shape", "") == "rounded_square", "reference rounded-square footprint")
	check(not shop.get_meta("underwater_architectural_base", true), "no underwater architectural base")
	check(main._zone_nodes.get("sea_supply") == shop, "single sea_supply owner is the new shop")
	check(shop.landing_points().size() == 1 and shop.walk_areas.size() == 1, "one authored support and one landing")
	var rest: Node = main.get_node("World/SeaStructures/floating_rest_stop")
	check(not ("zone_id" in rest), "old art has no duplicate zone identity")
	check(rest.get_meta("activity_role", "") == "navigation_only", "old art explicitly uses existing non-zone marine-structure contract")
	check(rest.find_children("*", "CollisionObject3D", true, false).is_empty(), "old rest-stop visual has no actor collision")
	check(rest.get_node_or_null("Objects/SupplyCounter") == null, "old art no longer opens a second shop")
	check(rest.get_meta("asset_id", "") == "SEA-SCENE-FSH-ASSEMBLY", "old art identity retained")
	var dir := DirAccess.open(PREFIX)
	var components := 0
	var triangles := 0
	if dir != null:
		for name in dir.get_files():
			if not name.ends_with(".tscn"):
				continue
			components += 1
			var packed: PackedScene = load(PREFIX + name)
			check(packed != null, name + " independent PackedScene loads")
			if packed == null:
				continue
			var component := packed.instantiate()
			check(component is Node3D and (component as Node3D).transform.is_equal_approx(Transform3D.IDENTITY), name + " root identity")
			for mesh: MeshInstance3D in component.find_children("*", "MeshInstance3D", true, false):
				check(mesh.mesh != null, name + " mesh exists")
				if mesh.mesh == null:
					continue
				for surface in mesh.mesh.get_surface_count():
					var mat := mesh.get_active_material(surface) as StandardMaterial3D
					check(mat != null, name + " imported shared standard material")
					if mat != null:
						check(mat.albedo_texture != null and mat.albedo_texture.resource_path == "res://assets/textures/shared/sea_cozy_8x8_512.png", name + " public palette binding")
						check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, name + " nearest palette sampling")
					var arrays: Array = mesh.mesh.surface_get_arrays(surface)
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					triangles += int(indices.size() / 3)
			component.free()
	check(components == 47, "all 47 independent component scenes")
	var underwater := shop.get_node("Visual/UnderwaterVisual")
	for node in underwater.find_children("*", "Node", true, false):
		check(not node is CollisionObject3D and not node.has_method("stand_position") and not node.has_method("interact"), "underwater flotation part has no gameplay: " + str(node.name))
	evidence["art"] = {"components": components, "master_triangles": triangles, "root_transform": str(shop.transform), "old_transform": str(rest.transform)}

func _check_walk_and_water() -> void:
	for p in [Vector2(0, 7.4), Vector2(-7.3, 4.5), Vector2(7.3, -4.5), Vector2(0, -7.3), Vector2(0, 4.3), Vector2(0, 0)]:
		check(area.contains_position(local_point(p.x, p.y), 0.01), "real ring/entry/interior support " + str(p))
	for p in [Vector2(0, 9.1), Vector2(-2.8, 6.35), Vector2(-1.36, 6.05), Vector2(5.93, 3.05), Vector2(7.05, -1.3), Vector2(2.3, 1.4), Vector2(3, 5.4)]:
		check(not area.contains_position(local_point(p.x, p.y), 0.01), "sea/prop/wall space rejected " + str(p))
	var dock: Node3D = shop.landing_point("main")
	var l: Dictionary = dock.data()
	var park := dock.get_node("BoatPark").global_position as Vector3
	check(main._is_open_water(park.x, park.z), "boat park outside actual deck blocker")
	var stand: Vector3 = dock.stand_position()
	check(not main._is_open_water(stand.x, stand.z), "visible deck blocks boats")
	var route: Array = main.navigation.plan_route_to(Vector2(main.boat.global_position.x, main.boat.global_position.z), park.x, park.z)
	check(not route.is_empty() and main.navigation.valid_route(route), "normal sea route from current home boat to remote shop")
	check(area.path_between(local_point(0, 7.9), local_point(0, 0)).size() >= 2, "nav route crosses the real open shop entrance")
	check(area.path_between(local_point(0, 7.9), local_point(0, -7.3)).size() >= 2, "nav route reaches rear ring")
	evidence["navigation"] = {"landing": l, "home_route_waypoints": route.size(), "blocker_rects": shop.water_block_rects.size(), "walk_rects": area.rects.size()}

func _check_source_transforms() -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/gift_kiosk/runtime_manifest.json"))
	for row in manifest.instances:
		var instance: Node3D=shop.get_node("Visual/"+str(row.godot_group)+"/"+str(row.name))
		var rotation: Array=row.rotation_euler_xyz
		var scale: Array=row.scale
		# This reference uses planar instancing. The independent engine Basis
		# constructor catches row/column transposition in the TSCN serializer.
		check(absf(float(rotation[0]))<0.00001 and absf(float(rotation[1]))<0.00001,"source planar instance axis "+str(row.name))
		var expected_basis:=Basis(Vector3.UP,float(rotation[2])).scaled_local(Vector3(float(scale[0]),float(scale[2]),float(scale[1])))
		var p: Array=row.position
		var expected:=Transform3D(expected_basis,Vector3(float(p[0]),float(p[2]),-float(p[1])))
		check(instance.transform.is_equal_approx(expected),"runtime matches Blender source matrix "+str(row.name))

func _check_normal_landing() -> void:
	var state: Node = root.get_node("GameState")
	var dock: Node3D = shop.landing_point("main")
	var park: Vector3 = dock.get_node("BoatPark").global_position
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	state.enter_zone("sea_supply")
	state.landing_id = "main"
	main.boat.place_at(park, 0)
	main._select_landing({"zone": "sea_supply", "landing": "main"})
	for i in 12:
		await physics_frame
		main._update_walk(1.0 / 60.0)
	check(main.actor_controller.state_id() == "ashore_idle", "normal docking flow lands the real actor")
	check(main.player.get_parent() == main, "actor remains owned by world controller")
	check(main.player.global_position.distance_to(dock.stand_position()) < 0.15, "actor stands on current moving support")
	var counter: Node = shop.get_node("Objects/SupplyCounter")
	check(main._start_walk(area, counter.global_position), "normal walk to shop counter starts")
	# Checkout moved from the entrance apron into the shop. Keep the exact
	# arrival assertion, allowing the genuine longer path through the door.
	for i in 600:
		await physics_frame
		main._update_walk(1.0 / 60.0)
		if main.actor_controller.state_id() == "ashore_idle":
			break
	check(main.player.global_position.distance_to(counter.global_position) < 0.20, "capsule reaches actual supply counter")
	counter.interact(main.player)
	check(main.shop_panel.is_open(), "counter opens the working general store panel")
	main.shop_panel.close()

func _check_idle_carry() -> void:
	var results := []
	for fps in [30, 60, 120]:
		shop.set_motion_time(0)
		main.actor_controller.restore_pose({"mode":0, "player":[local_point(0, 6.3).x, area.surface_y, local_point(0, 6.3).z]})
		main.actor_controller.walk_area = area
		main._update_walk(0.0)
		var max_error := 0.0
		var low := INF
		var high := -INF
		var revision: int = shop.ground_space.revision
		for i in range(1, fps * 14 + 1):
			shop.set_motion_time(float(i) / fps)
			main._update_walk(1.0 / fps)
			max_error = maxf(max_error, absf(main.player.global_position.y - area.surface_y))
			low = minf(low, area.surface_y)
			high = maxf(high, area.surface_y)
			var current: Dictionary = root.get_node("Zones").landing("sea_supply", "main")
			check(absf(float(current.landStand[1]) - area.surface_y) < 0.0001, "public landing follows support")
			check(absf(float(current.boatPark[1]) - 1.12) < 0.0001, "boat park remains at actual waterline")
		check(max_error < 0.002, "idle actor has no accumulated support drift at " + str(fps) + "fps")
		check(high - low > 0.23, "visible platform heave at " + str(fps) + "fps")
		check(shop.ground_space.revision == revision, "rigid motion reuses collision/nav without rebaking")
		var route: Array = area.path_between(local_point(0, 7.4), local_point(0, 0))
		check(not route.is_empty() and absf((route.back() as Vector3).y - area.surface_y) < 0.002, "translated nav map and support agree")
		results.append({"fps":fps,"max_idle_support_error_m":max_error,"heave_peak_to_peak_m":high-low,"ground_rebakes":shop.ground_space.revision-revision})
	evidence["support"] = results

func _check_real_walking() -> void:
	shop.set_motion_time(0)
	var start := local_point(0, 7.4)
	main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]})
	main.actor_controller.walk_area = area
	main._update_walk(0)
	var max_error := 0.0
	var time := 0.0
	var walked := []
	for goal in [Vector2(-7.3,4.3),Vector2(-7.3,-4.3),Vector2(0,-7.3),Vector2(7.3,-4.3),Vector2(7.3,4.6),Vector2(0,7.4),Vector2(0,0)]:
		check(main._start_walk(area,local_point(goal.x,goal.y)), "moving-deck path starts " + str(goal))
		for i in 650:
			time += 1.0 / 30.0
			shop.set_motion_time(time)
			await physics_frame
			main._update_walk(1.0 / 30.0)
			max_error = maxf(max_error,absf(main.player.global_position.y-area.surface_y))
			if main.actor_controller.state_id() == "ashore_idle":
				break
		var reached := local_point(goal.x,goal.y)
		check(main.player.global_position.distance_to(reached)<0.18,"real capsule reaches moving-deck goal "+str(goal))
		walked.append({"goal":str(goal),"actual":str(main.player.global_position)})
	check(max_error<0.035,"walking actor stays on heaving collision surface")
	# Keyboard movement uses the same support and cannot leave the declared deck.
	var before: Vector3 = main.player.global_position
	main.actor_controller.set_move_intent(Vector3.RIGHT)
	for i in 40:
		time += 1.0 / 60.0
		shop.set_motion_time(time)
		await physics_frame
		main._update_walk(1.0 / 60.0)
	main.actor_controller.set_move_intent(Vector3.ZERO)
	for i in 30:
		await physics_frame
		main._update_walk(1.0 / 60.0)
	check(main.player.global_position.x>before.x+0.4,"keyboard movement works on moving support")
	check(area.contains_position(main.player.global_position,0.05),"keyboard character stays supported")
	evidence["walking"]={"goals":walked,"max_support_error_m":max_error}

func _check_restore_at_another_phase() -> void:
	shop.set_motion_time(1.5)
	var saved := local_point(0,6.3)
	shop.set_motion_time(4.6)
	main.actor_controller.restore_pose({"mode":0,"player":[saved.x,saved.y,saved.z]})
	main.actor_controller.walk_area=area
	main._update_walk(0)
	check(absf(main.player.global_position.y-area.surface_y)<0.002,"restored actor attaches to current heave phase")

func _check_save_and_departure() -> void:
	var point: Vector3 = main.player.global_position
	var state := {"zone":"sea_supply","landing":"main","mode":0,"player":[point.x,point.y,point.z],"boat":[]}
	check(main.validate_world_state(state)=="","moving-deck position is accepted by existing save validator")
	var bad := state.duplicate(true)
	bad.player=[point.x+60,point.y,point.z]
	check(main.validate_world_state(bad)!="","open-water actor save remains invalid")
	main.actor_controller.board_player()
	check(main.actor_controller.mode()==1 and main.player.get_parent()==main.boat,"normal board action returns actor to boat")
	var position: Vector3=main.player.position
	for i in 60:
		shop.set_motion_time(20.0+float(i)/30.0)
		main._update_walk(1.0/30.0)
	check(main.player.position.distance_to(position)<0.0001,"old support stops carrying actor after boarding")
