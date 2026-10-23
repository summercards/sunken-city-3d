extends CanvasLayer
class_name ColorGradePanel
## 实时滤镜面板（P 键开关）。
##
## 改的是 `WorldEnvironment` 上那一个 Environment 的调整项，也就是整幅画面的最终调色：
##   曝光 → tonemap_exposure
##   亮度 / 对比度 / 饱和度 → adjustment_brightness / contrast / saturation
##
## 参考 ShellStorm2 的调试面板：拖动即时生效、可一键复位、可把数值复制出来
## 贴回场景资源。这里额外多做一件事 —— 数值会记在 `user://filter.cfg`，
## 下次启动仍然是你调好的样子（不然每次重启都要重调）。
##
## 场景里的默认值来自 `assets/materials/world_env.tres`，可以在编辑器里直接改；
## 面板的「复位」回到的就是那份默认值，不是硬编码的数字。

const UiFontLib = preload("res://src/ui/ui_font.gd")
const CFG_PATH := "user://filter.cfg"

const EXPOSURE_MIN := 0.4
const EXPOSURE_MAX := 2.0
const ADJ_MIN := 0.0
const ADJ_MAX := 2.0

var _env: Environment
var _defaults := {}
var _saved := {}
var _rows := {}
var _status: Label
var _font: Font
var _panel: PanelContainer
var _body: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))
	_build()
	visible = false
	# 先读盘：读档值要盖回场景默认值，否则每次启动都回到 1.0。
	call_deferred("_apply_saved_on_start")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != 0 else key.physical_keycode
	if code != KEY_P:
		return
	set_open(not visible)
	get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	visible = open
	if open:
		_ensure_env()
		_sync_from_env()
		_refresh_labels()
	else:
		_save_cfg()


## 供调试参数调用：`--grade` 启动就打开，`--grade=1.1,1.06,1.03` 直接套一组数。
func set_values(exposure: float, brightness: float, contrast: float, saturation: float) -> void:
	_ensure_env()
	if _env == null:
		return
	_env.tonemap_exposure = clampf(exposure, EXPOSURE_MIN, EXPOSURE_MAX)
	_env.adjustment_enabled = true
	_env.adjustment_brightness = clampf(brightness, ADJ_MIN, ADJ_MAX)
	_env.adjustment_contrast = clampf(contrast, ADJ_MIN, ADJ_MAX)
	_env.adjustment_saturation = clampf(saturation, ADJ_MIN, ADJ_MAX)
	_sync_from_env()
	_refresh_labels()


# ---- 环境解析 ---------------------------------------------------------------

func _ensure_env() -> void:
	if _env != null:
		return
	var we: WorldEnvironment = null
	var scene := get_tree().current_scene
	if scene != null:
		we = scene.get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	if we == null:
		# 兜底：场景没按约定摆放时，找树里第一个。
		for node in get_tree().get_nodes_in_group("world_environment"):
			we = node as WorldEnvironment
			if we != null:
				break
	if we == null:
		for node in get_tree().root.get_children():
			we = _find_env_recursive(node)
			if we != null:
				break
	if we != null and we.environment != null:
		_env = we.environment
		_defaults = _snapshot(_env)


func _find_env_recursive(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for c in node.get_children():
		var found := _find_env_recursive(c)
		if found != null:
			return found
	return null


func _snapshot(env: Environment) -> Dictionary:
	return {
		"exposure": env.tonemap_exposure,
		"brightness": env.adjustment_brightness,
		"contrast": env.adjustment_contrast,
		"saturation": env.adjustment_saturation,
	}


# ---- UI ---------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	# 放到标题下面：左上角是品牌区，压上去会两边都看不清。
	_panel.position = Vector2(18, 92)
	_panel.custom_minimum_size = Vector2(316, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	_panel.add_child(_body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_body.add_child(head)
	head.add_child(_label("滤镜", 13, Color("#eafaff")))
	var close := _button("关闭",func() -> void: set_open(false))
	head.add_child(close)

	_body.add_child(_separator())

	_add_row("exposure", "曝光", EXPOSURE_MIN, EXPOSURE_MAX, 0.01)
	_add_row("brightness", "亮度", ADJ_MIN, ADJ_MAX, 0.01)
	_add_row("contrast", "对比度", ADJ_MIN, ADJ_MAX, 0.01)
	_add_row("saturation", "饱和度", ADJ_MIN, ADJ_MAX, 0.01)

	_body.add_child(_separator())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 5)
	_body.add_child(buttons)
	buttons.add_child(_button("复位", _on_reset))
	buttons.add_child(_button("复制参数", _on_copy))
	buttons.add_child(_button("写入场景", _on_save_to_scene))

	_status = _label("P 开关 · 拖动即时生效，数值会记住", 9, Color(0.62, 0.80, 0.86, 0.85))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(292, 0)
	_body.add_child(_status)


func _add_row(key: String, title: String, lo: float, hi: float, step: float) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	_body.add_child(line)

	var name_label := _label(title, 11, Color(0.90, 0.97, 1.0, 0.92))
	name_label.custom_minimum_size = Vector2(52, 0)
	line.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(150, 18)
	slider.add_theme_stylebox_override("slider", _track_style())
	slider.add_theme_stylebox_override("grabber_area", _grabber_style(Color(0.55, 0.95, 0.85, 0.85)))
	line.add_child(slider)

	var value := _label("1.00", 10, Color(0.99, 0.92, 0.72, 1.0))
	value.custom_minimum_size = Vector2(42, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)

	slider.value_changed.connect(func(v: float) -> void:
		_write(key, v)
		value.text = "%.2f" % v)
	slider.drag_ended.connect(func(_changed: bool) -> void: _save_cfg())
	_rows[key] = {"slider": slider, "value": value}


func _write(key: String, v: float) -> void:
	_ensure_env()
	if _env == null:
		return
	match key:
		"exposure":
			_env.tonemap_exposure = v
		"brightness":
			_env.adjustment_enabled = true
			_env.adjustment_brightness = v
		"contrast":
			_env.adjustment_enabled = true
			_env.adjustment_contrast = v
		"saturation":
			_env.adjustment_enabled = true
			_env.adjustment_saturation = v


func _sync_from_env() -> void:
	_ensure_env()
	if _env == null or _rows.is_empty():
		return
	var snap := _snapshot(_env)
	for key in _rows.keys():
		var row: Dictionary = _rows[key]
		var slider: HSlider = row.slider
		slider.set_value_no_signal(float(snap.get(key, 1.0)))


func _refresh_labels() -> void:
	if _rows.is_empty():
		return
	for key in _rows.keys():
		var row: Dictionary = _rows[key]
		var slider: HSlider = row.slider
		var label: Label = row.value
		label.text = "%.2f" % slider.value
	if _env == null:
		_status.text = "找不到 WorldEnvironment，滤镜无法写入"


func _on_reset() -> void:
	_ensure_env()
	if _env == null:
		return
	_env.adjustment_enabled = true
	_env.tonemap_exposure = float(_defaults.get("exposure", 0.96))
	_env.adjustment_brightness = float(_defaults.get("brightness", 1.0))
	_env.adjustment_contrast = float(_defaults.get("contrast", 1.0))
	_env.adjustment_saturation = float(_defaults.get("saturation", 1.0))
	_sync_from_env()
	_refresh_labels()
	_save_cfg()
	_flash("已回到场景默认值")


## 复制成能直接贴进代码 / 文档的一行。
func _on_copy() -> void:
	_ensure_env()
	if _env == null:
		return
	var text := "exposure=%.2f brightness=%.2f contrast=%.2f saturation=%.2f" % [
		_env.tonemap_exposure, _env.adjustment_brightness,
		_env.adjustment_contrast, _env.adjustment_saturation]
	DisplayServer.clipboard_set(text)
	_flash("已复制：" + text)


## 把当前参数写回 assets/materials/world_env.tres：
## 下次启动、以及编辑器里打开的 Environment 都是这套值。
## 只在编辑器/开发环境可用（导出版 res:// 是只读的）。
func _on_save_to_scene() -> void:
	_ensure_env()
	if _env == null:
		return
	var path := "res://assets/materials/world_env.tres"
	if OS.has_feature("template"):
		_flash("导出版无法写回 res://，请用「复制参数」")
		return
	var err := ResourceSaver.save(_env, path)
	if err == OK:
		_save_cfg()
		_flash("已写入 %s（重开游戏生效）" % path)
	else:
		_flash("写入失败：%s" % error_string(err))


func _flash(text: String) -> void:
	if _status == null:
		return
	_status.text = text


# ---- 持久化 -----------------------------------------------------------------

func _apply_saved_on_start() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	_ensure_env()
	if _env == null:
		return
	_saved = {
		"exposure": float(cfg.get_value("filter", "exposure", _env.tonemap_exposure)),
		"brightness": float(cfg.get_value("filter", "brightness", _env.adjustment_brightness)),
		"contrast": float(cfg.get_value("filter", "contrast", _env.adjustment_contrast)),
		"saturation": float(cfg.get_value("filter", "saturation", _env.adjustment_saturation)),
	}
	_env.tonemap_exposure = _saved.exposure
	_env.adjustment_enabled = true
	_env.adjustment_brightness = _saved.brightness
	_env.adjustment_contrast = _saved.contrast
	_env.adjustment_saturation = _saved.saturation


func _save_cfg() -> void:
	_ensure_env()
	if _env == null:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("filter", "exposure", _env.tonemap_exposure)
	cfg.set_value("filter", "brightness", _env.adjustment_brightness)
	cfg.set_value("filter", "contrast", _env.adjustment_contrast)
	cfg.set_value("filter", "saturation", _env.adjustment_saturation)
	cfg.save(CFG_PATH)


# ---- 小工具 -----------------------------------------------------------------

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
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
