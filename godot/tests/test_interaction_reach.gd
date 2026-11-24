extends SceneTree
## 正式采集物热区、上下船和近距交互。

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
	var rope: Node3D = main.gather.find("zone1_rope")
	var rope_visible := is_instance_valid(rope) and rope.is_visible_in_tree()
	check(rope_visible, "打捞台绳索在默认范围里可见")
	if rope_visible:
		var ground: Node3D = main._zone_nodes["zone1"].area_at(rope.global_position, 0.6)
		var stand: Vector2 = ground.clamp_point(rope.global_position.x + 1.0, rope.global_position.z + 1.0)
		var stand_pos: Vector3 = ground.surface_point(Vector3(stand.x, ground.surface_y, stand.y))
		state.enter_zone("zone1")
		state.set_mode(state.Mode.ASHORE)
		controller.restore_pose({"mode": 0, "player": [stand_pos.x, stand_pos.y, stand_pos.z]})
		var focus: Vector3 = rope.focus_position()
		player.rotation.y = atan2(focus.x - player.global_position.x, focus.z - player.global_position.z)
		await frames(20)
		check(main.interactor.active, "岸上交互器已开放")
		check(main.interactor.target == rope, "E 焦点锁到绳索（实际 %s）" % str(main.interactor.target))
		main.interactor.auto_hold = true
		await frames(90)
		main.interactor.auto_hold = false
		check(not rope.available, "按 E 采到绳索后进入冷却")

	var landing: Node3D = main._zone_nodes.zone1.landing_point("main")
	var park: Marker3D = landing.get_node("BoatPark")
	main.boat.place_at(park.global_position, park.global_rotation.y)
	controller.restore_pose({"mode": 1})
	await frames(6)
	check(main.interactor.interaction_context == "sea" and main.interactor.candidates().is_empty(), "船上隔离岸上采集物")
	check(main._boat_shortcut_text() == "上岸", "船壳在泊位范围内显示上岸")
	press_key(KEY_E)
	await frames(6)
	check(controller.mode() == 0 and player.ground_contact, "按 E 上岸并落在实体甲板上")

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

	finish()


func finish() -> void:
	print("[interaction-reach] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
