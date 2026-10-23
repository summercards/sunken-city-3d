extends SceneTree

const ZoneSpecsLib = preload("res://tests/parity/zones.gd")
const EconomyLib = preload("res://tests/parity/economy.gd")
const SailNavLib = preload("res://tests/parity/sail_nav.gd")

## 核心层 parity 测试：逐条对应 sea/tests/economy-unit.cjs 与 sail-nav-unit.cjs。
## 运行：Godot --headless --path godot --script res://tests/test_core.gd

var checks := 0
var failures := 0
var current := ""


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL [%s] %s" % [current, msg])


func eq(actual: Variant, expected: Variant, msg: String) -> void:
	check(_deep_eq(actual, expected), "%s\n      got:  %s\n      want: %s" % [msg, _fmt(actual), _fmt(expected)])


func match_text(text: String, pattern: String, msg: String) -> void:
	var re := RegEx.new()
	re.compile(pattern)
	check(re.search(text) != null, "%s\n      text: %s\n      want match: %s" % [msg, text, pattern])


func _fmt(v: Variant) -> String:
	return JSON.stringify(v) if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY else str(v)


func _deep_eq(a: Variant, b: Variant, eps: float = 1e-9) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var na := ta == TYPE_INT or ta == TYPE_FLOAT
	var nb := tb == TYPE_INT or tb == TYPE_FLOAT
	if na and nb:
		var fa := float(a)
		var fb := float(b)
		if is_inf(fa) or is_inf(fb):
			return fa == fb
		return absf(fa - fb) <= eps
	if ta != tb:
		return false
	if ta == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deep_eq(a[i], b[i], eps):
				return false
		return true
	if ta == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a.keys():
			if not b.has(k):
				return false
			if not _deep_eq(a[k], b[k], eps):
				return false
		return true
	if ta == TYPE_VECTOR2 or ta == TYPE_VECTOR3 or ta == TYPE_RECT2:
		return a.is_equal_approx(b)
	return a == b


func make_state(overrides: Dictionary = {}) -> Dictionary:
	var s := {
		"coins": 80, "wood": 0, "parts": 0, "seeds": 3, "food": 0, "fish": 0, "pearl": 0,
		"shipLevel": 1, "farSeaUnlocked": false, "currentZone": "zone1",
		"workerMode": "IDLE_ASHORE", "activeJobSite": null,
	}
	for k in overrides.keys():
		s[k] = overrides[k]
	return s


func make(overrides: Dictionary = {}, levels: Dictionary = {}) -> Dictionary:
	var state := make_state(overrides)
	var lv := levels.duplicate(true)
	var eco := EconomyLib.new(state, func(id): return lv.get(id, 0))
	return {"state": state, "levels": lv, "eco": eco}


func snapshot(ctx: Dictionary) -> Dictionary:
	return {
		"state": ctx.state.duplicate(true),
		"nodes": ctx.eco.nodes.duplicate(true),
		"plots": ctx.eco.plots.duplicate(true),
		"facilities": ctx.eco.facilities.duplicate(true),
		"job": ctx.eco.job.duplicate(true) if ctx.eco.job != null else null,
	}


func unchanged(ctx: Dictionary, op: Callable) -> Variant:
	var before := snapshot(ctx)
	var result: Variant = op.call()
	eq(snapshot(ctx), before, "操作不应改变任何状态")
	return result


const COMPLETE_LEVELS := {"home_cabin": 2, "rooftop_planter": 1, "yokohama_station": 1}


func _init() -> void:
	test_config()
	test_transactions()
	test_invalid_bundles()
	test_capacity()
	test_collections()
	test_cooldown()
	test_sea_cache()
	test_plots()
	test_plot_growth()
	test_greenhouse()
	test_facilities()
	test_recycler()
	test_ship()
	test_trade()
	test_explore()
	test_big_tick()
	test_zones()
	test_sail_nav()

	print("\n%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_config() -> void:
	current = "config"
	var caps := {}
	for key in EconomyLib.MATERIALS.keys():
		caps[key] = [EconomyLib.MATERIALS[key].name, EconomyLib.MATERIALS[key].capacity]
	eq(caps, {
		"coins": ["海贝", INF], "wood": ["木料", 60.0], "parts": ["旧零件", 60.0],
		"seeds": ["种子", 20.0], "food": ["食物", 40.0], "fish": ["鱼", 40.0], "pearl": ["珍珠", 12.0],
	}, "材料名称与容量")
	eq(EconomyLib.HARVEST_THRESHOLD, 10, "挂机收取阈值")
	eq(EconomyLib.EXPLORE, {"step": 7.0, "chance": 0.6, "wood": [1, 2], "parts": [0, 1]}, "探索配置")
	eq(EconomyLib.CROP.dryDuration, 34.0, "干旱时长")
	eq(EconomyLib.CROP.greenhouseDuration, 26.0, "温室时长")
	eq(EconomyLib.COLLECTIONS.size(), 5, "采集点数量")

	var ctx := make()
	eq(ctx.eco.nodes.size(), 5, "节点实例化")
	eq(ctx.eco.nodes[0].left, 0.0, "初始冷却为 0")
	eq(ctx.eco.plots.size(), 2, "两个菜箱")
	eq(ctx.eco.facilities, {"greenhouse": {"level": 0, "stored": {}}, "recycler": {"level": 0, "stored": {}, "timer": 0.0}}, "设施初始状态")
	eq(ctx.eco.job, null, "无施工任务")

	# 实例之间互不影响。
	ctx.eco.nodes[0].reward.wood = 99
	ctx.eco.facilities.recycler.stored.parts = 6
	eq(EconomyLib.COLLECTIONS[0].reward.wood, 3, "配置常量不被实例改写")
	var other := make()
	eq(other.eco.nodes[0].reward.wood, 3, "新实例材料独立")
	eq(other.eco.facilities.recycler.stored, {}, "新实例设施独立")


func test_transactions() -> void:
	current = "transactions"
	# 对照原测试：空状态，用来验证"不存在的余额按 0 计算"。
	var state: Dictionary = {}
	var eco := EconomyLib.new(state, func(_id): return 0)
	eq(eco.missing({"coins": 4, "wood": 0, "food": 2}), {"coins": 4, "food": 2}, "不存在的余额按 0 计算")
	eq(state, {}, "查询无副作用")
	eq(eco.spend({"coins": 1}), false, "余额不足不能扣款")
	eq(state, {}, "失败不落盘")
	eq(eco.can_receive({"wood": 60, "seeds": 20}), true, "容量内可接收")
	eq(eco.receive({"wood": 60, "seeds": 20}), true, "接收满容量")
	eq(state, {"wood": 60, "seeds": 20}, "收支落盘")
	eq(eco.spend({"wood": 3, "seeds": 2}), true, "正常扣款")
	eq(state, {"wood": 57, "seeds": 18}, "扣款后余额")
	eq(eco.missing({"wood": 60, "seeds": 18}), {"wood": 3}, "缺口计算")
	eq(eco.spend({}), true, "空清单视为成功")
	eq(eco.receive({}), true, "空奖励视为成功")
	eq(eco.receive({"coins": 1000000000}), true, "海贝高额度")


func test_invalid_bundles() -> void:
	current = "invalid-bundles"
	var ctx := make({"wood": 10, "parts": 10})
	var invalid: Array = [
		null, 1, "wood", [], {"wood": 1, "unknown": 2},
		{"wood": -1}, {"wood": 1.5}, {"wood": "1"}, {"wood": true}, {"wood": null},
	]
	for bundle in invalid:
		eq(unchanged(ctx, func(): return ctx.eco.can_receive(bundle)), false, "非法清单不接收")
		eq(unchanged(ctx, func(): return ctx.eco.receive(bundle)), false, "非法清单不入账")
		eq(unchanged(ctx, func(): return ctx.eco.spend(bundle)), false, "非法清单不扣款")


func test_capacity() -> void:
	current = "capacity"
	var ctx := make({"wood": 10, "parts": 10})
	var state: Dictionary = ctx.state
	eq(unchanged(ctx, func(): return ctx.eco.spend({"wood": 1, "parts": 11})), false, "不足不部分提交")
	for key in EconomyLib.MATERIALS.keys():
		var capacity: float = float(EconomyLib.MATERIALS[key].capacity)
		if is_inf(capacity):
			continue
		state[key] = int(capacity)
		eq(unchanged(ctx, func(): return ctx.eco.receive({"coins": 1, key: 1})), false, "%s 满仓拒绝" % key)
		eq(unchanged(ctx, func(): return ctx.eco.can_receive({key: 1})), false, "%s 满仓不可接收" % key)
		eq(ctx.eco.spend({key: 1}), true, "%s 可花掉" % key)
		eq(ctx.eco.receive({key: 1}), true, "%s 可补回" % key)


func test_collections() -> void:
	current = "collections"
	var names := {"zone1": "sea", "zone2": "横滨铁道", "zone3": "圆弧农场", "zone4": "远海街町"}
	for node in EconomyLib.COLLECTIONS:
		var ctx := make({"farSeaUnlocked": true, "currentZone": "elsewhere"})
		var state: Dictionary = ctx.state
		eq(ctx.eco.get_collection_action(node.id), {"available": false, "reason": "先前往%s靠岸" % names[node.zone]}, "异地拒绝")
		eq(unchanged(ctx, func(): return ctx.eco.collect(node.id)).ok, false, "异地不产出")
		state.currentZone = node.zone
		for mode in ["SAILING", "WALKING", "CRAFTING"]:
			state.workerMode = mode
			eq(ctx.eco.get_collection_action(node.id).reason, "旅人忙碌中", "%s 忙碌" % mode)
			eq(unchanged(ctx, func(): return ctx.eco.collect(node.id)).ok, false, "%s 不产出" % mode)
		state.workerMode = "IDLE_ASHORE"
		state.activeJobSite = "home_cabin"
		eq(ctx.eco.get_collection_action(node.id).reason, "旅人忙碌中", "施工中忙碌")
		state.activeJobSite = null
		var result: Dictionary = ctx.eco.collect(node.id)
		eq(result.ok, true, "%s 采集成功" % node.id)
		eq(result.reward, node.reward, "%s 奖励正确" % node.id)


func test_cooldown() -> void:
	current = "cooldown"
	var ctx := make()
	var state: Dictionary = ctx.state
	eq(ctx.eco.collect("home_crate").ok, true, "首次采集")
	eq(unchanged(ctx, func(): return ctx.eco.collect("home_crate")).ok, false, "冷却中禁止重复")
	eq(ctx.eco.nodes[0].collections, 1, "采集计数")
	match_text(ctx.eco.get_collection_action("home_crate").reason, "34秒", "冷却显示 34 秒")
	ctx.eco.tick(1.25)
	eq(ctx.eco.nodes[0].left, 32.75, "冷却推进")
	match_text(ctx.eco.get_collection_action("home_crate").reason, "33秒", "冷却向上取整")
	state.currentZone = "zone3"
	eq(ctx.eco.collect("garden_cache").ok, true, "另一节点独立冷却")
	ctx.eco.tick(32.75)
	eq(ctx.eco.nodes[0].left, 0.0, "主节点冷却归零")
	eq(ctx.eco.nodes[2].left, 9.25, "农场节点剩余冷却")
	state.currentZone = "zone1"
	var reward: Dictionary = ctx.eco.collect("home_crate").reward
	reward.wood = 999
	eq(ctx.eco.nodes[0].reward.wood, 3, "返回值是副本")
	ctx.eco.tick(1000.0)
	for node in ctx.eco.nodes:
		eq(node.left, 0.0, "大步 tick 清空冷却")


func test_sea_cache() -> void:
	current = "sea-cache"
	var ctx := make({"currentZone": "zone4"})
	var state: Dictionary = ctx.state
	match_text(ctx.eco.get_collection_action("sea_cache").reason, "未解锁", "远海锁")
	state.farSeaUnlocked = true
	state.pearl = 12
	match_text(ctx.eco.get_collection_action("sea_cache").reason, "库存已满.*珍珠", "珍珠满仓")
	state.pearl = 11
	eq(ctx.eco.collect("sea_cache").ok, true, "解锁后可采")
	eq(state.pearl, 12, "珍珠到账")
	eq(state.parts, 2, "零件到账")


func test_plots() -> void:
	current = "plots"
	var ctx := make()
	var state: Dictionary = ctx.state
	var levels: Dictionary = ctx.levels
	match_text(ctx.eco.get_plot_action("home_plot").reason, "需2级", "等级不足")
	eq(unchanged(ctx, func(): return ctx.eco.act_plot("home_plot")).ok, false, "等级不足不播种")
	levels.home_cabin = 2
	eq(ctx.eco.get_plot_action("home_plot"), {"available": true, "reason": "", "label": "播种"}, "可播种")
	match_text(ctx.eco.get_plot_action("farm_plot").reason, "先前往圆弧农场靠岸", "异区菜箱")
	state.currentZone = "zone3"
	match_text(ctx.eco.get_plot_action("farm_plot").reason, "需1级", "农场未建")
	levels.rooftop_planter = 1
	state.activeJobSite = "rooftop_planter"
	eq(ctx.eco.get_plot_action("farm_plot").reason, "旅人忙碌中", "施工中")
	state.activeJobSite = null
	state.workerMode = "SAILING"
	eq(unchanged(ctx, func(): return ctx.eco.act_plot("farm_plot")).ok, false, "航行中不播种")
	state.workerMode = "IDLE_ASHORE"
	state.seeds = 0
	match_text(ctx.eco.get_plot_action("farm_plot").reason, "种子缺1.*来源", "缺种子")
	state.seeds = 1
	eq(ctx.eco.act_plot("farm_plot").ok, true, "播种成功")
	eq(state.seeds, 0, "扣种子")
	eq(ctx.eco.plots[1].remaining, 34.0, "生长计时 34 秒")
	eq(ctx.eco.plots[0].phase, "empty", "另一菜箱不受影响")


func test_plot_growth() -> void:
	current = "plot-growth"
	var ctx := make({}, COMPLETE_LEVELS)
	var state: Dictionary = ctx.state
	var plot: Dictionary = ctx.eco.plots[0]
	eq(ctx.eco.act_plot("home_plot"), {"ok": true, "reason": ""}, "播种")
	eq(state.seeds, 2, "扣一颗种子")
	eq(ctx.eco.busy(), false, "播种不算忙碌")
	eq(plot.moisture, 1.0, "播种后湿润")
	eq(plot.reward, {"food": 2, "seeds": 1}, "奖励快照")
	eq(unchanged(ctx, func(): return ctx.eco.act_plot("home_plot")).ok, false, "湿润时只是补水，不重复扣种")

	ctx.eco.tick(18.0)
	eq(plot.moisture, 0.0, "18 秒后干透")
	eq(plot.remaining, 16.0, "只长了 18 秒")
	ctx.eco.tick(100.0)
	eq(plot.remaining, 16.0, "干透后停止生长")
	eq(plot.phase, "growing", "仍未成熟")
	eq(ctx.eco.get_plot_action("home_plot"), {"available": true, "reason": "", "label": "浇水"}, "可浇水")
	eq(ctx.eco.act_plot("home_plot").ok, true, "浇水")
	eq(plot.moisture, 1.0, "重新湿润")
	eq(state.seeds, 2, "浇水不扣种")
	ctx.eco.tick(16.0)
	eq(plot.phase, "ready", "成熟")
	eq(ctx.eco.get_plot_action("home_plot"), {"available": true, "reason": "", "label": "收获"}, "可收获")
	var harvest: Dictionary = ctx.eco.act_plot("home_plot")
	eq(harvest, {"ok": true, "reason": "", "reward": {"food": 2, "seeds": 1}}, "收获结果")
	eq(state.food, 2, "食物到账")
	eq(state.seeds, 3, "种子返还")
	eq(plot.phase, "empty", "回到空箱")
	eq(plot.reward, null, "清空奖励")
	eq(plot.moisture, 0.0, "清空湿度")


func test_greenhouse() -> void:
	current = "greenhouse"
	var ctx := make({"wood": 10, "parts": 10}, COMPLETE_LEVELS)
	var state: Dictionary = ctx.state
	ctx.eco.act_plot("home_plot")
	eq(ctx.eco.build_facility("greenhouse").ok, true, "开始建温室")
	ctx.eco.tick(6.0)
	eq(ctx.eco.facilities.greenhouse.level, 1, "温室完工")
	eq(ctx.eco.plots[0].duration, 34.0, "在种作物保留旧快照")
	eq(ctx.eco.plots[0].remaining, 28.0, "施工期间湿润生长")
	eq(ctx.eco.plots[0].reward, {"food": 2, "seeds": 1}, "旧奖励不变")
	ctx.eco.tick(12.0)
	eq(ctx.eco.plots[0].moisture, 0.0, "再次干透")
	eq(ctx.eco.plots[0].remaining, 16.0, "剩余 16 秒")
	ctx.eco.act_plot("home_plot")
	ctx.eco.tick(16.0)
	eq(ctx.eco.act_plot("home_plot").reward, {"food": 2, "seeds": 1}, "旧作物仍是 2 食物")
	ctx.eco.act_plot("home_plot")
	eq(ctx.eco.plots[0].duration, 26.0, "新种 26 秒")
	eq(ctx.eco.plots[0].reward, {"food": 3, "seeds": 1}, "新种 3 食物")
	eq(state.food, 2, "只收过一批")


func test_facilities() -> void:
	current = "facilities"
	var ctx := make({"coins": 14, "wood": 3, "parts": 2})
	var levels: Dictionary = ctx.levels
	var state: Dictionary = ctx.state
	match_text(ctx.eco.get_facility_action("greenhouse").reason, "需2级.*需1级", "前置建筑不足")
	eq(unchanged(ctx, func(): return ctx.eco.build_facility("greenhouse")).ok, false, "前置不足不建")
	levels.home_cabin = 2
	levels.rooftop_planter = 1
	var reason: String = ctx.eco.get_facility_action("greenhouse").reason
	match_text(reason, "海贝缺1", "缺口海贝")
	match_text(reason, "木料缺2", "缺口木料")
	match_text(reason, "旧零件缺1", "缺口零件")
	match_text(reason, "来源", "缺口带来源")
	match_text(ctx.eco.get_facility_action("recycler").reason, "横滨.*需1级", "回收台前置")
	levels.yokohama_station = 1
	match_text(ctx.eco.get_facility_action("recycler").reason, "木料缺1.*旧零件缺2", "回收台缺口")

	var build := make({"wood": 30, "parts": 20, "food": 4}, COMPLETE_LEVELS)
	var bstate: Dictionary = build.state
	eq(build.eco.build_facility("greenhouse"), {"ok": true, "reason": ""}, "建造温室")
	eq([bstate.coins, bstate.wood, bstate.parts], [65, 25, 17], "一次扣完整成本")
	eq(build.eco.job, {"id": "greenhouse", "remaining": 6.0, "duration": 6.0}, "施工任务 6 秒")
	eq(bstate.workerMode, "CRAFTING", "进入施工状态")
	eq(build.eco.busy(), true, "施工中忙碌")
	eq(build.eco.get_facility_action("greenhouse").label, "施工中", "按钮文案")
	bstate.workerMode = "IDLE_ASHORE"
	eq(build.eco.busy(), true, "任务未完成仍忙碌")
	eq(unchanged(build, func(): return build.eco.collect("home_crate")).reason, "旅人忙碌中", "施工锁定采集")
	eq(unchanged(build, func(): return build.eco.upgrade_ship()).reason, "旅人忙碌中", "施工锁定升级")
	bstate.workerMode = "CRAFTING"
	build.eco.tick(5.5)
	eq(build.eco.job.remaining, 0.5, "施工进度")
	eq(build.eco.facilities.greenhouse.level, 0, "未完工")
	build.eco.tick(0.5)
	eq(build.eco.job, null, "任务清空")
	eq(build.eco.facilities.greenhouse.level, 1, "完工")
	eq(bstate.workerMode, "IDLE_ASHORE", "恢复待机")
	eq(unchanged(build, func(): return build.eco.build_facility("greenhouse")).ok, false, "禁止重复建造")


func test_recycler() -> void:
	current = "recycler"
	var ctx := make({"wood": 10, "parts": 10}, COMPLETE_LEVELS)
	var state: Dictionary = ctx.state
	eq(ctx.eco.build_facility("recycler").ok, true, "建回收台")
	ctx.eco.tick(6.0)
	eq(state.parts, 6, "建造成本扣除")
	var recycler: Dictionary = ctx.eco.get_facility("recycler")
	eq(recycler, ctx.eco.facilities.recycler, "设施引用一致")
	eq(recycler.stored, {}, "初始无暂存")
	eq(ctx.eco.get_facility_action("recycler").available, false, "空暂存不可取")
	ctx.eco.tick(29.5)
	eq(recycler.stored, {}, "未满 30 秒")
	eq(recycler.timer, 29.5, "计时 29.5")
	ctx.eco.tick(0.5)
	eq(recycler.stored, {"parts": 2}, "满 30 秒产出 2")
	eq(state.parts, 6, "暂存不自动入库")
	eq(ctx.eco.get_facility_action("recycler"), {"available": true, "reason": "", "label": "收取零件"}, "可收取")
	ctx.eco.tick(60.0)
	eq(recycler.stored, {"parts": 6}, "最多存 6")
	ctx.eco.tick(10000.0)
	eq(recycler.stored, {"parts": 6}, "满仓不再生产")
	eq(recycler.timer, 0.0, "满仓计时清零")
	eq(ctx.eco.collect_facility("recycler"), {"ok": true, "reason": "", "reward": {"parts": 6}}, "收走 6 个")
	eq(state.parts, 12, "零件入库")
	ctx.eco.tick(29.0)
	eq(recycler.stored, {}, "收取后重新计时")
	ctx.eco.tick(1.0)
	eq(recycler.stored, {"parts": 2}, "30 秒后再产 2")

	# 大步 tick 切分施工与生产。
	for row in [[6.0, 0, 0.0], [30.0, 0, 24.0], [35.0, 0, 29.0], [36.0, 2, 0.0], [65.0, 2, 29.0], [96.0, 6, 0.0]]:
		var c2 := make({"wood": 10, "parts": 10}, COMPLETE_LEVELS)
		c2.eco.build_facility("recycler")
		c2.eco.tick(row[0])
		eq(c2.eco.job, null, "dt=%s 完工" % row[0])
		eq(int(c2.eco.facilities.recycler.stored.get("parts", 0)), row[1], "dt=%s 产出" % row[0])
		eq(c2.eco.facilities.recycler.timer, row[2], "dt=%s 计时" % row[0])

	# 分帧推进与一次推进等价。
	var once := make({"wood": 10, "parts": 10}, COMPLETE_LEVELS)
	var split := make({"wood": 10, "parts": 10}, COMPLETE_LEVELS)
	once.eco.build_facility("recycler")
	split.eco.build_facility("recycler")
	once.eco.tick(65.0)
	for dt in [2.0, 3.0, 1.0, 0.5, 29.5, 29.0]:
		split.eco.tick(dt)
	eq(snapshot(split), snapshot(once), "分帧与一次性推进一致")


func test_ship() -> void:
	current = "ship"
	var ctx := make({"wood": 6, "parts": 4})
	var state: Dictionary = ctx.state
	match_text(ctx.eco.get_ship_action().reason, "前置建筑不足", "升级前置")
	eq(unchanged(ctx, func(): return ctx.eco.upgrade_ship()).ok, false, "前置不足不升级")
	for k in COMPLETE_LEVELS.keys():
		ctx.levels[k] = COMPLETE_LEVELS[k]
	match_text(ctx.eco.get_ship_action().reason, "食物缺2.*来源", "食物不足")
	state.food = 2
	eq(ctx.eco.upgrade_ship(), {"ok": true, "reason": ""}, "升级成功")
	eq([state.coins, state.wood, state.parts, state.food], [55, 0, 0, 0], "升级扣料")
	eq(state.shipLevel, 2, "船只 2 级")
	eq(state.farSeaUnlocked, true, "远海解锁")
	match_text(ctx.eco.get_ship_action().reason, "已升级", "重复升级提示")
	state.currentZone = "zone4"
	eq(ctx.eco.collect("sea_cache").ok, true, "解锁后可采远海贝匣")


func test_trade() -> void:
	current = "trade"
	var ctx := make({"food": 1})
	var state: Dictionary = ctx.state
	eq(unchanged(ctx, func(): return ctx.eco.trade_food()).ok, false, "食物不足")
	state.food = 2
	state.currentZone = "zone3"
	eq(unchanged(ctx, func(): return ctx.eco.trade_food()).reason, "先前往sea靠岸", "异地不可交易")
	state.currentZone = "zone1"
	state.workerMode = "SAILING"
	eq(unchanged(ctx, func(): return ctx.eco.trade_food()).reason, "旅人忙碌中", "航行不可交易")
	state.workerMode = "IDLE_ASHORE"
	eq(ctx.eco.trade_food(), {"ok": true, "reason": "", "reward": {"coins": 12}}, "交易成功")
	eq(state.coins, 92, "海贝到账")
	eq(state.food, 0, "食物扣除")


func test_explore() -> void:
	current = "explore"
	var state := make_state()
	var eco := EconomyLib.new(state, func(_id): return 0, func() -> float: return 0.0)
	var short := eco.explore(6.9)
	eq(short.ok, false, "不足 7 米不出货")
	eq(short.pending, 6.9, "里程累计")
	var first := eco.explore(0.2)
	eq(first.ok, true, "跨过 7 米出发")
	eq(first.reward, {"wood": 1}, "必中木料下限")
	eq(first.finds, 1, "出货一次")
	check(absf(float(first.pending) - 0.1) < 1e-9, "剩余里程 0.1")
	var many := eco.explore(21.0)
	eq(many.finds, 3, "21 米判定三次")
	eq(many.reward, {"wood": 3}, "木料累加")
	eq(state.wood, 4, "累计入账")
	state.currentZone = "zone4"
	eq(eco.explore(7.0).ok, true, "异区照样探索")
	eq(state.wood, 5, "累计入账 2")

	var idle := EconomyLib.new(make_state(), func(_id): return 0, func() -> float: return 0.99)
	eq(idle.explore(70.0).ok, false, "从不命中")
	eq(idle.explore(3.0).pending, 3.0, "未命中只累计")


func test_big_tick() -> void:
	current = "big-tick"
	var ctx := make({"wood": 20, "parts": 20}, COMPLETE_LEVELS)
	ctx.eco.collect("home_crate")
	ctx.eco.act_plot("home_plot")
	ctx.eco.build_facility("recycler")
	for bad in [-1.0, NAN, INF, -INF]:
		var before := snapshot(ctx)
		eq(ctx.eco.tick(bad), false, "非法 dt 拒绝")
		eq(snapshot(ctx), before, "非法 dt 不推进")
	eq(ctx.eco.tick(0.0), true, "零时间合法")
	var before0 := snapshot(ctx)
	ctx.eco.tick(0.0)
	eq(snapshot(ctx), before0, "零时间不变")
	ctx.eco.tick(1e12)
	eq(ctx.eco.nodes[0].left, 0.0, "超大 tick 清空冷却")
	eq(ctx.eco.plots[0].phase, "growing", "一次湿透只长一截")
	eq(ctx.eco.plots[0].moisture, 0.0, "干透")
	eq(ctx.eco.plots[0].remaining, 16.0, "剩余 16 秒")
	eq(ctx.eco.job, null, "施工完成")
	eq(ctx.eco.facilities.recycler.stored, {"parts": 6}, "回收台满仓")


func test_zones() -> void:
	current = "zones"
	var reg := ZoneSpecsLib.create_registry()
	eq(reg.ids, ["zone1", "zone2", "zone3", "zone4", "zone5"], "五个区块")
	eq(reg.label("zone3"), "圆弧农场", "区块名称")
	eq(reg.get_zone("zone3").origin, Vector3(-2.25, 0.3, -36.0), "zone3 锚点")
	eq(reg.get_zone("zone2").boat_park, Vector3(-33.51, 1.12, -12.22), "zone2 停泊位（世界坐标）")
	eq(reg.get_zone("zone4").dock_edge, Vector3(36.2, 1.73, -37.4), "zone4 上岸边（世界坐标）")
	var zone1: Dictionary = reg.get_zone("zone1")
	eq(zone1.landings.size(), 2, "zone1 两个上岸点")
	eq(zone1.landings[1].id, "salvage", "打捞台上岸点")
	eq(zone1.landings[1].dockEdge, Vector3(-9.0, 1.33, 13.0), "打捞台上岸边")
	eq(reg.landing("zone1", "salvage").boatYaw, 0.0, "打捞台停泊朝向")
	eq(reg.landing("zone1", "unknown").id, "main", "未知上岸点回落到主码头")
	eq(reg.is_unlocked("zone4", {"farSeaUnlocked": false}), false, "远海初始锁定")
	eq(reg.is_unlocked("zone4", {"farSeaUnlocked": true}), true, "远海解锁")
	eq(reg.harbor_point("salvage"), Vector3(-12.0, 1.12, 13.0), "打捞点")
	eq(reg.harbor_point("dock"), Vector3(0.3, 1.12, 9.0), "交易码头")
	eq(reg.service_zones("salvage"), ["zone1"], "服务区块")
	# 区块间距下限 6m（对应 tests/zone-spacing.cjs）。
	for i in range(reg.list.size()):
		for j in range(i + 1, reg.list.size()):
			var a: Dictionary = reg.footprint(reg.list[i].id)
			var b: Dictionary = reg.footprint(reg.list[j].id)
			var dx: float = maxf(0.0, maxf(a.minX - b.maxX, b.minX - a.maxX))
			var dz: float = maxf(0.0, maxf(a.minZ - b.maxZ, b.minZ - a.maxZ))
			var gap := sqrt(dx * dx + dz * dz)
			check(gap >= 6.0, "%s 与 %s 间距 %.2f < 6" % [reg.list[i].id, reg.list[j].id, gap])


func test_sail_nav() -> void:
	current = "sail-nav"
	var bounds := Rect2(-20, -20, 40, 40)

	# 空旷水面：直连。
	var empty := SailNavLib.create_nav_grid([], bounds)
	var path: Variant = SailNavLib.plan_route(empty, Vector2(-10, -10), Vector2(10, 10))
	check(path != null and path.size() >= 2, "空旷水面应有路")
	check(SailNavLib.path_length(path) <= 28.28 * 1.05, "空旷水面不应绕远")

	# 一整排障碍：必须从端点绕过去。
	var wall := SailNavLib.create_nav_grid([Rect2(-15, -0.6, 30, 1.2)], bounds)
	path = SailNavLib.plan_route(wall, Vector2(0, -8), Vector2(0, 8))
	check(path != null, "墙应能绕")
	check(_segments_clear(wall, path).ok, "绕墙航迹不能穿墙")
	var went_around := false
	for p in path:
		if absf(p.x) > 15.0:
			went_around = true
	check(went_around, "没有绕到墙的端点")
	check(SailNavLib.path_length(path) < 60.0, "绕墙不应太远")

	# U 形口袋。
	var pocket := SailNavLib.create_nav_grid([
		Rect2(-8, -8, 2, 14), Rect2(6, -8, 2, 14), Rect2(-8, -8, 16, 2),
	], bounds, 0.5, 0.8)
	path = SailNavLib.plan_route(pocket, Vector2(0, -2), Vector2(0, 14))
	check(path != null, "口袋应有出口")
	check(_segments_clear(pocket, path).ok, "出袋航迹不能穿墙")

	# 完全封死。
	var sealed := SailNavLib.create_nav_grid([
		Rect2(-6, -6, 12, 2), Rect2(-6, 4, 12, 2), Rect2(-6, -6, 2, 12), Rect2(4, -6, 2, 12),
	], bounds, 0.5, 0.6)
	eq(SailNavLib.find_path(sealed, Vector2(0, 0), Vector2(14, 0)), null, "封死必须返回 null")

	# 起点压在障碍里：吸到最近空格。
	var block := SailNavLib.create_nav_grid([Rect2(-2, -2, 4, 4)], bounds, 0.5, 0.5)
	eq(SailNavLib.is_free(block, 0, 0), false, "障碍内不可通行")
	var snapped: Variant = SailNavLib.nearest_free(block, 0, 0, 20)
	check(snapped != null, "应找到最近空格")
	check(SailNavLib.is_free(block, snapped.x, snapped.z), "吸附点可通行")
	path = SailNavLib.plan_route(block, Vector2(0, 0), Vector2(12, 0))
	check(path != null and path.size() >= 2, "吸附后仍能规划")

	# 斜向夹角不许蹭过去。
	var pinch := SailNavLib.create_nav_grid([
		Rect2(-4, -4, 4.1, 3.9), Rect2(-0.1, 0.1, 4.1, 3.9),
	], bounds, 0.5, 0.5)
	path = SailNavLib.find_path(pinch, Vector2(2, -2), Vector2(-2, 2))
	check(path != null, "绕外面应还有路")
	check(_segments_clear(pinch, path).ok, "航迹不能从夹角蹭过去")

	# 重叠判定：半格压住障碍也算阻挡。
	var thin := SailNavLib.create_nav_grid([Rect2(0, -5, 0.2, 10)], bounds, 0.5, 0.0)
	eq(SailNavLib.is_free(thin, 0.4, 0), false, "半格重叠算阻挡")
	eq(SailNavLib.is_free(thin, 1.2, 0), true, "远处可通行")


func _segments_clear(grid: Dictionary, path: Array, step: float = 0.2) -> Dictionary:
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var d := a.distance_to(b)
		var n: int = maxi(1, int(ceil(d / step)))
		for s in range(0, n + 1):
			var t := float(s) / float(n)
			var x := a.x + (b.x - a.x) * t
			var z := a.y + (b.y - a.y) * t
			# 起点 / 终点允许压在障碍边上（船就停在那儿），中段不许。
			if s == 0 and i == 1:
				continue
			if not SailNavLib.is_free(grid, x, z):
				return {"ok": false, "at": [x, z], "seg": i}
	return {"ok": true}
