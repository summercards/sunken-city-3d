extends SceneTree
## 临时取证：把「点远处虚影 → 走过去 → 开工」的三个时刻各截一张。

var main
var failures := 0


func _init() -> void:
	call_deferred("run")


func settle(n := 8) -> void:
	for i in n: await process_frame


func shot(name: String) -> void:
	await settle(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/approach-" + name + ".png")
	print("[shot] ", name, " player=", main.player.global_position, " built=", main.building.query().size(),
		" pending=", not main.building_controller.pending.is_empty())


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.interactor.set_process(false)
	var econ = root.get_node("Economy")
	econ.set_process(false)
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode": 0, "player": [20.5, 1.48, 16.0]})
	root.get_node("GameState").enter_zone("zone5")
	econ.inventory.set_count("wood", 30)
	econ.inventory.set_count("soil", 6)
	# 从远处看整块平台，能同时看到人与目标格。
	main.cam.global_position = Vector3(14.5, 14.0, 24.0)
	main.cam.look_at(Vector3(23.0, 1.4, 16.0))
	main.cam.fov = 42
	await settle(20)
	var controller = main.building_controller
	controller.open()
	controller.select_recipe("deck")
	await settle(4)
	await shot("1-ghosts")
	var candidate := {}
	for c in main.building.candidates():
		if c.x == 3 and c.z == 0 and main.building.can_place(c) == "":
			candidate = c
	# 模拟真实点击：直接用屏幕坐标推，确保走的是 handle_input 那条路。
	var target: Vector3 = main.building_world.position_for(candidate)
	var screen: Vector2 = main.cam.unproject_position(target)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle(3)
	await shot("2-queued")
	# 推进角色与控制器，走到一半再截一张。
	for i in 45:
		main.actor_controller.tick(1.0 / 60.0)
		controller.tick(1.0 / 60.0)
	await shot("3-walking")
	for i in 900:
		main.actor_controller.tick(1.0 / 60.0)
		controller.tick(1.0 / 60.0)
		if main.building.query().size() > 0: break
	await shot("4-started")
	for i in 240:
		main.actor_controller.tick(1.0 / 60.0)
		controller.tick(1.0 / 60.0)
	await shot("5-done")
	print("[shot] done built=", main.building.query().size())
	quit()
