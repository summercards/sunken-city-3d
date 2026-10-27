extends SceneTree
## 真正打开 P 面板「水面」页并截图，确认「水下光斑」组的控件被建出来了。
var out := "D:/projects/sea-work/caustics/panel"
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("run")
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 70: await process_frame
	main.hud.hide(); main.markers.hide(); main.ribbon.hide()
	var grade = main.grade
	grade.set_open(true)
	grade.set_tab("water")
	for i in 20: await process_frame
	# 滚到含「水下光斑」的位置：直接找 label 节点
	# 分组标题和 note 是富文本，不是独立 Label，所以直接按「斑块密度」这个
	# 控件滚过去 —— 它是本组第二行，滚到它就整组可见。
	var ctrls := _find_text(grade, "斑块密度")
	print("[pan] 找到「斑块密度」控件 ", ctrls.size(), " 处")
	if ctrls.size() > 0:
		var scroll := _find_scroll(grade)
		if scroll != null:
			await process_frame
			scroll.ensure_control_visible(ctrls[0])
			for i in 10: await process_frame
			print("[pan] 已滚动")
	for spec in _find_text(grade, "斑块密度"):
		print("[pan] 找到「斑块密度」控件")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/panel.png")
	print("[pan] saved")
	quit(0)
func _find_scroll(n: Node) -> ScrollContainer:
	var sc := n as ScrollContainer
	if sc != null:
		return sc
	for c in n.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


func _find_text(n: Node, t: String) -> Array:
	var r := []
	var lbl := n as Label
	if lbl != null and lbl.text.contains(t):
		r.append(lbl)
	for c in n.get_children():
		r.append_array(_find_text(c, t))
	return r
