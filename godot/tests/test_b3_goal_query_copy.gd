extends SceneTree

const GoalService = preload("res://src/goals/goal_service.gd")
const FacilityService = preload("res://src/facilities/facility_service.gd")
const ShipService = preload("res://src/ship/ship_service.gd")
const ConstructionService = preload("res://src/construction/construction_service.gd")
const Inventory = preload("res://src/inventory/inventory.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	_test_nested_queries()
	_test_authoritative_payments()
	print("[b3-goal-query-copy] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_nested_queries() -> void:
	var goals = GoalService.new()
	var state := {"ship_level": 1, "sites": {}, "facilities": {}}
	var source := {"wood": 4, "nested": {"rows": [{"amounts": [2, 3]}]}}
	var expected: Dictionary = source.duplicate(true)
	goals.FACILITIES = {
		"warehouse": {"name": "仓库夹具", "cost": source},
		"greenhouse": {"name": "温室夹具", "cost": source},
		"recycler": {"name": "回收台夹具", "cost": source},
	}
	goals.SITES = {"home_cabin": {"name": "木屋夹具"}, "rooftop_planter": {"name": "农场夹具"}}
	goals.configure({
		"facility_unlocked": func(id: String) -> bool: return state.facilities.get(id, false),
		"site_level": func(id: String) -> int: return state.sites.get(id, 1),
		"ship_cost": func() -> Dictionary: return source,
		"site_next_cost": func(_id: String) -> Dictionary: return source,
		"ship_level": func() -> int: return state.ship_level,
	})
	var notifications: Array = []
	goals.resources_changed.connect(func(): notifications.append(true))
	for id in ["warehouse", "ship", "ship3", "home_cabin"]:
		goals.track_goal(id)
		notifications.clear()
		var first: Dictionary = goals.goal_info()
		var original: Dictionary = first.duplicate(true)
		check(first.id == id and first.cost == expected, "查询保持原值：" + id)
		check(first.keys() == ["id", "name", "cost"] and first.cost.keys() == expected.keys(), "查询字段顺序不变：" + id)
		first.cost.nested.rows[0].amounts[0] = 999
		first.cost.nested.rows.append({"amounts": []})
		first.cost.wood = 0
		first.cost.erase("nested")
		first.id = "changed"
		first.name = "changed"
		check(source == expected, "嵌套字典和数组不污染来源：" + id)
		check(goals.goal_info() == original, "下次查询不受修改影响：" + id)
		check(goals.tracked_goal == id and notifications.is_empty(), "查询不写追踪状态或发布事件：" + id)
		# 让旧实现也能继续跑完全部反例，而不是连锁失败后中断。
		source.clear()
		source.merge(expected.duplicate(true))
	goals.track_goal("")
	for id in ["warehouse", "rooftop_planter", "home_cabin", "ship", "greenhouse", "recycler", "ship3"]:
		check(goals.goal_info().id == id, "推荐顺序不变：" + id)
		if goals.FACILITIES.has(id):
			state.facilities[id] = true
		elif goals.SITES.has(id):
			state.sites[id] = 2
		else:
			state.ship_level += 1
	var empty := {"id": "", "name": "第一阶段建设已完成，享受种植与探索吧", "cost": {}}
	check(goals.goal_info() == empty, "全部完成的空结果不变")
	var empty_result: Dictionary = goals.goal_info()
	empty_result.cost.wood = 999
	check(goals.goal_info() == empty, "空结果也相互隔离")
	goals.track_goal("unknown")
	check(goals.goal_info() == empty, "未知追踪目标沿用原有空结果")
	goals.ports.clear()

func _test_authoritative_payments() -> void:
	var inventory = Inventory.new(48)
	for id in ["coins", "wood", "parts", "rope", "glass"]:
		inventory.set_count(id, 200)
	var paid: Array = []
	var payments := {
		"construction_pay": func(cost: Dictionary) -> bool:
			paid.append(cost.duplicate(true))
			return inventory.pay(cost),
		"construction_has": inventory.has_all,
		"construction_missing_text": func(_cost: Dictionary) -> String: return "材料不足",
		"site_level": func(_id: String) -> int: return 3,
	}
	var facility = FacilityService.new()
	facility.configure(payments)
	var ship = ShipService.new()
	ship.configure(payments)
	var construction = ConstructionService.new()
	construction.configure(payments)
	var goals = GoalService.new()
	goals.FACILITIES = FacilityService.FACILITIES.duplicate(true)
	goals.SITES = ConstructionService.SITES.duplicate(true)
	goals.configure({
		"facility_unlocked": facility.facility_unlocked,
		"site_level": construction.site_level,
		"ship_cost": ship.ship_cost,
		"site_next_cost": construction.site_next_cost,
		"ship_level": func() -> int: return ship.ship_level,
	})
	var cases := [
		["warehouse", {"coins": 12, "wood": 4}],
		["ship", {"coins": 25, "wood": 6, "parts": 4, "rope": 2}],
		["ship3", {"coins": 60, "wood": 10, "parts": 8, "rope": 4}],
		["home_cabin", {"coins": 20, "wood": 4, "parts": 2}],
	]
	for entry in cases:
		var id: String = entry[0]
		var expected: Dictionary = entry[1]
		goals.track_goal(id)
		var result: Dictionary = goals.goal_info()
		check(result.cost == expected and result.cost.keys() == expected.keys(), "真实价格及顺序不变：" + id)
		check(not result.cost.is_read_only(), "查询返回可独立修改的副本：" + id)
		if not result.cost.is_read_only():
			for item in result.cost.keys():
				result.cost[item] = 0
			result.cost.erase("wood")
			result.cost["query_only"] = 999
		check(goals.goal_info().cost == expected, "真实服务下次查询价格不变：" + id)
		var before: Dictionary = inventory.all()
		var outcome: Dictionary
		if id == "warehouse":
			check(FacilityService.FACILITIES.warehouse.cost == expected, "权威设施价格不变")
			outcome = facility.build_facility(id)
		elif id.begins_with("ship"):
			check(ship.ship_cost() == expected, "权威船级价格不变：" + id)
			outcome = ship.upgrade_ship()
		else:
			check(construction.site_next_cost(id) == expected, "权威固定施工价格不变")
			outcome = construction.begin_site_upgrade(id)
		check(outcome.ok and paid.back() == expected, "实际支付端口仍收到原价格：" + id)
		for item in before:
			check(inventory.count(item) == before[item] - int(expected.get(item, 0)), "实际扣料不受查询污染：" + id + "/" + item)
	for service in [goals, facility, ship, construction]:
		service.ports.clear()
