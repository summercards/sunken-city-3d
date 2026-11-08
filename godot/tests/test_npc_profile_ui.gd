extends SceneTree
## 统一 runner 入口：npc-profile-ui。无 Main、无截图、不读写玩家存档。
const NpcPanelScript = preload("res://src/npc/npc_panel.gd")
const Service = preload("res://src/npc/npc_service.gd")
const Catalog = preload("res://src/npc/npc_catalog.gd")
const Runner = preload("res://src/npc/npc_dialogue_runner.gd")
const ShopService = preload("res://src/shop/shop_service.gd")
const ShopPanel = preload("res://src/shop/shop_panel.gd")
const Inventory = preload("res://src/inventory/inventory.gd")
const NAMES := {"npc_luo_yan": "船老大", "npc_mu_he": "豆豆", "npc_ji_chen": "阿海",
	"npc_nan_zhi": "木头叔", "npc_bai_shi": "灯伯", "npc_hua_yi": "小花", "npc_bao_he": "阿店"}
const FIELDS := ["age_range", "personality", "past", "arrival_reason", "short_term_wish", "habit", "catchphrase"]
var checks := 0
var failures := 0
var panel
var shop_panel
var shop
var bag
var vendor_calls: Array = []
var gameplay_signals: Array = []

class FakeService extends RefCounted:
	signal vendor_requested(npc_id: String, shop_id: String)
	var rows: Dictionary = {}
	var runner = Runner.new()
	var queries := {"profile": 0, "topics": 0}
	var starts: Array = []
	var completed_relation := false
	func _init(names: Dictionary) -> void:
		for id in names:
			var notes: Array = []
			for other in names:
				if other != id: notes.append({"npc_id": other, "text": "我和%s一起做过事。" % names[other]})
			rows[id] = {"id": id, "display_name": names[id], "role": "居民", "residence_id": id,
				"profile": {"age_range": "三十来岁", "personality": "说话实在", "past": "以前修过船",
					"arrival_reason": "过来帮忙", "short_term_wish": "把手边的活做好", "habit": "早起喝茶",
					"catchphrase": "慢慢来。", "secret_or_regret": "这件隐情不能在认识页出现"},
				"social_notes": notes, "runtime": {"met": false, "hearts": 0, "affinity": 0, "last_talk_day": 0}}
			if id == "npc_hua_yi": rows[id]["shop_id"] = "shop_flower"
			if id == "npc_bao_he": rows[id]["shop_id"] = "shop_general"
	func meet(id: String) -> Dictionary:
		rows[id].runtime.met = true
		return {"ok": true}
	func start_conversation(_id: String) -> Dictionary: return {"ok": true, "greeting_only": true}
	func npc_snapshot(id: String) -> Dictionary: return rows.get(id, {}).duplicate(true)
	func character_profile(id: String) -> Dictionary:
		queries.profile += 1
		return {"npc_id": id, "display_name": rows[id].display_name, "profile": rows[id].profile.duplicate(true), "social_notes": rows[id].social_notes.duplicate(true)}
	func conversation_topics(id: String) -> Array:
		queries.topics += 1
		var out: Array = []
		for index in 4: out.append({"id": id + "_topic_%d" % index, "title": "说说第%d件小事" % (index + 1)})
		return out
	func start_topic(id: String, topic: String) -> Dictionary:
		var valid := false
		for row in conversation_topics(id):
			if row.id == topic: valid = true
		if not valid: return {"ok": false, "reason": "没有这个话题"}
		starts.append([id, topic])
		return runner.start(topic, [{"id": "first", "speaker": rows[id].display_name, "text": "坐下来歇歇，我慢慢讲给你听。",
			"choices": [{"id": "listen", "text": "接着听", "next": "last"}]},
			{"id": "last", "speaker": rows[id].display_name, "text": "这就是我最近忙的事，明天还得接着做。"}])
	func dialogue_state() -> Dictionary: return runner.state()
	func advance_dialogue(serial: int) -> Dictionary: return runner.advance(serial)
	func choose_dialogue(id: String, serial: int) -> Dictionary: return runner.choose(id, serial)
	func close_dialogue() -> Dictionary:
		runner.cancel()
		return {"ok": true}
	func list_events(_id: String) -> Array:
		return [{"id": "fake_relation", "kind": "relationship", "npc_ids": ["npc_luo_yan", "npc_ji_chen"],
			"completed": completed_relation}]
	func gift_options(_id: String) -> Dictionary: return {"ok": false, "reason": "测试没有礼物"}
	func list_requests(_id: String) -> Array: return []
	func relationship_graph() -> Array:
		var edges: Array = Catalog.relationships()
		for edge in edges:
			edge["known"] = rows[edge.from].runtime.met and rows[edge.to].runtime.met
			edge["effective"] = edge.base
			edge["summary"] = "平日互相搭把手"
			edge["history"] = "以前一起修过踏板"
			edge["tension"] = "两个人还没把话说开"
			edge["reconcile"] = "未完成剧情的和解答案"
		return edges
	func request_vendor(id: String) -> Dictionary:
		vendor_requested.emit(id, rows[id].shop_id)
		return {"ok": true}
	func to_dict() -> Dictionary: return rows.duplicate(true)

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-profile-ui] ", label)
	return ok

func clock_query() -> Dictionary: return {"day": 1, "hour": 12.0, "weather": "clear"}
func _affinity(_id: String, _delta: int, _reason: String) -> void: gameplay_signals.append("affinity")
func _edge(_id: String, _delta: int, _reason: String) -> void: gameplay_signals.append("edge")
func _request(_id: String, _result: Dictionary) -> void: gameplay_signals.append("request")
func _result(value: Dictionary) -> void: gameplay_signals.append(value)
func _vendor(id: String, shop_id: String) -> void:
	vendor_calls.append({"npc_id": id, "shop_id": shop_id, "npc_closed": not panel.is_modal()})
	check(shop_panel.open_shop(shop_id).ok, "vendor 路由到独立真实商店 " + shop_id)

func button(action: String, id := "") -> Button:
	for candidate: Button in panel._buttons:
		if candidate.get_meta("npc_action", "") == action and (id == "" or candidate.get_meta("npc_payload", {}).get("id", "") == id): return candidate
	return null

func press(action: String, id := "") -> void:
	await process_frame
	if action in ["profile", "topics", "events", "gifts", "requests", "relationships", "talk"] and button(action, id) == null:
		if panel.session.service.dialogue_state().get("active", false): panel.session.command("home")
		await press("chat")
		await process_frame
	if action == "back" and panel.session.service.dialogue_state().get("active", false):
		panel.session.command("back")
		return
	var target := button(action, id)
	if action == "back" and target == null: target = button("home")
	if check(target != null and not target.disabled, "实际按钮可用 " + action + " " + id): target.pressed.emit()

func labels() -> String:
	var out: String = panel._title.text + "\n" + panel._identity.text + "\n"
	if panel.dialogue_view.panel.visible: out += panel.dialogue_view.line_label.text + "\n"
	for child in panel._body.get_children():
		if child is Label: out += child.text + "\n"
	return out

func key(code: Key, down := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	event.echo = echo
	return event

func tap(code: Key) -> void:
	await process_frame
	check(panel.handle_input(key(code)), "模态消费按键 %d" % code)
	panel.handle_input(key(code, false))

func mouse_click(target: Button) -> void:
	await process_frame
	if panel._scroll.is_ancestor_of(target): panel._scroll.ensure_control_visible(target)
	await process_frame
	var point := target.get_global_rect().get_center()
	check(target.is_visible_in_tree() and target.get_global_rect().has_point(point), "鼠标目标实际可见")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func finish_dialogue(service) -> void:
	for step in 64:
		var state: Dictionary = service.dialogue_state()
		if not state.get("active", false): return
		if state.typing or not state.page.has("choices"): await press("advance")
		else: await press("choice", str(state.page.choices[0].id))
	check(false, "对白有限步结束")

func home_labels() -> Dictionary:
	var out := {}
	for id in NAMES:
		var row: Dictionary = panel.session.service.npc_snapshot(id)
		out[row.residence_id] = "东南海上商店暂驻" if id == "npc_bao_he" else "天台草地暂驻"
	return out

func attach(service) -> void:
	panel.configure(service)
	panel.configure(service, home_labels())
	service.vendor_requested.connect(_vendor)

func run() -> void:
	root.size = Vector2i(1280, 900)
	panel = NpcPanelScript.new()
	root.add_child(panel)
	# 自动打字单独测试，遍历28话题时使用真实按钮逐步推进。
	panel.set_process(false)
	bag = Inventory.new(24)
	bag.set_count("coins", 100)
	shop = ShopService.new()
	shop.configure(bag)
	shop_panel = ShopPanel.new()
	root.add_child(shop_panel)
	shop_panel.configure(shop, bag)
	var fake = FakeService.new(NAMES)
	attach(fake)
	await privacy_and_queries(fake)
	await exercise_roster(fake, "Fake")
	await navigation(fake)
	await vendors(fake, "Fake")
	fake.vendor_requested.disconnect(_vendor)
	panel.cancel_session()
	var real = Service.new()
	check(real.configure(clock_query, Callable(), Callable(), bag.count, _result).get("ok", false), "真实Service内容及端口有效")
	var ready := true
	for method in ["character_profile", "conversation_topics", "start_topic"]:
		if not check(real.has_method(method), "真实Service提供 " + method): ready = false
	if ready:
		real.affinity_changed.connect(_affinity)
		real.relation_edge_changed.connect(_edge)
		real.request_completed.connect(_request)
		attach(real)
		await exercise_roster(real, "真实Service")
		await vendors(real, "真实Service")
		check(gameplay_signals.is_empty(), "阅读、取消、完成话题及逛店均不触发好感/关系/请求/结果结算")
		real.vendor_requested.disconnect(_vendor)
	panel.cancel_session()
	shop_panel.close()
	panel.free()
	shop_panel.free()
	panel = null
	shop_panel = null
	real.dispose()
	real = null
	fake = null
	shop = null
	bag = null
	await process_frame
	print("[npc-profile-ui] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func privacy_and_queries(fake) -> void:
	panel.open_npc("npc_luo_yan")
	check(fake.queries == {"profile": 0, "topics": 0}, "主页不请求新资料和话题")
	await press("profile")
	check(fake.queries == {"profile": 1, "topics": 0}, "认识页只查询资料一次")
	check(not labels().contains("豆豆") and not labels().contains("一起做过事"), "未认识者连看法正文中的名字也不泄漏")
	check(not labels().contains("这件隐情"), "公开资料不展示secret_or_regret")
	var snapshot: Dictionary = panel.panel_snapshot()
	snapshot.profile.profile.personality = "外部篡改"
	check(fake.character_profile("npc_luo_yan").profile.personality == "说话实在", "资料快照不修改服务静态内容")
	await press("back")
	await press("relationships")
	check(not labels().contains("豆豆") and not labels().contains("和解答案"), "未认识关系不显示姓名或和解内容")
	fake.meet("npc_ji_chen")
	panel._render()
	check(labels().contains("以前一起修过踏板") and labels().contains("两个人还没把话说开"), "已知关系展示summary/history/tension")
	check(not labels().contains("未完成剧情的和解答案"), "认识双方不等于已看过关系剧情")
	fake.completed_relation = true
	panel._render()
	check(labels().contains("未完成剧情的和解答案"), "对应关系剧情完成才展示reconcile")
	fake.completed_relation = false
	await press("back")
	var before: Dictionary = fake.queries.duplicate()
	for frame in 4: panel._process(1.0)
	check(fake.queries == before, "主页逐帧不查询大资料")
	panel.configure(fake)
	panel.open_npc("npc_luo_yan")
	check(panel.panel_snapshot().home == "暂驻点尚未登记" and labels().contains("常在") and not labels().contains("七灯住所港"), "未登记provider标签明确回退，不冒充旧住处")
	panel.configure(fake, home_labels())

func exercise_roster(service, source: String) -> void:
	for id in NAMES: service.meet(id)
	var before: Dictionary = service.to_dict()
	var inventory_before: Dictionary = bag.to_dict()
	var topic_count := 0
	var note_count := 0
	var edges: Array = service.relationship_graph()
	check(edges.size() == 9, source + "仍保留9条基础关系")
	var bases := {}
	for edge in Catalog.relationships(): bases[edge.id] = edge.base
	for edge in edges: check(bases.get(edge.id) == edge.base, source + "保留原关系base " + str(edge.id))
	for id in NAMES:
		var seen_topics := {}
		check(panel.open_npc(id).ok, source + "打开 " + id)
		check(panel._title.text.begins_with(NAMES[id]), source + "显示地气姓名 " + id)
		check(labels().contains("东南海上商店暂驻" if id == "npc_bao_he" else "天台草地暂驻"), source + "活动点来自注入标签 " + id)
		# 资料/话题属于显式“聊聊”子菜单，默认入场由npc-conversation专项覆盖。
		if service.dialogue_state().get("active", false): panel.session.command("home")
		await press("chat")
		check(button("profile").text == "认识一下" and button("topics").text == "聊点别的", source + "主页两个新入口")
		await press("profile")
		var character: Dictionary = panel.panel_snapshot().profile
		var profile: Dictionary = character.get("profile", {})
		for field in FIELDS:
			check(not str(profile.get(field, "")).is_empty() and labels().contains(str(profile.get(field, ""))), source + "公开背景字段 " + id + "/" + field)
		var notes: Array = character.get("social_notes", [])
		check(notes.size() == 6, source + "每人对其余6人的看法 " + id)
		for note in notes:
			note_count += 1
			check(note.npc_id != id and NAMES.has(note.npc_id) and labels().contains(str(note.text)), source + "已知看法展示 " + id + "/" + str(note.npc_id))
		check(not labels().contains(str(profile.get("secret_or_regret", "不应出现的隐情"))), source + "不公开隐情 " + id)
		await press("back")
		check(panel.panel_snapshot().section == "home", source + "资料返回主页")
		await press("topics")
		var topics: Array = panel.panel_snapshot().topics
		check(topics.size() == 4, source + "每人4话题 " + id)
		for topic in topics:
			topic_count += 1
			check(not seen_topics.has(topic.id), source + "话题ID不重复 " + str(topic.id))
			seen_topics[topic.id] = true
			check(button("topic", str(topic.id)) != null and button("topic", str(topic.id)).text == topic.title, source + "话题标题可操作")
			await press("topic", str(topic.id))
			var state: Dictionary = service.dialogue_state()
			if not check(state.get("active", false), source + "start_topic开启真实对白"): continue
			check(state.total >= 2 and state.typing, source + "话题为多页并先打字")
			await press("back")
			check(not service.dialogue_state().get("active", false) and panel.panel_snapshot().section == "topics", source + "取消话题回列表")
			check(service.to_dict() == before, source + "取消话题无持久结算")
			await press("topic", str(topic.id))
			await finish_dialogue(service)
			check(panel.panel_snapshot().section == "topics" and button("topic", str(topic.id)) != null, source + "听完回列表且可重聊")
			check(service.to_dict() == before, source + "完整阅读不加好感、日期、事件和请求")
		if not topics.is_empty():
			await press("topic", str(topics[0].id))
			panel.cancel_session()
			check(not panel.is_modal() and not service.dialogue_state().get("active", false) and service.to_dict() == before, source + "直接关闭活动话题也不结算")
			panel.open_npc(id)
			await press("topics")
		await press("back")
		check(panel.panel_snapshot().section == "home", source + "话题列表返回主页")
		await press("close")
		check(not panel.is_modal(), source + "告别关闭")
	check(topic_count == 28 and note_count == 42, source + "实际操作7资料、28话题及42看法")
	check(service.to_dict() == before and bag.to_dict() == inventory_before, source + "所有阅读不改持久状态和库存")

func navigation(fake) -> void:
	panel.open_npc("npc_luo_yan")
	var opening := key(KEY_ENTER)
	panel.handle_input(opening)
	panel.handle_input(key(KEY_ENTER, false))
	check(panel.panel_snapshot().section == "home", "打开同帧交互键不误入新页")
	await press("chat")
	await process_frame
	button("profile").grab_focus()
	var event := key(KEY_ENTER)
	panel.handle_input(event)
	panel.handle_input(event)
	panel.handle_input(key(KEY_SPACE))
	panel.handle_input(key(KEY_ENTER, false))
	panel.handle_input(key(KEY_SPACE, false))
	check(panel.panel_snapshot().section == "profile", "重复分发及同帧不同确认键只进入资料页一次")
	await process_frame
	panel.handle_input(key(KEY_ENTER, true, true))
	panel.handle_input(key(KEY_ENTER, false))
	check(panel.panel_snapshot().section == "profile", "长按回声不触发新页按钮")
	await tap(KEY_ESCAPE)
	check(panel.panel_snapshot().section == "home", "Esc资料返回主页")
	await press("chat")
	button("talk").grab_focus()
	await tap(KEY_DOWN)
	check(root.gui_get_focus_owner() == button("topics"), "方向键移动到话题入口")
	await tap(KEY_TAB)
	check(root.gui_get_focus_owner() == button("events"), "Tab导航有效")
	await mouse_click(button("topics"))
	check(panel.panel_snapshot().section == "topics", "真实鼠标点击进入话题列表")
	var topic_id := "npc_luo_yan_topic_0"
	var stale_topic: Callable = button("topic", topic_id).pressed.get_connections()[0].callable
	await press("topic", topic_id)
	var first: Dictionary = fake.dialogue_state()
	var stale_advance: Callable = panel._command.bind("advance", {"npc_id":panel.session.npc_id,"session_id":first.session_id}, panel._render_serial)
	var queries: Dictionary = fake.queries.duplicate()
	panel._process(0.01)
	check(fake.dialogue_state().typing and panel._text.visible_characters == 0, "文字按打字速度逐步显示")
	await process_frame
	panel._process(10.0)
	check(not fake.dialogue_state().typing and fake.dialogue_state().index == first.index, "自动打字完成只揭示本页，不跳页")
	check(fake.queries == queries, "打字逐帧和对白刷新不重新拷贝资料或话题列表")
	await press("choice", "listen")
	check(fake.dialogue_state().index == 1, "话题选择复用原对白分支")
	await tap(KEY_ESCAPE)
	check(panel.panel_snapshot().section == "topics" and not fake.dialogue_state().active, "Esc中断多页话题回列表")
	await press("topic", topic_id)
	var current: Dictionary = fake.dialogue_state()
	stale_topic.call()
	stale_advance.call()
	check(fake.dialogue_state() == current, "旧列表/旧页按钮serial不能作用新话题")
	check(not panel.session.command("advance", {"session_id": first.session_id}).ok and fake.dialogue_state() == current, "旧对白session_id不能推进新话题")
	paused = true
	await press("advance")
	panel._process(10.0)
	check(fake.dialogue_state() == current, "暂停阻止鼠标推进和打字")
	await tap(KEY_ENTER)
	check(fake.dialogue_state() == current, "暂停阻止键盘推进")
	await tap(KEY_ESCAPE)
	check(not fake.dialogue_state().active and panel.panel_snapshot().section == "topics", "暂停时Esc仍可取消对白")
	paused = false
	await tap(KEY_ESCAPE)
	await tap(KEY_ESCAPE)
	check(not panel.is_modal(), "Esc从列表回主页后关闭")
	check(panel.handle_input(key(KEY_ESCAPE, false)) == false, "已释放的关闭键不遗留模态")
	panel.open_npc("npc_mu_he")
	stale_topic.call()
	check(panel.panel_snapshot().npc_id == "npc_mu_he" and not fake.dialogue_state().active, "跨NPC旧回调失效")
	panel.cancel_session()

func vendors(service, source: String) -> void:
	var before: Dictionary = service.to_dict()
	var inventory_before: Dictionary = bag.to_dict()
	var calls := vendor_calls.size()
	for id in ["npc_hua_yi", "npc_bao_he"]:
		panel.open_npc(id)
		await press("profile")
		await press("back")
		await press("topics")
		await press("back")
		check(not shop_panel.is_open(), source + "浏览资料、话题、服务页均未自动开商店")
		await press("vendor")
		check(not panel.is_modal() and shop_panel.is_open(), source + "vendor先关NPC再打开独立商店")
		check(vendor_calls.back().npc_closed and shop_panel._shop_id == service.npc_snapshot(id).shop_id, source + "花店与阿店商店不串店")
		shop_panel.close()
	check(vendor_calls.size() == calls + 2 and service.to_dict() == before and bag.to_dict() == inventory_before, source + "两经营者只各路由一次，不扣库存不加好感")
