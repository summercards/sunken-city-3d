extends CanvasLayer
class_name InteractPrompt
## 交互提示：只显示「当前焦点」这一件事。
##
## 旧做法是把每个可点目标都投影到屏幕上（DOM 图标墙），屏幕越挤越难看清。
## 现在世界里只有物件本身，焦点由 Interactor 决定，这里只负责把它说清楚：
##   [E]  采集 · 瓶盖        ▓▓▓▓░░░░

const UiFontLib = preload("res://src/ui/ui_font.gd")
const HINT_COLOR := Color("#354c57")
const BLOCK_COLOR := Color("#995d3d")
const KEY_BG := Color(0.06, 0.30, 0.36, 0.92)
const PANEL_BG := Color(0.03, 0.12, 0.20, 0.74)

var enabled := true
signal action_requested
## 没有交互焦点时也能说的一句话（上船/上岸，SEA-INTERACT-R13）。
## 由 Main 每帧写；这里只负责在「焦点为空」时把它画出来，不判断条件。
var shortcut := ""
var _panel: PanelContainer
var _key_label: Button
var _text: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat
var _font: Font
var _blocked_left := 0.0
var _last_text := ""
var _finish_left := 0.0

## 主动切换焦点时立刻显示新目标，不让上一格的拒绝/成功提示遮住当前选择。
func focus_changed(_spot: Node3D) -> void:
	_finish_left = 0.0
	_blocked_left = 0.0
	_last_text = ""

func celebrate() -> void:
	if not enabled: return
	_finish_left = 1.4
	visible = true
	_bar.value = 1.0
	_fill.bg_color = Color("#ffce75")
	_text.text = "完成啦！"
	_key_label.text = "好啦"
	_key_label.disabled = true
	load("res://src/ui/cozy_ui.gd").reveal(_panel)


func _ready() -> void:
	layer = 11
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -245
	_panel.offset_right = 245
	# 抬高 14 px：底部的「视野 %」徽标贴在同一水平线上，原本两者的边只差 3 px，
	# 在 1280×800 下读起来像一条被劈成两半的横条。
	_panel.offset_top = -252
	_panel.offset_bottom = -164
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _badge_style())
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	_key_label = Button.new()
	_key_label.focus_mode = Control.FOCUS_NONE
	_key_label.text = "操作"
	_key_label.add_theme_font_override("font",_font)
	_key_label.add_theme_font_size_override("font_size",12)
	_key_label.pressed.connect(func() -> void: action_requested.emit())
	badge.add_child(_key_label)

	_text = _label("", 13, HINT_COLOR)
	row.add_child(_text)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_stylebox_override("background", _bar_bg())
	_fill = StyleBoxFlat.new()
	_fill.bg_color = Color(0.53, 0.95, 0.83, 0.95)
	_fill.corner_radius_top_left = 2
	_fill.corner_radius_top_right = 2
	_fill.corner_radius_bottom_left = 2
	_fill.corner_radius_bottom_right = 2
	_bar.add_theme_stylebox_override("fill", _fill)
	box.add_child(_bar)

	visible = false


func _process(delta: float) -> void:
	_finish_left = maxf(0.0,_finish_left-delta)
	if _blocked_left > 0.0:
		_blocked_left -= delta
		if _blocked_left <= 0.0 and _text != null:
			_text.add_theme_color_override("font_color", HINT_COLOR)
			_text.text = _last_text


## 每帧从 Interactor 同步显示状态。
func update_from(actor: Node) -> void:
	if not enabled:
		visible = false
		return
	if _finish_left > 0.0: return
	_fill.bg_color = Color("#8edbb3")
	if actor == null or not actor.active or actor.target == null:
		# 交互焦点为空时，仍要说清「现在按 E 会做什么」（上下船）。
		if shortcut != "":
			if not visible:
				visible = true
			if _blocked_left <= 0.0:
				_text.add_theme_color_override("font_color", HINT_COLOR)
				_last_text = shortcut
				_text.text = shortcut
			_key_label.disabled = false
			_key_label.text = "E"
			_bar.value = 0.0
			# 没在按住时不要留一条空槽：它会读成「进度 0%，还差一点」。
			# 只有真的在按（progress > 0）才把进度条显出来。
			_bar.visible = false
			return
		if visible:
			visible = false
			_bar.value = 0.0
		return
	if not visible:
		visible = true
	var spot: Node3D = actor.target
	if _blocked_left <= 0.0:
		_text.add_theme_color_override("font_color", HINT_COLOR)
		_last_text = spot.focus_text()
		if spot.is_in_group("farm_plots"): _last_text += "\n按住 E 操作 · Q / Shift+Q 切换附近地格"
		_text.text = _last_text
	_key_label.disabled = actor.progress()>0.0
	# 徽标只写「按哪个键」。以前这里写 `spot.verb`，于是画面上是
	# 「采集  采集 · 贝壳」—— 同一个词出现两次，还看不出要按 E。
	# 动词已经在 `focus_text()` 里了，这里只负责说清键位。
	_key_label.text = "进行中" if actor.progress()>0.0 else "E"
	_bar.value = actor.progress()
	_bar.visible = actor.progress() > 0.0


## 被规则挡住时短暂改色显示原因。
func flash_blocked(reason: String) -> void:
	if not enabled: return
	if _text == null:
		return
	visible = true
	_blocked_left = 1.6
	_text.add_theme_color_override("font_color", BLOCK_COLOR)
	_text.text = reason
	_bar.value = 0.0


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
	s.bg_color = PANEL_BG
	s.border_color = Color(0.42, 0.88, 0.82, 0.34)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _badge_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = KEY_BG
	s.border_color = Color(0.55, 0.95, 0.86, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


func _bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.24, 0.30, 0.85)
	s.set_corner_radius_all(2)
	return s
