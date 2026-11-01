extends SceneTree
## SEA-FARM-R14：作物按「天」结算，睡一觉就是一天。
##
## 现场反馈：12:00 浇水、次日 06:00 醒来，看到的还是「今日已浇、还需 3 天」，
## 要等到 07:00 甚至更晚才翻页。根因是生长只挂在 07:00 的出货结算上，
## 而睡觉流程自己的生长调用被 `Scope.minimal()` 挡掉了（默认就挡）。
##
## 这条测试量的是**时刻**，不是数值：醒来那一帧必须已经是新状态，
## 且同一天不能因为 07:00 再结算一次而长两遍。
var checks := 0
var failures := 0
var main
var economy
var farm
var clock

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func state_of(id: String) -> Dictionary:
	return farm.state(id)

func wait_sleep() -> void:
	for i in 300:
		await create_timer(0.1).timeout
		if not main.sleep_cycle.busy: return
	check(false, "sleep flow finishes")

## 把某个格子清成空地，再播一茬。返回播种是否成功。
func clear_and_plant(plot: Node3D, crop := "lettuce") -> bool:
	farm.states[plot.plot_id] = {"crop": "", "remaining": 0.0, "total": 0.0, "water": 0.0, "harvests": 0}
	plot._sync(0.0)
	return plot.perform("plant", crop).get("event", "") == "planted"

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	clock = main.world_clock
	clock.paused = true
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	main._enter_game()
	for i in 60: await process_frame
	economy = root.get_node("Economy")
	farm = economy.farm
	economy.inventory.set_count("lettuce_seed", 12)
	main.restore_world_state({"zone":"zone5","landing":"main","mode":0,"player":[22.0,1.48,16.0],"far_sea":false})
	for i in 4: await process_frame
	var plot: Node3D = main.farm_field.find("platform_plot:3")
	check(plot != null, "aqua platform cell available")

	# --- 核心：12:00 浇水 → 睡一觉 → 06:00 醒来就是新的一天 ---
	clock.from_dict({"day":10,"seconds":12.0*3600.0,"day_length":clock.day_length})
	economy.daily._last_morning = 10
	farm.sync_calendar_day(10)
	farm.grow_day = 10
	check(clear_and_plant(plot), "plant a crop at noon")
	check(plot.perform("water", "").get("event", "") == "watered", "water it at noon")
	check(is_equal_approx(float(state_of("platform_plot:3").remaining), 3.0), "three days to harvest at noon")
	check(is_equal_approx(float(state_of("platform_plot:3").water), 1.0), "soil is wet before sleeping")
	main.sleep_cycle.request()
	await wait_sleep()
	# 醒来这一刻：日期、剩余天数、湿度都必须已经是新状态。
	check(clock.day == 11 and is_equal_approx(clock.query().hour, 6.0), "wake at 06:00 of day 11")
	check(is_equal_approx(float(state_of("platform_plot:3").remaining), 2.0),
		"crop grew one day the moment the player wakes, not at 07:00 (remaining=%.1f)"
			% float(state_of("platform_plot:3").remaining))
	check(is_equal_approx(float(state_of("platform_plot:3").water), 0.0), "soil dries out on the same tick")
	check(farm.status_text("platform_plot:3").contains("还需 2 天"), "status text already reads the new day")
	check(plot.current_stage() == 1, "visible stage advances with the same tick")

	# --- 07:00 的出货结算不能把同一天再长一遍 ---
	var before: float = float(state_of("platform_plot:3").remaining)
	clock.from_dict({"day":11,"seconds":7.0*3600.0,"day_length":clock.day_length})
	economy.daily.observe(clock.query())
	check(is_equal_approx(float(state_of("platform_plot:3").remaining), before),
		"07:00 shipping settlement never grows the same day twice")

	# --- 醒来后马上浇水，07:00 也不能被多长一天 ---
	check(plot.perform("water", "").get("event", "") == "watered", "water again right after waking")
	clock.from_dict({"day":11,"seconds":7.05*3600.0,"day_length":clock.day_length})
	economy.daily.observe(clock.query())
	check(is_equal_approx(float(state_of("platform_plot:3").remaining), 2.0),
		"re-watering before 07:00 does not buy an extra growth day")

	# --- 不睡觉、让时间自然走过 07:00 也必须长一天（旧路径不能坏）---
	farm.sync_calendar_day(11)
	farm.grow_day = 11
	clock.from_dict({"day":11,"seconds":23.5*3600.0,"day_length":clock.day_length})
	economy.daily._last_morning = 11
	clock.from_dict({"day":12,"seconds":7.2*3600.0,"day_length":clock.day_length})
	economy.daily.observe(clock.query())
	check(is_equal_approx(float(state_of("platform_plot:3").remaining), 1.0),
		"natural time crossing 07:00 still grows exactly one day")

	# --- 缺水那天不长：醒来只清湿度、不扣天数 ---
	farm.sync_calendar_day(12)
	farm.grow_day = 12
	clock.from_dict({"day":12,"seconds":12.0*3600.0,"day_length":clock.day_length})
	economy.daily._last_morning = 12
	main.sleep_cycle.request()
	await wait_sleep()
	check(is_equal_approx(float(state_of("platform_plot:3").remaining), 1.0),
		"an unwatered day costs no growth day")
	check(clock.day == 13, "wake advanced the calendar anyway")

	# --- 读档：同一天不能因为重进而再长一遍 ---
	check(plot.perform("water", "").get("event", "") == "watered", "water before saving")
	var snapshot: Dictionary = preload("res://src/save/save_game.gd").encode(main)
	check(snapshot.economy.farm.get("grow_day", -1) == 13,
		"save records the growth watermark, not just the display day")
	var saved_remaining: float = float(snapshot.economy.farm.plots["platform_plot:3"].remaining)
	check(preload("res://src/save/save_game.gd").restore(main, snapshot).get("ok", false), "restore the same save")
	var replay: Dictionary = farm.advance_to_day(int(snapshot.time.day))
	check(replay.get("skipped", false) and is_equal_approx(float(state_of("platform_plot:3").remaining), saved_remaining),
		"reloading and re-entering the same day never re-grows")

	# --- 旧档没有 grow_day：按 day 起步，不把存档那天再长一遍 ---
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.economy.farm.erase("grow_day")
	legacy.economy.farm["version"] = 2
	check(preload("res://src/save/save_game.gd").restore(main, legacy).get("ok", false), "legacy farm record still restores")
	check(farm.grow_day == int(legacy.time.day), "legacy save starts the watermark at its own day")
	var after_legacy: Dictionary = farm.advance_to_day(int(legacy.time.day))
	check(after_legacy.get("skipped", false), "legacy save does not double-grow the day it was written on")

	main.queue_free()
	await process_frame
	print("[farm-day-change] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
