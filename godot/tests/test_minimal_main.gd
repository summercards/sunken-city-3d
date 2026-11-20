extends SceneTree

var checks := 0
var failures := 0
var scene: Node3D
var player: CharacterBody3D
var camera: OrbitCam
var deck: StaticBody3D
var ramp: StaticBody3D
var observed_min_y := INF
var grounded_steps := 0
var max_step_y := 0.0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [minimal-main] ", label)

func _finish() -> void:
	print("[minimal-main] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame

func _key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse(button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = root.get_visible_rect().size * 0.5
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _track(frames: int) -> void:
	observed_min_y = INF
	grounded_steps = 0
	max_step_y = 0.0
	for i in frames:
		var before := player.position.y
		await physics_frame
		observed_min_y = minf(observed_min_y, player.position.y)
		max_step_y = maxf(max_step_y, absf(player.position.y - before))
		grounded_steps += int(player.is_on_floor())

func _place(where: Vector3) -> void:
	player.global_position = where
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _wait(8)

func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _capture(name: String) -> void:
	var image := await _frame()
	check(image != null and not image.is_empty(), name + " renders")
	if image != null and not image.is_empty():
		check(image.save_png("res://outputs/minimal-main-" + name + ".png") == OK, name + " screenshot saved")

func _run() -> void:
	var entry := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	check(entry == "res://scenes/main_minimal.tscn", "F5 points to standalone entry")
	check(change_scene_to_file(entry) == OK, "configured entry loads")
	if failures:
		_finish()
		return
	await scene_changed
	scene = current_scene
	check(root.get_children() == [scene], "no autoloads or other scenes in main tree")
	var names: Array[StringName] = []
	for child in scene.get_children():
		names.append(child.name)
	check(names == [&"WorldEnvironment", &"Sun", &"HemisphereFill", &"VioletShadow", &"GroundBounce", &"Ocean", &"Deck", &"Ramp", &"TimberObstacles", &"Boat", &"Player", &"Camera", &"Controls"], "only the minimal scene is assembled")
	player = scene.get_node_or_null("Player") as CharacterBody3D
	camera = scene.get_node_or_null("Camera") as OrbitCam
	deck = scene.get_node_or_null("Deck") as StaticBody3D
	ramp = scene.get_node_or_null("Ramp") as StaticBody3D
	if not (player and camera and deck and ramp):
		check(false, "missing runtime nodes")
		_finish()
		return
	var ocean: MeshInstance3D = scene.get_node("Ocean")
	var high: Vector3 = ramp.get_node("UpperJoin").global_position
	var low: Vector3 = ramp.get_node("LowerJoin").global_position
	var spawn := player.position
	await _wait(12)
	check(player.get_node("BodyCollision").shape is CapsuleShape3D and player.collision_mask & deck.collision_layer != 0, "actual player capsule collides with structure layer")
	check(player.has_node("BodyPivot/HeadLook"), "reused traveler is built")
	check(player.is_on_floor() and absf(player.position.y - low.y) < 0.02, "spawn settles on land at ramp foot")
	check(is_equal_approx(high.y - low.y, 1.0) and high.is_equal_approx(deck.get_node("RampJoin").global_position), "1 m rise and flush high join")
	check(low.y > ocean.position.y and ocean.mesh.get_aabb().size.x >= 1000.0 and ocean.material_override is ShaderMaterial, "walkable foot above visible ocean resource")
	check(camera.current and camera.follow_subject == player and camera.follow_enabled, "camera starts following the traveler")
	check(not FileAccess.file_exists("user://save_slot_0.json"), "no slot created on boot")
	var deck_visual: MeshInstance3D = deck.get_node("Visual")
	var deck_shape: CollisionShape3D = deck.get_node("Collision")
	check(deck_visual.mesh.get_aabb().size.is_equal_approx(deck_shape.shape.size) and deck_visual.transform.is_equal_approx(deck_shape.transform), "deck geometry matches solid collision")
	var ramp_visual: CSGPolygon3D = ramp.get_node("Visual")
	var visual_bounds := ramp_visual.transform * ramp_visual.get_aabb()
	check(visual_bounds.position.is_equal_approx(Vector3(-1.6, 0, 0)) and visual_bounds.size.is_equal_approx(Vector3(3.2, 1.6, 6.0)), "ramp extrusion spans the two matching collision volumes: %s" % visual_bounds)
	check(not ramp_visual.use_collision and ramp.get_node("SlopeCollision").shape is ConvexPolygonShape3D, "slope uses explicit convex static collision")
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		var sea_frame := await _frame()
		ocean.hide()
		var no_sea := await _frame()
		ocean.show()
		var changed := 0
		for y in range(0, sea_frame.get_height(), 20):
			for x in range(0, sea_frame.get_width(), 20):
				var a := sea_frame.get_pixel(x, y)
				var b := no_sea.get_pixel(x, y)
				if a.b > a.r and a.g > a.r and absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b) > 0.15:
					changed += 1
		check(changed > 200, "real renderer shows substantial blue-green ocean: %d screen samples" % changed)
		await _capture("apron")

	var old_z := player.position.z
	var old_camera := camera.position
	_key(KEY_W, true)
	await _track(100)
	print("[minimal-main] uphill mid: player=", player.position, " cam=", camera.position, " start=", old_camera, " velocity=", player.get_real_velocity(), " grounded=", grounded_steps, " action=", player.animation_state())
	check(player.position.y > low.y + 0.22 and player.position.y < high.y - 0.15, "W moves onto ramp, y=%.3f" % player.position.y)
	check(player.position.z < old_z - 3.0 and camera.position.z < old_camera.z - 1.0, "real W input moves player and follow camera")
	check(player.animation_state() == "walking", "walk animation consumes real speed")
	if visual:
		_key(KEY_W, false)
		await _wait(12)
		await _capture("slope")
		_key(KEY_W, true)
	await _track(65)
	check(player.position.z < high.z - 0.25 and absf(player.position.y - high.y) < 0.015 and player.is_on_floor(), "climbs onto deck without jumping")
	check(grounded_steps >= 63 and max_step_y < 0.06, "upper join keeps ground contact without a teleport")
	_key(KEY_W, false)
	await _wait(24)
	check(player.get_real_velocity().length() < 0.06 and player.animation_state() == "idle", "release brakes to idle")
	if visual:
		await _capture("deck")
	_key(KEY_DOWN, true)
	await _track(145)
	_key(KEY_DOWN, false)
	await _wait(12)
	check(player.position.z > low.z + 0.20 and player.position.z < low.z + 2.25 and absf(player.position.y - low.y) < 0.015, "down arrow descends to the apron: %s" % player.position)
	check(grounded_steps >= 141 and max_step_y < 0.06 and observed_min_y >= low.y - 0.015, "continuous downhill contact, no fall through")
	check(player.global_basis.z.dot(Vector3.BACK) > 0.97, "+Z facing reverses with actual movement")

	# Below the top, press toward the exposed deck face outside the ramp opening.
	# A headless or rendered physics run must physically report the deck contact.
	await _place(Vector3(2.4, high.y - 0.65, high.z + 0.35))
	# The outside has no invisible floor: use a real capsule sweep from just outside.
	player.position = Vector3(2.4, high.y - 0.65, high.z + 0.40)
	var side := player.move_and_collide(Vector3.FORWARD * 1.0, true)
	check(side != null and side.get_collider() == deck and side.get_normal().z > 0.9, "deck side blocks the real capsule at visible boundary")
	player.position = Vector3(2.0, low.y - 0.05, lerpf(high.z, low.z, 0.55))
	var slope_side := player.move_and_collide(Vector3.LEFT, true)
	check(slope_side != null and slope_side.get_collider() == ramp and slope_side.get_normal().x > 0.9, "ramp side blocks the capsule; no side-entry through mesh")
	player.position = Vector3(1.85, low.y + 0.06, low.z + 0.5)
	var outside := player.move_and_collide(Vector3.DOWN * 0.3, true)
	check(outside == null, "no invisible collision outside ramp edge")

	await _place(Vector3(0, high.y + 0.03, -0.3))
	var old_dir := camera.dir
	_mouse(MOUSE_BUTTON_RIGHT, true)
	var drag := InputEventMouseMotion.new()
	drag.position = root.get_visible_rect().size * 0.5 + Vector2(135, -18)
	drag.relative = Vector2(135, -18)
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _wait(5)
	check(camera.dir.distance_to(old_dir) > 0.3 and not camera.rotating, "right-drag changes camera orbit and release ends drag")
	var old_distance := camera.distance
	_mouse(MOUSE_BUTTON_WHEEL_UP, true)
	await _wait(5)
	check(camera.distance < old_distance and camera.distance >= camera.zoom_min, "wheel zoom obeys shared bounds")
	var centered_forward := -camera.global_basis.z
	centered_forward.y = 0.0
	centered_forward = centered_forward.normalized()
	var before := player.position
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	await _wait(25)
	var sprint_speed := Vector2(player.get_real_velocity().x, player.get_real_velocity().z).length()
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	await _wait(18)
	check(sprint_speed > 3.7 and sprint_speed <= 4.12, "Shift reaches legacy sprint speed: %.3f" % sprint_speed)
	check((player.position - before).normalized().dot(centered_forward) > 0.97, "movement axes follow the rotated camera")
	check(player.global_basis.z.dot(centered_forward) > 0.97, "player turns smoothly toward new travel direction")
	camera.suspend_follow()
	_key(KEY_F, true)
	_key(KEY_F, false)
	await _wait(4)
	check(camera.follow_enabled and camera.follow_subject == player, "F restores camera follow")

	# Walk across an actual open deck edge, fall under gravity, and return to apron.
	await _place(Vector3(-3.55, high.y + 0.03, -0.2))
	camera.dir = Vector3(0, 0.707107, 0.707107)
	camera.apply_pose()
	_key(KEY_A, true)
	await _track(31)
	_key(KEY_A, false)
	check(observed_min_y < high.y - 0.05 and player.position.x < -4.0, "visible deck edge has no invisible barrier and gravity takes over")
	await _wait(60)
	check(player.position.distance_to(spawn) < 0.08 and player.is_on_floor(), "fall resets player to apron, not a persistent save")
	check(not FileAccess.file_exists("user://save_slot_0.json") and not FileAccess.file_exists("user://water.cfg"), "minimal session produces neither old game saves nor water settings")
	_finish()
