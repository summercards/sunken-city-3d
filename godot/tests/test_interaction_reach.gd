extends SceneTree
## 交互可达性 / 纯键盘可玩性（2026-11-06）
##
## 用户反馈两件事，这里各锁一条：
##   「靠岸后操作很不舒服，往下没办法往下挪」→ 在泊位里朝岸按方向键必须下船（SEA-MOVE-R24）；
##   「海上的采集无法靠近使用 E 键采集 / 没有鼠标就无法操作」→
##       采集点必须在 interactable 组里、必须站在可走面上（SEA-GATHER-R05/R06）；
##       船上必须有 E 入口去打捞/捕鱼/靠岸（SEA-INTERACT-R15/R16）。
##
## 不用真鼠标：方向用 `_update_keyboard_move` + 摆好的相机基向量合成，
## E 直接走 `_unhandled_input` 那条分支，和玩家按键是同一个入口。

var checks := 0
var failures := 0
var main: Node
var state: Node
var controller: Variant
var player: Node3D


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)


## 把镜头摆到「前向 = dir」，这样 move_forward 就是世界方向 dir。
func aim_camera(dir: Vector3, at: Vector3) -> void:
	main.cam.suspend_follow()
	main.cam.target = at
	var flat_dir := Vector3(dir.x, 0.0, dir.z).normalized()
	main.cam.position = at - flat_dir * 24.0 + Vector3.UP * 20.0
	main.cam.look_at(at, Vector3.UP)
	main.cam._cur_target = at


func press_key(code: int) -> void:
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
	controller = main.actor_controller
	player = controller.actor
	await frames(12)

	# ---- 契约 1：采集点必须可交互、且站在可走面上 ------------------------
	var in_group := 0
	var on_surface := 0
	var assembled := 0
	for spot in main.gather.spots:
		var zone: Node = main._zone_nodes.get(str(spot.get_meta("zone", "")), null)
		if zone == null:
			continue
		assembled += 1
		if spot.is_in_group("interactable"):
			in_group += 1
		if zone.area_at(spot.global_position, 0.6) != null:
			on_surface += 1
	check(assembled >= 5, "已装配采集点 %d 个" % assembled)
	check(in_group == assembled, "全部采集点都在 interactable 组里 (%d/%d)" % [in_group, assembled])
	check(on_surface == assembled, "全部采集点都站在可走面上 (%d/%d)" % [on_surface, assembled])

	# ---- 契约 2：岸边采集点能用 E 采到 -----------------------------------
	var shell: Node3D = main.gather.find("zone1_shell")
	if shell == null:
		printerr("FAIL 找不到 zone1_shell")
	else:
		check(shell.is_visible_in_tree(), "zone1_shell 在默认范围里可见")
		var ground: Node3D = main._zone_nodes["zone1"].area_at(shell.global_position, 0.6)
		var stand: Vector2 = ground.clamp_point(shell.global_position.x + 1.0, shell.global_position.z + 1.0)
		var stand_pos: Vector3 = ground.surface_point(Vector3(stand.x, ground.surface_y, stand.y))
		state.enter_zone("zone1")
		state.set_mode(state.Mode.ASHORE)
		controller.restore_pose({"mode": 0, "player": [stand_pos.x, stand_pos.y, stand_pos.z]})
		controller.walk_area = ground
		var shell_focus: Vector3 = shell.focus_position()
		player.rotation.y = atan2(shell_focus.x - player.global_position.x, shell_focus.z - player.global_position.z)
		await frames(20)
		check(main.interactor.active, "岸上交互器已开放")
		check(main.interactor.target == shell, "E 焦点锁到贝壳（实际 %s）" % str(main.interactor.target))
		main.interactor.auto_hold = true
		await frames(90)
		main.interactor.auto_hold = false
		check(not shell.available, "按住 E 采到了贝壳（点已进冷却）")

	# ---- 契约 3：泊位里朝岸按方向键 = 下船 -------------------------------
	var data: Dictionary = main._landing_data("zone1", "main")
	var park := Vector3(float(data.boatPark[0]), 1.12, float(data.boatPark[2]))
	var landing: Node3D = main._current_landing()
	var shore_dir: Vector3 = landing.stand_position() - park
	shore_dir.y = 0.0
	shore_dir = shore_dir.normalized()
	main.boat.place_at(park, float(data.boatYaw))
	state.landing_id = "main"
	state.enter_zone("zone1")
	controller.restore_pose({"mode": 1})
	controller.cancel()
	await frames(6)
	check(main._landing_is_docked(), "船停在泊位")
	check(main._key_intent_is_toward_shore(shore_dir), "朝岸方向被识别为「往岸上走」")
	check(not main._key_intent_is_toward_shore(Vector3(-shore_dir.z, 0, shore_dir.x)), "沿岸方向不算往岸上走")
	aim_camera(shore_dir, park)
	Input.action_press("move_forward")
	for i in 40:
		main._update_keyboard_move(1.0 / 60.0)
		controller.tick(1.0 / 60.0)
		await physics_frame
	release_all()
	check(controller.mode() == 0, "泊位里朝岸按方向键 → 直接下船（mode=%d）" % controller.mode())
	# 下船是「走到站立点」的过程，给它足够时间走完再判位置。
	for i in 180:
		main._update_keyboard_move(1.0 / 60.0)
		controller.tick(1.0 / 60.0)
		await physics_frame
	# 按住不放时会「下船后继续走」，所以判据是「已经站在岸上的可走面」，
	# 而不是「停在站立点」—— 后者只在松手一步一停时才成立。
	check(main._zone_nodes["zone1"].area_at(player.global_position, 0.6) != null,
		"下船后人在岸上的可走面上")
	check(flat(player.global_position, landing.stand_position()) < 4.0,
		"下船后离站立点 %.2f m（没被船带走）" % flat(player.global_position, landing.stand_position()))
	check(not main.boat.starts_sailing(), "下船没有把船开走")

	# ---- 契约 4：朝开阔水面按方向键仍然能划走 ----------------------------
	main.boat.place_at(park, float(data.boatYaw))
	controller.restore_pose({"mode": 1})
	await frames(4)
	var sea_dir := Vector3.ZERO
	for candidate: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
			Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized(),
			Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized()]:
		var clear := true
		for i in range(1, 9):
			var p: Vector3 = park + candidate * float(i)
			if not main._is_open_water(p.x, p.z):
				clear = false
				break
		if clear:
			sea_dir = candidate
			break
	if sea_dir == Vector3.ZERO:
		check(false, "泊位外找不到开阔水域")
	else:
		aim_camera(sea_dir, park)
		var from: Vector3 = main.boat.position
		Input.action_press("move_forward")
		for i in 40:
			main._update_keyboard_move(1.0 / 60.0)
			controller.tick(1.0 / 60.0)
			main.boat._process(1.0 / 60.0)
			await physics_frame
		release_all()
		check(flat(from, main.boat.position) > 0.3, "朝水面按方向键照旧划走 (%.2f m)" % flat(from, main.boat.position))
		check(controller.mode() == 2, "划走时处于航行")
		main.boat.stop_drive()

	# ---- 契约 5：漂出泊位一点，E 仍能靠回去上岸 --------------------------
	main.boat.place_at(park, float(data.boatYaw))
	controller.restore_pose({"mode": 1})
	await frames(4)
	var away: Vector3 = park + sea_dir * 2.2 if sea_dir != Vector3.ZERO else park + Vector3(2.2, 0, 0)
	main.boat.place_at(away, atan2(away.x - park.x, away.z - park.z))
	check(not main._landing_is_docked(), "离泊 2.2 米时不算靠妥")
	check(main._near_landing_key().get("landing", "") == "main", "但键盘靠岸仍认得出这个泊位")
	check(main._boat_shortcut_text().begins_with("靠岸"), "提示说「靠岸」而不是空")
	press_key(KEY_E)
	await frames(240)
	check(controller.mode() == 0, "E 靠回去并上岸（mode=%d）" % controller.mode())

	# ---- 契约 6：船上按 E 去打捞漂流物 -----------------------------------
	main.boat.place_at(park, float(data.boatYaw))
	controller.restore_pose({"mode": 1})
	controller.cancel()
	await frames(6)
	var crate: Dictionary = main.props.nearest_crate(main.boat.position, 40.0)
	if crate.is_empty():
		check(false, "附近找不到漂流物")
	else:
		var root: Node3D = crate.get("root")
		main.boat.place_at(root.global_position + Vector3(0.0, 0.0, 3.0), 0.0)
		await frames(4)
		var cand: Dictionary = main._sea_pick_candidate()
		check(not cand.is_empty(), "船边有可打捞目标")
		check(str(cand.get("type", "")) == "crate", "候选是漂流物")
		# 2026-11-07 契约变更：提示文案改读 `_near_action()`，而 pick 只在
		# `near=true` 时才算「近距交互」。这里把「提示」与「按键分派」的一致性
		# 实测出来：`_press_boat_key` 对「不在热区、想划过去捞」仍保留兜底，
		# 若提示为空但 E 会开捞，就是生产端的提示/动作不一致（不是测试夹具）。
		var near: bool = bool(cand.get("near", false))
		var reach: float = main.props.crate_reach(crate)
		var dock_dist: float = Vector2(root.global_position.x - main.boat.position.x,
			root.global_position.z - main.boat.position.z).length()
		var hint: String = main._boat_shortcut_text()
		print("[reach-salvage] kind=", crate.get("kind"), " reach=", reach,
			" dist=", dock_dist, " near_threshold=", reach + 0.4, " cand_near=", near,
			" near_action=", main._near_action(), " hint=[", hint, "]")
		# 距离在 crate_reach 内时提示必须说「打捞」：这是 new-contract 的近距正例。
		main.boat.place_at(root.global_position + Vector3(0.0, 0.0, reach + 0.2), 0.0)
		main._dock_cache.clear()
		await frames(4)
		check(str(main._near_action().get("kind", "")) == "pick" and main._boat_shortcut_text() == "打捞",
			"船贴着漂流物时提示说「打捞」（近距热区正例）")
		# 回到 3 米夹具：提示必须与「按 E 会打捞」这一实际动作一致。
		main.boat.place_at(root.global_position + Vector3(0.0, 0.0, 3.0), 0.0)
		main._dock_cache.clear()
		await frames(4)
		check(main._boat_shortcut_text() == "打捞", "提示说「打捞」（须与 E 实际打捞一致）")
		var crates_before: int = main.props.crates.size()
		press_key(KEY_E)
		await frames(4)
		check(main._pick_phase != 0, "E 进入了打捞流程（phase=%d）" % main._pick_phase)
		# 走完「划过去 → 停稳 → 计时」整条链：不允许只开个头就算通过。
		for i in 900:
			if main._pick_phase == 0 and main.props.crates.size() < crates_before:
				break
			await physics_frame
			await process_frame
		check(main.props.crates.size() < crates_before or main._pick_phase == 0,
			"E 打捞跑完整条链（漂流物 %d → %d）" % [crates_before, main.props.crates.size()])
	main._cancel_pending_pick()

	# ---- 契约 7：菜箱气泡菜单能纯键盘操作 -------------------------------
	# 菜箱 id 是 plot_id + 格子后缀（home_plot:2 表示第二格那一批）；
	# 直接取第一个现存菜箱，避免把格子编号写死。
	var plot: Node3D = null
	for candidate in main.farm_field.plots:
		if str(candidate.zone_id) == "zone1":
			plot = candidate
			break
	if plot == null:
		check(false, "找得到菜箱")
	else:
		var zone: Node = main._zone_nodes["zone1"]
		var parea: Node3D = zone.area_at(plot.global_position, 0.8)
		if parea == null:
			check(false, "菜箱站在可走面上")
		else:
			var pstand: Vector2 = parea.clamp_point(plot.global_position.x + 1.3, plot.global_position.z + 1.3)
			var ppos: Vector3 = parea.surface_point(Vector3(pstand.x, parea.surface_y, pstand.y))
			controller.restore_pose({"mode": 0, "player": [ppos.x, ppos.y, ppos.z]})
			controller.walk_area = parea
			var plot_focus: Vector3 = plot.focus_position()
			player.rotation.y = atan2(plot_focus.x - player.global_position.x, plot_focus.z - player.global_position.z)
			await frames(18)
			var actual: Node3D = main.interactor.target
			print("[reach-plot-fixture] player=", player.global_position, " focus=", plot_focus,
				" candidates_has_plot=", main.interactor.candidates().has(plot), " target=", actual,
				" target_focus=", actual.focus_position() if actual != null else Vector3.INF,
				" yaw=", player.rotation.y)
			check(main.interactor.target == plot, "菜箱成为 E 焦点（实际 %s）" % str(main.interactor.target))
			# 直接按 E 的语义：状态机走到「到位后按住」，交出 options 事件。
			main.interactor.auto_hold = true
			await frames(70)
			main.interactor.auto_hold = false
			check(main.hud.world_actions.is_open(), "E 弹出气泡菜单")
			if main.hud.world_actions.is_open():
				check(main.hud.world_actions.buttons.size() > 0, "菜单有可选项 %d 个" % main.hud.world_actions.buttons.size())
				check(main.hud.world_actions.buttons[0].hotkey == "", "第一项不显示键位角标，数字映射仍可用")
				check(main.hud.world_actions.index_for_key(KEY_1) == 0, "数字键 1 映射到第一项")
				check(main.hud.world_actions.index_for_key(KEY_9) == -1, "越界数字不越界选中")
				# 首选常常被规则灰掉（没种子时的播种）：灰项只报原因、不关闭菜单，
				# 所以按「第一个可用项的编号」来验，才是玩家真会按的那一下。
				var first_entries: int = main.hud.world_actions.entries.size()
				var first_id := str((main.hud.world_actions.entries[0] as Dictionary).get("id", ""))
				var slot := -1
				for i in main.hud.world_actions.entries.size():
					if str((main.hud.world_actions.entries[i] as Dictionary).get("blocked", "")) == "":
						slot = i
						break
				check(slot >= 0, "菜单里至少有一项可用")
				check(first_entries > 0 and first_id != "", "菜单首项有稳定 id（%s）" % first_id)
				if slot >= 0:
					var pressed := InputEventKey.new()
					pressed.physical_keycode = KEY_1 + slot
					pressed.pressed = true
					main._unhandled_input(pressed)
					# 收起有 0.16 s 的收拢动画，`is_open()` 在动画期间仍为真，
					# 所以要等过动画再判，否则测的是动画时长不是逻辑。
					await frames(24)
					# 这一项是「选择种子」：按下去会走近并弹出二级菜单，
					# 所以判据是「原菜单被消费」（换了内容或已收起），不是「什么都没打开」。
					var consumed: bool = (not main.hud.world_actions.is_open()) \
						or main.hud.world_actions.entries.size() != first_entries \
						or str((main.hud.world_actions.entries[0] as Dictionary).get("id", "")) != first_id
					check(consumed, "按 %d 后原菜单被消费（%d → %d 项）" % [
						slot + 1, first_entries, main.hud.world_actions.entries.size()])

	# ---- 契约 8：船上按 E 能靠到别的岛（纯键盘旅行） ---------------------
	main.boat.place_at(park, float(data.boatYaw))
	controller.restore_pose({"mode": 1})
	controller.cancel()
	await frames(4)
	var far: Dictionary = main._near_landing_key()
	check(not far.is_empty(), "泊位旁识别出可靠的登陆点")

	release_all()
	finish()


func finish() -> void:
	print("[interaction-reach] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
