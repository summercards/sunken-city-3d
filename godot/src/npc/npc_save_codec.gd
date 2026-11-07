extends RefCounted
## 版本1的纯快照编解码；不加载 Service，也不创建任何运行对象。
const VERSION := 1
const Catalog = preload("res://src/npc/npc_catalog.gd")

static func empty_snapshot() -> Dictionary:
	var graph := {"met": {}, "affinity": {}, "last_talk_day": {}, "gift_week": {}, "gift_count": {}, "birthday_gift_day": {}, "last_gift_day": {}, "edge_deltas": {}}
	for id in Catalog.ids():
		graph.met[id] = false
		graph.affinity[id] = 0
		graph.last_talk_day[id] = -1
		graph.gift_week[id] = ""
		graph.gift_count[id] = 0
		graph.birthday_gift_day[id] = -1
		graph.last_gift_day[id] = -1
	for edge in Catalog.relationships(): graph.edge_deltas[edge.id] = 0
	return {"version": VERSION, "graph": graph, "seen_events": {}, "choice_flags": {}, "request_states": {}}

static func validate(value: Variant) -> String:
	if not Catalog.fields(value, ["version", "graph", "seen_events", "choice_flags", "request_states"]): return "NPC快照缺少或含未知字段"
	if not Catalog.whole(value.version, 1, 1): return "npc.version须为1"
	var defaults := empty_snapshot()
	if not Catalog.fields(value.graph, defaults.graph.keys()): return "关系快照字段错误"
	for key in defaults.graph:
		if not Catalog.fields(value.graph[key], defaults.graph[key].keys()): return "关系快照缺少或含未知ID：" + key
	for id in Catalog.ids():
		var g: Dictionary = value.graph
		if not g.met[id] is bool: return "相识状态须为布尔"
		if not Catalog.whole(g.affinity[id], 0, 1000): return "好感须为0至1000整数"
		for key in ["last_talk_day", "birthday_gift_day", "last_gift_day"]:
			if not Catalog.whole(g[key][id], -1, 2147483647) or g[key][id] == 0: return "记录日期无效"
		if not Catalog.whole(g.gift_count[id], 0, 2) or not g.gift_week[id] is String: return "送礼周计数无效"
		if g.last_gift_day[id] == -1:
			if g.gift_week[id] != "" or g.gift_count[id] != 0 or g.birthday_gift_day[id] != -1: return "空送礼记录不一致"
		else:
			if g.gift_week[id] != str(int((int(g.last_gift_day[id]) - 1) / 7)): return "送礼周次不一致"
			if g.birthday_gift_day[id] > g.last_gift_day[id]: return "生日记录晚于送礼记录"
			if g.birthday_gift_day[id] != -1 and (int(g.birthday_gift_day[id]) - 1) % 112 + 1 != int(Catalog.get_npc(id).birthday): return "生日礼物不在生日"
			if g.gift_count[id] == 0 and g.birthday_gift_day[id] != g.last_gift_day[id]: return "送礼计数缺失"
		if not g.met[id] and (g.affinity[id] != 0 or g.last_talk_day[id] != -1 or g.last_gift_day[id] != -1): return "未相识居民含交往记录"
	if not value.seen_events is Dictionary or not value.choice_flags is Dictionary or not value.request_states is Dictionary: return "剧情或请求须为对象"
	if value.seen_events.size() > 25 or value.choice_flags.size() > 64 or value.request_states.size() > 7: return "剧情记录数量超限"
	for key in value.choice_flags:
		if not key is String or not value.choice_flags[key] is String: return "选择标记须为字符串"
	var expected_flags := {}
	var expected_edges: Dictionary = defaults.graph.edge_deltas.duplicate(true)
	for id in value.seen_events:
		if not id is String: return "剧情ID须为字符串"
		var event := Catalog.get_event(id)
		var record: Variant = value.seen_events[id]
		if event.is_empty() or not Catalog.fields(record, ["day", "choices"]) or not Catalog.whole(record.day, 1, 2147483647) or not record.choices is Dictionary: return "剧情记录无效或未知事件"
		for npc_id in event.npc_ids:
			if not value.graph.met[npc_id]: return "剧情人物未相识"
		for parent in event.conditions.get("events", []):
			if not value.seen_events.has(parent): return "剧情前置缺失"
			var parent_record: Variant = value.seen_events[parent]
			if not parent_record is Dictionary or not Catalog.whole(parent_record.get("day"), 1, int(record.day)): return "剧情前置日期无效"
		var error := _validate_path(event, record.choices)
		if error != "": return error
		for page in record.choices: expected_flags[id + ":" + page] = record.choices[page]
		for request_id in event.conditions.get("requests", []):
			var request: Variant = value.request_states.get(request_id)
			if not request is Dictionary or not request.get("status") is String: return "剧情请求前置格式无效"
			if request.status != "completed" or not Catalog.whole(request.get("completed_day"), 1, int(record.day)): return "剧情请求前置缺失"
	# 边值以事件发生日及内容顺序重建，同日事件提交次序不会改变同向的首批结果。
	var ordered: Array = value.seen_events.keys()
	ordered.sort_custom(func(a, b):
		if value.seen_events[a].day == value.seen_events[b].day: return str(a) < str(b)
		return value.seen_events[a].day < value.seen_events[b].day)
	for id in ordered:
		var event := Catalog.get_event(id)
		var effects: Array = [event.get("effects", {})]
		for page in event.pages:
			for choice in page.get("choices", []):
				if value.seen_events[id].choices.get(page.id) == choice.id: effects.append(choice.get("effects", {}))
		for effect in effects:
			for edge_id in effect.get("edges", {}):
				var base := 0
				for edge in Catalog.relationships():
					if edge.id == edge_id: base = int(edge.base)
				expected_edges[edge_id] = clampi(base + int(expected_edges[edge_id]) + int(effect.edges[edge_id]), -100, 100) - base
	if value.choice_flags != expected_flags: return "选择标记与剧情路径不一致"
	for edge in Catalog.relationships():
		if not Catalog.whole(value.graph.edge_deltas[edge.id], -100 - int(edge.base), 100 - int(edge.base)) or value.graph.edge_deltas[edge.id] != expected_edges[edge.id]: return "关系边无可追溯的剧情结果"
	for id in value.request_states:
		if not id is String: return "请求ID须为字符串"
		var request := Catalog.get_request(id)
		var record: Variant = value.request_states[id]
		if request.is_empty() or not Catalog.fields(record, ["status", "source_event", "opened_day"], ["completed_day", "result_tag"]): return "请求记录字段错误"
		if not record.status is String or not record.source_event is String: return "请求状态或来源类型错误"
		if record.has("result_tag") and not record.result_tag is String: return "请求结果标签类型错误"
		if record.source_event != request.source_event or not value.seen_events.has(request.source_event): return "请求来源剧情缺失"
		if not Catalog.whole(record.opened_day, 1, 2147483647) or record.opened_day != value.seen_events[request.source_event].day: return "请求开启日期错误"
		if record.status == "open":
			if record.has("completed_day") or record.has("result_tag"): return "未完成请求含结算字段"
		elif record.status == "completed":
			if not Catalog.whole(record.get("completed_day"), int(record.opened_day), 2147483647) or record.get("result_tag") != request.result_tag: return "请求结果无效"
		else: return "未知请求状态"
	for event_id in value.seen_events:
		for id in Catalog.get_event(event_id).get("effects", {}).get("requests", []):
			if not value.request_states.has(id): return "剧情开启的请求记录缺失"
	return ""

static func _validate_path(event: Dictionary, choices: Dictionary) -> String:
	var used := {}
	var index := 0
	while index < event.pages.size():
		var page: Dictionary = event.pages[index]
		var next: String = page.get("next", event.pages[index + 1].id if index + 1 < event.pages.size() else "")
		if page.has("choices"):
			var selected: Variant = choices.get(page.id)
			var found := false
			for choice in page.choices:
				if selected is String and selected == choice.id:
					next = choice.next
					found = true
			if not found: return "剧情选择缺失或未知"
			used[page.id] = selected
		if next.is_empty(): break
		var next_index := -1
		for i in event.pages.size():
			if event.pages[i].id == next: next_index = i
		if next_index <= index: return "无效剧情路径"
		index = next_index
	if used != choices: return "包含未到达页选择"
	return ""

static func decode(value: Variant) -> Dictionary:
	# 必须先严格验证，不能以 int() 将小数、非有限数或坏字段洗成合法数据。
	var error := validate(value)
	if error != "": return {"ok": false, "reason": error}
	var snapshot: Dictionary = value.duplicate(true)
	snapshot.version = VERSION
	for key in ["affinity", "last_talk_day", "gift_count", "birthday_gift_day", "last_gift_day", "edge_deltas"]:
		for id in snapshot.graph[key]: snapshot.graph[key][id] = int(snapshot.graph[key][id])
	for id in snapshot.seen_events: snapshot.seen_events[id].day = int(snapshot.seen_events[id].day)
	for id in snapshot.request_states:
		snapshot.request_states[id].opened_day = int(snapshot.request_states[id].opened_day)
		if snapshot.request_states[id].has("completed_day"):
			snapshot.request_states[id].completed_day = int(snapshot.request_states[id].completed_day)
	return {"ok": true, "snapshot": snapshot}

static func migrate(value: Variant) -> Dictionary:
	if value == null: return {"ok": true, "snapshot": empty_snapshot(), "migrated": true}
	var result := decode(value)
	if not result.ok: return result
	result["migrated"] = false
	return result
