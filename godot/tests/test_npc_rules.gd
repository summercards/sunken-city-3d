extends SceneTree
## 纯规则验证；只由 scripts/run_verification.py 的 npc-rules 入口运行。
const Catalog = preload("res://src/npc/npc_catalog.gd")
const Service = preload("res://src/npc/npc_service.gd")
const Codec = preload("res://src/npc/npc_save_codec.gd")
const Runner = preload("res://src/npc/npc_dialogue_runner.gd")
var checks := 0
var failures := 0

class FakePorts extends RefCounted:
	var day := 1
	var hour := 12.0
	var weather := "clear"
	var stock := {"rope": 100, "seed": 100, "parts": 100, "wood": 100, "glass": 100, "shell": 100, "fish": 100, "flower_bundle": 100}
	var results: Array = []
	var exchanges := 0
	var reject := false
	var service_ref: WeakRef
	var reentrant: Dictionary = {}
	func clock() -> Dictionary: return {"day": day, "hour": hour, "weather": weather}
	func count(item: String) -> int: return int(stock.get(item, 0))
	func exchange(costs: Dictionary, gains: Dictionary) -> Dictionary:
		exchanges += 1
		if service_ref != null and service_ref.get_ref() != null:
			reentrant = service_ref.get_ref().give_gift("npc_luo_yan", "rope")
		if reject: return {"ok": false, "reason": "测试拒绝"}
		for id in costs:
			if count(id) < costs[id]: return {"ok": false}
		for id in costs: stock[id] = count(id) - int(costs[id])
		for id in gains: stock[id] = count(id) + int(gains[id])
		return {"ok": true}
	func remove(item: String, amount: int) -> bool:
		if reject or count(item) < amount: return false
		stock[item] = count(item) - amount
		return true
	func result(value: Dictionary) -> void: results.append(value.duplicate(true))

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _init() -> void: call_deferred("run")

func make_service(ports: FakePorts) -> Service:
	var service: Service = Service.new()
	check(service.configure(ports.clock, ports.exchange, Callable(), ports.count, ports.result).ok, "注入命名方法端口")
	return service

func seed_affinity(service, amount: int) -> void:
	var state: Dictionary = service.to_dict()
	for id in Catalog.ids():
		state.graph.met[id] = true
		state.graph.affinity[id] = amount
	check(service.from_dict(state).ok, "通过合法快照设置测试起点")

func finish(service, selected := "") -> Dictionary:
	var last := {"ok": false}
	for _step in 100:
		var state: Dictionary = service.dialogue_state()
		if not state.active: return last
		if state.typing:
			last = service.advance_dialogue(state.session_id)
		elif state.page.has("choices"):
			var choice: String = selected if selected != "" else str(state.page.choices[0].id)
			last = service.choose_dialogue(choice, state.session_id)
		else: last = service.advance_dialogue(state.session_id)
		if not last.ok: return last
	return {"ok": false, "reason": "测试对白未终止"}

func check_event_branches(service, ports: FakePorts, event_id: String) -> void:
	var baseline: Dictionary = service.to_dict()
	var event := Catalog.get_event(event_id)
	for page in event.pages:
		for choice in page.get("choices", []):
			var branch_ports := FakePorts.new()
			branch_ports.day = ports.day
			branch_ports.hour = ports.hour
			branch_ports.weather = ports.weather
			var fork: Service = make_service(branch_ports)
			check(fork.from_dict(baseline).ok and fork.start_event(event_id).ok, "每条分支从同一前置快照打开")
			var result := finish(fork, choice.id)
			check(result.ok and result.get("committed", false) and Codec.validate(fork.to_dict()) == "", "每条分支都可完成且结果可追溯")
			fork = null
			branch_ports = null

func test_catalog() -> void:
	check(Catalog.validate() == "", "完整内容与外观ID通过目录验证")
	check(Catalog.ids().size() == 7 and Catalog.relationships().size() == 9, "七人九边")
	var expected_names := ["船老大", "豆豆", "阿海", "木头叔", "灯伯", "小花", "阿店"]
	var homes: Dictionary = {}
	var skins: Dictionary = {}
	var combinations: Dictionary = {}
	for i in Catalog.all().size():
		var row: Dictionary = Catalog.all()[i]
		check(row.display_name == expected_names[i], "保留ID并使用外化身份名")
		check(Catalog.profile(row.id).appearance == preload("res://src/avatar/avatar_catalog.gd").effective(Catalog.profile(row.id).appearance), "完整角色profile不依赖非法颜色fallback")
		homes[row.residence_id] = true
		skins[row.appearance.skin] = true
		var combination: String = "%s:%s:%s" % [row.appearance.body_type, row.appearance.hair_style, row.appearance.top_color]
		combinations[combination] = true
		var profile: Dictionary = Catalog.profile(row.id)
		check(row.morphs.size() == 9 and profile.morphs == row.morphs, "九项显式形体参数完整合并到profile")
		check(profile.appearance.skin == row.appearance.skin, "显式肤色保留到profile")
		profile.morphs.body_build = -1.0
		check(Catalog.profile(row.id).morphs.body_build == row.morphs.body_build, "profile形体参数为深副本")
	check(homes.size() == 7, "七个独立住所引用")
	check(skins.size() >= 4 and combinations.size() == 7, "至少四肤色与七组独特体型发型上装配色")
	var personal := 0
	var relations := 0
	for event in Catalog.events():
		if event.kind == "personal": personal += 1
		else: relations += 1
	check(personal == 21 and relations == 4 and Catalog.requests().size() == 7, "21个人事件加4关系事件与7请求")
	var texts := {}
	for content in Catalog.dialogues():
		for entry in content.daily: texts[entry.text] = true
	check(texts.size() == 84, "84条独特情境对白")
	var copy: Dictionary = Catalog.data()
	copy.npcs[0].appearance.top_color = "坏颜色"
	var events: Array = Catalog.events()
	events[0].pages[0].text = "被篡改"
	var requests: Array = Catalog.requests()
	requests[0].costs.rope = 999
	check(Catalog.all()[0].appearance.top_color != "坏颜色" and Catalog.events()[0].pages[0].text != "被篡改" and Catalog.requests()[0].costs.rope == 2, "所有目录深副本")

func test_daily_and_schedule() -> void:
	var ports := FakePorts.new()
	var service: Service = make_service(ports)
	check(not service.meet("missing").ok and service.npc_snapshot("missing").is_empty(), "未知NPC明确拒绝")
	check(service.meet("npc_luo_yan").ok and service.meet("npc_luo_yan").already, "见面幂等")
	check(not service.talk("npc_luo_yan", 1.5).ok and not service.talk("npc_luo_yan", -1).ok, "交谈拒绝小数与负日期")
	check(service.talk("npc_luo_yan").delta == 16 and not service.talk("npc_luo_yan").ok, "注入时钟交谈日限")
	ports.day = 2
	check(service.talk("npc_luo_yan").ok and not service.talk("npc_luo_yan", 1).ok, "次日可交谈且拒绝回拨刷好感")
	var snapshot: Dictionary = service.npc_snapshot("npc_luo_yan")
	snapshot.runtime.affinity = 999
	var graph: Array = service.relationship_graph()
	graph[0].effective = 9999
	check(service.npc_snapshot("npc_luo_yan").runtime.affinity == 32 and service.relationship_graph()[0].effective != 9999, "运行查询深副本")
	var anchors := {"anchor_dock": Vector3.ZERO, "residence_dock_workshop": Vector3.ZERO, "anchor_home_dock": Vector3.ZERO, "anchor_old_rail": Vector3.ZERO}
	check(service.schedule_at("npc_luo_yan", {"hour": 12.0}, anchors).action == "repair_boat", "默认职业日程兼容")
	check(service.schedule_at("npc_luo_yan", {"hour": 12.0, "weather": "rain"}, anchors).action == "sew_sails", "天气日程")
	check(service.schedule_at("npc_luo_yan", {"day": 7, "hour": 12.0}, anchors).action == "check_ferry", "星期日程")
	check(service.schedule_at("npc_luo_yan", {"day": 14.0, "hour": 12.0}, anchors).action == "check_ferry", "JSON整数日期与跨周星期日程")
	check(service.schedule_at("npc_luo_yan", {"day": 8, "hour": 12.0}, anchors).action == "repair_boat", "星期条件不误匹配新周首日")
	var sunday_actions := ["check_ferry", "exchange_cuttings", "record_tides", "repair_benches", "host_reading", "collect_cuttings", "receive_supplies"]
	var work_actions := ["repair_boat", "sort_seeds", "sort_salvage", "measure_decks", "light_lamps", "arrange_bouquets", "open_store"]
	var all_anchors := {}
	for row in Catalog.all():
		all_anchors[row.home_anchor] = Vector3.ZERO
		for rule in row.schedule: all_anchors[rule.anchor] = Vector3.ZERO
	for i in Catalog.ids().size():
		var id: String = Catalog.ids()[i]
		for day in [7, 14.0]:
			check(service.schedule_at(id, {"day": day, "hour": 12.0}, all_anchors).action == sunday_actions[i], "%s 第%s日星期日程" % [id, day])
		check(service.schedule_at(id, {"day": 8.0, "hour": 12.0}, all_anchors).action == work_actions[i], id + " JSON新周首日恢复职业日程")
		check(service.schedule_at(id, {"day": 7, "hour": 12.0, "weather": "rain"}, all_anchors).priority == 40, id + " 天气优先于星期日程")
	check(service.schedule_at("npc_luo_yan", {"hour": 23.0}, anchors).action == "rest", "21点半后回家")
	check(service.schedule_at("npc_luo_yan", {"hour": 12.0}, {}).fallback, "缺失锚点可观察回家降级")
	check(not service.schedule_at("npc_luo_yan", {"hour": NAN}, anchors).ok, "日程拒绝非有限时间")
	check(not service.schedule_at("npc_luo_yan", {"hour": 24.0}, anchors).ok, "日程拒绝越界时间")
	check(not service.schedule_at("npc_luo_yan", {"day": 1.5}, anchors).ok, "日程拒绝小数日期")
	seed_affinity(service, 500)
	check(service.schedule_at("npc_luo_yan", {"hour": 18.0}, anchors).action == "teach_knots", "好感日程条件")
	for id in Catalog.ids():
		for period in ["morning", "work", "evening"]:
			for situation in ["normal", "rain", "night", "friend"]:
				var opened: Dictionary = service.start_npc_dialogue(id, "daily", {"period": period, "context": situation})
				check(opened.ok and not opened.state.page.text.is_empty(), "全部84槽位可由UI查询打开")
				service.close_dialogue()
	check(service.start_npc_dialogue("npc_luo_yan").ok, "日常会话打开")
	var completed := finish(service)
	check(completed.ok and completed.completed and service.npc_snapshot("npc_luo_yan").runtime.affinity == 500, "同日对白结束不重复加交谈好感")
	check(not service.request_vendor("npc_luo_yan").ok and service.request_vendor("npc_hua_yi").shop_id == "shop_flower", "仅vendor公开端口")
	service = null
	ports = null

func test_dialogue_machine() -> void:
	var runner = Runner.new()
	var pages := [
		{"id": "a", "speaker": "甲", "text": "第一页"},
		{"id": "b", "speaker": "甲", "text": "选择页", "choices": [{"id": "left", "text": "左", "next": "c"}, {"id": "right", "text": "右", "next": "d"}]},
		{"id": "c", "speaker": "甲", "text": "左分支", "next": ""},
		{"id": "d", "speaker": "甲", "text": "右分支", "next": ""}]
	check(runner.start("test", pages).ok, "合法多页分支")
	var serial: int = runner.state().session_id
	check(not runner.start("other", pages).ok, "忙碌会话不被覆盖")
	check(not runner.choose("left").ok and not runner.choose("invented").ok, "未到选择页不能选择")
	check(runner.advance().revealed and runner.state().index == 0, "打字中确认只补全文字")
	runner.advance()
	runner.advance()
	check(not runner.advance().ok and not runner.choose("invented").ok, "选择页不能跳过或伪造选项")
	check(runner.choose("right").ok and runner.state().page.id == "d", "跳到真实右分支")
	check(runner.choose("right").already and runner.state().page.id == "d", "重复选择不重复推进")
	var public: Dictionary = runner.state()
	public.page.text = "改写"
	check(runner.state().page.text == "右分支", "对白状态深副本")
	runner.advance()
	var complete: Dictionary = runner.advance()
	check(complete.completed and complete.choices.b == "right" and not runner.state().active, "完成携带路径且关闭")
	check(not runner.advance().ok, "完成重复投递无副作用")
	runner.start("test", pages)
	check(not runner.advance(serial).ok, "拒绝上一会话的延迟输入")
	runner.cancel()
	var invalid: Array = pages.duplicate(true)
	invalid[1].choices[0].next = "missing"
	check(not runner.start("bad", invalid).ok and not runner.state().active, "未知分支不改变现场")
	invalid = pages.duplicate(true)
	invalid[2].next = "a"
	check(Runner.validate_pages(invalid) != "", "拒绝循环对白")
	runner = null

func test_gifts() -> void:
	var ports := FakePorts.new()
	var service: Service = make_service(ports)
	ports.service_ref = weakref(service)
	var before: Dictionary = service.to_dict()
	ports.reject = true
	check(not service.give_gift("npc_luo_yan", "rope").ok and service.to_dict() == before and ports.stock.rope == 100, "库存拒绝不改好感与额度")
	ports.reject = false
	check(not service.give_gift("missing", "rope").ok and not service.give_gift("npc_luo_yan", "unknown").ok and not service.give_gift("npc_luo_yan", "rope", "platinum").ok, "未知NPC物品品质在消费前拒绝")
	check(service.give_gift("npc_luo_yan", "rope", "silver").delta == 44, "喜爱银星倍率")
	check(not ports.reentrant.ok, "库存回调重入不能双花")
	check(service.give_gift("npc_luo_yan", "rope", "gold").delta == 48, "喜爱金星倍率")
	var count_before: int = ports.stock.rope
	check(not service.give_gift("npc_luo_yan", "rope").ok and ports.stock.rope == count_before, "每周普通额度最多两次")
	ports.day = 8
	check(service.give_gift("npc_luo_yan", "rope").ok, "第8日周次刷新")
	ports.day = 9
	var birthday: Dictionary = service.give_gift("npc_luo_yan", "rope", "gold")
	check(birthday.delta == 120 and birthday.birthday and birthday.slot == "birthday", "生日倍率封顶并独立额度")
	check(service.give_gift("npc_luo_yan", "rope").ok and not service.give_gift("npc_luo_yan", "rope").ok, "同周总两普通加一次生日")
	ports.day = 10
	check(not service.give_gift("npc_luo_yan", "rope").ok, "生日额外额度不延续为普通额度")
	ports.day = 15
	check(service.give_gift("npc_luo_yan", "fish", "gold").delta == -29, "厌恶品质倍率与整数舍入")
	var gift_snapshot: Dictionary = service.to_dict()
	check(Codec.validate(gift_snapshot) == "", "跨周生日快照合法")
	var gift_restored: Service = Service.new()
	check(gift_restored.from_dict(JSON.parse_string(JSON.stringify(gift_snapshot))).ok and gift_restored.to_dict() == gift_snapshot, "实际跨周和生日送礼记录JSON往返不丢失")
	var gift_graph: Dictionary = gift_restored.to_dict().graph
	check(gift_graph.gift_count.npc_luo_yan is int and gift_graph.last_gift_day.npc_luo_yan is int and gift_graph.birthday_gift_day.npc_luo_yan is int and gift_graph.gift_week.npc_luo_yan is String, "非空送礼记录只恢复数值字段，不改周次字符串")
	gift_restored = null
	ports.day = 8
	check(not service.give_gift("npc_luo_yan", "rope").ok, "送礼拒绝时间回拨")
	var fresh: Service = Service.new()
	check(not fresh.give_gift("npc_luo_yan", "rope").ok, "无时钟不猜日期")
	check(fresh.configure(ports.clock, Callable(), ports.remove, ports.count).ok, "单物品remove注入")
	ports.day = 20
	check(fresh.give_gift("npc_bai_shi", "wood").delta == 24, "喜欢礼物加24")
	check(fresh.give_gift("npc_nan_zhi", "seed").delta == 8, "普通礼物加8")
	check(fresh.give_gift("npc_nan_zhi", "glass").calculated_delta == -12 and fresh.npc_snapshot("npc_nan_zhi").runtime.affinity == 0, "不喜欢礼物减12但不低于零")
	check(fresh.give_gift("npc_mu_he", "fish").delta == 0, "负好感不低于零")
	check(fresh.give_gift("npc_mu_he", "seed").delta == 40, "原子remove路径可用")
	var weak_ports: WeakRef = weakref(ports)
	ports = null
	check(weak_ports.get_ref() == null and not fresh.give_gift("npc_mu_he", "seed").ok, "服务不强持有注入端口")
	fresh = null
	var weak_service: WeakRef = weakref(service)
	service = null
	check(weak_service.get_ref() == null, "服务和帮助类无循环引用")

func test_events_requests_and_saves() -> void:
	var ports := FakePorts.new()
	var service: Service = make_service(ports)
	seed_affinity(service, 199)
	check(not service.start_event("route_1").ok, "个人初识须200好感")
	seed_affinity(service, 200)
	check(service.start_event("route_1").ok, "个人初识200阈值可用")
	service.close_dialogue()
	var reward_ports := FakePorts.new()
	var reward_service: Service = make_service(reward_ports)
	seed_affinity(reward_service, 200)
	check(reward_service.start_event("route_1").ok and finish(reward_service).get("committed", false), "请求奖励测试前置剧情")
	check(reward_service.fulfill_request("request_route_rope").delta == 40 and reward_service.npc_snapshot("npc_luo_yan").runtime.affinity == 240, "请求奖励精确加40")
	reward_service = null
	reward_ports = null
	seed_affinity(service, 1000)
	var before: Dictionary = service.to_dict()
	check(not service.start_event("route_3").ok and not service.start_event("unknown").ok and service.to_dict() == before, "前置未满足或未知事件拒绝且不改状态")
	check(service.start_event("route_1").ok, "个人事件初识打开")
	service.advance_dialogue()
	service.advance_dialogue()
	service.advance_dialogue()
	check(service.choose_dialogue("new").ok, "待提交分支选择")
	check(service.npc_snapshot("npc_luo_yan").requests.is_empty(), "未到终页不开请求")
	service.close_dialogue()
	check(service.to_dict() == before, "取消事件无持久副作用")
	check_event_branches(service, ports, "route_1")
	check(service.start_event("route_1").ok, "取消后可重开")
	var bad: Dictionary = before.duplicate(true)
	bad.version = 1.5
	var active: Dictionary = service.dialogue_state()
	check(not service.from_dict(bad).ok and service.dialogue_state() == active, "坏档不取消当前会话")
	check(finish(service).committed, "终页一次提交个人事件")
	check(service.list_requests("npc_luo_yan").size() == 1 and service.list_requests("npc_luo_yan")[0].can_fulfill, "请求可查询且可完成")
	var saved: Dictionary = service.to_dict()
	ports.reject = true
	check(not service.fulfill_request("request_route_rope").ok and service.to_dict() == saved, "请求库存拒绝原子回滚")
	ports.reject = false
	var fulfilled: Dictionary = service.fulfill_request("request_route_rope")
	check(fulfilled.ok and fulfilled.source_event == "route_1" and fulfilled.followup == "route_2" and fulfilled.result_tag == "route_buoy_secured", "完成请求可追溯剧情影响")
	var exchanges: int = ports.exchanges
	check(service.fulfill_request("request_route_rope").already and ports.exchanges == exchanges, "请求重复完成不再消费")
	check(service.start_event("route_1").replay, "已完成事件自动回看")
	var stable_affinity: int = service.npc_snapshot("npc_luo_yan").runtime.affinity
	var result := finish(service, "new")
	check(result.ok and not result.committed and service.npc_snapshot("npc_luo_yan").runtime.affinity == stable_affinity, "回看不同分支也无副作用")
	check(service.to_dict().seen_events.route_1.choices.choice == "keep", "回看不改原选择")
	# 顺序完成全部个人前两段及请求，再解关系事件和终章。
	for pair in [["seed_1", "request_seed_trial"], ["echo_1", "request_echo_box"], ["joint_1", "request_joint_bench"], ["lamp_1", "request_lamp_glass"], ["flower_1", "request_flower_pot"], ["shelf_1", "request_shelf_basket"]]:
		check_event_branches(service, ports, pair[0])
		check(service.start_event(pair[0]).ok and finish(service).get("committed", false), "每人初识剧情可完整提交")
		check(service.fulfill_request(pair[1]).ok, "每人请求都可实际交付")
	for id in ["route_2", "seed_2", "echo_2", "joint_2", "lamp_2", "flower_2", "shelf_2"]:
		check_event_branches(service, ports, id)
		check(service.start_event(id).ok and finish(service).get("committed", false), "每人转折由请求解锁")
	ports.hour = 12.0
	for id in ["relation_old_route", "relation_seed_color", "relation_shop_supply"]:
		if id == "relation_seed_color":
			ports.weather = "rain"
			check(not service.start_event(id).ok, "种植记忆关系事件雨天等待不丢失")
			ports.weather = "clear"
		check_event_branches(service, ports, id)
		check(service.start_event(id).ok and finish(service).get("committed", false), "关系剧情真实结算")
	check(not service.start_event("relation_lamp_promise").ok, "关系剧情时间窗生效")
	ports.hour = 18.0
	check_event_branches(service, ports, "relation_lamp_promise")
	check(service.start_event("relation_lamp_promise").ok and finish(service).get("committed", false), "灯下关系剧情夜间解锁")
	for id in ["route_3", "seed_3", "echo_3", "joint_3", "lamp_3", "flower_3", "shelf_3"]:
		check(service.start_event(id).ok and finish(service).get("committed", false), "每人收束可完成")
	var final: Dictionary = service.to_dict()
	check(final.seen_events.size() == 25 and final.request_states.size() == 7, "25事件和7请求全部完成")
	check(Codec.validate(final) == "", "全部结果快照严格校验通过")
	var restored: Service = Service.new()
	var json_snapshot: Variant = JSON.parse_string(JSON.stringify(final))
	var restored_result: Dictionary = restored.from_dict(json_snapshot)
	check(restored_result.ok, "JSON快照严格解码成功：" + str(restored_result.get("reason", "")))
	check(restored_result.ok and restored.to_dict() == final, "JSON往返保留全部剧情、边值与请求")
	var normalized: Dictionary = restored.to_dict()
	check(normalized.version is int, "JSON版本恢复为int")
	for key in ["affinity", "last_talk_day", "gift_count", "birthday_gift_day", "last_gift_day", "edge_deltas"]:
		for id in normalized.graph[key]:
			check(normalized.graph[key][id] is int, "JSON持久整数恢复 graph.%s.%s" % [key, id])
	for id in normalized.seen_events:
		check(normalized.seen_events[id].day is int, "JSON剧情日期恢复为int：" + id)
	for id in normalized.request_states:
		check(normalized.request_states[id].opened_day is int and normalized.request_states[id].completed_day is int, "JSON请求日期恢复为int：" + id)
	var migrated := Codec.migrate(json_snapshot)
	check(migrated.ok and not migrated.migrated and migrated.snapshot == final, "已有版本的迁移入口同样严格解码JSON整数")
	check(json_snapshot.version is float and json_snapshot.seen_events.route_1.day is float, "解码不原地改写输入快照")
	normalized.graph.affinity.npc_luo_yan = 0
	check(restored.to_dict() == final, "解码后查询副本不改变唯一owner")
	json_snapshot.graph.affinity.npc_luo_yan = 0.25
	check(restored.to_dict() == final and not Codec.decode(json_snapshot).ok, "解码不持有输入且不能把JSON小数强转为整数")
	var anchors := {"anchor_old_rail": Vector3.ZERO, "residence_dock_workshop": Vector3.ZERO}
	check(service.schedule_at("npc_luo_yan", {"hour": 18.0, "weather": "rain"}, anchors).action == "share_route_log", "前置剧情日程优先于天气")
	for event in service.list_events(): check(event.completed and event.available and event.replay, "完成事件均可回看")
	var durable: Dictionary = service.to_dict()
	check(service.start_event("route_2").ok, "回看关系变更事件")
	check(finish(service).ok and service.to_dict() == durable, "回看不重复改变关系边")
	var corruptions: Array = []
	bad = final.duplicate(true); bad.graph.affinity.npc_luo_yan = 0.25; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.affinity.npc_luo_yan = NAN; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.met.npc_luo_yan = 1; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.affinity["ghost"] = 0; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.erase("last_talk_day"); corruptions.append(bad)
	bad = final.duplicate(true); bad["extra"] = true; corruptions.append(bad)
	bad = final.duplicate(true); bad.seen_events["ghost"] = true; corruptions.append(bad)
	bad = final.duplicate(true); bad.choice_flags["ghost"] = true; corruptions.append(bad)
	bad = final.duplicate(true); bad.seen_events.route_1.choices.choice = "forged"; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.edge_deltas.edge_route_echo = 100; corruptions.append(bad)
	bad = final.duplicate(true); bad.request_states.request_route_rope.result_tag = "forged"; corruptions.append(bad)
	bad = final.duplicate(true); bad.request_states.request_route_rope.completed_day = -1; corruptions.append(bad)
	bad = final.duplicate(true); bad.request_states["ghost"] = {}; corruptions.append(bad)
	bad = final.duplicate(true); bad.seen_events.erase("route_1"); corruptions.append(bad)
	bad = final.duplicate(true); bad.version = 2; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.last_talk_day.npc_luo_yan = INF; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.gift_count.npc_luo_yan = 3; corruptions.append(bad)
	bad = final.duplicate(true); bad.request_states.request_route_rope.status = {}; corruptions.append(bad)
	bad = final.duplicate(true); bad.seen_events.route_1.choices = []; corruptions.append(bad)
	bad = final.duplicate(true); bad.choice_flags["route_1:choice"] = {}; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.gift_week.npc_luo_yan = "99"; corruptions.append(bad)
	bad = final.duplicate(true); bad.graph.birthday_gift_day.npc_luo_yan = 8; corruptions.append(bad)
	var corruption_labels := ["小数好感", "NaN好感", "非布尔相识", "未知好感ID", "缺失关系字段", "未知根字段", "未知剧情ID", "未知选择标记", "伪造分支", "不可追溯边值", "伪造请求结果", "负完成日", "未知请求ID", "缺失前置剧情", "未知版本", "无限交谈日", "超额周礼物", "非字符串请求状态", "非对象选择路径", "非字符串选择标记", "错误礼物周次", "非生日的生日礼物"]
	for key in ["last_talk_day", "gift_count", "birthday_gift_day", "last_gift_day", "edge_deltas"]:
		bad = final.duplicate(true)
		var id: String = bad.graph[key].keys()[0]
		bad.graph[key][id] = 0.25
		corruptions.append(bad)
		corruption_labels.append("小数关系字段：" + key)
	for field in ["opened_day", "completed_day"]:
		bad = final.duplicate(true)
		bad.request_states.request_route_rope[field] = 1.25
		corruptions.append(bad)
		corruption_labels.append("小数请求日期：" + field)
	bad = final.duplicate(true); bad.seen_events.route_1.day = 1.25; corruptions.append(bad)
	corruption_labels.append("小数剧情日期")
	bad = final.duplicate(true); bad.version = 1.25; corruptions.append(bad)
	corruption_labels.append("小数版本")
	check(Codec.validate(restored.to_dict()) == "" and restored.to_dict() == final, "坏档测试前现场合法且与原始快照一致")
	for i in corruptions.size():
		var corruption: Dictionary = corruptions[i]
		var label: String = corruption_labels[i]
		check(restored.start_event("route_1").ok, "坏档测试保留活动回看：" + label)
		var current_dialogue: Dictionary = restored.dialogue_state()
		var error: String = restored.validate_snapshot(corruption)
		check(error != "", "坏档校验拒绝：" + label)
		var rejected: Dictionary = restored.from_dict(corruption)
		check(not rejected.ok and rejected.get("reason", "") == error, "坏档读入明确拒绝：" + label)
		check(restored.dialogue_state() == current_dialogue, "坏档拒绝不取消或推进会话：" + label)
		check(restored.to_dict() == final, "坏数值、字段、ID、路径与结果拒绝且现场不变：" + label)
	check(Codec.validate(Codec.empty_snapshot()) == "" and Codec.migrate(null).snapshot == Codec.empty_snapshot(), "空快照无递归服务与明确旧档迁移")
	check(not Codec.migrate({}).ok, "损坏对象不能被当旧档覆盖")
	check(not restored.from_dict([]).ok, "非对象快照明确拒绝")
	service.start_event("route_1")
	service.to_dict()
	check(not service.dialogue_state().active, "保存取消瞬态会话")
	service.start_event("route_1")
	check(service.from_dict(final).ok and not service.dialogue_state().active, "成功读档清理会话")
	check(ports.results.size() == 32, "25事件7请求各通知一次，回看不发结果")
	restored = null
	service = null
	ports = null

func run() -> void:
	check(root.get_node_or_null("Economy") == null and root.get_node_or_null("GameState") == null and root.get_node_or_null("Zones") == null, "无生产Autoload")
	test_catalog()
	test_daily_and_schedule()
	test_dialogue_machine()
	test_gifts()
	test_events_requests_and_saves()
	await process_frame
	print("[npc-rules] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
