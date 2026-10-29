extends SceneTree
## 取证：站在码头栈桥上，往主人圈的左右两条边走过去，看角色停在哪。
## 期望：停在甲板内，不会走到水面上。

var main


func _init() -> void:
	_run.call_deferred()


func settle(n := 8) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await settle(12)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/walkedge-walk-" + name + ".png")
	print("[shot] ", name, " player=", main.player.global_position)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.cam.suspend_follow()
	root.get_node("Economy").ticking = false
	root.get_node("GameState").enter_zone("zone1")
	await settle(30)

	var zone: Node3D = main._node_zone("zone1") if main.has_method("_node_zone") else main._zone_nodes.zone1
	var area: Node3D = null
	for a in zone.walk_areas:
		if str(a.area_id) == "zone1_home_dock":
			area = a
			break

	main.actor_controller.restore_pose({"mode": 0, "player": [3.0, 1.38, 15.0]})
	await settle(10)

	# 主人圈的两处：栈桥左缘外、右缘外。点过去应该被夹回甲板内。
	for probe in [["left", Vector3(0.10, 1.38, 14.5)], ["right", Vector3(6.40, 1.38, 14.5)]]:
		var want: Vector3 = probe[1]
		var clamped: Vector2 = area.clamp_point(want.x, want.z)
		print("[probe] ", probe[0], " want=", want, " clamped=", clamped,
			" inside=", area.contains_world(want.x, want.z))
		main.actor_controller.start_walk(area, Vector3(clamped.x, area.surface_y, clamped.y))
		for i in 180:
			main.actor_controller.tick(1.0 / 60.0)
		await settle(4)
		print("[probe] ", probe[0], " final=", main.player.global_position,
			" on_deck=", area.contains_world(main.player.global_position.x, main.player.global_position.z))

	main.cam.orbit_dir = Vector3(-0.74, 0.42, 0.52)
	main.cam.target = Vector3(2.6, 1.5, 15.0)
	main.cam.distance = 8.5
	main.cam.refresh()
	await shot("edge")
	quit(0)
