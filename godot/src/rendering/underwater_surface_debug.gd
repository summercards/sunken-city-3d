extends CanvasLayer
class_name UnderwaterSurfaceDebug
## 潜水状态下的 P 键水下海面调试工具。
## 这是表现调参器，不是水位/太阳/潜水状态的第二个所有者：
## - 可写值来自 UnderwaterSurfaceParams，统一写入活动海面 ShaderMaterial。
## - 配置只保存到 user://underwater_surface.cfg，不改 water.tres。
## - 活动地图只提供 surface materials 与运行时只读快照。

const Params = preload("res://src/rendering/underwater_surface_params.gd")
const UiFontLib = preload("res://src/ui/ui_font.gd")
const CFG_PATH := "user://underwater_surface.cfg"
const CFG_SECTION := "underwater_surface"
const PANEL_WIDTH := 430.0
const PANEL_TOP := 74.0
const ROW_NAME_W := 128.0
const VALUE_W := 66.0

var _font: Font
var _root: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _status: Label
var _runtime_label: Label
var _rows: Dictionary = {}
var _values: Dictionary = {}
var _saved_values: Dictionary = {}
var _spec: Dictionary = {}
var _runtime: Node
var _syncing := false
var _open := false

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))
	_spec = Params.flat()
	_values = Params.defaults()
	_load_saved_values()
	_build()
	visible = false

func bind_runtime(runtime: Node) -> void:
	_runtime = runtime
	_sync_input_block()
	_apply_all()
	_refresh_runtime()
	if _open:
		_flash("已连接：" + _runtime_label_text())

func clear_runtime() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.remove_meta("underwater_surface_debug_open")
	_runtime = null
	_open = false
	visible = false
	_refresh_runtime()

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_P and _runtime != null:
		set_open(not _open)
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE and _open:
		set_open(false)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	_open = open and _runtime != null
	visible = _open
	_sync_input_block()
	if _open:
		_refresh_all_widgets()
		_refresh_runtime()
	else:
		_save_values()

func is_open() -> bool:
	return _open

func _sync_input_block() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.set_meta("underwater_surface_debug_open", _open)

func _process(_delta: float) -> void:
	if _open:
		_refresh_runtime()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.position = Vector2(18, PANEL_TOP)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(_panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_panel.add_child(_body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_body.add_child(head)
	head.add_child(_label("水下海面", 14, Color("#eafaff")))
	var hint := _label("P 键 · 只在潜水时可用", 9, Color(0.58, 0.82, 0.87, 0.8))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(hint)
	var close := _button("关闭", func() -> void: set_open(false))
	close.custom_minimum_size = Vector2(48, 24)
	head.add_child(close)

	_body.add_child(_separator())
	_runtime_label = _label("运行时真值：未连接", 9, Color(0.70, 0.90, 0.88, 0.86))
	_runtime_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_runtime_label)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 520)
	_body.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)

	for group in Params.GROUPS:
		_add_group(group)

	_body.add_child(_separator())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	_body.add_child(actions)
	actions.add_child(_button("保存当前", _on_save))
	actions.add_child(_button("加载已保存", _on_load))
	actions.add_child(_button("恢复默认", _on_reset))
	actions.add_child(_button("复制参数", _on_copy))
	_status = _label("未保存改动", 9, Color(0.62, 0.80, 0.86, 0.9))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)

func _add_group(group: Dictionary) -> void:
	var head := Button.new()
	head.text = "▾  " + String(group.label)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_override("font", _font)
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0, 0.95))
	head.add_theme_stylebox_override("normal", _button_style(Color(12.0 / 255.0, 38.0 / 255.0, 62.0 / 255.0, 0.75), Color(110.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0, 0.22)))
	head.add_theme_stylebox_override("hover", _button_style(Color(24.0 / 255.0, 74.0 / 255.0, 118.0 / 255.0, 0.9), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.55)))
	head.custom_minimum_size = Vector2(0, 22)
	head.focus_mode = Control.FOCUS_NONE
	_content.add_child(head)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_content.add_child(box)
	var note := _label(String(group.get("note", "")), 9, Color(0.60, 0.80, 0.88, 0.72))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	for row in group.rows:
		_add_row(box, row)
	head.pressed.connect(func() -> void:
		box.visible = not box.visible
		head.text = ("▾  " if box.visible else "▸  ") + String(group.label))

func _add_row(parent: VBoxContainer, spec: Dictionary) -> void:
	var key := String(spec.key)
	match String(spec.kind):
		"float": _add_float_row(parent, spec)
		"color": _add_color_row(parent, spec)
		"vec2": _add_vec2_row(parent, spec)
		_:
			push_error("UnderwaterSurfaceDebug unsupported row kind: " + String(spec.kind))
	_rows[key] = _rows.get(key, {})

func _add_float_row(parent: VBoxContainer, spec: Dictionary) -> void:
	var key := String(spec.key)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	parent.add_child(line)
	line.add_child(_name_label(spec))
	var slider := _slider(float(spec.min), float(spec.max), float(spec.step))
	line.add_child(slider)
	var value := _value_label()
	line.add_child(value)
	var fmt := String(spec.get("fmt", "%.2f"))
	var unit := String(spec.get("unit", ""))
	slider.value_changed.connect(func(v: float) -> void:
		value.text = fmt % v + unit
		if not _syncing:
			_set_value(key, v, false))
	slider.drag_ended.connect(func(_changed: bool) -> void:
		if not _syncing:
			_save_values())
	_rows[key] = {"slider": slider, "value": value, "fmt": fmt, "unit": unit}
	_refresh_widget(key)

func _add_color_row(parent: VBoxContainer, spec: Dictionary) -> void:
	var key := String(spec.key)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	parent.add_child(line)
	line.add_child(_name_label(spec))
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(64, 20)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE
	line.add_child(picker)
	var value := _value_label()
	line.add_child(value)
	picker.color_changed.connect(func(c: Color) -> void:
		value.text = c.to_html(false).trim_prefix("#")
		if not _syncing:
			_set_value(key, c, false)
			_save_values())
	_rows[key] = {"picker": picker, "value": value}
	_refresh_widget(key)

func _add_vec2_row(parent: VBoxContainer, spec: Dictionary) -> void:
	var key := String(spec.key)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 2)
	parent.add_child(holder)
	var title := _name_label(spec)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(title)
	var sliders: Array[HSlider] = []
	var values: Array[Label] = []
	var labels: Array = spec.get("sub", ["X", "Y"])
	for i in 2:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		holder.add_child(line)
		var sub := _label(String(labels[i]), 9, Color(0.66, 0.84, 0.90, 0.85))
		sub.custom_minimum_size = Vector2(ROW_NAME_W - 24, 0)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(sub)
		var slider := _slider(float(spec.min), float(spec.max), float(spec.step))
		line.add_child(slider)
		var value := _value_label()
		line.add_child(value)
		sliders.append(slider)
		values.append(value)
		var index := i
		slider.value_changed.connect(func(v: float) -> void:
			value.text = "%.2f" % v
			if not _syncing:
				_set_vec2_component(key, index, v, false))
		slider.drag_ended.connect(func(_changed: bool) -> void:
			if not _syncing:
				_save_values())
	_rows[key] = {"sliders": sliders, "values": values}
	_refresh_widget(key)

func _set_vec2_component(key: String, index: int, value: float, save_now: bool) -> void:
	var current: Vector2 = _values.get(key, Vector2.ZERO)
	current[index] = value
	_set_value(key, current, save_now)

func _set_value(key: String, value: Variant, save_now: bool) -> void:
	_values[key] = value
	_apply_key(key)
	_status.text = "未保存改动 · %s" % key
	if save_now:
		_save_values()

func _apply_key(key: String) -> void:
	if _runtime == null or not is_instance_valid(_runtime):
		return
	var materials: Array = _surface_materials()
	for material in materials:
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(key, _values[key])

func _apply_all() -> void:
	if _runtime == null or not is_instance_valid(_runtime):
		return
	for key in _values.keys():
		_apply_key(String(key))

func _surface_materials() -> Array:
	if _runtime == null or not is_instance_valid(_runtime):
		return []
	if _runtime.has_method("underwater_surface_debug_materials"):
		return _runtime.call("underwater_surface_debug_materials")
	return []

func _refresh_all_widgets() -> void:
	_syncing = true
	for key in _rows.keys():
		_refresh_widget(String(key))
	_syncing = false

func _refresh_widget(key: String) -> void:
	if not _rows.has(key) or not _values.has(key):
		return
	var row: Dictionary = _rows[key]
	var value: Variant = _values[key]
	if row.has("slider"):
		var slider: HSlider = row.slider
		slider.set_value_no_signal(float(value))
		row.value.text = String(row.fmt) % float(value) + String(row.unit)
	elif row.has("picker"):
		var color := value as Color
		row.picker.color = color
		row.value.text = color.to_html(false).trim_prefix("#")
	elif row.has("sliders"):
		var vector := value as Vector2
		for i in 2:
			(row.sliders[i] as HSlider).set_value_no_signal(vector[i])
			(row.values[i] as Label).text = "%.2f" % vector[i]

func _load_saved_values() -> void:
	_saved_values = {}
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	for key in _spec.keys():
		if cfg.has_section_key(CFG_SECTION, key):
			_saved_values[key] = cfg.get_value(CFG_SECTION, key)
	for key in _saved_values.keys():
		if _values.has(key):
			_values[key] = _saved_values[key]

func _save_values() -> void:
	if _values.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value(CFG_SECTION, "version", 1)
	for key in _values.keys():
		cfg.set_value(CFG_SECTION, String(key), _values[key])
	var err := cfg.save(CFG_PATH)
	if err == OK:
		_saved_values = _values.duplicate(true)
		_status.text = "已保存全部 %d 项 · %s" % [_values.size(), CFG_PATH]
	else:
		_status.text = "保存失败：" + error_string(err)

func _on_save() -> void:
	_save_values()

func _on_load() -> void:
	_load_saved_values()
	_apply_all()
	_refresh_all_widgets()
	_status.text = "已加载保存值 · 全部 %d 项" % _values.size()

func _on_reset() -> void:
	_values = Params.defaults()
	_apply_all()
	_refresh_all_widgets()
	_save_values()
	_status.text = "已恢复默认并保存"

func _on_copy() -> void:
	var lines := PackedStringArray()
	for key in _spec.keys():
		if _values.has(key):
			lines.append("%s = %s" % [key, var_to_str(_values[key])])
	DisplayServer.clipboard_set("\n".join(lines))
	_status.text = "已复制全部 %d 项参数" % lines.size()

func _refresh_runtime() -> void:
	if _runtime_label == null:
		return
	_runtime_label.text = "运行时真值：" + _runtime_label_text()

func _runtime_label_text() -> String:
	if _runtime == null or not is_instance_valid(_runtime):
		return "未连接"
	if _runtime.has_method("underwater_surface_debug_runtime"):
		var data: Dictionary = _runtime.call("underwater_surface_debug_runtime")
		return "%s · 水位 %.2fm · 观察深度 %.2fm · 日光 %.2f（只读）" % [
			String(data.get("map", "水下地图")), float(data.get("water_level", 0.0)),
			float(data.get("view_depth", 0.0)), float(data.get("sun_strength", 0.0))]
	return "已连接 · ShaderMaterial %d 个 · 水位/深度/太阳为运行时只读" % _surface_materials().size()

func _flash(text: String) -> void:
	if _status != null:
		_status.text = text

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _name_label(spec: Dictionary) -> Label:
	var label := _label(String(spec.label), 10, Color(0.90, 0.97, 1.0, 0.92))
	label.custom_minimum_size = Vector2(ROW_NAME_W, 0)
	label.tooltip_text = String(spec.get("hint", ""))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label

func _value_label() -> Label:
	var label := _label("0.00", 9, Color(0.99, 0.92, 0.72, 1.0))
	label.custom_minimum_size = Vector2(VALUE_W, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

func _slider(lo: float, hi: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(110, 16)
	slider.focus_mode = Control.FOCUS_NONE
	slider.scrollable = false
	slider.add_theme_stylebox_override("slider", _track_style())
	slider.add_theme_stylebox_override("grabber_area", _grabber_style(Color(0.55, 0.95, 0.85, 0.85)))
	return slider

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 10)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 24)
	button.pressed.connect(callback)
	button.add_theme_stylebox_override("normal", _button_style(Color(14.0 / 255.0, 40.0 / 255.0, 64.0 / 255.0, 0.9), Color(110.0 / 255.0, 190.0 / 255.0, 200.0 / 255.0, 0.30)))
	button.add_theme_stylebox_override("hover", _button_style(Color(32.0 / 255.0, 90.0 / 255.0, 138.0 / 255.0, 0.92), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.6)))
	button.add_theme_color_override("font_color", Color("#e9f8ff"))
	return button

func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.08, 0.13, 0.96)
	box.border_color = Color(0.25, 0.75, 0.78, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box

func _track_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.20, 0.27, 0.9)
	box.set_corner_radius_all(4)
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box

func _grabber_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.modulate = Color(0.35, 0.72, 0.75, 0.35)
	return separator
