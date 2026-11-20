extends SceneTree
const KEYS := {KEY_W:Vector2(0,-1),KEY_S:Vector2(0,1),KEY_A:Vector2(-1,0),KEY_D:Vector2(1,0)}
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
	obstruction.collision_layer = 256
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
	var start := boat.global_position
	set_direction(Vector3.BACK)
	await tick(240)
	set_direction(Vector3.ZERO)
	await tick(110)
	print("[sea] departed ",start," -> ",boat.global_position," yaw=",boat.rotation.y)
	check(boat.global_position.z > start.z + 2.0 and absf(boat.global_position.y-start.y) < 0.001, "manual departure in screen direction, planar hull")
	check(player.get_parent() == boat and boat.is_still(), "neutral yields stationary boat with same rider")
	var saved := boat.global_transform
	main._on_destination("zone1")
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
	await dock_and_leave(marker, Vector3.RIGHT, "03-straight")
	if main.actor_controller.mode() != 0:
		finish(); return
	await tick(40)
	player.rotation.y = atan2(boat.global_position.x-player.global_position.x,boat.global_position.z-player.global_position.z)
	await tick(5)
	print("[sea-reboard] ",main._formal_berth_result(false)," near=",main._near_action()," actor=", player.global_position," cooldown=",main._boat_key_left," mode=",main.actor_controller.mode())
	await e()
	if not check(main.actor_controller.mode() == 1, "E boards again after handoff"):
		finish(); return
	await dock_and_leave(marker, Vector3(1,0,0.24).normalized(), "04-oblique")
	finish()

func dock_and_leave(marker: Marker3D, direction: Vector3, label: String) -> void:
	# For the first pass return from an open-water flank. In the second pass
	# open a fresh gap using only held input, then approach diagonally.
	var target := marker.global_position
	if boat.global_position.distance_to(target) < 2.0:
		set_direction(Vector3.LEFT)
		await tick(150)
		set_direction(Vector3.ZERO)
		await tick(85)
	# Approach from the port side. Corrections choose keys, not transforms.
	var flank := target + Vector3(-3.3,0,-0.5 if direction.z > 0 else 0.0)
	for i in 720:
		var offset := flank-boat.global_position
		offset.y = 0.0
		if offset.length() < 0.55: break
		set_direction(offset.normalized())
		await tick(1)
	set_direction(Vector3.ZERO)
	await tick(78)
	var pre := boat.global_position
	print("[sea-berth] ",label," approach beginning ",pre," heading ",boat.rotation.y)
	for i in 510:
		var offset := target-boat.global_position
		offset.y = 0.0
		if offset.length() < 0.62 and absf(boat.global_basis.z.dot(marker.global_basis.z)) > 0.88: break
		set_direction(offset.normalized() if offset.length() > 0.35 else direction)
		await tick(1)
	set_direction(Vector3.ZERO)
	await tick(106)
	var result: Dictionary = main._formal_berth_result(true)
	print("[sea-berth] ",label," stopped ",boat.global_transform," result=",result)
	check(boat.global_position.distance_to(pre) > 1.0, label+" approaches by input")
	check(main._boat_shortcut_text() == "上岸" and result.has("point"), label+" safe prompt agrees with berth query")
	var final_boat := boat.global_transform
	await e()
	check(main.actor_controller.mode() == 0 and player.get_parent() == main and main.cam.follow_subject == player, label+" E transfers original actor and camera")
	check(boat.global_transform.is_equal_approx(final_boat), label+" no berth snap")
	await shot(label)


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
