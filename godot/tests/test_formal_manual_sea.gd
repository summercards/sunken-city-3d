extends SceneTree
const KEYS := {KEY_W:Vector2(0,-1),KEY_S:Vector2(0,1),KEY_A:Vector2(-1,0),KEY_D:Vector2(1,0)}
const ACTIONS := {KEY_W: &"move_forward", KEY_S: &"move_back", KEY_A: &"move_left", KEY_D: &"move_right"}
var main
var boat: CharacterBody3D
var player: CharacterBody3D
var n := 0
var bad := 0
var held: Array[Key] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, title: String) -> bool:
	n += 1
	if not ok:
		bad += 1
		printerr("FAIL [formal-manual-sea] ", title)
	return ok

func tick(frames: int) -> void:
	for i in frames:
		for code: Key in ACTIONS:
			if held.has(code): Input.action_press(ACTIONS[code])
			else: Input.action_release(ACTIONS[code])
		await physics_frame
		await process_frame

func key(k: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)

func set_direction(world: Vector3) -> void:
	var best: Array[Key] = []
	var score := 0.0
	for a: Key in KEYS:
		for b: Key in KEYS:
			var v: Vector3 = main._camera_relative(KEYS[a]+KEYS[b])
			if v.dot(world) <= score: continue
			score = v.dot(world)
			best.clear(); best.append(a)
			if b != a: best.append(b)
	for k in held:
		if not best.has(k): key(k,false)
	for k in best:
		if not held.has(k): key(k,true)
	held = best
	Input.flush_buffered_events()

func e() -> void:
	for down in [true,false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.physical_keycode = KEY_E
		ev.pressed = down
		root.push_input(ev,true)
		await tick(2)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/formal-manual-"+name+".png") == OK, "rendered "+name)
	await process_frame

func finish() -> void:
	set_direction(Vector3.ZERO)
	if is_instance_valid(main) and main.is_inside_tree():
		main.queue_free()
		await process_frame
		await process_frame
	print("[formal-manual-sea] %d checks, %d failures" % [n,bad])
	quit(0 if bad == 0 else 1)

func run() -> void:
	if not check(DisplayServer.get_name() != "headless" and ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn" and str(ProjectSettings.get_setting("application/config/custom_user_dir_name")).begins_with("sea-verification/"), "formal isolated real window"):
		finish(); return
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.focus_entered.disconnect(main._on_surface_focus_entered)
	root.focus_exited.disconnect(main._on_surface_focus_exited)
	main._on_surface_focus_entered()
	await tick(25)
	boat = main.boat
	player = main.player
	var land: Node3D = main._current_landing()
	var marker: Marker3D = land.get_node("BoatPark")
	main.actor_controller.reconcile_mode(0)
	if player.get_parent() != main: player.reparent(main,true)
	player.global_position = land.stand_position()
	player.set_grounded_motion(true)
	player.rotation.y = 0.0
	# Preserve the authored viewing family, freeze only orientation for replay.
	main.cam.set_process(false)
	main.cam.position = land.global_position + Vector3(0,12,13)
	main.cam.look_at(land.global_position + Vector3(0,0,1),Vector3.UP)
	await tick(8)
	print("[sea] board query=",main._formal_berth_result(false)," park=",marker.global_transform," ship=",boat.global_transform," actor=",player.global_position)
	check(boat.get_node("HullCollision").shape is ConvexPolygonShape3D and boat.hull_clear(), "formal convex hull at authored berth")
	check(main._boat_shortcut_text() == "上船" and main.prompt.shortcut == "上船", "safe board prompt")
	var obstruction := StaticBody3D.new()
	obstruction.collision_layer = player.SCENE_GROUND_LAYER
	obstruction.collision_mask = 0
	var blocker := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	blocker.shape = box
	obstruction.add_child(blocker)
	main.add_child(obstruction)
	# Obstruct the capsule, not a different berth or the incoming hull.
	obstruction.global_position = player.global_position + Vector3.UP * 0.8
	await tick(3)
	var denied_pose := player.global_transform
	var denied_camera: Transform3D = main.cam.global_transform
	var unavailable: Dictionary = main._formal_berth_result(false)
	var focus: Dictionary = main._near_action()
	print("[sea-denial] ", unavailable, " focus=", focus.get("kind", ""), " hint=", main.prompt.unavailable_hint)
	check(main.prompt.shortcut == "" and unavailable.has("reason") and (not main.prompt.unavailable_hint.is_empty() or focus.get("kind") == "spot"), "unsafe berth has a reason, never advertises E board, and yields to existing land focus")
	await e()
	check(main.actor_controller.mode() == 0 and player.get_parent() == main and player.global_transform.is_equal_approx(denied_pose) and main.cam.global_transform.is_equal_approx(denied_camera), "E at obstructed berth leaves actor and camera untouched")
	obstruction.queue_free()
	await tick(4)
	await e()
	if not check(main.actor_controller.mode() == 1 and player.get_parent() == boat, "E boards real same actor"):
		finish(); return
	await shot("01-board")
	await check_docking_area(land, marker)
	var start := boat.global_position
	set_direction(Vector3.BACK)
	for i in 420:
		if boat.global_position.z > start.z + 3.0: break
		await tick(1)
	set_direction(Vector3.ZERO)
	await tick(110)
	print("[sea] departed ",start," -> ",boat.global_position," yaw=",boat.rotation.y)
	check(boat.global_position.z > start.z + 2.0 and absf(boat.global_position.y-start.y) < 0.001, "manual departure in screen direction, planar hull")
	check(player.get_parent() == boat and boat.is_still(), "neutral yields stationary boat with same rider")
	var saved := boat.global_transform
	check(not main.has_method("_on_destination") and not boat.has_method("sail_to"), "automatic sailing commands are removed")
	await tick(20)
	check(boat.global_transform.is_equal_approx(saved), "destination no longer moves the boat")
	var camera_subject: Node3D = main.cam.follow_subject
	await e()
	check(player.get_parent() == boat and main.cam.follow_subject == camera_subject, "E outside berth refuses without handoff")
	var contact: Object
	var advanced := 0.0
	for i in 475:
		set_direction(Vector3.FORWARD)
		await tick(1)
		advanced = maxf(advanced, saved.origin.z-boat.global_position.z)
		if i % 90 == 89: print("[sea-progress] frame=",i+1," pos=",boat.global_position," drive=",boat.drive_dir," speed=",boat.velocity," title/modal=",main.input_blocked())
		contact = boat.shore_contact()
		if is_instance_valid(contact): break
	print("[sea] head-on advances=",advanced," stopped=",boat.global_transform," contact=",contact.get_path() if contact is Node else contact)
	check(is_instance_valid(contact) and str(contact.name) == "BoardHullContact", "original formal bridge stops real hull")
	var stopped := boat.global_position
	if not is_instance_valid(contact):
		finish(); return
	await tick(40)
	check(boat.global_position.distance_to(stopped) < 0.025, "held into contact does not creep")
	await shot("02-contact")
	set_direction(Vector3.BACK)
	await tick(195)
	set_direction(Vector3.ZERO)
	await tick(100)
	print("[sea] edge release ",stopped," -> ",boat.global_position," hull_clear=",boat.hull_clear())
	check(boat.global_position.z > stopped.z+0.7 and boat.hull_clear(), "changed direction releases physical edge")
	await dive_and_return()
	await collect_manually()
	# Walk the hull away, then turn through a perpendicular intermediate lane
	# before approaching the authored pontoon parallel to its edge.
	# The separate surface-handoff replay covers the full parallel berth
	# approach against the wider authored bridge body.
	finish()

func check_docking_area(land: Node3D, park: Marker3D) -> void:
	var area := land.get_node("DockEdge/DockingArea") as Area3D
	var aligned_pose := boat.global_transform
	var seated_pose := player.transform
	var along := park.global_basis.z.normalized()
	var away := Vector3.BACK
	await tick(25)
	var offset_pose := aligned_pose.translated(along * 3.2)
	boat.global_transform = offset_pose
	await tick(6)
	check(area.overlaps_body(boat) and not area.overlaps_body(player), "dock detects the hull on the boat layer")
	var result: Dictionary = main._formal_berth_result(true)
	print("[sea-docking] centre offset=", offset_pose.origin.distance_to(park.global_position), " result=", result)
	check(result.get("node") == land and result.has("point") and main._boat_shortcut_text() == "上岸", "hull overlap works outside the former centre radius")
	player.transform = seated_pose.translated(Vector3.UP * 2.0)
	await tick(3)
	check(main._formal_berth_result(true).has("point"), "rider position does not change the overlap result")
	player.transform = seated_pose

	boat.global_transform = aligned_pose.translated(away * 2.0)
	await tick(6)
	check(not area.overlaps_body(boat) and main._boat_shortcut_text() != "上岸", "leaving the trigger clears the disembark prompt")
	await e()
	check(player.get_parent() == boat, "E outside the hull trigger cannot disembark")

	boat.global_transform = aligned_pose
	await tick(6)
	check(main._formal_berth_result(true).has("point"), "returning the hull to the trigger restores disembark")


func dive_and_return() -> void:
	var session: Node = main.dive
	var pose := boat.global_transform
	var camera: Camera3D = main.cam
	var subject := player.get_instance_id()
	var hull := boat.get_instance_id()
	main._on_dive()
	for i in 1200:
		if session.active and not session.switching: break
		await tick(1)
	check(session.active and str(session.source_id) == "home_seabed" and str(session.map_id) == "dive_home_seabed", "normal dive command preserves the home-water priority")
	if not session.active: return
	await shot("02a-underwater")
	main._on_dive()
	for i in 1200:
		if not session.active and not session.switching: break
		await tick(1)
	check(not session.active and not session.switching and main.is_inside_tree() and main.boat.get_instance_id() == hull and main.player.get_instance_id() == subject, "resumes exact Main, hull and actor after dive")
	check(boat.global_transform.is_equal_approx(pose) and player.get_parent() == boat and root.get_camera_3d() == camera and not main.input_blocked(), "dive restores actual hull pose, camera and motion input")

func collect_manually() -> void:
	# Only the spawned test prop is placed, never the boat or player.
	var start := boat.global_position
	var economy := root.get_node("Economy")
	var wood: int = economy.count("wood")
	main.props._spawn_crate(Vector2(start.x,start.z+5.4))
	var cargo: Dictionary = main.props.crates.back()
	var reach: float = main.props.crate_reach(cargo)
	main._handle_prop_click({"type":"crate","item":cargo})
	await tick(8)
	check(not boat.starts_sailing() and boat.global_position.is_equal_approx(start) and main.props.crates.has(cargo), "far salvage click cannot move, enlarge reach, or pay")
	for i in 450:
		var offset: Vector3 = cargo.root.global_position-boat.global_position
		offset.y = 0.0
		if offset.length() < reach-0.30: break
		set_direction(offset.normalized())
		await tick(1)
	set_direction(Vector3.ZERO)
	await tick(105)
	if main.props.crates.has(cargo): await e()
	await tick(115)
	check(not main.props.crates.has(cargo) and economy.count("wood") > wood, "actual manual approach collects floating wood using original reach and reward")
