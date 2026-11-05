extends SceneTree
## 缩放上限的真实渲染证据（SEA-CAMERA-R11）。
##
## 只抓图与断言，不改玩法：连续往外滚 20 档，距离必须钉在 zoom_max(38)；
## 再连续往里滚 20 档，必须停到 zoom_min(9)。两个机位各存一张图，
## 便于肉眼核对「最远」就是开局那一档取景。
##
## 跑法：python3 scripts/run_verification.py visual-camera-zoom

const OUT_DIR := "res://outputs"

var main: Node
var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)


func _init() -> void:
	call_deferred("run")


func shot(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null, "frame " + name)
	if image != null:
		check(image.save_png(OUT_DIR + "/" + name) == OK, "saved " + name)
		print("[camera-zoom-shot] ", name, " ", image.get_width(), "x", image.get_height())


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	root.get_node("Economy").set_process(false)
	main.world_clock.paused = true
	main.world_clock.from_dict({"day": 1, "seconds": 21 * 3600 + 39 * 60, "day_length": 1200})
	main.daylight_rig.apply(21.65)
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()

	var cam: Camera3D = main.cam
	check(is_equal_approx(cam.zoom_max, 38.0), "缩放上限=38")
	check(is_equal_approx(cam.zoom_min, 9.0), "缩放下限=9")
	cam.suspend_follow()
	cam.target = Vector3(0.45, 1.75, -0.65)
	cam.orbit_dir = Vector3(-0.5, 0.7, 0.5)
	cam.distance = 38.0
	cam.refresh()

	# 开局即最远：先确认默认机位就在上限上。
	check(is_equal_approx(cam.distance, cam.zoom_max), "开局=最远")
	check(absf(cam.zoom_ratio() - 1.0) < 0.001, "缩放比例 100%")
	await shot("camera-zoom-38.png")

	# 连续往外滚 20 档：一格 0.86 的倒数，20 档足以从任何位置到顶。
	for i in 20:
		cam.zoom_action.execute(cam, 1.0 / 0.86, Vector2(540, 337))
	for i in 20:
		cam._process(1.0 / 60.0)
	check(absf(cam.distance - 38.0) < 0.001, "滚轮拉不出去 distance=" + str(cam.distance))
	check(absf(cam._cur_distance - 38.0) < 0.001, "平滑后仍停 38 实际=" + str(cam._cur_distance))
	check(cam.position.distance_to(cam._cur_target) < 38.5, "相机没被甩出上限")
	await shot("camera-zoom-clamped.png")

	# 往里滚到底：下限 9 m 仍然有效，说明上限收紧没有把缩放整体压死。
	for i in 20:
		cam.zoom_action.execute(cam, 0.86, Vector2(540, 337))
	for i in 20:
		cam._process(1.0 / 60.0)
	check(absf(cam.distance - 9.0) < 0.001, "拉到最近 9m 实际=" + str(cam.distance))
	await shot("camera-zoom-9.png")

	print("[camera-zoom] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
