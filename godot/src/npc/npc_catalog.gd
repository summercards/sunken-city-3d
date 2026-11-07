extends RefCounted
## 静态内容统一入口；所有公开集合均为深副本，不持有运行状态。
const PATH := "res://assets/data/npc/npcs.json"
const BASE := "res://assets/data/npc/"
const AvatarCatalog = preload("res://src/avatar/avatar_catalog.gd")
const AvatarProfile = preload("res://src/avatar/avatar_profile.gd")
const DialogueRunner = preload("res://src/npc/npc_dialogue_runner.gd")
static var _data: Dictionary = {}

static func _load() -> void:
	if not _data.is_empty(): return
	for pair in [["roster", PATH], ["dialogues", BASE + "dialogues.json"], ["events", BASE + "events.json"], ["requests", BASE + "requests.json"], ["residences", BASE + "residences.json"], ["items", "res://assets/data/items.json"]]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pair[1]))
		_data[pair[0]] = parsed if parsed is Dictionary else {}

static func data() -> Dictionary:
	_load()
	return _data.roster.duplicate(true)

static func all() -> Array:
	_load()
	return _data.roster.get("npcs", []).duplicate(true)
static func relationships() -> Array:
	_load()
	return _data.roster.get("relationships", []).duplicate(true)
static func calendar() -> Dictionary:
	_load()
	return _data.roster.get("calendar", {}).duplicate(true)
static func ids() -> Array:
	_load()
	var out: Array = []
	for row in _data.roster.get("npcs", []): out.append(row.id)
	return out

static func get_npc(id: String) -> Dictionary:
	_load()
	return _find(_data.roster.get("npcs", []), id)

## 高频状态查询不复制静态人物背景；完整背景由独立查询提供。
static func snapshot_npc(npc_id: String) -> Dictionary:
	_load()
	for row in _data.roster.get("npcs", []):
		if row.id != npc_id: continue
		var result := {}
		for key in row:
			if key not in ["profile", "social_notes"]: result[key] = row[key]
		return result.duplicate(true)
	return {}

static func character_profile(npc_id: String) -> Dictionary:
	_load()
	for row in _data.roster.get("npcs", []):
		if row.id == npc_id:
			return {"npc_id": npc_id, "display_name": row.display_name, "profile": row.profile, "social_notes": row.social_notes}.duplicate(true)
	return {}

static func conversation_topics(npc_id: String) -> Array:
	_load()
	var result: Array = []
	for content in _data.dialogues.get("dialogues", []):
		if content.npc_id != npc_id: continue
		for topic in content.get("topics", []): result.append({"id": topic.id, "title": topic.title})
	return result

static func get_topic(npc_id: String, topic_id: String) -> Dictionary:
	_load()
	for content in _data.dialogues.get("dialogues", []):
		if content.npc_id == npc_id: return _find(content.get("topics", []), topic_id)
	return {}
static func profile(npc_id: String) -> Dictionary:
	var row := get_npc(npc_id)
	if row.is_empty(): return {}
	var result := AvatarProfile.fresh(true)
	result.name = row.display_name
	for slot in row.appearance: result.appearance[slot] = row.appearance[slot]
	for morph in row.morphs: result.morphs[morph] = row.morphs[morph]
	return result.duplicate(true)
static func events() -> Array:
	_load()
	return _data.events.get("events", []).duplicate(true)
static func requests() -> Array:
	_load()
	return _data.requests.get("requests", []).duplicate(true)
static func dialogues() -> Array:
	_load()
	return _data.dialogues.get("dialogues", []).duplicate(true)
static func get_event(id: String) -> Dictionary: return _find(events(), id)
static func get_request(id: String) -> Dictionary: return _find(requests(), id)
static func item_ids() -> Array:
	_load()
	var out: Array = []
	for item in _data.items.get("items", []):
		if item.get("category") != "currency": out.append(item.id)
	return out

static func _find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if row.get("id") == id: return row.duplicate(true)
	return {}

static func dialogue_for(npc_id: String) -> Dictionary:
	_load()
	for row in _data.dialogues.get("dialogues", []):
		if row.npc_id == npc_id: return row.duplicate(true)
	return {}

static func whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float): return false
	return is_finite(float(value)) and value >= low and value <= high and float(value) == floor(float(value))

static func fields(value: Variant, required: Array, optional: Array = []) -> bool:
	if not value is Dictionary: return false
	for key in required:
		if not value.has(key): return false
	for key in value:
		if not key is String or (key not in required and key not in optional): return false
	return true

static func condition_error(c: Variant) -> String:
	if not fields(c, [], ["affinity", "events", "requests", "weather", "weekdays", "hour_from", "hour_to", "edge"]): return "未知或无效条件字段"
	if c.has("affinity") and not whole(c.affinity, 0, 1000): return "好感条件无效"
	for key in ["events", "requests", "weather", "weekdays"]:
		if not c.has(key): continue
		if not c[key] is Array or c[key].is_empty(): return "条件数组为空"
		var seen := {}
		for id in c[key]:
			if key == "weekdays":
				if not whole(id, 1, 7): return "星期须为1至7整数"
			elif not id is String: return "条件ID类型无效"
			if seen.has(id): return "重复条件ID"
			seen[id] = true
			if key == "events" and get_event(str(id)).is_empty(): return "未知前置事件"
			if key == "requests" and get_request(str(id)).is_empty(): return "未知前置请求"
			if key == "weather" and id not in ["clear", "cloudy", "rain", "storm"]: return "未知天气"
	for key in ["hour_from", "hour_to"]:
		if c.has(key) and not _number(c[key], 0, 24): return "时间条件无效"
	if c.get("hour_from", 0) >= c.get("hour_to", 24): return "时间条件倒置"
	if c.has("edge"):
		if not fields(c.edge, ["id", "min"]) or _find(relationships(), str(c.edge.id)).is_empty() or not whole(c.edge.min, -100, 100): return "关系条件无效"
	return ""

static func matches(c: Dictionary, npc_ids: Array, world: Dictionary, state: Dictionary) -> bool:
	for id in npc_ids:
		if int(state.graph.affinity.get(id, 0)) < int(c.get("affinity", 0)): return false
	for id in c.get("events", []):
		if not state.seen_events.has(id): return false
	for id in c.get("requests", []):
		if state.request_states.get(id, {}).get("status") != "completed": return false
	if c.has("weather") and world.get("weather", "clear") not in c.weather: return false
	var day := int(world.get("day", 1))
	if c.has("weekdays"):
		# JSON 数字读取为 float，数组成员判断区分 int/float，先按日历整数比较。
		var weekday: int = (day - 1) % 7 + 1
		var matched := false
		for allowed_day in c.weekdays:
			if whole(allowed_day, 1, 7) and int(allowed_day) == weekday: matched = true
		if not matched: return false
	var hour := float(world.get("hour", 8.0))
	if hour < float(c.get("hour_from", 0)) or hour >= float(c.get("hour_to", 24)): return false
	if c.has("edge"):
		var edge := _find(relationships(), str(c.edge.id))
		if clampi(int(edge.base) + int(state.graph.edge_deltas[c.edge.id]), -100, 100) < int(c.edge.min): return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func effects_error(effects: Variant) -> String:
	if not fields(effects, [], ["edges", "requests"]): return "未知剧情结果字段"
	if effects.has("edges"):
		if not effects.edges is Dictionary: return "关系结果须为对象"
		for id in effects.edges:
			if _find(relationships(), str(id)).is_empty() or not whole(effects.edges[id], -100, 100): return "无效关系结果"
	if effects.has("requests"):
		if not effects.requests is Array: return "请求结果须为数组"
		for id in effects.requests:
			if not id is String or get_request(id).is_empty(): return "未知结果请求"
	return ""

static func _nonempty_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _person_error(row: Dictionary, npc_ids: Array) -> String:
	if not fields(row.profile, ["age_group", "age_range", "personality", "past", "arrival_reason", "short_term_wish", "secret_or_regret", "habit", "catchphrase"]): return "人物背景字段无效"
	for value in row.profile.values():
		if not _nonempty_text(value): return "人物背景须为非空文字"
	if row.profile.age_group != "成人": return "七名居民须为成人"
	if not row.social_notes is Array or row.social_notes.size() != 6: return "每人须有六条相处看法"
	var others := {}
	for note in row.social_notes:
		if not fields(note, ["npc_id", "text"]): return "相处看法字段无效"
		if not note.npc_id is String or note.npc_id not in npc_ids or note.npc_id == row.id or others.has(note.npc_id) or not _nonempty_text(note.text): return "相处看法须覆盖其余六人且不重复"
		others[note.npc_id] = true
	return ""

static func validate() -> String:
	_load()
	for pair in [["dialogues", "dialogues"], ["events", "events"], ["requests", "requests"]]:
		if not fields(_data[pair[0]], ["schema", pair[1]]) or not _data[pair[0]][pair[1]] is Array: return "内容根字段无效"
	if not fields(_data.roster, ["schema", "calendar", "npcs", "relationships"]): return "NPC根字段无效"
	if not _data.roster.npcs is Array or all().size() != 7: return "居民须为七人"
	if not _data.roster.relationships is Array or relationships().size() != 9: return "关系边须为九条"
	if not fields(calendar(), ["days_per_week", "days_per_year", "first_day", "birthday_slot"]) or calendar().days_per_week != 7 or calendar().days_per_year != 112 or calendar().first_day != 1: return "日历约定无效"
	var homes: Dictionary = {}
	var seen: Dictionary = {}
	var skins: Dictionary = {}
	var appearance_combinations: Dictionary = {}
	var residences: Array = _data.residences.get("residences", [])
	var allowed_items := item_ids()
	var npc_ids: Array = []
	for row in _data.roster.npcs:
		if not row is Dictionary or not _nonempty_text(row.get("id")): return "NPC身份无效"
		npc_ids.append(row.id)
	for row in all():
		if not fields(row, ["id", "display_name", "role", "home_anchor", "residence_id", "activity_anchor", "accessory_id", "birthday", "appearance", "morphs", "tastes", "schedule", "profile", "social_notes"], ["shop_id"]): return "NPC字段无效"
		for key in ["id", "display_name", "role", "home_anchor", "residence_id", "activity_anchor", "accessory_id"]:
			if not row[key] is String or row[key].is_empty(): return "身份字段无效"
		if seen.has(row.id) or homes.has(row.residence_id) or _find(residences, row.residence_id).is_empty(): return "重复身份或无效住所"
		seen[row.id] = true
		homes[row.residence_id] = true
		var person_error := _person_error(row, npc_ids)
		if person_error != "": return person_error
		if row.home_anchor != row.residence_id or not whole(row.birthday, 1, 112): return "住所或生日无效"
		if row.has("shop_id") and (not row.shop_id is String or row.shop_id not in ["shop_flower", "shop_general"]): return "未知商店引用"
		if not row.appearance is Dictionary: return "外观须为对象"
		for slot in ["skin", "body_type", "hair_style", "top_color"]:
			if not row.appearance.get(slot) is String: return "外观须明确配置 " + slot
		if not fields(row.morphs, AvatarCatalog.morph_defaults().keys()) or row.morphs.size() != 9: return "居民须明确配置九项形体参数"
		for morph in row.morphs:
			if not _number(row.morphs[morph], 0.0, 1.0): return "形体参数须为0至1有限数"
		skins[row.appearance.skin] = true
		var combination: String = "%s:%s:%s" % [row.appearance.body_type, row.appearance.hair_style, row.appearance.top_color]
		if appearance_combinations.has(combination): return "居民体型、发型、上装配色组合重复"
		appearance_combinations[combination] = true
		for slot in row.appearance:
			var found := false
			for option in AvatarCatalog.options(slot):
				if option.id == row.appearance[slot]: found = true
			if not found: return "%s 外观ID无效：%s=%s" % [row.id, slot, row.appearance[slot]]
		var profile_error := AvatarProfile.validate_snapshot(profile(row.id))
		if profile_error != "": return profile_error
		if not fields(row.tastes, ["love", "like", "dislike", "hate"]): return "喜好字段无效"
		var tasted := {}
		for taste in row.tastes:
			if not row.tastes[taste] is Array: return "喜好须为数组"
			for item in row.tastes[taste]:
				if item not in allowed_items or tasted.has(item): return "重复或未知礼物"
				tasted[item] = true
		if not row.schedule is Array or row.schedule.size() < 3: return "日程不足"
		for rule in row.schedule:
			if not fields(rule, ["from", "to", "anchor", "action"], ["priority", "conditions"]): return "日程字段无效"
			if not _number(rule.from, 0, 24) or not _number(rule.to, 0, 24) or rule.from >= rule.to: return "日程时间无效"
			if not rule.anchor is String or rule.anchor.is_empty() or not rule.action is String or rule.action.is_empty(): return "日程锚点或动作无效"
			if not whole(rule.get("priority", 0), 0, 100): return "日程优先级无效"
			var error := condition_error(rule.get("conditions", {}))
			if error != "": return error
	if skins.size() < 4: return "七人须覆盖至少四种肤色"
	var edge_seen := {}
	for edge in relationships():
		if not fields(edge, ["id", "from", "to", "type", "base", "summary", "history", "tension", "reconcile"]): return "关系字段无效"
		for key in ["type", "summary", "history", "tension", "reconcile"]:
			if not _nonempty_text(edge[key]): return "关系详情须为非空文字"
		if not edge.id is String or edge.id.is_empty() or edge_seen.has(edge.id) or not seen.has(edge.from) or not seen.has(edge.to) or edge.from == edge.to or not whole(edge.base, -100, 100): return "关系引用无效"
		edge_seen[edge.id] = true
	if dialogues().size() != 7: return "对白居民数无效"
	var dialogue_seen := {}
	var daily_ids := {}
	var texts := {}
	for content in dialogues():
		if not fields(content, ["npc_id", "intro", "daily", "topics"]) or not seen.has(content.npc_id) or dialogue_seen.has(content.npc_id): return "对白身份无效"
		dialogue_seen[content.npc_id] = true
		var speaker: String = get_npc(content.npc_id).display_name
		if not content.intro is Array or content.intro.size() != 3: return "初见对白须为三页"
		for page in content.intro:
			if not fields(page, ["speaker", "text"]) or page.speaker != speaker or not _nonempty_text(page.text): return "初见对白无效"
		if not content.daily is Array or content.daily.size() != 12: return "日常对白须每人12槽"
		var slots := {}
		for entry in content.daily:
			if not fields(entry, ["id", "period", "context", "text", "variants"]): return "日常字段无效"
			if not _nonempty_text(entry.id) or entry.period not in ["morning", "work", "evening"] or entry.context not in ["normal", "rain", "night", "friend"]: return "日常情境无效"
			var slot: String = entry.period + ":" + entry.context
			if slots.has(slot) or daily_ids.has(entry.id): return "重复日常槽位或ID"
			slots[slot] = true
			daily_ids[entry.id] = true
			if not entry.variants is Array or entry.variants.size() < 2: return "每槽须有至少两条日常变体"
			var lines: Array = [entry.text]
			lines.append_array(entry.variants)
			for line in lines:
				if not _nonempty_text(line) or texts.has(line): return "重复或空白日常内容"
				texts[line] = true
		if not content.topics is Array or content.topics.size() != 4: return "每人须有四个主动话题"
		var topic_seen := {}
		for topic in content.topics:
			if not fields(topic, ["id", "title", "pages"]) or topic.id not in ["past", "daily", "friends", "plans"] or topic_seen.has(topic.id) or not _nonempty_text(topic.title): return "话题身份字段无效"
			topic_seen[topic.id] = true
			if not topic.pages is Array or topic.pages.size() < 2: return "每话题须有至少两页"
			var topic_error := DialogueRunner.validate_pages(topic.pages)
			if topic_error != "": return topic_error
			for page in topic.pages:
				if not fields(page, ["id", "speaker", "text"]) or page.speaker != speaker: return "话题只能含顺序展示页"
			if topic.id == "friends":
				var named_other := false
				for other in _data.roster.npcs:
					if other.id == content.npc_id: continue
					for page in topic.pages:
						if page.text.contains(other.display_name): named_other = true
				if not named_other: return "朋友话题须点名具体邻人"
	if events().size() != 25: return "剧情事件须为25个"
	var personal := {}
	var event_seen := {}
	var relation_count := 0
	for event in events():
		if not fields(event, ["id", "kind", "title", "npc_ids", "conditions", "pages"], ["effects"]): return "事件字段无效"
		if not event.id is String or event.id.is_empty() or event_seen.has(event.id) or not event.title is String or event.title.is_empty(): return "事件身份无效"
		event_seen[event.id] = true
		if not event.npc_ids is Array or event.npc_ids.is_empty(): return "事件人物缺失"
		for id in event.npc_ids:
			if not seen.has(id): return "事件人物未知"
		if event.kind == "personal" and event.npc_ids.size() == 1:
			personal[event.npc_ids[0]] = int(personal.get(event.npc_ids[0], 0)) + 1
		elif event.kind == "relationship" and event.npc_ids.size() == 2: relation_count += 1
		else: return "事件类型无效"
		var error := condition_error(event.conditions)
		if error != "": return error
		error = DialogueRunner.validate_pages(event.pages)
		if error != "": return event.id + ":" + error
		error = effects_error(event.get("effects", {}))
		if error != "": return error
		for page in event.pages:
			for choice in page.get("choices", []):
				error = effects_error(choice.get("effects", {}))
				if error != "": return error
	for id in ids():
		if personal.get(id, 0) != 3: return "每人须有三个个人事件"
	if relation_count != 4: return "关系事件须为四个"
	for event in events():
		if _dependency_cycle(event.id, []): return "事件前置存在循环"
	if requests().size() != 7: return "请求须为七个"
	var request_seen := {}
	for request in requests():
		if not fields(request, ["id", "npc_id", "title", "description", "source_event", "costs", "result_tag", "followup"]): return "请求字段无效"
		for key in ["id", "npc_id", "title", "description", "source_event", "result_tag", "followup"]:
			if not request[key] is String or request[key].is_empty(): return "请求字段为空"
		if request_seen.has(request.id) or not seen.has(request.npc_id): return "重复请求或未知居民"
		request_seen[request.id] = true
		var source := get_event(request.source_event)
		var followup := get_event(request.followup)
		if source.is_empty() or followup.is_empty() or request.id not in source.get("effects", {}).get("requests", []) or request.id not in followup.conditions.get("requests", []): return "请求剧情链断开"
		if not request.costs is Dictionary or request.costs.is_empty(): return "请求交付内容缺失"
		for item in request.costs:
			if item not in allowed_items or not whole(request.costs[item], 1, 99): return "请求物品或数量无效"
	return ""

static func _dependency_cycle(id: String, trail: Array) -> bool:
	if id in trail: return true
	var next: Array = trail.duplicate()
	next.append(id)
	for parent in get_event(id).get("conditions", {}).get("events", []):
		if _dependency_cycle(parent, next): return true
	return false
