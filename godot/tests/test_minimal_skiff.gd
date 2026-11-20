extends SceneTree

const Entry = preload("res://src/bootstrap/minimal_main.gd")
const Skiff = preload("res://src/navigation/minimal_skiff.gd")
const Walker = preload("res://src/player/minimal_walker.gd")
const AvatarProbe = preload("res://tests/avatar_customization_support.gd")
var _scene: Entry
var _boat: Skiff
var _player: Walker
var _camera: OrbitCam
var _ramp: StaticBody3D
var _shore: Marker3D
var _park: Marker3D
var _visual := false
var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL [minimal-skiff] ", message)

func _finish() -> void:
	print("[minimal-skiff] %d checks, %d failures" % [_checks, _failures])
	quit(int(_failures != 0))

func _key(code: Key, down: bool, repeated := false) -> void:
	var input := InputEventKey.new()
	input.physical_keycode = code
	input.pressed = down
	input.echo = repeated
	Input.parse_input_event(input)
	Input.flush_buffered_events()

func _tap(code: Key, repeated := false) -> void:
	_key(code, true, repeated)
	await _wait(1)
	_key(code, false)
	await _wait(1)

func _mouse_button(button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = root.get_visible_rect().size * 0.5
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse_drag(mask: int = MOUSE_BUTTON_MASK_RIGHT, relative := Vector2(25, -12)) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = mask
	event.relative = relative
	event.position = root.get_visible_rect().size * 0.5 + event.relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _wait(frames: int) -> void:
	for frame in frames:
		await physics_frame

func _capture(tag: String) -> void:
	if not _visual:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_width() >= 1000, tag + " real render")
	if image != null and not image.is_empty():
		_check(image.save_png("res://outputs/minimal-skiff-" + tag + ".png") == OK, "capture " + tag)

func _flat_forward() -> Vector3:
	var f := -_camera.global_basis.z
	return Vector3(f.x, 0.0, f.z).normalized()

func _point_view(direction: Vector3) -> void:
	# Set a known view for the obstacle course. The direction matrix separately
	# exercises native mouse events and never substitutes camera angles for keys.
	_camera.dir = (Vector3.UP - direction.normalized()).normalized()
	_camera.apply_pose()

func _drive_to(key: Key, direction: Vector3, distance: float) -> void:
	var start := _boat.global_position
	_key(key, true)
	for frame in 610:
		await physics_frame
		var remaining := distance - (_boat.global_position - start).dot(direction)
		var speed := maxf(0.0, _boat.velocity.dot(direction))
		var stopping := 0.38 * speed + 0.075 * speed * speed
		if remaining <= stopping + 0.025:
			break
	_key(key, false)
	await _wait(140)
	_check(absf((_boat.global_position - start).dot(direction) - distance) < 0.55 and _boat.is_still(),
		"released %s stops near planned distance %.2f: from %s to %s" % [OS.get_keycode_string(key), distance, start, _boat.global_position])

func _sail(direction: Vector3, distance: float) -> void:
	_point_view(direction)
	await _drive_to(KEY_W, direction, distance)

func _verify_timber_layout() -> void:
	var obstacles := _scene.get_node("TimberObstacles")
	_check(obstacles.get_child_count() == 3, "three default independently placed blocks")
	for block in obstacles.get_children():
		var visual: MeshInstance3D = block.get_node("Visual")
		var collider: CollisionShape3D = block.get_node("Collision")
		var mesh: BoxMesh = visual.mesh
		var shape: BoxShape3D = collider.shape
		_check(block is StaticBody3D and (block.collision_layer & _boat.collision_mask) != 0 and not collider.disabled,
			"%s is solid on the skiff's real collision layer" % block.name)
		_check(mesh.size.is_equal_approx(shape.size) and visual.global_transform.is_equal_approx(collider.global_transform),
			"%s visible geometry and actual collision agree, including rotation" % block.name)
		var bounds := visual.global_transform * mesh.get_aabb()
		_check(bounds.position.y < _boat.global_position.y and bounds.end.y > _boat.global_position.y,
			"%s intersects the waterline and is visible above it" % block.name)

func _hand_error() -> float:
	var pose := _boat.rowing_pose()
	return maxf(_player.left_elbow.get_node("Hand").global_position.distance_to(pose.left_grip),
		_player.right_elbow.get_node("Hand").global_position.distance_to(pose.right_grip))

func _seat_error() -> float:
	var lower_pelvis := INF
	for point in AvatarProbe.points(_player.body_pivot.get_node("AvatarBody/Pelvis"), _boat.model):
		lower_pelvis = minf(lower_pelvis, point.y)
	var bench := _boat.model.get_node("Parts/bench_020")
	var top := -INF
	for mesh in AvatarProbe.meshes(bench):
		for point in AvatarProbe.points(mesh, _boat.model):
			top = maxf(top, point.y)
	return absf(lower_pelvis - top)

func _sail_toward(target: Vector3) -> void:
	var aim := target - _boat.global_position
	aim.y = 0.0
	if aim.length() > 0.18:
		await _sail(aim.normalized(), aim.length())

func _timber_course() -> void:
	var block_a: StaticBody3D = _scene.get_node("TimberObstacles/TimberA")
	var block_b: StaticBody3D = _scene.get_node("TimberObstacles/TimberB")
	var center := (block_a.global_position + block_b.global_position) * 0.5
	var gate := Vector3(center.x, _boat.global_position.y, center.z - 5.8)
	await _hit_timber(block_a, Vector3.BACK, "10-timber-head-on")
	await _sail_toward(gate)
	var diagonal := block_b.global_position - _boat.global_position
	diagonal.y = 0.0
	var face_alignment := absf(diagonal.normalized().dot(block_b.global_basis.z))
	_check(face_alignment > 0.50 and face_alignment < 0.93, "Timber B aimed at diagonally")
	await _hit_timber(block_b, diagonal.normalized(), "11-timber-oblique")
	await _sail_toward(gate)
	_point_view(Vector3.BACK)
	var safe_frames := true
	var collided := false
	var before := _boat.global_position
	_key(KEY_W, true)
	for frame in 470:
		await physics_frame
		safe_frames = safe_frames and not _boat.overlaps_shore(_boat.global_transform)
		collided = collided or _boat.shore_contact() != null
		if _boat.global_position.z > center.z + 2.5:
			break
	_key(KEY_W, false)
	await _wait(160)
	_check(safe_frames and not collided and _boat.is_still() and before.z < center.z - 4.0 and _boat.global_position.z > center.z + 3.0,
		"clear A/B channel: start=%s end=%s yaw=%.3f no_overlap=%s contact=%s stopped=%s" % [before,
			_boat.global_position, _boat.rotation.y, safe_frames, collided, _boat.is_still()])
	await _capture("12-beyond-channel")

func _hit_timber(block: StaticBody3D, travel_direction: Vector3, tag: String) -> void:
	_point_view(travel_direction)
	var start := _boat.global_position
	var impact := Vector3.INF
	var clear := true
	var first_contact: Object
	_key(KEY_W, true)
	for frame in 510:
		await physics_frame
		clear = clear and not _boat.overlaps_shore(_boat.global_transform)
		first_contact = _boat.shore_contact()
		if first_contact != null:
			if first_contact == block:
				impact = _boat.global_position
			break
	print("[timber] ", tag, " start=", start, " heading=", travel_direction, " end=", _boat.global_position,
		" contact=", first_contact, " clear=", clear)
	var impact_heading := -_boat.global_basis.z
	var max_travel := 0.0
	for frame in 32:
		await physics_frame
		max_travel = maxf(max_travel, _boat.global_position.distance_to(impact))
		clear = clear and not _boat.overlaps_shore(_boat.global_transform)
	_check(impact.is_finite() and (impact - start).dot(travel_direction) > 0.6 and clear, "%s: physical contact before overlap" % tag)
	_check(max_travel < 0.075 and _boat.velocity.length() < 0.045 and impact_heading.dot(travel_direction) > 0.94,
		"%s: sustained thrust neither creeps through nor turns the hull" % tag)
	await _capture(tag)
	_key(KEY_W, false)
	await _drive_to(KEY_S, -travel_direction, 4.0)
	_check(impact.is_finite() and (_boat.global_position - impact).dot(-travel_direction) > 3.05,
		"%s: opposite screen input clears the contact and stops again" % tag)

func _rotate_view(pixels: float) -> void:
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	_mouse_drag(MOUSE_BUTTON_MASK_RIGHT, Vector2(pixels, 0.0))
	_mouse_button(MOUSE_BUTTON_RIGHT, false)

func _screen_axes() -> Array[Vector3]:
	var forward := _flat_forward()
	var right := forward.cross(Vector3.UP)
	return [forward, -right, -forward, right]

func _screen_directions() -> void:
	# Move farther out before the matrix so opposing legs cannot hit the course.
	await _sail(Vector3.BACK, 12.0)
	for view_index in 3:
		var old_view := _flat_forward()
		if view_index > 0:
			_rotate_view(153.0 if view_index == 1 else -267.0)
			await _wait(2)
			_check(_flat_forward().dot(old_view) < 0.8, "mouse changes the actual camera heading")
		var expected := _screen_axes()
		var keys := [KEY_W, KEY_A, KEY_S, KEY_D] if view_index < 2 else [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]
		for index in 4:
			var direction := expected[index]
			var origin := _boat.global_position
			_key(keys[index], true)
			for frame in 380:
				await physics_frame
				if _boat.velocity.dot(direction) > 1.8 and (_boat.global_position - origin).dot(direction) > 0.75:
					break
			var moved := _boat.global_position - origin
			_check(moved.dot(direction) > 0.70 and moved.normalized().dot(direction) > 0.95
				and (-_boat.global_basis.z).dot(direction) > 0.95,
				"view %d key %s aims and moves along its screen axis, actual %s" % [view_index, OS.get_keycode_string(keys[index]), moved])
			_key(keys[index], false)
			await _wait(140)
		_check(_boat.is_still(), "release restores stop after direction matrix")
	await _capture("13-camera-relative")

func _land_directions() -> void:
	# Isolated land probes on the existing broad deck: only fixture start poses
	# are reset, movement under every sample is produced by the real key events.
	var deck: StaticBody3D = _scene.get_node("Deck")
	var surface: CollisionShape3D = deck.get_node("Collision")
	var point := surface.global_position + Vector3.UP * ((surface.shape as BoxShape3D).size.y * 0.5 + 0.04)
	var boat_pose := _boat.global_transform
	for view_index in 3:
		if view_index > 0:
			_rotate_view(153.0 if view_index == 1 else -267.0)
			await _wait(2)
		var expected := _screen_axes()
		var keys := [KEY_W, KEY_A, KEY_S, KEY_D] if view_index < 2 else [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]
		for index in 4:
			var direction := expected[index]
			_player.global_position = point
			_player.rotation.y = atan2(-direction.x, -direction.z)
			_player.velocity = Vector3.ZERO
			await _wait(10)
			var origin := _player.global_position
			_key(keys[index], true)
			await _wait(23)
			_key(keys[index], false)
			await _wait(18)
			var moved := _player.global_position - origin
			_check(moved.dot(direction) > 0.65 and moved.normalized().dot(direction) > 0.97 and _player.is_on_floor(),
				"land view %d key %s moves along its screen axis despite opposite facing" % [view_index, OS.get_keycode_string(keys[index])])
	_check(_boat.global_transform.is_equal_approx(boat_pose), "land direction matrix never moves the boat")

func _occlude_landing() -> StaticBody3D:
	var block := StaticBody3D.new()
	block.collision_layer = Walker.ACTOR_LAYER
	block.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.6)
	collider.shape = box
	block.add_child(collider)
	_scene.add_child(block)
	block.global_position = _shore.global_position + Vector3.UP * 0.6
	return block

func _prompt_is(text: String, ready := false) -> bool:
	var sign: Label3D = _ramp.get_node("Berth/BerthSign")
	var hint: Label = _scene.get_node("Controls/Hint")
	return hint.text.contains(text) and sign.text == ("泊位\n" + text if ready else "泊位")

func _test_shore_boundary() -> void:
	var saved := _player.global_transform
	var anchor := _shore.global_position
	# Specified fixture offsets from the authored marker, not a second prompt radius.
	for margin in [0.04, -0.04]:
		_player.global_position = anchor + Vector3.LEFT * (_scene.approach_radius + margin) + Vector3.UP * 0.04
		_player.velocity = Vector3.ZERO
		await _wait(15)
		var ready: bool = margin < 0.0
		_check(_prompt_is("E 上船" if ready else "走近坡脚", ready), "shore boundary %s has the matching prompt" % margin)
		await _tap(KEY_E)
		_check(_scene.aboard() == ready, "E matches the shore boundary prompt %s" % margin)
		if _scene.aboard():
			await _tap(KEY_E)
	_player.global_transform = saved
	_player.velocity = Vector3.ZERO
	await _wait(18)

func _test_water_boundary(parked: Transform3D) -> void:
	var waterline := parked.origin.y
	for margin in [0.04, -0.04]:
		var point: Vector3 = _park.global_position + Vector3.BACK * (_scene.mooring_radius + float(margin))
		point.y = waterline
		_boat.global_transform = Transform3D(_park.global_basis, point)
		await _wait(12)
		var ready: bool = margin < 0.0
		_check(_prompt_is("E 上岸" if ready else "划近泊位", ready), "water boundary %s has the matching prompt" % margin)
		await _tap(KEY_E)
		_check(_scene.aboard() != ready, "E matches the water boundary prompt %s" % margin)
		if not _scene.aboard():
			await _wait(12) # Let the restored capsule reacquire its actual floor.
			_check(_prompt_is("E 上船", true), "safe exit offers boarding again after the capsule settles")
			await _tap(KEY_E)
			_check(_scene.aboard(), "reboard for the next water-side probe")
	# Rotate about the fixture centre on the open side of the berth. Actual
	# collision clearance remains in the production query, not a test stub.
	_boat.global_transform = Transform3D(_park.global_basis.rotated(Vector3.UP, deg_to_rad(_scene.mooring_angle_deg + 6.0)), parked.origin)
	await _wait(12)
	_check(_prompt_is("让船身与甲板边平行"), "still boat inside berth at invalid yaw gets alignment guidance")
	await _tap(KEY_E)
	_check(_scene.aboard(), "misaligned boat cannot disembark")
	_boat.global_transform = parked
	await _wait(12)

func _fixture_water(point: Vector3, direction: Vector3) -> void:
	# Test-only initial pose. All contact, release, and steering after this
	# start are driven by the same keyboard path as the ordinary course.
	point.y = _boat.global_position.y
	_boat.global_transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), point)
	await _wait(12)

func _cruise_turn_probe() -> void:
	var start_heading := Vector3.FORWARD
	var hz := float(Engine.physics_ticks_per_second)
	for degrees in [90.0, 180.0]:
		# Start well clear of solids. Only the start pose is supplied by the
		# fixture; both the run-up and the new direction use actual input events.
		await _fixture_water(Vector3(24, 0, 32), start_heading)
		_point_view(start_heading)
		_key(KEY_W, true)
		await _wait(100)
		var start_speed := _boat.velocity.dot(start_heading)
		var start_yaw := _boat.rotation.y
		var goal := Vector3.RIGHT if degrees == 90.0 else Vector3.BACK
		var key := KEY_D if degrees == 90.0 else KEY_S
		var response_tick := -1
		var aimed_tick := -1
		var stable_tick := -1
		var streak := 0
		var clear := true
		_key(KEY_W, false)
		_key(key, true)
		for tick in range(1, 361):
			await physics_frame
			clear = clear and _boat.shore_contact() == null and not _boat.overlaps_shore(_boat.global_transform)
			var bow := -_boat.global_basis.z
			if response_tick < 0 and absf(angle_difference(start_yaw, _boat.rotation.y)) >= deg_to_rad(3.0):
				response_tick = tick
			if aimed_tick < 0 and bow.dot(goal) >= cos(deg_to_rad(10.0)):
				aimed_tick = tick
			if _boat.velocity.dot(goal) >= 1.0 and _boat.velocity.normalized().dot(goal) >= cos(deg_to_rad(15.0)):
				streak += 1
			else:
				streak = 0
			if streak >= 6 and aimed_tick >= 0:
				stable_tick = tick
				break
		print("[cruise-turn] %.0f entry=%.3f response_3deg=%.3f aim_10deg=%.3f stable_6ticks=%.3f clear=%s" % [degrees,
			start_speed, response_tick / hz, aimed_tick / hz, stable_tick / hz, clear])
		_check(start_speed >= 2.5 and response_tick > 0 and aimed_tick > response_tick and stable_tick >= aimed_tick and clear,
			"%.0f: cruise responds, aims, then travels stably in open water" % degrees)
		_key(key, false)
		await _wait(150)
		_check(_boat.is_still(), "cruise turn still coasts to a stop")
		await _capture("cruise-turn-%03d" % int(degrees))

func _handling_probe() -> void:
	_player.global_position = _shore.global_position + Vector3.UP * 0.03
	await _wait(12)
	await _tap(KEY_E)
	_check(_scene.aboard(), "handling fixture boards using E")
	if not _scene.aboard():
		_finish()
		return
	var timber: StaticBody3D = _scene.get_node("TimberObstacles/TimberA")
	for body in [_ramp, timber]:
		var center: Vector3 = (_ramp.get_node("ApronCollision") as Node3D).global_position if body == _ramp else body.global_position
		var side: float = 1.6 if body == _ramp else 1.2
		for degrees in [0.0, 58.0]:
			var exterior := Vector3.RIGHT if body == _ramp else Vector3.LEFT
			var incoming := (-exterior).rotated(Vector3.UP, deg_to_rad(-degrees if body == _ramp else degrees))
			var face := center + exterior * side
			var distance := 6.35
			if body == timber and is_zero_approx(degrees):
				incoming = Vector3.FORWARD
				face = center + Vector3.BACK
				distance = 4.8
			await _fixture_water(face - incoming * distance, incoming)
			_point_view(incoming)
			_key(KEY_W, true)
			var contact: Object
			var initial_clear := not _boat.overlaps_shore(_boat.global_transform)
			var swept_clear := initial_clear
			for frame in 230:
				await physics_frame
				swept_clear = swept_clear and not _boat.overlaps_shore(_boat.global_transform)
				contact = _boat.shore_contact()
				if contact != null:
					break
			var impact := _boat.global_position
			await _wait(16)
			var hold_drift := _boat.global_position.distance_to(impact)
			_key(KEY_W, false)
			await _wait(2)
			var tangent := Vector3.RIGHT if body == timber and is_zero_approx(degrees) else Vector3.BACK
			_point_view(tangent)
			var yaw := _boat.rotation.y
			var still_frames := 0
			var latched_frames := 0
			var swept_hits := 0
			_key(KEY_W, true)
			for frame in 150:
				await physics_frame
				swept_clear = swept_clear and not _boat.overlaps_shore(_boat.global_transform)
				still_frames += int(_boat.velocity.length() < 0.02 and absf(_boat._turn_rate) < 0.02)
				latched_frames += int(_boat._blocked_intent != Vector3.ZERO)
				swept_hits += int(_boat.shore_contact() != null)
			var escape := (_boat.global_position - impact).dot(tangent)
			var turned := rad_to_deg(absf(angle_difference(yaw, _boat.rotation.y)))
			print("[handling] %s %.0f impact=%s hold=%.4f escape=%.3f yaw=%.2f clear=%s input_latch=%d sweep_contact_frames=%d still=%d initial_clear=%s actual=%s" % [body.name, degrees, contact == body, hold_drift, escape, turned, swept_clear, latched_frames, swept_hits, still_frames, initial_clear, contact])
			_check(contact == body and swept_clear and hold_drift < 0.075 and escape > 0.7 and turned > 12.0,
				"%s %.0f: contact holds, then explicit edge-wise steering turns and clears" % [body.name, degrees])
			_key(KEY_W, false)
			await _wait(145)
			await _capture("handling-%s-%02d" % [body.name, int(degrees)])
	for degrees in [0.0, 18.0, -18.0]:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(degrees))
		var center := _park.global_position
		center.y = _boat.global_position.y
		await _fixture_water(center - direction * 4.8, direction)
		_point_view(direction)
		_key(KEY_W, true)
		var clear := true
		for frame in 250:
			await physics_frame
			clear = clear and not _boat.overlaps_shore(_boat.global_transform)
			if (center - _boat.global_position).dot(direction) < 0.45:
				break
		var up := _boat.global_position
		var release_speed := _boat.velocity.length()
		_key(KEY_W, false)
		await _wait(155)
		var final := _boat.global_position
		var ready := _prompt_is("E 上岸", true)
		await _tap(KEY_E)
		var accepted := not _scene.aboard()
		print("[handling] berth %.0f release=%.3f speed=%.3f coast=%.3f end=%.3f ready=%s E=%s clear=%s" % [degrees, up.distance_to(center), release_speed, up.distance_to(final), final.distance_to(center), ready, accepted, clear])
		_check(ready and accepted and clear, "berth %.0f: release inside, stop safely and E agrees" % degrees)
		if accepted:
			await _wait(12)
			await _tap(KEY_E)
		await _capture("handling-berth-%02d" % (int(degrees) + 18))
	# The marker must never apply motion after release, or oppose departure.
	await _fixture_water(_park.global_position, Vector3.BACK)
	_point_view(Vector3.BACK)
	_key(KEY_W, true)
	await _wait(120)
	_key(KEY_W, false)
	await _wait(160)
	var left := _boat.global_position
	await _wait(75)
	print("[handling] departure=%.3f idle_drift=%.4f" % [left.z - _park.global_position.z, left.distance_to(_boat.global_position)])
	_check(left.z - _park.global_position.z > 2.0 and left.distance_to(_boat.global_position) < 0.005 and not _prompt_is("E 上岸", true), "departure is not pulled back into the berth")
	await _cruise_turn_probe()
	_finish()

func _run() -> void:
	# Feed scripted events on the tick they are issued, rather than batching
	# keyboard and mouse changes at the next rendered frame.
	Input.use_accumulated_input = false
	_visual = DisplayServer.get_name() != "headless"
	var entry := str(ProjectSettings.get_setting("application/run/main_scene"))
	_check(entry == "res://scenes/main_minimal.tscn" and change_scene_to_file(entry) == OK, "real configured minimal entry loads")
	if _failures:
		_finish()
		return
	await scene_changed
	_scene = current_scene as Entry
	_boat = _scene.get_node("Boat")
	_ramp = _scene.get_node("Ramp")
	_shore = _scene.get_node("Ramp/Berth/Shore")
	_park = _scene.get_node("Ramp/Berth/BoatPark")
	_player = _scene.get_node("Player")
	_camera = _scene.get_node("Camera")
	await _wait(18)
	if OS.get_environment("SEA_SKIFF_HANDLING_PROBE") == "1":
		await _handling_probe()
		return
	_check(root.get_children() == [_scene] and _camera.is_current(), "one scene/camera; no legacy autoloads")
	_check(_boat.hull.shape is ConvexPolygonShape3D and (_boat.collision_mask & _ramp.collision_layer) != 0, "editable hull shares real pier collision layer")
	_check(_boat.model.scene_file_path.ends_with("/reference_skiff.tscn"), "uses existing skiff visual asset")
	_verify_timber_layout()
	var spawn := _player.global_position
	var spawn_pose := _player.global_transform
	var spawn_view := _camera.dir
	await _land_directions()
	_player.global_transform = spawn_pose
	_player.velocity = Vector3.ZERO
	_camera.dir = spawn_view
	_camera.restore_follow(_player)
	await _wait(22)
	var start := _boat.global_position
	_check(not _scene.aboard() and _player.is_on_floor() and _camera.follow_subject == _player, "land-only control at launch")
	_check(not _boat.overlaps_shore(_boat.global_transform) and _boat.is_still(), "initial skiff is clear and stationary")
	_check(_prompt_is("走近坡脚"), "land spawn identifies the berth without a false E prompt")
	await _capture("01-land")
	await _tap(KEY_E)
	_check(not _scene.aboard() and _player.global_position.distance_to(spawn) < 0.025 and _camera.follow_subject == _player,
		"E from outside reach does not change subject, position or mode")

	await _test_shore_boundary()
	_key(KEY_D, true)
	await _wait(17)
	_check(_player.global_position.x > spawn.x + 0.35 and _boat.global_position == start, "walk to berth; boat does not consume land input")
	_check(_prompt_is("E 上船", true), "walking into reach displays E on the berth and bottom hint")
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	_check(_camera.rotating, "right-drag is armed before boarding")
	await _tap(KEY_E)
	var boarding_dir := _camera.dir
	_mouse_drag()
	_check(_camera.dir.is_equal_approx(boarding_dir) and not _camera.rotating and not _camera.panning,
		"holding right mouse across successful boarding does not keep the old drag")
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	_check(_scene.aboard() and _player.get_parent() == _boat.seat and not _player.is_physics_processing(), "boards once, with land physics disabled")
	_check(_player.collision_layer == 0 and _player.collision_mask == 0 and _camera.follow_subject == _boat, "boat is sole motion subject and camera target")
	await _wait(25)
	_check(_boat.global_position == start and is_zero_approx(_boat.rotation.y), "held walk key does not turn or propel boat after handoff")
	_key(KEY_D, false)
	await _tap(KEY_E, true)
	_check(_scene.aboard(), "echo E cannot double-transfer")
	_check(_player.animation_state() == "rowing" and _player.position.is_zero_approx() and _boat.rowing_pose().has("left_grip"), "rider follows actual seat and oar anchors")
	_camera.suspend_follow()
	await _tap(KEY_F)
	_check(_camera.follow_enabled and _camera.follow_subject == _boat and not _camera.pan_bounds.has_area(), "F restores the active boat target, without the land pan clamp")
	_check(_prompt_is("E 上岸", true), "boarding refreshes both hints to E 上岸")
	await _capture("02-boarded")

	var wave_y := _boat.model.position.y
	await _wait(85)
	_check(absf(_boat.global_position.y - _scene.get_node("Ocean").global_position.y) < 0.001 and absf(_boat.model.position.y - wave_y) > 0.005 and absf(_boat.model.position.y) < 0.4,
		"physics hull stays at mean sea level while existing wave samples move the visual")
	var camera_start := _camera.global_position
	_key(KEY_S, true)
	await _wait(6)
	_check(_prompt_is("等船停稳"), "motion at berth shows stop guidance rather than E")
	await _capture("14-berth-stop")
	await _tap(KEY_E)
	_check(_scene.aboard() and _player.get_parent() == _boat.seat, "turning inside berth tolerance does not allow disembark")
	_key(KEY_S, false)
	await _wait(30)
	await _drive_to(KEY_S, Vector3.BACK, 4.35)
	_check(_boat.is_still() and _boat.global_position.z > start.z + 3.7 and -_boat.global_basis.z.dot(Vector3.BACK) > 0.95,
		"S from an opposite hull heading turns and actually moves toward screen down, then stops")
	_check(_camera.global_position.z > camera_start.z + 3.3 and _camera.follow_subject == _boat, "camera tracks the sailing hull")
	await _tap(KEY_E)
	_check(_scene.aboard() and _camera.follow_subject == _boat and _player.collision_mask == 0, "off-berth stop cannot disembark")
	await _capture("03-open-water")

	await _sail(Vector3.RIGHT, 4.1)
	await _sail(Vector3.FORWARD, _boat.global_position.z - _park.global_position.z)
	_point_view(Vector3.LEFT)
	var before_hit := _boat.global_position
	_key(KEY_W, true)
	var contact := false
	for frame in 410:
		await physics_frame
		if _boat.shore_contact() == _ramp:
			contact = true
			break
	var impact := _boat.global_position
	await _wait(24)
	_check(contact and impact.x < before_hit.x - 1.0 and not _boat.overlaps_shore(_boat.global_transform), "forward drive reports physical pier contact without overlap")
	_check(_boat.global_position.distance_to(impact) < 0.075, "continued propulsion cannot tunnel into the pier")
	await _capture("04-contact")
	_key(KEY_W, false)
	await _tap(KEY_E)
	_check(_scene.aboard(), "touching shore bow-first is not mooring")
	await _drive_to(KEY_S, Vector3.RIGHT, 3.5)
	_check(_boat.global_position.x > impact.x + 2.0 and not _boat.overlaps_shore(_boat.global_transform), "opposite screen input releases a real collision without a reset")
	await _capture("05-detached")

	# Approach the original berth from its open end with the hull pointing in.
	await _sail(Vector3.BACK, 5.0)
	await _sail(Vector3.LEFT, _boat.global_position.x - _park.global_position.x)
	await _sail(Vector3.FORWARD, _boat.global_position.z - _park.global_position.z)
	var parked := _boat.global_transform
	_point_view(Vector3.FORWARD)
	_check(Vector2(parked.origin.x - _park.global_position.x, parked.origin.z - _park.global_position.z).length() < _scene.mooring_radius, "boat returns to berth by input, not a snap")
	_check(_prompt_is("E 上岸", true), "returning under input shows E 上岸")
	await _capture("06-moored")
	await _test_water_boundary(parked)
	_rotate_view(95.0)
	await _wait(4)
	_check(_prompt_is("E 上岸", true), "camera drag does not change berth readiness")
	await _capture("15-berth-angled")
	_point_view(Vector3.FORWARD)

	var obstruction := _occlude_landing()
	await _wait(4)
	_mouse_button(MOUSE_BUTTON_MIDDLE, true)
	await _tap(KEY_E)
	_check(_scene.aboard() and _player.get_parent() == _boat.seat and _camera.follow_subject == _boat and _boat.global_transform.is_equal_approx(parked),
		"occupied exit rejects without changing rider, hull or camera")
	_check(_camera.rotating and _prompt_is("落脚点不安全"), "rejected E preserves current drag and explains the refusal")
	await _capture("16-berth-unsafe")
	_mouse_button(MOUSE_BUTTON_MIDDLE, false)
	obstruction.queue_free()
	var safe_marker := _shore.position
	_shore.position.y += 0.43
	await _wait(4)
	await _tap(KEY_E)
	_check(_scene.aboard() and _camera.follow_subject == _boat and _player.collision_mask == 0, "unsupported landing does not switch")
	_shore.position = safe_marker
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	_mouse_drag(MOUSE_BUTTON_MASK_LEFT)
	_check(_camera.panning and not _camera.follow_enabled, "left-pan is active before disembarking")
	_mouse_button(MOUSE_BUTTON_MIDDLE, true)
	await _tap(KEY_E)
	var landing_dir := _camera.dir
	_mouse_drag(MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)
	_check(_camera.dir.is_equal_approx(landing_dir) and not _camera.rotating and not _camera.panning and _camera.follow_enabled,
		"holding middle mouse and left pan across disembarking does not keep either drag")
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	_mouse_button(MOUSE_BUTTON_MIDDLE, false)
	await _wait(12)
	_check(not _scene.aboard() and _player.get_parent() == _scene and _player.is_on_floor() and _player.collision_mask == Walker.GROUND_LAYER,
		"safe E returns standing traveler to solid dock and restores capsule")
	_check(_camera.is_current() and _camera.follow_subject == _player and _camera.follow_enabled and _camera.pan_bounds.has_area() and _boat.global_transform.is_equal_approx(parked), "land follow and pan bounds restored; boat not repositioned")
	_check(_prompt_is("E 上船", true), "disembarking refreshes both visible prompts")
	await _capture("07-ashore")
	_check(_player.animation_state() == "idle", "seated pose releases to standing after disembark")
	var on_land := _player.global_position
	_key(KEY_A, true)
	await _wait(17)
	_key(KEY_A, false)
	await _wait(12)
	_check(_player.global_position.x < on_land.x - 0.45 and _boat.global_transform.is_equal_approx(parked), "land movement works again without driving the moored boat")
	await _tap(KEY_E)
	_check(_scene.aboard(), "reboard at the original berth for the live rowing and timber course")
	await _wait(12)
	var left: Node3D = _boat.model.get_node("OarL")
	var right: Node3D = _boat.model.get_node("OarR")
	var rest_left := left.rotation
	var rest_right := right.rotation
	_check(_boat.seat == _boat.model.get_node("RowingSeat") and left.has_node("OarLVisual/Grip") and right.has_node("OarRVisual/Grip"),
		"uses the authored seat and both existing oar grip markers")
	_check(_hand_error() < 0.008 and _seat_error() < 0.025 and _boat.rowing_state().y < 0.01,
		"seated idle uses actual grips and bench")
	# Keep the contact course separate from the free-water animation sample.
	await _sail(Vector3.BACK, 4.0)
	await _timber_course()
	await _sail(Vector3.BACK, 8.0)
	_point_view(Vector3.BACK)
	_key(KEY_W, true)
	for frame in 400:
		await physics_frame
		if _boat.velocity.z > 2.1 and _boat.rowing_state().y > 0.60:
			break
	var max_grip_error := 0.0
	var max_seat_error := 0.0
	var oar_min := INF
	var oar_max := -INF
	var hand_min := INF
	var hand_max := -INF
	var blade: Node3D = left.get_node("OarLVisual/BladeContact")
	var blade_min := INF
	var blade_max := -INF
	for frame in 90:
		await physics_frame
		max_grip_error = maxf(max_grip_error, _hand_error())
		max_seat_error = maxf(max_seat_error, _seat_error())
		oar_min = minf(oar_min, left.rotation.z)
		oar_max = maxf(oar_max, left.rotation.z)
		var hand_y := _boat.model.to_local(_player.left_elbow.get_node("Hand").global_position).y
		hand_min = minf(hand_min, hand_y)
		hand_max = maxf(hand_max, hand_y)
		var blade_y := _boat.model.to_local(blade.global_position).y
		blade_min = minf(blade_min, blade_y)
		blade_max = maxf(blade_max, blade_y)
		if frame == 15 or frame == 48:
			await _capture("08-rowing-%02d" % frame)
	_key(KEY_W, false)
	_check(_boat.rowing_state().y > 0.4 and oar_max - oar_min > 0.10 and hand_max - hand_min > 0.04,
		"live playback under propulsion: effort=%.3f oar span=%.3f hand span=%.3f" % [_boat.rowing_state().y, oar_max - oar_min, hand_max - hand_min])
	_check(max_grip_error < 0.008 and max_seat_error < 0.025 and blade_max - blade_min > 0.20,
		"live cycle keeps hands on grips and pelvis over bench while blade sweeps; grip=%.4f seat=%.4f blade span=%.3f" % [max_grip_error, max_seat_error, blade_max - blade_min])
	await _wait(160)
	_check(_boat.is_still() and _boat.rowing_state().y < 0.001 and left.rotation.distance_to(rest_left) < 0.002 and right.rotation.distance_to(rest_right) < 0.002
		and _player.animation_state() == "rowing" and _hand_error() < 0.008 and _seat_error() < 0.025,
		"stop blends to the original seated rest pose, with both hands still on resting oars")
	await _capture("09-rowing-stopped")
	await _screen_directions()
	_check(not FileAccess.file_exists("user://save_slot_0.json") and not FileAccess.file_exists("user://water.cfg"), "does not create old save or water preferences")
	_finish()
