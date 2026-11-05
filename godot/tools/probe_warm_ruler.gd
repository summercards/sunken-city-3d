extends SceneTree
## 用「最大连通暖光簇」当标尺，把主人截图里的取景反解成相机距离。
##
## 为什么要连通簇：夜里画面里暖色不止小屋一处 —— 右上角 HUD 圆钮、右下体力条、
## 左下日期文字、左侧独立灯台都偏暖。取全局包围盒会把它们一起圈进去，
## 量出来的宽度跟小屋大小无关（第一版就栽在这）。
##
## 做法：4 px 降采样 → 暖色阈值 → 8 邻域连通 → 取最大簇的包围盒宽度占比。
## 小屋的窗光、甲板灯、串灯连成一片，是画面里最大的那一簇。
##
## 跑法：python3 scripts/run_verification.py visual-warm-ruler

const REF := "res://assets/reference/night-framing-ref.jpg"
const STEP := 4
const CANDIDATES := [54.25, 68.0, 78.0, 84.0, 90.0, 100.0, 110.0, 120.0, 150.0, 190.0]


func _init() -> void:
	call_deferred("run")


func _is_warm(c: Color) -> bool:
	return c.r > 0.42 and (c.r - c.b) > 0.09 and c.r >= c.g * 0.85


## 最大连通暖光簇的包围盒（原图坐标，已乘回降采样倍数）。
func _biggest_warm_cluster(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var cols := int(w / STEP)
	var rows := int(h / STEP)
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	for gy in rows:
		for gx in cols:
			var c := img.get_pixel(gx * STEP, gy * STEP)
			mask[gy * cols + gx] = 1 if _is_warm(c) else 0

	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var best_area := 0
	var best_rect := Rect2i(0, 0, 0, 0)
	for gy in rows:
		for gx in cols:
			var idx := gy * cols + gx
			if mask[idx] == 0 or seen[idx] == 1:
				continue
			# 洪水填充
			var stack: Array[int] = [idx]
			seen[idx] = 1
			var area := 0
			var min_x := gx
			var max_x := gx
			var min_y := gy
			var max_y := gy
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				area += 1
				var cx := cur % cols
				var cy := int(cur / cols)
				if cx < min_x: min_x = cx
				if cx > max_x: max_x = cx
				if cy < min_y: min_y = cy
				if cy > max_y: max_y = cy
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nx := cx + dx
						var ny := cy + dy
						if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
							continue
						var nidx := ny * cols + nx
						if mask[nidx] == 1 and seen[nidx] == 0:
							seen[nidx] = 1
							stack.push_back(nidx)
			if area > best_area:
				best_area = area
				best_rect = Rect2i(min_x * STEP, min_y * STEP,
					(max_x - min_x + 1) * STEP, (max_y - min_y + 1) * STEP)
	return best_rect


func _report(tag: String, img: Image) -> float:
	var box := _biggest_warm_cluster(img)
	if box.size.x <= 0:
		print("[warm-ruler] ", tag, " cluster=none")
		return -1.0
	var pct := box.size.x / float(img.get_width()) * 100.0
	print("[warm-ruler] %-10s cluster=%s width=%.1f%% height=%.1f%%" % [
		tag, str(box), pct, box.size.y / float(img.get_height()) * 100.0])
	return pct


func run() -> void:
	var ref := Image.load_from_file(ProjectSettings.globalize_path(REF))
	if ref == null:
		printerr("[warm-ruler] FAIL 参考截图缺失 ", REF)
		quit(1)
		return
	var ref_pct := _report("REFERENCE", ref)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	root.get_node("Economy").set_process(false)
	main.world_clock.paused = true
	main.world_clock.from_dict({"day": 3, "seconds": 21 * 3600 + 39 * 60, "day_length": 1200})
	main.daylight_rig.apply(21.65)
	for i in 25:
		await process_frame

	var cam: Camera3D = main.cam
	cam.zoom_max = 400.0
	cam.suspend_follow()
	cam.target = Vector3(0.45, 1.75, -0.65)
	cam.orbit_dir = Vector3(-54, 76.37, 54)
	cam.refresh()

	var best_dist := 0.0
	var best_delta := 1e9
	for d in CANDIDATES:
		cam.distance = float(d)
		cam.refresh()
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.save_png("res://outputs/warm-ruler-%d.png" % int(round(float(d))))
		var pct := _report("d=%.1f" % d, shot)
		if pct > 0.0 and ref_pct > 0.0:
			var delta: float = absf(pct - ref_pct)
			if delta < best_delta:
				best_delta = delta
				best_dist = float(d)

	print("[warm-ruler] reference_width=%.1f%%  best_match=%.2f m (delta %.1f%%)" % [ref_pct, best_dist, best_delta])
	print("[warm-ruler] done")
	main.queue_free()
	await process_frame
	quit(0)
