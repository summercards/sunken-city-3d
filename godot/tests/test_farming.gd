extends SceneTree
var checks := 0
var failures := 0
var farm: Node
var economy: Node
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func _init() -> void:
	call_deferred("run")
func grow(id: String) -> void:
	for i in 10:
		if farm.phase(id) == "ready": return
		farm.refill()
		farm.water(id)
		farm.advance_day()
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	economy = root.get_node("Economy")
	economy.ticking = false
	farm = economy.farm
	check(farm.specs.size() == 13, "13 个独立地格（太阳房 1 + 圆弧农场 6 + 浅水 6）")
	check(get_nodes_in_group("farm_beds").size() == 3, "三个场景种植床")
	check(economy.count("lettuce_seed") == 3, "新游戏赠送三个生菜种子")
	economy.inventory.clear()
	economy.give({"coins":80})
	farm.from_dict({})
	check(not farm.buy_seed("lettuce").has("blocked"), "购买种子")
	check(economy.coins == 76 and economy.count("lettuce_seed") == 1, "购买准确扣款")
	check(farm.plant("home_plot","lettuce").get("event") == "planted", "播种")
	check(farm.is_empty("platform_plot:3"), "相邻格独立")
	farm.tick(100000)
	farm.advance_day()
	check(farm.state("home_plot").remaining == 3, "真实时间和干旱日不生长")
	farm.water("home_plot")
	check(farm.watering_can == 11, "浇水消耗一份")
	check(farm.water("home_plot").has("blocked") and farm.watering_can == 11, "重复浇水不消耗")
	grow("home_plot")
	check(farm.phase("home_plot") == "ready", "三个湿润日成熟")
	check(farm.harvest("home_plot").get("event") == "harvested", "收获")
	check(economy.count("vegetable") == 2 and farm.is_empty("home_plot"), "产量与地格复位")
	check(farm.sell_produce().get("income") == 12 and economy.coins == 88, "出售收入及利润")
	farm.buy_seed("lettuce")
	check(farm.plant("home_plot","lettuce").get("event") == "planted", "收入再投入闭环")
	check(farm.plant("unknown","lettuce").has("blocked"), "未知地格不可播种")
	farm.buy_seed("tomato")
	# 太阳房已并为单格：多茬用例放到浅水台，那里才是当前可连作的格子。
	# 浅水台要船 2 级才开放，原测试在更靠后处才抬等级，这里必须先给上。
	economy.ship_level = 2
	check(farm.plant("platform_plot:3","tomato").get("event") == "planted", "浅水台可播种番茄")
	for n in 3:
		grow("platform_plot:3")
		farm.harvest("platform_plot:3")
		check(economy.count("tomato") == (n+1)*2, "番茄第 %d 茬" % (n+1))
		check(farm.is_empty("platform_plot:3") == (n==2), "第三茬后清空")
	farm.from_dict({})
	economy.inventory.clear()
	var accessible: Array = []
	for row in farm.specs:
		economy.site_levels[str(row.requires_site)] = 9
		if farm.access_reason(str(row.id)) == "":
			accessible.append(str(row.id))
	check(accessible.size() >= 2, "至少两格在当前范围可用")
	economy.give({"lettuce_seed": accessible.size(), "coins": 80})
	for id in accessible: farm.plant(str(id), "lettuce")
	# 水壶只有 12 份，可用格数随范围变化；直接把壶压到 1 滴验证「见底/补水」两条边界。
	farm.watering_can = 1
	check(farm.water(str(accessible[0])).get("event") == "watered", "最后一滴水能浇上")
	check(farm.watering_can == 0, "水壶用尽")
	check(farm.water(str(accessible[1])).has("blocked"), "空壶拒绝")
	farm.refill()
	check(farm.water(str(accessible[1])).get("event") == "watered", "补水继续")
	var saved: Dictionary = farm.to_dict()
	farm.advance_day()
	farm.from_dict(saved)
	check(farm.to_dict() == saved, "日期水壶全格完整存档往返")
	# 太阳房 6 格并为 1 格：旧档里剩下的子格作物不能凭空消失。
	farm.register_plot({"id":"legacy_probe","zone":"zone1","name":"迁移探针"})
	farm.from_dict({"version":2,"plots":{
		"legacy_probe":{},
		"legacy_probe:1":{"crop":"lettuce","remaining":3.0,"total":3.0,"water":1.0,"harvests":0},
		"legacy_probe:2":{"crop":"lettuce","remaining":1.0,"total":3.0,"water":1.0,"harvests":0}}})
	check(farm.crop_of("legacy_probe") == "lettuce" and farm.state("legacy_probe").remaining == 1.0,
		"被删除子格中最近成熟的那一格搬进保留格")
	farm.from_dict({"plots":{"home_plot":{"crop":"lettuce","remaining":15.0,"total":30.0,"water":8.0}}})
	check(farm.state("home_plot").remaining == 2 and not farm.is_dry("home_plot"), "旧秒制按进度向上迁移天数")
	check(farm.is_empty("platform_plot:3"), "旧箱映射第一格保留下来的单格")
	grow("home_plot")
	economy.inventory.clear()
	economy.give({"coins":80,"wood":960})
	check(farm.harvest("home_plot").has("blocked") and farm.phase("home_plot")=="ready", "满包保留成熟作物")
	check(farm.buy_seed("lettuce").has("blocked") and economy.coins==80, "满包买种不扣钱")
	var state: Node = root.get_node("GameState")
	state.set_mode(state.Mode.ON_BOAT)
	var before: int = farm.day
	main._rest_for_day()
	check(farm.day==before, "在船上不能休息跳日")
	print("[farming] %d checks, %d failed" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
