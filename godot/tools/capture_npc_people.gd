extends "res://tools/capture_npc_release.gd"
## 当前Main真实人物与业务界面；只改相机和近景展示朝向，不挪根、不关闭升沉。
var front_shots := 0

func run() -> void:
	marker = "npc-people-render"
	if not check(DisplayServer.get_name() != "headless", "人物截图必须真实渲染") or not await boot():
		await finish(); return
	root.size = Vector2i(1920, 1080)
	if not landing_fixture("rooftop_ranch"):
		await finish(); return
	if not await until(func():
		for row in world.world_snapshot().residents.values():
			if row.remaining_waypoints > 0: return false
		return true, 45.0, "真实七人日程落位后取景"):
		await finish(); return
	cache_visual_occluders()
	if await roof_group(): await shot("roof-six-group")
	for id in Catalog.ids():
		if id == "npc_bao_he": continue
		await person(id)
	# 起点来自合法restore，跨站只走Main正式上下船与航行链。
	if not await sail_to_supply():
		await finish(); return
	visual_occluders.clear()
	for mesh: MeshInstance3D in sea_site.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var faces := mesh.mesh.get_faces()
		if not faces.is_empty(): visual_occluders.append({"mesh": mesh, "faces": faces, "inverse": mesh.global_transform.affine_inverse(), "bounds": mesh.global_transform * mesh.get_aabb()})
	aim(sea_site.global_position, 25.0)
	await shot("sea-shop-overview")
	var target: Vector3 = world.actor("npc_bao_he").global_position
	if await walk_to(target + Vector3(0.8, 0, 1.0), "从浮店泊位实走Counter附近"):
		check(main.player.global_position.distance_to(sea_site.get_node("Objects/SupplyCounter").global_position) < 3.5, "玩家实到Counter附近")
	await person("npc_bao_he")
	if await open_npc("npc_bao_he") and await npc_press("topics"):
		await shot("sea-topic-selection")
		var topics: Array = world.panel.panel_snapshot().topics
		if not topics.is_empty() and await npc_press("topic", topics[0].id):
			if main.npc_service.dialogue_state().typing: await npc_press("advance")
			check(world.panel._text != null and world.panel._text.visible_characters == -1, "话题实际文字完整可见")
			await shot("sea-topic-dialogue")
	await close_modals()
	if await open_npc("npc_bao_he") and await npc_press("relationships"):
		check(not world.panel._body.get_children().is_empty(), "关系页为真实Service内容")
		await shot("sea-relationships")
	await close_modals()
	check(economy.inventory.add("coins", 200).ok, "截图真实购买余额")
	if await vendor("npc_bao_he", "shop_general"):
		check(main.shop_panel._title.text == "阿店海上商店", "阿店海上商店标题正确")
		var panel = main.shop_panel
		var quote: Dictionary = main.shop_service.quote("shop_general", panel._selected_id, 1)
		var before: Dictionary = main.npc_service.to_dict()
		var coins: int = economy.inventory.count("coins")
		var count: int = economy.inventory.count(quote.item)
		if check(panel.open_actions() and quote.ok and not panel._buy.disabled, "海店图标格选中后气泡报价可购"):
			panel._buy.pressed.emit()
			await frames(3)
			check(economy.inventory.count("coins") == coins - int(quote.total_cost)
				and economy.inventory.count(quote.item) == count + 1 and main.npc_service.to_dict() == before
				and panel._feedback.text.contains("已购入"), "海店购买真实扣款给物不加NPC好感")
			await shot("sea-purchase")
	await close_modals()
	# 花店面板路由与标题来自实际Main服务，不改UI文案造图。
	if await vendor("npc_hua_yi", "shop_flower"):
		check(main.shop_panel._title.text.contains("小花"), "小花花店标题使用新名")
		await shot("flower-title")
	await close_modals()
	check(front_shots == 7, "七人实际正面近景")
	for required in ["roof-six-group", "sea-shop-overview", "sea-topic-selection", "sea-topic-dialogue", "sea-relationships", "sea-purchase", "flower-title"]:
		check(required in shots, "必需人物截图已生成 " + required)
	check(shots.size() == 28, "7正面7身份7背景及7场景业务共28张新截图")
	print("[npc-people-png] ", shots.size(), " PNG，目录=", ProjectSettings.globalize_path("res://outputs"))
	await finish()

func roof_group() -> bool:
	var ids: Array = Catalog.ids()
	ids.erase("npc_bao_he")
	var center := Vector3.ZERO
	var positions := {}
	for id in ids:
		center += world.actor(id).global_position
		positions[id] = world.actor(id).global_position
	center /= 6.0
	var best := {}
	var score := -1.0
	for yaw_degrees in [0, -30, 30, -60, 60, -90, 90, 180]:
		for pitch_degrees in [32, 40, 48, 56]:
			main.cam.target = center + Vector3.UP
			var yaw := deg_to_rad(float(yaw_degrees))
			var pitch := deg_to_rad(float(pitch_degrees))
			main.cam.dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			main.cam.follow_enabled = false
			main.cam.pose_lock = true
			main.cam.set_distance(70.0)
			var good := true
			var minimum := INF
			for id in ids:
				var metrics := actor_metrics(world.actor(id))
				good = good and metrics.visible and metrics.pixels >= 28.0
				minimum = minf(minimum, metrics.pixels)
			if good and minimum > score:
				score = minimum
				best = {"direction": main.cam.dir}
	if not check(not best.is_empty(), "六天台真实同框均可见且至少28px"): return false
	main.cam.dir = best.direction
	main.cam.apply_pose()
	await frames(3)
	for id in ids:
		check(npc_supported(id) and world.actor(id).global_position == positions[id], "六人原站位保持不变 " + id)
		check(actor_visible(world.actor(id), 28.0), "六人同框真实可见 " + id)
	return true

func person(id: String) -> void:
	await close_modals()
	var body = world.actor(id)
	if not await fit_actor_camera(body): return
	var previous_yaw: float = body.body_pivot.rotation.y
	var direction: Vector3 = main.cam.global_position - body.global_position
	body.set_preview_yaw(atan2(direction.x, direction.z) - body.rotation.y)
	await frames(3)
	check(actor_visible(body, 110.0) and npc_supported(id), "实际人物正面有支撑且无遮挡 " + id)
	await shot(id.trim_prefix("npc_") + "-front")
	front_shots += 1
	if not await open_npc(id): return
	check(world.panel._title.text.begins_with(NAMES[id]) and world.panel._identity.is_visible_in_tree(), "真实姓名身份可见 " + id)
	await shot(id.trim_prefix("npc_") + "-identity")
	if await npc_press("profile"):
		check(world.panel.panel_snapshot().section == "profile", "真实背景资料页 " + id)
		await shot(id.trim_prefix("npc_") + "-background")
	await close_modals()
	body.set_preview_yaw(previous_yaw)

func shot(id: String) -> void:
	var before := failures
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not check(image != null and not image.is_empty() and image.get_width() >= 1280 and image.get_height() >= 720, "真实人物viewport有效 " + id): return
	var colors := {}
	for y in range(0, image.get_height(), 32):
		for x in range(0, image.get_width(), 32): colors[image.get_pixel(x, y).to_html()] = true
	check(colors.size() > 24, "真实渲染非空 " + id)
	var path := "res://outputs/npc-people-" + id + ".png"
	if check(image.save_png(path) == OK, "保存新截图 " + path) and before == failures: shots.append(id)
	print("[npc-people-shot] ", ProjectSettings.globalize_path(path))
