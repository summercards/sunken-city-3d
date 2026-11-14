extends SceneTree
## B2 生产装配：奖励/保存重入、暂停恢复投影、自动保存与睡眠会话。
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main
var economy
var baseline: Dictionary

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[b2-session] ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.interactor.set_process(false)
	economy = root.get_node("Economy")
	economy.set_process(false)
	await process_frame
	await process_frame
	baseline = Save.encode(main)
	check(Save.Schema.validate_result(baseline).ok, "正式宿主基线可存")
	for free in [0, 1, 2]:
		economy.inventory.clear()
		economy.inventory.set_count("fish", (24 - free) * 20)
		economy.salvage.salvage_ready_at = 0.0
		var before: Dictionary = economy.inventory.to_dict()
		var result: Dictionary = main._npc_career_command("salvage", {"id":"do_salvage"})
		check(result.ok == (free == 2), "真实NPC打捞%d空格整笔接受/拒绝" % free)
		if free < 2:
			check(economy.inventory.to_dict() == before and economy.salvage.can_salvage(Save.now_seconds()), "拒绝不发部分奖励或冷却")
		else:
			check(result.added == {"wood":3, "parts":2} and result.message.contains("3") and economy.inventory.count("parts") == 2, "成功反馈取真实入账")
	check(Save.restore(main, baseline).ok, "奖励测试后恢复完整基线")
	var attacks: Array = []
	var callback := func(_id: String, _delta: int):
		attacks.append([main.save_registry.is_busy(), main.save_registry.capture().is_empty(), Save.write("user://b2-mid.json", main).ok, Save.restore(main, baseline).ok])
	economy.inventory.changed.connect(callback)
	economy.salvage.salvage_ready_at = 0.0
	var got: Dictionary = main._npc_career_command("salvage", {"id":"do_salvage"})
	economy.inventory.changed.disconnect(callback)
	check(got.ok and attacks.size() == 2, "真实奖励信号产生两次重入探针")
	for attack in attacks: check(attack == [true, true, false, false], "生产Registry拒绝中间保存与恢复")
	check(not FileAccess.file_exists("user://b2-mid.json"), "中间档从未写盘")
	check(Save.restore(main, baseline).ok, "事务后恢复基线")
	# 不重放时钟事件；暂停时也应立即刷新所有只读消费者。
	var clock_events := [0]
	var listener := func(_snapshot): clock_events[0] += 1
	main.world_clock.changed.connect(listener)
	for rainy in [true, false]:
		var snapshot := baseline.duplicate(true)
		snapshot.time.seconds = (21.0 if rainy else 10.0) * 3600.0
		snapshot.weather.kind = "rain" if rainy else "clear"
		main.world_clock.paused = true
		check(Save.restore(main, snapshot).ok, "暂停恢复雨夜/晴昼")
		check(main.bird_root.is_flying_hour() == not rainy and main.bird_root.visible == not rainy, "鸟群即时匹配恢复小时")
		check(main.daylight_rig.weather() == snapshot.weather.kind and main.weather_view.rain == (1.0 if rainy else 0.0), "光照天气上下文与雨层立即同步")
		check(main._calendar_label.text == main.world_clock.query().text + " · " + main.weather_service.query().label, "暂停日历文案同步")
	check(clock_events[0] == 0, "恢复不重播clock.changed经营事件")
	main.world_clock.changed.disconnect(listener)
	check(Save.restore(main, baseline).ok, "投影验证后恢复基线")
	# 成功替代读档接管新槽，不误覆盖坏槽；显式禁用开关保持。
	var good := "user://b2-good-slot.json"
	var bad := "user://b2-bad-slot.json"
	check(Save.write(good, main).ok, "替代档准备")
	var file := FileAccess.open(bad, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	main._save_path = bad
	main._save_protected = true
	main._autosave_on = true
	check(main.load_game(good).ok and not main._save_protected and main._autosave_on and main._save_path == good, "成功替代读档撤临时保护且保留自动保存意愿")
	var old_wall: String = FileAccess.get_file_as_string(good)
	economy.inventory.set_count("coins", 91)
	main._autosave_left = 0.0
	main._process(0.001)
	check(FileAccess.get_file_as_string(good) != old_wall and Save.read(good).snapshot.economy.inventory.counts.coins == 91, "到自动保存周期实际写入替代槽")
	check(FileAccess.get_file_as_string(bad) == "{", "原坏槽字节不变")
	main._autosave_on = false
	check(main.load_game(good).ok and not main._autosave_on, "测试/用户禁用不会被成功加载开启")
	# intent-only空槽恢复：无主档、无bak的未提交重置不永久锁槽。
	var empty := "user://b2-intent-only.json"
	var tx = Save.ResetTransaction.new()
	check(tx.write_verified(empty + tx.INTENT, JSON.stringify({"version":1,"mark":"empty","committed":false,"fresh_hash":"0".repeat(64),"originals":[]})), "准备仅intent无原槽的崩溃现场")
	check(main.load_game(empty).ok and not tx.pending(empty), "正式加载恢复空槽intent")
	check(Save.write(empty, main).ok, "空槽恢复后可正常保存")
	# 三类旧会话都在睡前关闭，旧回调醒后不可生效。
	for modal in ["shop", "career", "npc"]:
		check(Save.restore(main, baseline).ok, "睡眠前完整恢复")
		main.world_clock.seconds = 22.9999 * 3600.0
		main.world_clock.paused = false
		var stale := Callable()
		if modal == "shop":
			check(main.shop_panel.open_shop("shop_general").ok, "打开真实商店")
			await process_frame
			check(main.shop_panel.open_actions(), "商店进入购买确认")
			stale = main.shop_panel._buy.pressed.get_connections()[0].callable
		elif modal == "career":
			# 给足真实升级成本，使确认页确实存在；不能用无效Callable冒充旧按钮测试。
			economy.give({"wood":6,"parts":4,"rope":2})
			check(main.npc_career_panel.open_service("npc_luo_yan", "ship").ok, "打开真实职业面板")
			for button in main.npc_career_panel._buttons:
				if button.get_meta("career_command") == "prepare": button.pressed.emit(); break
			for button in main.npc_career_panel._buttons:
				if button.get_meta("career_command") == "confirm": stale = button.pressed.get_connections()[0].callable; break
		else:
			check(main.npc_world_presenter.panel.open_npc("npc_bai_shi").ok, "打开真实NPC会话")
		if modal != "npc": check(stale.is_valid(), "睡前持有真实可执行的旧确认回调")
		var bag_before: Dictionary = economy.inventory.to_dict()
		var level_before: int = economy.ship.ship_level
		var day_before: int = main.world_clock.day
		main.sleep_cycle.advance(1.0)
		check(main.sleep_cycle.busy, "22:59自动睡眠开始")
		for i in 1800:
			if not main.sleep_cycle.busy: break
			await process_frame
		check(not main.sleep_cycle.busy and main.world_clock.day == day_before + 1, "睡眠完成且只换日一次")
		check(not main.shop_panel.is_open() and not main.npc_career_panel.is_open() and not main.npc_world_presenter.is_modal(), "醒后三类逻辑模态均关闭")
		if stale.is_valid(): stale.call()
		check(economy.inventory.to_dict() == bag_before and economy.ship.ship_level == level_before, "旧确认回调不产生购买/支付/升级")
	check(not main._autosave_on, "睡眠和恢复均保留明确的自动保存禁用")
	main.queue_free()
	await process_frame
	print("[b2-session] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
