extends SceneTree
## 独立闭环入口，由run_verification的npc-world执行，不依赖Main接线。
const Harbor = preload("res://scenes/residence/resident_harbor.tscn")
const Presenter = preload("res://src/npc/npc_world_presenter.gd")
const Service = preload("res://src/npc/npc_service.gd")
var checks := 0
var failures := 0
var harbor: Node3D
var world
var service
var ports := TestPorts.new()
var fallbacks: Array = []
var actions: Array = []
var vendors: Array = []

class TestPorts extends RefCounted:
	var day := 1
	var hour := 8.0
	var enabled := true
	var stock := {"rope": 30, "seed": 30, "parts": 30, "wood": 30, "glass": 30, "shell": 30, "flower_bundle": 30}
	var exchanges := 0
	func clock() -> Dictionary: return {"day": day, "hour": hour, "weather": "clear"}
	func gate() -> bool: return enabled
	func count(id: String) -> int: return int(stock.get(id, 0))
	func exchange(costs: Dictionary, _gains: Dictionary) -> bool:
		for id in costs:
			if count(id) < int(costs[id]): return false
		for id in costs: stock[id] = count(id) - int(costs[id])
		exchanges += 1
		return true

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-world] ", label)

func _fallback(id: String, requested: String, target: String, reason: String) -> void:
	fallbacks.append([id, requested, target, reason])

func _action(id: String, action: String) -> void: actions.append([id, action])
func _vendor(id: String, shop: String) -> void: vendors.append([id, shop])

func key(code: Key) -> void:
	await process_frame
	var pressed := InputEventKey.new()
	pressed.keycode = code
	pressed.pressed = true
	check(world.handle_input(pressed), "模态消费键盘按下")
	await process_frame
	var released := InputEventKey.new()
	released.keycode = code
	released.pressed = false
	check(world.handle_input(released), "模态消费键盘释放")
	await process_frame

func command(action: String, payload: Dictionary = {}) -> Dictionary:
	return world.panel.session.command(action, payload)

func run() -> void:
	harbor = Harbor.instantiate()
	harbor.position = Vector3(38, 0, -32)
	root.add_child(harbor)
	await process_frame
	await physics_frame
	service = Service.new()
	check(service.configure(ports.clock, ports.exchange, Callable(), ports.count).ok, "配置规则服务端口")
	service.vendor_requested.connect(_vendor)
	world = Presenter.new()
	root.add_child(world)
	world.schedule_fallback.connect(_fallback)
	world.action_requested.connect(_action)
	check(world.configure(service, harbor, ports.clock, ports.gate).ok, "注入正式住所")
	world.set_physics_process(false)
	check(world.actors.size() == 7 and world.get_child_count() == 8, "七角色与独立面板，没有另造住所")
	var anchors: Dictionary = harbor.anchor_snapshot()
	for row in service.roster():
		var body = world.actor(row.id)
		check(body != null and body.grounded_motion_enabled, "沿用CharacterMotor " + row.id)
		check(anchors[row.home_anchor].ground.surface_point(body.global_position).is_finite(), "出生站在正式地面 " + row.id)
		check(body.get_node("NpcInteractable").can_interact(), "居民可交谈 " + row.id)
	check(harbor.has_method("resolve_anchor"), "住所公开resolve_anchor以解释旧日程站点")
	check(harbor.has_method("route"), "住所公开统一route端口")
	await _physical_routes(anchors)
	await _mouse_flow()
	await _ui_loop()
	_pause_and_restore()
	await _fallback_loop()
	var text := FileAccess.get_file_as_string("res://src/npc/npc_world_presenter.gd")
	check(not text.contains("create_tween") and not text.contains("BoxMesh") and not text.contains("anchor_positions"), "没有tween穿墙或第二套住所")
	var session_text := FileAccess.get_file_as_string("res://src/npc/npc_session.gd")
	check(not session_text.contains("preload(\"res://src/shop"), "NPC不预载商店")
	world.cancel_session()
	world.free()
	harbor.free()
	service = null
	print("[npc-world] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _physical_routes(anchors: Dictionary) -> void:
	# 用同一正式住所内work站位验证求路与物理执行；不通过旧alias硬编码目标。
	var id := "npc_luo_yan"
	var row: Dictionary = service.npc_snapshot(id)
	var target := {}
	for entry in anchors.values():
		if entry.residence_id == row.residence_id and entry.kind == "work": target = entry
	var body = world.actor(id)
	var path: Array = target.ground.path_between(body.global_position, target.position)
	check(not path.is_empty(), "正式home到work路径可用")
	var route: Dictionary = world._routes[id]
	route.path = path
	route.target = target
	route.anchor_id = target.anchor_id
	var max_step := 0.0
	var supported := true
	for frame in 1500:
		if route.path.is_empty(): break
		var before: Vector3 = body.global_position
		world._step(id, 1.0 / 60.0)
		max_step = maxf(max_step, Vector2(body.global_position.x-before.x, body.global_position.z-before.z).length())
		supported = supported and target.ground.surface_point(body.global_position).is_finite()
		if frame % 8 == 0: await physics_frame
	check(body.global_position.distance_to(target.position) < 0.12, "2m/s物理走到work而非瞬移")
	check(max_step <= 2.0 / 60.0 + 0.001 and route.distance_walked > 0.1, "每步位移受2m/s限制")
	check(supported and absf(body.global_position.y-target.position.y) < 0.05, "全程有实体地面支撑")
	ports.hour = 22.0
	world.sync_world(ports.clock())
	for npc in service.roster():
		check(world._routes[npc.id].target.get("kind") == "rest", "晚上前往本家rest marker " + npc.id)
	ports.hour = 12.0
	world.sync_world(ports.clock())
	for npc in service.roster():
		var route_row: Dictionary = world._routes[npc.id]
		check(not route_row.fallback, "正常工作日程不得以回家掩盖缺失alias " + npc.id)
		check(route_row.target.zone_id == "resident_harbor", "日程仍在住所港 " + npc.id)

func _mouse_flow() -> void:
	check(world.open_npc("npc_luo_yan").ok, "打开鼠标交互面板")
	await process_frame
	await process_frame
	var button: Button = world.panel._buttons[0]
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.global_position = point
		click.pressed = pressed
		root.push_input(click, true)
		await process_frame
	check(service.dialogue_state().active, "真实鼠标点击交谈按钮")
	world.cancel_session()
	await process_frame

func _ui_loop() -> void:
	var id := "npc_luo_yan"
	check(world.open_npc(id).ok and world.is_modal(), "世界交互打开独立NPC面板")
	check(not world.actor(id).get_node("NpcInteractable").can_interact(), "模态时隐藏世界交互")
	var before: Dictionary = service.to_dict()
	await process_frame
	await key(KEY_ENTER)
	var state: Dictionary = service.dialogue_state()
	check(state.get("active", false) and state.get("typing", false) and world.panel._text.text == state.get("page", {}).get("text", ""), "Enter进入对白，page/text/typing一致")
	await key(KEY_E)
	check(not service.dialogue_state().get("typing", false), "E只补全文字，不偷结算")
	await key(KEY_ESCAPE)
	check(not service.dialogue_state().get("active", false) and service.to_dict() == before, "Esc中止对白不增加亲密或完成记录")
	command("talk")
	var stale_serial: int = service.dialogue_state().session_id
	_finish_dialogue()
	check(service.npc_snapshot(id).runtime.affinity == int(before.graph.affinity[id]) + 16, "终页确认才交谈结算一次")
	command("talk")
	check(not command("advance", {"session_id": stale_serial}).ok, "旧session_id不能推进新对白")
	command("back")
	command("gifts")
	var exchanges := ports.exchanges
	check(command("gift", {"id": "rope"}).ok and not world.panel.panel_snapshot().confirmation.is_empty(), "库存礼物进入二次确认")
	await key(KEY_ESCAPE)
	check(ports.exchanges == exchanges, "取消礼物不扣库存")
	command("gift", {"id": "rope"})
	check(command("confirm").ok and ports.exchanges == exchanges + 1, "确认后礼物原子扣库存")
	check(not command("confirm").ok and ports.exchanges == exchanges + 1, "重复确认不重复送礼")
	var gifts: Dictionary = world.panel.panel_snapshot().gifts
	check(gifts.allowance.normal_remaining == 1, "面板展示本周剩余礼物次数")
	command("events")
	check(world.panel.panel_snapshot().events.size() >= 3, "剧情列表包含可用与锁定原因")
	world.cancel_session()
	var snapshot: Dictionary = service.to_dict()
	for npc in service.roster(): snapshot.graph.met[npc.id] = true
	snapshot.graph.affinity[id] = 500
	check(service.from_dict(snapshot).ok, "合法快照开启剧情测试前置")
	check(world.open_npc(id).ok, "读档后重开居民会话")
	command("events")
	check(command("event", {"id": "route_1"}).ok, "个人剧情可开始")
	_finish_dialogue()
	check(service.list_requests(id).size() == 1, "完成事件开启请求")
	var completed_snapshot: Dictionary = service.to_dict()
	check(command("event", {"id": "route_1"}).ok and service.dialogue_state().replay, "已完成剧情可回看")
	_finish_dialogue()
	check(service.to_dict() == completed_snapshot, "回看不重复结算")
	command("requests")
	exchanges = ports.exchanges
	check(command("request", {"id": "request_route_rope"}).ok, "请求交付二次确认")
	await key(KEY_ESCAPE)
	check(ports.exchanges == exchanges, "请求取消不扣库存")
	command("request", {"id": "request_route_rope"})
	check(command("confirm").ok and ports.exchanges == exchanges + 1, "请求确认后原子交付")
	command("services")
	check(command("function").ok and actions == [[id, "ship"]] and not world.is_modal(), "船职能仅通过外部action端口")
	for pair in [["npc_mu_he", "cultivation"], ["npc_ji_chen", "salvage"], ["npc_nan_zhi", "building"], ["npc_bai_shi", "archive"]]:
		world.open_npc(pair[0])
		command("services")
		command("function")
		check(actions.back() == pair, "外部经营端口 " + pair[1])
	for pair in [["npc_hua_yi", "shop_flower"], ["npc_bao_he", "shop_general"]]:
		var count := vendors.size()
		check(world.open_npc(pair[0]).ok and vendors.size() == count, "商店人物不自动变货架")
		command("talk")
		check(service.dialogue_state().active, "商店人物拥有对白")
		command("back")
		command("services")
		command("vendor")
		check(vendors.back() == pair and not world.is_modal(), "request_vendor交给Main的ShopPanel")

func _finish_dialogue() -> void:
	for step in 100:
		var state: Dictionary = service.dialogue_state()
		if not state.active: return
		var payload := {"session_id": state.session_id}
		if not state.get("typing", false) and state.get("page", {}).has("choices"):
			payload["id"] = state.page.choices[0].id
			check(command("choice", payload).ok, "对白选项可确认")
		else:
			check(command("advance", payload).ok, "对白页可推进")
	check(false, "对白必须终止")

func _pause_and_restore() -> void:
	world.open_npc("npc_luo_yan")
	command("talk")
	var body = world.actor("npc_luo_yan")
	var before: Vector3 = body.global_position
	ports.enabled = false
	world._physics_process(0.02)
	check(not world.is_modal() and not service.dialogue_state().active, "睡眠室内等外部门禁取消会话")
	check(body.global_position == before and not body.get_node("NpcInteractable").can_interact(), "外部门禁停止移动与世界交互")
	ports.enabled = true
	world.sync_world(ports.clock())
	paused = true
	world._physics_process(0.02)
	check(body.global_position == before and not body.get_node("NpcInteractable").can_interact(), "暂停停止移动交互")
	paused = false
	world.refresh_after_restore()
	check(body.global_position == before and not world.is_modal(), "读档刷新不瞬移也不保存world坐标")

func _fallback_loop() -> void:
	var id := "npc_luo_yan"
	var body = world.actor(id)
	var before: Vector3 = body.global_position
	var route: Dictionary = world._routes[id]
	route.target = {"position": Vector3.INF}
	route.path = [before + Vector3.RIGHT]
	var count := fallbacks.size()
	world._step(id, 0.02)
	check(fallbacks.size() == count + 1 and route.fallback, "站点失效发出可观测fallback")
	check(body.global_position == before and not body.visible and route.path.is_empty(), "失效站点不穿水面不瞬移")
	await physics_frame
