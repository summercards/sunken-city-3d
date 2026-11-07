extends SceneTree
## 真实 main.tscn 的无鼠标闭环。runner 映射 keyboard-farm-loop / visual-keyboard-farm-loop。
## 仅定位、库存、水壶与初始日历属于夹具；种植、浇水、收获、生长、入睡均由键盘触发。
## visual- 映射运行本脚本即可截图，文件落在 runner 隔离工程的 outputs（sea-work）下。
const IDS := ["platform_plot", "platform_plot:1", "platform_plot:2", "platform_plot:3", "platform_plot:4", "platform_plot:5"]
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const Items = preload("res://src/inventory/item_db.gd")
var checks := 0
var failures := 0
var main
var economy
var farm
var menu
var actor
var acted: Array = []
var starts: Array = []
var completions: Array = []
var farm_center := Vector3.ZERO
var max_progress := 0.0
var saw_character_progress := false
var down_keys: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [keyboard-farm-loop] ", label)

## 菜单瞬时键用 Viewport 分发；持续键用 parse 更新全局 Input，绝不双重分发同一事件。
func send(code: int, pressed: bool, global_input := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	if global_input:
		Input.parse_input_event(event)
		# 累积输入默认缓冲；先刷新再检查 Input，否则同帧查询仍是旧状态。
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

func held_key(code: int, seconds: float) -> void:
	send(code, true, true)
	await create_timer(seconds).timeout
	send(code, false, true)
	await frames(2)

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
	return false

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "res://outputs/keyboard-farm-" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "真实渲染截图 " + label)
	print("[keyboard-farm-shot] ", path)

func entry_index(id: String) -> int:
	for i in menu.entries.size():
		if str(menu.entries[i].get("id", "")) == id: return i
	return -1

func menu_focus(label: String) -> bool:
	var selected: Variant = menu.get("selected_index")
	var valid: bool = selected != null and int(selected) >= 0 and int(selected) < menu.buttons.size()
	check(valid, label + " 有合法 selected_index")
	if not valid: return false
	var button: Button = menu.buttons[int(selected)]
	check(button.is_visible_in_tree() and bool(button.selected), label + " 选中气泡可见并高亮")
	check(root.gui_get_focus_owner() == button, label + " GUI 焦点属于选中气泡")
	return true

func select_entry(id: String) -> bool:
	var index := entry_index(id)
	check(menu.active and index >= 0, "真实菜单包含 " + id)
	if not menu.active or index < 0: return false
	if menu.get("selected_index") == null:
		check(false, "生产菜单尚未提供 selected_index")
		return false
	var before: Vector3 = actor.global_position
	for attempt in menu.entries.size() + 1:
		if int(menu.get("selected_index")) == index:
			check(actor.global_position.distance_to(before) < 0.02, "菜单方向键不穿透角色移动 " + id)
			return menu_focus(id)
		await key(KEY_RIGHT)
	check(false, "方向键可选择实际项 " + id)
	return false

func choose(id: String, confirm := KEY_ENTER) -> bool:
	if not await select_entry(id): return false
	await key(confirm)
	return true

func assert_menu_layout(label: String) -> void:
	await frames(24)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
	check(viewport_size.x >= 1280.0 and viewport_size.x <= 1600.0 and is_equal_approx(viewport_size.x / viewport_size.y, 1.6), label + " 支持 1280/1600 宽屏布局")
	var viewport := Rect2(Vector2.ZERO, viewport_size)
	var box: Rect2 = menu._content_box()
	var content := Rect2(menu.cluster.position + box.position, box.size)
	if menu.hint_box != null:
		content = content.merge(Rect2(menu.cluster.position + menu.hint_box.position, menu.hint_box.size))
	check(content.size.x > 0.0 and content.size.y > 0.0, label + " 菜单布局已完成")
	check(viewport.grow(-2.0).encloses(content), label + " 菜单簇在视口内")
	check(menu.hint_label != null and menu.hint_label.visible and menu.hint_label.text != "", label + " 标题文字完整存在")
	check(not menu.hint_label.text.contains("方向键选择") and not menu.hint_label.text.contains("Enter 确认"), label + " 标题不含教程说明行")
	if not menu.entries.is_empty():
		check(menu.index_for_key(KEY_1) == 0, label + " 数字键索引仍可用")
	for i in menu.buttons.size():
		check(menu.buttons[i].hotkey == "", label + " 不显示数字键角标 " + str(i))
	if menu.hint_box != null and menu.hint_label != null:
		check(menu.hint_box.size.x >= menu.hint_label.get_combined_minimum_size().x and menu.hint_box.size.y >= menu.hint_label.get_combined_minimum_size().y, label + " 标题无裁切")
	for i in menu.buttons.size():
		var button: Button = menu.buttons[i]
		check(button.is_visible_in_tree() and button.caption != "", label + " 气泡文字可见 " + str(i))

func near_focus_expected_point(spot: Node3D) -> Vector3:
	if spot == null: return Vector3.INF
	if spot.has_method("focus_position"):
		return spot.focus_position() + Vector3.UP * 0.85
	if spot.has_method("stand_position"):
		return spot.stand_position() + Vector3.UP * 0.55
	return spot.global_position + Vector3.UP * 0.5

func near_focus_is_legal() -> bool:
	var focus: Node3D = main.hover.keyboard_focus
	if not is_instance_valid(focus): return false
	if focus == main.interactor.target: return true
	if main.has_method("_current_landing") and focus == main._current_landing(): return true
	if main.has_method("_near_landing_key"):
		var dock: Dictionary = main._near_landing_key()
		if not dock.is_empty() and main._zone_nodes.has(str(dock.zone)):
			var landing: Node3D = main._zone_nodes[str(dock.zone)].landing_point(str(dock.landing))
			if focus == landing: return true
	if main.has_method("_sea_pick_candidate"):
		var pick: Dictionary = main._sea_pick_candidate()
		if not pick.is_empty() and pick.has("item"):
			var root_node: Node3D = pick.item.get("root")
			if focus == root_node: return true
	return false

func escape_menu() -> void:
	for attempt in 3:
		if not menu.is_open(): break
		await key(KEY_ESCAPE)
		await create_timer(0.20).timeout
	check(not menu.is_open(), "Esc 退出世界菜单")
	check(not main.hover._near_progress.visible, "菜单收起后近距进度条保持收起")
	if main.hover._near_icon.visible:
		check(near_focus_is_legal(), "菜单收起后近距图标绑定合法焦点来源")
		var expected: Vector3 = near_focus_expected_point(main.hover.keyboard_focus)
		var expected_screen: Vector2 = main.cam.unproject_position(expected)
		var icon_center: Vector2 = main.hover._near_icon.position + main.hover._near_icon.size * 0.5
		check(icon_center.distance_to(expected_screen) < 60.0, "菜单收起后近距图标仍贴近合法目标")
	else:
		check(main.hover.keyboard_focus == null, "菜单收起后没有陈旧近距焦点绑定")
	check(not main.hud.menu.active and not paused, "Esc 不穿透到系统暂停")

## 定位夹具：只恢复角色位置与镜头，不指定交互焦点，不动作物状态。
func stand_fixture(at: Vector3) -> void:
	main.actor_controller.restore_pose({"mode":0,"player":[at.x,at.y,at.z]})
	main._reach_cache.clear()
	main.hover._reach_cache.clear()
	await frames(12)

func farm_fixture() -> void:
	main.restore_world_state({"zone":"zone5","landing":"main","mode":0,
		"player":[farm_center.x,farm_center.y,farm_center.z],"far_sea":false})
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.cam.global_position = farm_center + Vector3(-6,11,12)
	main.cam.look_at(farm_center)
	main.cam.fov = 40
	main._reach_cache.clear()
	main.hover._reach_cache.clear()
	await frames(12)

func lock(spot: Node3D) -> bool:
	var focus: Vector3 = spot.focus_position()
	actor.rotation.y = atan2(focus.x - actor.global_position.x, focus.z - actor.global_position.z)
	await frames(10)
	for attempt in 36:
		if main.interactor.target == spot:
			check(spot.focused, "世界目标获得焦点 " + str(spot.id))
			await frames(2)
			check(main.hover.keyboard_focus == spot, "近距焦点图标绑定目标 " + str(spot.id))
			check(main.hover._near_icon != null and main.hover._near_icon.visible, "近距焦点图标可见 " + str(spot.id))
			var expected_screen: Vector2 = main.cam.unproject_position(spot.focus_position() + Vector3.UP * 0.85)
			var icon_center: Vector2 = main.hover._near_icon.position + main.hover._near_icon.size * 0.5
			check(icon_center.distance_to(expected_screen) < 60.0, "近距图标贴近模型投影 " + str(spot.id))
			return true
		await key(KEY_Q)
		await frames(1)
	check(false, "Q 循环能够锁定 " + str(spot.id))
	return false

func open_plot(plot: Node3D, hold_after_open := false) -> bool:
	if menu.is_open(): await escape_menu()
	if not await lock(plot): return false
	var state_before: Dictionary = farm.state(str(plot.plot_id))
	var count_before := acted.size()
	max_progress = 0.0
	saw_character_progress = false
	send(KEY_E, true, true)
	check(Input.is_action_pressed("interact"), "E 按下进入全局 Input")
	check(main.interactor.target == plot and main.actor_controller.state_id() == "ashore_idle",
		"Q 已锁定地格后 E 不得被上下船抢走或清除焦点")
	var opened := await until(func(): return menu.active, 3.0, "E 按住打开地格菜单")
	if opened:
		# 2026-11-07 契约变更：种植区改**触发式**，按一下就执行，不再要求读条。
		# 所以这里反过来验：一次按下立刻出菜单，且全程没有进度条/头顶读数。
		# 旧的「max_progress > 0」是读条时代的断言，已经不再成立。
		check(is_zero_approx(max_progress) and not saw_character_progress,
			"触发式交互不读条：按一下就开菜单，没有进度条")
		check(not main.hover._near_icon.visible and not main.hover._near_progress.visible, "菜单出现后近距图标与进度条一起收起")
		check(farm.state(str(plot.plot_id)) == state_before and acted.size() == count_before, "E 开菜单不偷做种植业务")
		check(menu.hint_label != null and menu.hint_label.text.contains(farm.status_text(str(plot.plot_id))), "一级标题包含当前地格状态")
		await assert_menu_layout("一级菜单")
		menu_focus("一级菜单")
		var generation: int = menu.generation
		var position_before: Vector3 = actor.global_position
		await held_key(KEY_DOWN, 0.10)
		await held_key(KEY_UP, 0.10)
		send(KEY_E, true, true, true)
		await create_timer(0.65).timeout
		var held_reopened: bool = not menu.active or menu.generation != generation or entry_index("seed:lettuce") >= 0
		if held_reopened:
			var ids: Array = []
			for entry in menu.entries: ids.append(str(entry.get("id", "")))
			print("[keyboard-farm-e-diagnostic] generation_before=", generation,
				" generation_now=", menu.generation, " active=", menu.active,
				" selected_index=", menu.selected_index, " entries=", ids,
				" E=", Input.is_action_pressed("interact"), " held_keys=", main.hud.world_actions._held_keys,
				" interactor_target=", main.interactor.target, " interactor_hold=", main.interactor.hold,
				" require_release=", main.interactor._wait_release)
		check(not held_reopened, "E 持续按住不连触发二级或重开菜单")
		check(actor.global_position.distance_to(position_before) < 0.02, "气泡方向键与长按不穿透世界移动")
		check(is_zero_approx(main.interactor.progress()), "菜单接管后世界 hold 归零")
	if not hold_after_open or not opened:
		send(KEY_E, false, true)
		await frames(2)
		check(not Input.is_action_pressed("interact"), "E 松开清除全局 Input")
	return opened

func begin_action_measure() -> void:
	max_progress = 0.0
	saw_character_progress = false

func action_feedback(event: String, clip: String, before_acted: int, before_starts: int) -> bool:
	var completed := await until(func(): return acted.size() > before_acted, 7.0, "键盘命令真正执行 " + event)
	if not completed: return false
	check(acted.size() == before_acted + 1 and str(acted.back()[1]) == event, "业务成功事件恰好一次 " + event)
	check(starts.size() == before_starts + 1 and str(starts.back()[0]) == clip, "成功动作恰好一次且类型正确 " + clip)
	check(str(actor.action_playback().get("id", "")) == clip, "角色播放成功动作 " + clip)
	# 2026-11-07 契约变更：命令式动作是触发式，执行过程不压读条。
	# 角色动作本身（上一行）仍然要播，进度条不应出现。
	check(is_zero_approx(max_progress) and not saw_character_progress,
		"命令式动作不读条：确认即执行，没有进度条 " + event)
	check(main.hud.visible and main.hud._toast_box.visible, "业务反馈 HUD 可见 " + event)
	var expected := {"planted":"播下", "watered":"浇水", "harvested":"收获"}
	check(main.hud._toast.text.contains(expected[event]) and main.hud._toast.text.contains("生菜"), "HUD 反馈明确动作与作物 " + event)
	check(not menu.active and is_zero_approx(main.interactor.progress()), "成功释放菜单与 hold " + event)
	check(not main.hover._near_progress.visible, "成功后近距进度条不残留 " + event)
	return true

func debug_failure(label: String) -> void:
	var ids: Array = []
	for entry in menu.entries: ids.append(str(entry.get("id", "")))
	print("[keyboard-farm-failure] ", label,
		" actor_state=", main.actor_controller.state_id(),
		" actor_pos=", actor.global_position,
		" walking=", main.actor_controller.walking(),
		" auto_target=", main.actor_controller.auto_target,
		" interactor_active=", main.interactor.active,
		" interactor_target=", main.interactor.target,
		" interactor_hold=", main.interactor.hold,
		" interactor_progress=", main.interactor.progress(),
		" auto_hold=", main.interactor.auto_hold,
		" selected_command=", main.interactor.selected_command.is_valid(),
		" last_blocked=", main.interactor.last_blocked,
		" menu_active=", menu.active,
		" menu_generation=", menu.generation,
		" menu_entries=", ids,
		" menu_selected=", menu.selected_index,
		" E=", Input.is_action_pressed("interact"),
		" held_keys=", menu._held_keys,
		" toast=", main.hud._toast.text,
		" hover_focus=", main.hover.keyboard_focus)

func idle_feedback() -> bool:
	var settled := await until(func(): return actor.action_playback().is_empty() and main.actor_controller.auto_target == null, 4.0, "动作及自动接近自然结束")
	if not settled: debug_failure("idle_feedback timeout")
	await frames(2)
	var idle: bool = main.actor_controller.state_id() == "ashore_idle"
	if not idle: debug_failure("not ashore_idle")
	check(idle, "业务完成后回到岸上待机")
	var released: bool = not main.interactor.auto_hold and not main.interactor.selected_command.is_valid()
	if not released: debug_failure("interaction command residue")
	check(released, "无残留自动按住及待执行命令")
	return settled and idle and released

func plant_keyboard(plot: Node3D, keep_e := false) -> bool:
	if not await open_plot(plot, keep_e): return false
	var seeds: int = economy.count("lettuce_seed")
	var before_acted := acted.size()
	var before_starts := starts.size()
	if not await choose("plant"): return false
	check(menu.active and entry_index("seed:lettuce") >= 0 and farm.is_empty(str(plot.plot_id)), "Enter 种植只进入种子二级，不提前播种")
	check(menu.hint_label != null and menu.hint_label.text.contains("选择种子"), "二级标题明确选择种子")
	var seed_index := entry_index("seed:lettuce")
	if seed_index >= 0:
		check(str(menu.entries[seed_index].get("caption", "")).contains("×" + str(seeds)), "二级显示真实生菜种子余量")
	begin_action_measure()
	if not await choose("seed:lettuce"): return false
	var ok := await action_feedback("planted", "planting", before_acted, before_starts)
	check(farm.crop_of(str(plot.plot_id)) == "lettuce" and farm.phase(str(plot.plot_id)) == "growing", "真实种下生菜，进入生长态")
	check(float(farm.state(str(plot.plot_id)).remaining) == 3.0 and float(farm.state(str(plot.plot_id)).water) == 0.0, "初种三天且土壤未浇水")
	check(economy.count("lettuce_seed") == seeds - 1, "实际播种只扣一包种子")
	if keep_e:
		await create_timer(0.75).timeout
		check(not menu.active and acted.size() == before_acted + 1 and starts.size() == before_starts + 1, "E 跨菜单确认仍按住也不自动照料/重开/重复动作")
		send(KEY_E, false, true)
	await shot("planted")
	await idle_feedback()
	return ok

func water_keyboard(plot: Node3D, refill := false) -> bool:
	if not await open_plot(plot): return false
	var index := entry_index("water")
	if index < 0:
		check(false, "缺水地格提供浇水项")
		return false
	check(str(menu.entries[index].get("label", "")) == ("补水并浇水" if refill else "浇水"), "水壶状态对应正确动作标签")
	var water_before: int = farm.watering_can
	var before_acted := acted.size()
	var before_starts := starts.size()
	begin_action_measure()
	if not await choose("water", KEY_E): return false
	var ok := await action_feedback("watered", "watering", before_acted, before_starts)
	check(float(farm.state(str(plot.plot_id)).water) == 1.0 and not farm.is_dry(str(plot.plot_id)), "浇水真正改变目标土壤")
	check(farm.watering_can == (farm.WATER_CAPACITY - 1 if refill else water_before - 1), "浇水/补水并浇水准确扣一份水")
	check(farm.status_text(str(plot.plot_id)).contains("今日已浇"), "湿润地格状态反馈更新")
	await shot("refill-watered" if refill else "watered")
	await idle_feedback()
	return ok

func cancel_and_missing(plot: Node3D) -> void:
	if not await open_plot(plot): return
	var seeds: int = economy.count("lettuce_seed")
	var business: Dictionary = farm.state(str(plot.plot_id))
	var before_starts := starts.size()
	var before_acted := acted.size()
	if not await choose("plant"): return
	await key(KEY_ESCAPE)
	check(menu.active and entry_index("plant") >= 0 and entry_index("seed:lettuce") < 0, "二级 Esc 返回同格一级，不关闭整层")
	menu_focus("二级返回一级")
	await escape_menu()
	check(economy.count("lettuce_seed") == seeds and farm.state(str(plot.plot_id)) == business, "取消不扣种子不改变空地")
	check(starts.size() == before_starts and acted.size() == before_acted, "取消不假报业务/动作成功")
	# 库存夹具：在二级已展示之后移除资源，验收执行边界再次检查，而非只看灰项。
	if not await open_plot(plot): return
	if not await choose("plant"): return
	economy.inventory.set_count("lettuce_seed", 0)
	begin_action_measure()
	if await choose("seed:lettuce"):
		var blocked_seen := await until(func(): return not main.interactor.last_blocked.is_empty(), 7.0, "过期种子菜单执行时报告缺种")
		if not blocked_seen: debug_failure("expired seed did not reach blocked")
		check(main.interactor.last_blocked.contains("缺少") and main.hud._toast.text.contains("种子"), "缺种失败反馈包含明确原因")
		check(farm.state(str(plot.plot_id)) == business and economy.count("lettuce_seed") == 0, "缺种失败不假播种")
		check(starts.size() == before_starts and acted.size() == before_acted and actor._item_receive.prop == null, "缺种失败不启动成功动作或举物")
		check(actor.action_playback().is_empty() and not main.pickup_progress.bar.visible, "缺种失败不启动角色成功动作或头顶进度")
	await idle_feedback()
	if await open_plot(plot):
		var index := entry_index("plant")
		check(index >= 0 and str(menu.entries[index].get("blocked", "")).contains("种子"), "没有种子时一级灰项解释原因")
		if index >= 0: check(not bool(menu.buttons[index].available), "缺种子气泡真实灰显")
		await choose("plant")
		check(farm.state(str(plot.plot_id)) == business and starts.size() == before_starts, "确认缺种灰项不假成功")
		await escape_menu()
	economy.inventory.set_count("lettuce_seed", seeds)

func repeated_water(plot: Node3D) -> void:
	if not await open_plot(plot): return
	var index := entry_index("water")
	check(index >= 0, "已浇地格仍提供可解释的浇水项")
	if index < 0: return
	var reason := str(menu.entries[index].get("blocked", ""))
	check(reason.contains("已经浇") or reason.contains("已浇"), "重复浇水灰项明确说明今天已浇")
	check(not bool(menu.buttons[index].available), "重复浇水气泡灰显")
	var state: Dictionary = farm.state(str(plot.plot_id))
	var water: int = farm.watering_can
	var before_acted := acted.size()
	var before_starts := starts.size()
	await choose("water")
	check(menu.active and main.hud._toast.text.contains(reason), "确认灰项留在菜单并显示具体原因")
	check(farm.state(str(plot.plot_id)) == state and farm.watering_can == water, "重复浇水不改土壤且不扣水")
	check(acted.size() == before_acted and starts.size() == before_starts, "重复浇水不发成功事件/动作")
	menu_focus("重复浇水拒绝后")
	await shot("already-watered")
	await escape_menu()

func sleep_keyboard(day_index: int) -> bool:
	# 跨区定位夹具不代替进屋/睡觉；实际房门与床都用 Q + E 完成。
	var door: Node3D = main._zone_nodes.zone1.get_node("Objects/RoomDoor")
	var at: Vector3 = main.room_controller.exit_position
	main.restore_world_state({"zone":"zone1","landing":"main","mode":0,"player":[at.x,at.y,at.z],"far_sea":false})
	main.cam.set_process(true)
	await frames(12)
	if not await lock(door): return false
	var day: int = main.world_clock.day
	var remaining: float = farm.state(IDS[0]).remaining
	send(KEY_E, true, true)
	var entered := await until(func(): return main.room_service.inside or menu.active, 4.0, "键盘房门触发进屋")
	send(KEY_E, false, true)
	if not entered: return false
	if menu.active:
		if not await choose("interact"): return false
	if not await until(func(): return main.room_service.inside and not main.room_controller.busy, 6.0, "真实圆幕后进入房间"): return false
	check(main.hud._room_mode and main.hud._room_exit.visible and main.world_clock.day == day, "进屋 HUD 切为室内且不偷推进天数")
	var bed: Node3D = main.room.get_node("Furnishings/Bed")
	await stand_fixture(main.room.wake_position())
	if not await lock(bed): return false
	send(KEY_E, true, true)
	var requested := await until(func(): return main.sleep_cycle.busy or menu.active, 4.0, "键盘床铺触发睡觉")
	send(KEY_E, false, true)
	if not requested: return false
	if menu.active:
		if not await choose("interact"): return false
	if not await until(func(): return main.sleep_cycle.busy, 5.0, "床铺键盘命令真正开始睡眠"): return false
	check(main.input_blocked() and main.actor_controller.state_id() == "sleeping" and not main.hud.visible, "睡眠态锁输入并隐藏 HUD")
	await key(KEY_ESCAPE)
	check(not main.hud.menu.active and not paused, "睡眠中的 Esc 不穿透暂停")
	if not await until(func(): return not main.sleep_cycle.busy, 14.0, "真实睡眠过场结束"): return false
	check(main.world_clock.day == day + 1 and is_equal_approx(float(main.world_clock.query().hour), 6.0), "键盘睡觉只推进一天并醒于06:00")
	check(float(farm.state(IDS[0]).remaining) == remaining - 1.0 and float(farm.state(IDS[0]).water) == 0.0, "醒来即生长一天并清水 第" + str(day_index))
	check(main.room_service.inside and main.hud.visible and not main.input_blocked(), "醒来仍在室内且 HUD/输入恢复")
	check(main._calendar_label.text.contains("06:00") and main.actor_controller.state_id() == "ashore_idle", "醒来日历与角色待机同步")
	await shot("wake-" + str(day_index))
	# 醒来后用真实 X 键退出，不调用 room_controller.exit 夹具。
	# 同时把 E 保持按下到 X 路由完成，守住「X 与持续 E 不互相误触」：
	# X 必须进入 room_exit，E 不得打开床菜单、重新睡觉或产生种植业务。
	var before_acted := acted.size()
	var before_starts := starts.size()
	send(KEY_E, true, true)
	send(KEY_X, true)
	send(KEY_X, false)
	var left := await until(func(): return not main.room_service.inside and not main.room_controller.busy, 6.0, "真实 X 键退出房间完成")
	send(KEY_E, false, true)
	if not left: return false
	await frames(4)
	check(root.get_node("GameState").current_zone == "zone1", "真实 X 退出回到 zone1")
	check(not main.room_service.inside and not main.hud._room_mode, "真实 X 恢复室外房间状态")
	check(not main.hud._room_exit.visible and main.hud.corner.toolbar.visible, "真实 X 恢复室外 HUD")
	check(not menu.is_open() and not main.sleep_cycle.busy, "X 与持续 E 不打开菜单或再次睡觉")
	check(acted.size() == before_acted and starts.size() == before_starts, "X 与持续 E 不产生额外种植业务/动作")
	return true

func harvest_keyboard(plot: Node3D) -> bool:
	# 满包夹具：精确填满全部格，原库存随后还原；绝不改成熟作物。
	var inventory: Dictionary = economy.inventory.to_dict()
	economy.inventory.set_count("vegetable", 0)
	economy.inventory.set_count("wood", 0)
	economy.inventory.set_count("wood", economy.inventory.slots_free() * Items.stack_limit("wood"))
	check(economy.inventory.slots_used() == economy.inventory.capacity(), "满包夹具恰好占满而非越界超量")
	check(not economy.inventory.can_add("vegetable", 2), "满包拒绝前置确实无收获容量")
	var state: Dictionary = farm.state(str(plot.plot_id))
	var before_starts := starts.size()
	var before_acted := acted.size()
	if await open_plot(plot):
		var index := entry_index("harvest")
		check(index >= 0 and str(menu.entries[index].get("blocked", "")).contains("满"), "满包收获灰项明确原因")
		await choose("harvest")
		check(farm.state(str(plot.plot_id)) == state and farm.phase(str(plot.plot_id)) == "ready", "满包拒绝保留完整成熟状态")
		check(economy.count("vegetable") == 0 and starts.size() == before_starts and acted.size() == before_acted, "满包失败不发奖励/成功动作")
		check(actor._item_receive.prop == null and main.hud._toast.text.contains("满"), "满包只反馈原因，不假举物")
		await shot("full-bag")
		await escape_menu()
	economy.inventory.from_dict(inventory)
	if not await open_plot(plot): return false
	var vegetables: int = economy.count("vegetable")
	var seeds: int = economy.count("lettuce_seed")
	begin_action_measure()
	if not await choose("harvest"): return false
	if not await action_feedback("harvested", "harvesting", before_acted, before_starts): return false
	var reward: Dictionary = farm.yield_of("lettuce")
	check(farm.is_empty(str(plot.plot_id)) and economy.count("vegetable") == vegetables + int(reward.get("vegetable", 0)), "收获清空地格并按原产量入包一次")
	check(actor._item_receive.prop != null and actor._item_receive.prop.get_meta("crop_id", "") == "lettuce", "实际举起正确生菜模型")
	var overhead := await until(func():
		return actor._item_receive.prop != null and actor._item_receive.prop.visible and actor._item_receive.prop.position.y > 1.5 * Dimensions.SCALE,
		2.0, "成功生菜实物举过帽顶")
	if overhead: await shot("harvest-overhead")
	await idle_feedback()
	check(actor._item_receive.prop == null, "举物动画结束清理临时模型")
	check(economy.count("vegetable") == vegetables + int(reward.get("vegetable", 0)) and economy.count("lettuce_seed") == seeds, "举物表现不重复奖励不扣种子")
	check(starts.size() == before_starts + 1 and acted.size() == before_acted + 1, "收获全过程只有一次成功反馈")
	return true

func run() -> void:
	var scene = load("res://scenes/main.tscn")
	check(scene != null, "真实 main.tscn 可加载")
	if scene == null:
		finish()
		return
	main = scene.instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	main._enter_game()
	economy = root.get_node("Economy")
	economy.ticking = false
	farm = economy.farm
	actor = main.player
	menu = main.hud.world_actions
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	# 初始时间夹具只设日历水位线；此后每一次生长必须来自真实床铺键盘睡眠。
	main.world_clock.from_dict({"day":10,"seconds":12.0*3600.0,"day_length":main.world_clock.day_length})
	economy.daily._last_morning = 10
	farm.sync_calendar_day(10)
	farm.grow_day = 10
	economy.inventory.set_count("lettuce_seed", 9)
	farm.watering_can = farm.WATER_CAPACITY
	actor.action_started.connect(func(id, token): starts.append([id, token]))
	main.farm_field.acted.connect(func(id, event, payload): acted.append([id, event, payload.duplicate(true)]))
	main.interactor.completed.connect(func(spot, result): completions.append([str(spot.id), result.duplicate(true)]))
	main.interactor.progress_changed.connect(func(value): max_progress = maxf(max_progress, float(value)))
	process_frame.connect(func():
		if main != null and is_instance_valid(main) and main.hover != null:
			var bar: Variant = main.hover._near_progress
			if bar != null and bar.visible and float(bar.get("ratio")) > 0.0:
				saw_character_progress = true)
	await frames(20)
	await until(func(): return not main._title_active, 3.0, "标题过场结束")
	check(not main._title_active and main.hud.visible and not main.hud.is_panel_open(), "游戏已开始且没有夹具残留面板")
	for id: String in IDS:
		var plot: Node3D = main.farm_field.find(id)
		check(plot != null and farm.is_empty(id), "初始六格存在且为空 " + id)
		if plot == null:
			finish()
			return
		farm_center += plot.global_position / float(IDS.size())
	await farm_fixture()
	var seen: Dictionary = {}
	var scan_position: Vector3 = actor.global_position
	# 新正面契约：同站位可以转身面对各格，再用真实Q逐项选择；
	# 不能在上一次Q前采样焦点，轮换面向后凭空期望背面两格也被记录。
	for id: String in IDS:
		var scan_plot: Node3D = main.farm_field.find(id)
		var selected := await lock(scan_plot)
		check(selected and main.interactor.target == scan_plot and scan_plot.focused,
			"转身面向后Q可锁定独立地格 " + id)
		check(actor.global_position.distance_to(scan_position) < 0.01, "六格切换不偷移玩家 " + id)
		if selected: seen[id] = true
	for id: String in IDS: check(seen.has(id), "六格均有正面键盘入口 " + id)
	check(acted.is_empty() and starts.is_empty(), "Q 切目标不触发业务或成功动作")
	var plot: Node3D = main.farm_field.find(IDS[0])
	var spare: Node3D = main.farm_field.find(IDS[1])
	await cancel_and_missing(spare)
	if not await plant_keyboard(plot, true):
		finish()
		return
	if not await water_keyboard(plot):
		finish()
		return
	await repeated_water(plot)
	for day_index in range(1, 4):
		if not await sleep_keyboard(day_index):
			finish()
			return
		await farm_fixture()
		check(plot.current_stage() == day_index, "真实作物模型阶段随第%d次醒来更新" % day_index)
		if day_index < 3:
			if day_index == 1:
				# 只将水壶置空作为资源夹具，不直接补水/浇水/生长。
				farm.watering_can = 0
			if not await water_keyboard(plot, day_index == 1):
				finish()
				return
	check(farm.phase(str(plot.plot_id)) == "ready" and farm.progress(str(plot.plot_id)) == 1.0, "三个真实睡眠浇水日后成熟，非调试生长")
	if not await harvest_keyboard(plot):
		finish()
		return
	if not await plant_keyboard(plot):
		finish()
		return
	check(farm.crop_of(str(plot.plot_id)) == "lettuce" and float(farm.state(str(plot.plot_id)).remaining) == 3.0, "收获后键盘再次播种开启新周期")
	for id: String in IDS:
		if id != IDS[0]: check(farm.is_empty(id), "全流程未误操作邻格 " + id)
	finish()

func finish() -> void:
	for code in down_keys.keys(): send(int(code), false, true)
	print("[keyboard-farm-loop] ", checks, " checks, ", failures, " failures")
	if main != null and is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(0 if failures == 0 else 1)
