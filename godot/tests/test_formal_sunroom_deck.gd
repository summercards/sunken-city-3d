extends SceneTree
## Record same-pose A/B on the actual formal land motor, not a replacement capsule.
const MAIN := "res://scenes/main.tscn"
const FreeWalk = preload("res://src/player/actions/free_walk_action.gd")
const MOVE := {KEY_W: Vector2(0,-1), KEY_S: Vector2(0,1), KEY_A: Vector2(-1,0), KEY_D: Vector2(1,0)}
var checks := 0
var failures := 0
var main
var actor: CharacterBody3D
var zone: Node3D
var surface: Node3D
var ground: Node3D
var deck: Node3D
var wall: StaticBody3D
var floors: Array[StaticBody3D] = []
var boundary: StaticBody3D
var held: Array[Key] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [formal-sunroom-deck] ", label)

func tick(frames := 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func place(feet: Vector3) -> void:
	main.actor_controller.cancel()
	main.actor_controller.walk_area = null
	actor.global_position = feet + Vector3.UP * 0.0003
	actor.set_grounded_motion(true)
	await tick()

func contact(label: String, origin: Vector3, displacement: Vector3) -> Dictionary:
	var hit := KinematicCollision3D.new()
	if not actor.test_move(Transform3D(actor.global_basis, origin), displacement, hit, actor.safe_margin):
		print("[deck-contact] ", label, " from=", origin, " move=", displacement, " none")
		return {}
	var body := hit.get_collider() as CollisionObject3D
	var index := hit.get_collider_shape_index()
	var shape_owner := body.shape_owner_get_owner(body.shape_find_owner(index)) as Node3D
	print("[deck-contact] ", label, " from=", origin, " move=", displacement,
		" body=", body.get_path(), " shape=", shape_owner.get_path(), " index=", index,
		" scene_owner=", shape_owner.owner.get_path() if shape_owner.owner != null else "runtime",
		" domain=", body.get_meta("collision_owner", str(body.get_parent().name)),
		" layer/mask=", body.collision_layer, "/", body.collision_mask,
		" body_xform=", body.global_transform, " shape_xform=", shape_owner.global_transform,
		" hit=", hit.get_position(), " normal=", hit.get_normal(), " travel=", hit.get_travel())
	return {"body":body, "shape":shape_owner, "position":hit.get_position(), "normal":hit.get_normal()}

func set_disabled(kind: String) -> void:
	wall.collision_layer = 0 if kind == "wall" else 256
	wall.collision_mask = 0 if kind == "wall" else 512
	boundary.collision_layer = 0 if kind == "boundary" else 256
	boundary.collision_mask = 0 if kind == "boundary" else 512
	for body in floors:
		body.collision_layer = 0 if kind == "floor" else 256
		body.collision_mask = 0 if kind == "floor" else 512
	await tick()

func matrix(label: String, from: Vector3, to: Vector3) -> void:
	var motion := to - from
	var free := FreeWalk.new()
	var last := from
	var first_reject := Vector3.INF
	for i in range(1, 101):
		var point := from.lerp(to, float(i) / 100.0)
		var area: Node3D = zone.area_at(last, 0.45)
		if area == null or not free._standable_step(area, point, last):
			first_reject = point
			break
		last = point
	print("[deck-query] ", label, " first_WalkArea_reject=", first_reject,
		" start_area=", zone.area_at(from, 0.45), " end_area=", zone.area_at(to, 0.45),
		" water_segment_clear=", main.navigation.segment_clear(Vector2(from.x, from.z), Vector2(to.x, to.z)))
	for kind: String in ["all", "wall", "boundary", "floor"]:
		await set_disabled(kind)
		contact(label + "/" + kind, from + Vector3.UP * 0.0003, motion)
		if kind == "all" or kind == "floor":
			contact(label + "/support-" + kind, from + Vector3.UP * 0.07, Vector3.DOWN * 0.15)
	await set_disabled("all")

# Diagnostic only: read rendered triangles to identify the visible wood and
# wall, never feed them into a PhysicsServer shape or a gameplay query.
func visible_pieces(ray_from: Vector3, ray_to: Vector3, label: String) -> void:
	var pieces: Array = []
	for visual: MultiMeshInstance3D in surface.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh := visual.multimesh.mesh
		for index in visual.multimesh.visible_instance_count if visual.multimesh.visible_instance_count >= 0 else visual.multimesh.instance_count:
			var pose := visual.global_transform * visual.multimesh.get_instance_transform(index)
			var inv := pose.affine_inverse()
			var p := inv * ray_from
			var q := inv * ray_to
			if mesh.get_aabb().grow(0.001).intersects_segment(p, q) == null: continue
			var faces := mesh.get_faces()
			var near := INF
			var at := Vector3.INF
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(p, q, faces[i], faces[i+1], faces[i+2])
				if hit == null: continue
				var world_hit: Vector3 = pose * hit
				var d := world_hit.distance_to(ray_from)
				if d < near:
					near = d
					at = world_hit
			if near < INF:
				pieces.append([near, visual.get_meta("asset_component", visual.name), index, at, pose * mesh.get_aabb()])
	pieces.sort_custom(func(a: Array, b: Array): return a[0] < b[0])
	print("[deck-visual] ", label, " from=", ray_from, " to=", ray_to, " hits=", pieces.slice(0,4))

func set_keys(next: Array[Key]) -> void:
	if held == next: return
	for code in held:
		if not next.has(code): emit_key(code, false)
	for code in next:
		if not held.has(code): emit_key(code, true)
	Input.flush_buffered_events()
	held = next

func emit_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func drive(direction: Vector3, frames: int) -> void:
	# A pair permits actual diagonals with the native four-direction input map.
	var best: Array[Key] = []
	var score := -INF
	for first: Key in MOVE:
		for second: Key in MOVE:
			var axis: Vector2 = MOVE[first] + MOVE[second]
			if axis == Vector2.ZERO: continue
			var d: Vector3 = main._camera_relative(axis)
			if d.dot(direction) <= score: continue
			score = d.dot(direction)
			best.clear()
			best.append(first)
			if first != second: best.append(second)
	set_keys(best)
	for i in frames:
		await tick(1)
		if i % 20 == 19:
			print("[deck-drive] keys=", best, " frame=", i+1, " position=", actor.global_position,
				" held=", Input.get_vector("move_left","move_right","move_forward","move_back"),
				" state=", main.actor_controller.state_id(), " support=", actor.ground_contact)
	set_keys([])
	await tick(7)

func supported(label: String) -> bool:
	# At rest the motor does not continuously poll support; independently sweep
	# the same capsule down at the final position and check the live floor.
	var hit := contact(label, actor.global_position + Vector3.UP * 0.05, Vector3.DOWN * 0.12)
	return floors.has(hit.get("body")) and (hit.get("normal", Vector3.ZERO) as Vector3).y > 0.9

func shot(label: String, point: Vector3) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(main.cam.is_position_in_frustum(point) and not image.is_empty() and image.save_png("res://outputs/sunroom-deck-" + label + ".png") == OK, "in-frame real screenshot " + label)
	await process_frame

func run() -> void:
	var profile := str(ProjectSettings.get_setting("application/run/main_scene"))
	var user_dir := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if profile != MAIN or not user_dir.begins_with("sea-verification/") or DisplayServer.get_name() == "headless":
		check(false, "formal project, isolated user dir, actual renderer")
		finish()
		return
	main = load(MAIN).instantiate()
	root.add_child(main)
	main._autosave_on = false
	await tick(20)
	actor = main.player
	zone = main.get_node("World/Zones/Zone1HomeHarbor")
	surface = zone.get_node("Models/太阳能木屋/太阳能木屋-海上区域")
	wall = surface.get_node("SurfaceCollision")
	ground = zone.ground_space
	deck = zone.landing_point("main").ground()
	for child in ground.get_children():
		if not child is StaticBody3D: continue
		if child.name == &"GroundBoundary": boundary = child
		else: floors.append(child)
	var capsule: CollisionShape3D = actor.get_node("BodyCollision")
	check(capsule.shape is CapsuleShape3D and boundary != null and not floors.is_empty(), "original Explorer and candidate physical owners present")
	main.actor_controller.reconcile_mode(0)
	if actor.get_parent() != main: actor.reparent(main, true)
	var foot: Node3D = surface.find_child("SunroomLadderBottomAnchor", true, false)
	var y := foot.global_position.y
	var start := Vector3(4.05, y, 4.15)
	var end := Vector3(1.2, y, start.z)
	await place(start)
	check(actor.collision_layer == 512 and actor.collision_mask == 256, "original capsule layer and mask")
	print("[deck-profile] source=verbal-reconstruction surface=", surface.global_transform, " ladder=", foot.global_transform,
		" capsule=", capsule.global_transform, " radius=", capsule.shape.radius, " height=", capsule.shape.height)
	main.cam.set_process(false)
	main.cam.position = Vector3(-7.0, 11.0, 13.8)
	main.cam.look_at(Vector3(3.2, 2.8, 3.5), Vector3.UP)
	print("[deck-camera] transform=", main.cam.global_transform, " fov=", main.cam.fov, " viewport=", root.size)
	await shot("01-reconstruction", start)
	for p: Vector2 in [Vector2(1.2, 4.15), Vector2(2.05, 4.15), Vector2(3.3, 4.15), Vector2(3.3, 3.05), Vector2(1.2, 3.05), Vector2(1.2, 2.8), Vector2(0.15, 4.15), Vector2(-0.5, 4.15), Vector2(1.2, 4.75)]:
		visible_pieces(Vector3(p.x, y+0.15, p.y), Vector3(p.x, y-0.3, p.y), "visible-support")
	visible_pieces(Vector3(2.75, y+0.8, 3.7), Vector3(2.24, y+0.8, 1.35), "oblique-wall")
	await matrix("lower-window-left-ladder", start, end)
	await matrix("lower-window-second-lane", Vector3(4.05,y,4.75), Vector3(1.2,y,4.75))
	await matrix("solid-wall-oblique", Vector3(2.75,y,3.7), Vector3(2.24,y,1.95))
	await matrix("ladder-corridor", Vector3(4.4,y,4.75), Vector3(4.4,y,2.82))
	check(not main.input_blocked(), "formal input available")
	await drive(Vector3.LEFT, 72)
	print("[deck-input] lower-window-left-ladder from=", start, " to=", actor.global_position, " support=", actor.ground_contact)
	check(actor.global_position.x < 2.2 and absf(actor.global_position.z-start.z) < 0.3 and supported("crossing-rest-support"), "WASD crosses previous edge along visible deck")
	await shot("02-after-walk", actor.global_position)
	var wall_start := Vector3(2.75,y,3.7)
	await place(wall_start)
	var hit := contact("wall-control", actor.global_position, Vector3(-0.51,0,-1.75))
	check(hit.get("body") == wall and hit.get("shape").name == &"FrontWallLeft", "different path first contacts real wall")
	await drive(Vector3.FORWARD, 57)
	print("[deck-input] solid wall stopped at ", actor.global_position, " support=", actor.ground_contact)
	check(actor.global_position.z < wall_start.z-0.25 and actor.global_position.z >= 2.83 and supported("wall-rest-support"), "keyboard walk stops at wall without losing deck support")
	await shot("03-wall", actor.global_position)
	var ladder_start := Vector3(foot.global_position.x,y,4.78)
	await place(ladder_start)
	await drive(Vector3.FORWARD, 38)
	check(actor.global_position.distance_to(foot.global_position) < 0.7 and actor.ground_contact, "WASD walks through corridor toward lower ladder")
	var economy := root.get_node("Economy")
	economy.inventory.set_count("wood",20)
	economy.inventory.set_count("soil",2)
	economy.inventory.set_count("glass",1)
	check(not economy.sunroom.repair_ladder().is_empty(), "repair uses existing service")
	check(not economy.sunroom.restore_upper().is_empty(), "upper restoration uses existing service")
	await tick()
	var bottom: Node = surface.find_child("SunroomLadderBottom", true, false)
	var top: Node = surface.find_child("SunroomLadderTop", true, false)
	var climb: Dictionary = bottom.interact(actor)
	check(climb.get("event") == "ladder_climb_started", "lower ladder request from corridor succeeds")
	await tick(105)
	check(main.actor_controller.climbing() and actor.global_position.y > y+1.0, "continuous physical ladder presentation at midpoint")
	await shot("04-ladder", actor.global_position)
	await tick(200)
	check(not main.actor_controller.climbing() and actor.global_position.y > y+4.0, "reaches original upper endpoint")
	var down: Dictionary = top.interact(actor)
	check(down.get("event") == "ladder_climb_started", "upper ladder request succeeds")
	await tick(300)
	check(not main.actor_controller.climbing() and absf(actor.global_position.y-y) < 0.12, "returns to original lower landing")
	var ledge := contact("outer-deck-edge", Vector3(-0.4,y+0.0003,4.15), Vector3.LEFT*1.25)
	check(ledge.get("body") == zone.ground_space.get_node("GroundBoundary"), "actual water-side edge still blocks capsule")
	finish()

func finish() -> void:
	set_keys([])
	print("[formal-sunroom-deck] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
