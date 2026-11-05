extends SceneTree
## 围挡在正式游戏里的真实渲染证据（SEA-ASSET-R47）。
## 只抓图，不改玩法；跑法：python3 scripts/run_verification.py visual-sea-barrier

var main: Node
var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)


func _init() -> void:
	call_deferred("run")


func shot(label: String, target: Vector3, distance: float, orbit: Vector3) -> void:
	main.cam.target = target
	main.cam.distance = distance
	main.cam.orbit_dir = orbit
	main.cam.refresh()
	for i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null, "frame " + label)
	if image != null:
		check(image.save_png("res://outputs/sea-barrier-" + label + ".png") == OK, "saved " + label)
		print("[barrier-shot] ", label, " ", image.get_width(), "x", image.get_height())


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 取景工具：玩家上限是 38 m（SEA-CAMERA-R11），这里临时放开；
	# 围挡在 108~112 m 外，贴着墙拍仍需要中远景机位。
	main.cam.zoom_max = 260.0
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()
	await process_frame
	# 相机 zoom_max 只有 190 米，从家园中心（原点）拉不到 240 米外的围挡 ——
	# 这是范围放大后的真实限制，所以取景要贴着围挡，不能站在圈心拍。
	# 北墙：镜头在墙内侧，朝北看墙
	await shot("north", Vector3(0, 1.12, 108), 42.0, Vector3(0.1, 0.42, -0.9))
	# 西南角：看两条墙的交角
	await shot("corner", Vector3(-104, 1.12, -104), 46.0, Vector3(0.68, 0.46, 0.57))
	# 沿墙斜看：能同时看到连续性与纵深
	await shot("along", Vector3(-40, 1.12, 112), 58.0, Vector3(0.86, 0.36, -0.36))

	print("[sea-barrier-render] ", failures, " failures")
	quit(0 if failures == 0 else 1)
