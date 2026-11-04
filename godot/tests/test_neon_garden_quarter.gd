extends SceneTree

const COMPONENTS := "res://scenes/components/facilities/neon_garden_quarter/"
const SURVEYED_SUNROOM := Vector2(6.149682, 2.473711)
const PALETTE := "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
const POSTER := "res://assets/textures/facilities/neon_garden_quarter/poster_atlas.png"
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		if child is MeshInstance3D and child.mesh != null:
			var part: AABB = child.global_transform * child.mesh.get_aabb()
			result = part if first else result.merge(part)
			first = false
		elif child is MultiMeshInstance3D and child.multimesh != null and child.multimesh.mesh != null:
			for i in child.multimesh.instance_count:
				var transform: Transform3D = child.global_transform * child.multimesh.get_instance_transform(i)
				var part: AABB = transform * child.multimesh.mesh.get_aabb()
				result = part if first else result.merge(part)
				first = false
	return result

func check_components() -> void:
	var count := 0
	var print_surfaces := 0
	for file in DirAccess.get_files_at(COMPONENTS):
		if not file.ends_with(".tscn"): continue
		var component := (load(COMPONENTS + file) as PackedScene).instantiate()
		count += 1
		check(component.get_meta("asset_version") == "v003", file + " stable wrapper version")
		var meshes := component.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), file + " independent geometry")
		for child in meshes:
			var mesh := child as MeshInstance3D
			for i in mesh.mesh.get_surface_count():
				var material := mesh.get_surface_override_material(i) as StandardMaterial3D
				check(material != null and material.albedo_texture != null, file + " role has texture")
				if material == null or material.albedo_texture == null: continue
				var is_poster := material.resource_name == "SEA_Poster"
				print_surfaces += int(is_poster)
				check(material.albedo_texture.resource_path == (POSTER if is_poster else PALETTE), file + " canonical texture")
				check(is_poster or material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, file + " palette nearest")
		component.free()
	check(count == 50, "50 stable independent components")
	check(print_surfaces == 8, "eight original poster panels retain atlas")

func capture(camera: Camera3D, target: Vector3, offset: Vector3, name: String) -> void:
	camera.position = target + offset
	camera.look_at(target)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and image.get_width() >= 800, "real frame " + name)
	if image != null:
		check(image.save_png("res://outputs/neon_garden_" + name + ".png") == OK, "saved frame " + name)

func run() -> void:
	check_components()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 8: await process_frame
	var quarter := main.get_node("World/SeaStructures/neon_garden_quarter") as Node3D
	var p := quarter.global_position
	var live_body := AABB()
	var first := true
	for name in ["后部方形建筑", "前部倾斜太阳能房"]:
		var part := main.get_node("World/Zones/Zone1HomeHarbor").find_child(name, true, false) as Node3D
		check(part != null, "sunroom reference " + name)
		if part != null:
			var measured := bounds(part)
			if measured.size != Vector3.ZERO:
				live_body = measured if first else live_body.merge(measured)
				first = false
	var center := live_body.get_center()
	check((Vector2(p.x, p.z) - SURVEYED_SUNROOM - Vector2(150, 0)).length() < 0.02, "150 m due east of surveyed sunroom body center")
	# The headless MultiMesh fallback has different proxy bounds. Use the rendered geometry for the survey.
	if DisplayServer.get_name() != "headless":
		check(not first and Vector2(center.x, center.z).distance_to(SURVEYED_SUNROOM) < 0.02, "survey agrees with the two rendered sunroom body meshes")
	check(absf(p.y - main.get_node("World/Water").global_position.y) < 0.002, "foundation at world water datum")
	check(quarter.is_visible_in_tree() and quarter.scale.is_equal_approx(Vector3.ONE), "visible in default main at real scale")
	check(quarter.get_node("Visual").get_child_count() == 506, "all Blender placements instantiated")
	var roof: Node3D
	for child in quarter.get_node("Visual").get_children():
		if str(child.name).begins_with("roof_soil_"):roof = child
		if str(child.name).begins_with("crop_bed_"):
			check(child.basis.z.y < -0.37 and child.basis.z.y > -0.40, "crop bed tilt follows front roof plane " + str(child.basis))
	check(roof != null, "gable roof instance exists")
	if roof != null:
		var roof_bounds := bounds(roof)
		check(roof_bounds.size.x > 21 and roof_bounds.size.y > 2.65, "gable mesh spans the alley and rises above its eaves")
	var full_bounds := bounds(quarter)
	check(full_bounds.size.x > 41 and full_bounds.size.y > 39, "widened assembly dimensions")
	check(quarter.water_block_rects.size() > 0 and not main._is_open_water(p.x, p.z), "foundation blocks boats through the street")
	var approach := Vector2(p.x, p.z + 24)
	check(main._is_open_water(approach.x, approach.y), "southern approach is open water")
	var boat_position: Vector3 = main.boat.global_position
	var route: Array = main.navigation.plan_route_to(Vector2(boat_position.x, boat_position.z), approach.x, approach.y)
	check(not route.is_empty() and main.navigation.valid_route(route), "normal boat route from home to quarter approach")
	check(not main.cam.pan_bounds.has_area() or main.cam.pan_bounds.has_point(Vector2(p.x, p.z)), "camera can pan to the quarter")
	check(main._zone_nodes.get("neon_garden_quarter") == quarter, "registered for landing in default scope")
	var landing := quarter.get_node("WalkAreas/WalkStreetLanding/Landing_main") as Marker3D
	var park := landing.get_node("BoatPark") as Marker3D
	check(main._is_open_water(park.global_position.x, park.global_position.z), "park lies outside the boat blockers")
	var state := root.get_node("GameState")
	state.enter_zone("neon_garden_quarter")
	state.landing_id = "main"
	state.set_mode(state.Mode.ON_BOAT)
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	var boarded: bool = main._step_ashore()
	check(boarded, "real character steps ashore at street landing")
	if boarded:
		for i in 450:
			main.actor_controller.tick(1.0 / 60.0)
			if not main.actor_controller.walking():break
		check(main.player.global_position.distance_to(landing.global_position) < 0.65, "character lands on the paved street")
		var target := quarter.to_global(Vector3(6.2, .3, 8.3))
		var walking: bool = main.actor_controller.start_walk(landing.ground(), target)
		check(walking, "street approach supports a short walk")
		if walking:
			for i in 450:
				main.actor_controller.tick(1.0 / 60.0)
				if not main.actor_controller.walking():break
			check(main.player.global_position.distance_to(target) < .65, "character reaches destination on street paving")
	print("[neon-garden-quarter] evidence ", {"anchor": p, "live_sunroom_mesh_bounds": live_body, "extent": full_bounds, "blockers": quarter.water_block_rects.size(), "route_waypoints": route.size()})
	if DisplayServer.get_name() != "headless":
		main.set_process(false)
		var camera := Camera3D.new()
		camera.fov = 41.0
		main.add_child(camera)
		camera.make_current()
		await capture(camera, p + Vector3(-1, 17, -2), Vector3(-48, 34, 62), "overview")
		await capture(camera, p + Vector3(0, 25.8, 1), Vector3(-3, 12, 38), "roof")
		await capture(camera, p + Vector3(0, 13, -1), Vector3(41, 9, -54), "rear")
	print("[neon-garden-quarter] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
