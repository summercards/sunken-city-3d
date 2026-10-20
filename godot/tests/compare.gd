extends SceneTree
## 画面回归对比：把当前截图和网页版基准逐格比色。
##
## 用法：
##   Godot --headless --path godot --script res://tests/compare.gd -- <参考图> <被测图>
## 默认参考 outputs/harbor-lush.png（1440x1000，裁中部 900 与 1440x900 的截图对齐）。


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ref_path := "/Users/summercards/WorkBuddy/sea/outputs/harbor-lush.png"
	var got_path := "/Users/summercards/WorkBuddy/sea/godot/outputs/godot-preview.png"
	if args.size() >= 1:
		ref_path = args[0]
	if args.size() >= 2:
		got_path = args[1]

	var ref := Image.load_from_file(ref_path)
	var got := Image.load_from_file(got_path)
	if ref == null or got == null:
		print("读不到图片")
		quit(1)
		return

	var w := mini(ref.get_width(), got.get_width())
	var h := mini(ref.get_height(), got.get_height())
	# 参考图比截图高 100px，按中心裁
	var ref_off := (ref.get_height() - h) / 2

	var sw := 0.0
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var dark := 0
	var bright := 0
	var n := 0
	var grid := {}
	var cols := 6
	var rows := 5
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var a: Color = ref.get_pixel(x, y + ref_off)
			var b: Color = got.get_pixel(x, y)
			sr += a.r - b.r
			sg += a.g - b.g
			sb += a.b - b.b
			sw += b.get_luminance()
			if b.get_luminance() < 0.28:
				dark += 1
			if b.get_luminance() > 0.72:
				bright += 1
			n += 1
			var key := "%d,%d" % [x * cols / w, y * rows / h]
			var cell: Array = grid.get(key, [0.0, 0.0, 0.0, 0])
			cell[0] += a.r - b.r
			cell[1] += a.g - b.g
			cell[2] += a.b - b.b
			cell[3] += 1
			grid[key] = cell

	print("size %dx%d  mean_lum=%.3f  dark%%=%.1f  bright%%=%.1f" % [
		w, h, sw / n, 100.0 * dark / n, 100.0 * bright / n])
	print("色差（参考-被测）：R %+.3f  G %+.3f  B %+.3f" % [sr / n, sg / n, sb / n])
	for j in rows:
		var line := ""
		for i in cols:
			var cell: Array = grid.get("%d,%d" % [i, j], [0, 0, 0, 1])
			line += "(%+.2f,%+.2f,%+.2f) " % [cell[0] / cell[3], cell[1] / cell[3], cell[2] / cell[3]]
		print("row", j, " ", line)
	quit(0)
