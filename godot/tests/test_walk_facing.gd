extends SceneTree
## 用真实角色和控制器核对八方向；真实渲染时另拍平台上的往返行走。
var checks := 0
var failures := 0
var main: Node

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func forward() -> Vector3:
	var direction: Vector3 = main.player.head_pivot.global_basis.z
	direction.y = 0.0
	return direction.normalized()

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# Freeze the two production drivers, not CollisionObject3D participation:
	# PROCESS_MODE_DISABLED would remove the character from the physics world.
	main.set_process(false)
	main.set_physics_process(false)
	main.player.set_process(false)
	if main.actor_controller.actor == null:
		printerr("FAIL actor controller did not initialize")
		main.queue_free()
		await process_frame
		quit(1)
		return
	# 独立合法地面避免用正式场景的箱子布局限制八方向样本。
	var area = preload("res://src/navigation/walk_area.gd").new()
	area.rects = [Rect2(-5, -5, 10, 10)]
	area.surface_y = 10.0
	main.add_child(area)
	var fixture_space = preload("res://src/navigation/ground_space.gd").new()
	main.add_child(fixture_space)
	fixture_space.configure([area])
	# This fixture used to need only a declared rectangle. The formal motor now
	# requires real support, while every speed/facing assertion stays unchanged.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 256
	floor_body.collision_mask = 512
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10.0, 0.2, 10.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	main.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, 9.9, 0.0)
	for i in 3:
		await physics_frame
		await process_frame
	for fps in [30, 60, 120]:
		for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD,
				Vector3(1,0,1).normalized(), Vector3(1,0,-1).normalized(),
				Vector3(-1,0,1).normalized(), Vector3(-1,0,-1).normalized()]:
			main.actor_controller.restore_pose({"mode":0,"player":[0,10,0]})
			main.player.rotation = Vector3.ZERO
			var start: Vector3 = main.player.global_position
			check(main.actor_controller.start_walk(area, start + direction * 3.0), "start %s %d FPS" % [direction,fps])
			main.player._process(0.0)
			for i in fps / 2: main.actor_controller.tick(1.0 / fps)
			var movement: Vector3 = main.player.global_position - start
			check(movement.normalized().dot(forward()) > 0.9999, "face follows displacement %s %d FPS moved=%s facing=%s" % [direction,fps,movement,forward()])
			check(absf(movement.length() - 1.15) < 0.001, "walk speed preserved")
			for i in fps: main.actor_controller.tick(1.0 / fps)
			check(not main.actor_controller.walking() and main.player.global_position.distance_to(start + direction * 3.0) < 0.001, "arrive and stop")
	# 正式平台上的反向改道也应平滑转身；取消后不再改朝向。
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[20.5,1.48,16]})
	var ground: Node3D = main._zone_nodes.zone5.landing_point("main").ground()
	check(main.actor_controller.start_walk(ground, Vector3(23.5,1.48,16)), "platform outward")
	main.player._process(0.0)
	for i in 30: main.actor_controller.tick(1.0/60)
	check(forward().dot(Vector3.RIGHT) > 0.9999, "platform faces outward")
	if DisplayServer.get_name() != "headless": await capture("outward")
	check(main.actor_controller.start_walk(ground, Vector3(19.8,1.48,16)), "platform reverse")
	main.player._process(0.0)
	var previous: Vector3 = forward()
	main.actor_controller.tick(1.0/60)
	check(previous.dot(forward()) > 0.8, "reverse turns smoothly")
	for i in 30: main.actor_controller.tick(1.0/60)
	check(forward().dot(Vector3.LEFT) > 0.9999, "platform faces return direction")
	if DisplayServer.get_name() != "headless": await capture("return")
	main.actor_controller.cancel()
	var stopped: Vector3 = main.player.rotation
	for i in 30: main.actor_controller.tick(1.0/60)
	check(main.player.rotation.is_equal_approx(stopped), "cancel keeps stopped facing")
	area.queue_free()
	main.queue_free()
	await process_frame
	print("[walk-facing] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func capture(label: String) -> void:
	main.player._process(0.12)
	main.cam.global_position = main.player.global_position + Vector3(-3.5,3.6,5.0)
	main.cam.look_at(main.player.global_position + Vector3.UP * 0.5)
	main.cam.fov = 35.0
	for i in 8: await process_frame
	var point: Vector2 = main.cam.unproject_position(main.player.global_position + Vector3.UP * 0.6)
	var viewport: Vector2 = root.get_visible_rect().size
	check(Rect2(viewport * 0.05, viewport * 0.9).has_point(point), "character in frame")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/walk-facing-" + label + ".png") == OK, "save " + label)
