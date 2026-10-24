extends SceneTree
## 截 P 面板的两页，确认水面参数的排版与控件都在。
##
## 用法：
##   SEA_SHOT_DIR=F:/wxgame/sea-work/tmp Godot --path godot \
##     --script res://tools/capture_water_panel.gd
##
## 没有 SEA_SHOT_DIR 就落到 user://。注意这个脚本会真实起一帧世界，
## 连带把水面渲出来，所以图里也能顺带看出参数改动有没有把水弄坏。

var main: Node
var out_dir := ""


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	# 岸线图要几秒，等世界稳定下来再开面板。
	for i in 90:
		await process_frame

	if main.grade == null:
		print("[panel-shot] FAIL 没有 grade 面板")
		quit(1)
		return

	main.grade.set_open(true)
	main.grade.set_tab("water")
	for i in 10:
		await process_frame
	await _shot("water-panel-top.png")

	# 滚到底：确认长列表后半段的泡沫/输出组也在。
	main.grade._water_scroll.scroll_vertical = 100000
	for i in 6:
		await process_frame
	await _shot("water-panel-bottom.png")

	# 中段：按组名定位，专门拍新加的那几组（目前是「水面光点」）。
	await _scroll_to_group("水面光点")
	await _shot("water-panel-mid.png")

	main.grade._water_scroll.scroll_vertical = 0
	main.grade.set_tab("filter")
	for i in 6:
		await process_frame
	await _shot("filter-panel.png")

	print("[panel-shot] done out_dir=", out_dir)
	main.queue_free()
	await process_frame
	quit(0)


## 按分组标题的文字滚过去。写死像素位置很容易被新加的组挤偏。
func _scroll_to_group(title: String) -> void:
	var body = main.grade._water_body
	var y := 0
	for c in body.get_children():
		if c is Button and String((c as Button).text).contains(title):
			y = int((c as Control).position.y)
			break
	main.grade._water_scroll.scroll_vertical = maxi(0, y - 40)
	for i in 6:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	print("[panel-shot] ", name, " -> ", err, " ", path)
