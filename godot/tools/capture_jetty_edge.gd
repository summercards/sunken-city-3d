extends SceneTree
## 取证：点栈桥东缘，角色最终站在哪 —— 复刻主人报问题时的机位与朝向。
##
## 主人的图是「人贴着栈桥东边、帽檐和脚已经在水面上」。
## 这张图用来对照：同样的点击、同样的角度，角色应当整个落在甲板内侧。
##
##   godot --path godot --script res://tools/capture_jetty_edge.gd

var main


func _init() -> void:
	_run.call_deferred()


func settle(n := 8) -> void:
	for i in n:
		await process_frame


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
	if area == null:
		print("[jetty-shot] 找不到 zone1_home_dock")
		quit(1)
		return

	var want := Vector2(6.60, 14.20)
	var stand: Vector2 = area.clamp_point(want.x, want.y)
	main.actor_controller.restore_pose({"mode": 0, "player": [3.0, area.surface_y, 14.6]})
	await settle(2)
	main.actor_controller.start_walk(area, Vector3(stand.x, area.surface_y, stand.y))
	for i in 300:
		main.actor_controller.tick(1.0 / 60.0)
	await settle(10)

	var p: Vector3 = main.player.global_position
	var local: Vector3 = area.to_local(Vector3(p.x, 0, p.z))
	print("[jetty-shot] 点 (%.2f,%.2f) → 站位 (%.2f,%.2f) 净空 %.2f 身影半径 %.2f" % [
		want.x, want.y, p.x, p.z, area.clearance(local.x, local.z), area.body_radius])

	main.cam.orbit_dir = Vector3(0.34, 0.80, 0.50)
	main.cam.target = Vector3(p.x - 0.4, area.surface_y + 0.4, p.z)
	main.cam.distance = 5.2
	main.cam.refresh()
	await settle(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/jetty-edge.png")
	print("[jetty-shot] saved")
	quit(0)
