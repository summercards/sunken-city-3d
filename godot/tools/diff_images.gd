extends SceneTree
## 两张 PNG 的差异统计，用来回答「这两张看起来一样，到底差多少」。
##
## 有水面的截图几乎不可能逐字节相同（波场在动），所以看的是统计量：
## 平均绝对差、超过阈值的像素占比、最大差。
##
## 用法：
##   SEA_DIFF_A=a.png SEA_DIFF_B=b.png Godot --headless --path godot \
##     --script res://tools/diff_images.gd

const THRESHOLD := 2.0 / 255.0


func _init() -> void:
	var a_path := OS.get_environment("SEA_DIFF_A")
	var b_path := OS.get_environment("SEA_DIFF_B")
	if a_path == "" or b_path == "":
		print("[diff] FAIL 需要 SEA_DIFF_A / SEA_DIFF_B")
		quit(1)
		return
	var a := Image.load_from_file(a_path)
	var b := Image.load_from_file(b_path)
	if a == null or b == null:
		print("[diff] FAIL 读不到图：", a_path, " / ", b_path)
		quit(1)
		return
	if a.get_size() != b.get_size():
		b.resize(a.get_width(), a.get_height(), Image.INTERPOLATE_BILINEAR)
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)

	var total := 0.0
	var over := 0
	var peak := 0.0
	var count := a.get_width() * a.get_height()
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			total += d
			peak = maxf(peak, d)
			if d > THRESHOLD:
				over += 1

	print("[diff] 尺寸=", a.get_size(), " 平均绝对差=", "%.5f" % (total / float(count)),
		"（8 位 ", "%.2f" % (total / float(count) * 255.0), "）",
		" 超阈值像素=", "%.2f%%" % (100.0 * float(over) / float(count)),
		" 最大差=", "%.4f" % peak)
	quit(0)
