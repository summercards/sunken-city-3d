extends SceneTree
## 真实鼠标点击探针：走 main._unhandled_input() 这条玩家实际使用的链路，
## 不直接调用 _try_walk / clamp_point，避免"函数对但链路上被别的分支截走"。
##
##   godot --path godot --script res://tools/probe_real_click.gd

var main


func _init() -> void:
	_run.call_deferred()


func settle(n := 6) -> void:
	for i in n:
		await process_frame


func click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.pressed = pressed
		main._unhandled_input(e)
		await settle(2)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	await settle(30)

	var area: Node3D = null
	for a in main._zone_nodes.zone1.walk_areas:
		if str(a.area_id) == "zone1_home_dock":
			area = a

	print("[realclick] 运行中 body_radius=%.2f  rects=%s" % [area.body_radius, str(area.rects)])
	print("[realclick] 场景文件路径=%s" % area.scene_file_path)

	main.cam.orbit_dir = Vector3(0.34, 0.80, 0.50)
	main.cam.target = Vector3(3.2, area.surface_y + 0.4, 14.6)
	main.cam.distance = 5.2
	main.cam.refresh()
	await settle(6)

	# 屏幕上「栈桥东侧水面」与「甲板边」两个点，走真实点击
	var cases := [
		["甲板内 x=5.2", Vector3(5.2, area.surface_y, 14.2)],
		["甲板边 x=5.8", Vector3(5.8, area.surface_y, 14.2)],
		["水里 x=6.4", Vector3(6.4, area.surface_y, 14.2)],
		["水里 x=7.0", Vector3(7.0, area.surface_y, 14.2)],
	]
	for c in cases:
		var at: Vector2 = main.cam.unproject_position(c[1])
		main.actor_controller.restore_pose({"mode": 0, "player": [3.0, area.surface_y, 14.6]})
		await settle(2)
		await click(at)
		for i in 330:
			main.actor_controller.tick(1.0 / 60.0)
		await settle(2)
		var got: Vector3 = main.player.global_position
		var local: Vector3 = area.to_local(Vector3(got.x, 0, got.z))
		var on_deck: bool = area.contains_world(got.x, got.z)
		var free: float = area.clearance(local.x, local.z)
		print("[realclick] %s (屏幕 %s) → 站位=(%.2f,%.2f) 在矩形内=%s 净空=%.2f" % [
			c[0], str(at.round()), got.x, got.z, str(on_deck), free])
	quit(0)
