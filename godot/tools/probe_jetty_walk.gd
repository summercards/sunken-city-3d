extends SceneTree
## 取证 + 量化：点栈桥各条边的外侧，角色最终站在哪、身影离甲板边多远。
##
## 甲板边界来自 tools/probe_deck_cover.gd 的实测（球检测，抗木板缝）：
##   栈桥 z 13.4…17.9 → x 0.35…5.90（东缘、西缘）
##   栈桥根部 z 11.8…12.4 → x 0.20…5.75
## 角色轮廓半径 0.54（帽檐，tools/probe_player_radius.gd 实测）。
##
##   godot --path godot --script res://tools/probe_jetty_walk.gd

var main


func _init() -> void:
	_run.call_deferred()


func settle(n := 8) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await settle(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/jetty-" + name + ".png")
	print("[shot] ", name)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	await settle(30)

	var zone: Node3D = main._zone_nodes.zone1
	var area: Node3D = null
	for a in zone.walk_areas:
		if str(a.area_id) == "zone1_home_dock":
			area = a
			break

	print("[jetty] body_radius=", area.body_radius)
	# [标签, 想去的 x, 想去的 z, 该处甲板东/西边界的保守值]
	var cases := [
		["东缘 z=14.2", 6.60, 14.20, 5.90, false],
		["东缘 z=16.0", 6.60, 16.00, 6.20, false],
		["西缘 z=14.2", 0.00, 14.20, 0.35, true],
		["西缘 z=16.0", -0.30, 16.00, -0.10, true],
		["末端 z=18.2", 3.00, 18.20, 17.95, false],
		["根部东缘 z=12.2", 6.60, 12.20, 5.75, false],
	]

	for c in cases:
		var want := Vector2(float(c[1]), float(c[2]))
		var clamped: Vector2 = area.clamp_point(want.x, want.y)
		main.actor_controller.restore_pose({"mode": 0, "player": [3.0, area.surface_y, 14.6]})
		await settle(2)
		main.actor_controller.start_walk(area, Vector3(clamped.x, area.surface_y, clamped.y))
		for i in 240:
			main.actor_controller.tick(1.0 / 60.0)
		await settle(2)
		var got: Vector3 = main.player.global_position
		var local: Vector3 = area.to_local(Vector3(got.x, 0, got.z))
		var free: float = area.clearance(local.x, local.z)
		var edge := float(c[3])
		var west: bool = bool(c[4])
		var margin: float
		if str(c[0]).begins_with("末端"):
			margin = edge - (got.z + area.body_radius)
		else:
			margin = (got.x - area.body_radius - edge) if west else (edge - (got.x + area.body_radius))
		print("[jetty] %-14s want=(%.2f,%.2f) → 站位=(%.2f,%.2f) 身影余量=%.2f 净空=%.2f" % [
			c[0], want.x, want.y, got.x, got.z, margin, free])
		if free + 0.001 < area.body_radius:
			print("[jetty]   注意：此处净空不足人影半径（走廊比人窄）")

	main.actor_controller.restore_pose({"mode": 0, "player": [5.25, area.surface_y, 14.4]})
	await settle(6)
	main.cam.orbit_dir = Vector3(-0.74, 0.42, 0.52)
	main.cam.target = Vector3(3.2, 1.5, 15.0)
	main.cam.distance = 8.0
	main.cam.refresh()
	if DisplayServer.get_name() != "headless":
		await shot("east-edge")
	quit(0)
