extends SceneTree
## 朝向契约专项；同脚本支持 facing-interaction / visual-facing-interaction。
## 位置、朝向、库存属于夹具；E/Q/菜单确认必须经过真实 Viewport/Input 分发。
const InteractorScript = preload("res://src/interaction/interactor.gd")
const SpotScript = preload("res://src/interaction/interactable.gd")
var checks := 0
var failures := 0
var main
var menu
var actor: Node3D
var down_keys: Dictionary = {}
var business: Array = []
var completions: Array = []
var max_progress := 0.0
var park := Vector3.ZERO
var stand := Vector3.ZERO
var landing: Node3D

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [facing-interaction] ", label)
	return ok

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
	print("[facing-state] ", label, " state=", main.actor_controller.state_id(),
		" target=", main.interactor.target, " keyboard=", main.interactor.keyboard_target,
		" boat_action=", main._boat_key_action(), " hold=", main.interactor.hold,
		" menu=", menu.active, " pos=", actor.global_position, " yaw=", actor.rotation.y)
	return false

func send(code: int, pressed: bool, continuous := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
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

func direction(from: Vector3, to: Vector3) -> Vector3:
	return Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()

func face(node: Node3D, dir: Vector3) -> void:
	node.rotation.y = atan2(dir.x, dir.z)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "res://outputs/facing-interaction-" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "真实渲染截图 " + label)
	print("[facing-interaction-shot] ", path)

func shore_fixture(at: Vector3, dir: Vector3) -> void:
	main.restore_world_state({"zone":"zone5", "landing":"main", "mode":0,
		"player":[at.x, at.y, at.z], "far_sea":false})
	main._boat_key_left = 0.0
	main._reach_cache.clear()
	main.hover._reach_cache.clear()
	face(actor, dir)
	await frames(14)
	check(main.actor_controller.state_id() == "ashore_idle", "岸上位置朝向夹具不代执行业务")

func near_winner(expected: Node3D, label: String) -> void:
	check(main.hover.keyboard_focus == expected, label + " 近距图标与E同一胜出目标")
	check(main.hover._near_icon.visible == (expected != null), label + " 近距图标显隐一致")

func close_menu() -> void:
	for attempt in 3:
		if not menu.is_open(): break
		await key(KEY_ESCAPE)
		await frames(14)
	check(not menu.is_open() and not paused and not main.hud.menu.active, "Esc 关闭菜单且不穿透暂停")

func interactor_contract() -> void:
	# 独立探针与正式世界保持空间隔离，阈值断言不依赖场景偶然摆位。
	var probe = InteractorScript.new()
	root.add_child(probe)
	probe.global_position = Vector3(200, 10, 0)
	probe.active = true
	var spot = SpotScript.new()
	spot.focus_anchor = "node"
	spot.auto_radius = false
	spot.hold_time = 0.35
	root.add_child(spot)
	spot.global_position = probe.global_position + Vector3(0, 0, 1.5)
	# 2026-11-07 契约变更：朝向不再是交互硬门槛。
	# candidates() 不再按朝向过滤，单目标只要在判定区里就直接可选（背对也能操作）；
	# 旧的 dot>=0.55 门槛与「背对候选为空」断言全部删除。
	for dot_value: float in [-1.0, 0.0, 0.54, 0.55, 0.56, 1.0]:
		face(probe, Vector3(sqrt(maxf(0.0, 1.0 - dot_value * dot_value)), 0, dot_value))
		await frames(10)
		check(probe.candidates().has(spot), "单目标背/侧/正对都在候选 dot=%.2f（朝向不再过滤）" % dot_value)
		check(probe.target == spot, "单目标扫描不按朝向过滤 dot=%.2f" % dot_value)
	# facing_alignment() 数值本身仍正确；它现在只用于多目标排序，不再当门槛。
	face(probe, Vector3(0, 0, 1))
	await frames(2)
	check(probe.facing_alignment(spot.focus_position()) > 0.99, "正对对齐度≈1.0")
	face(probe, Vector3(0, 0, -1))
	await frames(2)
	check(probe.facing_alignment(spot.focus_position()) < -0.99, "背对对齐度≈-1.0")
	# 脚下近中心豁免：CENTER_REACH 半径内没有方向可言，一律算完全正对。
	for distance: float in [0.34, 0.35]:
		spot.global_position = probe.global_position + Vector3(0, 0, distance)
		await frames(2)
		check(probe.facing_alignment(spot.focus_position()) == 1.0, "脚下近中心豁免 %.2f 返回 1.0" % distance)
	spot.global_position = probe.global_position + Vector3(0, 0, 0.36)
	await frames(2)
	check(probe.facing_alignment(spot.focus_position()) < -0.9, "超过近中心半径 0.36 恢复真实朝向")
	# preferred_target 仍是绝对优先；背对着也能照常执行一次。
	spot.global_position = probe.global_position + Vector3(0, 0, 1.5)
	await frames(10)
	probe.preferred_target = spot
	await frames(10)
	check(probe.candidates().has(spot), "背对时单目标仍在候选（preferred不再是绕过门槛的必要条件）")
	check(probe.target == spot, "背对时单目标仍被选中")
	var executed: Array = []
	probe.queue_command(spot, func():
		executed.append(true)
		return {"probe":true})
	probe.completed.connect(func(_spot, _reward): probe.auto_hold = false)
	probe.auto_hold = true
	await frames(45)
	check(executed.size() == 1, "auto_hold且preferred显式命令背对仍在正常hold边界执行一次")
	check(not probe.selected_command.is_valid() and probe.command_target == null, "自动命令消费后无残留")
	probe.cancel()
	spot.queue_free()
	await frames(2)
	# 两目标同框：面朝谁选谁；朝向差在 FACING_TIE 内时更近的赢。这是新的核心契约。
	var front = SpotScript.new()
	front.name = "FacingFrontFixture"
	front.focus_anchor = "node"
	front.auto_radius = false
	front.hold_time = 0.0
	root.add_child(front)
	var back = SpotScript.new()
	back.name = "FacingBackFixture"
	back.focus_anchor = "node"
	back.auto_radius = false
	back.hold_time = 0.0
	root.add_child(back)
	front.global_position = probe.global_position + Vector3(0, 0, 1.4)
	back.global_position = probe.global_position + Vector3(0, 0, -1.4)
	face(probe, Vector3(0, 0, 1))
	await frames(14)
	check(probe.target == front, "两目标同框：面朝 A 选 A")
	face(probe, Vector3(0, 0, -1))
	await frames(14)
	check(probe.target == back, "两目标同框：面朝 B 选 B")
	# 同档（对齐差 < FACING_TIE=0.08）：两个目标几乎同向，比较距离而不是朝向。
	front.global_position = probe.global_position + Vector3(0, 0, 1.2)
	back.global_position = probe.global_position + Vector3(0.12, 0, 1.8)
	face(probe, Vector3(0, 0, 1))
	await frames(14)
	check(probe.target == front, "朝向差 <FACING_TIE 时更近者赢（近的目标胜出）")
	back.global_position = probe.global_position + Vector3(0, 0, 1.0)
	await frames(14)
	check(probe.target == back, "朝向差 <FACING_TIE 时更近者赢（交换距离后换人）")
	probe.cancel()
	probe.queue_free()
	front.queue_free()
	back.queue_free()
	await frames(2)

func plot_contract(plot: Node3D) -> void:
	var to_plot := direction(stand, plot.focus_position())
	# 2026-11-07 契约变更：朝向不再是交互硬门槛。
	# 背/侧对种植格时 candidates() 仍包含它，真实按一次 E 就能打开菜单（可以操作）。
	for angle: float in [PI, PI * 0.5]:
		await shore_fixture(stand, to_plot.rotated(Vector3.UP, angle))
		check(main.interactor.candidates().has(plot), "背/侧对种植格仍在候选 angle=%.2f" % angle)
		check(main._boat_key_action() == "", "背/侧对种植格时泊位不抢E angle=%.2f" % angle)
		send(KEY_E, true, true)
		var opened := await until(func(): return menu.active, 4.0, "背/侧对按一次E打开种植菜单 angle=%.2f" % angle)
		send(KEY_E, false, true)
		await frames(4)
		check(opened, "背/侧对种植格按 E 仍然可以操作 angle=%.2f" % angle)
		check(business.is_empty(), "背/侧对只开菜单不偷播种 angle=%.2f" % angle)
		check(main.actor_controller.mode() == 0 and not main.boat.starts_sailing(), "背/侧对种植格按 E 不误离岸 angle=%.2f" % angle)
		if menu.is_open(): await close_menu()
	await shore_fixture(stand, to_plot)
	check(main.interactor.target == plot, "正对真实种植格取得手动焦点")
	check(main._boat_key_action() == "", "正对plot时泊位不得抢E")
	near_winner(plot, "正对种植格")
	await shot("plot-facing")
	# Q 是显式选择：它压过自然排序。朝向不是门槛后，转身不再让 Q 目标失效
	# —— 旧的「Q目标离开面向后清除锁定」契约（依赖朝向过滤）已删除。
	for attempt in 12:
		await key(KEY_Q)
		if main.interactor.keyboard_target == plot: break
	check(main.interactor.keyboard_target == plot, "真实Q选中当前正面种植格")
	face(actor, -to_plot)
	await frames(14)
	check(main.interactor.keyboard_target == plot, "Q显式选择不因转身失效（朝向不再是门槛）")
	check(main.interactor.target == plot and plot.focused, "Q目标转身后仍保有焦点（显式优先）")
	face(actor, to_plot)
	await frames(14)
	max_progress = 0.0
	var before: Dictionary = root.get_node("Economy").farm.state(str(plot.plot_id)).duplicate(true)
	send(KEY_E, true, true)
	check(Input.is_action_pressed("interact") and Input.is_physical_key_pressed(KEY_E), "parse/flush真实E已进入全局Input")
	var opened := await until(func(): return menu.active, 4.0, "按一次E打开种植一级菜单")
	if opened:
		# 2026-11-07 契约变更：种植格是瞬发动作（hold_time=0.0），不再要求按住读条，
		# 所以 max_progress>0 不再必然。改为断言「一次按下即开一级菜单，且不会连开两级」。
		check(is_zero_approx(float(main.interactor.target.hold_time)), "种植格是瞬发动作（hold_time=0）")
		check(main.actor_controller.mode() == 0 and not main.boat.starts_sailing(), "正对plot按E不误离岸")
		check(main.hover.keyboard_focus == null and not main.hover._near_icon.visible and not main.hover._near_progress.visible, "菜单模态接管近距图标与进度")
		var generation: int = menu.generation
		send(KEY_E, true, true, true)
		await frames(45)
		check(menu.active and menu.generation == generation, "持续E和echo不连穿二级菜单")
		check(root.get_node("Economy").farm.state(str(plot.plot_id)) == before and business.is_empty(), "长按只开菜单不播种不奖励")
		await shot("plot-hold-menu")
	send(KEY_E, false, true)
	await frames(3)
	if not opened: return
	check(menu.entries.size() > 0 and menu.selected_index >= 0, "真实菜单有默认键盘选项")
	var plant_index := -1
	for i in menu.entries.size():
		if str(menu.entries[i].get("id", "")) == "plant": plant_index = i
	check(plant_index >= 0, "真实菜单包含种植入口")
	for attempt in menu.entries.size():
		if menu.selected_index == plant_index: break
		await key(KEY_RIGHT)
	await key(KEY_E)
	check(menu.active and menu.hint_label.text.contains("选择种子"), "松E后再次真实E只进入种子二级")
	check(business.is_empty() and main.actor_controller.mode() == 0, "二级确认未偷播种或上船")
	await close_menu()

func boarding_contract() -> void:
	var boat_dir := direction(stand, park)
	# 2026-11-07 契约变更：朝向不再是上船的硬门槛，改为「热区 + 朝向仲裁」。
	# 热区是**位置**判定（船 3.0 米内 或 站立点 2.4 米内），与朝向无关；
	# 朝向只决定「同时够得着种植格和上船口时谁赢 E」。
	await shore_fixture(stand, -boat_dir)
	check(main._actor_in_boarding_zone(landing), "背对船站在landing中心仍在热区（位置判定，朝向不再当门槛）")
	check(main.interactor.candidates().size() > 0, "landing中心船与种植格同框参与仲裁")
	check(main._boat_key_action() == "", "背对船时正面种植格赢仲裁（朝向只仲裁、不再当门槛）")
	await shore_fixture(stand, boat_dir)
	check(main._boat_key_action() == "board", "面朝船时船赢仲裁可上船")
	# 2026-11-07 契约变更：`_near_action()` 的 boat_board 返回 node=船（不是泊位），
	# 上船图标挂到船上；靠岸/上岸入口才挂到 landing。
	near_winner(main.boat, "面朝船上船入口")
	# 船 3 米热区（BOAT_HULL_REACH）：站在船边、却在站立点 2.4 米外，也算走进热区。
	# 先用纯几何挑候选点（不恢复场景），再对少量候选做真实验证，避免上千次场景重置。
	var hull_at := Vector3.INF
	var hull_clear := false
	var hull_probes: Array[Vector3] = []
	var ground: Node3D = landing.ground()
	for ix in 44:
		for iz in 38:
			var probe_at: Vector3 = ground.surface_point(Vector3(18.8 + float(ix) * 0.15, ground.surface_y, 13.2 + float(iz) * 0.15))
			if not probe_at.is_finite(): continue
			var d_stand := Vector2(probe_at.x - stand.x, probe_at.z - stand.z).length()
			var d_boat := Vector2(probe_at.x - main.boat.global_position.x, probe_at.z - main.boat.global_position.z).length()
			if d_stand <= main.BOAT_KEY_REACH or d_boat > main.BOAT_HULL_REACH: continue
			if hull_at == Vector3.INF: hull_at = probe_at
			hull_probes.append(probe_at)
	if not hull_probes.is_empty():
		# 从候选里均匀抽样最多 10 个做真实验证。
		for k in mini(10, hull_probes.size()):
			var probe_at: Vector3 = hull_probes[int(float(k) * float(hull_probes.size()) / float(mini(10, hull_probes.size())))]
			await shore_fixture(probe_at, -boat_dir)
			if not main._actor_in_boarding_zone(landing): continue
			hull_at = probe_at
			if main.interactor.candidates().is_empty():
				hull_clear = true
				break
	if check(hull_at.is_finite(), "找到船3米热区、站立点2.4米外（BOAT_HULL_REACH）的真实站位 %d 个候选" % hull_probes.size()):
		# 位置判定：同一站位背对/正对船都在热区。
		await shore_fixture(hull_at, -boat_dir)
		check(main._actor_in_boarding_zone(landing), "贴船舷背对船仍在热区（位置判定）")
		await shore_fixture(hull_at, boat_dir)
		check(main._actor_in_boarding_zone(landing), "贴船舷正对船仍在热区（位置判定）")
		if hull_clear:
			await shore_fixture(hull_at, -boat_dir)
			check(main._boat_key_action() == "board", "船边热区内背对船、无竞争时按 E 上船")
		else:
			print("[facing-hull] zone5 船边热区采样点均被种植格覆盖（无纯船候选点），按仲裁断言：")
			await shore_fixture(hull_at, boat_dir)
			check(main._boat_key_action() == "board", "船边热区内正对船时船赢仲裁可上船")
	# 上船链路：真实按 E 上船、船上背对泊位仍可上岸。
	await shore_fixture(stand, boat_dir)
	await shot("boat-facing")
	await key(KEY_E)
	if not await until(func(): return main.actor_controller.state_id() == "boat_idle", 8.0, "中心stand真实E上船完成"): return
	await frames(25)
	face(actor, -boat_dir)
	check(main._boat_key_action() == "leave", "船上泊位leave不要求转角色")
	near_winner(landing, "船上上岸入口")
	await key(KEY_E)
	await until(func(): return main.actor_controller.state_id() == "ashore_idle", 8.0, "真实E保留上岸链")

func alignment_contract() -> void:
	var boat_dir := direction(stand, park)
	var spot = SpotScript.new()
	spot.name = "FacingPriorityFixture"
	spot.id = "facing-priority-fixture"
	spot.focus_anchor = "node"
	spot.auto_radius = false
	main.add_child(spot)
	spot.global_position = stand + boat_dir.rotated(Vector3.UP, PI / 4.0) * 1.2
	spot.set_meta("approach_points", [stand])
	await shore_fixture(stand, boat_dir.rotated(Vector3.UP, PI / 8.0))
	check(main.interactor.target == spot, "正面有效spot夹具实际进入正式候选")
	check(main._boat_key_action() == "", "船与spot同等对齐时优先spot")
	near_winner(spot, "spot对齐优先")
	face(actor, boat_dir)
	# 2026-11-07 契约变更：仲裁带宽从 0.15 改为 main.FACING_TIE（=0.08，与 Interactor 同值）。
	# 面朝船时 boat_align=1.0，spot_align=alignment；船赢当且仅当 1.0-alignment >= FACING_TIE。
	for alignment: float in [0.94, 0.90]:
		spot.global_position = stand + boat_dir.rotated(Vector3.UP, acos(alignment)) * 1.2
		main._reach_cache.clear()
		await frames(14)
		check(main.interactor.target == spot, "FACING_TIE仲裁两侧spot均实际有效")
		check((main._boat_key_action() == "board") == (1.0 - alignment >= main.FACING_TIE), "船与spot对齐优势门槛FACING_TIE 差值=%.2f" % (1.0 - alignment))
	spot.global_position = stand + boat_dir.rotated(Vector3.UP, PI / 4.0) * 1.2
	main._reach_cache.clear()
	await frames(14)
	check(main.interactor.target == spot, "船更对齐时spot仍合法而非通过失效避开竞争")
	check(main._boat_key_action() == "board", "船正对且优势超过FACING_TIE可上船")
	near_winner(main.boat, "船对齐优势胜出")
	await key(KEY_E)
	await until(func(): return main.actor_controller.state_id() == "boat_idle", 8.0, "对齐竞争赢家与真实E上船一致")
	spot.queue_free()
	await frames(2)

func docking_contract() -> void:
	var away := Vector3.ZERO
	for i in 16:
		var dir := Vector3(sin(float(i) * TAU / 16.0), 0, cos(float(i) * TAU / 16.0))
		var point := park + dir * 2.2
		if not main._is_open_water(point.x, point.z): continue
		main.boat.place_at(point, 0.0)
		if not main.plan_route_to(park.x, park.z).is_empty():
			away = point
			break
	if not check(away != Vector3.ZERO, "找到真实可航route的离泊位置"): return
	main.actor_controller.restore_pose({"mode":1})
	var to_park := direction(away, park)
	# 2026-11-07 契约变更：删除「船头朝 park 门槛 0.20」的方向锥断言。
	# 现在靠岸入口由「在 6.5 米热区内 + 真的可航」决定，与船头朝向无关（含背对）。
	for dot_value: float in [-1.0, 0.0, 0.19, 0.21, 1.0]:
		var heading := to_park.rotated(Vector3.UP, acos(dot_value))
		main.boat.place_at(away, atan2(-heading.x, -heading.z))
		await frames(12)
		var dock: Dictionary = main._near_landing_key()
		check(dock.get("zone", "") == "zone5" and dock.get("landing", "") == "main", "热区内任意船头朝向（含背对）都提供靠岸 dot=%.2f" % dot_value)
		if dot_value == 1.0:
			check(not main.plan_route_to(park.x, park.z).is_empty(), "正向候选具有实际可航route")
			near_winner(landing, "正向可航靠岸")
	# 热区外（6.5 米）不再提供靠岸入口。
	var far_dir := direction(park, away)
	for reach: float in [6.6, 7.0, 7.6]:
		var point := park + far_dir * reach
		if not main._is_open_water(point.x, point.z): continue
		main.boat.place_at(point, 0.0)
		await frames(6)
		check(main._near_landing_key().is_empty(), "热区外 %.1f 米不提供靠岸入口" % reach)
	# 可航性仍生效：距离近但航线不通的泊位不给入口（找不到就断言不变量并打印实测）。
	var route_checked := 0
	var route_violations := 0
	var unroutable_near: Vector3 = Vector3.ZERO
	for i in 24:
		var dir := Vector3(sin(float(i) * TAU / 24.0), 0, cos(float(i) * TAU / 24.0))
		for reach: float in [1.4, 2.6, 4.0, 5.2, 6.2]:
			var point := park + dir * reach
			if not main._is_open_water(point.x, point.z): continue
			main.boat.place_at(point, 0.0)
			# 缓存 key 不含 boat.z，逐点测量前清掉，避免同 x 不同 z 互相污染。
			main._dock_cache.clear()
			var routable: bool = not main.plan_route_to(park.x, park.z).is_empty()
			var entry: bool = not main._near_landing_key().is_empty()
			route_checked += 1
			if entry and not routable: route_violations += 1
			if not routable and unroutable_near == Vector3.ZERO:
				unroutable_near = point
	if unroutable_near != Vector3.ZERO:
		main.boat.place_at(unroutable_near, 0.0)
		# `_dock_route_ok` 的缓存 key 只含 boat.x / park.x / park.z（不含 boat.z），
		# 本搜索循环会让不同 z、同 x 的点互相命中缓存。先清缓存再测真实契约。
		main._dock_cache.clear()
		await frames(6)
		check(main._near_landing_key().is_empty(), "距离近但可航失败的位置不给靠岸入口")
	else:
		check(route_violations == 0, "热区内所有靠岸候选都满足可航不变量（实测 %d 处）" % route_checked)
		print("[facing-dock] 本世界未找到「近距但不可航」的泊位点位，改断言可航不变量 checked=%d violations=%d" % [route_checked, route_violations])

func run() -> void:
	if not check(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"), "统一runner在Autoload前隔离用户目录"):
		finish(); return
	var scene = load("res://scenes/main.tscn")
	if not check(scene is PackedScene, "真实main场景资源可加载"):
		finish(); return
	main = scene.instantiate()
	if not check(main.get_script() != null and main.get_script().can_instantiate(), "正式主场景脚本及依赖可编译"):
		finish(); return
	root.add_child(main)
	main._autosave_on = false
	root.get_node("Economy").ticking = false
	root.get_node("Economy").inventory.set_count("lettuce_seed", 3)
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	menu = main.hud.world_actions
	actor = main.player
	main.farm_field.acted.connect(func(id, event, payload): business.append([id, event, payload]))
	main.interactor.progress_changed.connect(func(value): max_progress = maxf(max_progress, float(value)))
	main.interactor.completed.connect(func(spot, _reward): completions.append(spot))
	await frames(20)
	check(not main._title_active and not main.input_blocked(), "正式场景已启动且无模态夹具")
	await interactor_contract()
	landing = main._zone_nodes.zone5.landing_point("main")
	stand = landing.stand_position()
	var data: Dictionary = main._landing_data("zone5", "main")
	park = Vector3(float(data.boatPark[0]), main.WATER_LEVEL, float(data.boatPark[2]))
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.cam.global_position = stand + Vector3(-6, 11, 12)
	main.cam.look_at(stand)
	main.cam.fov = 40
	var nearest: Node3D
	var nearest_distance := INF
	for candidate in main.farm_field.plots:
		if str(candidate.zone_id) != "zone5": continue
		var distance := Vector2(candidate.focus_position().x - stand.x, candidate.focus_position().z - stand.z).length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	if not check(nearest != null and nearest_distance > 0.35 and nearest_distance < 3.0, "泊位范围有非脚下种植格用于误离岸回归"):
		finish(); return
	await plot_contract(nearest)
	await boarding_contract()
	await alignment_contract()
	await docking_contract()
	finish()

func finish() -> void:
	for code in down_keys.keys(): send(int(code), false, true)
	print("[facing-interaction] %d checks, %d failures" % [checks, failures])
	if main != null and is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(0 if failures == 0 else 1)
