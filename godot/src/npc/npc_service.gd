extends RefCounted
## 七人 NPC 持久状态的唯一所有者；所有外部依赖通过弱引用端口注入。
signal npc_met(npc_id: String)
signal dialogue_completed(dialogue_id: String)
signal affinity_changed(npc_id: String, delta: int, reason: String)
signal relation_edge_changed(edge_id: String, delta: int, reason: String)
signal vendor_requested(npc_id: String, shop_id: String)
signal schedule_fallback(npc_id: String, requested_anchor: String, fallback_anchor: String)
signal npc_schedule_fallback(npc_id: String, requested_anchor: String, fallback_anchor: String)
signal npc_request_opened(request_id: String)
signal request_completed(request_id: String, result: Dictionary)
const Catalog = preload("res://src/npc/npc_catalog.gd")
const Graph = preload("res://src/npc/npc_relationship_graph.gd")
const ScheduleResolver = preload("res://src/npc/npc_schedule_resolver.gd")
const DialogueRunner = preload("res://src/npc/npc_dialogue_runner.gd")
const Codec = preload("res://src/npc/npc_save_codec.gd")
var _state: Dictionary = Codec.empty_snapshot()
var _dialogue = DialogueRunner.new()
var _schedule = ScheduleResolver.new()
var _pending: Dictionary = {}
var _ports: Dictionary = {}
var _busy := false

## 端口必须为对象的命名方法，不接收捕获闭包，避免库存/服务相互持有。
## exchange(costs, gains)->bool或{ok:bool}；remove(item_id, count) 同上。
## clock_query()->{day,hour,weather}；count(item_id)->非负整数。
## result_port(result)->任意值，仅通知，不负责物品结算。
func configure(clock_query: Callable = Callable(), exchange: Callable = Callable(), remove: Callable = Callable(), count: Callable = Callable(), result_port: Callable = Callable()) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var content_error := Catalog.validate()
	if content_error != "": return _fail(content_error)
	var next := {}
	var inputs := {"clock": clock_query, "exchange": exchange, "remove": remove, "count": count, "result": result_port}
	for key in inputs:
		var callback: Callable = inputs[key]
		if callback.is_null(): continue
		if not callback.is_valid() or callback.is_custom() or callback.get_object() == null: return _fail("端口须为有效对象命名方法：" + key)
		next[key] = {"owner": weakref(callback.get_object()), "method": callback.get_method()}
	_ports = next
	return {"ok": true}

func dispose() -> void:
	if _busy: return
	_ports.clear()
	_pending.clear()
	_dialogue.cancel()

func _call(key: String, args: Array = []) -> Variant:
	if not _ports.has(key): return null
	var owner: Object = _ports[key].owner.get_ref()
	if owner == null: return null
	return owner.callv(_ports[key].method, args)

func _port_alive(key: String) -> bool:
	return _ports.has(key) and _ports[key].owner.get_ref() != null

func _world() -> Dictionary:
	var world: Variant = _call("clock")
	if not world is Dictionary: return _fail("未注入有效时钟查询")
	if not Catalog.whole(world.get("day"), 1, 2147483647): return _fail("游戏日须从1开始且为整数")
	var hour: Variant = world.get("hour", 8.0)
	if not (hour is int or hour is float) or not is_finite(float(hour)) or hour < 0 or hour >= 24: return _fail("小时无效")
	if world.get("weather", "clear") not in ["clear", "cloudy", "rain", "storm"]: return _fail("未知天气")
	return {"ok": true, "day": int(world.day), "hour": float(hour), "weather": world.get("weather", "clear")}

func roster() -> Array:
	var out: Array = []
	for id in Catalog.ids(): out.append(npc_snapshot(id))
	return out

func character_profile(npc_id: String) -> Dictionary:
	return Catalog.character_profile(npc_id)

func conversation_topics(npc_id: String) -> Array:
	return Catalog.conversation_topics(npc_id)

## 主动话题不登记见面或交谈，不发业务事件，也不写持久状态。
func start_topic(npc_id: String, topic_id: String) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var topic := Catalog.get_topic(npc_id, topic_id)
	if topic.is_empty(): return _fail("未知NPC或话题")
	var result: Dictionary = _dialogue.start(npc_id + "_topic_" + topic_id, topic.pages)
	if result.ok: _pending = {"kind": "display", "npc_id": npc_id, "topic_id": topic_id}
	return result

func npc_snapshot(npc_id: String) -> Dictionary:
	var row := Catalog.snapshot_npc(npc_id)
	if row.is_empty(): return {}
	row["runtime"] = Graph.npc_snapshot(_state.graph, npc_id)
	row["dialogue_active"] = not _pending.is_empty() and _pending.get("npc_id") == npc_id
	row["requests"] = list_requests(npc_id)
	return row

func relationship_graph(_viewer := "player") -> Array: return Graph.graph(_state.graph)
func dialogue_state() -> Dictionary: return _dialogue.state()

func meet(npc_id: String) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	if not _state.graph.met.has(npc_id): return _fail("未知NPC")
	var already: bool = _state.graph.met[npc_id]
	if not already:
		_state.graph.met[npc_id] = true
		_busy = true
		npc_met.emit(npc_id)
		_busy = false
	return {"ok": true, "npc_id": npc_id, "already": already}

func talk(npc_id: String, day: Variant = null) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	if not _state.graph.met.has(npc_id): return _fail("未知NPC")
	if day == null or _port_alive("clock"):
		var world := _world()
		if not world.ok: return world
		if day != null and (not Catalog.whole(day, 1, 2147483647) or day != world.day): return _fail("显式日期与注入时钟不一致")
		day = world.day
	if not Catalog.whole(day, 1, 2147483647): return _fail("交谈日期须为正整数")
	if int(day) <= int(_state.graph.last_talk_day[npc_id]): return _fail("今天已交谈或时钟倒退")
	var was_met: bool = _state.graph.met[npc_id]
	_state.graph.met[npc_id] = true
	_state.graph.last_talk_day[npc_id] = int(day)
	var delta := _change_affinity(npc_id, 16)
	_busy = true
	if not was_met: npc_met.emit(npc_id)
	if delta != 0: affinity_changed.emit(npc_id, delta, "talk")
	_busy = false
	return {"ok": true, "npc_id": npc_id, "day": int(day), "delta": delta}

func request_vendor(npc_id: String) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var row := Catalog.get_npc(npc_id)
	if row.is_empty(): return _fail("未知NPC")
	if not row.has("shop_id"): return _fail("该NPC不是商店经营者")
	var result := meet(npc_id)
	if not result.ok: return result
	_busy = true
	vendor_requested.emit(npc_id, row.shop_id)
	_busy = false
	return {"ok": true, "npc_id": npc_id, "shop_id": row.shop_id}

func schedule_at(npc_id: String, world: Dictionary, anchors := {}) -> Dictionary:
	var result: Dictionary = _schedule.resolve(npc_id, world.duplicate(true), anchors.duplicate(true), _state)
	if result.get("fallback", false):
		schedule_fallback.emit(npc_id, result.requested_anchor, result.anchor_id)
		npc_schedule_fallback.emit(npc_id, result.requested_anchor, result.anchor_id)
	return result

## 自定义对白为纯展示兼容入口，不允许调用者注入结算结果。
func start_dialogue(dialogue_id: String, pages: Array) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var normalized: Array = []
	for i in pages.size():
		if not pages[i] is Dictionary: return _fail("页面须为对象")
		var page: Dictionary = pages[i].duplicate(true)
		if not page.has("id"): page["id"] = "page_%d" % i
		normalized.append(page)
	var error := DialogueRunner.validate_pages(normalized)
	if error != "": return _fail(error)
	for page in normalized:
		for choice in page.get("choices", []):
			if choice.has("effects"): return _fail("自定义展示对白不能包含结算")
	var result: Dictionary = _dialogue.start(dialogue_id, normalized)
	if result.ok: _pending = {"kind": "display"}
	return result

func start_npc_dialogue(npc_id: String, kind := "daily", context: Dictionary = {}) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	if kind == "topic":
		if not Catalog.fields(context, ["topic_id"]) or not context.topic_id is String: return _fail("话题情境须提供topic_id")
		return start_topic(npc_id, context.topic_id)
	var row := Catalog.snapshot_npc(npc_id)
	if row.is_empty(): return _fail("未知NPC")
	if kind == "arc":
		var available := list_events(npc_id)
		for event in available:
			if event.kind == "personal" and event.available and not event.completed: return start_event(event.id)
		return _fail("暂无可用个人剧情")
	if kind not in ["daily", "intro"]: return _fail("未知对白类型")
	if not Catalog.fields(context, [], ["period", "context"]): return _fail("未知日常情境字段")
	var world := _world()
	if not world.ok: return world
	var content := Catalog.dialogue_for(npc_id)
	var pages: Array = []
	var selected_id := npc_id + "_" + kind
	if kind == "intro":
		for i in content.get("intro", []).size():
			var page: Dictionary = content.intro[i].duplicate(true)
			page["id"] = "intro_%d" % i
			pages.append(page)
	else:
		var period: Variant = context.get("period", "morning" if world.hour < 10 else ("work" if world.hour < 17 else "evening"))
		var situation: Variant = context.get("context", "night" if world.hour >= 21.5 or world.hour < 6 else ("rain" if world.weather in ["rain", "storm"] else ("friend" if _state.graph.affinity[npc_id] >= 500 else "normal")))
		if period not in ["morning", "work", "evening"] or situation not in ["normal", "rain", "night", "friend"]: return _fail("未知对白情境")
		for entry in content.get("daily", []):
			if entry.period == period and entry.context == situation:
				selected_id = entry.id
				pages.append({"id": entry.id, "speaker": row.display_name, "text": _daily_text(entry, world)})
	if pages.is_empty(): pages = [{"id": "fallback", "speaker": row.display_name, "text": "先在这里歇一会儿吧，等我把手边这点事做完。"}]
	var result: Dictionary = _dialogue.start(selected_id, pages)
	if result.ok: _pending = {"kind": kind, "npc_id": npc_id, "day": world.day}
	return result

## 入场优先级：未读完的初见 > 已满足条件的未完成剧情 > 偶发日常 > 功能问候。
## 概率按游戏日/居民稳定取样，重开与读档不刷随机；不新增存档写入者。
func start_conversation(npc_id: String) -> Dictionary:
	var npc := npc_snapshot(npc_id)
	if npc.is_empty(): return _fail("未知NPC")
	if int(npc.runtime.last_talk_day) < 1:
		return start_npc_dialogue(npc_id, "intro")
	for event in list_events(npc_id):
		if event.available and not event.completed:
			return start_event(str(event.id))
	var world := _world()
	if not world.ok: return world
	if posmod((npc_id + ":" + str(world.day)).hash(), 4) == 0:
		return start_npc_dialogue(npc_id, "daily")
	return {"ok": true, "greeting_only": true}

## 只用现有时钟和剧情进度轮换；同一天重开及读档保持一致，不保存随机种子。
func _daily_text(entry: Dictionary, world: Dictionary) -> String:
	var count: int = entry.variants.size() + 1
	var weather_offset: int = ["clear", "cloudy", "rain", "storm"].find(world.weather)
	var index: int = (int(world.day) - 1 + weather_offset + _state.seen_events.size() + posmod(str(entry.id).hash(), count)) % count
	return entry.text if index == 0 else str(entry.variants[index - 1])

func list_events(npc_id := "") -> Array:
	if npc_id != "" and Catalog.get_npc(npc_id).is_empty(): return []
	var out: Array = []
	var world := _world()
	for event in Catalog.events():
		if npc_id != "" and npc_id not in event.npc_ids: continue
		var completed: bool = _state.seen_events.has(event.id)
		var available: bool = completed or (world.ok and _event_available(event, world))
		var row := {"id": event.id, "kind": event.kind, "title": event.title, "npc_ids": event.npc_ids.duplicate(),
			"available": available, "completed": completed, "replay": completed,
			"reason": "" if available else ("条件尚未满足" if world.ok else world.reason)}
		if completed: row["record"] = _state.seen_events[event.id].duplicate(true)
		out.append(row)
	return out

func _event_available(event: Dictionary, world: Dictionary) -> bool:
	for id in event.npc_ids:
		if not _state.graph.met[id]: return false
	return Catalog.matches(event.conditions, event.npc_ids, world, _state)

func start_event(event_id: String, replay := false) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var event := Catalog.get_event(event_id)
	if event.is_empty(): return _fail("未知剧情事件")
	var completed: bool = _state.seen_events.has(event_id)
	if replay and not completed: return _fail("未完成事件不能回看")
	var day := -1
	if not completed:
		var world := _world()
		if not world.ok: return world
		if not _event_available(event, world): return _fail("事件条件尚未满足")
		day = world.day
	var result: Dictionary = _dialogue.start(event_id, event.pages, completed)
	if result.ok:
		_pending = {"kind": "event", "event_id": event_id, "npc_id": event.npc_ids[0], "day": day, "replay": completed}
		result["replay"] = completed
	return result

func advance_dialogue(session_id := -1) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	return _finish_step(_dialogue.advance(session_id))

func choose_dialogue(choice_id: String, session_id := -1) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	return _finish_step(_dialogue.choose(choice_id, session_id))

func close_dialogue() -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var active: bool = _dialogue.state().active
	_dialogue.cancel()
	_pending.clear()
	return {"ok": true, "cancelled": active}

func cancel_dialogue() -> void: close_dialogue()

func _finish_step(result: Dictionary) -> Dictionary:
	if not result.get("ok", false) or not result.get("completed", false): return result
	var pending: Dictionary = _pending.duplicate(true)
	_pending.clear()
	if pending.get("replay", false):
		result["committed"] = false
		return result
	if pending.get("kind") == "event":
		return _commit_event(pending, result)
	if pending.get("kind") == "display" and pending.has("topic_id"):
		result["committed"] = false
		return result
	if pending.get("kind") in ["daily", "intro"]:
		result["talk_result"] = talk(pending.npc_id)
	_busy = true
	dialogue_completed.emit(result.dialogue_id)
	_busy = false
	result["committed"] = pending.get("kind") in ["daily", "intro"]
	return result

func _commit_event(pending: Dictionary, result: Dictionary) -> Dictionary:
	var event := Catalog.get_event(pending.event_id)
	if _state.seen_events.has(event.id):
		result["committed"] = false
		return result
	var before: Dictionary = _state.duplicate(true)
	_state.seen_events[event.id] = {"day": pending.day, "choices": result.choices.duplicate(true)}
	var effects: Array = [event.get("effects", {})]
	for page in event.pages:
		for choice in page.get("choices", []):
			if result.choices.get(page.id) == choice.id: effects.append(choice.get("effects", {}))
	for page_id in result.choices: _state.choice_flags[event.id + ":" + page_id] = result.choices[page_id]
	var edge_changes := {}
	var opened: Array = []
	for effect in effects:
		for id in effect.get("edges", {}):
			var old := int(_state.graph.edge_deltas[id])
			_state.graph.edge_deltas[id] = Graph.edge_value(id, old, int(effect.edges[id]))
			edge_changes[id] = int(edge_changes.get(id, 0)) + int(_state.graph.edge_deltas[id]) - old
		for id in effect.get("requests", []):
			if _state.request_states.has(id): continue
			_state.request_states[id] = {"status": "open", "source_event": event.id, "opened_day": pending.day}
			opened.append(id)
	var error := Codec.validate(_state)
	if error != "":
		_state = before
		return _fail(error)
	_busy = true
	for id in edge_changes:
		if edge_changes[id] != 0: relation_edge_changed.emit(id, edge_changes[id], event.id)
	for id in opened: npc_request_opened.emit(id)
	dialogue_completed.emit(event.id)
	_call("result", [{"kind": "npc_event", "event_id": event.id, "day": pending.day, "choices": result.choices.duplicate(true), "edge_changes": edge_changes.duplicate(true), "opened_requests": opened.duplicate()}])
	_busy = false
	result["committed"] = true
	return result

func list_requests(npc_id := "") -> Array:
	var out: Array = []
	for request in Catalog.requests():
		if npc_id != "" and npc_id != request.npc_id: continue
		if not _state.request_states.has(request.id): continue
		request["runtime"] = _state.request_states[request.id].duplicate(true)
		request["affinity_reward"] = 40
		request["can_fulfill"] = false
		if request.runtime.status == "open" and _port_alive("count"):
			var enough := true
			for item in request.costs:
				var count: Variant = _call("count", [item])
				if not Catalog.whole(count, 0, 2147483647) or count < request.costs[item]: enough = false
			request.can_fulfill = enough and (_port_alive("exchange") or (request.costs.size() == 1 and _port_alive("remove")))
		out.append(request)
	return out

func fulfill_request(request_id: String) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var request := Catalog.get_request(request_id)
	if request.is_empty(): return _fail("未知请求")
	if not _state.request_states.has(request_id): return _fail("请求尚未开启")
	if _state.request_states[request_id].status == "completed": return {"ok": true, "already": true, "request_id": request_id}
	var world := _world()
	if not world.ok: return world
	if world.day < _state.request_states[request_id].opened_day: return _fail("时钟早于请求开启日")
	_busy = true
	var paid := _pay(request.costs)
	if not paid.ok:
		_busy = false
		return paid
	_state.request_states[request_id].status = "completed"
	_state.request_states[request_id]["completed_day"] = world.day
	_state.request_states[request_id]["result_tag"] = request.result_tag
	var delta := _change_affinity(request.npc_id, 40)
	var result := {"ok": true, "already": false, "kind": "npc_request", "request_id": request_id, "npc_id": request.npc_id,
		"source_event": request.source_event, "followup": request.followup, "result_tag": request.result_tag, "day": world.day, "delta": delta}
	if delta != 0: affinity_changed.emit(request.npc_id, delta, request_id)
	request_completed.emit(request_id, result.duplicate(true))
	_call("result", [result.duplicate(true)])
	_busy = false
	return result

## 外部请求总账可调用此入口，但仍由同一原子库存端口交付，不接受伪造成功字段。
func acknowledge_request(request_id: String, result: Dictionary) -> Dictionary:
	if not Catalog.fields(result, ["result_tag"]) or not result.result_tag is String: return _fail("请求结果字段无效")
	var request := Catalog.get_request(request_id)
	if request.is_empty() or result.result_tag != request.result_tag: return _fail("请求结果不匹配")
	return fulfill_request(request_id)

func gift_options(npc_id: String) -> Dictionary:
	var row := Catalog.get_npc(npc_id)
	if row.is_empty(): return _fail("未知NPC")
	var world := _world()
	if not world.ok: return world
	var allowance := _gift_allowance(npc_id, world.day)
	var items: Array = []
	for item in Catalog.item_ids():
		var entry := {"item_id": item, "taste": _taste(row, item), "available": false}
		var count: Variant = _call("count", [item])
		if Catalog.whole(count, 0, 2147483647):
			entry["count"] = int(count)
			entry.available = count > 0 and allowance.ok and (_port_alive("exchange") or _port_alive("remove"))
		items.append(entry)
	return {"ok": true, "npc_id": npc_id, "day": world.day, "allowance": allowance, "items": items, "qualities": ["normal", "silver", "gold"]}

func _gift_allowance(npc_id: String, day: int) -> Dictionary:
	var week := str(int((day - 1) / 7))
	var birthday := (day - 1) % 112 + 1 == int(Catalog.get_npc(npc_id).birthday)
	var count := int(_state.graph.gift_count[npc_id]) if _state.graph.gift_week[npc_id] == week else 0
	var birthday_slot: bool = birthday and _state.graph.birthday_gift_day[npc_id] != day
	var forward := day >= int(_state.graph.last_gift_day[npc_id])
	return {"ok": forward and (birthday_slot or count < 2), "week": week, "count": count,
		"normal_remaining": maxi(0, 2 - count), "birthday": birthday, "birthday_available": birthday_slot,
		"slot": "birthday" if birthday_slot else "weekly", "reason": "" if forward and (birthday_slot or count < 2) else "周额度已满或时钟倒退"}

func give_gift(npc_id: String, item_id: String, quality := "normal") -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var row := Catalog.get_npc(npc_id)
	if row.is_empty(): return _fail("未知NPC")
	if item_id not in Catalog.item_ids(): return _fail("未知或不可赠送物品")
	if quality not in ["normal", "silver", "gold"]: return _fail("未知礼物品质")
	var world := _world()
	if not world.ok: return world
	var allowance := _gift_allowance(npc_id, world.day)
	if not allowance.ok: return _fail(allowance.reason)
	var taste := _taste(row, item_id)
	var base := int({"love": 40, "like": 24, "normal": 8, "dislike": -12, "hate": -24}[taste])
	var quality_multiplier := float({"normal": 1.0, "silver": 1.1, "gold": 1.2}[quality])
	var requested_delta := clampi(roundi(base * (3 if allowance.birthday else 1) * quality_multiplier), -80, 120)
	_busy = true
	var paid := _pay({item_id: 1})
	if not paid.ok:
		_busy = false
		return paid
	var was_met: bool = _state.graph.met[npc_id]
	_state.graph.met[npc_id] = true
	_state.graph.gift_week[npc_id] = allowance.week
	_state.graph.gift_count[npc_id] = allowance.count + (0 if allowance.slot == "birthday" else 1)
	_state.graph.last_gift_day[npc_id] = world.day
	if allowance.slot == "birthday": _state.graph.birthday_gift_day[npc_id] = world.day
	var delta := _change_affinity(npc_id, requested_delta)
	var result := {"ok": true, "npc_id": npc_id, "item_id": item_id, "quality": quality, "taste": taste, "delta": delta,
		"calculated_delta": requested_delta, "birthday": allowance.birthday, "slot": allowance.slot, "week": allowance.week, "day": world.day}
	if not was_met: npc_met.emit(npc_id)
	if delta != 0: affinity_changed.emit(npc_id, delta, "gift")
	_call("result", [result.duplicate(true)])
	_busy = false
	return result

func _taste(row: Dictionary, item: String) -> String:
	for taste in ["love", "like", "dislike", "hate"]:
		if item in row.tastes[taste]: return taste
	return "normal"

func _pay(costs: Dictionary) -> Dictionary:
	var result: Variant
	if _port_alive("exchange"):
		result = _call("exchange", [costs.duplicate(true), {}])
	elif costs.size() == 1 and _port_alive("remove"):
		var item: String = costs.keys()[0]
		result = _call("remove", [item, int(costs[item])])
	else: return _fail("未注入原子库存exchange/remove端口")
	if result is bool:
		return {"ok": true} if result else _fail("库存不足或拒绝交付")
	if result is Dictionary and result.get("ok") is bool:
		return {"ok": true} if result.ok else _fail(str(result.get("reason", "库存拒绝交付")))
	return _fail("库存端口返回契约错误")

func _change_affinity(npc_id: String, delta: int) -> int:
	var old := int(_state.graph.affinity[npc_id])
	_state.graph.affinity[npc_id] = Graph.affinity_value(old, delta)
	return int(_state.graph.affinity[npc_id]) - old

func to_dict() -> Dictionary:
	# 保存取消尚未提交会话；不会把待选分支偷偷结算进存档。
	if not _busy: close_dialogue()
	return _state.duplicate(true)

func from_dict(value: Variant) -> Dictionary:
	if _busy: return _fail("服务正在结算")
	var decoded: Dictionary = Codec.decode(value)
	if not decoded.ok: return decoded
	close_dialogue()
	_state = decoded.snapshot
	return {"ok": true}

func validate_snapshot(value: Variant) -> String: return Codec.validate(value)

func _fail(reason: String) -> Dictionary: return {"ok": false, "reason": reason}
