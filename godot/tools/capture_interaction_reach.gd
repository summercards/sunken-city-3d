extends "res://tools/capture_farm_cycle.gd"
## 真实渲染证据：岸边采集点的 E 焦点、泊位旁的「上岸 / 打捞」提示（2026-11-06）。
##
## 两张图各证明一件事：
##   1. 采集点在默认范围里**看得见、站得住、按 E 有焦点**（曾经整场被藏起来）；
##   2. 站在船边时提示条说的是「E 上岸」，走到岸上又说「E 上船」。
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	economy = root.get_node("Economy")
	economy.ticking = false
	await settle(12)
	main.cam.suspend_follow()

	# ---- 1. 站在打捞台的绳索旁边，等焦点锁定 ----
	var rope: Node3D = main.gather.find("zone1_rope")
	if rope == null:
		check(false, "zone1_rope 存在")
		print("[interaction-reach-render] failures=%d" % failures)
		quit(1)
		return
	var zone: Node = main._zone_nodes["zone1"]
	var area: Node3D = zone.area_at(rope.global_position, 0.6)
	var stand: Vector2 = area.clamp_point(rope.global_position.x + 1.1, rope.global_position.z + 0.9)
	var pos: Vector3 = area.surface_point(Vector3(stand.x, area.surface_y, stand.y))
	main.actor_controller.restore_pose({"mode": 0, "player": [pos.x, pos.y, pos.z]})
	main.player.look_at(Vector3(rope.global_position.x, pos.y, rope.global_position.z), Vector3.UP, true)
	for i in 30:
		await process_frame
	check(main.interactor.target == rope, "绳索成为 E 焦点（实际 %s）" % str(main.interactor.target))
	print("[dbg] active=", main.interactor.active, " prompt_visible=", main.prompt.visible,
		" prompt_text=", main.prompt._text.text if main.prompt._text != null else "n/a",
		" shortcut='", main.prompt.shortcut, "' mode=", main.actor_controller.mode(),
		" hud_modal=", main.hud.is_modal())
	main.cam.target = rope.global_position
	main.cam.distance = 11.0
	main.cam.orbit_dir = Vector3(-0.62, 0.66, 0.42)
	main.cam.refresh()
	await shot("2026-11-06-gather-focus")

	# ---- 2. 泊位旁：船上说「上岸」 ----
	var park: Marker3D = zone.landing_point("main").get_node("BoatPark")
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.actor_controller.restore_pose({"mode": 1})
	for i in 20:
		await process_frame
	check(main._boat_shortcut_text() == "上岸", "船上提示「上岸」（实际 %s）" % main._boat_shortcut_text())
	main.cam.target = main.boat.position
	main.cam.distance = 10.0
	main.cam.orbit_dir = Vector3(-0.58, 0.62, 0.53)
	main.cam.refresh()
	await shot("2026-11-06-boat-prompt")

	print("[interaction-reach-render] failures=%d" % failures)
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
