extends SceneTree
## 取景对照探针：同一构图、同一时刻，只改相机距离，各存一张。
## 用来核对「玩家说的 38」到底是 38 米还是面板上的 38%。
## 跑法：SEA_ZOOM_SET="38,54.25,68,78,90" python3 → 见 scripts/probe_zoom_framing.py

const OUT_DIR := "res://outputs"

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	root.get_node("Economy").set_process(false)
	main.world_clock.paused = true
	main.world_clock.from_dict({"day": 1, "seconds": 21 * 3600 + 39 * 60, "day_length": 1200})
	main.daylight_rig.apply(21.65)

	var cam: Camera3D = main.cam
	# 对照工具：玩家上限已收紧，这里放开以便比较各种机位。
	cam.zoom_max = 260.0
	cam.suspend_follow()
	var spec := OS.get_environment("SEA_ZOOM_SET")
	if spec == "":
		spec = "38"
	for piece in spec.split(",", false):
		var d := float(piece.strip_edges())
		cam.target = Vector3(0.45, 1.75, -0.65)
		cam.orbit_dir = Vector3(-54, 76.37, 54)
		cam.distance = d
		cam.refresh()
		for i in 14:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var name := "framing-" + str(int(round(d * 100))) + ".png"
		img.save_png(OUT_DIR + "/" + name)
		print("[framing] ", name, " distance=", d, " ", img.get_width(), "x", img.get_height())

	main.queue_free()
	await process_frame
	quit(0)
