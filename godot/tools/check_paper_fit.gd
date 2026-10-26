extends SceneTree
## 背板装配闸门：证明「每块纸背板都装得住自己的字」。
##
## 为什么需要它：`island_paper` 的圆角是按面板宽高比例算的（横向约 0.09 W、
## 纵向约 0.10 H），而面板的内边距是固定 32 px。面板一窄一宽，圆角就会吃进
## 文字所在的矩形 —— 字看起来「探出背板」，但所有 `inside(panel)` 断言都通过，
## 因为它们只比面板矩形，不比纸的轮廓。
##
## 这里直接拿纸多边形做内点判定，逐个 Label 的四角与四边中点取样。
##
## 用法：
##   SEA_SHOT_DIR=<dir> Godot --path godot --script res://tools/check_paper_fit.gd
##   SEA_SHOT_DIR 存在时会顺带存图，便于人眼复核。
##
## 退出码：0 = 无越界（或有越界但给了显式豁免），1 = 有字探出背板。

const TOLERANCE := 1.5
const SHOT_TAG := "paper-fit"

var main: Node
var out_dir := ""
var checks := 0
var failures := 0
var worst_report: Array[String] = []


func _init() -> void:
	out_dir = OS.get_environment("SEA_SHOT_DIR")
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


# ---- 几何 -------------------------------------------------------------------

func _paper_of(panel: Control) -> Control:
	for c in panel.get_parent().get_children():
		if c.has_meta("paper_owner") and c.get_meta("paper_owner") == panel:
			return c
	return null


func _poly_global(paper: Control) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in paper._outline():
		out.append(p + paper.global_position)
	return out


func _inside(poly: PackedVector2Array, pt: Vector2) -> bool:
	var ins := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if ((b.y > pt.y) != (a.y > pt.y)) and (pt.x < (a.x - b.x) * (pt.y - b.y) / (a.y - b.y) + b.x):
			ins = not ins
		j = i
	return ins


func _depth(poly: PackedVector2Array, pt: Vector2) -> float:
	# 只作为报告用的相对量：到最近轮廓点的距离。
	var d := 1e9
	for p in poly:
		d = minf(d, p.distance_to(pt))
	return d


## 返回 (越界像素, 越界朝向)。0 表示完全在背板内。
func _overflow(poly: PackedVector2Array, rect: Rect2) -> Vector2:
	var samples := {
		"TL": rect.position, "TR": Vector2(rect.end.x, rect.position.y),
		"BL": Vector2(rect.position.x, rect.end.y), "BR": rect.end,
		"L": Vector2(rect.position.x, rect.get_center().y),
		"R": Vector2(rect.end.x, rect.get_center().y),
		"T": Vector2(rect.get_center().x, rect.position.y),
		"B": Vector2(rect.get_center().x, rect.end.y),
	}
	var worst := 0.0
	var where := ""
	for key in samples:
		var pt: Vector2 = samples[key]
		if _inside(poly, pt):
			continue
		var d := _depth(poly, pt)
		if d > worst:
			worst = d
			where = key
	return Vector2(worst, 0.0) if where == "" else Vector2(worst, ["TL", "TR", "BL", "BR", "L", "R", "T", "B"].find(where))


func _label_of_where(idx: float) -> String:
	var names := ["TL", "TR", "BL", "BR", "L", "R", "T", "B"]
	var i := int(idx)
	return names[i] if i >= 0 and i < names.size() else "?"


## 只看会被纸裁到的 Label：落在 ScrollContainer 里的由滚动区自己裁，不算。
func _clipped_by_scroll(node: Node) -> bool:
	var n := node.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


func audit(id: String, panel: Control) -> void:
	checks += 1
	var paper := _paper_of(panel)
	if paper == null:
		print("[paper-fit] FAIL %s 没有纸背板" % id)
		failures += 1
		return
	var poly := _poly_global(paper)
	var bad: Array[String] = []
	var worst := 0.0
	var worst_text := ""
	var measured := 0
	for node in panel.find_children("*", "Label", true, false):
		var l := node as Label
		if not l.is_visible_in_tree() or l.text.strip_edges() == "":
			continue
		if _clipped_by_scroll(l):
			continue
		measured += 1
		var ov := _overflow(poly, Rect2(l.global_position, l.size))
		if ov.x > TOLERANCE:
			bad.append("%s %.1fpx@%s" % [l.text.substr(0, 14), ov.x, _label_of_where(ov.y)])
			if ov.x > worst:
				worst = ov.x
				worst_text = l.text.substr(0, 24)
	# 一个可测的字都没有，说明这块面板根本没显示 —— 那是空跑，不能算通过。
	if measured == 0:
		bad.append("没有可测文字（面板可能没显示）")
	# 纸是往四面长大的，长大之后必须还在屏幕里 —— 否则字确实不探边了，
	# 但整块纸被推出画面，那是另一种坏。
	var vp := root.get_visible_rect()
	var clipped := 0.0
	for p in poly:
		clipped = maxf(clipped, maxf(maxf(-p.x, -p.y), maxf(p.x - vp.size.x, p.y - vp.size.y)))
	if clipped > TOLERANCE:
		bad.append("纸超出屏幕 %.1fpx" % clipped)
		worst = maxf(worst, clipped)
		if worst_text == "":
			worst_text = "（纸越出视口）"
	if bad.is_empty():
		print("[paper-fit] PASS %s  panel=%s paper=%s" % [id, panel.size, paper.size])
	else:
		failures += 1
		print("[paper-fit] FAIL %s 最大 %.1fpx「%s」 panel=%s paper=%s" % [id, worst, worst_text, panel.size, paper.size])
		for line in bad:
			print("[paper-fit]   · ", line)
		worst_report.append("%s: %.1fpx" % [id, worst])


## 找一个真的可交互 spot：气泡文本来自它的 `focus_text()`。
func _nearest_spot(main: Node) -> Node3D:
	for node in main.get_tree().get_nodes_in_group("interactive"):
		if node is Node3D and node.has_method("focus_text"):
			return node
	var groups := ["interactable", "spots", "harvest_spots", "pickups"]
	for g in groups:
		for node in main.get_tree().get_nodes_in_group(g):
			if node is Node3D and node.has_method("focus_text"):
				return node
	return null


func shot(tag: String) -> void:
	if out_dir == "":
		return
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(SHOT_TAG + "-" + tag + ".png"))


# ---- 场景 -------------------------------------------------------------------

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	await frames(90)

	var hud: CanvasLayer = main.hud
	var menu: CanvasLayer = hud.menu

	# 摄像机 / 调色室两页
	main.cam_panel.set_open(true)
	await frames(10)
	audit("camera", main.cam_panel._panel)
	await shot("camera")
	main.cam_panel.set_open(false)
	await frames(4)

	main.grade.set_open(true)
	main.grade.set_tab("filter")
	await frames(10)
	audit("grade/filter", main.grade._panel)
	await shot("grade-filter")
	main.grade.set_tab("water")
	await frames(10)
	audit("grade/water", main.grade._panel)
	await shot("grade-water")
	main.grade.set_open(false)
	await frames(4)

	# 订单 / 打捞
	main.order_panel.set_open(true)
	await frames(10)
	audit("orders", main.order_panel._card)
	await shot("orders")
	main.order_panel.set_open(false)
	await frames(4)

	main.salvage_panel.begin()
	await frames(10)
	audit("salvage", main.salvage_panel._card)
	await shot("salvage")
	main.salvage_panel.cancel()
	await frames(4)

	# 世界上的提示气泡 + 对话条
	# 气泡由 `main._process` 每帧 `update_from(interactor)` 驱动，手上没聚焦目标
	# 就会把自己收起来。造一个真的交互目标，让气泡按正式路径显示 —— 手动点亮
	# 会在下一帧被收回去，那是空跑。
	# 先把外面的每帧驱动停掉，再让气泡自己的 `update_from` 走一遍正式路径。
	main.set_process(false)
	var spot := _nearest_spot(main)
	main.interactor.target = spot
	main.interactor.active = spot != null
	main.prompt.update_from(main.interactor)
	await frames(8)
	audit("prompt", main.prompt._panel)
	await shot("prompt")
	print("[paper-fit] prompt 状态 layer_visible=%s panel_visible=%s panel.visible=%s menu=%s panel_open=%s text=%s" % [
		main.prompt.visible, main.prompt._panel.is_visible_in_tree(), main.prompt._panel.visible,
		main.hud.menu.active, main.hud._panel_open, main.prompt._text.text])
	print("[paper-fit] external_open=%s salvage_visible=%s" % [
		main.hud.menu.external_open(), main.salvage_panel.visible])
	main.prompt.visible = false
	main.set_process(true)
	await frames(4)
	hud.toast("今天也收获满满！海风送来了新的礼物。", 5)
	await frames(8)
	audit("toast", hud._toast_box)
	await shot("toast")
	hud._toast_left = 0.0
	await frames(4)

	# 暂停菜单四页
	for page in ["pause", "settings", "help", "load"]:
		menu.show_menu(page)
		await frames(8)
		audit("menu/" + page, menu._paper)
		await shot("menu-" + page)
		menu.close_menu()
		await frames(4)

	print("[paper-fit] %d checks, %d failures, tolerance=%.1fpx" % [checks, failures, TOLERANCE])
	if not worst_report.is_empty():
		print("[paper-fit] 越界汇总: ", worst_report)
	main.queue_free()
	await frames(2)
	quit(0 if failures == 0 else 1)
