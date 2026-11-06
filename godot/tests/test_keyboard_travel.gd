extends SceneTree
## 正式默认场景的纯键盘往返；仅初始家泊位定位，途中不恢复位置或代执行业务。
const IDS := ["platform_plot", "platform_plot:1", "platform_plot:2", "platform_plot:3", "platform_plot:4", "platform_plot:5"]
const MOVE := [KEY_W, KEY_A, KEY_S, KEY_D]
var checks := 0
var failures := 0
var main
var state
var economy
var menu
var down_keys: Dictionary = {}
var destinations: Array[String] = []
var arrivals: Array = []
var business: Array = []
var max_progress := 0.0
var saw_strolling := false
var completed_trip := false

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [keyboard-travel] ", label)
	return ok

## 瞬时键走 Viewport；持续键更新全局 Input 并刷新缓冲，不重复分发。
func send(code: int, pressed: bool, continuous := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	if continuous:
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed: down_keys[code] = true
		else: down_keys.erase(code)
	else:
		root.push_input(event, true)

func key(code: int) -> void:
	send(code, true)
	await process_frame
	send(code, false)
	await process_frame

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func until(predicate: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()): return true
		await process_frame
	check(false, label)
	diagnostic(label)
	return false

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func diagnostic(label: String) -> void:
	if main == null: return
	print("[keyboard-travel-state] ", label, " zone=", state.current_zone,
		" landing=", state.landing_id, " actor=", main.player.global_position,
		" controller=", main.actor_controller.snapshot(), " boat=", main.boat.position,
		" sailing=", main.boat.starts_sailing(), " route=", main.boat.remaining_route(),
		" pick=", main._sea_pick_candidate(), " pick_phase=", main._pick_phase,
		" dock=", main._near_landing_key(), " target=", main.interactor.target,
		" keyboard_target=", main.interactor.keyboard_target,
		" blocked=", main.interactor.last_blocked, " toast=", main.hud._toast.text)

func no_tutorial(text: String, label: String) -> void:
	check(not text.strip_edges().is_empty(), label + " 内容非空")
	for fragment in ["按住", "按 E", "再按", "方向键", "Enter", "Shift+", "点水面", "快捷键"]:
		check(not text.contains(fragment), label + " 不含键位教程 " + fragment)

func prompt_hidden(label: String) -> void:
	check(not main.prompt.enabled and not main.prompt.visible and not main.prompt._panel.is_visible_in_tree(), label + " 底部 prompt 不可见")

func near_icon(spot: Node3D, label: String) -> void:
	check(main.hover.keyboard_focus == spot, label + " keyboard_focus 绑定真实目标")
	check(main.hover._near_icon.visible and main.hover._near_icon.is_visible_in_tree(), label + " 近距图标可见")
	var world: Vector3 = spot.focus_position() + Vector3.UP * 0.85 if spot.has_method("focus_position") else spot.stand_position() + Vector3.UP * 0.55
	var screen: Vector2 = main.cam.unproject_position(world)
	var center: Vector2 = main.hover._near_icon.position + main.hover._near_icon.size * 0.5
	check(center.distance_to(screen) < 60.0, label + " 图标贴近目标投影")
	prompt_hidden(label)

func open_map() -> bool:
	var at: Vector3 = main.player.global_position
	var boat_at: Vector3 = main.boat.position
	await key(KEY_N)
	var note = main.hud.notebook
	if not check(note.visible and main.hud.is_panel_open(), "N 打开正式笔记"): return false
	for attempt in 5:
		if root.gui_get_focus_owner() in note.categories.values(): break
		await key(KEY_UP)
	if not check(root.gui_get_focus_owner() in note.categories.values(), "方向键到笔记分类"): return false
	for attempt in 5:
		if root.gui_get_focus_owner() == note.categories.life: break
		await key(KEY_RIGHT)
	if not check(root.gui_get_focus_owner() == note.categories.life, "方向键选 life 分类"): return false
	await key(KEY_ENTER)
	if not check(note.category == "life" and note.cards[0].has_focus(), "Enter 进入生活卡片"): return false
	await key(KEY_DOWN)
	await key(KEY_RIGHT)
	if not check(note.selected == "sailing" and root.gui_get_focus_owner() in note.cards, "方向键选航海卡 sailing"): return false
	await key(KEY_ENTER)
	if not check(note.action_button.has_focus(), "航海卡 Enter 到详情动作"): return false
	await key(KEY_ENTER)
	await frames(4)
	if not check(main.hud._tab == "map" and main.hud._panel.detail.visible, "详情 Enter 打开正式航海图"): return false
	check(flat(at, main.player.global_position) < 0.02 and flat(boat_at, main.boat.position) < 0.02, "笔记及地图方向键不穿透移动")
	check(not main.hover._near_icon.visible and main.hover.keyboard_focus == null, "笔记地图接管时近距图标收起")
	prompt_hidden("航海图")
	return true

func travel(zone_id: String) -> bool:
	if not await open_map(): return false
	var chosen := false
	for attempt in main.hud._map_buttons.size() + 1:
		var focused: Control = root.gui_get_focus_owner()
		if focused != null and str(focused.get_meta("zone_id", "")) == zone_id:
			chosen = true
			break
		await key(KEY_DOWN)
	if not check(chosen, "地图方向键可达 " + zone_id): return false
	var requested := destinations.size()
	var arrived := arrivals.size()
	await key(KEY_ENTER)
	if not check(destinations.size() == requested + 1 and destinations.back() == zone_id and not main.hud.is_panel_open(), "Enter 只发一次现有 destination 链 " + zone_id): return false
	if not await until(func(): return main.boat.starts_sailing(), 10.0, "真实离岸并开始航行 " + zone_id): return false
	check(main.actor_controller.mode() == 2 and not main._ashore_on_arrival, "地图航行态不偷自动上岸 " + zone_id)
	if not await until(func(): return arrivals.size() > arrived and not main.boat.starts_sailing(), 90.0, "90 秒内真实航行抵达 " + zone_id): return false
	if not check(arrivals.size() == arrived + 1 and arrivals.back() == [zone_id, "main"], "真实 arrived 事件只到指定主泊位 " + zone_id): return false
	check(state.current_zone == zone_id and state.landing_id == "main" and main.actor_controller.state_id() == "boat_idle", "到站状态由现有链同步 " + zone_id)
	check(main._landing_is_docked() and main._pick_phase == 0, "到站船已靠妥且没有拾取流程 " + zone_id)
	print("[keyboard-travel-leg] 抵达 ", zone_id, " boat=", main.boat.position)
	await frames(4)
	return true

func disembark(zone_id: String) -> bool:
	var candidate: Dictionary = main._sea_pick_candidate()
	# 近距拾取有合法优先权；若真实泊位被它占用，报告失败，不能删物或伪造靠岸。
	if not check(candidate.is_empty() or not bool(candidate.get("near", false)), "靠岸 E 不被合法近距 sea pick 占用 " + zone_id):
		diagnostic("靠岸优先级冲突")
		return false
	if not check(main._boat_key_action() == "leave", "真实泊位提供上岸 E " + zone_id): return false
	near_icon(main._current_landing(), "到站 " + zone_id)
	await key(KEY_E)
	if not await until(func(): return main.actor_controller.state_id() == "ashore_idle", 8.0, "E 真正上岸 " + zone_id): return false
	check(main.actor_controller.mode() == 0 and main._zone_nodes[zone_id].area_at(main.player.global_position, 0.6) != null, "上岸落在真实可走面 " + zone_id)
	check(main._pick_phase == 0 and main._pending_pick.is_empty() and not main.boat.starts_sailing(), "E 上岸没有串成海面拾取 " + zone_id)
	check(main.hud._toast.text == "上岸了" and main.hud._toast_box.visible, "上岸成功反馈明确 " + zone_id)
	no_tutorial(main.hud._toast.text, "上岸反馈 " + zone_id)
	prompt_hidden("上岸 " + zone_id)
	await frames(24)
	return true

## 每次只按当前 camera basis 下最接近目标的 WASD；不调用移动命令或写位置。
func walk_to(goal: Vector3, label: String) -> bool:
	var start: Vector3 = main.player.global_position
	var deadline := Time.get_ticks_msec() + 12000
	var stalled_since := Time.get_ticks_msec()
	var last: Vector3 = start
	var held := 0
	while Time.get_ticks_msec() < deadline and flat(main.player.global_position, goal) > 0.22:
		var offset: Vector3 = goal - main.player.global_position
		offset.y = 0.0
		var forward: Vector3 = -main.cam.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP).normalized()
		var x := offset.dot(right)
		var y := offset.dot(forward)
		var code: int = (KEY_D if x > 0.0 else KEY_A) if absf(x) > absf(y) else (KEY_W if y > 0.0 else KEY_S)
		if code != held:
			if held != 0: send(held, false, true)
			send(code, true, true)
			held = code
		await frames(2)
		saw_strolling = saw_strolling or main.actor_controller.strolling()
		if flat(last, main.player.global_position) > 0.02:
			last = main.player.global_position
			stalled_since = Time.get_ticks_msec()
		if Time.get_ticks_msec() - stalled_since > 1500: break
	if held != 0: send(held, false, true)
	await frames(24)
	var ok := check(flat(main.player.global_position, goal) <= 0.40, label + " WASD 实际到位")
	check(main.actor_controller.mode() == 0 and not main.boat.starts_sailing(), label + " 始终岸上步行")
	check(main.actor_controller.move_intent == Vector3.ZERO and main.actor_controller.state_id() == "ashore_idle", label + " 松键后停稳")
	if not ok: diagnostic(label + " 无可走路径或实际受阻")
	print("[keyboard-travel-walk] ", label, " from=", start, " to=", main.player.global_position, " goal=", goal)
	return ok

func camera_keys(label: String) -> void:
	check(not main.room_service.inside and not main.cam.pose_lock and not main.cam.orbit_only, label + " 在室外复验镜头")
	var at: Vector3 = main.player.global_position
	var boat_at: Vector3 = main.boat.position
	var before: Vector3 = main.cam.dir
	await key(KEY_BRACKETLEFT)
	check(main.cam.dir.distance_to(before) > 0.02, label + " [ 旋转镜头")
	await key(KEY_BRACKETRIGHT)
	check(main.cam.dir.distance_to(before) < 0.01, label + " ] 反向旋转镜头")
	var distance: float = main.cam.distance
	await key(KEY_MINUS)
	check(main.cam.distance > distance, label + " - 拉远")
	await key(KEY_EQUAL)
	check(is_equal_approx(main.cam.distance, distance), label + " = 拉近回原距离")
	await key(KEY_F)
	check(main.cam.follow_enabled and main.cam.follow_subject == main.player, label + " F 恢复角色跟随")
	check(main.hud._toast.text == "镜头已回到角色", label + " F 反馈正确")
	no_tutorial(main.hud._toast.text, label + " 镜头反馈")
	check(flat(at, main.player.global_position) < 0.02 and flat(boat_at, main.boat.position) < 0.02, label + " 镜头键不移动人船")
	check(not menu.is_open() and not main.hud.is_panel_open() and not main.hud.menu.active and not paused and main._pick_phase == 0, label + " 镜头键不串菜单、暂停或拾取")
	prompt_hidden(label)

func plot_menu(plot: Node3D) -> bool:
	var locked := false
	for attempt in 24:
		# 必须真实按过 Q，不能把自动挑中的 target 当作 Q 已验收。
		await key(KEY_Q)
		await frames(2)
		if main.interactor.target == plot and main.interactor.keyboard_target == plot:
			locked = true
			break
	if not check(locked and plot.focused, "Q 循环选中六格之一 " + str(plot.plot_id)):
		diagnostic("Q 无法选中 " + str(plot.plot_id))
		return false
	near_icon(plot, str(plot.plot_id))
	var snapshot: Dictionary = economy.farm.state(str(plot.plot_id)).duplicate(true)
	var at: Vector3 = main.player.global_position
	max_progress = 0.0
	send(KEY_E, true, true)
	check(Input.is_action_pressed("interact") and Input.is_physical_key_pressed(KEY_E), "持续 E 已刷新全局 Input")
	var opened := await until(func(): return menu.active, 4.0, "按住 E 出现世界菜单 " + str(plot.plot_id))
	if opened:
		check(max_progress > 0.0, "菜单来自真实 interactor 长按 " + str(plot.plot_id))
		check(not main.hover._near_icon.visible and not main.hover._near_progress.visible and main.hover.keyboard_focus == null, "菜单开时近距图标与进度收起")
		var generation: int = menu.generation
		await create_timer(0.65).timeout
		check(menu.active and menu.generation == generation, "持续 E 不连确认或重开菜单")
	send(KEY_E, false, true)
	await frames(2)
	if not opened: return false
	check(not menu.entries.is_empty() and menu.selected_index >= 0 and menu.selected_index < menu.buttons.size(), "世界菜单存在真实选项与选择")
	if menu.entries.is_empty(): return false
	check(root.gui_get_focus_owner() == menu.buttons[menu.selected_index], "菜单持有 GUI 焦点")
	check(menu.hint_label.text.contains(economy.farm.status_text(str(plot.plot_id))), "菜单标题含当前地格状态")
	no_tutorial(menu.hint_label.text, "地格菜单")
	# 空格的浇水灰项来自真实业务，不改库存/作物以制造结果。
	var blocked := -1
	for i in menu.entries.size():
		if str(menu.entries[i].get("blocked", "")) != "":
			blocked = i
			break
	if not check(blocked >= 0, "真实空地菜单提供受阻项"): return false
	for attempt in menu.entries.size():
		if menu.selected_index == blocked: break
		await key(KEY_RIGHT)
	var reason := str(menu.entries[blocked].get("blocked", ""))
	check(menu.selected_index == blocked and not menu.buttons[blocked].available, "方向键选择真实灰项")
	await key(KEY_ENTER)
	check(menu.active and main.hud._toast_box.visible and main.hud._toast.text == reason, "灰项确认反馈真实受阻原因")
	no_tutorial(main.hud._toast.text, "受阻反馈")
	check(flat(at, main.player.global_position) < 0.02 and main.actor_controller.mode() == 0, "Q/E/菜单方向与确认不穿透步行或上船")
	check(economy.farm.state(str(plot.plot_id)) == snapshot and business.is_empty(), "打开及受阻操作不偷改作物、不假报成功")
	prompt_hidden("世界菜单")
	await key(KEY_ESCAPE)
	if not await until(func(): return not menu.is_open(), 2.0, "Esc 收起世界菜单"): return false
	check(not main.hud.menu.active and not paused and not main.hud.is_panel_open(), "Esc 不穿透到暂停或笔记")
	await frames(4)
	check(not main.hover._near_progress.visible and not Input.is_action_pressed("interact"), "Esc 后无长按残留")
	prompt_hidden("Esc 后")
	return true

func run() -> void:
	if not check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"), "必须由 runner 在 Autoload 前隔离用户目录"):
		finish(); return
	if not check(OS.get_cmdline_user_args().has("--skip-title") and not OS.get_cmdline_user_args().has("--full-world"), "使用默认正式范围并仅跳过标题"):
		finish(); return
	var path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var scene = load(path)
	if not check(scene is PackedScene and scene.resource_path == "res://scenes/main.tscn", "加载项目默认正式主场景"):
		finish(); return
	main = scene.instantiate()
	root.add_child(main)
	main._autosave_on = false
	economy = root.get_node("Economy")
	economy.ticking = false
	main.world_clock.paused = true
	state = root.get_node("GameState")
	menu = main.hud.world_actions
	main.hud.destination_pressed.connect(func(id): destinations.append(id))
	main.boat.arrived.connect(func(zone, landing): arrivals.append([zone, landing]))
	main.farm_field.acted.connect(func(id, event, payload): business.append([id, event, payload]))
	main.interactor.progress_changed.connect(func(value): max_progress = maxf(max_progress, float(value)))
	# 唯一位置夹具：角色放在家主泊位；船保留正式场景的初始泊位。
	var home: Node3D = main._zone_nodes.zone1.landing_point("main")
	var stand: Vector3 = home.stand_position()
	main.actor_controller.restore_pose({"mode":0,"player":[stand.x, stand.y, stand.z]})
	await frames(20)
	if not check(not main._title_active and main.hud.visible and not main.input_blocked() and state.current_zone == "zone1" and main._landing_is_docked(), "初始角色在家泊位，正式主循环可用"):
		finish(); return
	await camera_keys("家泊位")
	if not await travel("zone5"):
		finish(); return
	if not await disembark("zone5"):
		finish(); return
	var center := Vector3.ZERO
	for id in IDS:
		var plot: Node3D = main.farm_field.find(id)
		if not check(plot != null and plot.is_visible_in_tree() and economy.farm.is_empty(id), "正式初始六格存在且为空 " + id):
			finish(); return
		center += plot.global_position / float(IDS.size())
	var landed: Vector3 = main.player.global_position
	check(flat(landed, center) < 5.0, "登陆点到六格很近，不绕行或跨区")
	if not await walk_to(center, "登陆点至六格"):
		finish(); return
	if not check(saw_strolling and flat(landed, main.player.global_position) > 0.40, "真实 WASD 从登陆点走入六格区"):
		finish(); return
	for id in IDS:
		if not await plot_menu(main.farm_field.find(id)):
			finish(); return
	await camera_keys("六格菜单退出后")
	if not await walk_to(main._current_landing().stand_position(), "六格返船"):
		finish(); return
	await frames(24)
	if not check(main._boat_key_action() == "board", "走回泊位后 E 合法优先上船而非地格"):
		diagnostic("返船 E 被占用"); finish(); return
	await key(KEY_E)
	if not await until(func(): return main.actor_controller.state_id() == "boat_idle", 8.0, "E 真正返船完成"):
		finish(); return
	check(main.hud._toast.text == "上船了" and main._pick_phase == 0, "返船成功反馈且不串拾取")
	no_tutorial(main.hud._toast.text, "返船反馈")
	if not await travel("zone1"):
		finish(); return
	if not await disembark("zone1"):
		finish(); return
	check(destinations == ["zone5", "zone1"] and arrivals == [["zone5", "main"], ["zone1", "main"]], "键盘往返仅两次真实目的地与抵达事件")
	check(business.is_empty(), "旅行验收全程不执行种植业务")
	completed_trip = true
	finish()

func finish() -> void:
	for code in down_keys.keys(): send(int(code), false, true)
	check(completed_trip, "完整完成家泊位→zone5六格→返船→家泊位上岸，不允许中途空通过")
	print("[keyboard-travel] ", checks, " checks, ", failures, " failures")
	if main != null and is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(0 if failures == 0 else 1)
