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
	# 默认距离与俯角从房间自己的 `camera_pose()` 取，不在这里另写一份 ——
	# 否则调了正式机位，验收图还停在旧数值上，等于没验。
	var pose: Dictionary = main.room.camera_pose()
	var dist: float = float(pose.distance)
	var base_yaw := 41.0
	var base_pitch := rad_to_deg(asin(Vector3(pose.dir).normalized().y))
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
