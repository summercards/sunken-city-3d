extends CanvasLayer
## 独立第三人称潜水 HUD：只依赖 dive session 与地图公开状态，不依赖 Main。
const Cozy = preload("res://src/ui/cozy_ui.gd")

const PANEL := Color(0.035, 0.16, 0.20, 0.86)
const PANEL_SOFT := Color(0.035, 0.16, 0.20, 0.70)
const CREAM := Color("#fff9e8")
const MUTED := Color(0.78, 0.90, 0.88, 0.84)
const TRACK := Color(0.02, 0.09, 0.12, 0.72)

var session: Node3D
var command_buttons: Dictionary = {}
var menu_buttons: Dictionary = {}
var _status: Label
var _menu: PanelContainer
var _return_button: Button
var _oxygen_bar: ProgressBar
var _oxygen_label: Label
var _depth_label: Label
var _lamp_label: Label
var _motion_label: Label
var _camera_label: Label
var _notice: Label
var _notice_left := 0.0
var _oxygen := -1.0
var _depth := 0.0
var _lamp_on := false
var _found := 0
var _total := 0

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	if is_instance_valid(session) and session.has_signal("message"):
		session.message.connect(_on_message)

func _build_hud() -> void:
	var root := Control.new()
	root.name = "DiveHudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var map_panel := _panel(PANEL, Vector2(360, 148))
	map_panel.position = Vector2(24, 22)
	root.add_child(map_panel)
	var map_body := VBoxContainer.new()
	map_body.add_theme_constant_override("separation", 3)
	map_panel.add_child(map_body)
	var map_tag := _label("UNDERWATER / 潜水状态", 14, MUTED)
	map_body.add_child(map_tag)
	_status = _label("等待地图状态", 23, CREAM)
	_status.name = "MapStatus"
	map_body.add_child(_status)
	_motion_label = _label("游动状态 · 待机", 17, MUTED)
	map_body.add_child(_motion_label)
	_depth_label = _label("水深 0m", 17, CREAM)
	map_body.add_child(_depth_label)
	_lamp_label = _label("头灯 · 关闭", 17, MUTED)
	map_body.add_child(_lamp_label)
	_camera_label = _label("", 15, MUTED)
	_camera_label.visible = false
	map_body.add_child(_camera_label)
	_notice = _label("", 16, Cozy.GOLD)
	_notice.name = "MessageNotice"
	_notice.visible = false
	map_body.add_child(_notice)

	var command_panel := _panel(PANEL_SOFT, Vector2(568, 78))
	command_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	command_panel.offset_left = -592.0
	command_panel.offset_top = 22.0
	command_panel.offset_right = -24.0
	command_panel.offset_bottom = 100.0
	root.add_child(command_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	command_panel.add_child(top)
	for entry in [["surface", "上浮", _surface], ["rise", "上游", _rise], ["descend", "下潜", _descend], ["lamp", "头灯", _lamp], ["cancel", "取消游动", _cancel]]:
		var button := _button(entry[1], Vector2(103, 50))
		# 游动热键不可被上次点击留下的按钮焦点吞掉/重复触发。
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[2])
		command_buttons[entry[0]] = button
		top.add_child(button)

	var oxygen_panel := _panel(PANEL, Vector2(326, 88))
	oxygen_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	oxygen_panel.offset_left = 24.0
	oxygen_panel.offset_top = -112.0
	oxygen_panel.offset_right = 350.0
	oxygen_panel.offset_bottom = -24.0
	root.add_child(oxygen_panel)
	var oxygen_body := VBoxContainer.new()
	oxygen_body.add_theme_constant_override("separation", 5)
	oxygen_panel.add_child(oxygen_body)
	var oxygen_head := HBoxContainer.new()
	oxygen_body.add_child(oxygen_head)
	var oxygen_title := _label("氧气余量", 17, CREAM)
	oxygen_head.add_child(oxygen_title)
	_oxygen_label = _label("--%", 19, CREAM)
	_oxygen_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_oxygen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	oxygen_head.add_child(_oxygen_label)
	_oxygen_bar = ProgressBar.new()
	_oxygen_bar.name = "OxygenProgress"
	_oxygen_bar.set_meta("cozy_skip", true)
	_oxygen_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oxygen_bar.custom_minimum_size = Vector2(0, 14)
	_oxygen_bar.show_percentage = false
	_oxygen_bar.min_value = 0.0
	_oxygen_bar.max_value = 1.0
	_oxygen_bar.value = 0.0
	_oxygen_bar.add_theme_stylebox_override("background", _bar_style(TRACK, 7))
	_oxygen_bar.add_theme_stylebox_override("fill", _bar_style(Cozy.TEAL, 7))
	oxygen_body.add_child(_oxygen_bar)

	var hint_panel := _panel(PANEL_SOFT, Vector2(350, 148))
	hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint_panel.offset_left = -374.0
	hint_panel.offset_top = -172.0
	hint_panel.offset_right = -24.0
	hint_panel.offset_bottom = -24.0
	root.add_child(hint_panel)
	var hint_body := VBoxContainer.new()
	hint_body.add_theme_constant_override("separation", 3)
	hint_panel.add_child(hint_body)
	hint_body.add_child(_label("操控提示", 16, Cozy.GOLD))
	var hints := _label("WASD 游动 / E 或空格 上游\nQ 或 Ctrl 下潜 / Shift 加速\n右键 环视 / 滚轮 远近 / F 头灯\n左键短点自动游", 16, CREAM)
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_body.add_child(hints)

	_menu = _panel(Color(0.035, 0.14, 0.18, 0.96), Vector2(292, 188))
	_menu.name = "PauseMenu"
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.offset_left = -146.0
	_menu.offset_top = -94.0
	_menu.offset_right = 146.0
	_menu.offset_bottom = 94.0
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_menu)
	var menu_body := VBoxContainer.new()
	menu_body.add_theme_constant_override("separation", 8)
	_menu.add_child(menu_body)
	var pause_title := _label("潜水已暂停", 24, CREAM)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_body.add_child(pause_title)
	for entry in [["resume", "继续探索", _resume], ["surface", "上浮返回海面", _surface]]:
		var button := _button(entry[1], Vector2(0, 48))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[2])
		menu_buttons[entry[0]] = button
		menu_body.add_child(button)
		if _return_button == null:
			_return_button = button
	_menu.hide()

func _panel(color: Color, minimum: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", Cozy.surface(color, 22))
	return panel

func _button(text: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("cozy_skip", true)
	button.add_theme_font_override("font", Cozy.world_font())
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Cozy.INK)
	button.add_theme_color_override("font_hover_color", Cozy.INK)
	button.add_theme_color_override("font_pressed_color", Cozy.INK)
	button.add_theme_color_override("font_focus_color", Cozy.INK)
	button.add_theme_stylebox_override("normal", Cozy.surface(CREAM, 16))
	button.add_theme_stylebox_override("hover", Cozy.surface(Cozy.GOLD, 16))
	button.add_theme_stylebox_override("pressed", Cozy.surface(Cozy.MINT, 16))
	var focus := Cozy.surface(Color.TRANSPARENT, 16)
	focus.border_color = Cozy.TEAL
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	return button

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Cozy.world_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.01, 0.06, 0.08, 0.60))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("outline_size", 0)
	return label

func _bar_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style

func _on_message(text: String) -> void:
	_notice.text = text
	_notice_left = 3.0

func _process(delta: float) -> void:
	if not is_instance_valid(session): return
	var frozen: bool = bool(session.switching)
	for button in command_buttons.values(): button.disabled = frozen
	for button in menu_buttons.values(): button.disabled = frozen
	if frozen and _menu.visible: _resume()
	if not is_instance_valid(session.runtime):
		return
	if not get_tree().paused:
		_notice_left = maxf(0.0, _notice_left - delta)
	_notice.visible = _notice_left > 0.0
	var map: Node = session.runtime
	if not is_instance_valid(map) or not map.has_method("get"):
		return
	_update_state(map)

func _update_state(map: Node) -> void:
	var air: Variant = map.get("air")
	if air != null and air is Object and air.has_method("ratio"):
		_oxygen = clampf(float(air.ratio()), 0.0, 1.0)
		_lamp_on = bool(air.get("lamp"))
	else:
		_oxygen = -1.0
		_lamp_on = false
	_depth = float(map.get("depth"))
	_found = int(map.discovered_count()) if map.has_method("discovered_count") else 0
	_total = int(map.chest_count()) if map.has_method("chest_count") else 0
	var map_name := str(map.get("map_label"))
	if map_name.is_empty():
		map_name = str(map.get("map_id"))
	var oxygen_percent := roundi(_oxygen * 100.0) if _oxygen >= 0.0 else 0
	var warning := " · 氧气危急" if _oxygen >= 0.0 and _oxygen <= 0.15 else (" · 氧气偏低" if _oxygen >= 0.0 and _oxygen <= 0.30 else "")
	var found_text := "" if _total <= 0 else " · 发现 %d/%d" % [_found, _total]
	_status.text = map_name + found_text + ("\n" + warning.trim_prefix(" · ") if not warning.is_empty() else "")
	_status.add_theme_color_override("font_color", air_color(_oxygen))
	_depth_label.text = "水深 %.0fm" % _depth
	_lamp_label.text = "头灯 · %s" % ("开启" if _lamp_on else "关闭")
	_lamp_label.add_theme_color_override("font_color", Cozy.GOLD if _lamp_on else MUTED)
	_oxygen_label.text = "%d%%" % oxygen_percent if _oxygen >= 0.0 else "--%"
	_oxygen_label.add_theme_color_override("font_color", air_color(_oxygen))
	_oxygen_bar.value = maxf(0.0, _oxygen)
	var bar_fill := air_color(_oxygen)
	_oxygen_bar.add_theme_stylebox_override("fill", _bar_style(bar_fill, 7))
	_update_motion(map)

func _update_motion(map: Node) -> void:
	var state := _runtime_snapshot(map)
	var phase := str(state.get("phase", map.get("phase")))
	if phase.is_empty() or phase == "Null":
		phase = "swim"
	var motion := str(state.get("motion", "自由游动"))
	if motion.is_empty() or motion == "Null":
		motion = "自由游动"
	var speed := float(state.get("speed", 0.0))
	var navigation: Variant = state.get("navigation", false)
	var phase_text := str({"surface":"海面", "enter":"正在下潜", "swim":motion, "exit":"正在上浮"}.get(phase, motion))
	_motion_label.text = "%s · %.1f m/s%s" % [phase_text, speed, " · 自动游动" if bool(navigation) else ""]
	var camera_fov: Variant = state.get("camera_fov", null)
	_camera_label.visible = camera_fov != null
	if camera_fov != null:
		_camera_label.text = "视野 %.0f°" % float(camera_fov)

func _runtime_snapshot(map: Node) -> Dictionary:
	var controller: Variant = null
	for property in map.get_property_list():
		if str(property.name) == "dive_controller":
			controller = map.get("dive_controller")
			break
	if controller == null:
		controller = map.get_node_or_null("dive_controller")
	if controller is Object and is_instance_valid(controller) and controller.has_method("snapshot"):
		var value: Variant = controller.call("snapshot")
		if value is Dictionary:
			return value
	if map.has_method("snapshot"):
		var fallback: Variant = map.call("snapshot")
		if fallback is Dictionary:
			return fallback
	return {}

static func air_color(ratio: float) -> Color:
	if ratio < 0.0: return Color.WHITE
	if ratio <= 0.15: return Color("#D4573F")
	if ratio <= 0.30: return Color("#E08B4A")
	return Color.WHITE

func presentation_snapshot() -> Dictionary:
	return {"oxygen": _oxygen, "depth": _depth, "lamp_on": _lamp_on, "found": _found, "total": _total, "text": _status.text, "color": _status.get_theme_color("font_color"), "paused": get_tree().paused, "menu_open": _menu.visible}

func _input(event: InputEvent) -> void:
	if not is_instance_valid(session): return
	if session.switching: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _menu.visible:
			_resume()
		else:
			get_tree().paused = true
			_menu.show()
			_return_button.grab_focus()
		get_viewport().set_input_as_handled()

func _resume() -> void:
	get_tree().paused = false
	_menu.hide()

func _surface() -> void:
	_resume()
	if is_instance_valid(session):
		session.surface()

func _rise() -> void:
	if not get_tree().paused and is_instance_valid(session) and is_instance_valid(session.runtime):
		session.swim_to(session.runtime.diver_pos + Vector3.UP * 3.0)

func _descend() -> void:
	if not get_tree().paused and is_instance_valid(session) and is_instance_valid(session.runtime):
		session.swim_to(session.runtime.diver_pos + Vector3.DOWN * 3.0)

func _lamp() -> void:
	if not get_tree().paused and is_instance_valid(session):
		session.toggle_lamp()

func _cancel() -> void:
	if not get_tree().paused and is_instance_valid(session):
		session.cancel_navigation()
