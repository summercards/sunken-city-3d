extends SceneTree
## SEA-MOVE: physical sweeps, supported slopes and the production physics clock.
## Fixtures are isolated physics primitives, never new playable rooms or content.
const CharacterScript = preload("res://src/player/character.gd")
const WalkAreaScript = preload("res://src/navigation/walk_area.gd")
const GroundSpaceScript = preload("res://src/navigation/ground_space.gd")
const GROUND_LAYER := 256
const ACTOR_LAYER := 512
var checks := 0
var failures := 0
var fixture: Node3D
var main: Node

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func box(parent: Node3D, center: Vector3, size: Vector3, angle := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = GROUND_LAYER
	body.collision_mask = ACTOR_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = center
	body.rotation.z = angle
	return body

func physics_sync() -> void:
	for i in 3:
		await physics_frame
		await process_frame

func ground_at(point: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point - Vector3.UP * 3.0, GROUND_LAYER)
	return root.get_world_3d().direct_space_state.intersect_ray(ray)

func run() -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0.0, -0.1, 0.0), Vector3(20.0, 0.2, 12.0))
	box(fixture, Vector3(2.0, 1.0, 0.0), Vector3(0.2, 2.0, 8.0))
	var actor: Node3D = CharacterScript.new()
	fixture.add_child(actor)
	actor.set_process(false)
	check(actor is CharacterBody3D, "formal character uses CharacterBody3D")
	check(actor.has_method("move_ground") and actor.has_method("set_grounded_motion"), "public motor commands exist")
	if not actor.has_method("move_ground"):
		fixture.queue_free()
		await process_frame
		finish()
		return
	actor.set_grounded_motion(true)
	await physics_sync()
	var shapes := actor.find_children("*", "CollisionShape3D", true, false)
	check(shapes.size() == 1, "one actor collision shape, no duplicate legacy proxy")
	if shapes.size() == 1:
		check(shapes[0].shape is CapsuleShape3D, "actor uses a capsule")
		if shapes[0].shape is CapsuleShape3D:
			check(absf(shapes[0].shape.radius - 0.22) < 0.0001, "physical radius preserves construction width")
			check(absf(shapes[0].shape.height - 1.30) < 0.0001, "physical height contract")
	check(actor.grounded_motion_enabled, "ground motion can be enabled")
	check(actor.collision_layer == ACTOR_LAYER and actor.collision_mask == GROUND_LAYER, "actor collisions are isolated from boat and water")
	var start: Vector3 = actor.global_position
	var free: Dictionary = actor.move_ground(Vector3(0.46, 0.0, 0.0), 0.2)
	check(absf(actor.global_position.x - start.x - 0.46) < 0.001, "free movement keeps requested horizontal distance")
	check(free.has("moved") and free.has("blocked") and free.has("grounded"), "motor returns motion, obstruction and support")
	check(not free.get("blocked", true), "flat floor contact is not a wall obstruction")
	# The wall is deliberately absent from every WalkArea: only a physical
	# shape sweep can reject this eight metre request and prevent tunnelling.
	var hit: Dictionary = actor.move_ground(Vector3(8.0, 0.0, 0.0), 0.2)
	check(hit.get("blocked", false), "physical wall blocks a long displacement")
	check(actor.global_position.x <= 1.69 and actor.global_position.x > 1.5, "capsule stops on the near side of the wall")
	var stopped: Vector3 = actor.global_position
	for i in 12:
		actor.move_ground(Vector3(0.1, 0.0, 0.0), 1.0 / 60.0)
	check(actor.global_position.x <= 1.69, "repeated input never leaks through the wall")
	check(absf(actor.global_position.y - start.y) < 0.02, "ground support preserves the authored foot height")
	# A component can explicitly opt out of blocking without changing its mesh
	# or the character. The proxy is independent of farm and crop state.
	var optional = preload("res://src/navigation/actor_collision_body.gd").new()
	var optional_shape := CollisionShape3D.new()
	var optional_box := BoxShape3D.new(); optional_box.size=Vector3(0.2,2,3)
	optional_shape.shape=optional_box;optional.add_child(optional_shape)
	fixture.add_child(optional);optional.position=Vector3(-3,1,0)
	actor.global_position=Vector3(-4,0,0);actor.set_grounded_motion(true)
	await physics_sync()
	check(actor.move_ground(Vector3(2,0,0),0.2).blocked,"explicit solid component proxy blocks actor")
	optional.blocks_actor=false;actor.global_position=Vector3(-4,0,0)
	await physics_sync()
	check(not actor.move_ground(Vector3(2,0,0),0.2).blocked and actor.global_position.x>-2.01,"component proxy can become pass-through without removing its content")
	optional.queue_free()
	actor.set_grounded_motion(false)
	check(not actor.grounded_motion_enabled and actor.collision_layer == 0 and actor.collision_mask == 0, "disabled ground motion removes collision participation")
	stopped = actor.global_position
	await physics_sync()
	check(actor.global_position.is_equal_approx(stopped), "disabled motor does not fall or drift")
	# A real sloped collider exercises three-dimensional height following.
	box(fixture, Vector3(30.0, 1.15, 0.0), Vector3(6.0, 0.2, 4.0), atan(1.0 / 3.0))
	await physics_sync()
	var support := ground_at(Vector3(27.5, 1.0, 0.0))
	check(not support.is_empty(), "slope fixture has physical support")
	if not support.is_empty():
		actor.global_position = support.position + Vector3.UP * 0.02
		actor.set_grounded_motion(true)
		var lower: Vector3 = actor.global_position
		for i in 60:
			actor.move_ground(Vector3(0.05, 0.05 / 3.0, 0.0), 1.0 / 60.0)
			if i % 10 == 0:
				var floor_hit := ground_at(actor.global_position)
				check(not floor_hit.is_empty() and absf(actor.global_position.y - floor_hit.position.y) < 0.09, "uphill stays on slope sample %d" % i)
		check(actor.global_position.x - lower.x > 2.85, "slope is traversable rather than treated as a wall")
		check(actor.global_position.y - lower.y > 0.90, "uphill changes real world height")
		var upper: Vector3 = actor.global_position
		for i in 40:
			actor.move_ground(Vector3(-0.05, -0.05 / 3.0, 0.0), 1.0 / 60.0)
		check(upper.y - actor.global_position.y > 0.58, "downhill follows the lower support")
		var lower_hit := ground_at(actor.global_position)
		check(not lower_hit.is_empty() and absf(actor.global_position.y - lower_hit.position.y) < 0.09, "downhill ends attached to the slope")
	fixture.queue_free()
	await process_frame
	await physics_sync()
	await production_checks()
	finish()

func production_checks() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	if not main.has_method("capture_world_state"):
		check(false, "formal Main compiles before production physics checks")
		main.free()
		return
	root.add_child(main)
	main._autosave_on = false
	if main.get("player") == null or main.get("sleep_cycle") == null:
		check(false, "formal Main initializes character and session services")
		main.queue_free()
		await process_frame
		return
	for i in 8:
		await process_frame
	# Existing board/diving/restore commands must own participation switches.
	main.actor_controller.restore_pose({"mode": 1, "player": []})
	check(main.player.get_parent() == main.boat, "boat restore preserves parenting")
	check(not main.player.grounded_motion_enabled and main.player.collision_mask == 0, "boat restore disables ground collisions")
	var zone: Node3D = main._zone_nodes.zone1
	var landing: Node3D = zone.landing_point("main")
	var stand: Vector3 = landing.stand_position()
	main.actor_controller.restore_pose({"mode": 0, "player": [stand.x, stand.y, stand.z]})
	check(main.player.grounded_motion_enabled and main.player.collision_mask == GROUND_LAYER, "ashore restore re-enables the motor")
	check(main.actor_controller.request_mode(3), "existing diving transition remains accepted")
	check(not main.player.grounded_motion_enabled and main.player.collision_mask == 0, "diving does not collide against land proxies")
	main.actor_controller.restore_pose({"mode": 1, "player": []})
	check(not main.player.grounded_motion_enabled, "restoring from dive to boat keeps land motion disabled")
	# A remote flat surface avoids existing planter/box layouts. It is a physics
	# fixture only; the production Main and controller still drive the movement.
	var area: Node3D = WalkAreaScript.new()
	area.position = Vector3(1000.0, 0.0, 1000.0)
	area.rects = [Rect2(-5.0, -5.0, 10.0, 10.0)]
	area.surface_y = 12.0
	main.add_child(area)
	var fixture_space: Node3D = GroundSpaceScript.new()
	main.add_child(fixture_space)
	fixture_space.configure([area])
	box(main, Vector3(1000.0, 11.9, 1000.0), Vector3(10.0, 0.2, 10.0))
	await physics_sync()
	main.actor_controller.restore_pose({"mode": 0, "player": [1000.0, 12.0, 1000.0]})
	var origin: Vector3 = main.player.global_position
	check(main.actor_controller.start_walk(area, origin + Vector3.RIGHT * 3.0), "production route starts")
	var first_frame := Engine.get_physics_frames()
	for i in 30:
		await physics_frame
	var frames := Engine.get_physics_frames() - first_frame
	var expected := 2.3 * float(frames) / float(Engine.physics_ticks_per_second)
	var distance := Vector2(main.player.global_position.x - origin.x, main.player.global_position.z - origin.z).length()
	check(absf(distance - expected) < 0.06, "production has one motion owner: %.3fm over %d physics frames, expected %.3f" % [distance, frames, expected])
	check(main.actor_controller.walking(), "half second motion has not prematurely consumed the route")
	main.actor_controller.cancel()
	var cancelled: Vector3 = main.player.global_position
	for i in 12:
		await physics_frame
	check(main.player.global_position.distance_to(cancelled) < 0.01, "cancel clears physical movement on subsequent production frames")
	check(main.actor_controller.walk_path.is_empty(), "cancel clears the pending route")
	main.actor_controller.board_player()
	check(main.player.get_parent() == main.boat and not main.player.grounded_motion_enabled, "boarding disables land collision before attachment")
	main.queue_free()
	await process_frame
	await physics_sync()

func finish() -> void:
	print("[character-motor] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
