extends SceneTree
## 键盘操控专项（2026-11-05）
##
## 锁四条契约：
##   SEA-MOVE-R20   方向键/WASD 让角色沿「镜头朝向」行走，松开即停，任何一帧都不离开脚下地面；
##   SEA-NAV-R15    船上同一组方向键手动划船，松手减速停稳，撞岸停住且不穿过岸线；
##   SEA-CAMERA-R12 方向键不再移动镜头（以前按住 = 平移镜头）；
##   SEA-INTERACT-R13 泊位旁按 E 上船、船上按 E 上岸；附近有交互焦点时 E 归交互。
##
## 面板打开时不读键（方向键在背包页里是选格子）也一并断言 —— 这条不报错，
## 只会在实际游玩里表现为「翻着包人自己跑了」。

var checks := 0
var failures := 0
var main: Node
var state: Node


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func wait_frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func press(action: String) -> void:
	Input.action_press(action)


func release(action: String) -> void:
	Input.action_release(action)


func release_all() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func key_event(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	main._unhandled_input(event)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	state = root.get_node("GameState")
	root.get_node("Economy").ticking = false
	await wait_frames(12)

	var controller: Variant = main.actor_controller
	if controller == null or not controller.actor is Node3D:
		printerr("FAIL actor controller unavailable")
		finish(false)
		return
	var player: Node3D = controller.actor

	# ---- 键位注册：两条轴各两个键，缺一个就等于半个方向不能走 -----------------
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		check(InputMap.has_action(action), "移动动作已注册 " + action)
	var forward_keys := 0
	for event in InputMap.action_get_events("move_forward"):
		if event is InputEventKey:
			forward_keys += 1
	check(forward_keys >= 2, "前进同时接受 W 与 上方向键")

	# ---- 岸上：方向键走人，镜头不动 -------------------------------------------
	state.enter_zone("zone1")
	state.set_mode(state.Mode.ASHORE)
	var landing: Node3D = main._current_landing()
	if landing == null:
		printerr("FAIL zone1 landing missing")
		finish(false)
		return
	var stand: Vector3 = landing.stand_position()
	controller.restore_pose({"mode": 0, "player": [stand.x, stand.y, stand.z]})
	main.cam.suspend_follow()
	await wait_frames(4)
	check(controller.mode() == 0, "角色先在岸上")

	var cam_before: Vector3 = main.cam.target
	var start: Vector3 = player.global_position
	press("move_forward")
	await wait_frames(26)
	var travelled := flat_distance(start, player.global_position)
	check(travelled > 0.10, "按住前进角色真的走了 (%.2f m)" % travelled)
	check(controller.strolling(), "键盘行走进入 strolling 状态")
	var intent: Vector3 = controller.move_intent
	var expected_facing := atan2(intent.x, intent.z)
	var facing_error: float = absf(angle_difference(player.rotation.y, expected_facing))
	check(facing_error < 0.45, "朝向对齐行走方向 (%.2f rad)" % facing_error)
	check(main.cam.target.distance_to(cam_before) < 0.001, "方向键不再平移镜头")
	# 松手是减速停，不是一帧归零（SEA-MOVE-R23）：滑行一小段、0.35 秒内停稳，
	# 之后不再自走。逐帧数值由 control-feel 负责，这里只锁「大体量级」。
	release("move_forward")
	await wait_frames(21)
	var parked: Vector3 = player.global_position
	await wait_frames(12)
	check(flat_distance(parked, player.global_position) < 0.01, "松开方向键 0.35 秒内停稳且不再滑")
	check(not controller.strolling(), "停住后回到站立状态")

	# ---- 边界：朝海连按 1 秒也不掉下甲板 -------------------------------------
	var before_edge: Vector3 = player.global_position
	press("move_left")
	await wait_frames(60)
	release("move_left")
	await wait_frames(4)
	check(absf(player.global_position.y - before_edge.y) < 0.5, "沿甲板走不落海（高度未跳变）")
	check(main._current_landing() != null, "泊位仍可用")

	# ---- 面板打开时不读键 -----------------------------------------------------
	controller.restore_pose({"mode": 0, "player": [stand.x, stand.y, stand.z]})
	await wait_frames(4)
	main.hud.toggle_panel()
	await wait_frames(2)
	var panel_start: Vector3 = player.global_position
	press("move_forward")
	await wait_frames(20)
	release("move_forward")
	check(flat_distance(panel_start, player.global_position) < 0.02, "面板打开时方向键不移动角色")
	main.hud.toggle_panel()
	await wait_frames(2)

	# ---- 船上：同一组键手动划船 ---------------------------------------------
	controller.restore_pose({"mode": 1})
	await wait_frames(6)
	check(controller.mode() == 1, "先在船上")
	check(main._landing_is_docked(), "船停在泊位")
	var boat_start: Vector3 = main.boat.position
	press("move_forward")
	await wait_frames(40)
	var sailed := flat_distance(boat_start, main.boat.position)
	check(sailed > 0.15, "方向键让船划出去了 (%.2f m)" % sailed)
	check(main.boat.driving(), "手动驾驶接管")
	check(controller.mode() == 2, "船上按键切到航行")
	release("move_forward")
	await wait_frames(60)
	check(not main.boat.driving() and not main.boat.starts_sailing(), "松手减速停稳")
	check(main._is_open_water(main.boat.position.x, main.boat.position.z), "停下时仍在开阔水面")
	await wait_frames(4)
	check(controller.mode() == 1, "停稳后回船上待机")

	# ---- 撞岸：从泊位朝家园中心划，不许穿过去 ---------------------------------
	var l1: Dictionary = main._landing_data("zone1", "main")
	var park := Vector3(float(l1.boatPark[0]), 1.12, float(l1.boatPark[2]))
	main.boat.place_at(park, 0.0)
	main.boat.set_drive(Vector2(stand.x - park.x, stand.z - park.z))
	controller.request_mode(state.Mode.SAILING)
	for i in 120:
		await process_frame
	check(main._is_open_water(main.boat.position.x, main.boat.position.z), "撞岸后船仍在开阔水面")
	main.boat.stop_drive()
	release_all()
	await wait_frames(4)

	# ---- E 键上船 / 上岸 -----------------------------------------------------
	main.boat.place_at(park, 0.0)
	state.landing_id = "main"
	state.enter_zone("zone1")
	# 站在泊位旁边一米多：站在站立点「正上方」时点击/上船那条走路链没有距离可走，
	# 是既有行为，不是本轮引入的；这里按真实玩法摆位。
	var ground: Node3D = landing.ground()
	var near: Vector2 = ground.clamp_point(stand.x + 0.9, stand.z + 0.9)
	var near_point: Vector3 = ground.surface_point(Vector3(near.x, stand.y, near.y))
	if not near_point.is_finite():
		near_point = stand
	controller.restore_pose({"mode": 0, "player": [near_point.x, near_point.y, near_point.z]})
	await wait_frames(4)
	check(main._boat_shortcut_text() == "上船", "泊位旁提示按 E 上船")
	# 更近的可交互目标优先：用一个临时替身站在角色脚边，
	# 证明「物件比泊位近时 E 归采集」，不依赖世界里某个具体家具的位置。
	var stub := Node3D.new()
	main.add_child(stub)
	stub.global_position = player.global_position + Vector3(0.2, 0.0, 0.0)
	main.interactor.target = stub
	check(main._toggle_boat_by_key() == false, "更近的交互目标时 E 不抢上船")
	main.interactor.target = null
	stub.queue_free()
	await wait_frames(2)
	key_event(KEY_E)
	await wait_frames(70)
	check(controller.mode() == 1, "按 E 上船")
	check(main._boat_shortcut_text() == "上岸", "船上提示按 E 上岸")
	key_event(KEY_E)
	await wait_frames(30)
	check(controller.mode() == 0, "按 E 上岸")

	release_all()
	await wait_frames(4)
	finish(true)


func finish(ok: bool) -> void:
	if not ok and failures == 0:
		failures += 1
	print("[keyboard-control] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
