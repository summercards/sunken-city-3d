extends SceneTree
var checks := 0
var failures := 0
var economy: Node
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	economy = root.get_node("Economy")
	economy.ticking = false
	var farm = economy.farm
	check(economy.goal_info().id == "warehouse", "起步推荐仓库")
	check(economy.deposit_materials().has("blocked"), "未建仓库不可入库")
	check(farm._access_reason("home_plot") == "", "起步开放六格")
	check(farm._access_reason("farm_plot_a") != "", "第二种植床待修复")
	check(farm._access_reason("platform_plot") != "", "第三种植床需船二级")
	# 真正经过播种、浇水、休息与收获，随后交出订单。
	farm.plant("home_plot", "lettuce")
	for day in 3:
		farm.water("home_plot")
		farm.advance_day()
	farm.harvest("home_plot")
	check(economy.count("vegetable") == 2, "种植获得两份农产品")
	var board = economy.orders
	var order_id := ""
	for id in board._by_id:
		if board._by_id[id].item == "vegetable" and int(board._by_id[id].tier) == 1: order_id = id
	check(order_id != "", "有农产品订单")
	var offer: Dictionary = board._make_offer(board._by_id[order_id], "crop-loop", 0.1)
	while economy.count("vegetable") < int(offer.amount):
		farm.plant("home_plot", "lettuce")
		for day in 3:
			farm.refill()
			farm.water("home_plot")
			farm.advance_day()
		farm.harvest("home_plot")
	board.slots[0] = offer
	board.tick(999999)
	check(board.slots[0].uid == "crop-loop", "订单不因等待失效")
	var money: int = economy.coins
	check(board.fulfill("crop-loop").get("ok", false), "农产品交单")
	check(economy.coins == money + int(offer.pay), "订单收入到账")
	check(not board.fulfill("crop-loop").get("ok", false), "不重复领取奖励")
	# 可再生打捞产出进入建设循环。
	economy.do_salvage(1000)
	economy.do_salvage(1020)
	check(economy.build_facility("warehouse").get("ok", false), "打捞材料建仓库")
	var wood_before: int = economy.count("wood")
	economy.deposit_materials()
	check(economy.count("wood") == 0 and economy.warehouse.count("wood") == wood_before, "入库数量守恒")
	check(economy.count("lettuce_seed") > 0 and economy.warehouse.count("lettuce_seed") == 0, "不存走种子")
	check(economy.goal_info().id == "rooftop_planter", "目标自动推进")
	economy.do_salvage(1040)
	economy.deposit_materials()
	var total: int = economy.construction_count("wood")
	check(economy.begin_site_upgrade("rooftop_planter").get("ok", false), "背包及仓库联合支付")
	check(economy.construction_count("wood") == total - 5, "建设精确扣料")
	check(farm._access_reason("farm_plot_a") != "", "施工尚未完成仍锁定")
	economy.tick_sites(25)
	check(farm._access_reason("farm_plot_a") == "", "修复后开放第二种植床")
	# 原子失败、仓满、背包满与存档。
	var before: Dictionary = economy.warehouse.all()
	check(not economy.construction_pay({"wood":99999,"coins":1}), "材料不足不扣款")
	check(economy.warehouse.all() == before, "失败不会损失仓库材料")
	economy.warehouse.from_dict({"capacity":1,"counts":{"wood":40}})
	economy.inventory.set_count("parts", 4)
	economy.deposit_materials()
	check(economy.count("parts") == 4, "仓满材料留在背包")
	economy.inventory.from_dict({"capacity":1,"counts":{"parts":30}})
	check(economy.withdraw_material("wood").has("blocked") and economy.warehouse.count("wood") == 40, "包满取出不损失")
	economy.inventory.clear()
	check(not economy.withdraw_material("wood").has("blocked") and economy.count("wood") == 40, "取回材料")
	economy.inventory.from_dict({"capacity":24,"counts":{"coins":100,"wood":10,"parts":8,"rope":4}})
	economy.warehouse.from_dict({"capacity":48})
	economy.deposit_materials()
	check(economy.upgrade_ship().get("ok", false), "库存材料升级船")
	check(root.get_node("Zones").is_unlocked("zone4") and farm._access_reason("platform_plot") == "", "船升级开放远海和第三种植床")
	economy.track_goal("greenhouse")
	var snapshot: Dictionary = economy.to_dict()
	economy.warehouse.clear()
	economy.tracked_goal = ""
	economy.from_dict(snapshot)
	check(economy.warehouse.all() == snapshot.warehouse.counts and economy.tracked_goal == "greenhouse", "库存目标读档恢复")
	check(economy.site_level("rooftop_planter") == 2 and economy.ship_level == 2, "解锁进度读档恢复")
	var speed: float = main.boat.cruise_speed()
	economy.give({"coins":100,"wood":10,"parts":8,"rope":4})
	check(economy.upgrade_ship().get("ok", false), "三级船升级")
	check(is_equal_approx(main.boat.cruise_speed(), speed * 1.15), "三级船巡航提高15%")
	check(not economy.upgrade_ship().get("ok", true), "满级不能重复付费升级")
	economy.coins = 0
	check(board.reroll().ok and economy.coins == 0, "零海贝免费换单")
	# 奖励容量必须在扣除货物后的空间上检查。
	economy.inventory.from_dict({"capacity":1,"counts":{"wood":40}})
	board.slots[0] = {"uid":"full", "item":"wood", "amount":1, "pay":8, "bonus":{"rope":1}}
	check(not board.fulfill("full").ok and economy.count("wood") == 40, "奖励装不下不扣货")
	board.slots[0].amount = 40
	check(board.fulfill("full").ok and economy.count("rope") == 1, "扣货释放的空间可接奖励")
	economy.from_dict({"inventory":{"counts":{"wood":3}},"site_levels":{"home_cabin":2}})
	check(economy.warehouse.slots_used() == 0 and economy.warehouse.capacity() == 48, "旧存档迁移空仓库")
	check(economy.count("wood") == 3 and economy.site_level("home_cabin") == 2, "旧档保留已有资产")
	main.queue_free()
	await process_frame
	print("[management] %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
