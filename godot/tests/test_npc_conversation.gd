extends "res://tests/test_npc_integration.gd"
## 默认正式Main，实际点击/接近/Interactor/底部壳/功能路由；仅隔离runner执行。
var visual := false
var shots: Array[String] = []

func run() -> void:
	marker = "npc-conversation"
	visual = DisplayServer.get_name() != "headless"
	if not await boot():
		await finish(); return
	check(world.panel.dialogue_view == main.hud.dialogue, "复用HUD原底部对话框实例")
	if not landing_fixture("rooftop_ranch"):
		await finish(); return
	var roof: Vector3 = harbor.to_global(Vector3(0, harbor.ROOF_Y, 9))
	if not await walk_to(roof, "沿正式消防梯进入天台"):
		await finish(); return
	await until(func():
		for row in world.world_snapshot().residents.values():
			if row.remaining_waypoints > 0: return false
		return true, 45.0, "七人日程落位")
	for id in Catalog.ids():
		if id == "npc_bao_he" and not landing_fixture("sea_supply"): continue
		# 豆豆 2026-11-08 起在霓虹花园菜园桥（离水面约 28 米）。用户明确选择
		# 「只让她在楼上种菜、不额外做上楼路径」，所以「走近交谈」在她身上不成立：
		# 玩家在楼下船上能看到她、收到头顶招呼，但走不到判定区。
		# 她的站立、可走面、招呼由 garden-npc 与 visual-garden-bubble 验。
		if id == "npc_mu_he":
			check(world.actor("npc_mu_he").visible, "豆豆在花园楼顶可见（不走走近交谈链）")
			continue
		await contact(id)
	await stories()
	await persistence_and_chance()
	await cancellation()
	await layout_sizes()
	if visual: print("[npc-conversation-render] %d PNG" % shots.size())
	await finish()

func contact(id: String) -> void:
	await close_modals()
	var body = world.actor(id)
	var spot = body.get_node("NpcInteractable")
	var site = sea_site if id == "npc_bao_he" else harbor
	var hub: Vector3 = site.landing_point("main").stand_position() if id == "npc_bao_he" else harbor.to_global(Vector3(0, harbor.ROOF_Y, 11.5))
	var point: Vector3 = body.global_position + (hub - body.global_position).normalized() * 3.5
	if not await walk_to(point, "交谈前站在判定区外 " + id): return
	aim(body.global_position, 13.0)
	await frames(3)
	var screen: Vector2 = main.cam.unproject_position(spot.focus_position() + Vector3.UP * 0.75)
	var hit: Dictionary = main.hover._pick(screen)
	if not check(hit.get("node") == spot, "真实屏幕命中居民 " + id): return
	var start: Vector3 = main.player.global_position
	await click(screen)
	check(not main.hud.world_actions.is_open(), "点击居民不弹物体气泡 " + id)
	if not await until(func(): return world.is_modal(), 20.0, "一次点击自动接近交谈 " + id): return
	check(main.player.global_position.distance_to(start) > 0.1, "确实先走近 " + id)
	check(main.npc_service.dialogue_state().dialogue_id == id + "_intro", "初见直接开始介绍 " + id)
	check(main.hud.dialogue.panel.visible and not world.panel._paper.visible
		and not main.shop_panel.is_open() and not main.npc_career_panel.is_open(), "只有底部台词，没有资料/功能面板 " + id)
	check(main.hud.dialogue.choice_buttons.is_empty(), "介绍期间不提前出现服务选项 " + id)
	var serial: int = main.npc_service.dialogue_state().session_id
	var page: int = main.npc_service.dialogue_state().index
	await key(KEY_ENTER)
	check(main.npc_service.dialogue_state().session_id == serial and main.npc_service.dialogue_state().index == page,
		"首确认只补全当前句 " + id)
	await create_timer(0.3).timeout
	var to_player: Vector3 = main.player.global_position - body.global_position
	to_player.y = 0
	check(body.global_basis.z.normalized().dot(to_player.normalized()) > 0.98, "NPC朝向玩家 " + id)
	await capture(id + "-intro")
	if not await finish_dialogue(): return
	check(main.npc_service.npc_snapshot(id).runtime.last_talk_day == main.world_clock.day, "介绍读完才记忆并结算 " + id)
	check(main.hud.dialogue.panel.visible and not main.npc_service.dialogue_state().active,
		"台词结束转功能问候 " + id)
	check(main.hud.dialogue.choice_buttons.size() == 3, "服务、聊聊、退出三个小选项 " + id)
	await capture(id + "-choices")
	var before: Vector3 = main.player.global_position
	await key(KEY_W)
	await frames(4)
	check(main.player.global_position.distance_to(before) < 0.05, "对话时世界输入不穿透 " + id)
	if Catalog.get_npc(id).has("shop_id"):
		await npc_press("vendor")
		check(main.shop_panel.is_open() and not world.is_modal() and not main.hud.dialogue.panel.visible,
			"选择商店后才进入独立商店 " + id)
		await capture(id + "-shop")
	else:
		await npc_press("function")
		check(main.npc_career_panel.is_open() and not world.is_modal() and not main.hud.dialogue.panel.visible,
			"选择职业后才打开功能 " + id)
	await close_modals()
	var near: Vector3 = body.global_position + (main.player.global_position - body.global_position).normalized() * 1.7
	if await walk_to(near, "近距E入口 " + id):
		main.interactor.refresh_now()
		for attempt in 24:
			if main.interactor.target == spot: break
			await key(KEY_Q)
		check(main.interactor.target == spot, "近距同一NPC焦点 " + id)
		send(KEY_E, true, true)
		await until(func(): return world.is_modal(), 5.0, "E直接开始底部对话 " + id)
		send(KEY_E, false, true)
		check(main.hud.dialogue.panel.visible and not main.hud.world_actions.is_open(), "E与点击同一对话入口 " + id)
	await close_modals()

func stories() -> void:
	await close_modals()
	if not landing_fixture("rooftop_ranch"): return
	var roof: Vector3 = harbor.to_global(Vector3(0, harbor.ROOF_Y, 9))
	if not await walk_to(roof, "剧情前沿消防梯回到天台"): return
	var body = world.actor("npc_luo_yan")
	if not await walk_to(body.global_position + (roof - body.global_position).normalized() * 1.7, "走到剧情说话人身边"): return
	aim(body.global_position, 13.0)
	var saved: Dictionary = main.npc_service.to_dict()
	for id in Catalog.ids(): saved.graph.met[id] = true
	saved.graph.affinity.npc_luo_yan = 200
	saved.graph.last_talk_day.npc_luo_yan = 1
	check(main.npc_service.from_dict(saved).ok, "有效进度前置开启剧情")
	check(world.open_npc("npc_luo_yan").ok, "打开剧情居民")
	check(main.npc_service.dialogue_state().dialogue_id == "route_1", "条件剧情优先于功能问候")
	await npc_press("advance")
	await capture("story-before-service")
	await key(KEY_ESCAPE)
	check(not world.is_modal() and not main.npc_service.to_dict().seen_events.has("route_1"), "剧情中取消不提交")
	check(world.open_npc("npc_luo_yan").ok, "取消后剧情可重试")
	var captured_choice := false
	for step in 120:
		var dialogue: Dictionary = main.npc_service.dialogue_state()
		if not dialogue.active: break
		if not dialogue.typing and dialogue.page.has("choices"):
			if not captured_choice:
				await capture("story-branch")
				captured_choice = true
			if not await npc_press("choice", dialogue.page.choices[0].id): return
		else:
			if not await npc_press("advance"): return
	check(captured_choice, "剧情真实分支在右侧展示并可选择")
	check(main.hud.dialogue.choice_buttons.size() == 3 and main.npc_service.list_events("npc_luo_yan")[0].completed,
		"剧情完成才回功能选项，事件单次提交")
	await capture("story-completed-service")
	await close_modals()

func persistence_and_chance() -> void:
	if not landing_fixture("sea_supply"): return
	var body = world.actor("npc_bao_he")
	var stand: Vector3 = sea_site.landing_point("main").stand_position()
	if not await walk_to(body.global_position + (stand - body.global_position).normalized() * 3.5, "回到阿店商店前"): return
	aim(body.global_position, 13.0)
	main._open_spot_bubbles(body.get_node("NpcInteractable"))
	if not await until(func(): return world.is_modal(), 15.0, "原接近链走到阿店身边复验"): return
	await close_modals()
	var saved: Dictionary = main.npc_service.to_dict()
	var file := FileAccess.open("user://conversation-roundtrip.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(saved)); file.close()
	check(main.npc_service.from_dict(JSON.parse_string(FileAccess.get_file_as_string("user://conversation-roundtrip.json"))).ok,
		"旧v1结构文件往返恢复")
	check(world.open_npc("npc_bao_he").ok, "恢复后再找阿店")
	check(main.npc_service.dialogue_state().get("dialogue_id", "") != "npc_bao_he_intro", "读档不重播已听完的初见")
	await close_modals()
	var daily := 0
	var greeting := 0
	for day in range(2, 22):
		main.world_clock.day = day
		var result: Dictionary = main.npc_service.start_conversation("npc_bao_he")
		check(result.ok, "正常日常概率分流")
		var first: Dictionary = main.npc_service.dialogue_state()
		if first.active: daily += 1
		else: greeting += 1
		main.npc_service.close_dialogue()
		main.npc_service.start_conversation("npc_bao_he")
		check(main.npc_service.dialogue_state().get("dialogue_id", "") == first.get("dialogue_id", ""), "同日重开不刷概率")
		main.npc_service.close_dialogue()
	check(daily > 0 and greeting > 0, "既有偶发日常，也有直接功能问候")
	main.world_clock.day = 1
	check(main.npc_service.from_dict(saved).ok, "恢复测试前进度")

func cancellation() -> void:
	for reason in ["paused", "sleeping", "player_indoors", "dialogue_active"]:
		await close_modals()
		check(world.open_npc("npc_bao_he").ok, "打开后模拟取消 " + reason)
		var clock: Dictionary = main._npc_world_query()
		clock[reason] = true
		world.notify_world(clock)
		world._physics_process(0.01)
		check(not world.is_modal() and not main.hud.dialogue.panel.visible
			and not main.hud.dialogue.choice_panel.visible and not main.npc_service.dialogue_state().active,
			"外部状态完整清理台词/选项/会话 " + reason)
		world.notify_world(main._npc_world_query())
	await close_modals()
	main.hud.show_dialogue_sequence([{"speaker":"我", "text":"普通开场第一句。"}, {"speaker":"我", "text":"普通开场第二句。"}])
	check(main.hud.narrative_active() and not main.hud.dialogue.conversation_mode, "原开场多句仍阻断世界")
	main.hud.dialogue.close_line()

func layout_sizes() -> void:
	for size in [Vector2i(1280,800), Vector2i(1600,1000), Vector2i(1920,1080)]:
		await close_modals()
		root.size = size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		check(world.open_npc("npc_bao_he").ok, "适配视口打开会话")
		await finish_dialogue()
		await frames(3)
		var view = main.hud.dialogue
		var screen := root.get_visible_rect()
		print("[conversation-layout] window=", root.size, " viewport=", screen,
			" dialogue=", view.panel.get_global_rect(), " menu=", view.choice_panel.get_global_rect())
		check(screen.encloses(view.panel.get_global_rect()) and screen.encloses(view.choice_panel.get_global_rect())
			and not view.panel.get_global_rect().intersects(view.choice_panel.get_global_rect()), "对话与菜单完整且不重叠 " + str(size))
		await capture("layout-%dx%d" % [size.x, size.y])
		await npc_press("chat")
		await frames(2)
		check(screen.encloses(view.choice_panel.get_global_rect()), "聊聊子菜单不出屏 " + str(size))
		await capture("chat-%dx%d" % [size.x, size.y])
	await close_modals()

func capture(label: String) -> void:
	if not visual: return
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://outputs/npc-conversation")
	var path := "res://outputs/npc-conversation/" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "真实PNG " + label)
	shots.append(path)
