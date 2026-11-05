extends SceneTree
## 自动量「小屋连通块」的屏幕包围盒，用同一套算法跑参考图与候选渲染。
##
## 关键点：不需要知道包围盒「绝对正确」—— 只要两边用同一个算法，
## 系统性偏差就抵消了。找宽度相等的那个距离即可。
##
## 遮掉 HUD（右上按钮/提示条、左下日期、右下体力与图标），否则 HUD 会成为
## 最大的连通块（第一版暖光标尺就栽在这）。
##
## 跑法：python3 scripts/run_verification.py visual-silhouette

## 参考截图不放 assets（避免污染资产目录与清单），从环境变量给绝对路径：
##   SEA_FRAMING_REF="D:/projects/sea/sea-work/camera_ref/night-framing-ref.jpg"
## 不给就只输出各档宽度占比，不做 BEST 判定。
const REF_ENV := "SEA_FRAMING_REF"
const STEP := 3
var main: Node


func _init() -> void:
	call_deferred("run")


## 水面：偏冷、偏暗、蓝明显压过红。夜里海面大面积都是这个特征。
func _is_water(c: Color) -> bool:
	if c.b > c.r * 1.18 and c.b > 0.045:
		return true
	if c.get_luminance() < 0.035:
		return true
	return false


func _blank(img: Image, u0: float, v0: float, u1: float, v1: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(int(v0 * h), int(v1 * h)):
		for x in range(int(u0 * w), int(u1 * w)):
			img.set_pixel(x, y, Color(0.02, 0.05, 0.12))


func _prepare(img: Image) -> void:
	_blank(img, 0.86, 0.0, 1.0, 0.10)    # 右上圆钮
	_blank(img, 0.65, 0.0, 1.0, 0.14)    # 右上提示条
	_blank(img, 0.0, 0.85, 0.18, 1.0)    # 左下日期/瓶盖/背包
	_blank(img, 0.85, 0.85, 1.0, 0.94)   # 右下体力条
	_blank(img, 0.91, 0.88, 1.0, 1.0)    # 右下角色图标
	_blank(img, 0.28, 0.90, 0.72, 1.0)   # 底部中央 pill


## 最大连通「非水面」块的包围盒。
func _largest_block(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var cols := int(w / STEP)
	var rows := int(h / STEP)
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	for gy in rows:
		for gx in cols:
			var c := img.get_pixel(gx * STEP, gy * STEP)
			mask[gy * cols + gx] = 0 if _is_water(c) else 1

	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var best_area := 0
	var best := Rect2i(0, 0, 0, 0)
	for gy in rows:
		for gx in cols:
			var start := gy * cols + gx
			if mask[start] == 0 or seen[start] == 1:
				continue
			var stack: Array[int] = [start]
			seen[start] = 1
			var area := 0
			var min_x := gx
			var max_x := gx
			var min_y := gy
			var max_y := gy
			while not stack.is_empty():
				var cur: int = stack.pop_back()
				area += 1
				var cx: int = cur % cols
				var cy: int = int(cur / cols)
				if cx < min_x: min_x = cx
				if cx > max_x: max_x = cx
				if cy < min_y: min_y = cy
				if cy > max_y: max_y = cy
				for dy: int in [-1, 0, 1]:
					for dx: int in [-1, 0, 1]:
						var nx: int = cx + dx
						var ny: int = cy + dy
						if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
							continue
						var nidx: int = ny * cols + nx
						if mask[nidx] == 1 and seen[nidx] == 0:
							seen[nidx] = 1
							stack.push_back(nidx)
			if area > best_area:
				best_area = area
				best = Rect2i(min_x * STEP, min_y * STEP,
					(max_x - min_x + 1) * STEP, (max_y - min_y + 1) * STEP)
	return best


func _report(tag: String, img: Image) -> float:
	_prepare(img)
	var box := _largest_block(img)
	if box.size.x <= 0:
		print("[silhouette] ", tag, " none")
		return -1.0
	var pct := box.size.x / float(img.get_width()) * 100.0
	print("[silhouette] %-10s box=%s  w=%.1f%%  h=%.1f%%" % [
		tag, str(box), pct, box.size.y / float(img.get_height()) * 100.0])
	# 把包围盒画回去，用来核对两边量的是不是同一个物体。
	var w := img.get_width()
	var h := img.get_height()
	var red := Color(1.0, 0.15, 0.15, 1.0)
	for t in 4:
		for x in range(box.position.x, box.end.x):
			if x >= 0 and x < w:
				img.set_pixel(x, clampi(box.position.y + t - 2, 0, h - 1), red)
				img.set_pixel(x, clampi(box.end.y - 1 + t - 2, 0, h - 1), red)
		for y in range(box.position.y, box.end.y):
			if y >= 0 and y < h:
				img.set_pixel(clampi(box.position.x + t - 2, 0, w - 1), y, red)
				img.set_pixel(clampi(box.end.x - 1 + t - 2, 0, w - 1), y, red)
	img.save_png("res://outputs/sil-box-%s.png" % tag.replace("=", "").replace(".", "_"))
	return pct


func run() -> void:
	var ref_pct := -1.0
	var ref_path := OS.get_environment(REF_ENV)
	if ref_path != "" and FileAccess.file_exists(ref_path):
		var ref := Image.load_from_file(ref_path)
		if ref != null:
			ref_pct = _report("REFERENCE", ref)
	if ref_pct < 0.0:
		print("[silhouette] 未提供 ", REF_ENV, "，只输出候选宽度、不做 BEST 判定")

	main = load("res://scenes/main.tscn").instantiate()
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

	var spec := OS.get_environment("SEA_SIL_SET")
	if spec == "":
		spec = "54.25,66,78,90,100,110,120,132,145,160,175,190"
	var best := {"d": 0.0, "delta": 1e9}
	for piece in spec.split(",", false):
		var d := float(piece.strip_edges())
		cam.distance = d
		cam.refresh()
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.save_png("res://outputs/sil-%d.png" % int(round(d)))
		var pct := _report("d=%.1f" % d, shot)
		if pct > 0 and ref_pct > 0:
			var delta: float = absf(pct - ref_pct)
			if delta < best["delta"]:
				best = {"d": d, "delta": delta}

	if ref_pct > 0.0:
		print("[silhouette] reference_w=%.1f%%  BEST=%.2f m (delta %.1f%%)" % [ref_pct, best["d"], best["delta"]])
	else:
		print("[silhouette] no reference; candidates measured above")
	print("[silhouette] done")
	main.queue_free()
	await process_frame
	quit(0)
