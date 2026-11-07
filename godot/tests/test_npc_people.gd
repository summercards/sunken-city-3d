extends SceneTree
## 由主线程登记统一 runner 的 npc-people；不直接运行引擎、不接 Main 或场景。
const Catalog = preload("res://src/npc/npc_catalog.gd")
const Service = preload("res://src/npc/npc_service.gd")
const Codec = preload("res://src/npc/npc_save_codec.gd")
const NAMES := {"npc_luo_yan": "船老大", "npc_mu_he": "豆豆", "npc_ji_chen": "阿海", "npc_nan_zhi": "木头叔", "npc_bai_shi": "灯伯", "npc_hua_yi": "小花", "npc_bao_he": "阿店"}
const PREFIXES := ["route", "seed", "echo", "joint", "lamp", "flower", "shelf"]
const EDGE_IDS := ["edge_route_seed", "edge_route_echo", "edge_route_joint", "edge_seed_joint", "edge_seed_lamp", "edge_echo_lamp", "edge_joint_lamp", "edge_seed_flower", "edge_flower_shelf"]
const BASES := [65, -35, 20, 55, 35, -20, 75, 60, 45]
const REQUEST_IDS := ["request_route_rope", "request_seed_trial", "request_echo_box", "request_joint_bench", "request_lamp_glass", "request_flower_pot", "request_shelf_basket"]
const COSTS := [{"rope": 2}, {"seed": 3}, {"parts": 2}, {"wood": 3}, {"glass": 2}, {"shell": 3}, {"rope": 2}]
const TAGS := ["route_buoy_secured", "seed_trial_sprouted", "echo_log_box_repaired", "joint_bench_rebuilt", "lamp_shade_restored", "flower_pot_drained", "shelf_basket_opened"]
var checks := 0
var failures := 0
var signals_seen: Array = []

class Ports extends RefCounted:
	var day := 1
	var hour := 12.0
	var weather := "clear"
	var exchanges := 0
	var results := 0
	func clock() -> Dictionary: return {"day": day, "hour": hour, "weather": weather}
	func exchange(_costs: Dictionary, _gains: Dictionary) -> bool:
		exchanges += 1
		return true
	func result(_value: Dictionary) -> void: results += 1

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-people] ", label)

func _costs_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for key in expected:
		if not actual.has(key) or actual[key] != expected[key]: return false
	return true

func _met(_id: String) -> void: signals_seen.append("met")
func _affinity(_id: String, _delta: int, _reason: String) -> void: signals_seen.append("affinity")
func _edge(_id: String, _delta: int, _reason: String) -> void: signals_seen.append("edge")
func _opened(_id: String) -> void: signals_seen.append("request")
func _done(_id: String) -> void: signals_seen.append("dialogue")
func _gift_or_request(_id: String, _value: Dictionary) -> void: signals_seen.append("completed_request")
func _vendor(_id: String, _shop: String) -> void: signals_seen.append("vendor")

func make_service(ports: Ports) -> Service:
	var service = Service.new()
	check(service.configure(ports.clock, ports.exchange, Callable(), Callable(), ports.result).ok, "合法目录与端口配置")
	return service

func finish(service) -> Dictionary:
	for step in 64:
		var state: Dictionary = service.dialogue_state()
		if not state.active: return {"ok": false, "reason": "会话提前结束"}
		var result: Dictionary = service.advance_dialogue(state.session_id)
		if not result.ok or result.get("completed", false): return result
	return {"ok": false, "reason": "会话未在有限步内完成"}

func test_content() -> void:
	check(Catalog.validate() == "", "严格内容校验")
	check(Catalog.ids() == NAMES.keys(), "七人稳定ID与顺序不变")
	var notes := 0
	var lines := {}
	var topics := 0
	var pages := 0
	var intros := 0
	for index in NAMES.size():
		var id: String = NAMES.keys()[index]
		var row: Dictionary = Catalog.get_npc(id)
		check(row.display_name == NAMES[id] and row.profile.age_group == "成人", "固定显示名与成人背景 " + id)
		var others := {}
		for note in row.social_notes:
			others[note.npc_id] = true
			check(note.npc_id != id and note.text.contains(NAMES[note.npc_id]), "具体相处文字点名对方")
		notes += row.social_notes.size()
		check(others.size() == 6, "完整覆盖六位邻人")
		var content: Dictionary = Catalog.dialogue_for(id)
		intros += content.intro.size()
		for entry in content.daily:
			check(entry.id == PREFIXES[index] + "_" + entry.period + "_" + entry.context, "原84槽ID和情境不变")
			check(entry.variants.size() >= 2, "每槽至少两变体")
			lines[entry.text] = true
			for text in entry.variants: lines[text] = true
		for topic in content.topics:
			topics += 1
			pages += topic.pages.size()
			check(topic.pages.size() >= 2, "每话题至少两页")
			if topic.id == "friends":
				var named := false
				for other in NAMES:
					if other == id: continue
					for page in topic.pages:
						if page.text.contains(NAMES[other]): named = true
				check(named, "朋友话题必须具体点名")
	check(notes == 42 and lines.size() >= 252 and topics == 28 and pages >= 56 and intros == 21, "42看法252日常28话题56页21初见页")
	for index in EDGE_IDS.size():
		var edge: Dictionary = Catalog.relationships()[index]
		check(edge.id == EDGE_IDS[index] and edge.base == BASES[index], "九条旧边ID数值不变")
		for key in ["summary", "history", "tension", "reconcile"]: check(not edge[key].strip_edges().is_empty(), "关系图四详情字段")
	var serialized := JSON.stringify(Catalog.data()) + JSON.stringify(Catalog.dialogues()) + JSON.stringify(Catalog.events()) + JSON.stringify(Catalog.requests())
	for old_name in ["牵线", "叶脉", "回声", "榫口", "灯芯", "花序"]:
		check(not serialized.contains(old_name), "本轮文本无旧人物名 " + old_name)
	# 货架是正常名词，不做全局禁词；柜子同理，不能按人名误替换。
	check(Catalog.get_event("lamp_1").pages[3].text.contains("柜子"), "保留普通柜子名词")

func test_queries() -> void:
	var ports := Ports.new()
	var service = make_service(ports)
	var before: Dictionary = service.to_dict()
	var profile: Dictionary = service.character_profile("npc_mu_he")
	profile.profile.past = "篡改"
	profile.social_notes[0].text = "篡改"
	check(service.character_profile("npc_mu_he").profile.past != "篡改" and service.character_profile("npc_mu_he").social_notes[0].text != "篡改", "人物嵌套查询深副本")
	var row: Dictionary = Catalog.get_npc("npc_mu_he")
	row.profile.habit = "篡改"
	check(Catalog.get_npc("npc_mu_he").profile.habit != "篡改", "Catalog整行查询深副本")
	var topics: Array = service.conversation_topics("npc_mu_he")
	check(topics.size() == 4 and Catalog.fields(topics[0], ["id", "title"]), "话题摘要只给ID标题")
	topics[0].title = "篡改"
	check(service.conversation_topics("npc_mu_he")[0].title != "篡改", "话题列表深副本")
	var topic: Dictionary = Catalog.get_topic("npc_mu_he", "past")
	topic.pages[0].text = "篡改"
	check(Catalog.get_topic("npc_mu_he", "past").pages[0].text != "篡改", "话题页面深副本")
	var graph: Array = service.relationship_graph()
	graph[0].history = "篡改"
	check(service.relationship_graph()[0].history != "篡改", "关系详情深副本")
	var snapshot: Dictionary = service.npc_snapshot("npc_mu_he")
	check(not snapshot.has("profile") and not snapshot.has("social_notes"), "高频状态不复制人物背景")
	snapshot.runtime.affinity = 999
	check(service.to_dict() == before, "新增查询及旧snapshot都不污染durable")
	check(service.character_profile("missing").is_empty() and service.conversation_topics("missing").is_empty(), "未知身份查询为空")
	var loaded: Dictionary = Catalog._data.duplicate(true)
	for repeat in 10: check(Catalog.validate() == "", "重复validate复用载入内容")
	check(Catalog._data == loaded, "validate不重新parse替换内容缓存")

func test_topics() -> void:
	var ports := Ports.new()
	var service = make_service(ports)
	service.npc_met.connect(_met)
	service.affinity_changed.connect(_affinity)
	service.relation_edge_changed.connect(_edge)
	service.npc_request_opened.connect(_opened)
	service.dialogue_completed.connect(_done)
	service.request_completed.connect(_gift_or_request)
	service.vendor_requested.connect(_vendor)
	var before: Dictionary = service.to_dict()
	signals_seen.clear()
	for id in NAMES:
		for topic in service.conversation_topics(id):
			check(service.start_topic(id, topic.id).ok, "全部28话题能打开")
			check(service.dialogue_state().total >= 2 and service._pending.kind == "display", "多页纯展示会话")
			var first: Dictionary = service.dialogue_state()
			check(not service.start_topic(id, topic.id).ok and service.dialogue_state() == first, "重入不替换现有会话")
			var result := finish(service)
			check(result.ok and result.completed and not result.committed and not result.has("talk_result"), "话题正常结束不提交")
			check(service.to_dict() == before, "28话题逐个完成无状态变化")
			for cancel_after in [0, 1, 2]:
				check(service.start_npc_dialogue(id, "topic", {"topic_id": topic.id}).ok, "兼容kind topic入口")
				for step in cancel_after: service.advance_dialogue()
				check(service.close_dialogue().ok and not service.dialogue_state().active, "首字中或第二页取消")
				check(service.to_dict() == before, "话题取消无状态变化")
	check(service.start_topic("npc_mu_he", "past").ok and service.to_dict() == before and not service.dialogue_state().active, "保存期间取消话题不写静态或临时内容")
	check(signals_seen.is_empty() and ports.results == 0 and ports.exchanges == 0, "话题不发业务事件不调用库存不结算礼物请求")
	check(not service.start_topic("missing", "past").ok and not service.start_topic("npc_mu_he", "missing").ok, "未知话题拒绝")
	check(not service.start_npc_dialogue("npc_mu_he", "topic", {"topic_id": "past", "effects": {}}).ok, "话题拒绝注入多余字段")

func test_variants() -> void:
	var ports := Ports.new()
	var service = make_service(ports)
	var all_lines := {}
	for id in NAMES:
		for entry in Catalog.dialogue_for(id).daily:
			var context := {"period": entry.period, "context": entry.context}
			var seen := {}
			var previous := ""
			for day in range(1, 7):
				ports.day = day
				check(service.start_npc_dialogue(id, "daily", context).ok, "所有日常槽逐日打开")
				var text: String = service.dialogue_state().page.text
				check(text != previous, "相邻同情境日期轮换")
				previous = text
				seen[text] = true
				all_lines[text] = true
				service.close_dialogue()
				check(service.start_npc_dialogue(id, "daily", context).ok and service.dialogue_state().page.text == text, "同日重开确定")
				service.close_dialogue()
				var state: Dictionary = service.to_dict()
				check(service.from_dict(state).ok and service.start_npc_dialogue(id, "daily", context).ok and service.dialogue_state().page.text == text, "读档无随机种子仍确定")
				service.close_dialogue()
			check(seen.size() == 3, "主文本和两变体均能轮到")
	check(all_lines.size() == 252, "所有252句可达")
	var entry: Dictionary = Catalog.dialogue_for("npc_mu_he").daily[0]
	ports.day = 20
	var plain: String = service._daily_text(entry, ports.clock())
	ports.weather = "cloudy"
	check(service._daily_text(entry, ports.clock()) != plain, "同槽天气参与确定性选择")
	ports.weather = "clear"
	var old: Dictionary = legacy_reference()
	check(service.from_dict(old).ok and service._daily_text(entry, ports.clock()) != plain, "现有剧情进度参与选择")
	for id in NAMES:
		for repeat in 3:
			check(service.start_npc_dialogue(id).ok, "同日日常可重看")
			check(finish(service).ok, "日常正常完成")
		check(service.npc_snapshot(id).runtime.affinity == 116, "每日只增加一次16好感")

## 固定旧v1数据，不从当前empty_snapshot生成，覆盖已有事件、请求与九边引用。
func legacy_reference() -> Dictionary:
	return {"version": 1, "graph": {
		"met": {"npc_luo_yan": true, "npc_mu_he": true, "npc_ji_chen": true, "npc_nan_zhi": true, "npc_bai_shi": true, "npc_hua_yi": true, "npc_bao_he": true},
		"affinity": {"npc_luo_yan": 100, "npc_mu_he": 100, "npc_ji_chen": 100, "npc_nan_zhi": 100, "npc_bai_shi": 100, "npc_hua_yi": 100, "npc_bao_he": 100},
		"last_talk_day": {"npc_luo_yan": 1, "npc_mu_he": 1, "npc_ji_chen": 1, "npc_nan_zhi": 1, "npc_bai_shi": 1, "npc_hua_yi": 1, "npc_bao_he": 1},
		"gift_week": {"npc_luo_yan": "", "npc_mu_he": "", "npc_ji_chen": "", "npc_nan_zhi": "", "npc_bai_shi": "", "npc_hua_yi": "", "npc_bao_he": ""},
		"gift_count": {"npc_luo_yan": 0, "npc_mu_he": 0, "npc_ji_chen": 0, "npc_nan_zhi": 0, "npc_bai_shi": 0, "npc_hua_yi": 0, "npc_bao_he": 0},
		"birthday_gift_day": {"npc_luo_yan": -1, "npc_mu_he": -1, "npc_ji_chen": -1, "npc_nan_zhi": -1, "npc_bai_shi": -1, "npc_hua_yi": -1, "npc_bao_he": -1},
		"last_gift_day": {"npc_luo_yan": -1, "npc_mu_he": -1, "npc_ji_chen": -1, "npc_nan_zhi": -1, "npc_bai_shi": -1, "npc_hua_yi": -1, "npc_bao_he": -1},
		"edge_deltas": {"edge_route_seed": 0, "edge_route_echo": 10, "edge_route_joint": 0, "edge_seed_joint": 0, "edge_seed_lamp": 0, "edge_echo_lamp": 0, "edge_joint_lamp": 0, "edge_seed_flower": 0, "edge_flower_shelf": 0}},
		"seen_events": {"route_1": {"day": 1, "choices": {"choice": "keep"}}, "route_2": {"day": 2, "choices": {"choice": "invite"}}, "seed_1": {"day": 1, "choices": {"choice": "observe"}}, "echo_1": {"day": 1, "choices": {"choice": "wait"}}, "joint_1": {"day": 1, "choices": {"choice": "repair"}}, "lamp_1": {"day": 1, "choices": {"choice": "book"}}, "flower_1": {"day": 1, "choices": {"choice": "door"}}, "shelf_1": {"day": 1, "choices": {"choice": "leave"}}},
		"choice_flags": {"route_1:choice": "keep", "route_2:choice": "invite", "seed_1:choice": "observe", "echo_1:choice": "wait", "joint_1:choice": "repair", "lamp_1:choice": "book", "flower_1:choice": "door", "shelf_1:choice": "leave"},
		"request_states": {"request_route_rope": {"status": "completed", "source_event": "route_1", "opened_day": 1, "completed_day": 2, "result_tag": "route_buoy_secured"}, "request_seed_trial": {"status": "open", "source_event": "seed_1", "opened_day": 1}, "request_echo_box": {"status": "open", "source_event": "echo_1", "opened_day": 1}, "request_joint_bench": {"status": "open", "source_event": "joint_1", "opened_day": 1}, "request_lamp_glass": {"status": "open", "source_event": "lamp_1", "opened_day": 1}, "request_flower_pot": {"status": "open", "source_event": "flower_1", "opened_day": 1}, "request_shelf_basket": {"status": "open", "source_event": "shelf_1", "opened_day": 1}}}

func test_legacy() -> void:
	var ports := Ports.new()
	var service = make_service(ports)
	var old := legacy_reference()
	check(Codec.validate(old) == "" and service.from_dict(old).ok and service.to_dict() == old, "固定旧档原样往返且version1不变")
	for id in NAMES:
		service.character_profile(id)
		service.conversation_topics(id)
		service.npc_snapshot(id)
	check(service.to_dict() == old, "静态新增字段不进入旧档to_dict")
	old.graph.affinity.npc_mu_he = 999
	check(service.to_dict().graph.affinity.npc_mu_he == 100, "恢复不持有调用者引用")
	for index in REQUEST_IDS.size():
		var request: Dictionary = Catalog.get_request(REQUEST_IDS[index])
		check(_costs_equal(request.costs, COSTS[index]) and request.result_tag == TAGS[index] and request.source_event == PREFIXES[index] + "_1" and request.followup == PREFIXES[index] + "_2", "旧请求成本结果前后置不变")
		var first_conditions: Dictionary = Catalog.get_event(PREFIXES[index] + "_1").conditions
		check(first_conditions.size() == 1 and first_conditions.get("affinity", -1) == 200, "旧初识阈值不变")
		var followup_conditions: Dictionary = Catalog.get_event(PREFIXES[index] + "_2").conditions
		check(followup_conditions.size() == 3 and followup_conditions.get("affinity", -1) == 500 and followup_conditions.get("events", []) == [PREFIXES[index] + "_1"] and followup_conditions.get("requests", []) == [REQUEST_IDS[index]], "旧转折前置不变")

func test_schema_rejections() -> void:
	var original: Dictionary = Catalog._data.duplicate(true)
	for field in ["profile", "social_notes"]:
		Catalog._data = original.duplicate(true)
		Catalog._data.roster.npcs[0].erase(field)
		check(Catalog.validate() != "", "缺少新增必填字段拒绝 " + field)
	for key in ["age_range", "personality", "past", "arrival_reason", "short_term_wish", "secret_or_regret", "habit", "catchphrase"]:
		Catalog._data = original.duplicate(true)
		Catalog._data.roster.npcs[0].profile[key] = "  "
		check(Catalog.validate() != "", "背景空文字拒绝 " + key)
	Catalog._data = original.duplicate(true)
	Catalog._data.roster.npcs[0].profile["unexpected"] = true
	check(Catalog.validate() != "", "背景未知字段拒绝")
	Catalog._data = original.duplicate(true)
	Catalog._data.roster.npcs[0].social_notes[1].npc_id = "npc_mu_he"
	check(Catalog.validate() != "", "看法重复对象拒绝")
	Catalog._data = original.duplicate(true)
	Catalog._data.dialogues.dialogues[0].daily[0].variants = ["只有一条"]
	check(Catalog.validate() != "", "日常不足两变体拒绝")
	Catalog._data = original.duplicate(true)
	Catalog._data.dialogues.dialogues[0].topics[0].pages[0]["effects"] = {}
	check(Catalog.validate() != "", "话题不能注入effects")
	Catalog._data = original.duplicate(true)
	Catalog._data.dialogues.dialogues[0].topics[0].pages = [{"id": "one", "speaker": "船老大", "text": "只有一页"}]
	check(Catalog.validate() != "", "话题不足两页拒绝")
	Catalog._data = original.duplicate(true)
	Catalog._data.roster.relationships[0].erase("history")
	check(Catalog.validate() != "", "关系详情缺字段拒绝")
	Catalog._data = original
	check(Catalog.validate() == "", "反例不污染正式目录")

func test_local_schedule() -> void:
	var ports := Ports.new()
	var service = make_service(ports)
	var row: Dictionary = Catalog.get_npc("npc_bao_he")
	var own := {"residence_general_store": Vector3.ZERO, "anchor_general_store": Vector3.ONE, "residence_general_store_social": Vector3(2, 0, 0)}
	check(row.home_anchor == "residence_general_store" and row.activity_anchor == "anchor_general_store", "阿店家与工作锚稳定")
	for rule in row.schedule: check(own.has(rule.anchor), "阿店每条规则只指浮店本地")
	for state in [Codec.empty_snapshot(), legacy_reference()]:
		state.graph.met.npc_bao_he = true
		state.graph.affinity.npc_bao_he = 800
		check(service.from_dict(state).ok, "日程fixture不绕过严格旧档")
		for weather in ["clear", "rain", "storm"]:
			for day in [1, 7]:
				for hour in [0.0, 6.0, 9.0, 10.0, 12.0, 17.0, 21.49, 21.5, 23.99]:
					var resolved: Dictionary = service.schedule_at(row.id, {"day": day, "hour": hour, "weather": weather}, own)
					check(resolved.ok and own.has(resolved.anchor_id) and not resolved.fallback, "全天候不寻路跨海且夜间仍本地")
	for rule in Catalog.get_npc("npc_hua_yi").schedule:
		check(rule.anchor not in own, "小花任何日程不访问阿店跨海锚")
		if "relation_shop_supply" in rule.get("conditions", {}).get("events", []): check(rule.anchor == "anchor_flower_shop", "补给关系后仍在自己天台陈列")

func run() -> void:
	test_content()
	test_queries()
	test_topics()
	test_legacy()
	test_variants()
	test_schema_rejections()
	test_local_schedule()
	print("[npc-people] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
