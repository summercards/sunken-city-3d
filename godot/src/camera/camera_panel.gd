extends CanvasLayer
class_name CameraPanel
## 相机调试面板（C 键）。
##
## 用途是「把镜头一键送到最近 / 最远，再慢慢找中间位置」——
## 试玩时最常见的诉求不是某个精确数字，而是想从远处看全貌、再扑到近处看细节。
##
## 和滤镜面板（P）一样，它只是调试/观察工具，不影响玩法：
##   · 四个档位按钮：最近（zoom_min）/ 中景 / 远景 / 最远（zoom_max）；
##   · 「默认机位」回到场景里存的 distance（main.tscn 的值）；
##   · 滑杆连续调，±10m 微调按钮给手感；
##   · 快捷键 Z = 最近、X = 最远，面板关着也能用。
##
## 距离写的是 `OrbitCam.set_distance()`，即时生效（不做平滑），
## 因为「定位」这个动作需要所见即所得；连续拖动滑杆同样是即时。

## 距离变化时发出去（HUD 用它闪一下百分比，和滚轮缩放共用同一套反馈）。
signal distance_changed(distance: float)

const UiFontLib = preload("res://src/ui/ui_font.gd")
const PANEL_W := 300.0
const MARGIN := 18.0
const TOP := 92.0
## 中景/远景的插值位置（0=最近，1=最远）。
const MID_RATIO := 0.45
const FAR_RATIO := 0.72

var cam: OrbitCam = null
## 场景里的原始距离（「默认机位」回到这里）。
var _default_distance := 106.0

var _panel: PanelContainer
var _slider: HSlider
var _readout: Label
var _status: Label
var _font: Font
var _syncing := false
## 上一次显示的米数：滚轮/捏合在面板外缩放时，读数要跟着走。
var _last_shown := -1.0


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))
	_build()
	visible = false
	get_viewport().size_changed.connect(_place)


func _process(_delta: float) -> void:
	# 面板开着的时候，滚轮/捏合/键盘缩放也要反映到读数与滑杆上。
	if not visible or cam == null:
		return
	if absf(cam.distance - _last_shown) > 0.05:
		_sync()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != 0 else key.physical_keycode
	match code:
		KEY_C:
			set_open(not visible)
		KEY_Z:
			snap_to("near")
		KEY_X:
			snap_to("far")
		_:
			return
	get_viewport().set_input_as_handled()


## 由 main 调用：接上相机并把当前距离记成「默认机位」。
func bind_camera(c: OrbitCam) -> void:
	cam = c
	if cam == null:
		return
	_default_distance = clampf(cam.distance, cam.zoom_min, cam.zoom_max)
	_sync()
	if visible:
		_place()


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	visible = open
	if open:
		_sync()
		_place()


# ---- 定位 -------------------------------------------------------------------

## 一键定位。kind: near / mid / far / farthest / default / 0~100 的百分比字符串。
func snap_to(kind: String) -> void:
	if cam == null:
		return
	var lo := cam.zoom_min
	var hi := cam.zoom_max
	var target := cam.distance
	match kind:
		"near", "nearest", "min":
			target = lo
		"mid":
			target = lerpf(lo, hi, MID_RATIO)
		"far":
			target = lerpf(lo, hi, FAR_RATIO)
		"farthest", "max":
			target = hi
		"default":
			target = _default_distance
		_:
			# 允许 --zoom=60% 这种写法：按区间百分比定位。
			var text := kind.trim_suffix("%")
			if text.is_valid_float():
				target = lerpf(lo, hi, clampf(float(text) / 100.0, 0.0, 1.0))
			else:
				return
	set_distance_m(target)


## 直接给米数（夹在 zoom_min..zoom_max 之间）。
func set_distance_m(d: float) -> void:
	if cam == null:
		return
	cam.set_distance(d)
	_sync()
	distance_changed.emit(cam.distance)


func distance_m() -> float:
	return cam.distance if cam != null else 0.0


# ---- UI ---------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "CameraPanelBox"
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 7)
	_panel.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	head.add_child(_label("相机", 13, Color("#eafaff")))
	var close := _button("关闭",func() -> void: set_open(false))
	head.add_child(close)

	body.add_child(_separator())

	_readout = _label("106 m", 22, Color(0.99, 0.92, 0.72, 1.0))
	_readout.name = "Readout"
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_readout)

	_slider = HSlider.new()
	_slider.name = "Distance"
	_slider.min_value = 9.0
	_slider.max_value = 190.0
	_slider.step = 0.5
	_slider.custom_minimum_size = Vector2(PANEL_W - 24.0, 18)
	_slider.add_theme_stylebox_override("slider", _track_style())
	_slider.add_theme_stylebox_override("grabber_area", _grabber_style(Color(0.55, 0.95, 0.85, 0.85)))
	_slider.value_changed.connect(_on_slider)
	body.add_child(_slider)

	var presets := HBoxContainer.new()
	presets.name = "Presets"
	presets.add_theme_constant_override("separation", 5)
	body.add_child(presets)
	presets.add_child(_button("最近", func() -> void: snap_to("near")))
	presets.add_child(_button("中景", func() -> void: snap_to("mid")))
	presets.add_child(_button("远景", func() -> void: snap_to("far")))
	presets.add_child(_button("最远", func() -> void: snap_to("farthest")))

	var fine := HBoxContainer.new()
	fine.add_theme_constant_override("separation", 5)
	body.add_child(fine)
	fine.add_child(_button("−10m", func() -> void: set_distance_m(distance_m() - 10.0)))
	fine.add_child(_button("默认机位", func() -> void: snap_to("default")))
	fine.add_child(_button("+10m", func() -> void: set_distance_m(distance_m() + 10.0)))

	_status = _label("", 9, Color(0.62, 0.80, 0.86, 0.85))
	_status.name = "Status"
	body.add_child(_status)

	var keys := _label("Z 最近 · X 最远 · 拖动滑杆连续调", 9, Color(0.55, 0.72, 0.80, 0.75))
	keys.name = "Keys"
	body.add_child(keys)


func _place() -> void:
	if _panel == null or not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	# 显式给尺寸：PanelContainer 在普通 Control 下不会自己撑到 custom_minimum_size，
	# 不写这一行它只有内容最小宽度，右边按钮会被挤成空块。
	_panel.size = Vector2(PANEL_W, maxf(_panel.get_combined_minimum_size().y, 10.0))
	_panel.position = Vector2(vp.x - PANEL_W - MARGIN, TOP)


func _sync() -> void:
	if cam == null or _slider == null:
		return
	_syncing = true
	_slider.min_value = cam.zoom_min
	_slider.max_value = cam.zoom_max
	_slider.step = 0.5
	_slider.set_value_no_signal(clampf(cam.distance, cam.zoom_min, cam.zoom_max))
	_syncing = false
	_last_shown = cam.distance
	_readout.text = "%d m" % int(round(cam.distance))
	var pct := cam.zoom_ratio() * 100.0
	_status.text = "最近 %d m · 最远 %d m · 当前 %d%%" % [
		int(round(cam.zoom_min)), int(round(cam.zoom_max)), int(round(pct))]
	_place()


func _on_slider(v: float) -> void:
	if _syncing:
		return
	set_distance_m(v)


# ---- 小工具（与滤镜面板同一套观感）------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", Color("#e9f8ff"))
	b.add_theme_stylebox_override("normal", _btn_style(Color(18.0 / 255.0, 52.0 / 255.0, 86.0 / 255.0, 0.8),
		Color(120.0 / 255.0, 200.0 / 255.0, 210.0 / 255.0, 0.28)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.9),
		Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.7)))
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.42, 0.78, 0.86, 0.22)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(3.0 / 255.0, 14.0 / 255.0, 26.0 / 255.0, 0.88)
	s.border_color = Color(0.34, 0.78, 0.80, 0.42)
	s.set_border_width_all(1)
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_left = 10
	s.corner_radius_bottom_right = 10
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _track_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.24, 0.32, 0.9)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


func _grabber_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	return s


func _btn_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1)
	s.corner_radius_top_left = 7
	s.corner_radius_top_right = 7
	s.corner_radius_bottom_left = 7
	s.corner_radius_bottom_right = 7
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
