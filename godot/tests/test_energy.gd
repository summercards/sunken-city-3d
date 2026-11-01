extends SceneTree
## SEA-ENERGY：体力开销、疲劳提醒、见底强制休息、次日上限减半、右下角体力条。
##
## 用正式场景与正式命令（`farm.perform` / `building.begin` / 睡觉流程），
## 不直接改 state；只有为了把数值压到阈值才调用 `energy.current =` 的测试夹具。
var checks := 0
var failures := 0
var main
var economy
var energy

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func shot(path: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path) == OK, "save render " + path)

## 等一次完整过场结束。**按真实时间等，不按帧数** —— headless 下帧跑得飞快，
## 补间是按 delta 走的，数帧会在 0.5 秒后就宣布「没结束」。
func wait_sleep() -> void:
	for i in 300:
		await create_timer(0.1).timeout
		if not main.sleep_cycle.busy: return
	check(false, "sleep flow finishes")

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	main._enter_game()
	for i in 60: await process_frame
	economy = root.get_node("Economy")
	energy = economy.energy

	# --- 开局与随档 ---
	check(energy.current == 100.0 and energy.maximum == 100.0, "new game starts with a full 100 stamina")
	var snapshot: Dictionary = preload("res://src/save/save_game.gd").encode(main)
	check(snapshot.economy.has("energy"), "energy is part of the formal save snapshot")
	check(main.hud.corner.stamina != null, "corner HUD owns a stamina bar widget")
	check(is_equal_approx(main.hud.corner.stamina.ratio(), 1.0), "stamina bar starts full")

	# --- 每个行为扣体力 ---
	economy.inventory.set_count("lettuce_seed", 6)
	var plot: Node3D = main.farm_field.find("home_plot")
	main.actor_controller.disembark.execute(main.actor_controller, main._current_landing().stand_position())
	main.actor_controller.reconcile_mode(0)
	check(plot.perform("plant", "lettuce").get("event", "") == "planted", "plant succeeds")
	check(is_equal_approx(energy.current, 98.0), "plant costs 2")
	check(plot.perform("water", "").get("event", "") == "watered", "water succeeds")
	check(is_equal_approx(energy.current, 97.0), "water costs 1")
	# 成熟只用夹具推进（生长本身归 SEA-FARM，这条只关心收获会不会扣体力）。
	# `debug_set_growth` 的 ratio 是「剩余生长量占比」，0 才是可收获。
	check(economy.farm.debug_set_growth("home_plot", 0.0, false), "fixture ripens the planted cell")
	check(plot.perform("harvest", "").get("event", "") == "harvested", "harvest succeeds")
	check(is_equal_approx(energy.current, 96.0), "harvest costs 1")

	# 建造：木板要站在海面平台上，用正式服务入口。
	main.restore_world_state({"zone":"zone5","landing":"main","mode":0,"player":[20.6,1.48,16.0],"far_sea":false})
	for i in 6: await process_frame
	economy.inventory.set_count("wood", 40)
	energy.current = 50.0
	var before: float = energy.current
	var placed: Dictionary = main.building.begin({"kind":"deck","x":1,"z":-1,"px":0.0,"pz":0.0,"turn":0,"support":""})
	check(placed.get("ok", false), "new board still buildable beside the aqua platform")
	check(is_equal_approx(energy.current, before - 4.0), "build costs 4")
	var deck_id := str(placed.get("id", ""))
	# 新板要盖完才能回收；这里直接推进施工计时，不测工期。
	for i in 4: main.building.tick(1.5)
	var removed: Dictionary = main.building.remove(deck_id)
	check(removed.get("ok", false), "board removal still works " + str(removed.get("reason", "")))
	check(is_equal_approx(energy.current, before - 7.0), "remove costs 3")

	# --- 疲劳提醒：只提一次 ---
	var tired_hits := [0]
	var exhausted_hits := [0]
	energy.tired.connect(func(): tired_hits[0] += 1)
	energy.exhausted.connect(func(): exhausted_hits[0] += 1)
	energy.current = 27.0
	energy.spend("plant")
	check(tired_hits[0] == 1, "tired warning fires once when stamina drops below 25%")
	energy.current = 5.0
	energy.spend("plant")
	check(tired_hits[0] == 1, "tired warning does not repeat in the same day")

	# --- 见底：拒绝继续，触发强制休息 ---
	check(energy.reason("plant") == "", "one remaining point still allows acting")
	energy.current = 1.0
	energy.spend("plant")
	check(energy.current == 0.0, "stamina floors at zero")
	check(exhausted_hits[0] == 1, "exhausted signal fires at zero")
	check(energy.reason("plant") != "", "empty stamina blocks further work")
	check(plot.perform("water", "").get("blocked", "") != "" or plot.phase("home_plot") != "growing", "farming is refused at zero stamina")

	# 主场景的强制休息：先念台词、再收幕，期间输入被吞。
	main._on_energy_exhausted()
	await process_frame
	check(main.hud.dialogue != null and main.hud.dialogue.panel.visible, "exhausted line appears before the curtain")
	check(main.hud.dialogue.line_label.text.contains("太累了"), "line reads 啊，太累了，今天需要休息了。")
	check(main.input_blocked(), "exhausted rest locks gameplay input")
	await shot("res://outputs/energy-exhausted-line.png")
	var day: int = main.world_clock.day
	for i in 300:
		await create_timer(0.1).timeout
		if main.sleep_cycle.busy: break
	check(main.sleep_cycle.busy and main.sleep_cycle.forced, "forced sleep starts after the line")
	await wait_sleep()
	await create_timer(0.2).timeout
	check(main.world_clock.day == day + 1, "forced rest wakes the next day")
	check(is_equal_approx(energy.maximum, 50.0) and is_equal_approx(energy.current, 50.0),
		"next day cap is halved to 50 and refilled")
	check(is_equal_approx(main.hud.corner.stamina.ratio(), 1.0), "halved cap draws as a full bar")
	check(not main._exhausted_rest, "forced rest flag clears after waking")
	await shot("res://outputs/energy-half-day.png")

	# 惩罚只挂一天：正常睡一次回满。
	main.sleep_cycle.request()
	await wait_sleep()
	check(is_equal_approx(energy.maximum, 100.0) and is_equal_approx(energy.current, 100.0),
		"one normal sleep restores the full cap")

	# 存档往返：体力、上限与惩罚标记都留在正式档里。
	energy.current = 33.0
	var written: Dictionary = preload("res://src/save/save_game.gd").write("user://energy.json", main)
	check(written.get("ok", false), "save writes energy through the formal schema")
	var restored: Dictionary = preload("res://src/save/save_game.gd").read("user://energy.json")
	check(restored.get("ok", false) and is_equal_approx(float(restored.snapshot.economy.energy.current), 33.0),
		"saved stamina value round-trips")
	energy.current = 90.0
	check(preload("res://src/save/save_game.gd").restore(main, restored.snapshot).get("ok", false), "restore applies stamina")
	check(is_equal_approx(energy.current, 33.0), "restored stamina replaces the live value")

	# 旧档（没有 energy 字段）照常读成满体力。
	var legacy: Dictionary = restored.snapshot.duplicate(true)
	legacy.economy.erase("energy")
	check(preload("res://src/save/save_game.gd").restore(main, legacy).get("ok", false),
		"snapshot without an energy record still restores")
	check(is_equal_approx(energy.current, 100.0) and is_equal_approx(energy.maximum, 100.0),
		"missing energy record starts full, never zero")

	main.queue_free()
	await process_frame
	print("[energy] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
