extends SceneTree
## 靠泊热点：船明明停在泊位旁边，就不许说「无法到达该泊位」。
##
## 2026-11-09 主人反馈（键盘操作）：「我明明停在这里，标记都出来了，显示无法到达」。
## 根因两条，各锁一条：
##
##   1. **泊位点本身落进岸线 0.9 m 缓冲**。zone1 的绞盘泊位实测 park=(-9.95, 18.21)，
##      `plan_route_to` 判它不可航 —— 每一次靠岸都报「无法到达」。
##      现在 `_landing_data` 把 park 挪到最近的开阔水（≤3.5 m）。
##   2. **已经在旁边还要重新规划**。旧实现只认「身份 + 1.6 m」为靠妥，
##      键盘划回来时身份还是上一个泊位，于是掉进规划分支。现在先认领身份再滑进去。
##
## 还锁住「提示 == 按键」：靠岸入口出现的位置，必须是按下去真能靠岸的位置。

var main: Node
var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func settle(n := 4) -> void:
	for i in n:
		await process_frame


## 推进船与角色，直到 `until` 成立或帧数用完（与 building-ocean 同一套驱动）。
func advance(frames: int, until: Callable = Callable()) -> void:
	for i in frames:
		main.boat._process(1.0 / 60.0)
		main.actor_controller.tick(1.0 / 60.0)
		if until.is_valid() and until.call():
			break


func park_of(zone_id: String, landing_id: String) -> Vector3:
	var data: Dictionary = main._landing_data(zone_id, landing_id)
	if data.is_empty():
		return Vector3.INF
	return Vector3(float(data.boatPark[0]), 1.12, float(data.boatPark[2]))


## 在 park 周围找一个「合法水面、且直线能滑进泊位」的船位，距离落在 [lo, hi]。
func berth_spot_near(park: Vector3, lo: float, hi: float) -> Vector3:
	for ring in 32:
		var angle := TAU * float(ring) / 32.0
		for radius in [1.2, 1.6, 2.0, 2.4, 2.8]:
			if radius < lo or radius > hi:
				continue
			var probe := park + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			if not main.navigation.is_open_water(probe.x, probe.z):
				continue
			main.boat.place_at(Vector3(probe.x, probe.y - 0.36, probe.z), 0.0)
			if main._park_glide_clear(park):
				return probe
	return Vector3.INF


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.boat.set_process(false)
	main.cam.set_process(false)
	root.get_node("Economy").set_process(false)
	root.get_node("Economy").ticking = false
	await settle(20)

	# ---- 1. 每个泊位的 park 都必须是合法水面 ----
	var checked := 0
	for zone_id in main._zone_nodes.keys():
		var zone: Node = main._zone_nodes[zone_id]
		if zone == null or not zone.has_method("landing_points"):
			continue
		for point in zone.landing_points():
			var lid := str(point.landing_id)
			var park := park_of(str(zone_id), lid)
			check(park.is_finite(), "%s/%s 有泊位数据" % [zone_id, lid])
			if not park.is_finite():
				continue
			checked += 1
			check(main.navigation.is_open_water(park.x, park.z),
				"%s/%s 的 park 在开阔水面 %s" % [zone_id, lid, str(park)])
	check(checked >= 3, "至少核过 3 个泊位（实际 %d）" % checked)

	# 绞盘泊位是这次的现场：原始 BoatPark 在缓冲里，归一化之后必须可航。
	var salvage := park_of("zone1", "salvage")
	check(salvage.is_finite(), "zone1/salvage 泊位存在")
	check(main.navigation.is_open_water(salvage.x, salvage.z), "绞盘泊位的 park 已抬到开阔水")
	var salvage_route: Array = main.navigation.plan_route_to(
		Vector2(main.boat.position.x, main.boat.position.z), salvage.x, salvage.z)
	check(not salvage_route.is_empty(), "从家园能规划到绞盘泊位（路径 %d 点）" % salvage_route.size())

	# ---- 2. 规划器容忍「起点在缓冲里」 ----
	# 键盘划船进不了缓冲，但存档/传送/工具会 `place_at` 到那里；
	# 旧实现在这种起点上整条规划作废，任何目标都变成「无法到达」。
	var home := park_of("zone1", "main")
	check(home.is_finite(), "zone1/main 泊位存在")
	var tucked := Vector3.INF
	for ring in 24:
		var angle := TAU * float(ring) / 24.0
		for radius in [1.6, 1.9, 2.2]:
			var probe := home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			if not main.navigation.is_open_water(probe.x, probe.z):
				tucked = probe
				break
		if tucked.is_finite():
			break
	check(tucked.is_finite(), "找到一处落在缓冲里的起点")
	if tucked.is_finite():
		var route: Array = main.navigation.plan_route_to(
			Vector2(tucked.x, tucked.z), home.x, home.z)
		check(not route.is_empty(), "起点在缓冲里也能规划到泊位（路径 %d 点）" % route.size())

	# ---- 3. 停在泊位旁边、身份还是上一个泊位：按 E 不许报「无法到达」 ----
	var spot := berth_spot_near(salvage, 1.6, 2.8)
	check(spot.is_finite(), "绞盘泊位旁边有可停的合法水面")
	if not spot.is_finite():
		spot = salvage + Vector3(2.2, 0.0, 0.0)
	main.boat.place_at(Vector3(spot.x, spot.y - 0.36, spot.z), 0.0)
	root.get_node("GameState").current_zone = "zone1"
	root.get_node("GameState").landing_id = "main"
	main.actor_controller.restore_pose({"mode": 1})
	await settle(4)
	var reach: float = main.boat.position.distance_to(salvage)
	check(reach > 1.6 and reach <= 3.0, "船在泊位旁边 %.2f m（不是已靠妥）" % reach)
	# 提示与按键同源：这个位置必须给得出「靠岸」入口。
	var hot: Dictionary = main._near_landing_key()
	check(not hot.is_empty(), "泊位旁边 2 m 时靠岸入口非空")
	check(str(hot.get("landing", "")) == "salvage",
		"靠岸入口指向 zone1/salvage（实际 %s）" % str(hot.get("landing", "")))
	main._select_landing({"zone": "zone1", "landing": "salvage"})
	# 立刻取：后续帧里别的提示（撞岸、抵达）会覆盖这一句。
	var said := str(main.hud.toast_snapshot().text)
	await settle(3)
	check(not said.contains("无法到达"), "按靠岸不报「无法到达」（实际：%s）" % said)
	check(root.get_node("GameState").landing_id == "salvage", "认领了 salvage 泊位身份")
	var ashore := func() -> bool:
		return main.actor_controller.mode() == 0 and not main.actor_controller.walking()
	advance(900, ashore)
	check(main.actor_controller.mode() == 0, "靠妥后上岸（state=%s）" % main.actor_controller.state_id())
	check(main._current_landing() != null and main._current_landing().landing_id == "salvage",
		"上岸用的是 salvage 泊位")
	check(main.boat.position.distance_to(salvage) < 1.6,
		"船停在 park 上（偏差 %.2f m）" % main.boat.position.distance_to(salvage))

	# ---- 4. 已经靠妥再按：直接上下船，不再规划 ----
	main.actor_controller.restore_pose({"mode": 1})
	await settle(3)
	main._select_landing({"zone": "zone1", "landing": "salvage"})
	advance(900, ashore)
	check(main.actor_controller.mode() == 0, "已靠妥时直接上岸")

	main.queue_free()
	await process_frame
	print("[dock-hotspot] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
