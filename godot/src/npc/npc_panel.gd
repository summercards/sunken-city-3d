extends CanvasLayer
## 独立奶油色居民面板，不访问Main/HUD或其他玩法的界面。
signal action_requested(npc_id: String, action_id: String)
signal modal_changed(active: bool)
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Session = preload("res://src/npc/npc_session.gd")
var session = Session.new()
var _overlay: Control
var _title: Label
var _identity: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _buttons: Array[Button] = []
var _text: Label
var _typing_elapsed := 0.0
var _page_stamp := ""
var _last_event: InputEvent
var _last_event_frame := -1
var _render_serial := 0
var _opened_frame := -1
var _activation_frame := -1
var _held_keys: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 24
	_ensure_ui()
	session.changed.connect(_render)
	session.modal_changed.connect(_on_modal)
	session.action_requested.connect(_on_action)

func configure(service, home_labels: Dictionary = {}) -> void:
	_ensure_ui()
	session.configure(service, home_labels)

func open_npc(npc_id: String) -> Dictionary:
	return session.open(npc_id)

func cancel_session() -> void:
	session.cancel()

func is_modal() -> bool:
	return session.is_modal()

func panel_snapshot() -> Dictionary:
	return session.snapshot()

func _exit_tree() -> void:
	session.cancel()

func _on_modal(active: bool) -> void:
	_overlay.visible = active
	if active:
		_opened_frame = Engine.get_process_frames()
		_page_stamp = ""
		_typing_elapsed = 0.0
	else:
		for button in _buttons: button.release_focus()
	modal_changed.emit(active)

func _on_action(npc_id: String, action_id: String) -> void:
	action_requested.emit(npc_id, action_id)

func _input(event: InputEvent) -> void:
	if handle_input(event): get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> bool:
	if not event is InputEventKey: return false
	# 自身_input与装配层转发同一个事件时只消费一次。
	var frame := Engine.get_process_frames()
	if event == _last_event and frame == _last_event_frame: return true
	var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if not is_modal():
		if not _held_keys.has(key): return false
		if not event.pressed: _held_keys.erase(key)
		return true
	_last_event = event
	_last_event_frame = frame
	if not event.pressed:
		_held_keys.erase(key)
		return true
	var held := _held_keys.has(key)
	_held_keys[key] = true
	if event.echo or held: return true
	if get_tree().paused and key != KEY_ESCAPE: return true
	match key:
		KEY_ESCAPE:
			if frame == _activation_frame: return true
			_activation_frame = frame
			session.back()
		KEY_UP, KEY_LEFT:
			_move_focus(-1)
		KEY_DOWN, KEY_RIGHT:
			_move_focus(1)
		KEY_TAB:
			_move_focus(-1 if event.shift_pressed else 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE:
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

func _process(delta: float) -> void:
	if not is_modal(): return
	# 暂停状态只接受取消，不在后台自动补全或结算。
	if get_tree().paused: return
	var state: Dictionary = session.service.dialogue_state()
	if not state.get("active", false) or not state.get("typing", false) or _text == null: return
	_typing_elapsed += delta
	_text.visible_characters = mini(_text.text.length(), int(_typing_elapsed * 32.0))
	if _text.visible_characters >= _text.text.length() and _activation_frame != Engine.get_process_frames():
		_activation_frame = Engine.get_process_frames()
		session.command("advance", {"session_id": state.session_id})

func _ensure_ui() -> void:
	if _overlay != null: return
	_overlay = Control.new()
	_overlay.name = "NpcOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var theme := Theme.new()
	theme.default_font = Cozy.ui_font()
	theme.default_font_size = 22
	_overlay.theme = theme
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.19, 0.18, 0.27)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)
	var paper := PanelContainer.new()
	paper.name = "ResidentPaper"
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.anchor_left = 0.16
	paper.anchor_right = 0.84
	paper.anchor_top = 0.08
	paper.anchor_bottom = 0.92
	_overlay.add_child(paper)
	Cozy.apply(paper)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	paper.add_child(layout)
	_title = _label(layout, "", 32)
	_identity = _label(layout, "", 22)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)
	_overlay.hide()

func _label(parent: Node, value: String, font_size := 22) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Cozy.INK)
	parent.add_child(label)
	return label

func _button(text: String, action: String, payload: Dictionary = {}, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = disabled
	button.set_meta("npc_action", action)
	button.set_meta("npc_payload", payload.duplicate(true))
	var stamped := payload.duplicate(true)
	stamped["npc_id"] = session.npc_id
	button.pressed.connect(_command.bind(action, stamped, _render_serial))
	_body.add_child(button)
	Cozy.apply(button)
	_buttons.append(button)
	return button

func _command(action: String, payload: Dictionary, serial: int) -> void:
	if serial != _render_serial or not is_modal(): return
	if get_tree().paused and action not in ["back", "close"]: return
	var frame := Engine.get_process_frames()
	if frame == _activation_frame: return
	_activation_frame = frame
	session.command(action, payload)

func _render() -> void:
	_ensure_ui()
	_render_serial += 1
	_buttons.clear()
	_scroll.scroll_vertical = 0
	_text = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var state: Dictionary = session.snapshot()
	_overlay.visible = state.get("open", false)
	if not state.get("open", false): return
	var npc: Dictionary = state.npc
	_title.text = "%s · %s" % [npc.display_name, npc.role]
	_identity.text = "关系心  %d / 10   ·   亲近度 %d\n常在  %s" % [npc.runtime.hearts, npc.runtime.affinity, state.home]
	var dialogue: Dictionary = state.dialogue
	if dialogue.get("active", false):
		_render_dialogue(dialogue)
	elif not state.confirmation.is_empty():
		_label(_body, state.confirmation.text, 26)
		_button("确认送出" if state.confirmation.kind == "gift" else "确认交付", "confirm")
		_button("暂不送出" if state.confirmation.kind == "gift" else "暂不交付", "back")
	else:
		match state.section:
			"home":
				_button("聊一会儿", "talk")
				_button("认识一下", "profile")
				_button("聊点别的", "topics")
				_button("居民故事", "events")
				_button("送一份礼物", "gifts")
				_button("帮忙与交付", "requests")
				_button("关系网", "relationships")
				_button("经营与服务", "services")
			"profile": _render_profile(state.profile)
			"topics":
				if state.topics.is_empty(): _label(_body, "这会儿还没想好聊什么。")
				for topic in state.topics: _button(str(topic.title), "topic", {"id": topic.id})
			"events": _render_events(state.events)
			"gifts": _render_gifts(state.gifts)
			"requests": _render_requests(state.requests)
			"relationships":
				_render_relationships(state.relationships, state.events)
				_render_social_notes(state.profile.get("social_notes", []))
			"services":
				if npc.has("shop_id"):
					_button("逛逛花店" if npc.shop_id == "shop_flower" else "逛逛综合商店", "vendor")
				elif not state.function.is_empty():
					_button(str(state.function[1]), "function")
				_label(_body, "也可以先回去聊一会儿。")
		if state.section != "home": _button("返回", "back")
		_button("告别", "close")
	if state.feedback != "": _label(_body, state.feedback)
	for button in _buttons:
		if not button.disabled:
			button.grab_focus()
			break
	_scroll.set_deferred("scroll_vertical", 0)

func _render_dialogue(state: Dictionary) -> void:
	var page: Dictionary = state.page
	var stamp := "%s:%s:%s" % [state.session_id, state.index, state.typing]
	if stamp != _page_stamp:
		_typing_elapsed = 0.0
		_page_stamp = stamp
	_label(_body, "%s    %d / %d%s" % [page.speaker, int(state.index) + 1, state.total, " · 回看" if state.replay else ""], 24)
	_text = _label(_body, page.text, 26)
	_text.custom_minimum_size.y = 150
	_text.visible_characters = 0 if state.typing else -1
	if state.typing:
		_button("读完这句话", "advance", {"session_id": state.session_id})
	elif page.has("choices"):
		for choice in page.choices:
			_button(choice.text, "choice", {"id": choice.id, "session_id": state.session_id})
	else:
		_button("继续" if int(state.index) + 1 < int(state.total) else "听完了", "advance", {"session_id": state.session_id})
	_button("结束交谈", "back")

func _render_events(events: Array) -> void:
	if events.is_empty(): _label(_body, "暂时没有故事。")
	for event in events:
		var suffix := " · 已完成，可回看" if event.completed else (" · 可以开始" if event.available else " · " + str(event.reason))
		_button(str(event.title) + suffix, "event", {"id": event.id}, not event.available)

func _render_gifts(gifts: Dictionary) -> void:
	if not gifts.get("ok", false):
		_label(_body, str(gifts.get("reason", "礼物暂不可用")))
		return
	var allowance: Dictionary = gifts.allowance
	_label(_body, "本周普通礼物剩余 %d / 2%s" % [allowance.normal_remaining, " · 生日专用礼物可用" if allowance.birthday_available else ""])
	if not allowance.ok: _label(_body, str(allowance.reason))
	var owned := 0
	for item in gifts.items:
		if int(item.get("count", 0)) <= 0: continue
		owned += 1
		_button("%s  ·  持有 %d" % [session.item_label(item.item_id), item.count], "gift", {"id": item.item_id}, not item.available)
	if owned == 0: _label(_body, "背包里还没有可赠送的物品。")

func _render_requests(requests: Array) -> void:
	if requests.is_empty(): _label(_body, "暂时没有开启的请求，先听听居民的故事吧。")
	for request in requests:
		var costs: Array[String] = []
		for item in request.costs: costs.append("%s × %d" % [session.item_label(item), request.costs[item]])
		_label(_body, "%s\n%s\n所需：%s" % [request.get("title", request.id), request.get("description", request.get("followup", "")), "、".join(costs)])
		var completed: bool = request.runtime.status == "completed"
		_button("已完成" if completed else ("交付物品" if request.can_fulfill else "物品不足或交付端口未就绪"), "request", {"id": request.id}, not request.can_fulfill or completed)

func _render_profile(character: Dictionary) -> void:
	var profile: Dictionary = character.get("profile", {})
	if profile.is_empty(): _label(_body, "还没来得及细聊。")
	_label(_body, "称呼\n" + str(character.get("display_name", session.service.npc_snapshot(session.npc_id).display_name)))
	for field in [["age_range", "年纪"], ["personality", "性格"], ["past", "以前"],
		["arrival_reason", "为什么来这里"], ["short_term_wish", "眼下的愿望"],
		["habit", "平时的习惯"], ["catchphrase", "常说的话"]]:
		var value := str(profile.get(field[0], ""))
		if not value.is_empty(): _label(_body, "%s\n%s" % [field[1], value])
	# secret_or_regret 属于剧情内容，不作为初次认识时的公开资料。
	_render_social_notes(character.get("social_notes", []))

func _render_social_notes(notes: Array) -> void:
	if notes.is_empty(): return
	_label(_body, "说起大家", 24)
	for note in notes:
		var other: Dictionary = session.service.npc_snapshot(str(note.get("npc_id", "")))
		if not other.get("runtime", {}).get("met", false):
			_label(_body, "还没认识的人 · 等见过面再聊。")
			continue
		_label(_body, "%s\n%s" % [other.display_name, note.get("text", "")])

func _render_relationships(edges: Array, events: Array) -> void:
	for edge in edges:
		if session.npc_id not in [edge.from, edge.to]: continue
		if not edge.known:
			_label(_body, "尚未相识的关系 · 等待了解")
			continue
		var left: Dictionary = session.service.npc_snapshot(edge.from)
		var right: Dictionary = session.service.npc_snapshot(edge.to)
		_label(_body, "%s — %s\n%s · 原有关系 %d · 现在 %d" % [left.display_name, right.display_name, edge.type, edge.base, edge.effective], 24)
		for field in [["summary", "平日相处"], ["history", "以前的事"], ["tension", "还没说开的话"]]:
			if not str(edge.get(field[0], "")).is_empty(): _label(_body, "%s\n%s" % [field[1], edge[field[0]]])
		var reconciled := bool(edge.get("reconcile_known", false))
		for event in events:
			var participants: Array = event.get("npc_ids", [])
			if event.get("kind", "") == "relationship" and event.get("completed", false) and edge.from in participants and edge.to in participants:
				reconciled = true
		if reconciled and not str(edge.get("reconcile", "")).is_empty():
			_label(_body, "后来商量的办法\n" + str(edge.reconcile))
		elif not str(edge.get("reconcile", "")).is_empty():
			_label(_body, "以后怎么办 · 还没听他们说起。")
