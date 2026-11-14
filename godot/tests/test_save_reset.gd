extends SceneTree
## SEA-SAVE-R14 验收：重置存档。
##
## 三件事必须同时成立，缺一条这个功能就是坑：
##   1. 重置后**内存**回到开局（背包、日历、天气、建造都归位）；
##   2. 重置后**磁盘上**是开局档（不是「内存对了但文件还是旧的」）；
##   3. 旧进度**还在**，能用同一个 read() 打开。
## 第 3 条最容易漏 —— 只看前两条的话，把旧档删掉也能全绿。
##
## 另加一条「保护标志要撤掉」：读档失败后 `_save_protected` 会挡住写盘，
## 重置不清它，新档就写不进去，玩家看到的还是旧进度。

const Save = preload("res://src/save/save_game.gd")

var checks := 0
var failures := 0
var main: Node
var economy: Node
var slot := "user://reset-test-slot.json"


func _init() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	print("[save-reset] ", "PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func run() -> void:
	for suffix in ["", ".bak"]:
		var leftover: String = slot + suffix
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.world_clock.paused = true
	economy = root.get_node("Economy")
	economy.set_process(false)
	# 在现有 runner 入口执行新增的最小隔离反例，不放宽日志判定。
	await process_frame
	await process_frame
	preload("res://tests/test_save_boundaries.gd").run(main, check)

	var coins0: int = economy.count("coins")
	var seeds0: int = economy.count("lettuce_seed")
	check(coins0 == 80 and seeds0 == 3, "开局就是 80 瓶盖 / 3 包生菜种子")

	# ---- 造一份「玩了一阵」的进度 ------------------------------------------
	economy.give({"coins": 420, "wood": 30, "parts": 12})
	main.world_clock.day = 6
	main.world_clock.seconds = 19.0 * 3600.0
	main.weather_service.set_weather("rain")
	check(economy.count("coins") == 500 and economy.count("wood") == 30, "进度已造好（瓶盖 500 / 木板 30）")
	var before: Dictionary = main.save_game(slot, true)
	check(before.get("ok", false), "旧进度写盘成功")
	# 再存一次：这一次会生成 `.bak`。重置必须把回滚备份一起归档，
	# 只挪主档会留下一个「上次的档」在原位，下次启动就莫名回退到它。
	economy.give({"coins": 100})
	check(main.save_game(slot, true).get("ok", false), "再存一次，生成 .bak 回滚位")
	check(FileAccess.file_exists(slot + ".bak"), "备份文件确实存在（否则下面那条断言是空转）")
	var old_snapshot: Dictionary = Save.read(slot).get("snapshot", {})
	check(int(old_snapshot.get("economy", {}).get("inventory", {}).get("counts", {}).get("coins", 0)) == 600,
		"磁盘上确实是旧进度（瓶盖 600）")

	# ---- 重置 --------------------------------------------------------------
	# 先人为立起写盘保护：重置必须能自己撤掉它，否则第 3 步写不进新档。
	main._save_protected = true
	var result: Dictionary = main.reset_save(slot)
	check(result.get("ok", false), "重置成功")
	var archived: Array = result.get("archived", [])
	check(archived.size() == 2, "主档与备份都归档了（不是只挪一个）")

	# 1) 内存归位
	check(economy.count("coins") == coins0, "瓶盖回到开局值")
	check(economy.count("lettuce_seed") == seeds0, "种子回到开局值")
	check(economy.count("wood") == 0 and economy.count("parts") == 0, "材料清空")
	check(main.world_clock.day == 1, "日历回到第 1 天")
	check(is_equal_approx(main.world_clock.query().hour, 7.0), "时刻回到 07:00")
	check(main.weather_service.kind == "clear", "天气回到晴")
	check(not main._save_protected, "读档保护标志已撤掉（否则新档写不进去）")

	# 2) 磁盘也是开局档 —— 必须重新从文件读，不能信内存
	var fresh: Dictionary = Save.read(slot)
	check(fresh.get("ok", false), "重置后槽位上有可用存档")
	var counts: Dictionary = fresh.get("snapshot", {}).get("economy", {}).get("inventory", {}).get("counts", {})
	check(int(counts.get("coins", 0)) == coins0 and int(counts.get("wood", 0)) == 0,
		"磁盘上的新档是开局状态（瓶盖 %d / 木板 %d）" % [int(counts.get("coins", 0)), int(counts.get("wood", 0))])
	check(int(fresh.get("snapshot", {}).get("time", {}).get("day", 0)) == 1, "磁盘上的新档是第 1 天")

	# 3) 旧进度还在，且能读回来
	var kept: Dictionary = Save.read(String(archived[0]))
	check(kept.get("ok", false), "归档文件仍是一份有效存档")
	var kept_counts: Dictionary = kept.get("snapshot", {}).get("economy", {}).get("inventory", {}).get("counts", {})
	check(int(kept_counts.get("coins", 0)) == 600 and int(kept_counts.get("wood", 0)) == 30,
		"归档里就是旧进度（瓶盖 600 / 木板 30）—— 重置不等于烧桥")
	check(String(archived[0]).get_file().begins_with("reset-test-slot_pre_reset-"),
		"归档名带 _pre_reset 标记，不占用 .bak 回滚位")
	check(String(archived[0]) != slot and String(archived[0]).get_extension() == "json",
		"归档不在原槽位路径上、但仍带 .json 后缀（能直接打开）")

	# 4) 连按两次不会把归档顶掉
	var second: Dictionary = main.reset_save(slot)
	check(second.get("ok", false), "再重置一次仍然成功")
	var second_files: Array = second.get("archived", [])
	check(second_files.size() == 1, "第二次只归档新档（没有 .bak 可归档）")
	check(FileAccess.file_exists(String(archived[0])), "第一份归档没被第二次重置覆盖")
	check(economy.count("coins") == coins0, "第二次重置后仍是开局值")

	# 5) 空槽位重置 = 没有可归档的东西，但不是失败
	var empty := Save.archive("user://reset-test-empty.json")
	check(empty.get("ok", false) and (empty.get("files", []) as Array).is_empty(),
		"没有存档时归档返回成功且清单为空（不是错误）")

	finish()


func finish() -> void:
	for suffix in ["", ".bak"]:
		var leftover: String = slot + suffix
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(leftover))
	for dir_name in DirAccess.get_files_at("user://"):
		if dir_name.begins_with("reset-test-slot_pre_reset-"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + dir_name))
	print("[save-reset] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
