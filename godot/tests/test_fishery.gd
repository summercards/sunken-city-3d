extends SceneTree
## SEA-AQUA-R04：家园补给站升级为渔场。
##
## 只验收「升级操作」这一段：入口（木牌气泡）、成本（木板 100 / 鱼 50）、
## 背包与仓库合并付款、拒绝路径、正式渔区显隐、存档往返。
## 养殖/投苗/收成不在该升级专项；模型/空间另由fishery-environment覆盖。
var checks := 0
var failures := 0
var main
var economy

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

func bubble_labels() -> Array:
	var out: Array = []
	if main.hud.world_actions.active:
		for button: Button in main.hud.world_actions.buttons:
			out.append(str(button.get_meta("action_label", "")))
	return out

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

	# --- 默认未升级 ---
	check(not economy.fishery.unlocked, "supply station starts as a supply station")
	check(str(economy.fishery.reason()).contains("木板"), "locked reason names the missing wood")
	check(main.trade_board.label=="渔场 · 待建", "board advertises only fishery construction before upgrading")

	# --- 入口长在木牌的气泡上 ---
	main.actor_controller.disembark.execute(main.actor_controller, main._current_landing().stand_position())
	main.actor_controller.reconcile_mode(0)
	main.player.global_position = main.trade_board.global_position + Vector3(0, 0, 1.2)
	main._reach_cache.clear()
	main._open_spot_bubbles(main.trade_board)
	await process_frame
	var labels := bubble_labels()
	check(labels==["建造渔场"], "fishery board offers only its construction bubble " + str(labels))
	main.hud.world_actions.close(true)

	# --- 材料不足：拒绝且不扣料 ---
	var wood_before: int = economy.count("wood") + economy.warehouse.count("wood")
	var fish_before: int = economy.count("fish") + economy.warehouse.count("fish")
	var poor: Dictionary = main._upgrade_fishery()
	check(poor.has("blocked"), "upgrade refused while materials are short")
	check(not economy.fishery.unlocked, "refused upgrade leaves the station unchanged")
	check(economy.count("wood") + economy.warehouse.count("wood") == wood_before
		and economy.count("fish") + economy.warehouse.count("fish") == fish_before,
		"refused upgrade spends nothing")

	# --- 差一份也不行（边界）---
	economy.inventory.set_count("wood", 100)
	economy.inventory.set_count("fish", 49)
	check(economy.fishery.reason() != "", "99+1 fish boundary is still refused")
	economy.inventory.set_count("fish", 50)
	check(economy.fishery.reason() == "", "exact cost satisfies the requirement")

	# --- 仓库里的材料也算（100 块木板塞不进 24 格背包）---
	economy.inventory.set_count("wood", 10)
	economy.warehouse.set_count("wood", 90)
	check(economy.fishery.held("wood") == 100, "warehouse wood counts towards the cost")
	main.hud.open_aqua_upgrade(main._upgrade_fishery)
	for i in 30: await process_frame
	check(main.hud.is_panel_open(), "upgrade page opens as a card")
	await shot("res://outputs/fishery-upgrade-page.png")
	var result: Dictionary = main._upgrade_fishery()
	check(result.get("event", "") == "fishery_unlocked", "upgrade succeeds " + str(result))
	check(economy.fishery.unlocked, "station is now a fishery")
	check(economy.count("wood") + economy.warehouse.count("wood") == 0, "100 boards are consumed")
	check(economy.count("fish") == 0, "50 fish are consumed")
	check(not main.trade_board.visible and main._fishery_harvest.visible, "upgraded board is replaced by the harvest interaction")
	check(main._fishery_visual != null and main._fishery_visual.visible, "platform gets its authored shore, net and floats")
	check(str(economy.fishery.reason()).contains("已经是渔场"), "second upgrade is refused with a clear reason")
	await shot("res://outputs/fishery-upgraded.png")

	# --- 存档往返 ---
	var written: Dictionary = preload("res://src/save/save_game.gd").write("user://fishery.json", main)
	check(written.get("ok", false), "save writes the fishery record")
	var saved: Dictionary = preload("res://src/save/save_game.gd").read("user://fishery.json")
	check(saved.get("ok", false) and bool(saved.snapshot.economy.fishery.unlocked), "saved snapshot marks the fishery")
	economy.fishery.from_dict({"version": 1, "unlocked": false})
	check(not economy.fishery.unlocked, "fixture resets the live flag")
	check(preload("res://src/save/save_game.gd").restore(main, saved.snapshot).get("ok", false), "restore applies the fishery")
	check(economy.fishery.unlocked, "restored save unlocks the fishery again")
	check(not main.trade_board.visible and main._fishery_harvest.visible, "restored save replaces the board with harvest interaction")

	# 旧档（没有 fishery 字段）读成「没升过」，不报错。
	var legacy: Dictionary = saved.snapshot.duplicate(true)
	legacy.economy.erase("fishery")
	check(preload("res://src/save/save_game.gd").restore(main, legacy).get("ok", false),
		"snapshot without a fishery record still restores")
	check(not economy.fishery.unlocked, "missing fishery record means not upgraded")

	main.queue_free()
	await process_frame
	print("[fishery] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
