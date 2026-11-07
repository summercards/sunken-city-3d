extends CanvasLayer
## 独立地图 HUD：本地状态栏替代旧海面潜水日志，不依赖已移出树的海面 UI。
var session: Node3D
var command_buttons: Dictionary = {}
var menu_buttons: Dictionary = {}
var _status: Label
var _menu: PanelContainer
var _return_button: Button
var _oxygen := -1.0
var _depth := 0.0
var _lamp_on := false
var _found := 0
var _total := 0
var _notice: Label
var _notice_left := 0.0

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var top := HBoxContainer.new()
	top.position = Vector2(24,24)
	add_child(top)
	var font: Font = preload("res://src/ui/ui_font.gd").embedded()
	for entry in [["surface","上浮",_surface],["rise","上游",_rise],["descend","下游",_descend],["lamp","头灯",_lamp],["cancel","取消游动",_cancel]]:
		var button := Button.new()
		button.text = entry[1]
		button.custom_minimum_size = Vector2(100,48)
		button.add_theme_font_override("font",font)
		button.pressed.connect(entry[2])
		command_buttons[entry[0]] = button
		top.add_child(button)
	_status = Label.new()
	_status.position = Vector2(24,84)
	_status.add_theme_font_size_override("font_size",22)
	_status.add_theme_font_override("font",font)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	_menu = PanelContainer.new()
	_menu.position = Vector2(24,136)
	add_child(_menu)
	var body := VBoxContainer.new()
	_menu.add_child(body)
	for entry in [["resume","继续探索",_resume],["surface","上浮返回海面",_surface]]:
		var button := Button.new()
		button.text = entry[1]
		button.custom_minimum_size = Vector2(230,52)
		button.add_theme_font_override("font",font)
		button.pressed.connect(entry[2])
		menu_buttons[entry[0]] = button
		body.add_child(button)
		if _return_button == null: _return_button = button
	_menu.hide()
	_notice = Label.new()
	_notice.position = Vector2(24,118)
	_notice.add_theme_font_override("font",font)
	_notice.add_theme_font_size_override("font_size",20)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice)
	session.message.connect(_on_message)

func _on_message(text: String) -> void:
	_notice.text = text
	_notice_left = 3.0

func _process(_delta: float) -> void:
	if not is_instance_valid(session) or not is_instance_valid(session.runtime): return
	if not get_tree().paused: _notice_left = maxf(0.0,_notice_left-_delta)
	_notice.visible = _notice_left>0
	var map = session.runtime
	_oxygen = map.air.ratio()
	_depth = map.depth
	_lamp_on = map.air.lamp
	_found = map.discovered_count()
	_total = map.chest_count()
	var warning := " · 氧气危急" if _oxygen <= 0.15 else (" · 氧气偏低" if _oxygen <= 0.30 else "")
	# 没有宝箱的地图（家园海底）不显示「发现 0/0」这种看起来像坏掉的计数。
	var found_text := "" if _total<=0 else " · 发现 %d/%d" % [_found,_total]
	_status.text = "%s · 氧气 %d%% · 水深 %.0fm%s%s" % [map.map_label,roundi(_oxygen*100),_depth,found_text,warning]
	_status.add_theme_color_override("font_color",air_color(_oxygen))

static func air_color(ratio: float) -> Color:
	if ratio <= 0.15: return Color("#D4573F")
	if ratio <= 0.30: return Color("#E08B4A")
	return Color.WHITE

func presentation_snapshot() -> Dictionary:
	return {"oxygen":_oxygen,"depth":_depth,"lamp_on":_lamp_on,"found":_found,"total":_total,"text":_status.text,"color":_status.get_theme_color("font_color"),"paused":get_tree().paused,"menu_open":_menu.visible}

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _menu.visible: _resume()
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
	session.surface()
func _rise() -> void:
	if not get_tree().paused: session.swim_to(session.runtime.diver_pos+Vector3.UP*3.0)
func _descend() -> void:
	if not get_tree().paused: session.swim_to(session.runtime.diver_pos+Vector3.DOWN*3.0)
func _lamp() -> void:
	if not get_tree().paused: session.toggle_lamp()
func _cancel() -> void:
	if not get_tree().paused: session.cancel_navigation()
