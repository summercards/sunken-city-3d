extends CanvasLayer
## 纯职业展示适配器；装配层负责查询、授权、扣费、奖励和跨面板路由。
signal closed
const Cozy = preload("res://src/ui/cozy_ui.gd")
const ACTIONS := ["ship", "cultivation", "salvage", "building", "archive"]
const TITLES := {"ship": "船只与航行", "cultivation": "种植与种子", "salvage": "打捞与记录", "building": "建造与修缮", "archive": "灯火与档案"}

var _query: Callable
var _perform: Callable
var _npc_id := ""
var _action_id := ""
var _view: Dictionary = {}
var _open := false
var _busy := false
var _confirming := false
var _submitted := false
var _feedback := ""
var _serial := 0
var _opened_frame := -1
var _last_event: InputEvent
var _last_event_frame := -1
var _held_keys: Dictionary = {}
var _overlay: Control
var _title: Label
var _identity: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _buttons: Array[Button] = []

## query(action:String)->Dictionary：公共 display_name/role/description/ok/reason。
## ship：ship_level/cost:Dictionary/item_labels:Dictionary/can_execute:bool。
## salvage：cooldown_left:float/can_execute:bool；不在UI倒计时或计算产出。
## cultivation：crops:Array[{display_name,growth_text,status_text}]。
## archive：events:Array[{id,title,completed,npc_id?}]，未完成项不进入回看列表。
## perform(action:String, command:Dictionary)->{ok:bool,reason?:String,message?:String,close?:bool}。
## command固定包含id/npc_id；回看额外含event_id/event_npc_id。
## id为upgrade_ship/do_salvage/shop_general/open_plant/open_building/open_events/replay_event。
## perform必须同步返回，真实owner在执行时重新校验；query不得产生玩法副作用。
func configure(query: Callable, perform: Callable) -> void:
	close()
	_query = query
	_perform = perform

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	_ensure_ui()

func open_service(npc_id: String, action_id: String) -> Dictionary:
	if _busy: return {"ok": false, "reason": "职业面板正在处理命令"}
	if action_id not in ACTIONS or npc_id.is_empty(): return {"ok": false, "reason": "未知职业服务"}
	if not _query.is_valid(): return {"ok": false, "reason": "职业查询尚未接入"}
	close()
	_npc_id = npc_id
	_action_id = action_id
	_open = true
	_opened_frame = Engine.get_process_frames()
	_confirming = false
	_submitted = false
	_feedback = ""
	_read_view()
	_render()
	return {"ok": true}

func close() -> void:
	if not _open: return
	_open = false
	_confirming = false
	_submitted = false
	_serial += 1
	_view.clear()
	_feedback = ""
	_npc_id = ""
	_action_id = ""
	if _overlay != null:
		_overlay.hide()
		for button in _buttons: button.release_focus()
	closed.emit()

func is_open() -> bool:
	return _open

func panel_snapshot() -> Dictionary:
	return {"open": _open, "npc_id": _npc_id, "action_id": _action_id,
		"view": _view.duplicate(true), "confirming": _confirming,
		"submitted": _submitted, "busy": _busy, "feedback": _feedback}

func _exit_tree() -> void:
	close()
	_query = Callable()
	_perform = Callable()
	_last_event = null

func _read_view() -> void:
	var value: Variant = _query.call(_action_id) if _query.is_valid() else null
	_view = value.duplicate(true) if value is Dictionary else {"ok": false, "reason": "职业查询未返回有效信息"}

func _can_execute() -> bool:
	return bool(_view.get("ok", true)) and bool(_view.get("can_execute", false)) and _perform.is_valid()

func _input(event: InputEvent) -> void:
	if handle_input(event): get_viewport().set_input_as_handled()

## 装配层可优先转发；同帧同事件、长按回声及关闭键的释放都只消费不再执行。
func handle_input(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	var frame := Engine.get_process_frames()
	if event == _last_event and frame == _last_event_frame: return true
	var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if not _open:
		if not _held_keys.has(key): return false
		if not event.pressed: _held_keys.erase(key)
		_last_event = event
		_last_event_frame = frame
		return true
	_last_event = event
	_last_event_frame = frame
	if not event.pressed:
		_held_keys.erase(key)
		return true
	_held_keys[key] = true
	if event.echo or _busy: return true
	if key == KEY_ESCAPE:
		if _confirming:
			_confirming = false
			_feedback = ""
			_render()
		else: close()
		return true
	if get_tree().paused: return true
	match key:
		KEY_UP, KEY_LEFT: _move_focus(-1)
		KEY_DOWN, KEY_RIGHT: _move_focus(1)
		KEY_TAB: _move_focus(-1 if event.shift_pressed else 1)
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			# 打开服务的那次交互不能直接落在新的确认按钮上。
			if frame == _opened_frame: return true
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button and focus in _buttons and not focus.disabled: focus.pressed.emit()
	return true

func _move_focus(step: int) -> void:
	var index := _buttons.find(get_viewport().gui_get_focus_owner())
	for offset in range(1, _buttons.size() + 1):
		var next := posmod(index + step * offset, _buttons.size())
		if not _buttons[next].disabled:
			_buttons[next].grab_focus()
			_scroll.ensure_control_visible(_buttons[next])
			return

func _on_button(id: String, event: Dictionary, stamp: int) -> void:
	if not _open or _busy or stamp != _serial: return
	if id == "close":
		close()
		return
	if get_tree().paused: return
	match id:
		"refresh":
			_confirming = false
			_submitted = false
			_feedback = ""
			_read_view()
			_render()
		"prepare":
			if _submitted or not _can_execute(): return
			_confirming = true
			_feedback = ""
			_render()
		"cancel":
			_confirming = false
			_feedback = ""
			_render()
		"confirm":
			if not _confirming or _submitted or not _can_execute(): return
			_confirming = false
			_submitted = true
			_execute("upgrade_ship" if _action_id == "ship" else "do_salvage")
		_:
			if not _confirming and bool(_view.get("ok", true)):
				_execute(id, event)

func _execute(id: String, event: Dictionary = {}) -> void:
	# 先作废本页所有回调，阻止同步owner信号、鼠标双击和延迟旧按钮再次提交。
	_serial += 1
	var stamp := _serial
	var command := {"id": id, "npc_id": _npc_id}
	if id == "replay_event":
		command["event_id"] = str(event.get("id", ""))
		command["event_npc_id"] = str(event.get("npc_id", _npc_id))
	_busy = true
	var result: Variant = _perform.call(_action_id, command) if _perform.is_valid() else {"ok": false, "reason": "职业命令尚未接入"}
	_busy = false
	# Main可以在路由过程中主动close；返回后不复活旧面板。
	if not _open or stamp != _serial: return
	if not result is Dictionary: result = {"ok": false, "reason": "职业命令未返回有效结果"}
	var ok := bool(result.get("ok", false))
	_feedback = str(result.get("message", "已完成")) if ok else str(result.get("reason", "暂未完成，请稍后再试"))
	_submitted = ok
	_read_view()
	if ok and bool(result.get("close", false)):
		close()
	else:
		_render()

func _ensure_ui() -> void:
	if _overlay != null: return
	_overlay = Control.new()
	_overlay.name = "NpcCareerOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var theme := Theme.new()
	theme.default_font = Cozy.ui_font()
	theme.default_font_size = 22
	_overlay.theme = theme
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.12, 0.19, 0.18, 0.27)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)
	var paper := PanelContainer.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.anchor_left = 0.18
	paper.anchor_right = 0.82
	paper.anchor_top = 0.12
	paper.anchor_bottom = 0.88
	_overlay.add_child(paper)
	Cozy.apply(paper)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	paper.add_child(layout)
	_title = _label(layout, "", 30)
	_identity = _label(layout, "")
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	_overlay.hide()

func _label(parent: Node, text: String, font_size := 22) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Cozy.INK)
	parent.add_child(label)
	return label

func _button(text: String, id: String, disabled := false, event: Dictionary = {}) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = disabled
	button.set_meta("career_command", id)
	button.set_meta("career_event", event.duplicate(true))
	button.pressed.connect(_on_button.bind(id, event.duplicate(true), _serial))
	_body.add_child(button)
	Cozy.apply(button)
	_buttons.append(button)

func _cost_text() -> String:
	var parts: Array[String] = []
	var labels: Dictionary = _view.get("item_labels", {})
	var cost: Dictionary = _view.get("cost", {})
	for item in cost: parts.append("%s × %s" % [labels.get(item, item), cost[item]])
	return "、".join(parts)

func _render() -> void:
	_ensure_ui()
	_serial += 1
	_buttons.clear()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_overlay.visible = _open
	if not _open: return
	_title.text = str(TITLES[_action_id])
	_identity.text = "%s · %s" % [_view.get("display_name", _npc_id), _view.get("role", TITLES[_action_id])]
	if str(_view.get("description", "")) != "": _label(_body, str(_view.description))
	match _action_id:
		"ship":
			_label(_body, "当前船只等级  %s" % _view.get("ship_level", "—"))
			if not _cost_text().is_empty(): _label(_body, "升级所需：" + _cost_text())
			_render_confirmation("请船匠升级船只", "确认按以上费用升级船只？", "确认升级")
		"salvage":
			if _view.has("cooldown_left"): _label(_body, "打捞冷却剩余  %.1f 秒" % float(_view.cooldown_left))
			_render_confirmation("委托一次打捞", "确认委托本次打捞？收获以实际结果为准。", "确认打捞")
		"cultivation":
			for crop in _view.get("crops", []):
				_label(_body, "%s\n成长：%s\n%s" % [crop.get("display_name", "作物"), crop.get("growth_text", "—"), crop.get("status_text", "")])
			_route_button("看看种子", "shop_general")
			_route_button("去照料作物", "open_plant")
		"building": _route_button("打开建造", "open_building")
		"archive":
			var completed := 0
			for event in _view.get("events", []):
				if not event.get("completed", false): continue
				completed += 1
				_button("回看 · " + str(event.get("title", event.get("id", "故事"))), "replay_event", not _perform.is_valid() or not bool(_view.get("ok", true)), event)
			_label(_body, "已收录 %d 段故事" % completed)
			_route_button("打开居民故事", "open_events")
	if str(_view.get("reason", "")) != "": _label(_body, str(_view.reason))
	if not _perform.is_valid(): _label(_body, "职业命令尚未接入")
	if not _feedback.is_empty(): _label(_body, _feedback)
	if not _confirming: _button("再看看", "refresh")
	_button("告别", "close")
	for button in _buttons:
		if not button.disabled:
			button.grab_focus()
			break

func _render_confirmation(prepare_text: String, question: String, confirm_text: String) -> void:
	if _confirming:
		_label(_body, question, 24)
		_button(confirm_text, "confirm", not _can_execute())
		_button("暂不委托", "cancel")
	elif not _submitted:
		_button(prepare_text, "prepare", not _can_execute())

func _route_button(text: String, id: String) -> void:
	_button(text, id, not _perform.is_valid() or not bool(_view.get("ok", true)))
