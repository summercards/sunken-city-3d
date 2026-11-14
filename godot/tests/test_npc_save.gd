extends "res://tests/test_npc_integration.gd"
## 同一脚本支持 suite / seed / restart；阶段由用户参数或 SEA_NPC_SAVE_PHASE 指定。
const Schema = preload("res://src/save/save_schema.gd")
const Service = preload("res://src/npc/npc_service.gd")
const SLOT := "user://npc-tests/restart.json"
const MANIFEST := "user://npc-tests/restart-expected.json"
var phase := "suite"
var restored_events := 0

func run() -> void:
	marker = "npc-save"
	phase = OS.get_environment("SEA_NPC_SAVE_PHASE")
	if phase == "": phase = "suite"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--npc-save-phase="): phase = arg.trim_prefix("--npc-save-phase=")
	if not check(phase in ["suite", "seed", "restart"], "存档阶段仅允许 suite/seed/restart"):
		await finish(); return
	if not await boot():
		await finish(); return
	main.save_registry.restored.connect(func(): restored_events += 1)
	if phase == "restart":
		await restart()
	else:
		await seed_state()
		if failures != 0:
			check(false, "真实存档前置失败，不能用空夹具继续或伪造通过")
			await finish(); return
		if phase == "suite":
			strict_codec()
			atomic_rejections()
			legacy_policy()
			await roundtrip()
			future_protection()
		else:
			await seed_disk()
	print("[npc-save-phase] ", phase, " 完成，failures=", failures)
	await finish()

func seed_state() -> void:
	if not landing_fixture("rooftop_ranch"): return
	await frames(3)
	await transactions_and_stories()
	await close_modals()
	if not landing_fixture("zone5"): return
	var support_id: String = await build_support_platform()
	if not check(not support_id.is_empty(), "存档夹具通过真实 BuildingService 创建非空正式平台记录"): return
	check(main.npc_service.to_dict().seen_events.size() == 7, "存档夹具包含真实七剧情选择和七请求结算")
	if not landing_fixture("rooftop_ranch"): return
	# 真正走上草地后再冻结稳定现场；不写玩家或 NPC 坐标。
	var roof: Vector3 = harbor.to_global(Vector3(0, harbor.ROOF_Y, 11.5))
	if not await walk_to(roof, "存档夹具沿消防梯实走至草地稳定现场"): return
	if not await until(func():
		for row in world.world_snapshot().residents.values():
			if row.remaining_waypoints > 0: return false
		return true, 40.0, "存档前七人真实日程走完"): return
	check_current_schedules()
	main.set_process(false)
	main.set_physics_process(false)
	# 胶囊扫掠保留微小安全间距；通过正式恢复端口统一为其承诺的支撑点，
	# 不把物理margin写成跨进程期望，也不放宽XYZ精确比较。
	var settled: Dictionary = main.capture_world_state()
	if not check(main.validate_world_state(settled) == "", "实走后的天台现场通过正式恢复校验"): return
	main.restore_world_state(settled)
	print("[npc-save-stable-support] walked=", settled, " restored=", main.capture_world_state())
	check(grass_support(main.player.global_position)
		and main.validate_world_state(main.capture_world_state()) == "", "天台草地现场及 landing 绑定通过正式世界验证")
	freeze_boat_presentation()

func freeze_boat_presentation() -> void:
	# Boat每帧按海浪改根Y，place_at按契约恢复WATER_LEVEL；它不是NPC存档位移。
	# 在写档前固定正式place_at的稳定海面姿态，不放宽玩家XYZ/船XZ/yaw断言。
	main.boat.set_process(false)
	main.boat.place_at(main.boat.position, main.boat.rotation.y)

func stable() -> Dictionary:
	return {"inventory": economy.inventory.to_dict(), "profile": main.avatar_profile.to_dict(),
		"building": main.building.to_dict(), "time": main.world_clock.to_dict(),
		"game": main.capture_world_state(), "npc": main.npc_service.to_dict(),
		"player": main.player.global_position, "actor": main.actor_controller.snapshot()}

func npc_bad_cases(base: Dictionary) -> Array:
	var cases: Array = []
	for pair in [["version", 2], ["version", 1.5], ["graph", {}], ["seen_events", []], ["choice_flags", []], ["request_states", []], ["typing", true], ["paths", [[1, 2, 3]]], ["inventory", {"rope": 999}]]:
		var bad: Dictionary = base.duplicate(true)
		bad[pair[0]] = pair[1]
		cases.append({"label": "坏字段 " + str(pair[0]) + "=" + str(pair[1]), "npc": bad})
	for key in base:
		var bad: Dictionary = base.duplicate(true)
		bad.erase(key)
		cases.append({"label": "已有 npc 截断缺 " + key, "npc": bad})
	for pair in [["affinity", -1], ["affinity", 1001], ["affinity", 1.5], ["met", "true"], ["last_talk_day", 0], ["gift_count", 3], ["last_gift_day", 0], ["birthday_gift_day", 0]]:
		var bad: Dictionary = base.duplicate(true)
		bad.graph[pair[0]]["npc_luo_yan"] = pair[1]
		cases.append({"label": "关系坏类型或越界 " + str(pair), "npc": bad})
	var unknown: Dictionary = base.duplicate(true)
	unknown.graph.affinity["npc_unknown"] = 1
	cases.append({"label": "未知 NPC ID", "npc": unknown})
	var lost: Dictionary = base.duplicate(true)
	lost.graph.met.erase("npc_hua_yi")
	cases.append({"label": "缺少第六人 graph 记录", "npc": lost})
	var choices: Dictionary = base.duplicate(true)
	choices.choice_flags["route_1:choice"] = "not-a-choice"
	cases.append({"label": "选择与真实路径不一致", "npc": choices})
	var request: Dictionary = base.duplicate(true)
	request.request_states.request_route_rope.source_event = "flower_1"
	cases.append({"label": "请求来源串到另一所有者", "npc": request})
	var edge: Dictionary = base.duplicate(true)
	edge.graph.edge_deltas[edge.graph.edge_deltas.keys()[0]] = 999
	cases.append({"label": "无可追溯剧情的关系边", "npc": edge})
	return cases

func strict_codec() -> void:
	var durable: Dictionary = main.npc_service.to_dict()
	check(Codec.validate(durable) == "" and Schema.validate(Save.encode(main)) == "", "唯一 durable codec 与整档 schema 接受同一真实状态")
	var service = Service.new()
	check(service.from_dict(JSON.parse_string(JSON.stringify(durable))).ok and service.to_dict() == durable, "跨 JSON 数字类型后由唯一 NpcService/Codec 还原")
	var mutated: Dictionary = service.to_dict()
	mutated.graph.affinity.npc_luo_yan = 0
	check(service.to_dict() == durable, "durable 查询为深副本")
	var entries: Dictionary = main.save_registry._entries
	check(entries.has("npc") and entries.npc.capture.get_object() == main.npc_service
		and entries.npc.apply.get_object() == main.npc_service and entries.npc.validator.get_object() == main.npc_service,
		"注册表 npc capture/apply/validator 唯一指向真实 NpcService")
	var owners := 0
	for id in entries:
		if entries[id].capture.get_object() == main.npc_service: owners += 1
	check(owners == 1, "Npc durable owner 仅登记一次")
	check(durable.keys().size() == 5 and durable.has("graph") and durable.has("seen_events")
		and durable.has("choice_flags") and durable.has("request_states"), "持久字段仅为 version/graph/seen_events/choice_flags/request_states")
	check(not has_transient(durable), "NPC 不保存 Node、路径、坐标、typing、UI、库存或临时目标")
	service.dispose()

func has_transient(value: Variant) -> bool:
	if value is Object or value is Callable or value is Vector3 or value is Vector2: return true
	if value is Dictionary:
		for key in value:
			if str(key) in ["paths", "path", "position", "target", "typing", "session_id", "confirmation", "inventory", "shop", "residence", "world", "actors"]: return true
			if has_transient(value[key]): return true
	elif value is Array:
		for item in value:
			if has_transient(item): return true
	return false

func atomic_rejections() -> void:
	var good: Dictionary = Save.encode(main)
	var cases := npc_bad_cases(good.npc)
	for entry in cases:
		var bad: Dictionary = good.duplicate(true)
		bad.npc = entry.npc
		# 所有候选都夹带有效的跨模块变更，若错误地先恢复就能看出来。
		bad.economy.inventory.counts.coins = int(bad.economy.inventory.counts.coins) + 7
		bad.time.seconds = float(bad.time.seconds) + 1.0
		bad.game = home_game()
		bad.building = preload("res://src/building/building_service.gd").empty_snapshot()
		var control: Dictionary = bad.duplicate(true)
		control.npc = good.npc.duplicate(true)
		check(Schema.validate(control) == "" and main.save_registry.validate(control) == "", "跨域污染候选本身合法，拒绝必须来自 npc " + entry.label)
		var before := stable()
		check(Codec.validate(entry.npc) != "" and not main.npc_service.from_dict(entry.npc).ok
			and main.npc_service.to_dict() == before.npc, "唯一 durable owner 自身原子拒绝 " + entry.label)
		var signals_before := restored_events
		check(not Save.decode(JSON.stringify(bad)).get("ok", false), "decode 必须拒绝 " + entry.label)
		check(not Save.restore(main, bad).get("ok", false), "整局 restore 必须拒绝 " + entry.label)
		check(stable() == before and restored_events == signals_before, "坏 npc 不改 Inventory/角色/建筑/时钟/profile，也不发 restored " + entry.label)
	var future: Dictionary = good.duplicate(true)
	future.version = Save.VERSION + 1
	var before := stable()
	check(Save.decode(JSON.stringify(future)).get("future", false), "future 整档可观测保护")
	check(not Save.restore(main, future).ok and stable() == before, "直接 future restore 拒绝整个事务")
	var malformed: Dictionary = good.duplicate(true)
	malformed.version = 4.5
	check(not Save.decode(JSON.stringify(malformed)).ok and not Save.restore(main, malformed).ok and stable() == before, "非法小数 wire 版本不是可迁移旧档")
	# npc 内部未来版本必须拒绝，而不是把已有 npc 当成缺省模块迁移。
	var future_npc: Dictionary = good.duplicate(true)
	future_npc.npc.version = 99
	check(not Save.decode(JSON.stringify(future_npc)).ok and not Save.restore(main, future_npc).ok and stable() == before, "future npc 不可回退 empty_snapshot")

func home_game() -> Dictionary:
	var landing: Dictionary = main._zone_nodes.zone1.landing_point("main").data()
	return {"zone": "zone1", "landing": "main", "mode": 0, "far_sea": state.far_sea_unlocked,
		"boat": [landing.boatPark[0], landing.boatPark[1], landing.boatPark[2], landing.boatYaw], "player": landing.landStand}

func legacy_policy() -> void:
	var good: Dictionary = Save.encode(main)
	var old: Dictionary = good.duplicate(true)
	old.erase("npc")
	var decoded: Dictionary = Save.decode(JSON.stringify(old))
	if check(decoded.get("ok", false), "按兼容文档，wire4 无 npc 是明确旧档，不误判为损坏 current"):
		check(decoded.snapshot.npc == Codec.empty_snapshot(), "旧 wire4 只补唯一 Codec 的明确默认")
		for key in good:
			if key != "npc": check(equivalent(decoded.snapshot[key], good[key]), "迁移不替换其他 owner " + key)
	var missing: Dictionary = main.save_registry.capture()
	missing.erase("npc")
	var before := stable()
	check(not main.save_registry.restore(missing).ok and stable() == before, "未经迁移的 current 注册表快照缺 npc 必须拒绝")
	check(Save.restore(main, old).ok and main.npc_service.to_dict() == Codec.empty_snapshot(), "SaveGame 兼容入口显式补旧 npc 默认")
	check(economy.inventory.to_dict() == before.inventory and main.avatar_profile.to_dict() == before.profile
		and main.building.to_dict() == before.building and main.world_clock.to_dict() == before.time, "旧档只清 NPC、不清背包/profile/建筑/钟")
	check(Save.restore(main, good).ok, "恢复合法集成夹具")

func roundtrip() -> void:
	var durable: Dictionary = main.npc_service.to_dict()
	if not await open_npc("npc_luo_yan"): return
	if not main.npc_service.dialogue_state().active and not await npc_press("talk"): return
	check(main.npc_service.dialogue_state().active and main.npc_service.dialogue_state().typing, "保存时存在真实未提交 typing 会话")
	var runtime: Dictionary = main.npc_service.capture_runtime()
	var path := "user://npc-tests/roundtrip.json"
	var saved: Dictionary = main.save_game(path, true)
	if not check(saved.get("ok", false), "Main.save_game 正式写盘：" + str(saved.get("reason", ""))): return
	check(main.npc_service.capture_runtime() == runtime and saved.snapshot.npc == durable
		and not has_transient(saved.snapshot.npc), "保存纯读保留未提交对白、不偷加好感、不存 typing/path")
	await close_modals()
	var expected: Dictionary = saved.snapshot
	check(economy.inventory.add("coins", 17).ok, "读档前更改现场库存")
	check(main.npc_service.from_dict(Codec.empty_snapshot()).ok, "读档前更改现场 NPC")
	if not landing_fixture("zone1"): return
	if not await open_career("npc_luo_yan", "ship"): return
	var restored := restored_events
	if not check(main.load_game(path).get("ok", false), "Main.load_game 正式读盘并完整恢复"): return
	await frames(3)
	check(restored_events == restored + 1, "整局只发一次 restored")
	check(main.npc_service.to_dict() == expected.npc and economy.inventory.to_dict() == expected.economy.inventory, "读档恢复真实 NPC 与 Inventory")
	check(equivalent(main.avatar_profile.to_dict(), expected.profile) and equivalent(main.building.to_dict(), expected.building)
		and equivalent(main.world_clock.to_dict(), expected.time), "读档恢复 profile/建筑/钟")
	print("[npc-save-pose] expected=", expected.game, " actual=", main.capture_world_state(), " actor=", main.actor_controller.snapshot())
	check(equivalent(main.capture_world_state(), expected.game) and main.actor_controller.state_id() == "ashore_idle"
		and expected.game.zone == "rooftop_ranch" and grass_support(main.player.global_position), "读档恢复天台草地稳定现场、合法 landing 与站立态")
	check(not world.is_modal() and not main.shop_panel.is_open() and not main.npc_career_panel.is_open()
		and not main.npc_service.dialogue_state().active and not main.hud._external_modal, "读档收起全部旧模态/typing/确认且解除世界输入盾")
	var positions := {}
	for id in Catalog.ids(): positions[id] = npc_site_position(id)
	var first: Dictionary = main.save_registry.capture()
	if not check(main.load_game(path).ok, "同档再次读取"): return
	await frames(3)
	check(main.save_registry.capture().npc == first.npc and equivalent(main.capture_world_state(), expected.game), "重复读档无叠加奖励/位置漂移")
	for id in positions:
		check(npc_site_position(id).distance_to(positions[id]) < 0.003 and npc_supported(id), "NPC 刷新依据天台/浮店/菜园桥/左楼顶支撑局部站位而非存档世界坐标 " + id)
	if await open_npc("npc_luo_yan") and await npc_press("gifts") and await npc_press("gift", "rope"):
		check(not world.panel.panel_snapshot().confirmation.is_empty(), "读档前存在真实礼物待确认")
		check(main.load_game(path).ok, "礼物确认途中正式读档")
		await frames(2)
		check(not world.is_modal() and not main.npc_service.dialogue_state().active
			and economy.inventory.to_dict() == expected.economy.inventory, "读档撤销礼物确认，不扣库存、不复活面板")
	if await open_npc("npc_hua_yi") and await finish_dialogue() and await npc_press("vendor"):
		check(main.shop_panel.is_open(), "读档前存在真实商店会话")
		check(main.load_game(path).ok, "商店打开时正式读档")
		await frames(2)
		check(not main.shop_panel.is_open() and not main.hud._external_modal
			and equivalent(main.capture_world_state(), expected.game), "读档关闭商店并恢复稳定 UI/位置")

func write_fixture(path: String, document: Dictionary) -> bool:
	if not check(path.begins_with("user://npc-tests/"), "只写隔离测试槽位"): return false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if not check(error == OK, "创建隔离测试目录"): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "打开测试文件 " + path): return false
	file.store_string(JSON.stringify(document))
	file.close()
	return true

func future_protection() -> void:
	var future: Dictionary = Save.encode(main)
	future.version = Save.VERSION + 1
	for suffix in ["primary", "backup"]:
		var path: String = "user://npc-tests/future-" + str(suffix) + ".json"
		var protected_path: String = path if suffix == "primary" else path + ".bak"
		if not write_fixture(protected_path, future): continue
		var before := file_state(protected_path)
		var snapshot := stable()
		check(Save.read(path).get("future", false), "未来主档/仅备份均不回退 " + suffix)
		var result: Dictionary = main.save_game(path, true)
		check(not result.ok and result.get("future", false) and file_state(protected_path) == before
			and stable() == snapshot, "未来档不覆盖且现场不改 " + suffix)

func expected_manifest(document: Dictionary) -> Dictionary:
	return {"seed_pid": OS.get_process_id(), "slot_sha256": FileAccess.get_sha256(SLOT),
		"npc": document.npc, "inventory": document.economy.inventory, "profile": document.profile,
		"building": document.building, "time": document.time, "game": document.game}

func seed_disk() -> void:
	if failures != 0:
		check(false, "seed 前置失败，禁止写入成功凭据"); return
	var result: Dictionary = main.save_game(SLOT, true)
	if not check(result.get("ok", false), "seed 正式 SaveGame 写共享槽位"): return
	check(write_fixture(MANIFEST, expected_manifest(result.snapshot)), "seed 写跨进程期望值，不以重启现场自证")
	print("[npc-save-seed] pid=", OS.get_process_id(), " slot=", ProjectSettings.globalize_path(SLOT), " sha256=", FileAccess.get_sha256(SLOT))

func restart() -> void:
	if not check(FileAccess.file_exists(SLOT) and FileAccess.file_exists(MANIFEST), "restart 必须复用 seed 的 user 目录，缺文件不能跳过"): return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not check(expected is Dictionary and expected.has("seed_pid") and expected.has("slot_sha256"), "跨进程期望文件完整"): return
	check(int(expected.seed_pid) != OS.get_process_id(), "restart 必须是不同进程，不能进程内伪重启")
	check(FileAccess.get_sha256(SLOT) == expected.slot_sha256, "重启前 seed 档未被自动保存覆盖")
	check(main.npc_service.to_dict() == Codec.empty_snapshot(), "restart 前尚未隐式加载 seed 数据")
	main.set_process(false)
	main.set_physics_process(false)
	freeze_boat_presentation()
	if not check(main.load_game(SLOT).get("ok", false), "新进程经正式 Main.load_game 恢复 seed"): return
	await frames(4)
	check_current_schedules()
	check(equivalent(main.npc_service.to_dict(), expected.npc) and equivalent(economy.inventory.to_dict(), expected.inventory), "跨进程 NPC/库存精确一致")
	print("[npc-save-restart-owners] profile=", equivalent(main.avatar_profile.to_dict(), expected.profile),
		" building=", equivalent(main.building.to_dict(), expected.building), " time=", equivalent(main.world_clock.to_dict(), expected.time),
		" expected_game=", expected.game, " actual_game=", main.capture_world_state())
	check(equivalent(main.avatar_profile.to_dict(), expected.profile) and equivalent(main.building.to_dict(), expected.building)
		and equivalent(main.world_clock.to_dict(), expected.time) and equivalent(main.capture_world_state(), expected.game), "跨进程 profile/建筑/钟/天台草地稳定现场一致")
	check(expected.game.zone == "rooftop_ranch" and expected.game.landing == "main"
		and main.actor_controller.state_id() == "ashore_idle" and grass_support(main.player.global_position), "跨进程恢复天台草地稳定现场及合法 landing，不回退旧社区")
	for id in Catalog.ids():
		check(npc_supported(id), "新进程 NPC 保持所属实际面的支撑 " + id)
		var route: Dictionary = world._routes.get(id, {})
		var target: Dictionary = route.get("target", {})
		if not check(not target.is_empty(), "新进程日程目标非空 " + id): continue
		var current_anchors: Dictionary = provider.anchor_snapshot()
		if not check(current_anchors.has(target.get("anchor_id", "")), "新进程日程目标来自实际 provider " + id): continue
		check(target.ground == current_anchors[target.anchor_id].ground,
			"新进程由当前日程所属 Marker 派生面恢复而非存档坐标 " + id)
		check(not route.get("fallback", true), "新进程当前日程无静默回退 " + id)
	check(not world.is_modal() and not main.shop_panel.is_open() and not main.npc_career_panel.is_open()
		and not main.npc_service.dialogue_state().active, "跨进程只恢复稳定 UI，不复活 typing/路径/确认")
	if not await open_career("npc_bai_shi", "archive"): return
	# 入场可先触发一段新的条件剧情；回看无副作用从进入档案后开始核对。
	var durable: Dictionary = main.npc_service.to_dict()
	if not await career_press("replay_event", "route_1") or not await finish_dialogue(): return
	check(main.npc_service.to_dict() == durable, "新进程档案回看不重复请求奖励")
	await close_modals()
	check(FileAccess.get_sha256(SLOT) == expected.slot_sha256, "restart 全程不回写 seed 槽位")
	print("[npc-save-restart] seed_pid=", expected.seed_pid, " restart_pid=", OS.get_process_id(), " sha256=", FileAccess.get_sha256(SLOT))
