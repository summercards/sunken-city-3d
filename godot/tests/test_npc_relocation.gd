extends "res://tests/test_npc_integration.gd"
## 真实Main两站点验收；共享原集成闭环，不以独立陈列fixture替代。

func run() -> void:
	marker = "npc-relocation"
	if not await boot():
		await finish(); return
	await travel()
	await homes_and_interactions()
	await people_ui()
	check(economy.inventory.add_all({"coins": 200}), "真实海店购买余额")
	await buy("npc_bao_he", "general_soil", 2)
	for section in ["travel", "sea-supply-travel", "two-site-stations", "seven-click-e", "people-ui"]:
		check(section in completed_sections, "迁移闭环完成 " + section)
	await finish()

func panel_labels() -> String:
	var text: String = world.panel._title.text + "\n" + world.panel._identity.text
	for child in world.panel._body.get_children():
		if child is Label: text += "\n" + child.text
	return text

func people_ui() -> void:
	for id in Catalog.ids():
		if not await open_npc(id): return
	await close_modals()
	var durable: Dictionary = main.npc_service.to_dict()
	var inventory_before: Dictionary = economy.inventory.to_dict()
	var topic_count := 0
	var page_count := 0
	var profiles := 0
	var notes := 0
	for id in Catalog.ids():
		if not await open_npc(id) or not await npc_press("profile"): continue
		var character: Dictionary = world.panel.panel_snapshot().profile
		check(world.panel._title.text.begins_with(NAMES[id]), "资料显示新姓名 " + id)
		for field in ["age_range", "personality", "past", "arrival_reason", "short_term_wish", "habit", "catchphrase"]:
			check(not str(character.profile.get(field, "")).is_empty() and panel_labels().contains(str(character.profile[field])), "真实Main公开背景 " + id + "/" + field)
		for note in character.social_notes:
			notes += 1
			check(panel_labels().contains(str(note.text)), "真实Main已认识社交看法 " + id + "/" + str(note.npc_id))
		profiles += 1
		if not await npc_press("back") or not await npc_press("topics"): continue
		var topics: Array = world.panel.panel_snapshot().topics
		check(topics.size() == 4, "每人四个正式话题 " + id)
		for topic in topics:
			if not await npc_press("topic", topic.id): continue
			var dialogue: Dictionary = main.npc_service.dialogue_state()
			check(dialogue.active and dialogue.total >= 2, "话题真实多页开始 " + topic.id)
			page_count += int(dialogue.get("total", 0))
			if not await npc_press("back"): continue
			check(not main.npc_service.dialogue_state().active and main.npc_service.to_dict() == durable, "话题取消无副作用 " + topic.id)
			if not await npc_press("topic", topic.id) or not await finish_dialogue(): continue
			check(main.npc_service.to_dict() == durable and economy.inventory.to_dict() == inventory_before, "话题完整读完不改日期好感事件请求库存 " + topic.id)
			topic_count += 1
		if not await npc_press("back") or not await npc_press("relationships"): continue
		var text := panel_labels()
		for edge in main.npc_service.relationship_graph():
			if id not in [edge.from, edge.to] or not edge.known: continue
			check(not str(edge.get("summary", "")).is_empty() and text.contains(str(edge.summary)), "已认识关系展示新summary " + edge.id)
			if not str(edge.get("reconcile", "")).is_empty():
				check(not text.contains(str(edge.reconcile)), "未完成关系事件不泄漏reconcile " + edge.id)
		await close_modals()
	check(main.npc_service.to_dict() == durable and economy.inventory.to_dict() == inventory_before, "全部资料话题关系只读")
	if check(profiles == 7 and topic_count == 28 and page_count >= 56 and notes == 42, "真实Main7资料28话题56页42看法全部操作"):
		completed_sections.append("people-ui")
	print("[npc-people-ui-counts] profiles=", profiles, " topics=", topic_count, " pages=", page_count, " notes=", notes)
