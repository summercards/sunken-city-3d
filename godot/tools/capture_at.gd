extends SceneTree
## 定点抓图：给一个眼位与目标位，存一张 res://outputs/ 下的 png。
##
##   --script res://tools/capture_at.gd -- --eye=100,8,55 --target=110,8,72 --name=neon_face --fov=55
##
## `--hour=12` 把世界时钟钉到该时刻再抓：读档时间在半夜时，整张图只有月光，
## 几何对不对根本看不清。不给就保持存档里的时刻。

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var want_hour := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			want_hour = float(arg.substr(7))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.cam.set_process(false)
	main.cam.suspend_follow()
	if main.get("world_clock") != null:
		main.world_clock.paused = true
	# 标题屏是一层单独的 CanvasLayer，把 hud 藏了它还在，整张图会被压暗一半。
	if main.get("start_screen") != null:
		main.start_screen.visible = false
		main.start_screen.process_mode = Node.PROCESS_MODE_DISABLED
	main._title_active = false
	for i in 40:
		await process_frame
	if want_hour >= 0.0 and main.get("world_clock") != null:
		print("[shot] 存档时刻 %.1f 点 → 改到 %.1f 点" % [
			float(main.world_clock.query().get("hour", -1.0)), want_hour])
		main.world_clock.seconds = want_hour * 3600.0
		if main.get("daylight_rig") != null:
			main.daylight_rig.set_preview(want_hour)
		for i in 8:
			await process_frame
	if main.get("hud") != null:
		main.hud.visible = false

	var eye := Vector3(100, 8, 55)
	var target := Vector3(110, 8, 72)
	var name := "shot"
	var fov := 55.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--eye="):
			var f := arg.substr(6).split(",")
			eye = Vector3(float(f[0]), float(f[1]), float(f[2]))
		elif arg.begins_with("--target="):
			var f2 := arg.substr(9).split(",")
			target = Vector3(float(f2[0]), float(f2[1]), float(f2[2]))
		elif arg.begins_with("--name="):
			name = arg.substr(7)
		elif arg.begins_with("--fov="):
			fov = float(arg.substr(6))
	var cam := main.cam as Camera3D
	cam.fov = fov
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := "res://outputs/%s.png" % name
	img.save_png(path)
	print("[shot] ", path, " ", img.get_width(), "x", img.get_height())
	quit(0)
