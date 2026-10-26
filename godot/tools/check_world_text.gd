extends SceneTree
## 世界浮层纯文字闸门：字号够大、字体是打包圆体、**没有勾边**。
##
## 为什么需要它：这几行字浮在 3D 画面上、没有背板托着，除了这里没有任何断言
## 盯着。踩过的两个坑都不是崩溃，而是"看起来不对"：
##   1. 上岸点名称用 `ThemeDB.fallback_font` + 11px + 4px `draw_string_outline`，
##      既不是打包字体，描边又把笔画之间的空隙糊掉 —— 字又小又"沟"。
##   2. `Cozy.world_text()` 设好的字体被 `island_presenters._font_tree()` 在
##      attach 时整树刷回 `hud._font`，字号对了、数字却掉回细笔画。
## 两条都不会让任何既有测试变红，只能靠这里的显式断言。
##
## 用法：
##   Godot --path godot --script res://tools/check_world_text.gd
## 退出码：0 = 全部合格，1 = 有不合格项。

const Cozy = preload("res://src/ui/cozy_ui.gd")

var main: Node
var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[world-text] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


## 描边与硬阴影都会沿圆体笔画外侧勾边；`shadow_outline_size` 和 `outline_size`
## 必须为 0，`shadow_offset` 允许非 0（那是偏移投影，不贴轮廓）。
func no_outline(label: Label) -> bool:
	return label.get_theme_constant("outline_size") == 0 \
		and label.get_theme_constant("shadow_outline_size") == 0


func bundled(label: Label) -> bool:
	var f: Font = label.get_theme_font("font")
	while f is FontVariation and (f as FontVariation).base_font != null:
		f = (f as FontVariation).base_font
	return f == Cozy.ui_font()


## 世界浮层的最小字号：基准正文 22 × 2.0 × 原字号/22 里最小的一档（0.60）= 26。
## 写成"至少 26"是为了挡住回退到 11~16px 那种旧值。
## 绝对下限，不与配置倍数自比 —— 否则把倍数整体调小，断言会跟着缩小、
## 永远通过（实测过：倍率 2.0→1.0 时旧写法只红了「≥26」这一条）。
func big_enough(label: Label) -> bool:
	return label.get_theme_font_size("font_size") >= Cozy.WORLD_TEXT_FLOOR


func audit(label: Label, name: String, allow_shadow := true) -> void:
	var fs: int = label.get_theme_font_size("font_size")
	ok(big_enough(label), "%s 字号 ≥ 下限 %dpx（实际 %dpx）" % [name, Cozy.WORLD_TEXT_FLOOR, fs])
	ok(bundled(label), "%s 用打包圆体（可含合成加粗变体）" % name)
	ok(no_outline(label), "%s 没有勾边（outline=%d shadow_outline=%d）" % [
		name, label.get_theme_constant("outline_size"), label.get_theme_constant("shadow_outline_size")])
	if not allow_shadow:
		ok(label.get_theme_color("font_shadow_color").a < 0.01, "%s 没有硬阴影" % name)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 90:
		await process_frame

	var hud: CanvasLayer = main.hud
	# 资源常驻行 / 潜水状态 / 视野提示
	audit(hud._res_label, "资源常驻行")
	hud.set_dive_air(0.86, true, 2, 5)
	hud.set_dive_depth(12.0)
	await frames(3)
	audit(hud._dive_status, "潜水状态")
	hud.note_zoom(1.25)
	await frames(3)
	audit(hud._zoom, "视野提示")

	# 世界浮层字必须扛得住 `_font_tree` 整树刷字体：这里显式重跑一遍。
	var adapter: Node = null
	for c in hud.get_children():
		if c.has_method("_font_tree"):
			adapter = c
			break
	if adapter != null:
		adapter._font_tree(main)
		await frames(2)
		ok(bundled(hud._res_label), "资源行在 _font_tree 之后仍是加粗变体")
		ok(bundled(hud._dive_status), "潜水状态在 _font_tree 之后仍是加粗变体")

	# 上岸点名称：自绘走 `Cozy.world_font()`，字号走 `Cozy.world_text_size`。
	var markers: Node = main.get_node_or_null("LandingMarkers")
	if markers != null:
		ok(markers._font is FontVariation, "上岸点名称用加粗变体（%s）" % markers._font.get_class())
		var fs: int = Cozy.world_text_size(Cozy.WORLD_TEXT_LANDING)
		ok(fs >= Cozy.WORLD_TEXT_FLOOR, "上岸点名称 ≥ 下限 %dpx（%dpx，原 11px）" % [Cozy.WORLD_TEXT_FLOOR, fs])
		# 自绘拿不到主题，只能查源码：`draw_string_outline(` 会在笔画外侧勾硬边。
		# 只查调用形态，注释里提到这个方法名不算。
		var src := FileAccess.get_file_as_string("res://src/ui/landing_markers.gd")
		ok(not src.contains("draw_string_outline("), "上岸点名称不再调用 draw_string_outline")

	# 水下宝箱名牌
	var uw: Node = main.get_node_or_null("Underwater")
	var seen := 0
	if uw != null:
		for chest in uw._chests:
			var l: Label = chest.get("marker")
			if l == null:
				continue
			audit(l, "水下宝箱名牌「%s」" % l.text)
			seen += 1
			if seen >= 3:
				break
	ok(seen > 0, "水下宝箱名牌存在（%d 个）" % seen)

	print("[world-text] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await frames(2)
	quit(0 if failures == 0 else 1)
