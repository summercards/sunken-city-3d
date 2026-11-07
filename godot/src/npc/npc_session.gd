extends RefCounted
## 仅持有面板瞬态意图。对白推进和所有结算均交回已配置的 NpcService。
signal changed
signal modal_changed(active: bool)
signal action_requested(npc_id: String, action_id: String)
const FUNCTIONS := {
	"npc_luo_yan": ["ship", "船只与航行"],
	"npc_mu_he": ["cultivation", "种植与种子"],
	"npc_ji_chen": ["salvage", "打捞与记录"],
	"npc_nan_zhi": ["building", "建造与修缮"],
	"npc_bai_shi": ["archive", "灯火与档案"]
}
var service
var npc_id := ""
var section := "home"
var feedback := ""
var confirmation: Dictionary = {}
var _home_labels: Dictionary = {}
var _items: Dictionary = {}
var _executing := false

func configure(npc_service, home_labels: Dictionary = {}) -> void:
	cancel()
	service = npc_service
	_home_labels = home_labels.duplicate(true)
	_items.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/items.json"))
	if data is Dictionary:
		for row in data.get("items", []): _items[str(row.id)] = str(row.get("label", row.id))

func open(id: String) -> Dictionary:
	if service == null: return {"ok": false, "reason": "NPC服务尚未接入"}
	if service.npc_snapshot(id).is_empty(): return {"ok": false, "reason": "未知居民"}
	cancel()
	var result: Dictionary = service.meet(id)
	if not result.get("ok", false): return result
	npc_id = id
	section = "home"
	feedback = ""
	modal_changed.emit(true)
	changed.emit()
	return {"ok": true}

func is_modal() -> bool:
	return not npc_id.is_empty()

func cancel() -> void:
	var was_open := is_modal()
	if service != null and was_open: service.close_dialogue()
	npc_id = ""
	section = "home"
	confirmation.clear()
	feedback = ""
	if was_open:
		modal_changed.emit(false)
		changed.emit()

func back() -> void:
	if not confirmation.is_empty():
		confirmation.clear()
	elif service != null and service.dialogue_state().get("active", false):
		service.close_dialogue()
	elif section != "home":
		section = "home"
	else:
		cancel()
		return
	feedback = ""
	changed.emit()

func item_label(id: String) -> String:
	return str(_items.get(id, id))

func snapshot() -> Dictionary:
	if not is_modal() or service == null: return {"open": false}
	var npc: Dictionary = service.npc_snapshot(npc_id)
	var state := {"open": true, "npc_id": npc_id, "npc": npc, "section": section,
		"home": _home_labels.get(npc.get("residence_id", ""), "暂驻点尚未登记"),
		"dialogue": service.dialogue_state(), "confirmation": confirmation.duplicate(true),
		"feedback": feedback, "events": service.list_events(npc_id),
		"gifts": service.gift_options(npc_id), "requests": service.list_requests(npc_id),
		"relationships": service.relationship_graph(), "function": FUNCTIONS.get(npc_id, []).duplicate()}
	# 资料与话题只在阅读对应页面时查询，不进入逐帧打字路径。
	if section in ["profile", "relationships"] and not state.dialogue.get("active", false):
		state["profile"] = service.character_profile(npc_id) if service.has_method("character_profile") else {}
	if section == "topics" and not state.dialogue.get("active", false):
		state["topics"] = service.conversation_topics(npc_id) if service.has_method("conversation_topics") else []
	return state

## 命令表是UI的唯一入口，旧按钮携带的npc/session戳不得作用到新会话。
func command(action: String, payload: Dictionary = {}) -> Dictionary:
	if not is_modal() or service == null or _executing: return {"ok": false, "reason": "会话不可用"}
	if payload.has("npc_id") and payload.npc_id != npc_id: return {"ok": false, "reason": "过期面板"}
	if action == "back":
		back()
		return {"ok": true}
	if action == "close":
		cancel()
		return {"ok": true}
	var dialogue: Dictionary = service.dialogue_state()
	var result := {"ok": false, "reason": "当前操作不可用"}
	_executing = true
	if dialogue.get("active", false):
		var serial := int(payload.get("session_id", -1))
		if serial != int(dialogue.session_id):
			result = {"ok": false, "reason": "过期对白"}
		elif action == "advance": result = service.advance_dialogue(serial)
		elif action == "choice": result = service.choose_dialogue(str(payload.get("id", "")), serial)
	elif not confirmation.is_empty():
		if action == "confirm":
			var pending := confirmation.duplicate(true)
			confirmation.clear()
			if pending.kind == "gift": result = service.give_gift(npc_id, pending.id)
			elif pending.kind == "request": result = service.fulfill_request(pending.id)
	elif action in ["home", "profile", "topics", "events", "gifts", "requests", "relationships", "services"]:
		section = action
		result = {"ok": true}
	elif action == "topic" and section == "topics":
		if service.has_method("start_topic"):
			result = service.start_topic(npc_id, str(payload.get("id", "")))
		else:
			result = {"ok": false, "reason": "这段闲聊还没准备好"}
	elif action == "talk":
		var npc: Dictionary = service.npc_snapshot(npc_id)
		result = service.start_npc_dialogue(npc_id, "intro" if int(npc.runtime.last_talk_day) < 1 else "daily")
	elif action == "event":
		for event in service.list_events(npc_id):
			if event.id == str(payload.get("id", "")):
				result = service.start_event(event.id, bool(event.completed))
	elif action == "gift":
		var options: Dictionary = service.gift_options(npc_id)
		for item in options.get("items", []):
			if item.item_id == str(payload.get("id", "")) and item.available:
				confirmation = {"kind": "gift", "id": item.item_id, "text": "送出 %s × 1？" % item_label(item.item_id)}
				result = {"ok": true}
	elif action == "request":
		for request in service.list_requests(npc_id):
			if request.id == str(payload.get("id", "")) and request.can_fulfill:
				confirmation = {"kind": "request", "id": request.id, "text": "确认交付「%s」所需物品？" % request.get("title", request.id)}
				result = {"ok": true}
	elif action == "vendor":
		var id := npc_id
		if service.npc_snapshot(id).has("shop_id"):
			# 先撤销NPC模态，再让Main的vendor_requested打开商店，避免关闭信号反盖商店。
			cancel()
			result = service.request_vendor(id)
	elif action == "function":
		var entry: Array = FUNCTIONS.get(npc_id, [])
		if not entry.is_empty():
			var id := npc_id
			cancel()
			action_requested.emit(id, str(entry[0]))
			result = {"ok": true}
	_executing = false
	if is_modal():
		feedback = str(result.get("reason", "")) if not result.get("ok", false) else ("已完成" if result.get("completed", false) else "")
		if result.get("ok", false) and action == "confirm": feedback = "礼物已送达" if section == "gifts" else "请求已交付"
		changed.emit()
	return result
