extends SceneTree
## 登陆标记双向 / 种植二级选种 / 固定天气 三件事的行为约定。
##
## 这三条都是「点一下应该发生什么」的交互契约，最容易在没有断言的情况下
## 悄悄退回旧行为：标记又变成只开船、单一种子又变成一键种、天气又开始自己变。
## 所以每条各给一个会失败的断言。
##
## 运行：python scripts/run_verification.py dock-seed
var main: Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _init() -> void: call_deferred("run")

## 把一个泊位的坐标取出来（世界坐标）。`Zones` 是 autoload，不挂在 main 实例上。
func park_of(zone_id: String, landing_id: String) -> Vector3:
	var l: Dictionary = root.get_node("Zones").landing(zone_id, landing_id)
	return Vector3(float(l.boatPark[0]), 1.12, float(l.boatPark[2]))

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	var state: Node = root.get_node("GameState")
	state.enter_zone("zone1")

	# ---- 1. 船上点当前泊位标记 → 上岸 ------------------------------------
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	var park := park_of("zone1", "main")
	main.boat.place_at(park, float(root.get_node("Zones").landing("zone1", "main").boatYaw))
	main._select_landing({"zone": "zone1", "landing": "main"})
	# 上岸是「走到泊位站立点」这一个动作；角色本来就在那个点上，一帧即完成。
	main._update_walk(1.0 / 60.0)
	check(main.actor_controller.state_id() == "ashore_idle", "船上点标记直接上岸")
	check(main.player.get_parent() == main, "上岸后角色挂在世界而不是船")
	check(main.player.global_position.distance_to(main._current_landing().stand_position()) < 0.05,
		"上岸落在泊位站立点")

	# ---- 2. 岸上点同一标记 → 上船 ----------------------------------------
	main._select_landing({"zone": "zone1", "landing": "main"})
	for i in 3: main._update_walk(1.0 / 60.0)
	check(main.actor_controller.state_id() == "boat_idle", "岸上点标记回到船上")
	check(main.player.get_parent() == main.boat, "上船后角色挂在船下")

	# ---- 3. 不在泊位时点标记 → 记下「到岸即上岸」 -------------------------
	main.boat.place_at(park + Vector3(0, 0, 6.0), 0.0)
	state.set_mode(state.Mode.ON_BOAT)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	main._select_landing({"zone": "zone1", "landing": "main"})
	check(main._ashore_on_arrival, "开过去时记下上岸意图")
	# 直接把船放回泊位并走一遍到达回调：不依赖真实航行时长。
	main.boat.place_at(park, float(root.get_node("Zones").landing("zone1", "main").boatYaw))
	main._on_boat_arrived("zone1", "main")
	main._update_walk(1.0 / 60.0)
	check(main.actor_controller.state_id() == "ashore_idle", "靠妥后自动上岸")
	check(not main._ashore_on_arrival, "上岸意图只消费一次")

	# ---- 4. 取消动作清掉上岸意图 ------------------------------------------
	main.boat.place_at(park + Vector3(0, 0, 6.0), 0.0)
	main._ashore_on_arrival = true
	main._cancel_action()
	check(not main._ashore_on_arrival, "取消后不再擅自送人下船")

	# ---- 5. 只有一种种子也弹二级，且带数量 --------------------------------
	var economy: Node = root.get_node("Economy")
	var cell: Node3D = main.farm_field.find("home_plot")
	economy.inventory.clear()
	economy.give({"lettuce_seed": 3})
	main._open_spot_bubbles(cell)
	var actions = main.hud.world_actions
	check(actions.entries.size() == 3, "地格一级仍是种植/浇水/收获三颗")
	check(str(actions.entries[0].id) == "plant", "第一颗是种植")
	actions.activate(0)
	check(actions.entries.size() == 1, "单一种子也弹二级")
	check(str(actions.entries[0].id) == "seed:lettuce", "二级列出可种种子")
	check(str(actions.entries[0].get("caption", "")) == "生菜 ×3", "二级标出名称与数量")
	check(actions.hint_label != null and actions.hint_label.text == "选择种子", "二级有层级标题")
	actions.close(true)

	# ---- 6. 天气是固定的晴天 ---------------------------------------------
	var weather = main.weather_service
	check(weather.fixed, "天气配置为固定模式")
	check(weather.kind == "clear", "固定天气是晴")
	weather.tick(600.0)
	check(weather.kind == "clear", "固定天气不会自己变")
	check(weather.query().rain == 0.0, "晴天不出雨线")
	# 旧档（无 version）里的雨不沿用；新档（version 2）显式设定的雨保留。
	weather.from_dict({"kind": "rain", "remaining": 12.0, "seed": 9, "duration": 240})
	check(weather.kind == "clear", "旧档的随机雨被固定天气覆盖")
	weather.set_weather("rain")
	weather.from_dict(weather.to_dict())
	check(weather.kind == "rain", "显式设定的天气能被存档恢复")
	weather.set_weather("clear")

	print("[dock-seed] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
