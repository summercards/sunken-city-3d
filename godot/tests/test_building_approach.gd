extends SceneTree
## 建造要先走过去，站定了才开工。
##
## 2026-10-29 用户要求：造木板或培养土，角色必须走到边上，然后才触发开始建造。
## 旧实现是「点虚影 → 当场扣材料 → 五米外自己长出进度条」，建造读起来像在
## map 上点按钮，而不是在自己家里动手。
##
## 本测试锁死四条：
##   1. 点远处虚影只排队，不扣材料、不开工；
##   2. 角色走到位的那一刻自动开工，材料只扣一次；
##   3. 站在格子旁边再点，当场开工，不让他再走一趟；
##   4. 退出建造模式清掉排队，不留下「走着走着突然开工」。

const Catalog = preload("res://src/building/building_catalog.gd")
var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


## main 关掉了自动 process，角色与建造控制器的 tick 要测试自己推。
func walk_until_built(controller: Node, main: Node, frames: int) -> bool:
	for i in frames:
		main.actor_controller.tick(1.0 / 60.0)
		controller.tick(1.0 / 60.0)
		if main.building.query().size() > 0:
			return true
	return false


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	var econ: Node = root.get_node("Economy")
	econ.set_process(false)
	await process_frame

	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode": 0, "player": [21.0, 1.48, 16.0]})
	root.get_node("GameState").enter_zone("zone5")
	econ.inventory.set_count("wood", 30)
	econ.inventory.set_count("soil", 6)
	await process_frame

	var controller: Node = main.building_controller
	controller.open()
	controller.select_recipe("deck")
	check(not controller.book.visible, "选中配方后进入摆位")

	var candidate: Dictionary = {}
	for c in main.building.candidates():
		if c.x == 3 and c.z == 0 and main.building.can_place(c) == "":
			candidate = c
			break
	check(not candidate.is_empty(), "平台东侧可以接木板")
	if candidate.is_empty():
		print("[building-approach] %d checks, %d failures" % [checks, failures])
		quit(1)
		return

	# ---- 落脚点必须落在可走面上，且靠近目标格 ----
	var center: Vector3 = main.building_world.position_for(candidate)
	var stand: Vector3 = main._construction_stand_point(center)
	check(stand != Vector3.INF and stand.is_finite(), "目标格旁能找到落脚点（%s）" % str(stand))
	check(Vector2(stand.x - center.x, stand.z - center.z).length() < 2.6,
		"落脚点在目标格附近（%.2f 米）" % Vector2(stand.x - center.x, stand.z - center.z).length())
	var zone: Node = main._zone_nodes["zone5"]
	check(zone.area_containing(stand.x, stand.z) != null, "落脚点在可行走区域内")

	# ---- 1. 点远处虚影：只排队 ----
	var wood_before: int = econ.count("wood")
	controller._request_build(candidate.duplicate(true))
	check(main.building.query().is_empty(), "人还在远处时不立刻开工")
	check(econ.count("wood") == wood_before, "没开工就不扣材料")
	check(not controller.pending.is_empty(), "记下了「要走过去建这一格」")
	check(not controller.preview.is_empty(), "等待期间虚影停在目标位置，不跟着鼠标跑")

	# ---- 2. 走到位自动开工 ----
	var started := walk_until_built(controller, main, 900)
	check(started, "走到工地后自动开工")
	check(econ.count("wood") == wood_before - 6, "开工只扣一次木板（6）")
	check(controller.pending.is_empty(), "开工后清掉排队")
	check(main.actor_controller.state_id() == "ashore_idle",
		"开工后人站在工地边（实际状态 %s）" % main.actor_controller.state_id())

	# ---- 3. 退出建造模式：清排队 ----
	controller.tick(4.0)
	var next: Dictionary = {}
	for c in main.building.candidates():
		if main.building.can_place(c) == "":
			next = c
			break
	check(not next.is_empty(), "还有一格可以接")
	if not next.is_empty():
		controller._request_build(next.duplicate(true))
		var queued: bool = not controller.pending.is_empty()
		controller.close()
		check(not queued or controller.pending.is_empty(), "退出建造模式清掉等待中的施工")
		var wood_after_close: int = econ.count("wood")
		for i in 240:
			main.actor_controller.tick(1.0 / 60.0)
			controller.tick(1.0 / 60.0)
		check(econ.count("wood") == wood_after_close, "退出后不会再自己开工扣材料")

	# ---- 4. 站在旁边点：当场开工 ----
	controller.open()
	controller.select_recipe("deck")
	var nearby: Dictionary = {}
	for c in main.building.candidates():
		if c.x == 3 and c.z == -1 and main.building.can_place(c) == "":
			nearby = c
			break
	if nearby.is_empty():
		for c in main.building.candidates():
			if main.building.can_place(c) == "":
				nearby = c
				break
	if not nearby.is_empty():
		# 先把人挪到那一格旁边，模拟「已经站在工地边」。
		var spot: Vector3 = main._construction_stand_point(main.building_world.position_for(nearby))
		main.actor_controller.restore_pose({"mode": 0, "player": [spot.x, spot.y, spot.z]})
		root.get_node("GameState").enter_zone("zone5")
		await process_frame
		var before_near: int = main.building.query().size()
		controller._request_build(nearby.duplicate(true))
		check(main.building.query().size() == before_near + 1, "站在旁边点一下当场开工，不再走第二趟")
		check(controller.pending.is_empty(), "当场开工不留排队")

	controller.close()
	main.queue_free()
	await process_frame
	print("[building-approach] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
