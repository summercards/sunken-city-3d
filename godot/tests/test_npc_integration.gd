extends SceneTree
## 正式 main 集成；只由隔离 runner 执行。另两个入口复用本脚本的夹具和断言。
const Save = preload("res://src/save/save_game.gd")
const Codec = preload("res://src/npc/npc_save_codec.gd")
const Catalog = preload("res://src/npc/npc_catalog.gd")
const BuildingCatalog = preload("res://src/building/building_catalog.gd")
var marker := "npc-integration"
var checks := 0
var failures := 0
var main
var economy
var state
var zones
var world
var harbor
var provider
var roof_provider
var sea_provider
var sea_site
var garden_site
var garden_provider
var left_roof_provider
var authored_garden_transform := Transform3D.IDENTITY
var active_section := "启动"
var finished := false
var authored_sea_transform := Transform3D.IDENTITY
const NAMES := {"npc_luo_yan": "船老大", "npc_mu_he": "豆豆", "npc_ji_chen": "阿海",
	"npc_nan_zhi": "木头叔", "npc_bai_shi": "灯伯", "npc_hua_yi": "小花", "npc_bao_he": "阿店"}
var authored_roof_transform := Transform3D.IDENTITY
var authored_provider_transform := Transform3D.IDENTITY
var profile_before: Dictionary = {}
var slot_before: Dictionary = {}
var completions: Array = []
var arrivals: Array = []
var actor_states: Array[String] = []
var held_keys: Dictionary = {}
var completed_sections: Array[String] = []

func _init() -> void:
	call_deferred("start_run")

func start_run() -> void:
	# 逻辑验证加倍采样频率并同步加倍模拟时速，物理步长仍为 1/60 秒。
	# 保留完整真实航路/碰撞/结算，不增大 runner 的 180 秒墙钟预算。
	if DisplayServer.get_name() == "headless":
		Engine.physics_ticks_per_second = 120
		Engine.time_scale = 2.0
		print("[npc-test-simulation] physics_hz=120 time_scale=2 step=1/60")
	# 脚本异常可能中断协程，不能只依赖 run 尾部清理或 runner 的 124。
	create_timer(170.0, true, false, true).timeout.connect(func():
		if finished: return
		check(false, "测试未收尾，最后阶段=" + active_section)
		if is_instance_valid(main) and main.is_inside_tree():
			printerr("[", marker, "-watchdog] actor=", main.actor_controller.snapshot(),
				" boat=", main.boat.global_position, " remaining=", main.boat.remaining_distance(),
				" npc=", world.world_snapshot())
		print("[%s] %d checks, %d failures" % [marker, checks, failures])
		quit(1))
	await run()

func section(label: String) -> void:
	active_section = label
	print("[", marker, "-section] ", label, " ticks=", Time.get_ticks_msec())

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [", marker, "] ", label)
	return ok

func frames(count := 2) -> void:
	for i in count:
		await physics_frame
		await process_frame

func until(predicate: Callable, seconds: float, label: String) -> bool:
	section("等待 " + label)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()): return true
		await frames(1)
	check(false, label)
	if main != null:
		printerr("[", marker, "-state] ", main.actor_controller.snapshot(), " player=", main.player.global_position,
			" zone=", state.current_zone, " target=", main.interactor.target, " blocked=", main.interactor.last_blocked,
			" toast=", main.hud._toast.text, " npc=", world.world_snapshot())
		printerr("[", marker, "-boat-state] position=", main.boat.global_position,
			" remaining=", main.boat.remaining_distance(), " route=", main.boat.route,
			" wp=", main.boat._wp, " velocity=", main.boat._vel,
			" speed_actual=", main.boat._speed_actual, " processing=", main.boat.is_processing(),
			" process_frames=", Engine.get_process_frames(), " physics_frames=", Engine.get_physics_frames(),
			" fps=", Engine.get_frames_per_second())
	return false

func send(code: int, pressed: bool, continuous := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	if continuous:
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed: held_keys[code] = true
		else: held_keys.erase(code)
	else:
		root.push_input(event, true)

func key(code: int) -> void:
	send(code, true)
	await process_frame
	send(code, false)
	await process_frame

func click(point: Vector2) -> void:
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

func equivalent(left: Variant, right: Variant) -> bool:
	# JSON将整数读为float；递归比数值，不把wire类型变化误报为owner被改写。
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) <= 0.000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for field in left:
			if not right.has(field) or not equivalent(left[field], right[field]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for i in left.size():
			if not equivalent(left[i], right[i]): return false
		return true
	return left == right

func file_state(path: String) -> Dictionary:
	return {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}

func boot() -> bool:
	var args := OS.get_cmdline_user_args()
	if not check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
		and str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"),
		"必须在 Autoload 前由 runner 隔离 user 目录"): return false
	if not check(args.has("--skip-title") and args.has("--nosave") and not args.has("--full-world"),
		"必须使用默认正式范围、--skip-title、--nosave"): return false
	for arg in args:
		if not check(not (arg.begins_with("--load") or arg.begins_with("--savepath=") or arg == "--saveshot"
			or arg == "--capture" or arg == "--selftest"), "禁止主场景启动时隐式读写/另起截图：" + arg): return false
	slot_before = {"primary": file_state(Save.SLOT_PATH), "backup": file_state(Save.SLOT_PATH + ".bak")}
	var path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not check(path == "res://scenes/main.tscn", "项目默认入口必须是正式 main.tscn"): return false
	var packed = load(path)
	if not check(packed is PackedScene, "正式 main 可以加载"): return false
	main = packed.instantiate()
	harbor = main.get_node_or_null("World/SeaStructures/rooftop_ranch")
	roof_provider = main.get_node_or_null("World/SeaStructures/rooftop_ranch/NpcStations")
	sea_site = main.get_node_or_null("World/SeaStructures/floating_shop")
	sea_provider = main.get_node_or_null("World/SeaStructures/floating_shop/Objects/NpcStations")
	garden_site = main.get_node_or_null("World/SeaStructures/neon_garden_quarter")
	garden_provider = main.get_node_or_null("World/SeaStructures/neon_garden_quarter/NpcStations")
	left_roof_provider = main.get_node_or_null("World/SeaStructures/neon_garden_quarter/RoofNpcStations")
	if not check(harbor != null and roof_provider != null and sea_site != null and sea_provider != null,
		"正式 main 包含天台与浮店站点"): return false
	if not check(garden_site != null and garden_provider != null and left_roof_provider != null,
		"正式 main 包含菜园桥与独立左楼顶 provider"): return false
	authored_garden_transform = garden_site.transform
	authored_roof_transform = harbor.transform
	authored_provider_transform = roof_provider.transform
	authored_sea_transform = sea_site.transform
	# 入树前关闭，不能等 _ready、自动加载或第一帧过去后才关闭。
	main._autosave_on = false
	main._save_path = "user://npc-tests/automatic-disabled.json"
	root.add_child(main)
	current_scene = main
	economy = root.get_node("Economy")
	state = root.get_node("GameState")
	zones = root.get_node("Zones")
	economy.ticking = false
	main.world_clock.paused = true
	profile_before = main.avatar_profile.to_dict().duplicate(true)
	world = main.npc_world_presenter
	if not check(world != null, "真实 main 装配 NPC presenter"): return false
	provider = world._ports.residence()
	if not check(provider != null and provider == main.get_node_or_null("NpcAnchorHub"), "真实 main 注入聚合 NpcAnchorHub"): return false
	check(main._zone_nodes.get("sea_supply") == sea_site and sea_site.zone_id == "sea_supply", "sea_supply 指向作者 floating_shop，天台仍独立注册")
	check(main.get_node_or_null("World/SeaStructures/resident_harbor") == null
		and not main._zone_nodes.has("resident_harbor") and zones.get_zone("resident_harbor").is_empty()
		and zones.landing("resident_harbor", "main").is_empty(), "无 resident_harbor 实例、zone 定义或泊位绑定")
	main.interactor.completed.connect(func(spot, result): completions.append({"spot": spot, "result": result.duplicate(true)}))
	main.boat.arrived.connect(func(zone, landing): arrivals.append([zone, landing]))
	main.actor_controller.state_changed.connect(func(_previous, next): actor_states.append(next))
	await frames(8)
	check(not main._autosave_on and not main._title_active and not main.avatar_session.active()
		and not main.hud.narrative_active(), "skip-title 不触发创建角色/开场独白且自动存档关闭")
	check(equivalent(main.avatar_profile.to_dict(), profile_before), "启动不偷偷完成或替换玩家 profile")
	if not check(main._zone_nodes.get("rooftop_ranch") == harbor and harbor.zone_id == "rooftop_ranch", "正式 zone 注册指向现有天台实例"): return false
	var actual: Dictionary = harbor.landing_point("main").data()
	check(zones.landing("rooftop_ranch", "main") == actual, "Zones 泊位数据来自真实天台 TSCN，不用 JSON 旧坐标")
	check(world.service == main.npc_service and world.actors.size() == 7, "七人由正式唯一 NpcService 装配")
	check_rooftop_anchors()
	return true

func check_rooftop_anchors() -> void:
	check(harbor.transform.is_equal_approx(authored_roof_transform)
		and roof_provider.transform.is_equal_approx(authored_provider_transform)
		and sea_site.transform.is_equal_approx(authored_sea_transform), "两个站点根及天台 NpcStations 保持 main 手动 transform")
	var anchors: Dictionary = roof_provider.anchor_snapshot()
	var area = harbor.get_node("WalkAreas/Walk_rooftop_ranch_access")
	var markers: Array = roof_provider.find_children("*", "Marker3D", true, false)
	check(markers.size() == 25, "天台五站台保留25个作者 Marker")
	check(anchors.size() == 25 and roof_provider.get_child_count() == 5, "天台25锚点全部有效")
	for site_provider in [garden_provider, left_roof_provider]:
		var site_anchors: Dictionary = site_provider.anchor_snapshot()
		var deck = garden_site.get_node(site_provider.walk_path)
		check(site_anchors.size() == 5, "独立派生面5锚点有效 " + str(site_provider.name))
		for point_marker: Marker3D in site_provider.find_children("*", "Marker3D", true, false):
			var station = point_marker.get_parent()
			var kind := str(point_marker.name).to_lower()
			var anchor_id := str(station.name) if kind == "home" else str(station.name) + "_" + kind
			if not check(site_anchors.has(anchor_id), "作者 Marker 可解析 " + anchor_id): continue
			var anchor: Dictionary = site_anchors[anchor_id]
			check(point_marker.global_position.distance_to(anchor.position) <= 0.05,
				"锚点无 height mismatch " + anchor_id)
			check(anchor.support_validated and anchor.ground == deck
				and deck.contains_position(anchor.position, 0.05), "锚点支撑于所属实际派生面 " + anchor_id)
	check(sea_provider.anchor_snapshot().size() == 5, "浮店5锚点有效")
	check(provider.anchor_snapshot().size() == 40, "天台25 + 浮店5 + 菜园桥5 + 左楼顶5 聚合40锚点")
	for point_marker: Marker3D in markers:
		var station = point_marker.get_parent()
		var kind := str(point_marker.name).to_lower()
		var anchor_id := str(station.name) if kind == "home" else str(station.name) + "_" + kind
		if kind == "work": anchor_id = str(station.get_meta("work_anchor_id", anchor_id))
		check(anchors.has(anchor_id) and anchors[anchor_id].position.distance_to(point_marker.global_position) < 0.05
			and grass_support(point_marker.global_position), "手摆 Marker 本身位于真实草地且未被运行时吸附替代 " + anchor_id)
	var owners := {}
	for anchor in anchors.values():
		var point: Vector3 = anchor.position
		owners[anchor.npc_id] = true
		check(anchor.zone == "rooftop_ranch" and anchor.zone_id == "rooftop_ranch"
			and anchor.ground == area and anchor.ground_space == harbor.ground_space
			and harbor.area_at(point, 0.05) == area, "锚点复用原天台 ground/ground_space " + anchor.anchor_id)
		check(absf(harbor.to_local(point).y - harbor.ROOF_Y) < 0.05
			and grass_support(point), "锚点位于真实天台草皮而非消防梯或水面 " + anchor.anchor_id)
		check(roof_provider.resolve_anchor(anchor.anchor_id) == anchor, "稳定ID解析回同一天台锚点 " + anchor.anchor_id)
	for id in Catalog.ids():
		check(Catalog.get_npc(id).display_name == NAMES[id] and world.actor(id).display_name == NAMES[id], "正式目录与世界姓名一致 " + id)
		if id == "npc_mu_he":
			# 她的天台站台仍在场景里（用户没删），但当前日程已指向霓虹花园，
			# 所以断言的是「不在天台日程里」，不是「场景里没有她的 Marker」。
			var muhe_routes: Array = []
			for rule in Catalog.get_npc(id).get("schedule", []):
				muhe_routes.append(str(rule.anchor))
			check(not muhe_routes.has("anchor_planter") and muhe_routes.has("residence_garden_bridge_work"),
				"豆豆的日程锚点已指向霓虹花园菜园桥 " + id)
			continue
		check(owners.has(id) == (id != "npc_bao_he" and id != "npc_luo_yan"),
			"天台仅四位当前居民及豆豆保留站台，船老大与阿店无旧站台 " + id)
	for anchor in sea_provider.anchor_snapshot().values():
		check(anchor.npc_id == "npc_bao_he" and anchor.zone_id == "sea_supply"
			and anchor.ground_space == sea_site.ground_space and anchor.support_frame == sea_site.get_node("Objects")
			and anchor.position.distance_to(anchor.ground.surface_point(anchor.position)) < 0.003,
			"阿店锚点复用浮店支撑 " + anchor.anchor_id)
	check(provider.home_labels().size() == 8, "七人标签来自聚合 provider（天台5+浮店1+菜园桥1+左楼顶1，含豆豆保留站台）")

func grass_support(point: Vector3) -> bool:
	var grass = harbor.get_node("Models/ORF3_中央草皮基底")
	for mesh: MeshInstance3D in grass.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var inverse := mesh.global_transform.affine_inverse()
		var start: Vector3 = inverse * (point + Vector3.UP * 0.10)
		var end: Vector3 = inverse * (point - Vector3.UP * 0.10)
		var faces := mesh.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null: return true
	return false

func landing_fixture(zone_id: String) -> bool:
	var landing: Dictionary = main._zone_nodes[zone_id].landing_point("main").data()
	var game := {"zone": zone_id, "landing": "main", "mode": 0, "far_sea": state.far_sea_unlocked,
		"boat": [landing.boatPark[0], landing.boatPark[1], landing.boatPark[2], landing.boatYaw], "player": landing.landStand.duplicate()}
	var reason: String = main.validate_world_state(game)
	if not check(reason == "", "landStand 夹具通过正式世界验证 " + zone_id + "：" + reason):
		report_landing(zone_id)
		return false
	main.restore_world_state(game)
	return check(state.current_zone == zone_id and main.actor_controller.mode() == 0, "通过主场景恢复 landStand " + zone_id)

func report_landing(zone_id: String) -> void:
	var zone = main._zone_nodes[zone_id]
	var landing: Dictionary = zone.landing_point("main").data()
	var park := Vector2(float(landing.boatPark[0]), float(landing.boatPark[2]))
	var stand := Vector3(float(landing.landStand[0]), float(landing.landStand[1]), float(landing.landStand[2]))
	var blockers: Array = []
	for shape: Dictionary in main._water_shapes() + main.building_world.water_shapes(main.building.query()):
		var offset := park - Vector2(float(shape.x), float(shape.z))
		var hx := float(shape.hx) + 0.9
		var blocked := offset.length() <= hx if bool(shape.get("round", false)) else absf(offset.x) <= hx and absf(offset.y) <= float(shape.get("hz", shape.hx)) + 0.9
		if blocked: blockers.append(shape)
	print("[npc-landing-probe] zone=", zone_id, " landing=", landing,
		" stand_area=", zone.area_at(stand, 0.5), " park_open=", main._is_open_water(park.x, park.y),
		" start_open=", main._is_open_water(main.boat.position.x, main.boat.position.z), " blockers=", blockers)

func aim(point: Vector3, distance := 22.0) -> void:
	main.cam.follow_enabled = false
	main.cam.pose_lock = true
	main.cam.target = point + Vector3.UP
	main.cam.dir = Vector3(0.22, 0.85, 1.0).normalized()
	main.cam.zoom_max = maxf(main.cam.zoom_max, distance)
	main.cam.distance = distance
	main.cam.apply_pose()

func walk_to(point: Vector3, label: String) -> bool:
	section("步行 " + label)
	var site = main._zone_nodes.get(state.current_zone)
	if not check(site != null, label + " 当前区块存在"): return false
	var area = site.area_at(point, 0.5)
	if not check(area != null, label + " 目标有实际支撑面"): return false
	if not check(not site.ground_space.route(main.player.global_position, point).is_empty(), label + " 有正式路线"): return false
	var start: Vector3 = main.player.global_position
	if not check(main._start_walk(area, point), label + " 正式 ActorController 接受移动"): return false
	var supported := true
	var max_step := 0.0
	var previous: Vector3 = start
	var deadline := Time.get_ticks_msec() + 40000
	while main.actor_controller.walking() and Time.get_ticks_msec() < deadline:
		await frames(1)
		var now: Vector3 = main.player.global_position
		supported = supported and site.area_at(now, 0.55) != null
		max_step = maxf(max_step, now.distance_to(previous))
		previous = now
	check(supported and max_step < 0.8, label + " 全程物理支撑且无瞬移")
	return check(main.player.global_position.distance_to(point) < 0.25 and not main.actor_controller.walking(), label + " 实际到位")

func npc_press(action: String, id := "") -> bool:
	if action in ["talk", "profile", "topics", "events", "gifts", "requests", "relationships"]:
		var visible := false
		for candidate: Button in world.panel._buttons:
			if candidate.get_meta("npc_action", "") == action: visible = true
		if not visible:
			if not await finish_dialogue(): return false
			if not await npc_press("chat"): return false
			await process_frame
	for button: Button in world.panel._buttons:
		if button.get_meta("npc_action", "") == action and (id == "" or button.get_meta("npc_payload", {}).get("id", "") == id):
			if not check(not button.disabled, "NPC 按钮可用 " + action + " " + id): return false
			button.pressed.emit()
			await process_frame
			return true
	return check(false, "缺少实际 NPC 按钮 " + action + " " + id)

func career_press(command: String, event_id := "") -> bool:
	for button: Button in main.npc_career_panel._buttons:
		if button.get_meta("career_command", "") == command and (event_id == "" or button.get_meta("career_event", {}).get("id", "") == event_id):
			if not check(not button.disabled, "职业按钮可用 " + command): return false
			button.pressed.emit()
			await process_frame
			return true
	return check(false, "缺少实际职业按钮 " + command + " " + event_id)

func open_npc(id: String) -> bool:
	await close_modals()
	return check(world.open_npc(id).get("ok", false), "正式 presenter 打开 " + id)

func close_modals() -> void:
	world.cancel_session()
	main.shop_panel.close()
	main.npc_career_panel.close()
	main.hud.world_actions.close(true)
	if main.hud.is_panel_open(): main.hud.toggle_panel()
	if main.building_controller.active: main.building_controller.close()
	await frames(2)

func finish_dialogue() -> bool:
	for step in 120:
		var dialogue: Dictionary = main.npc_service.dialogue_state()
		if not dialogue.active: return true
		if not dialogue.typing and dialogue.page.has("choices"):
			if not await npc_press("choice", dialogue.page.choices[0].id): return false
		else:
			if not await npc_press("advance"): return false
	return check(false, "对白必须有限步完成，不能静默跳过")

func open_career(id: String, action: String) -> bool:
	if not await open_npc(id): return false
	if not await finish_dialogue(): return false
	if not await npc_press("function"): return false
	var snapshot: Dictionary = main.npc_career_panel.panel_snapshot()
	return check(snapshot.open and snapshot.npc_id == id and snapshot.action_id == action
		and not world.is_modal() and main.hud._external_modal, "Main 路由至实际职业面板 " + action)

func buy(id: String, product_id: String, amount := 1) -> bool:
	if not await open_npc(id): return false
	if not await finish_dialogue(): return false
	if not await npc_press("vendor"): return false
	var shop_id: String = Catalog.get_npc(id).shop_id
	var panel = main.shop_panel
	var shop: Dictionary = main.shop_service.shop_snapshot(shop_id)
	if not check(panel.is_open() and panel._shop_id == shop_id and panel._title.text == shop.display_name
		and panel._title.is_visible_in_tree() and not main.hud.is_panel_open(), "flower/general 标题正确且不打开旧 HUD " + shop_id): return false
	check(panel._title.text == ("小花花店" if shop_id == "shop_flower" else "阿店海上商店"), "商店标题使用新姓名 " + shop_id)
	check(panel._inventory == economy.inventory and main.shop_service.inventory == economy.inventory, "商店使用真实同一个 Inventory")
	var found := false
	for button: Button in panel._product_buttons:
		if button.get_meta("product_id") == product_id:
			button.pressed.emit()
			found = true
	if not check(found, "正式商品存在 " + product_id): return false
	for i in amount - 1: panel._plus.pressed.emit()
	var quote: Dictionary = main.shop_service.quote(shop_id, product_id, amount)
	if not check(quote.ok and not panel._buy.disabled, "真实报价允许购买 " + product_id): return false
	var npc_before: Dictionary = main.npc_service.to_dict()
	var expected: Dictionary = economy.inventory.all()
	expected.coins = int(expected.get("coins", 0)) - int(quote.total_cost)
	expected[quote.item] = int(expected.get(quote.item, 0)) + amount
	panel._buy.pressed.emit()
	await process_frame
	check(economy.inventory.all() == expected, "购买精确扣瓶盖并给物品 " + product_id)
	check(main.npc_service.to_dict() == npc_before and panel._feedback.text.contains("已购入"), "购买不由 NPC 再扣款或加好感")
	await close_modals()
	return true

func run() -> void:
	if not await boot():
		await finish(); return
	section("travel")
	await travel()
	section("homes-and-interactions")
	await homes_and_interactions()
	section("transactions-and-stories")
	await transactions_and_stories()
	section("careers")
	await careers()
	for required in ["travel", "three-site-stations", "six-click-e", "sea-supply-travel", "transactions-stories", "careers"]:
		check(required in completed_sections, "必测闭环完成 " + required)
	await finish()

func travel() -> void:
	if not landing_fixture("zone1"): return
	await frames(3)
	var initial: Vector3 = main.boat.global_position
	var count := arrivals.size()
	# 发真实 HUD 意图，经 Main→航路→Boat.arrived→靠泊，不调用 arrived 或改终点位置。
	main.hud.destination_pressed.emit("rooftop_ranch")
	if not await until(func(): return main.boat.starts_sailing(), 12.0, "主场景离岸并实际开始天台航行"):
		report_landing("rooftop_ranch")
		return
	check(main.actor_controller.mode() == 2, "真实航行态")
	if not await until(func(): return arrivals.size() > count and not main.boat.starts_sailing(), 120.0, "船实际抵达天台消防梯泊位"): return
	check(arrivals.back() == ["rooftop_ranch", "main"] and main.boat.global_position.distance_to(initial) > 5.0, "真实 arrived 来自完整航程")
	check(state.current_zone == "rooftop_ranch" and main._landing_is_docked(), "到站同步 zone/landing 且船已靠妥")
	await key(KEY_E)
	if not await until(func(): return main.actor_controller.mode() == 0 and not main.actor_controller.walking(), 8.0, "真实 E 从消防梯泊位上岸"): return
	var stand: Vector3 = harbor.landing_point("main").stand_position()
	check(main.player.global_position.distance_to(stand) < 0.3
		and harbor.area_at(main.player.global_position, 0.5) != null
		and harbor.to_local(main.player.global_position).y < harbor.ROOF_Y - 2.0, "E 上岸落在原消防梯下平台，不直接落到草地")
	var roof: Vector3 = harbor.to_global(Vector3(0, harbor.ROOF_Y, 6))
	var route: Array = harbor.ground_space.route(main.player.global_position, roof)
	check(route.size() >= 4, "原 Walk_rooftop_ranch_access 路线经过消防梯和楼顶入口")
	if not await walk_to(roof, "从原消防梯下平台真实爬至天台草地"): return
	check(grass_support(main.player.global_position), "爬楼后角色踩在真实草皮")
	completed_sections.append("travel")

func homes_and_interactions() -> void:
	if state.current_zone != "rooftop_ranch" or main.actor_controller.mode() != 0 or not "travel" in completed_sections:
		check(false, "旅行失败不能用天台瞬移掩盖"); return
	var anchors: Dictionary = provider.anchor_snapshot()
	var hub: Vector3 = harbor.to_global(Vector3(0, harbor.ROOF_Y, 11.5))
	check(roof_provider.get_child_count() == 5 and anchors.size() == 40, "天台五站台与浮店、菜园桥、左楼顶聚合40锚点")
	# 日钟冻结后等待真实 NPC 走完，不改 actor 坐标/路线。
	if not await until(func():
		for row in world.world_snapshot().residents.values():
			if row.remaining_waypoints > 0: return false
		return true, 40.0, "七 NPC 真实日程落位"): return
	check_current_schedules()
	var homes := 0
	var interactions := 0
	var roster: Array = main.npc_service.roster()
	# 四位天台居民先验；随后保留真实浮店航程，最后在左楼顶验证船老大。
	var visit_order := ["npc_ji_chen", "npc_nan_zhi", "npc_bai_shi", "npc_hua_yi", "npc_mu_he", "npc_bao_he", "npc_luo_yan"]
	roster.sort_custom(func(a, b): return visit_order.find(a.id) < visit_order.find(b.id))
	for index in roster.size():
		var npc: Dictionary = roster[index]
		section("走访 " + str(npc.id))
		# 豆豆 2026-11-08 起在霓虹花园菜园桥种菜，不在这条天台走访链上。
		# 她的站位/点击由 test_garden_npc.gd 在真实主场景里单独验。
		if npc.id == "npc_mu_he":
			var garden_body = world.actor("npc_mu_he")
			check(is_instance_valid(garden_body) and garden_body.visible
				and not world.world_snapshot().residents["npc_mu_he"].fallback,
				"豆豆在霓虹花园菜园桥落位且无静默回退")
			continue
		if npc.id == "npc_bao_he":
			if not await sail_to_supply(): continue
			anchors = provider.anchor_snapshot()
			hub = sea_site.landing_point("main").stand_position()
		if npc.id == "npc_luo_yan":
			if not landing_fixture("neon_garden_quarter"): continue
			hub = garden_site.landing_point("main").stand_position()
		var row := {"id": str(npc.residence_id), "npc_id": str(npc.id)}
		if not check(anchors.has(npc.home_anchor), "聚合 provider 提供 home Marker " + row.id): continue
		var home: Dictionary = anchors[npc.home_anchor]
		var site = main._zone_nodes.get(home.zone_id)
		if not check(site != null and state.current_zone == home.zone_id, "玩家与 home 同属真实区块 " + row.id): continue
		if not await walk_to(hub, row.id + " 回到所属场地公共路径"): continue
		if not check(not site.ground_space.route(hub, home.position).is_empty(), "所属公共路径连通 home Marker " + row.id): continue
		if not await walk_to(home.position, "实际走至 home Marker " + row.id): continue
		homes += 1
		var body = world.actor(row.npc_id)
		check(npc_supported(row.npc_id) and not world.world_snapshot().residents[row.npc_id].fallback,
			"居民真实日程落位所属站点且无静默回退 " + row.npc_id)
		# 从真实站位退至三米外再点击，保留实际 approach 移动，绝不挪动 NPC。
		var approach: Vector3 = body.global_position + (hub - body.global_position).normalized() * 3.0
		if not await walk_to(approach, "草地交谈接近起点 " + row.id): continue
		var spot = body.get_node("NpcInteractable")
		check(body.is_visible_in_tree() and body.grounded_motion_enabled and spot.can_interact()
			and spot.is_in_group("interactable"), "正式 actor 注册可交谈 " + row.npc_id)
		aim(body.global_position)
		await frames(3)
		if not await until(func(): return main.hover.reach_reason(spot) == "", 1.0,
			"切换场地后真实悬停可达性刷新 " + row.npc_id): continue
		# NPC 交互节点是无子网格的逻辑点，正式 HoverCard 将热区抬到上半身0.75米。
		# 脚底投影在近景下已经超出30像素热区，不能以根坐标冒充可点击位置。
		var point: Vector2 = main.cam.unproject_position(spot.focus_position() + Vector3.UP * 0.75)
		var hit: Dictionary = main.hover._pick(point)
		print("[npc-click-probe] npc=", row.npc_id, " camera=", main.cam.global_position,
			" viewport=", root.get_visible_rect(), " click=", point, " actual_hit=", hit,
			" previous_hover=", main.hover.target, " previous_focus=", main.interactor.target,
			" near_focus=", main.hover.keyboard_focus, " can_interact=", spot.can_interact(),
			" reach=", main._compute_reach_reason(spot))
		if not check(root.get_visible_rect().has_point(point) and hit.get("type") == "spot"
			and hit.get("node") == spot, "真实点击命中 NPC 而非家具 " + row.npc_id): continue
		var before := completions.size()
		actor_states.clear()
		var approach_start: Vector3 = main.player.global_position
		await click(point)
		if not check(not main.hud.world_actions.active, "点击NPC直接接近，不出现物体菜单"): continue
		if not await until(func(): return world.is_modal(), 35.0, "点击交谈经实际 approach/Interactor 打开 " + row.npc_id): continue
		check(completions.size() == before + 1 and completions.back().spot == spot
			and completions.back().result.get("npc_id") == row.npc_id, "点击完整执行真实交互链 " + row.npc_id)
		check("approaching" in actor_states and "interacting" in actor_states
			and main.player.global_position.distance_to(approach_start) > 0.15, "点击确实移动且经过 approach/interacting，而非直接打开面板 " + row.npc_id)
		check(world.panel.panel_snapshot().npc_id == row.npc_id and not main.shop_panel.is_open(), "商店居民也先打开 NPC 而非货架")
		if not await finish_dialogue(): continue
		check(main.npc_service.npc_snapshot(row.npc_id).runtime.last_talk_day == main.world_clock.day, "七人实际交谈结算 " + row.npc_id)
		await close_modals()
		var delta: Vector3 = spot.focus_position() - main.player.global_position
		main.player.rotation.y = atan2(delta.x, delta.z)
		await frames(12)
		for attempt in 24:
			if main.interactor.target == spot: break
			await key(KEY_Q)
		if not check(main.interactor.target == spot, "Q 可选正式 NPC，E 不指向其它物件 " + row.npc_id): continue
		before = completions.size()
		send(KEY_E, true, true)
		var opened := await until(func(): return world.is_modal(), 5.0, "按住 E 真实打开 " + row.npc_id)
		send(KEY_E, false, true)
		if not opened: continue
		check(completions.size() == before + 1 and completions.back().spot == spot, "E 经 Interactor 恰执行一次 " + row.npc_id)
		check(world.panel.panel_snapshot().npc_id == row.npc_id
			and world.panel._title.text.begins_with(NAMES[row.npc_id]), "E 保持正确 NPC 所有者与新姓名")
		await close_modals()
		if row.npc_id == "npc_bao_he": await verify_heave()
		interactions += 1
	if check(homes == 6, "四位天台居民+阿店浮店+船老大左楼顶 home 真实可达（豆豆无玩家通路）"): completed_sections.append("three-site-stations")
	if check(interactions == 6, "六位可达居民完成点击/approach/对白/E（豆豆在花园另验）"): completed_sections.append("six-click-e")

func check_current_schedules() -> void:
	var clock: Dictionary = main._npc_world_query()
	var anchors: Dictionary = provider.anchor_snapshot()
	for id in Catalog.ids():
		var npc: Dictionary = Catalog.get_npc(id)
		var available: Dictionary = anchors.duplicate()
		for rule in npc.schedule: available.erase(str(rule.anchor))
		for rule in npc.schedule:
			var canonical: String = provider.canonical_anchor_for_npc(str(rule.anchor), npc)
			if anchors.has(canonical): available[str(rule.anchor)] = anchors[canonical]
		var expected: Dictionary = main.npc_service.schedule_at(id, clock, available)
		if not check(expected.get("ok", false), "当前时钟/天气可解析日程 " + id): continue
		var route: Dictionary = world._routes.get(id, {})
		check(not route.get("fallback", true), "当前日程不 fallback " + id)
		check(route.get("requested_anchor") == expected.get("requested_anchor")
			and route.get("action") == expected.get("action"), "实际意图匹配当前日程而非旧场地假设 " + id)
		var target: Dictionary = route.get("target", {})
		if not check(not target.is_empty(), "当前日程有真实目标 " + id): continue
		var canonical: String = provider.canonical_anchor_for_npc(str(expected.anchor_id), npc)
		check(target.get("anchor_id") == canonical and anchors.has(canonical), "当前日程锚点来自实际聚合 provider " + id)

func npc_site_position(id: String) -> Vector3:
	var body = world.actor(id)
	if id == "npc_bao_he": return sea_site.get_node("Objects").to_local(body.global_position)
	if id in ["npc_mu_he", "npc_luo_yan"]:
		# 菜园桥与左楼顶共用作者根，但各自使用独立派生面。
		var garden: Node3D = main.get_node("World/SeaStructures/neon_garden_quarter")
		return garden.to_local(body.global_position)
	return harbor.to_local(body.global_position)

func npc_supported(id: String) -> bool:
	var body = world.actor(id)
	if id == "npc_mu_he":
		# 菜园桥的支撑来自从模型派生的 DerivedWalkArea，不是天台草皮。
		var garden: Node3D = main.get_node("World/SeaStructures/neon_garden_quarter")
		var deck: Node3D = garden.get_node("WalkAreas/WalkGardenDeck")
		return deck.contains_position(body.global_position, 0.6)
	if id == "npc_luo_yan":
		var deck = garden_site.get_node("WalkAreas/WalkLeftRoof")
		return deck.contains_position(body.global_position, 0.05)
	if id != "npc_bao_he": return grass_support(body.global_position)
	var area = sea_site.area_at(body.global_position, 0.05)
	return area != null and body.global_position.distance_to(area.surface_point(body.global_position)) < 0.01

func sail_to_supply() -> bool:
	await close_modals()
	if not await walk_to(harbor.landing_point("main").stand_position(), "原消防梯实走回船边"): return false
	var count := arrivals.size()
	var initial: Vector3 = main.boat.global_position
	main.hud.destination_pressed.emit("sea_supply")
	if not await until(func(): return main.boat.starts_sailing(), 15.0, "HUD sea_supply 实际上船离岸"): return false
	check(main.actor_controller.mode() == 2, "浮店航程进入真实航行态")
	if not await until(func(): return arrivals.size() > count and not main.boat.starts_sailing(), 120.0, "船真实抵达东南浮店"): return false
	check(arrivals.back() == ["sea_supply", "main"] and main.boat.global_position.distance_to(initial) > 5.0
		and state.current_zone == "sea_supply" and main._landing_is_docked(), "浮店到站来自真实航程与靠泊")
	await key(KEY_E)
	if not await until(func(): return main.actor_controller.mode() == 0 and not main.actor_controller.walking(), 8.0, "真实 E 下船进入浮店甲板"): return false
	check(sea_site.area_at(main.player.global_position, 0.5) != null, "玩家有浮店实际甲板支撑")
	completed_sections.append("sea-supply-travel")
	return true

func verify_heave() -> void:
	var frame: Node3D = sea_site.get_node("Objects")
	var body = world.actor("npc_bao_he")
	var local: Vector3 = frame.to_local(body.global_position)
	var roof_positions := {}
	for id in Catalog.ids():
		if id != "npc_bao_he": roof_positions[id] = world.actor(id).global_position
	var low := INF
	var high := -INF
	var max_error := 0.0
	var hotspot_error := 0.0
	var supported := true
	for sample in 480:
		await frames(1)
		low = minf(low, frame.position.y)
		high = maxf(high, frame.position.y)
		max_error = maxf(max_error, frame.to_global(local).distance_to(body.global_position))
		hotspot_error = maxf(hotspot_error, body.get_node("NpcInteractable").global_position.distance_to(body.global_position))
		supported = supported and npc_supported("npc_bao_he")
	check(sea_site.motion_enabled and is_equal_approx(sea_site.heave_amplitude + sea_site.secondary_amplitude, 0.145)
		and high - low > 0.15, "原0.145m升沉保持开启且实际观测到运动")
	check(max_error < 0.01 and hotspot_error < 0.003 and supported, "阿店角色与热点连续随支撑且脚不穿甲板")
	for id in roof_positions: check(world.actor(id).global_position.distance_to(roof_positions[id]) < 0.003, "浮店升沉不改变六人原站位 " + id)
	print("[npc-heave] range=", high - low, " actor_error=", max_error, " hotspot_error=", hotspot_error)

func transactions_and_stories() -> void:
	await close_modals()
	check(economy.inventory.add_all({"coins": 1000, "wood": 30, "parts": 20, "rope": 20, "seed": 10, "glass": 10, "shell": 10}), "真实 Inventory 测试资源夹具")
	var bought := await buy("npc_hua_yi", "flower_bundle")
	bought = await buy("npc_bao_he", "general_soil", 2) and bought
	if not await open_npc("npc_hua_yi"): return
	var count: int = economy.inventory.count("flower_bundle")
	var affinity: int = main.npc_service.npc_snapshot("npc_hua_yi").runtime.affinity
	var other: Dictionary = main.npc_service.npc_snapshot("npc_bao_he").runtime
	if not await npc_press("gifts"): return
	if not await npc_press("gift", "flower_bundle"): return
	check(economy.inventory.count("flower_bundle") == count, "礼物确认前不扣库存")
	if not await npc_press("confirm"): return
	check(economy.inventory.count("flower_bundle") == count - 1
		and main.npc_service.npc_snapshot("npc_hua_yi").runtime.affinity == affinity + 40
		and main.npc_service.npc_snapshot("npc_bao_he").runtime == other, "礼物仅由 Inventory 扣一次、好感给花序且不串经营者")
	await close_modals()
	var fixture: Dictionary = main.npc_service.to_dict()
	for id in Catalog.ids():
		fixture.graph.met[id] = true
		fixture.graph.affinity[id] = 500
	if not check(main.npc_service.from_dict(fixture).ok, "仅用 strict durable 快照设置剧情前置"): return
	var finished_events := 0
	var delivered := 0
	for event in Catalog.events():
		if event.kind != "personal" or event.conditions.has("events"): continue
		var id: String = event.npc_ids[0]
		if not await open_npc(id): continue
		var inventory_before: Dictionary = economy.inventory.to_dict()
		if not await npc_press("events"): continue
		if not await npc_press("event", event.id): continue
		if not await finish_dialogue(): continue
		check(economy.inventory.to_dict() == inventory_before, "剧情记录不冒充经济结算 " + event.id)
		var durable: Dictionary = main.npc_service.to_dict()
		check(durable.seen_events.has(event.id) and not durable.seen_events[event.id].choices.is_empty(), "真实剧情选择持久提交 " + event.id)
		if not await npc_press("back"): continue
		if not check(world.panel.panel_snapshot().section == "home", "剧情列表经实际返回按钮回主页 " + event.id): continue
		for request_id in event.effects.requests:
			var request: Dictionary = Catalog.get_request(request_id)
			var graph_before: Dictionary = main.npc_service.to_dict().graph
			var expected: Dictionary = economy.inventory.all()
			for item in request.costs: expected[item] = int(expected.get(item, 0)) - int(request.costs[item])
			if not await npc_press("requests"): continue
			if not await npc_press("request", request_id): continue
			if not await npc_press("confirm"): continue
			check(economy.inventory.all() == expected, "请求精确扣真实 Inventory " + request_id)
			var after: Dictionary = main.npc_service.to_dict()
			check(after.request_states[request_id].status == "completed", "请求由 NPC owner 完成 " + request_id)
			for npc_id in Catalog.ids():
				check(after.graph.affinity[npc_id] == graph_before.affinity[npc_id] + (40 if npc_id == request.npc_id else 0), "请求好感只给正确所有者 " + request_id + "/" + npc_id)
			delivered += 1
		finished_events += 1
	if check(bought and finished_events == 7 and delivered == 7, "两商店购买、礼物和七人剧情请求均执行"): completed_sections.append("transactions-stories")
	await close_modals()

func build_support_platform() -> String:
	# 平台与固定底板真实共边，培养土以其稳定ID为support；不放宽生产承载校验。
	var extent: Vector2 = BuildingCatalog.RECIPES.platform_5x5.footprint
	var center := Vector2(BuildingCatalog.BASE.end.x + extent.x * 0.5, 0.0)
	var request := {"kind": "platform_5x5", "px": center.x, "pz": center.y, "py": 0.0, "turn": 0, "support": ""}
	var result: Dictionary = main.building.begin(request)
	if not check(result.get("ok", false), "正式承载平台开工：" + str(result)): return ""
	var id := str(result.id)
	if not await until(func(): return not main.building.row(id).is_empty() and float(main.building.row(id).left) <= 0.0, 15.0, "正式承载平台实际完工"): return ""
	if not check(main.building_world.node_for(id) != null, "承载平台已有真实世界投影"): return ""
	return id

func careers() -> void:
	if not await open_career("npc_luo_yan", "ship"): return
	var level: int = economy.ship.ship_level
	var expected: Dictionary = economy.inventory.all()
	for item in economy.ship.ship_cost(): expected[item] = int(expected.get(item, 0)) - int(economy.ship.ship_cost()[item])
	if not await career_press("prepare"): return
	if not await career_press("confirm"): return
	check(economy.ship.ship_level == level + 1 and economy.inventory.all() == expected, "船职业实际调用 ShipService 并精确付费")
	if not await open_career("npc_ji_chen", "salvage"): return
	var wood: int = economy.inventory.count("wood")
	var parts: int = economy.inventory.count("parts")
	if not await career_press("prepare"): return
	if not await career_press("confirm"): return
	check(economy.inventory.count("wood") == wood + 3 and economy.inventory.count("parts") == parts + 2
		and economy.salvage.salvage_cooldown_left(Save.now_seconds()) > 0.0, "打捞职业实际奖励和冷却来自 Salvage owner")
	if not await open_career("npc_mu_he", "cultivation"): return
	if not await career_press("shop_general"): return
	check(main.shop_panel.is_open() and main.shop_panel._shop_id == "shop_general", "种植职业买种路由真实商店")
	if not await open_career("npc_mu_he", "cultivation"): return
	if not await career_press("open_plant"): return
	check(main.hud.is_panel_open() and main.hud._tab == "plant", "种植职业打开正式种植页")
	await close_modals()
	# 土壤归建造 owner；种植归 Farm owner，不在 NPC 面板里自造种植算法。
	if not landing_fixture("zone5"): return
	var support_id: String = await build_support_platform()
	if support_id.is_empty(): return
	var soil: int = economy.inventory.count("soil")
	var center: Vector2 = BuildingCatalog.footprint_rect(main.building.row(support_id)).get_center()
	var request := {"kind": "planter_small", "px": center.x, "pz": center.y, "turn": 0, "support": support_id}
	var placed: Dictionary = main.building.begin(request)
	if not check(placed.get("ok", false), "正式建造端口用购得土壤制作培养土：" + str(placed)): return
	check(economy.inventory.count("soil") == soil - int(BuildingCatalog.RECIPES.planter_small.cost.soil), "土壤由 BuildingService 扣除")
	if not await until(func(): return not main.building.row(str(placed.id)).is_empty() and float(main.building.row(str(placed.id)).left) <= 0.0, 12.0, "培养土真实施工完成"): return
	var plot = main.farm_field.find("dynamic/" + str(placed.id))
	if not check(plot != null and plot.farm_model == economy.farm, "真实培养土完成后绑定同一个 Farm"): return
	var seed_id: String = economy.farm.crop_def("lettuce").seed
	check(economy.inventory.add(seed_id, 1).ok, "播种资源夹具")
	var seeds: int = economy.inventory.count(seed_id)
	main._queue_plot_action(plot, "plant", "lettuce")
	if not await until(func(): return economy.farm.crop_of(plot.plot_id) == "lettuce", 20.0, "正式培养土经 approach/Interactor 执行播种"): return
	check(economy.inventory.count(seed_id) == seeds - 1, "实际世界培养土端口播种并扣种，不由 NPC 持有作物")
	if not await open_career("npc_nan_zhi", "building"): return
	if not await career_press("open_building"): return
	check(main.building_controller.active and main.building_controller.service == main.building, "建造职业路由真实 BuildingController")
	if not await open_career("npc_bai_shi", "archive"): return
	if not await career_press("replay_event", "route_1"): return
	print("[npc-archive-owner] event=route_1 expected=npc_luo_yan actual=", world.panel.panel_snapshot().get("npc_id", ""),
		" dialogue=", main.npc_service.dialogue_state())
	check(world.panel.panel_snapshot().npc_id == "npc_luo_yan" and main.npc_service.dialogue_state().replay,
		"档案跨域回看归属原 NPC 而非档案员")
	var before: Dictionary = main.npc_service.to_dict()
	# to_dict 按保存契约取消会话；重开回看再验证不重复结算。
	await close_modals()
	if not await open_career("npc_bai_shi", "archive"): return
	if not await career_press("replay_event", "route_1"): return
	if not await finish_dialogue(): return
	check(main.npc_service.to_dict() == before, "档案实际回看不重发请求或好感")
	completed_sections.append("careers")
	await close_modals()

func finish() -> void:
	section("清理并退出")
	for code in held_keys.keys(): send(int(code), false, true)
	if main != null and is_instance_valid(main):
		if is_instance_valid(harbor) and is_instance_valid(provider):
			check(harbor.transform.is_equal_approx(authored_roof_transform)
				and roof_provider.transform.is_equal_approx(authored_provider_transform)
				and sea_site.transform.is_equal_approx(authored_sea_transform)
			and garden_site.transform.is_equal_approx(authored_garden_transform), "所有操作后天台、浮店、花园根及天台 provider 手动 transform 未被改写")
		check(not main._autosave_on, "结束时仍禁止自动存档")
		check(equivalent(main.avatar_profile.to_dict(), profile_before), "所有 NPC 操作均未改玩家 profile")
		main.queue_free()
		await process_frame
	if not slot_before.is_empty():
		check(file_state(Save.SLOT_PATH) == slot_before.primary and file_state(Save.SLOT_PATH + ".bak") == slot_before.backup, "默认玩家槽位及备份字节未动")
	print("[%s] %d checks, %d failures" % [marker, checks, failures])
	finished = true
	quit(0 if failures == 0 else 1)
