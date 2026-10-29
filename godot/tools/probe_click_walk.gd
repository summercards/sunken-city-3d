extends SceneTree
## 端到端探针：把相机摆在主人的视角，算出屏幕上「栈桥东侧水里」那一点的
## 屏幕坐标，然后走真正的点击链路（_try_walk → pick_walk → clamp_point → 状态机），
## 看角色最后停在哪、身影离甲板边多远。
##
## 这条链路和玩家鼠标点击完全一致，不直接调用 clamp_point，避免「函数对但没接上」。
##
##   godot --path godot --script res://tools/probe_click_walk.gd

var main


func _init() -> void:
	_run.call_deferred()


func settle(n := 6) -> void:
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

	# 主人的机位：从东南上方俯看栈桥
	main.cam.orbit_dir = Vector3(0.34, 0.80, 0.50)
	main.cam.target = Vector3(3.2, area.surface_y + 0.4, 14.6)
	main.cam.distance = 5.2
	main.cam.refresh()
	await settle(6)

	print("[clickwalk] body_radius=%.2f  surface_y=%.2f" % [area.body_radius, area.surface_y])

	# 目标点：栈桥东缘外侧（水面），x 依次往外
	for want in [5.4, 5.9, 6.2, 6.6]:
		var world := Vector3(want, area.surface_y, 14.2)
		var screen: Vector2 = main.cam.unproject_position(world)
		main.actor_controller.restore_pose({"mode": 0, "player": [3.0, area.surface_y, 14.6]})
		await settle(2)
		var hit: Dictionary = main.pick_walk_at(screen)
		var accepted: bool = main._try_walk(screen)
		for i in 360:
			main.actor_controller.tick(1.0 / 60.0)
		await settle(2)
		var got: Vector3 = main.player.global_position
		var local: Vector3 = area.to_local(Vector3(got.x, 0, got.z))
		var free: float = area.clearance(local.x, local.z)
		print("[clickwalk] 点世界 x=%.2f (屏幕 %s) → pick=%s 接受=%s 站位=(%.2f,%.2f) 净空=%.2f" % [
			want, str(screen.round()), str(hit.get("point", "无")), str(accepted),
			got.x, got.z, free])
	quit(0)
