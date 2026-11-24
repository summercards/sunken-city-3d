extends SceneTree
## Real F5 -> fresh dock arrival -> manual voyage -> grounded walking again.
const MAIN := "res://scenes/main.tscn"
const WASD := [KEY_A, KEY_D, KEY_W, KEY_S]
const ARROWS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
const DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
var main
var boat: Boat
var player: Character
var camera: OrbitCam
var held: Array[Key] = []
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL [formal-surface-handoff] ", label)
	return condition

func tick(frames := 1) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func until(predicate: Callable, frames: int) -> bool:
	for i in frames:
		if predicate.call(): return true
		await tick()
	return bool(predicate.call())

func key(code: Key, pressed: bool, viewport := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.shift_pressed = pressed if code == KEY_SHIFT else Input.is_physical_key_pressed(KEY_SHIFT)
	event.pressed = pressed
	if viewport:
		event.keycode = code
		root.push_input(event, true)
	else:
		Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true, true)
	await tick()
	key(code, false, true)
	await tick()

func mouse(button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)

func drag(from: Vector2, offset: Vector2, buttons: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = from+offset
	event.relative = offset
	event.button_mask = buttons
	root.push_input(event, true)

func keys(next: Array[Key]) -> void:
	for k in held:
		if not next.has(k): key(k, false)
	for k in next:
		if not held.has(k): key(k, true)
	held = next
	Input.flush_buffered_events()
	# Maintain the replay's keys if the OS releases the injected events.
	var actions := [&"move_left", &"move_right", &"move_forward", &"move_back"]
	for i in actions.size():
		if held.has(WASD[i]) or held.has(ARROWS[i]):
			Input.action_press(actions[i])
		else:
			Input.action_release(actions[i])

func horizontal(v: Vector3) -> Vector3: return Vector3(v.x, 0.0, v.z)

func heading(axis: Vector2) -> Vector3:
	var forward := horizontal(-camera.global_basis.z).normalized()
	return (forward.cross(Vector3.UP)*axis.x-forward*axis.y).normalized()

func steer(world: Vector3) -> void:
	var best: Array[Key] = []
	var score := 0.0
	for i in DIRECTIONS.size():
		for j in range(i,DIRECTIONS.size()):
			var alignment := heading(DIRECTIONS[i]+DIRECTIONS[j]).dot(world)
			if alignment <= score: continue
			score = alignment
			best.clear()
			best.append(WASD[i])
			if i != j: best.append(WASD[j])
	keys(best)

func move_toward_point(body: Node3D, goal: Vector3, radius: float, frames: int, forward_axis := Vector3.ZERO) -> bool:
	for i in frames:
		var delta := horizontal(goal-body.global_position)
		if delta.length() <= radius and (forward_axis == Vector3.ZERO or absf(body.global_basis.z.dot(forward_axis)) > 0.88):
			keys([])
			return true
		steer(delta.normalized())
		await tick()
	keys([])
	return false

func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(not image.is_empty() and not camera.is_position_behind(player.global_position) and camera.is_position_in_frustum(player.global_position) and image.save_png("res://outputs/formal-handoff-"+label+".png") == OK, "real viewport: "+label)
	await process_frame

func finish() -> void:
	keys([])
	print("[formal-surface-handoff] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func run() -> void:
	var path := str(ProjectSettings.get_setting("application/run/main_scene"))
	var user_dir := str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	if not check(path == MAIN and user_dir.begins_with("sea-verification/") and not FileAccess.file_exists("res://override.cfg") and DisplayServer.get_name() != "headless", "native F5 scene and isolated real viewport"):
		finish(); return
	if not check(change_scene_to_file(path) == OK, "load configured Main"):
		finish(); return
	await scene_changed
	main = current_scene
	main._autosave_on = false
	# This replay injects viewport events and must keep running when the host
	# switches apps. The product window still handles genuine focus changes.
	root.focus_entered.disconnect(main._on_surface_focus_entered)
	root.focus_exited.disconnect(main._on_surface_focus_exited)
	main._on_surface_focus_entered()
	if not check(await until(func(): return main._title_active and is_instance_valid(main.start_screen), 240), "normal title opens"):
		finish(); return
	await tick(90)
	var button: Button = main.start_screen.start_button
	var at := button.get_global_transform_with_canvas() * (button.size*0.5)
	mouse(MOUSE_BUTTON_LEFT,true,at)
	await tick()
	mouse(MOUSE_BUTTON_LEFT,false,at)
	if not check(await until(func(): return main.avatar_session.phase == "editing", 240), "title button opens fresh onboarding"):
		finish(); return
	var editor = main.avatar_session.editor
	editor.name_input.text = "家园试航旅人"
	editor.name_input.text_changed.emit("家园试航旅人")
	editor.advance(); editor.advance(); editor.advance()
	if not check(await until(func(): return not main._title_active and main.hud.narrative_active(), 360), "normal arrival at home"):
		finish(); return
	for i in 12:
		if not main.hud.narrative_active(): break
		await tap(KEY_ENTER)
	if not check(not main.input_blocked() and main.actor_controller.mode() == 0, "fresh shore input enabled"):
		finish(); return
	boat = main.boat
	player = main.player
	camera = main.cam
	var berth: Node3D = main._current_landing()
	var park: Marker3D = berth.get_node("BoatPark")
	var away := horizontal(park.global_position-berth.stand_position()).normalized()
	var along := horizontal(park.global_basis.z).normalized()
	var screen := root.get_visible_rect().size * Vector2(0.32,0.44)
	check(root.get_camera_3d() == camera and camera.is_processing() and camera.follow_subject == player and camera.follow_enabled, "shore follows live Explorer")
	var start_on_shore := player.global_position
	check(player.collision_mask == player.SCENE_GROUND_LAYER, "Explorer uses scene-owned home bodies")
	check(not main.has_method("pick_walk_at"), "legacy click walking entry is removed")
	check(await move_toward_point(player,berth.stand_position(),0.7,300), "walks from arrival to the actual berth")
	# Face the boat with real movement; land focus keeps its existing arbitration.
	steer(away)
	await tick(9)
	keys([])
	await tick(20)
	if not check(main.prompt.shortcut == "上船", "E board prompt at the shore berth"):
		print("[handoff] shore=",player.global_position," result=",main._formal_berth_result(false)," focus=",main._near_action())
		finish(); return
	keys([KEY_W,KEY_S])
	await tick(5)
	await tap(KEY_E)
	check(player.get_parent() == main and camera.follow_subject == player and main.prompt.shortcut != "上船", "opposite held keys are not neutral and cannot board")
	keys([])
	await tick(5)
	mouse(MOUSE_BUTTON_RIGHT,true,screen)
	await tick()
	check(camera.rotating, "real right press began a camera drag before boarding")
	var board_view := camera.global_position
	await tap(KEY_E)
	if not check(player.get_parent() == boat and main.actor_controller.vessel == boat and main.actor_controller.mode() == 1 and player.collision_mask == 0, "E boards the same actor and disables ground collision"):
		mouse(MOUSE_BUTTON_RIGHT,false,screen)
		finish(); return
	check(camera.follow_subject == boat and camera.follow_enabled and not camera.rotating and not camera.panning and camera.global_position.distance_to(board_view) < 1.0, "boarding blends to the boat without a snap and cancels drag before mouse release")
	mouse(MOUSE_BUTTON_RIGHT,false,screen)
	await shot("01-aboard")
	var depart := boat.global_position
	var departure_view := camera.global_position
	steer(away)
	if not check(await until(func(): return horizontal(boat.global_position-depart).dot(away) > 3.0, 420), "manual departure clears the bridge"):
		print("[handoff] departure=", boat.global_position-depart, " yaw=", boat.rotation.y,
			" drive=", boat.drive_dir, " contact=", boat.shore_contact())
	keys([])
	check(await until(func(): return boat.is_still() and main.actor_controller.mode() == 1, 130), "WASD release naturally stops the boat")
	var travelled := horizontal(boat.global_position-depart)
	var view_motion := horizontal(camera.global_position-departure_view)
	check(travelled.dot(away) > 3.0 and view_motion.dot(away) > 2.0 and camera.follow_subject == boat and absf(boat.global_position.y-depart.y) < 0.001, "WASD moves the hull and a live camera follows")
	var before_orbit := heading(Vector2.UP)
	mouse(MOUSE_BUTTON_RIGHT,true,screen)
	drag(screen,Vector2(165,0),MOUSE_BUTTON_MASK_RIGHT)
	mouse(MOUSE_BUTTON_RIGHT,false,screen+Vector2(165,0))
	await tick(15)
	var after_orbit := heading(Vector2.UP)
	check(before_orbit.dot(after_orbit) < 0.85, "mouse orbit changes the actual screen direction")
	# Pick the arrow most aligned away from the dock, then measure actual travel.
	var arrow := 0
	for i in DIRECTIONS.size():
		if heading(DIRECTIONS[i]).dot(away) > heading(DIRECTIONS[arrow]).dot(away): arrow = i
	var before_arrow := boat.global_position
	var arrow_heading := heading(DIRECTIONS[arrow])
	keys([ARROWS[arrow]])
	await tick(180)
	check(player.animation_state() == "rowing", "original seated rowing remains active under manual propulsion")
	var regular_speed := boat.velocity.length()
	key(KEY_SHIFT, true)
	Input.flush_buffered_events()
	await tick(80)
	var power_speed := boat.velocity.length()
	check(power_speed >= regular_speed * 1.42 and boat.rowing_pose().power > 0.90,
		"Shift makes the real boat and rowing pose work harder")
	await shot("02-power-stroke")
	key(KEY_SHIFT, false)
	Input.flush_buffered_events()
	await tick(50)
	check(absf(boat.velocity.length() - regular_speed) < 0.05 and boat.rowing_pose().power < 0.03,
		"releasing Shift returns to the regular stroke while continuing to row")
	print("[handoff] regular_speed=", regular_speed, " power_speed=", power_speed)
	keys([])
	await until(func(): return boat.is_still(),120)
	var arrow_motion := horizontal(boat.global_position-before_arrow)
	check(arrow_motion.length() > 1.0 and arrow_motion.normalized().dot(arrow_heading) > 0.85, "arrow drives along the orbited camera's screen axis")
	mouse(MOUSE_BUTTON_LEFT,true,screen)
	drag(screen,Vector2(64,18),MOUSE_BUTTON_MASK_LEFT)
	mouse(MOUSE_BUTTON_LEFT,false,screen+Vector2(64,18))
	await tick(5)
	check(not camera.follow_enabled, "manual pan takes over on the water")
	await tap(KEY_F)
	check(camera.follow_subject == boat and camera.follow_enabled, "F afloat restores boat follow")
	await shot("02-under-way")
	# Line up clear of the outermost board, then follow the berth axis in.
	# Use a fixed view for this leg after the orbit checks above.
	camera.orbit_dir = Vector3(0, 0.8, 1).normalized()
	camera.refresh()
	var entry_lane := park.global_position + away*0.58
	var outside := entry_lane - along*6.2 + away*2.0
	var flank := entry_lane - along*6.2
	check(await move_toward_point(boat,outside,0.50,750), "manual approach reaches the outside approach lane")
	await until(func(): return boat.is_still(),125)
	check(await move_toward_point(boat,flank,0.35,500), "manual approach reaches the berth flank")
	await until(func(): return boat.is_still(),125)
	steer(along)
	check(await until(func(): return absf(horizontal(boat.global_position-park.global_position).dot(along)) < 0.45, 600), "steers along the berth without snapping")
	keys([])
	check(await until(func(): return boat.is_still() and main.actor_controller.mode() == 1,125), "boat comes to rest after approach")
	if not check(await until(func(): return main.prompt.shortcut == "上岸" and main._formal_berth_result(true).has("point"),12), "stop and real E leave prompt agree"):
		print("[handoff] stopped=",boat.global_transform," berth=",main._formal_berth_result(true)," focus=",main._near_action()," displayed=",main.prompt.shortcut)
		finish(); return
	await shot("03-stopped")
	mouse(MOUSE_BUTTON_MIDDLE,true,screen)
	await tick()
	check(camera.rotating,"real middle press began a camera drag before leaving")
	await tap(KEY_E)
	if not check(main.actor_controller.mode() == 0 and player.get_parent() == main and player.collision_mask == player.SCENE_GROUND_LAYER, "E returns the same actor to scene ground"):
		mouse(MOUSE_BUTTON_MIDDLE,false,screen)
		finish(); return
	check(camera.follow_subject == player and camera.follow_enabled and not camera.rotating and not camera.panning,
		"leaving restores Explorer follow and cancels drag before mouse release")
	check(boat.global_position.distance_to(park.global_position) < 0.02
		and absf(angle_difference(boat.global_rotation.y, park.global_rotation.y)) < 0.02,
		"leaving aligns the hull with BoatPark")
	mouse(MOUSE_BUTTON_MIDDLE,false,screen)
	await tick(20)
	var before_walk := player.global_position
	steer(-away)
	await tick(34)
	check(horizontal(player.global_position-before_walk).dot(-away) > 0.55 and player.ground_contact and not boat.starts_sailing(), "ordinary grounded WASD works immediately after leaving")
	keys([])
	await shot("04-ashore")
	check(await move_toward_point(player,start_on_shore,0.7,300) and player.ground_contact, "walks all the way back to the sunroom courtyard")
	await shot("05-returned")
	print("[handoff] travelled=",travelled," follow displacement=",view_motion," arrow=",arrow_motion," ashore=",player.global_position)
	finish()
