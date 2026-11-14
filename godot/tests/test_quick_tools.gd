extends SceneTree
## 仅由 runner 在工程外副本执行；功能版和视觉版共用真实输入及动态计数。
## Main 停止自动推进，QuickTools / WorldActionBubbles 子节点仍正常 process。
const QuickTools = preload("res://src/quick_tools/quick_tools.gd")
const Bubbles = preload("res://src/ui/world_action_bubbles.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const Catalog = preload("res://src/building/building_catalog.gd")
const SIZES := [Vector2i(1280, 800), Vector2i(1600, 1000), Vector2i(1920, 1080)]
var checks := 0
var failures := 0
var main
var menu
var quick
var economy
var real_renderer := false
var original_motion := true
var commands: Array[String] = []
var probe: WorldProbe
var clock_before := {}

class WorldProbe extends Node:
	var armed := false
	var leaked: Array[String] = []
	func _unhandled_input(event: InputEvent) -> void:
		if not armed: return
		if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
			leaked.append("Escape 按下" if event.pressed else "Escape 松开")
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			leaked.append("空白按下" if event.pressed else "空白松开")

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[quick-tools] FAIL ", label)

func send(code: int, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)

func key(code: int) -> void:
	send(code, true)
	await process_frame
	send(code, false)
	await process_frame

func mouse_at(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(1, 0)
	root.push_input(event, true)

func click(point: Vector2) -> void:
	mouse_at(point)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func wait_until(predicate: Callable, label: String, timeout_ms := 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok := bool(predicate.call())
	check(ok, label + "（有界等待）")
	return ok

func entries_are(ids: Array) -> bool:
	if menu.entries.size() != ids.size() or menu.buttons.size() != ids.size(): return false
	for i in ids.size():
		if str(menu.entries[i].id) != str(ids[i]): return false
	return true

func expect_open(context: String) -> bool:
	await key(KEY_ALT)
	var ids := ["build", "demolish"] if context == "land" else ["fish", "dive"]
	var ok: bool = quick.is_open() and menu.active and menu.presentation == "quick" and entries_are(ids)
	check(ok, context + "：真实 Alt 打开且恰好两枚正确动作")
	return ok

func record_command(id: String) -> void:
	# 只旁观入口；命令仍委托正式 Main，不能替它发奖励或切换状态。
	commands.append(id)
	main._execute_quick_tool(id)

func frame_camera(point: Vector3) -> void:
	main.cam.follow_enabled = false
	main.cam.global_position = point + Vector3(0, 18, 23)
	main.cam.look_at(point + Vector3.UP)

func land_pose() -> void:
	main.actor_controller.restore_pose({"mode":0, "player":[Catalog.ORIGIN.x + 2.0, Catalog.ORIGIN.y, Catalog.ORIGIN.z + 11.5]})
	root.get_node("GameState").enter_zone("zone5")
	frame_camera(main.player.global_position)

func boat_pose(point := Vector3(400, 1.12, 400)) -> void:
	main.boat.place_at(point, 0.0)
	main.actor_controller.restore_pose({"mode":1})
	frame_camera(main.player.global_position)

func check_glyphs() -> void:
	var expected := {"build":"quick_build", "demolish":"quick_demolish", "fish":"quick_fish", "dive":"quick_dive"}
	for button in menu.buttons:
		var glyph = button._quick_glyph
		check(is_instance_valid(glyph) and glyph.get_script() == preload("res://src/ui/quick_tool_glyph.gd")
			and button.kind == expected.get(str(button.get_meta("action_id")), "")
			and glyph.kind == button.kind and glyph.is_visible_in_tree() and glyph.size == Vector2(46, 46),
			"真实按钮挂接白色剪影：" + str(button.kind))

func module_cases() -> void:
	# 纯模块夹具不伪造 Main；只验注入边界及回调幂等，再销毁整份夹具。
	var owner := Node.new()
	root.add_child(owner)
	var bubbles = Bubbles.new()
	owner.add_child(bubbles)
	var tools = QuickTools.new()
	owner.add_child(tools)
	tools.menu = bubbles
	var snapshot := {"context":"land", "blocked":false, "anchor":Vector2(600, 400)}
	var calls: Array[String] = []
	tools.context_query = func(): return snapshot
	tools.execute = func(id: String): calls.append(id)
	for invalid in [{"context":"other", "blocked":false, "anchor":Vector2.ZERO},
		{"context":"land", "blocked":true, "anchor":Vector2.ZERO},
		{"context":"land", "blocked":false, "anchor":Vector2.INF},
		{"context":"land", "blocked":false, "anchor":"不是坐标"}]:
		snapshot.assign(invalid)
		check(not tools.toggle() and not bubbles.is_open(), "模块拒绝非法上下文：" + str(invalid))
	tools.context_query = func(): return null
	check(not tools.toggle(), "查询返回非 Dictionary 时安全拒绝")
	tools.context_query = Callable()
	check(not tools.toggle(), "未注入查询时安全拒绝")
	tools.context_query = func(): return snapshot
	snapshot.assign({"context":"land", "blocked":false, "anchor":Vector2(600, 400)})
	check(tools.toggle(), "模块有效快照可打开")
	var command: Callable = bubbles.entries[0].command
	snapshot.context = "boat"
	command.call()
	check(calls.is_empty() and not bubbles.is_open(), "保存的回调执行前重查，land→boat 不执行")
	snapshot.context = "land"
	check(tools.toggle(), "模块可重新打开")
	command = bubbles.entries[0].command
	snapshot.blocked = true
	command.call()
	check(calls.is_empty() and not bubbles.is_open(), "已打开后变 blocked 的旧回调不执行")
	snapshot.blocked = false
	check(tools.toggle(), "模块会话 A 打开")
	var command_a: Callable = bubbles.entries[0].command
	tools.close(true)
	command_a.call()
	check(calls.is_empty() and not tools.is_open() and not bubbles.is_open(),
		"tools.close(true) 后保存的 A 回调不执行")
	check(tools.toggle(), "模块重新打开会话 A，准备同类菜单替换")
	command_a = bubbles.entries[0].command
	# 直接撤菜单而不调用 tools.close，让测试单独约束 toggle() 的新 session token。
	bubbles.close(true)
	check(tools.toggle(), "相同 land 上下文打开新会话 B")
	var generation_b: int = bubbles.generation
	command_a.call()
	check(calls.is_empty() and tools.is_open() and bubbles.active and bubbles.generation == generation_b,
		"同类新会话 token：A 不能执行或关闭 B")
	tools.close(true)
	check(tools.toggle(), "模块菜单收起夹具打开")
	command = bubbles.entries[0].command
	bubbles.close()
	var closing_generation: int = bubbles.generation
	command.call()
	check(bubbles.closing and not bubbles.active and calls.is_empty() and bubbles.generation == closing_generation,
		"bubbles.close() 收起期旧回调不执行，也不打断收起")
	await wait_until(func(): return not bubbles.is_open(), "模块 bubbles 收起完成")
	command.call()
	check(calls.is_empty() and not bubbles.root.visible and not bubbles.is_open(),
		"bubbles.close() 收起后旧回调仍无效")
	check(tools.toggle(), "模块命令防重夹具打开")
	command = bubbles.entries[0].command
	command.call()
	command.call()
	check(calls == ["build"], "同一保存命令重复调用只执行一次")
	owner.free()
	await process_frame

func toggle_and_dismiss_cases() -> void:
	land_pose()
	# 首次打开不能先用 key()/expect_open() 松开 Alt，否则漏掉 open 时的初始键锁。
	send(KEY_ALT, true)
	await process_frame
	check(quick.is_open() and menu.active and menu.presentation == "quick" and entries_are(["build", "demolish"]),
		"首次真实 Alt press 打开 land 菜单，尚未 release")
	if not quick.is_open():
		send(KEY_ALT, false)
		return
	check_glyphs()
	var generation: int = menu.generation
	send(KEY_ALT, true)
	await process_frame
	check(quick.is_open() and menu.active and menu.generation == generation,
		"首次 Alt release 前重复 non-echo press 不关闭或重建菜单")
	send(KEY_ALT, true, true)
	await process_frame
	check(quick.is_open() and menu.active and menu.generation == generation,
		"首次 Alt release 前 echo press 不关闭或重建菜单")
	send(KEY_ALT, false)
	await process_frame
	check(quick.is_open() and menu.active and menu.generation == generation, "首次 Alt release 只解锁，不关闭菜单")
	await key(KEY_ALT)
	await wait_until(func(): return not menu.is_open(), "Alt 收起动画结束")
	check(not menu.is_open(), "第二次真实 Alt 收起菜单")
	send(KEY_ALT, true, true)
	await process_frame
	send(KEY_ALT, false)
	check(not menu.is_open(), "关闭状态 Alt echo 不重新打开")
	if not await expect_open("land"): return
	var point: Vector3 = main.player.global_position
	var anchor: Vector2 = menu.anchor_query.call()
	check(anchor.is_equal_approx(main.cam.unproject_position(point + Vector3.UP * Dimensions.SCALE * 1.55)),
		"锚点来自正式角色头顶相机投影")
	var cluster_before: Vector2 = menu.cluster.position
	main.player.global_position += main.cam.global_basis.x * 1.5
	await process_frame
	await process_frame
	var moved: Vector2 = menu.anchor_query.call()
	check(moved.distance_to(anchor) > 5.0 and menu.cluster.position.distance_to(cluster_before) > 5.0,
		"Main process 停止时子菜单仍每帧跟随移动角色投影")
	var actor_before: Dictionary = main.actor_controller.snapshot().duplicate(true)
	var route_before: Array = main.boat.route.duplicate()
	var count_before := commands.size()
	probe.armed = true
	await key(KEY_ESCAPE)
	await wait_until(func(): return not menu.is_open(), "Esc 收起结束")
	check(probe.leaked.is_empty() and commands.size() == count_before
		and main.actor_controller.snapshot() == actor_before and main.boat.route == route_before
		and not main.hud.is_panel_open(), "Esc 只关菜单，不穿透世界或打开其他界面")
	probe.armed = false
	if not await expect_open("land"): return
	probe.leaked.clear()
	probe.armed = true
	await click(Vector2(40, root.get_visible_rect().size.y * 0.65))
	await wait_until(func(): return not menu.is_open(), "空白点击收起结束")
	check(probe.leaked.is_empty() and commands.size() == count_before and not main._world_press
		and main.actor_controller.snapshot() == actor_before and main.boat.route == route_before,
		"空白点击关闭，不发世界按下、不走路、不改航线或执行动作")
	probe.armed = false
	# 留下 _opened_by_quick 的历史所有权，再由普通世界菜单接管。
	if not await expect_open("land"): return
	menu.open(func(): return Vector2(600, 400), [{"id":"ordinary", "label":"普通世界操作"}], "世界")
	var world_generation: int = menu.generation
	await key(KEY_ALT)
	check(menu.active and menu.presentation == "world" and menu.generation == world_generation,
		"普通 world 菜单存在时真实 Alt 不替换或关闭它")
	main._title_active = true
	await process_frame
	await process_frame
	check(menu.active and menu.presentation == "world" and not quick.is_open(),
		"QuickTools 的真实 process 不误关取代它的普通 world 菜单")
	quick.close(true)
	check(menu.active and menu.presentation == "world", "旧快捷所有者显式 close 也不误关 world 菜单")
	main._title_active = false
	menu.close(true)

func rejection_cases() -> void:
	land_pose()
	for reason in ["外部模态", "标题", "室内", "房间过场", "潜水切换", "拾取中", "角色过渡"]:
		var old_state: String = main.actor_controller.state_id()
		match reason:
			"外部模态": main.cam_panel.set_open(true)
			"标题": main._title_active = true
			"室内": main.room_service.inside = true
			"房间过场": main.room_controller.busy = true
			"潜水切换": main.dive.switching = true
			"拾取中": main._pick_phase = main.PICK_PHASE_GATHERING
			"角色过渡": main.actor_controller.machine.change("sleeping", {}, true)
		var snapshot: Dictionary = main._quick_tools_context()
		var before := commands.size()
		await key(KEY_ALT)
		check((snapshot.blocked or snapshot.context == "") and not quick.is_open() and not menu.is_open()
			and commands.size() == before, reason + "：真实 Alt 拒绝且没有命令副作用")
		match reason:
			"外部模态":
				main.cam_panel.set_open(false)
				main.hud.menu._sync_backdrop()
			"标题": main._title_active = false
			"室内": main.room_service.inside = false
			"房间过场": main.room_controller.busy = false
			"潜水切换": main.dive.switching = false
			"拾取中": main._pick_phase = main.PICK_PHASE_IDLE
			"角色过渡": main.actor_controller.machine.change(old_state, {}, true)
	if not await expect_open("land"): return
	var stale: Callable = menu.entries[0].command
	var before := commands.size()
	boat_pose()
	await process_frame
	await process_frame
	check(not menu.is_open(), "真实 QuickTools process 在 land→boat 后关闭失效菜单")
	stale.call()
	check(commands.size() == before and not main.building_controller.active, "失效上下文的保存回调不能打开建造")
	land_pose()
	if not await expect_open("land"): return
	main.cam_panel.set_open(true)
	await process_frame
	await process_frame
	check(not menu.is_open(), "已打开后出现外部 modal，子节点 process 自动关闭")
	main.cam_panel.set_open(false)
	main.hud.menu._sync_backdrop()

func restore_and_focus_cases() -> void:
	land_pose()
	var saved: Dictionary = main.capture_world_state().duplicate(true)
	check(int(saved.mode) == 0 and main._quick_tools_context().context == "land", "真实恢复夹具保存 land 快照")
	if not await expect_open("land"): return
	var stale: Callable = menu.entries[0].command
	var before := commands.size()
	main.restore_world_state(saved)
	check(main._quick_tools_context().context == "land" and not quick.is_open() and not menu.is_open()
		and not menu.root.visible, "真实 restore_world_state 恢复同类 land 仍立即关闭快捷菜单")
	stale.call()
	check(commands.size() == before and not main.building_controller.active,
		"同类 land 恢复后的旧回调不能执行建造")
	if not await expect_open("land"): return
	var generation: int = menu.generation
	stale.call()
	check(quick.is_open() and menu.active and menu.generation == generation and commands.size() == before,
		"恢复前旧回调也不能关闭恢复后新打开的 land 菜单")
	stale = menu.entries[0].command
	quick._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not quick.is_open() and not menu.is_open() and not menu.root.visible,
		"窗口失焦通知立即收起快捷菜单")
	stale.call()
	check(commands.size() == before and not main.building_controller.active,
		"窗口失焦后的保存回调无效")
	await process_frame

func edge_caption_cases() -> void:
	var official_query: Callable = quick.context_query
	var motion_before := Cozy.motion_enabled
	Cozy.motion_enabled = false
	var viewport := root.get_visible_rect()
	for context in ["land", "boat"]:
		if context == "land": land_pose()
		else: boat_pose()
		var snapshot: Dictionary = official_query.call().duplicate(true)
		check(snapshot.context == context and not snapshot.blocked, "边缘夹具来自正式快照：" + context)
		quick.context_query = func(): return snapshot
		for anchor in [Vector2(2, 2), viewport.size - Vector2(2, 2)]:
			snapshot.anchor = anchor
			if await expect_open(context):
				await process_frame
				for button in menu.buttons:
					# 与真实 _draw_caption 相同的字体和胶囊尺寸，不能仅验 76px 按钮矩形。
					var text_size: Vector2 = Cozy.world_font().get_string_size(button.caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
					var caption_rect := Rect2(Vector2(button.size.x * 0.5 - text_size.x * 0.5 - 11.0, button.size.y - 2.0),
						Vector2(text_size.x + 22.0, 33.0))
					var local_box := Rect2(Vector2.ZERO, button.size).merge(caption_rect)
					var global_box: Rect2 = button.get_global_transform() * local_box
					check(button.caption != "" and viewport.encloses(global_box),
						"边缘 %s %s：按钮及 caption 完整包围盒在视口内：%s" % [context, str(anchor), button.caption])
			quick.close(true)
	quick.context_query = official_query
	Cozy.motion_enabled = motion_before
	check(quick.context_query == official_query, "边缘测试恢复正式 context_query")

func reduced_motion_case() -> void:
	Cozy.motion_enabled = false
	land_pose()
	if not await expect_open("land"):
		Cozy.motion_enabled = true
		return
	for i in menu.buttons.size():
		var button = menu.buttons[i]
		check(button.entrance == null and button.motion == null and button.scale == Vector2.ONE
			and is_equal_approx(button.modulate.a, 1.0) and button.position.is_equal_approx(menu._offset(i, 2)),
			"减少动效：按钮立即到终点，无入场或焦点 tween：" + str(i))
	await key(KEY_ESCAPE)
	check(not menu.is_open() and not menu.root.visible and not menu.closing, "减少动效 Esc 同步隐藏，无收起 tween")
	Cozy.motion_enabled = true

func building_cases() -> void:
	land_pose()
	var rows: Array = main.building.query().duplicate(true)
	var inventory: Dictionary = economy.to_dict().duplicate(true)
	if not await expect_open("land"): return
	if not await wait_until(func(): return menu.buttons[0].entrance == null or not menu.buttons[0].entrance.is_running(), "建造按钮入场可点击"): return
	await click(menu.buttons[0].get_global_rect().get_center())
	check(main.building_controller.active and main.building_controller.book.visible and not menu.is_open()
		and not commands.is_empty() and commands.back() == "build", "真实建造按钮经正式 craft 链打开 book")
	check(main.building.query() == rows and economy.to_dict() == inventory, "只开 book 不建造、不扣费或退款")
	main.building_controller.close()
	if not await expect_open("land"): return
	var before := commands.size()
	send(KEY_2, true)
	send(KEY_2, true, true)
	send(KEY_2, true)
	send(KEY_2, false)
	await process_frame
	check(commands.size() == before + 1 and commands.back() == "demolish"
		and main.building_controller.active and main.building_controller.recipe == "remove"
		and not main.building_controller.book.visible and not main.building_controller.demolition.confirmation_open(),
		"真实数字键连发仅执行一次拆除入口，并实际进入 remove 选物模式")
	check(main.building.query() == rows and economy.to_dict() == inventory,
		"进入 remove 不提交拆除、不改变布局、不提前退款")
	main.building_controller.close()

func prepare_props() -> Dictionary:
	# 仅用正式恢复端口准备有真实可视 root 的记录，不调用 collect / 奖励端口。
	var data: Dictionary = main.props.to_dict().duplicate(true)
	data.crates = [{"id":90001, "slot":"quick-tools-wood", "kind":"planks", "wood_amount":3,
		"base":[400.2, 1.12, 400.0], "phase":0.0, "yaw":0.0}]
	data.schools = [{"id":90002, "slot":"quick-tools-fish", "base":[406.0, 1.12, 400.0], "phase":0.0, "count":4}]
	data.next_id = 90003
	main.props.from_dict(data)
	return main.props.schools[0]

func no_fish_case() -> void:
	main._cancel_action()
	prepare_props()
	boat_pose(Vector3(800, 1.12, 800))
	check(main.props.schools.size() == 1 and main.props.nearest_school(main.boat.global_position, 24.0).is_empty()
		and not main.boat.starts_sailing(), "无鱼夹具保留真实鱼群，但船已移到 24m 范围外且停稳")
	if not await expect_open("boat"): return
	var before := commands.size()
	var fish_before: int = economy.count("fish")
	var props_before: Dictionary = main.props.to_dict().duplicate(true)
	var route_before: Array = main.boat.route.duplicate()
	var received: Array[String] = []
	var observed := func(label: String): received.append(label)
	main.props.fish_collected.connect(observed)
	await key(KEY_1)
	main._update_pickup_progress(3.0)
	check(commands.size() == before + 1 and commands.back() == "fish" and not menu.is_open(),
		"无鱼时船环 fish 仍经正式 Main 命令入口消费一次并收起")
	check(not main.boat.starts_sailing() and main.boat.route == route_before
		and main._pick_phase == main.PICK_PHASE_IDLE and main._pending_pick.is_empty()
		and economy.count("fish") == fish_before and received.is_empty() and main.props.to_dict() == props_before,
		"24m 内无鱼：不启动航行、不排拾取、不发鱼、不改变真实鱼群")
	check(str(main.hud.toast_snapshot().get("text", "")).contains("附近没有鱼群"), "无鱼沿正式 HUD 提示原因")
	main.props.fish_collected.disconnect(observed)

func sailing_dive_case() -> void:
	main._cancel_action()
	main._debug_teleport("zone1")
	frame_camera(main.player.global_position)
	check(not main._dive_source_at(main.boat.position).is_empty(), "航行潜水夹具位于正式有效潜水来源")
	var destination: Vector3 = main.boat.position + Vector3(0, 0, -30)
	main.boat.sail_to_point(destination)
	main.actor_controller.request_mode(2)
	check(main.boat.starts_sailing() and main._quick_tools_context().context == "boat",
		"正式 sail_to_point 建立航行状态，仍允许打开船环")
	if not await expect_open("boat"): return
	if not await wait_until(func(): return menu.buttons[1].entrance == null or not menu.buttons[1].entrance.is_running(), "航行潜水按钮入场可点击"): return
	var before := commands.size()
	var session = main.dive
	var scene_before := current_scene
	await click(menu.buttons[1].get_global_rect().get_center())
	check(commands.size() == before + 1 and commands.back() == "dive" and not menu.is_open(),
		"航行中真实潜水按钮经正式 Main 命令入口消费一次并收起")
	check(main.boat.starts_sailing() and not main.dive.active and not main.dive.switching
		and main.dive.runtime == null and main.dive == session and current_scene == scene_before and main.is_inside_tree(),
		"航行中潜水不切图、不启动转场，保留正式 session 至最后潜水用例")
	check(str(main.hud.toast_snapshot().get("text", "")).contains("先靠岸或停船再潜水"),
		"航行潜水沿原 _on_dive 保持先停船规则")
	main._cancel_action()

func fishing_case() -> void:
	boat_pose()
	var school: Dictionary = prepare_props()
	check(not main.props.nearest_crate(main.boat.position, 24.0).is_empty()
		and main.props.nearest_school(main.boat.position, 24.0) == school,
		"近处真实木头和稍远鱼群并存，nearest_school 仍选择鱼群")
	if not await expect_open("boat"): return
	check_glyphs()
	var fish_before: int = economy.count("fish")
	var wood_before: int = economy.count("wood")
	var received: Array[String] = []
	var observed := func(label: String): received.append(label)
	main.props.fish_collected.connect(observed)
	var before := commands.size()
	send(KEY_1, true)
	send(KEY_1, true, true)
	send(KEY_ENTER, true)
	send(KEY_1, false)
	send(KEY_ENTER, false)
	check(commands.size() == before + 1 and commands.back() == "fish" and main._pick_phase == main.PICK_PHASE_SAILING
		and main._pending_pick.get("type", "") == "fish" and main._pending_pick.get("item", {}) == school
		and main.boat.starts_sailing(), "钓鱼经原 _handle_prop_click 排真实航线，近木头不抢目标，同帧确认不重发")
	check(economy.count("fish") == fish_before and economy.count("wood") == wood_before,
		"排航行时不直接奖励鱼或木头")
	var gathering := false
	# Main 的全局时间保持停用，只确定性推进原船和原拾取时序，不直接 finish/collect。
	for _step in 2400:
		main.boat._process(1.0 / 60.0)
		main.actor_controller.tick(1.0 / 60.0)
		main._update_pickup_progress(1.0 / 60.0)
		if main._pick_phase == main.PICK_PHASE_GATHERING:
			gathering = true
			if economy.count("fish") != fish_before:
				check(false, "打捞计时完成前不得提前奖励")
				break
		if main._pick_phase == main.PICK_PHASE_IDLE: break
	check(gathering and main._pick_phase == main.PICK_PHASE_IDLE and received == ["鱼群"]
		and economy.count("fish") == fish_before + 1 and economy.count("wood") == wood_before
		and not main.props.schools.has(school) and main.props.crates.size() == 1,
		"原航行→范围校验→计时→props 结算链只收一条鱼，木头保留")
	main._update_pickup_progress(3.0)
	check(received.size() == 1 and economy.count("fish") == fish_before + 1, "原拾取链重复推进不重复奖励")
	main.props.fish_collected.disconnect(observed)
	main._cancel_action()

func save_frame(stage: String) -> void:
	# 调用者已等待真实绘制；headless 永远不进入截图路径。
	var texture := root.get_texture()
	# canvas_items 的逻辑视口经 stretch 后才是渲染像素；不从待验 Image 反推尺寸。
	var capture_size := Vector2i((root.get_visible_rect().size * root.get_stretch_transform().get_scale()).round())
	var image: Image = texture.get_image()
	var path := "res://outputs/quick-tools-" + stage + ".png"
	var valid := image != null and not image.is_empty()
	check(valid, "真实渲染图非空：" + stage)
	if not valid: return
	check(capture_size.x > 0 and capture_size.y > 0
		and image.get_size() == capture_size,
		"截图像素尺寸匹配当前 viewport：%s expected=%s actual=%s" % [stage, capture_size, image.get_size()])
	check(image.save_png(ProjectSettings.globalize_path(path)) == OK, "真实 PNG 保存：" + stage)
	print("[quick-tools-shot] ", ProjectSettings.globalize_path(path),
		" window=", DisplayServer.window_get_size(root.get_window_id()),
		" viewport=", capture_size, " image=", image.get_size())

func capture(stage: String) -> void:
	if not real_renderer: return
	await RenderingServer.frame_post_draw
	save_frame(stage)

func visual_cases() -> void:
	if not real_renderer: return
	for size in SIZES:
		root.size = size
		root.content_scale_size = size
		await process_frame
		await process_frame
		for context in ["land", "boat"]:
			if context == "land": land_pose()
			else: boat_pose()
			mouse_at(Vector2(30, size.y * 0.6))
			var stage := "%dx%d-%s" % [size.x, size.y, context]
			if not await expect_open(context): return
			# 捕获真实 tween 的中间帧，不用终态截图冒充动画。
			var saw_opening := false
			for _frame in 30:
				await RenderingServer.frame_post_draw
				var button = menu.buttons[1]
				if button.scale.x > 0.15 and button.scale.x < 0.95 and button.modulate.a > 0.0:
					saw_opening = true
					save_frame(stage + "-opening")
					break
			check(saw_opening, stage + "：有真实展开中间帧")
			await wait_until(func(): return not menu.buttons[1].entrance.is_running(), stage + " 入场完成")
			await capture(stage + "-open")
			var viewport := root.get_visible_rect()
			for button in menu.buttons:
				check(viewport.encloses(button.get_global_rect()) and button._quick_glyph.is_visible_in_tree(),
					stage + "：图标按钮完整位于视口")
			mouse_at(menu.buttons[1].get_global_rect().get_center())
			await process_frame
			await process_frame
			await wait_until(func(): return menu.buttons[1].motion == null or not menu.buttons[1].motion.is_running(), stage + " hover 完成")
			check(menu.selected_index == 1 and menu.buttons[1].selected, stage + "：真实鼠标 hover 命中第二枚")
			await capture(stage + "-hover")
			send(KEY_ESCAPE, true)
			send(KEY_ESCAPE, false)
			var saw_closing := false
			for _frame in 20:
				await RenderingServer.frame_post_draw
				if menu.closing and menu.buttons[1].scale.x > 0.2 and menu.buttons[1].scale.x < 0.95:
					saw_closing = true
					save_frame(stage + "-closing")
					break
			check(saw_closing, stage + "：有真实收起中间帧")
			await wait_until(func(): return not menu.is_open(), stage + " 收起完成")
			check(not menu.root.visible, stage + "：收起后根控件隐藏")
			await capture(stage + "-closed")

func dive_case() -> void:
	# 最后一项只验证同步接纳边界，不加载海底或替代 dive-transition 的完整往返。
	main._cancel_action()
	main._debug_teleport("zone1")
	frame_camera(main.player.global_position)
	main.dive.air.recover = 0.0
	var entry: Vector3 = main.boat.position
	check(not main._dive_source_at(entry).is_empty(), "潜水夹具用正式位置解析有效来源")
	if not await expect_open("boat"): return
	check(main.input_blocked() and not main._quick_tools_context().blocked, "自有 quick 菜单是世界 modal，但不会自挡上下文")
	var before := commands.size()
	send(KEY_2, true)
	send(KEY_2, true, true)
	send(KEY_ENTER, true)
	send(KEY_2, false)
	send(KEY_ENTER, false)
	check(commands.size() == before + 1 and commands.back() == "dive" and main.dive.switching
		and main.dive.runtime == null and main.is_inside_tree() and not menu.is_open() and not menu.root.visible,
		"潜水按钮先撤自身 modal，再走原 _on_dive→request_dive，仅一次并即时 switching")
	check(main._quick_tools_context().blocked and main.input_blocked(), "接纳潜水后转场立即阻塞新输入")
	# 在 deferred 装载前 dispose；不伪造成功完成或潜水渲染证据。
	main.dive.dispose()

func finish() -> void:
	Cozy.motion_enabled = original_motion
	if is_instance_valid(main):
		if is_instance_valid(main.dive): main.dive.dispose()
		current_scene = null
		main.free()
	if is_instance_valid(probe): probe.free()
	await process_frame
	print("[quick-tools] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var user := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not user.begins_with("sea-verification/") or not project.ends_with("/project"):
		check(false, "只允许 runner 隔离工程与独立 user://，拒绝直接运行主工程")
		print("[quick-tools] %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	if not OS.get_cmdline_user_args().has("--skip-title"):
		check(false, "runner 必须传 --skip-title")
		await finish()
		return
	real_renderer = DisplayServer.get_name() != "headless"
	original_motion = Cozy.motion_enabled
	Cozy.motion_enabled = true
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs")) == OK, "隔离 outputs 目录可用")
	root.content_scale_size = SIZES[0]
	if real_renderer: root.size = SIZES[0]
	await module_cases()
	if failures: await finish(); return
	economy = root.get_node("Economy")
	economy.set_process(false)
	economy.set_physics_process(false)
	# 探针先于 Main 入树，让 Main/GUI 优先处理，探针只观察剩余的世界输入。
	probe = WorldProbe.new()
	root.add_child(probe)
	main = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	root.add_child(main)
	current_scene = main
	main.set_process(false)
	main.set_physics_process(false)
	main.interactor.set_process(false)
	main.boat.set_process(false)
	main.cam.set_process(false)
	main.props.set_process(false)
	main._title_active = false
	if is_instance_valid(main.start_screen):
		main.start_screen.hide()
		main.start_screen.set_process_input(false)
	await process_frame
	await process_frame
	if main.quick_tools == null or main.building_controller == null or main.hud.world_actions == null:
		check(false, "正式 Main 必须完成 QuickTools、世界菜单和建造控制器装配")
		await finish()
		return
	quick = main.quick_tools
	menu = main.hud.world_actions
	quick.execute = record_command
	clock_before = main.world_clock.to_dict().duplicate(true)
	check(not main.is_processing() and not main._autosave_on and quick.is_processing() and menu.is_processing(),
		"Main/自动存档已停用，QuickTools 和菜单仍真实逐帧运行")
	main._restore_building({"version":1, "next_id":3, "instances":[
		{"id":"built_1", "kind":"raft_4x4", "x":0, "z":0, "px":2.0, "pz":10.0, "py":0.0, "turn":0, "support":"", "left":0.0},
		{"id":"built_2", "kind":"planter_small", "x":0, "z":0, "px":0.8, "pz":8.8, "py":0.0, "turn":0, "support":"built_1", "left":0.0}]})
	await physics_frame
	await physics_frame
	await toggle_and_dismiss_cases()
	if failures: await finish(); return
	await rejection_cases()
	if failures: await finish(); return
	await restore_and_focus_cases()
	if failures: await finish(); return
	await edge_caption_cases()
	if failures: await finish(); return
	await reduced_motion_case()
	if failures: await finish(); return
	await building_cases()
	if failures: await finish(); return
	await no_fish_case()
	if failures: await finish(); return
	await sailing_dive_case()
	if failures: await finish(); return
	await fishing_case()
	if failures: await finish(); return
	await visual_cases()
	check(main.world_clock.to_dict() == clock_before and not main._autosave_on,
		"功能与截图全程未推进世界时钟，未开启自动存档")
	if failures: await finish(); return
	await dive_case()
	await finish()
