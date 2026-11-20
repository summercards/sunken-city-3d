extends SceneTree
## Formal F5 configuration, fresh traveler, and real viewport keyboard input.
const MAIN := "res://scenes/main.tscn"
const RAMP := "World/Zones/Zone1HomeHarbor/WalkAreas/TemporaryHomeRamp"
const MOVE := {&"move_forward": Vector2(0, -1), &"move_back": Vector2(0, 1), &"move_left": Vector2(-1, 0), &"move_right": Vector2(1, 0)}
const KEYS := {&"move_forward": KEY_W, &"move_back": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D}
var main
var held := &""
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [formal-home-ramp] ", label)
	return ok

func wait_for(predicate: Callable, frames := 240) -> bool:
	for i in frames:
		if predicate.call(): return true
		await process_frame
	return bool(predicate.call())

func tap(key: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func hold(action: StringName) -> void:
	if held == action: return
	for pair: Array in [[held, false], [action, true]]:
		if pair[0] == &"": continue
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[pair[0]]
		event.pressed = pair[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	held = action

func shot(name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png("res://outputs/home-ramp-" + name + ".png") == OK, "real image " + name)
	for i in 3: await process_frame

func walk_to(goal: Vector3, label: String) -> bool:
	var before: Vector3 = main.player.global_position
	var last := before
	var big_step := 0.0
	for i in 360:
		var here: Vector3 = main.player.global_position
		big_step = maxf(big_step, here.distance_to(last))
		last = here
		var offset := Vector3(goal.x - here.x, 0, goal.z - here.z)
		if offset.length() < 0.16 and absf(here.y - goal.y) < 0.16:
			hold(&"")
			print("[formal-home-ramp-trace] ", label, " from=", before, " at=", here, " step_max=", big_step)
			return check(big_step < 0.18 and main.player.ground_contact, label + " continuous grounded capsule")
		var best := -INF
		var action := &""
		for name in MOVE:
			var axis: Vector3 = main._camera_relative(MOVE[name])
			var score := axis.dot(offset)
			if score > best:
				best = score
				action = name
		hold(action)
		await physics_frame
		await process_frame
	hold(&"")
	return check(false, "%s from %s wanted %s stopped at %s support=%s" % [label, before, goal, main.player.global_position, main.player.ground_contact])

func run() -> void:
	var project := str(ProjectSettings.get_setting("application/run/main_scene"))
	var slot := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not check(project == MAIN and slot.begins_with("sea-verification/") and not FileAccess.file_exists("res://override.cfg"), "actual F5 project setting, no override, isolated user data"):
		finish(); return
	if not check(DisplayServer.get_name() != "headless" and root.has_node("Zones") and root.has_node("Economy") and root.has_node("GameState"), "real renderer and three Autoloads"):
		finish(); return
	if not check(change_scene_to_file(project) == OK, "load configured Main"):
		finish(); return
	await scene_changed
	main = current_scene
	main._autosave_on = false
	var ramp: Node3D = main.get_node_or_null(RAMP)
	if not check(ramp != null and ramp.get_meta("temporary_fixture", false), "temporary ramp is installed in the actual map"):
		finish(); return
	if not check(await wait_for(func(): return main._title_active and is_instance_valid(main.start_screen)), "native title started"):
		finish(); return
	await create_timer(1.4).timeout
	var button: Button = main.start_screen.start_button
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	if not check(await wait_for(func(): return main.avatar_session.phase == "editing"), "title click enters fresh onboarding"):
		finish(); return
	var editor = main.avatar_session.editor
	editor.name_input.text = "坡道测试旅人"
	editor.name_input.text_changed.emit("坡道测试旅人")
	editor.advance()
	editor.advance()
	editor.advance()
	if not check(await wait_for(func(): return not main._title_active and main.hud.narrative_active()), "fresh traveler reaches normal dock story"):
		finish(); return
	for i in 12:
		if not main.hud.narrative_active(): break
		await tap(KEY_ENTER)
	if not check(not main.input_blocked() and main.actor_controller.mode() == 0, "normal dock spawn releases input"):
		finish(); return
	var low: Vector3 = ramp.get_node("LowMark").global_position
	var high: Vector3 = ramp.get_node("HighMark").global_position
	var player: Vector3 = main.player.global_position
	check(player.distance_to(low) > 0.8, "starts off the ramp")
	check(main.cam.is_position_in_frustum(ramp.get_node("RampSign").global_position), "ramp sign visible from new traveler spawn")
	await shot("01-spawn")
	var exit_point := low + Vector3(0, 0, 1.35)
	if not await walk_to(low, "spawn to foot") or not await walk_to(high, "unassisted uphill"):
		finish(); return
	await shot("02-top")
	if not await walk_to(low, "unassisted downhill") or not await walk_to(exit_point, "walk off onto original deck"):
		finish(); return
	check(absf(main.player.global_position.y - player.y) < 0.08, "back at original deck height")
	await shot("03-exit")
	finish()

func finish() -> void:
	hold(&"")
	print("[formal-home-ramp] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
