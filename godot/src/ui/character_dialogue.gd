extends CanvasLayer
## Only explicit character dialogue uses this bottom panel. System notices use HUD.toast.
## Supports single lines and multi-line narrative sequences with indie typewriter reveal.
signal closed
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Fonts = preload("res://src/ui/ui_font.gd")
var panel: PanelContainer
var speaker_label: Label
var line_label: Label
var page_label: Label
var close_button: Button
var _queue: Array[Dictionary] = []
var _index := 0
var _reveal_tween: Tween
var _entry_tween: Tween
var _font: Font
var _input_shield: Control

func is_blocking() -> bool:
	return is_instance_valid(panel) and panel.visible and _queue.size() > 1

func _ready() -> void:
	layer = 70
	_font = Fonts.embedded()
	_input_shield = Control.new()
	_input_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_shield.hide()
	add_child(_input_shield)
	panel = PanelContainer.new()
	panel.set_meta("cozy_skip", true)
	panel.custom_minimum_size = Vector2(680, 168)
	var style := Cozy.surface(Color("#fbf6e8"), 28)
	style.border_color = Color("#d8ceba")
	style.set_border_width_all(2)
	style.shadow_color = Color(0.08, 0.16, 0.19, 0.22)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	body.add_child(header)
	speaker_label = Label.new()
	speaker_label.add_theme_font_override("font", _font)
	speaker_label.add_theme_font_size_override("font_size", 21)
	speaker_label.add_theme_color_override("font_color", Cozy.TEAL)
	speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(speaker_label)
	page_label = Label.new()
	page_label.add_theme_font_override("font", _font)
	page_label.add_theme_font_size_override("font_size", 18)
	page_label.add_theme_color_override("font_color", Cozy.DIM)
	header.add_child(page_label)
	line_label = Label.new()
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(616, 68)
	line_label.add_theme_font_override("font", _font)
	line_label.add_theme_font_size_override("font_size", 24)
	line_label.add_theme_color_override("font_color", Cozy.INK)
	body.add_child(line_label)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(footer)
	close_button = Button.new()
	close_button.text = "继续"
	close_button.custom_minimum_size = Vector2(126, 40)
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.add_theme_font_override("font", _font)
	close_button.add_theme_font_size_override("font_size", 20)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		close_button.add_theme_color_override(key, Cozy.INK)
	close_button.add_theme_stylebox_override("normal", Cozy.surface(Color("#eee8d5"), 18))
	close_button.add_theme_stylebox_override("hover", Cozy.surface(Cozy.GOLD, 18))
	close_button.add_theme_stylebox_override("pressed", Cozy.surface(Cozy.MINT, 18))
	close_button.pressed.connect(_advance)
	footer.add_child(close_button)
	get_viewport().size_changed.connect(_place)
	panel.hide()

func _place() -> void:
	if not is_instance_valid(panel): return
	var vp := get_viewport().get_visible_rect().size
	# Keep the established 1600px design scale; don't let minimum-size content
	# push the last line or footer out of the viewport at 1280x800.
	var fit := minf(1.0, minf(vp.x / 1600.0, vp.y / 1000.0))
	panel.scale = Vector2.ONE * fit
	var extent := panel.get_combined_minimum_size().max(panel.size) * fit
	panel.position = Vector2((vp.x - extent.x) * 0.5, vp.y - extent.y - 32.0 * fit)

func show_line(speaker: String, text: String) -> void:
	if speaker.strip_edges().is_empty() or text.strip_edges().is_empty(): return
	show_sequence([{"speaker": speaker, "text": text}])

func show_sequence(lines: Array) -> void:
	_queue.clear()
	for entry in lines:
		if entry is Dictionary:
			var s := str(entry.get("speaker", "")).strip_edges()
			var t := str(entry.get("text", "")).strip_edges()
			if not s.is_empty() and not t.is_empty():
				_queue.append({"speaker": s, "text": t})
	if _queue.is_empty(): return
	_index = 0
	var was_visible := panel.visible
	panel.show()
	_input_shield.visible = _queue.size() > 1
	_place()
	_place.call_deferred()
	if not was_visible and Cozy.motion_enabled:
		if _entry_tween and _entry_tween.is_valid(): _entry_tween.kill()
		var target_y := panel.position.y
		panel.position.y = target_y + 18.0
		panel.modulate.a = 0.0
		_entry_tween = create_tween().set_parallel(true)
		_entry_tween.tween_property(panel, "position:y", target_y, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_entry_tween.tween_property(panel, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE)
	else:
		panel.modulate.a = 1.0
	_present_current()

func _present_current() -> void:
	if _index < 0 or _index >= _queue.size():
		close_line()
		return
	var current: Dictionary = _queue[_index]
	speaker_label.text = "✦  " + str(current.speaker)
	line_label.text = str(current.text)
	var total := _queue.size()
	page_label.text = ("%d / %d" % [_index + 1, total]) if total > 1 else ""
	close_button.text = "下一步 ▸" if _index + 1 < total else "开始生活" if total > 1 else "继续"
	if _reveal_tween and _reveal_tween.is_valid(): _reveal_tween.kill()
	if Cozy.motion_enabled and total > 1:
		line_label.visible_ratio = 0.0
		var duration := clampf(float(line_label.text.length()) * 0.018, 0.22, 0.65)
		_reveal_tween = create_tween()
		_reveal_tween.tween_property(line_label, "visible_ratio", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	else:
		line_label.visible_ratio = 1.0

func _advance() -> void:
	if not panel.visible: return
	if line_label.visible_ratio < 0.999:
		if _reveal_tween and _reveal_tween.is_valid(): _reveal_tween.kill()
		line_label.visible_ratio = 1.0
		return
	_index += 1
	if _index < _queue.size():
		_present_current()
	else:
		close_line()

## 由调用方收掉台词（体力见底那句由 Main 定时收起，不等玩家点「继续」）。
func close_line() -> void:
	if not panel.visible: return
	if _reveal_tween and _reveal_tween.is_valid(): _reveal_tween.kill()
	if _entry_tween and _entry_tween.is_valid(): _entry_tween.kill()
	line_label.visible_ratio = 1.0
	_queue.clear()
	_index = 0
	panel.hide()
	_input_shield.hide()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_blocking(): return
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_advance()
		# Narrative keys never reach gameplay or a previously focused HUD button.
		get_viewport().set_input_as_handled()
