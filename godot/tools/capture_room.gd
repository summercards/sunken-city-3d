extends SceneTree
## SEA-ROOM 真实渲染证据：门口、室内全景、床铺近景、前厅、夜景与剖切换面。
## 只抓图，不改玩法。跑法：python3 scripts/run_verification.py visual-room

var main: Node
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func shot(label: String, target: Vector3, distance: float, orbit: Vector3) -> void:
	main.cam.target = target
	main.cam.distance = distance
	main.cam.orbit_dir = orbit
	main.cam.refresh()
	main.cam.apply_pose()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null, "frame " + label)
	if image != null:
		check(image.save_png("res://outputs/room-" + label + ".png") == OK, "saved " + label)
		print("[room-shot] ", label, " ", image.get_size())


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	await process_frame
	main.set_process(false)

	var room: Node3D = main.room
	var door: Node3D = main._zone_nodes.zone1.get_node("Objects/RoomDoor")

	# ⓪ 室外全景：确认房间没有反过来破坏屋顶外观（它在屋面上方，从甲板看得出体积）。
	await shot("outside", Vector3(2.5, 10.5, 1.0), 30.0, Vector3(-0.55, 0.42, 0.72))

	# ① 门口：太阳房入口原来是睡觉点，现在挂着「房间」的牌子。
	await shot("door", door.global_position + Vector3(0, 1.1, 0), 9.0, Vector3(0.55, 0.42, 0.72))

	# ② 进屋（瞬时路径，只为了取景），用正式机位拍室内全景。
	main.room_controller.enter(true)
	await process_frame
	main.hud.hide()
	var pose: Dictionary = room.camera_pose()
	await shot("inside", pose.target, pose.distance, pose.dir)

	# ③ 床铺近景：右边是窗，左边是床头柜与台灯。
	var bed: Node3D = room.get_node("Furnishings/Bed")
	await shot("bed", bed.global_position + Vector3(0.5, 0.7, 0.3), 4.6, Vector3(0.45, 0.55, 0.70))

	# ④ 前厅：站在屋里朝外看 —— 门洞后面就是那间玻璃厅，再外面是海。
	# 机位放在房间内侧（z<0），所以前墙与门框仍然可见，玻璃厅整间露出来。
	await shot("porch", room.to_global(Vector3(0.0, 1.15, 2.05)), 6.4, Vector3(-0.10, 0.22, -0.97))

	# ⑤ 从另一侧看：藏起来的墙换成后墙（证明剖切跟着镜头，而不是写死一面墙）。
	await shot("cutaway-north", room.global_position + Vector3(0.0, 1.2, -1.0), 9.6,
		Vector3(0.12, 0.58, -0.80))

	# ⑥ 夜里：台灯与补光在 home_lamps 组里跟着日照曲线亮起来。
	main.world_clock.from_dict({"day": 1, "seconds": 21.0 * 3600.0, "day_length": 1200.0})
	main.daylight_rig.apply(21.0)
	await shot("night", pose.target, pose.distance, pose.dir)

	print("[room-render] ", failures, " failures")
	quit(0 if failures == 0 else 1)
