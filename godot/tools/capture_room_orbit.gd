extends SceneTree
## 室内环绕机位的实拍验收：把镜头绕房间转一圈、拉近拉远，逐张落盘。
## 用途是「眼睛看得见」的验收 —— 断言只能证明数值变了，证明不了画面没坏。
var main: Node


func _init() -> void:
	call_deferred("run")


func shot(label: String, yaw_deg: float, pitch_deg: float, distance: float) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	main.cam.orbit_only = true
	main.cam.distance = distance
	main.cam.orbit_dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	main.cam.refresh()
	main.cam.apply_pose()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/room-orbit-" + label + ".png")
	print("[room-orbit] ", label, " yaw=", yaw_deg, " pitch=", pitch_deg, " d=", distance)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").set_process(false)
	main.cam.suspend_follow()
	await process_frame
	main.room_controller.enter(true)
	await process_frame
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	# 拆除（锤子）钮不挂在 hud 下，`hud.hide()` 管不到它；它的可见性由
	# `launcher_visibility_query` 每帧算，而那个 query 里有一条 `hud.is_modal()` ——
	# 截图工具把 hud 整个藏了，这条判据就失真。这里显式关掉，
	# 让截图反映的是「玩家在屋里看到的画面」（游戏里它是被 query 收掉的）。
	if main.building_controller != null and main.building_controller.demolition != null:
		main.building_controller.demolition.launcher.hide()
	# 默认距离与俯角从房间自己的 `camera_pose()` 取，不在这里另写一份 ——
	# 否则调了正式机位，验收图还停在旧数值上，等于没验。
	var pose: Dictionary = main.room.camera_pose()
	var dist: float = float(pose.distance)
	# 方位角也从 `pose.dir` 反解，不能写死 —— 写死 41° 时房间会被推偏到画面一侧，
	# 而那只是取景工具有 bug，不是构图问题。
	var dir: Vector3 = Vector3(pose.dir).normalized()
	var base_yaw := rad_to_deg(atan2(dir.x, dir.z))
	var base_pitch := rad_to_deg(asin(dir.y))
	# 默认（+Z 一侧）→ 右侧 90° → 背面 180° → 左侧 270°。
	await shot("front", base_yaw, base_pitch, dist)
	await shot("east", base_yaw + 90.0, base_pitch, dist)
	await shot("back", base_yaw + 180.0, base_pitch, dist)
	await shot("west", base_yaw + 270.0, base_pitch, dist)
	# 两头：最近的构图与最远的构图，确认不会切进家具 / 缩成一个点。
	await shot("near", base_yaw, base_pitch, main.cam.orbit_zoom_min)
	await shot("far", base_yaw, base_pitch, main.cam.orbit_zoom_max)
	# 贴地平视：确认俯仰下限时仍能看见室内、不会穿到墙背后。
	await shot("low", base_yaw, main.cam.orbit_pitch_min_deg, dist)
	# 俯视：确认上限时房间不变成平面图、天花不会漏出来。
	await shot("high", base_yaw, main.cam.orbit_pitch_max_deg, dist)
	print("[room-orbit] done")
	quit(0)
