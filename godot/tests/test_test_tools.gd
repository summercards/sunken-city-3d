extends SceneTree
## SEA-TOOL 验收：P 键面板的「测试」页到底有没有真的改到游戏状态。
##
## 只验四类动作，全部走「用户点按钮」的同一条函数：
##   1. 加货币/资源 → 落到 Inventory（容量、堆叠规则仍在）；
##   2. 改时间 → 只动 WorldClock 的公开字段，跨午夜把天数带过去；
##   3. 换天气 → 调 WeatherService.set_weather，非法值被拒；
##   4. 回体力 → EnergyModel.refill。
## 另加两条「不发散」的约束：默认页仍是滤镜；测试页打开时不锁昼夜预览。
##
## 这里不截图：版面属于 visual-* 的活，这一支只回答「行为对不对」。

var checks := 0
var failures := 0
var main: Node
var economy: Node


func _init() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	print("[test-tools] ", "PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.world_clock.paused = true
	economy = root.get_node("Economy")
	economy.set_process(false)

	var grade = main.grade
	check(grade != null, "P 面板装配到主场景")
	if grade == null:
		finish()
		return
	check(String(grade._tab) == "filter", "默认仍停在滤镜页，测试页不抢开场")
	grade.set_open(true)
	grade.set_tab("test")
	var page = grade.test_tools()
	check(page != null and grade._test_wrap.visible, "「测试」页可切换并显示")
	if page == null:
		finish()
		return

	# 1) 资源。只挑起始为 0 的三种材料，断言「恰好 +10」才能抓住
	#    「加进了别的格子」或「被溢出吞掉」这两种错。
	var wood: int = economy.count("wood")
	var parts: int = economy.count("parts")
	var fish: int = economy.count("fish")
	page.add_item("wood", 10)
	check(economy.count("wood") == wood + 10, "木板 +10 落到 Inventory")
	page.add_item("coins", 100)
	check(economy.count("coins") >= 100, "瓶盖 +100 落到 Inventory")
	page.add_all(10)
	check(economy.count("parts") == parts + 10 and economy.count("fish") == fish + 10,
		"「全部 +10」覆盖到不在第一排的物品")
	check(economy.count("wood") == wood + 20, "「全部 +10」和单项加的是同一本账")
	check(not page._item_buttons.is_empty() and page._item_buttons.has("wood"),
		"资源格子按物品表生成（不是写死的一排）")

	# 2) 时间。
	main.world_clock.day = 1
	main.world_clock.seconds = 7 * 3600.0
	page.shift_hours(3)
	check(is_equal_approx(main.world_clock.query().hour, 10.0), "加 3 小时 → 10:00")
	page.jump_to_hour(17.0)
	check(is_equal_approx(main.world_clock.query().hour, 17.0) and main.world_clock.day == 1,
		"跳到夕阳时刻不改日期")
	page.shift_days(1)
	check(main.world_clock.day == 2 and is_equal_approx(main.world_clock.query().hour, 17.0),
		"+1 天保留时刻")
	page.shift_days(-1)
	check(main.world_clock.day == 1, "-1 天退回")
	main.world_clock.day = 1
	main.world_clock.seconds = 23.5 * 3600.0
	page.shift_hours(1)
	check(main.world_clock.day == 2 and is_equal_approx(main.world_clock.query().hour, 0.5),
		"跨午夜把天数带过去")
	check(int(main.world_clock.query().day) >= 1, "第 0 天不会出现（存档契约 day >= 1）")

	# 3) 天气。
	page.set_weather("rain")
	check(main.weather_service.kind == "rain" and is_equal_approx(main.weather_service.query().rain, 1.0),
		"换天气改的是 WeatherService，查询立刻是雨")
	page.set_weather("cloudy")
	check(main.weather_service.kind == "cloudy", "可以再切多云")
	page.set_weather("typhoon")
	check(main.weather_service.kind == "cloudy", "非法天气被拒且状态不变")

	# 4) 体力。
	economy.energy.current = 3.0
	page.refill_energy()
	check(is_equal_approx(economy.energy.current, economy.energy.maximum), "体力回满走 EnergyModel.refill")

	# 5) 预览：测试页必须放开，否则改完时刻画面还停在旧的那一段。
	var rig = main.daylight_rig
	check(rig != null, "昼夜装置已装配")
	if rig != null:
		check(not rig.is_previewing(), "测试页打开时不锁昼夜预览")
		grade.set_tab("light")
		check(rig.is_previewing(), "回到光照页重新锁上预览")
		grade.set_tab("test")
		check(not rig.is_previewing(), "切回测试页又放开")
		grade.set_open(false)
		check(not rig.is_previewing(), "关面板放开预览")

	finish()


func finish() -> void:
	print("[test-tools] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
