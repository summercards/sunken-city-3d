extends CanvasLayer
## 绞盘打捞面板：下钩 → 收线 → 结算。
##
## 规则在 `scripts/core/salvage.gd`（纯状态机），这里只负责「看得懂 + 按得动」：
##   · 深度条：钩子下到哪了；按 E 停住之后不再动。
##   · 张力表：绿区才有收线进度。中间画一条针，顶到红线开始计时。
##   · 进度条：收满即完成。
##
## 交互约定与网页版一致：整个界面不挡鼠标点击以外的东西 ——
## 打开时只吃 E / 空格 / 回车 / ESC，其余交给主场景。

signal finished(haul: Dictionary, success: bool)

const SalvageLib = preload("res://scripts/core/salvage.gd")
const ItemDB = preload("res://scripts/core/item_db.gd")

const SWEET_MIN := 0.42
const SWEET_MAX := 0.78
const SNAP := 0.96

const C_PANEL := Color(0.030, 0.098, 0.165, 0.92)
const C_BORDER := Color(0.42, 0.88, 0.82, 0.40)
const C_TITLE := Color(0.86, 0.98, 1.0, 1.0)
const C_TEXT := Color(0.72, 0.86, 0.92, 1.0)
const C_GOOD := Color(0.45, 0.93, 0.76, 1.0)
const C_WARN := Color(1.0, 0.80, 0.42, 1.0)
const C_BAD := Color(1.0, 0.45, 0.42, 1.0)

var model = null
var open := false

var _card: PanelContainer
var _title: Label
var _hint: Label
var _depth_bar: ProgressBar
var _depth_fill: StyleBoxFlat
var _depth_text: Label
var _tension: Control
var _progress_bar: ProgressBar
var _progress_fill: StyleBoxFlat
var _progress_text: Label
var _result: Label
var _font: SystemFont
var _hold_was := false
## 打开面板的那次 E 还没松手：必须先松开一次才算「按键」，
## 否则玩家一按 E 面板就开、钩子立刻停在 0% 深度。
var _armed := false
var _close_left := 0.0


## 张力表：绿区 + 红线 + 指针，纯 _draw 画的，比三根 ProgressBar 便宜也更好看。
class TensionGauge extends Control:
	var tension := 0.0
	var sweet_min := 0.42
	var sweet_max := 0.78
	var snap_at := 0.96
	var hot := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.10, 0.24, 0.30, 0.9), true)
		# 绿区
		draw_rect(Rect2(w * sweet_min, 0, w * (sweet_max - sweet_min), h),
			Color(0.30, 0.78, 0.60, 0.55), true)
		# 危险线
		draw_rect(Rect2(w * snap_at, 0, maxf(1.0, w * (1.0 - snap_at)), h),
			Color(0.95, 0.36, 0.32, 0.55), true)
		# 指针
		var x := clampf(w * tension, 0.0, w - 2.0)
		draw_rect(Rect2(x - 1.5, -3.0, 3.0, h + 6.0),
			Color(1.0, 0.72, 0.30, 1.0) if hot else Color(0.93, 0.99, 1.0, 1.0), true)


func _ready() -> void:
	layer = 60
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"])

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_card = PanelContainer.new()
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -232
	_card.offset_right = 232
	_card.offset_top = -308
	_card.offset_bottom = -104
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	_title = _label("绞盘打捞", 14, C_TITLE)
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_hint = _label("", 11, C_TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_hint)

	# 深度
	_depth_text = _label("深度 0%", 11, C_TEXT)
	box.add_child(_depth_text)
	var drow := _make_bar(C_GOOD)
	_depth_bar = drow[0]
	_depth_fill = drow[1]
	box.add_child(_depth_bar)

	# 张力
	var tlabel := _label("张力", 11, C_TEXT)
	box.add_child(tlabel)
	_tension = TensionGauge.new()
	_tension.custom_minimum_size = Vector2(0, 13)
	_tension.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_tension)

	# 收线进度
	_progress_text = _label("收线 0%", 11, C_TEXT)
	box.add_child(_progress_text)
	var prow := _make_bar(C_GOOD)
	_progress_bar = prow[0]
	_progress_fill = prow[1]
	box.add_child(_progress_bar)

	_result = _label("", 12, C_GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_result)

	visible = false


func _process(delta: float) -> void:
	if not open or model == null:
		return
	var raw := Input.is_action_pressed("interact") or Input.is_physical_key_pressed(KEY_SPACE)
	if not raw:
		_armed = true
	var holding := raw and _armed
	if holding and not _hold_was:
		model.press()
	_hold_was = holding
	model.update(delta, holding)
	_sync()

	if model.is_finished():
		_close_left -= delta
		if _close_left <= 0.0:
			_finish_up()
		elif holding and model.phase == SalvageLib.Phase.DONE:
			# 收工了还按着：直接关，不用干等。
			_close_left = 0.0


func begin() -> void:
	model = SalvageLib.new()
	model.start()
	open = true
	_hold_was = false
	_armed = false
	_close_left = 2.4
	_result.text = ""
	_sync()
	visible = true


func is_open() -> bool:
	return open


func _sync() -> void:
	if model == null:
		return
	_depth_bar.value = model.depth
	_depth_text.text = "深度 %d%%%s" % [int(model.depth * 100.0),
		"（钩子没到底，产出会打折）" if model.shallow else ""]
	_tension.tension = model.tension
	_tension.hot = model.tension >= SNAP
	_tension.queue_redraw()
	_progress_bar.value = model.progress
	_progress_text.text = "收线 %d%% · 准度 %d%%" % [int(model.progress * 100.0),
		int(model.accuracy() * 100.0)]

	match model.phase:
		SalvageLib.Phase.DROP:
			_hint.text = "按 E 停住钩子"
			_hint.add_theme_color_override("font_color", C_TEXT)
		SalvageLib.Phase.REEL:
			_hint.text = "按住 E 收线 · 松开放线"
			var off: float = model.tension_offset()
			_hint.add_theme_color_override("font_color",
				C_GOOD if off == 0.0 else (C_BAD if off > 0.0 else C_WARN))
		SalvageLib.Phase.DONE:
			_hint.text = "收工"
			_hint.add_theme_color_override("font_color", C_GOOD)
			var parts := PackedStringArray()
			var haul: Dictionary = model.haul()
			for k in haul.keys():
				parts.append("%s +%d" % [ItemDB.label(str(k)), int(haul[k])])
			_result.add_theme_color_override("font_color", C_GOOD)
			_result.text = "拖上来了：" + "   ".join(parts)
		SalvageLib.Phase.FAILED:
			_hint.text = "断线"
			_hint.add_theme_color_override("font_color", C_BAD)
			_result.add_theme_color_override("font_color", C_BAD)
			_result.text = model.reason + "。冷却后可以再来。"


func _finish_up() -> void:
	var haul: Dictionary = model.haul()
	var ok: bool = model.phase == SalvageLib.Phase.DONE
	open = false
	visible = false
	model = null
	finished.emit(haul, ok)


func _unhandled_input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			# 中途退出：当作这一趟放弃（不给产出、也不进冷却，免得罚玩家）。
			open = false
			visible = false
			model = null
			finished.emit({}, false)
			get_viewport().set_input_as_handled()


func _make_bar(fill_color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.24, 0.30, 0.88)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return [bar, fill]


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	s.shadow_color = Color(0.0, 0.05, 0.10, 0.30)
	s.shadow_size = 8
	return s
