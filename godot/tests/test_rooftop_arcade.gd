extends SceneTree

const PATH := "World/SeaStructures/rooftop_arcade"
const PARTS := "res://scenes/components/facilities/rooftop_arcade/"
const PALETTE := "res://assets/textures/shared/sea_rooftop_arcade_8x8_512.png"
var checks := 0
var failures := 0
var main: Node

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func capture(name: String, eye: Vector3, target: Vector3) -> void:
	main.cam.global_position = eye
	main.cam.look_at(target)
	main.cam.fov = 40.0
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var pixel := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	check(not pixel.is_equal_approx(image.get_pixel(10, 10)), "nonuniform rendered image " + name)
	check(image.save_png("res://outputs/rooftop-arcade-" + name + ".png") == OK, "wrote PNG " + name)

func run() -> void:
	var files := DirAccess.get_files_at(PARTS)
	var count := 0
	for filename in files:
		if not filename.ends_with(".tscn"):
			continue
		count += 1
		var scene := load(PARTS + filename) as PackedScene
		check(scene != null, "independent package " + filename)
		if scene == null:
			continue
		var part := scene.instantiate() as Node3D
		check(part.transform == Transform3D.IDENTITY and part.get_meta("asset_version", "") == "v001", "root contract " + filename)
		var meshes := part.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), "nonempty visual " + filename)
		for node: MeshInstance3D in meshes:
			for surface in node.mesh.get_surface_count():
				var mat := node.get_active_material(surface) as BaseMaterial3D
				check(mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path == PALETTE and mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "palette " + filename)
		part.free()
	check(count == 41, "41 component wrappers")
	var world := load("res://scenes/main.tscn") as PackedScene
	if world == null:
		check(false, "production main scene loads")
		finish()
		return
	main = world.instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.suspend_follow()
	main.cam.set_process(false)
	main.boat.set_process(false)
	main.hud.hide()
	root.get_node("Economy").ticking = false
	for i in 10:
		await process_frame
	var arcade: Node3D = main.get_node_or_null(PATH)
	check(arcade != null, "mounted in production main")
	if arcade == null:
		finish()
		return
	check(main._zone_nodes.get("rooftop_arcade") == arcade and arcade.is_visible_in_tree(), "registered and visible in default scope")
	check(arcade.get_node("Visual").get_child_count() == 355, "355 visual instances")
	check(arcade.get_node("Blockers").derived_tris > 0 and not arcade.water_block_rects.is_empty(), "waterline geometry blocks sailing")
	check(arcade.get_node_or_null("Objects") == null, "no shop or other interactions")
	var area: Node3D = arcade.walk_areas[0]
	var dock: Node3D = arcade.landing_point("main")
	var park: Vector3 = dock.get_node("BoatPark").global_position
	check(area.contains_position(dock.stand_position(), 0.01) and arcade.ground_space.navigation_polygons > 0, "ground projection supports landing")
	check(is_equal_approx(park.y, main.WATER_LEVEL), "park is on the real waterline")
	for rect: Rect2 in arcade.water_block_rects:
		check(not rect.has_point(Vector2(park.x, park.z)), "park outside arcade obstruction")
	var other: Node3D = main.get_node("World/SeaStructures/floating_shop")
	for a: Rect2 in arcade.water_block_rects:
		for b: Rect2 in other.water_block_rects:
			check(not a.intersects(b), "shop and arcade water envelopes do not overlap")
	var boat_start: Vector3 = main.boat.global_position
	var route: Array = main.navigation.plan_route_to(Vector2(boat_start.x, boat_start.z), park.x, park.z)
	check(main._is_open_water(park.x, park.z) and not route.is_empty() and main.navigation.valid_route(route), "home boat can route to the real dock")
	var render := DisplayServer.get_name() != "headless"
	var p := arcade.global_position
	if render:
		main.daylight_rig.apply(12.0)
		await capture("near-gift-kiosk", p + Vector3(-22, 21, 24), (p + other.global_position) * 0.5 + Vector3.UP * 2.0)
	var state := root.get_node("GameState")
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	state.enter_zone("rooftop_arcade")
	state.landing_id = "main"
	main.boat.place_at(park, 0)
	if render:
		await capture("boat-approach", park + Vector3(-5, 4, 4), p + Vector3.UP * 2.4)
	main._select_landing({"zone":"rooftop_arcade", "landing":"main"})
	for i in 20:
		await physics_frame
		main._update_walk(1.0 / 60.0)
	check(main.actor_controller.state_id() == "ashore_idle" and main.player.get_parent() == main, "standard landing flow disembarks real actor")
	check(main.player.global_position.distance_to(dock.stand_position()) < 0.18, "actor reaches the deck")
	for goal: Vector3 in [arcade.to_global(Vector3(-1.8, 0.42, -0.22)), dock.stand_position()]:
		check(main._start_walk(area, goal), "walking route begins")
		for i in 180:
			await physics_frame
			main._update_walk(1.0 / 60.0)
			if main.actor_controller.state_id() == "ashore_idle":
				break
		check(main.player.global_position.distance_to(goal) < 0.18, "capsule reaches deck goal " + str(goal))
	if render:
		await capture("ashore", p + Vector3(-6, 5, -7), p + Vector3.UP * 2.4)
	main._select_landing({"zone":"rooftop_arcade", "landing":"main"})
	for i in 40:
		await physics_frame
		main._update_walk(1.0 / 60.0)
	check(main.player.get_parent() == main.boat, "standard landing control boards the actor again")
	main.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("[rooftop-arcade] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
