extends SceneTree
## 仅由隔离 runner 执行；实际调用 Main，不用源码正则替代装配回归。
const Save = preload("res://src/save/save_game.gd")
const Clock = preload("res://src/time/world_clock.gd")
const Sleep = preload("res://src/time/sleep_cycle.gd")
const SLOT := "user://npc-clock-roundtrip.json"
const AUTO_SLOT := "user://npc-clock-automatic-disabled.json"
const DELTA := 1.0 / 60.0
var checks := 0
var failures := 0
var main
var clock
var sleep
var world
var economy
var changed: Array = []
var days: Array = []
var wakes: Array = []
var receipts: Array = []
var phases: Array = []
var default_slots: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL [npc-clock] ", label)
	return ok

func file_state(path: String) -> Dictionary:
	return {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}

func positions() -> Dictionary:
	var result := {}
	for id in world.actors:
		result[id] = world.actor(id).global_position
	return result

func run() -> void:
	if not check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
		and str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/"),
		"Autoload 前已由统一 runner 隔离 user 数据"):
		quit(1)
		return
	if not check(DisplayServer.get_name() == "headless" and OS.get_cmdline_user_args().has("--skip-title")
		and not OS.get_cmdline_user_args().has("--full-world"), "只用默认范围 headless runner，不与真实 visual 争用"):
		quit(1)
		return
	for path in [Save.SLOT_PATH, Save.SLOT_PATH + ".bak", AUTO_SLOT, AUTO_SLOT + ".bak"]:
		default_slots[path] = file_state(path)
	main = load("res://scenes/main.tscn").instantiate()
	# 入树前关闭；即使 runner 尚未为此入口追加 --nosave 也不会隐式读写默认槽。
	main._autosave_on = false
	main._save_path = AUTO_SLOT
	root.add_child(main)
	current_scene = main
	main.set_process(false)
	main.set_physics_process(false)
	main.interactor.set_process(false)
	economy = root.get_node("Economy")
	economy.ticking = false
	clock = main.world_clock
	sleep = main.sleep_cycle
	world = main.npc_world_presenter
	world.set_physics_process(false)
	if not check(clock.get_script() == Clock and sleep.get_script() == Sleep and sleep.clock == clock
		and sleep.curtain == main.sleep_curtain, "真实 Main 注入同一 WorldClock、SleepCycle 与圆幕"):
		await finish()
		return
	check(not main._autosave_on and not main._title_active, "入树后自动存档仍关闭且标题已跳过")
	check(world.service == main.npc_service and world.actors.size() == 7, "真实 Main 装配七人及唯一 NPC 服务")
	clock.changed.connect(func(snapshot: Dictionary): changed.append(snapshot.duplicate(true)))
	clock.day_changed.connect(func(day: int): days.append(day))
	sleep.woke.connect(func(snapshot: Dictionary): wakes.append(snapshot.duplicate(true)))
	economy.daily.settled.connect(func(receipt: Dictionary): receipts.append(receipt.duplicate(true)))
	main.sleep_curtain.phase_changed.connect(func(phase: String): phases.append(phase))
	# 等待 Main 自己的延迟装配完成；Main 的自动 _process 已关闭，时钟不会漂移。
	await process_frame
	await process_frame
	clock.from_dict({"day": clock.day, "seconds": 12.0 * 3600.0, "day_length": 1200.0})
	clock.paused = false
	world._physics_process(0.5)
	single_ticks_and_notify()
	await pause_and_title()
	if not check(Save.write(SLOT, main).get("ok", false), "正式 SaveGame 写入隔离测试槽供跨时段读档"):
		await finish()
		return
	await bedtime_and_morning()
	restore_schedule()
	await finish()

func single_ticks_and_notify() -> void:
	var metrics: Dictionary = world.performance_metrics()
	var before_positions := positions()
	var durable: Dictionary = main.npc_service.to_dict()
	var start: float = clock.seconds
	var day: int = clock.day
	changed.clear()
	days.clear()
	for index in 120:
		var before: float = clock.seconds
		var signals := changed.size()
		main._process(DELTA)
		check(absf(clock.seconds - before - DELTA * 86400.0 / clock.day_length) < 0.000001,
			"Main 第 %d 帧仅推进一次 delta×86400/day_length" % (index + 1))
		check(changed.size() == signals + 1 and absf(float(changed.back().hour) * 3600.0 - clock.seconds) < 0.000001,
			"Main 第 %d 帧 changed 恰好一次且快照为实际时刻" % (index + 1))
	check(absf(clock.seconds - start - 120.0 * DELTA * 86400.0 / clock.day_length) < 0.000001
		and clock.day == day and days.is_empty(), "120 次 Main 调用累计时间准确，不换天")
	var notified: Dictionary = world.performance_metrics()
	check(notified.notify_requests == metrics.notify_requests + 120, "120 个真实 changed 均仅通知 NPC")
	for key in metrics:
		if key == "notify_requests": continue
		check(notified[key] == metrics[key], "120 次高频通知不执行全量日程工作：" + str(key))
	check(positions() == before_positions and main.npc_service.to_dict() == durable, "通知不移动 NPC、不改持久状态")
	check(absf(float(world.world_snapshot().world.hour) - float(clock.query().hour)) < 0.000001,
		"通知保留最新时刻而非丢弃所有 changed")
	world._physics_process(0.49)
	check(world.performance_metrics().sync_requests == notified.sync_requests, "未满 0.5 秒不启动日程批次")
	world._physics_process(0.01)
	var polled: Dictionary = world.performance_metrics()
	check(polled.sync_requests == notified.sync_requests + 1 and polled.sync_executed == notified.sync_executed + 1,
		"跨分钟的 120 通知在 0.5 秒合为一次实际日程同步")
	check(polled.state_queries == notified.state_queries + 7, "合并批次只查询七份 NPC 状态")
	world._physics_process(0.5)
	check(world.performance_metrics().sync_executed == polled.sync_executed, "下一次同状态轮询不重建日程")
	print("[npc-clock-metrics] before=", metrics, " notified=", notified, " polled=", polled)

func pause_and_title() -> void:
	var before: Dictionary = clock.to_dict()
	var signals := changed.size()
	clock.paused = true
	for index in 3: main._process(DELTA)
	check(clock.to_dict() == before and changed.size() == signals, "WorldClock 暂停时实际 Main 调用不推进、不发 changed")
	clock.paused = false
	# 菜单依靠 SceneTree 暂停抑制调度，不把手动调用 _process 当引擎的暂停语义。
	main.hud.menu.show_menu("pause")
	check(paused and not main.can_process(), "正式暂停菜单阻止 Main 被引擎调度")
	main.set_process(true)
	await process_frame
	await process_frame
	main.set_process(false)
	check(clock.to_dict() == before and changed.size() == signals, "真实暂停帧不推进时间、不发布 changed")
	main.hud.menu.close_menu()
	check(not paused, "正式关闭菜单解除暂停")
	main._begin_title()
	check(main._title_active, "正式标题流程已进入")
	for index in 3: main._process(DELTA)
	main.set_process(true)
	await process_frame
	await process_frame
	main.set_process(false)
	check(clock.to_dict() == before and changed.size() == signals and not sleep.busy,
		"标题手动调用及真实引擎帧均不推进、不发 changed、不睡觉")
	main._resume_after_avatar_or_title()
	check(not main._title_active, "正式标题恢复流程完成")
	main._process(DELTA)
	check(changed.size() == signals + 1 and clock.seconds > float(before.seconds), "恢复后 Main 只发布一次推进")

func bedtime_and_morning() -> void:
	var day: int = clock.day
	economy.give({"fish": 1})
	economy.daily.deposit("fish", 1)
	check(economy.daily.query().items.get("fish", 0) == 1, "正式出货箱放入一条鱼作为晨次观察物")
	var coins: int = economy.coins
	var income: int = economy.daily.query().expected
	var settlements := receipts.size()
	clock.from_dict({"day": day, "seconds": 22.99 * 3600.0, "day_length": clock.day_length})
	world._physics_process(0.5)
	check(world.world_snapshot().residents.npc_luo_yan.action == "rest", "23 点前正式 NPC 已进入夜间休息日程")
	changed.clear()
	days.clear()
	main._process(10000.0)
	check(sleep.busy and clock.paused and clock.day == day and absf(clock.seconds - 23.0 * 3600.0) < 0.000001,
		"实际 Main 超长帧截在当日 23:00 并启动正式睡眠")
	check(changed.size() == 1 and days.is_empty() and absf(float(changed[0].hour) - 23.0) < 0.000001,
		"超长帧只发布一次 23:00，未先越界或跨多天")
	check(main.sleep_curtain.phase == "closing" and main.actor_controller.state_id() == "sleeping",
		"Main 实际 prepare 接线进入圆幕与角色睡眠态")
	for index in 120: main._process(10000.0)
	check(clock.day == day and changed.size() == 1 and days.is_empty() and wakes.is_empty(),
		"过场中重复 Main 长帧不重入、不额外 tick 或提前醒来")
	await sleep.woke
	check(wakes.size() == 1 and days == [day + 1] and clock.day == day + 1
		and absf(clock.seconds - 6.0 * 3600.0) < 0.000001, "真实圆幕结束只醒一次至次日 06:00")
	check(changed.size() == 2 and int(changed[1].day) == day + 1 and float(changed[1].hour) == 6.0,
		"整个 Main 睡眠链只有 23:00 与 06:00 两次 changed")
	check(phases == ["closing", "closed", "morning", "opening", "idle"] and not sleep.busy and not clock.paused,
		"圆幕五阶段各一次，睡醒恢复时钟")
	check(main._calendar_label.text.contains("06:00") and main.hud.visible,
		"真实 Main 醒来接线刷新日历及玩法 UI")
	check(receipts.size() == settlements and economy.coins == coins and economy.daily.query().items.get("fish", 0) == 1,
		"06:00 不提前执行 07:00 收货晨次")
	var metrics: Dictionary = world.performance_metrics()
	world._physics_process(0.5)
	check(world.performance_metrics().sync_executed == metrics.sync_executed + 1
		and world.world_snapshot().world.day == day + 1 and world.world_snapshot().world.hour == 6.0,
		"真实睡醒通知使下一批日程更新至新一天 06:00")
	check(world.world_snapshot().residents.npc_luo_yan.action == "sort_tools", "睡醒不残留昨晚 rest 日程")
	var signals := changed.size()
	main._process(clock.day_length / 24.0)
	check(clock.query().hour == 7.0 and changed.size() == signals + 1 and wakes.size() == 1 and days.size() == 1,
		"Main 从 06:00 到 07:00 仍只推进一次，不重复醒来或换天")
	check(receipts.size() == settlements + 1 and economy.coins == coins + income
		and economy.daily.query().items.is_empty() and int(receipts.back().day) == day + 1,
		"07:00 正式出货晨次只执行一次且金额准确")
	check(Save.write(SLOT + ".morning", main).get("ok", false), "保存真实已结算 07:00 状态")
	var saved: Dictionary = Save.read(SLOT + ".morning")
	if check(saved.get("ok", false), "读回正式 07:00 存档"):
		check(Save.restore(main, saved.snapshot).get("ok", false), "通过正式 Registry 恢复已结算晨次")
	for index in 3: main._process(0.0)
	main._process(DELTA)
	check(receipts.size() == settlements + 1 and economy.coins == coins + income and wakes.size() == 1,
		"07:00 读档及重复帧均不再卖货或重复醒来")

func restore_schedule() -> void:
	var saved: Dictionary = Save.read(SLOT)
	if not check(saved.get("ok", false), "正式读回先前白天整档"): return
	var before_positions := positions()
	var metrics: Dictionary = world.performance_metrics()
	var signals := changed.size()
	var result: Dictionary = Save.restore(main, saved.snapshot)
	if not check(result.get("ok", false), "实际 SaveGame.restore 成功：" + str(result)): return
	# JSON 数字往返不保证浮点逐位一致，按世界秒精度比较，不放宽日历或信号次数。
	check(clock.day == int(saved.snapshot.time.day)
		and absf(clock.seconds - float(saved.snapshot.time.seconds)) < 0.000001
		and absf(clock.day_length - float(saved.snapshot.time.day_length)) < 0.000001,
		"Registry 恢复唯一时间所有者至存档时刻：" + str(clock.to_dict()))
	check(changed.size() == signals, "Registry 屏蔽恢复中的中间 changed")
	check(world.performance_metrics().sync_executed == metrics.sync_executed + 1,
		"Main restored 接线不依赖 changed，立即强制刷新一次 NPC 日程")
	check(world.world_snapshot().world.day == clock.day
		and absf(float(world.world_snapshot().world.hour) - float(clock.query().hour)) < 0.000001
		and world.world_snapshot().residents.npc_luo_yan.action == "repair_boat", "读档后日程回到所存白天而非停在清晨")
	check(positions() == before_positions, "正式读档重算日程不硬写 NPC 世界位置")
	var executed: int = world.performance_metrics().sync_executed
	world._physics_process(0.5)
	check(world.performance_metrics().sync_executed == executed, "读档后同值下一批不重复重建")

func finish() -> void:
	if is_instance_valid(main):
		check(not main._autosave_on, "结束时自动存档仍关闭")
		main.queue_free()
		await process_frame
	for path in default_slots:
		check(file_state(path) == default_slots[path], "自动槽及默认玩家槽字节不变：" + str(path))
	print("[npc-clock] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
