extends SceneTree
## 仅正式 runner 的隔离工程运行；故障端口只存在于本测试子类。
const Save = preload("res://src/save/save_game.gd")
const Tx = preload("res://src/save/reset_transaction.gd")
const Registry = preload("res://src/save/snapshot_registry.gd")

class Host extends Node:
	var save_registry
	var npc_owner
	var _save_protected := true
	var _autosave_on := false
	var _autosave_left := 17.0

class InjectedTx extends Tx:
	var fault := ""
	var killed_at := ""
	var fired := false
	var rollback_failed := false
	var stages := 0
	func write_verified(path: String, text: String) -> bool:
		if path.ends_with(STAGE): stages += 1
		if not fired and ((fault == "prepare-after-apply" and stages == 2) or (fault == "intent" and path.ends_with(INTENT + ".tmp"))):
			fired = true
			return false
		if not fired and ((fault == "prepare" and path.ends_with(STAGE)) or (fault in ["commit", "rollback"] and text.contains('"committed":true'))):
			fired = true
			return false
		return super.write_verified(path, text)
	func copy_verified(source: String, target: String, expected: String) -> bool:
		if not fired and fault == "archive" and target.contains("_pre_reset-") and target.ends_with(".bak"):
			fired = true
			return false
		var ok := super.copy_verified(source, target, expected)
		if ok and killed_at == "archive" and target.contains("_pre_reset-"): OS.kill(OS.get_process_id())
		return ok
	func rename_file(source: String, target: String) -> Error:
		if fault == "rollback" and source.ends_with(".reset-rollback"):
			rollback_failed = true
			return ERR_CANT_CREATE
		if not fired and fault == "rename" and source.ends_with(STAGE):
			fired = true
			return ERR_CANT_CREATE
		var code := super.rename_file(source, target)
		if code == OK:
			if killed_at == "intent" and target.ends_with(INTENT): OS.kill(OS.get_process_id())
			if killed_at == "replace" and source.ends_with(STAGE): OS.kill(OS.get_process_id())
		return code
	func remove_file(path: String) -> Error:
		if killed_at == "commit" and path.ends_with(STAGE): OS.kill(OS.get_process_id())
		return super.remove_file(path)

var checks := 0
var failures := 0
var initial: Dictionary
var crash_root := ""

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	print("[b2-reset-atomic] ", "PASS " if value else "FAIL ", label)
	if not value: failures += 1

func host_for(snapshot: Dictionary) -> Host:
	var host := Host.new()
	host.save_registry = Registry.new()
	var schemas: Dictionary = Save.Schema.schemas()
	var state := snapshot.duplicate(true)
	for id in schemas:
		if not state.has(id): continue
		var key: String = id
		if key == "npc":
			var service = preload("res://src/npc/npc_service.gd").new()
			host.npc_owner = service
			service.from_dict(state[key])
			host.save_registry.register(key, service.to_dict, service.from_dict, schemas[key], initial[key], service.validate_snapshot, [service])
		else:
			host.save_registry.register(key, func(): return state[key], func(data): state[key] = data, schemas[key], initial[key])
	return host

func played() -> Dictionary:
	var snapshot := initial.duplicate(true)
	snapshot.economy.inventory.counts.coins = 654
	return snapshot

func fixture(path: String, future := false) -> Dictionary:
	var main := played()
	if future: main.version = 999
	var tx := Tx.new()
	check(tx.write_verified(path, JSON.stringify(main)), "准备主档 " + path.get_file())
	check(tx.write_verified(path + ".bak", JSON.stringify(initial)), "准备备份")
	return {"main":FileAccess.get_sha256(path), "bak":FileAccess.get_sha256(path + ".bak")}

func unchanged(path: String, hashes: Dictionary, host: Host) -> void:
	check(FileAccess.get_sha256(path) == hashes.main and FileAccess.get_sha256(path + ".bak") == hashes.bak, "原槽与备份字节未变")
	check(host.save_registry.capture() == _modules(played()), "前内存已完整恢复")
	check(host._save_protected and not host._autosave_on and host._autosave_left == 17.0, "宿主保护与自动存档配置未被修改")

func _modules(snapshot: Dictionary) -> Dictionary:
	var data := snapshot.duplicate(true)
	for key in ["version", "saved_at", "wall_time"]: data.erase(key)
	return data

func run() -> void:
	crash_root = OS.get_environment("SEA_B2_RESET_ROOT")
	var phase := OS.get_environment("SEA_B2_RESET_PHASE")
	if phase != "":
		initial = JSON.parse_string(FileAccess.get_file_as_string(crash_root + "/initial.json"))
		await crash_case(phase)
		return
	var main: Node
	if OS.get_environment("SEA_B2_PORT_ONLY") == "1":
		initial = JSON.parse_string(FileAccess.get_file_as_string(crash_root + "/initial.json"))
		check(Save.Schema.validate_result(initial).ok, "已冻结正式开局夹具合法（仅存储端验证）")
	else:
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		main._autosave_on = false
		main.set_process(false)
		main.set_physics_process(false)
		main.world_clock.paused = true
		root.get_node("Economy").set_process(false)
		await process_frame
		await process_frame
		initial = Save.encode(main)
		check(Save.Schema.validate_result(initial).ok, "正式宿主开局快照合法")
		# 实际 Main 注册表及 restored 投影，不只测字典夹具。
		var real_slot := "user://b2-real-reset.json"
		check(Save.write(real_slot, main).ok, "正式宿主可写初始档")
		var real_result: Dictionary = Save.reset(real_slot, main)
		check(real_result.ok and real_result.archived.size() == 1, "总接口对正式宿主提交成功")
		check(Save.read_recoverable(real_slot, main.save_registry).ok, "正式宿主提交后的磁盘可恢复")
	if crash_root != "": check(Tx.new().write_verified(crash_root + "/initial.json", JSON.stringify(initial)), "准备工程外跨进程夹具")
	for fault in ["prepare", "prepare-after-apply", "intent", "archive", "rename", "commit"]:
		var path: String = "user://b2-reset-" + fault + ".json"
		var hashes := fixture(path)
		var host := host_for(played())
		var tx := InjectedTx.new()
		tx.fault = fault
		var npc: Object = host.save_registry._entries.npc.apply.get_object()
		check(npc.start_dialogue("reset_probe", [{"id":"one","speaker":"测试","text":"重置前未提交"}]).ok, "重置故障前启动会话")
		var runtime: Dictionary = npc.capture_runtime()
		var result: Dictionary = tx.run(path, host, Save, "fixed")
		check(not result.ok and tx.fired, "注入 " + fault + " 返回失败")
		check(npc.capture_runtime() == runtime, "失败重置保留runtime会话：" + fault)
		unchanged(path, hashes, host)
		check(not Tx.new().pending(path), "回滚后无未完成意图")
		host.free()
	var rollback_path := "user://b2-reset-rollback.json"
	var rollback_hashes := fixture(rollback_path)
	var rollback_host := host_for(played())
	var rollback_tx := InjectedTx.new()
	rollback_tx.fault = "rollback"
	var rollback_result: Dictionary = rollback_tx.run(rollback_path, rollback_host, Save, "fixed")
	check(not rollback_result.ok and rollback_result.recovery_required and rollback_tx.rollback_failed, "回滚自身失败明确报告并保留意图")
	check(not Save.write(rollback_path, rollback_host).ok, "回滚失败后禁止普通存档覆盖")
	check(Save.read_recoverable(rollback_path, rollback_host.save_registry).ok, "移除测试 I/O 故障后可恢复")
	unchanged(rollback_path, rollback_hashes, rollback_host)
	rollback_host.free()
	var invalid_path := "user://b2-reset-invalid-fresh.json"
	var invalid_hashes := fixture(invalid_path)
	var invalid_host := host_for(played())
	invalid_host.save_registry.snapshot_validator = func(data): return "测试拒绝 fresh" if data.economy.inventory.counts.coins == 80 else ""
	var invalid_result: Dictionary = Save.reset(invalid_path, invalid_host)
	check(not invalid_result.ok and not FileAccess.file_exists(invalid_path + Tx.STAGE), "fresh 预校验失败发生在写盘和内存修改之前")
	unchanged(invalid_path, invalid_hashes, invalid_host)
	invalid_host.free()
	var apply_path := "user://b2-reset-apply.json"
	var apply_hashes := fixture(apply_path)
	var apply_host := host_for(played())
	var fail_once := [true]
	apply_host.save_registry.register("reject", func(): return {}, func(_data):
		if fail_once[0]:
			fail_once[0] = false
			return false
		return true, {}, {})
	var apply_events: Array = []
	apply_host.save_registry.restored.connect(func(): apply_events.append(true))
	var apply_result: Dictionary = Tx.new().run(apply_path, apply_host, Save, "fixed")
	check(not apply_result.ok and apply_result.get("rollback_ok", false), "真实注册表 apply 失败与整件回滚")
	check(apply_events.is_empty(), "registry apply失败不二次restore或发伪成功事件")
	check(FileAccess.get_sha256(apply_path) == apply_hashes.main and apply_host.save_registry.capture().economy.inventory.counts.coins == 654, "apply 失败保留原盘和前内存")
	apply_host.free()
	var path := "user://b2-reset-fixed.json"
	var hashes := fixture(path, true)
	var host := host_for(played())
	check(Save.write(path, host).get("future", false), "普通写盘拒绝未来主档")
	var first: Dictionary = Tx.new().run(path, host, Save, "fixed")
	check(first.ok and first.archived.size() == 2, "显式重置归档未来档及备份")
	check(FileAccess.get_sha256(first.archived[0]) == hashes.main, "未来档原字节完整保留")
	check(Save.read(first.archived[0]).get("future", false), "未来归档仍拒绝降存")
	var second: Dictionary = Tx.new().run(path, host, Save, "fixed")
	check(second.ok and second.mark == "fixed-1", "重复固定标记使用唯一归档")
	check(FileAccess.get_sha256(first.archived[0]) == hashes.main, "重复重置不覆盖首次归档")
	check(not FileAccess.file_exists(path + ".bak"), "提交后旧备份不在原槽回滚位")
	var reentrant: Array = []
	host.save_registry.restored.connect(func():
		reentrant.append(Save.write(path, host).ok)
		reentrant.append(Save.reset(path, host).ok))
	check(Save.reset(path, host).ok and reentrant == [false, false], "restored 同步重入不能写盘或再次重置")
	host.free()
	var future_bak_path := "user://b2-reset-future-bak.json"
	fixture(future_bak_path)
	var future_bak := initial.duplicate(true)
	future_bak.weather.version = 999
	Tx.new().write_verified(future_bak_path + ".bak", JSON.stringify(future_bak))
	var future_bak_hash := FileAccess.get_sha256(future_bak_path + ".bak")
	var future_host := host_for(played())
	check(Save.write(future_bak_path, future_host).get("future", false), "普通写盘保护同 root 未来模块备份")
	var future_result: Dictionary = Save.reset(future_bak_path, future_host)
	check(future_result.ok and FileAccess.get_sha256(future_result.archived[1]) == future_bak_hash, "显式 reset 原字节保留未来模块备份")
	future_host.free()
	var empty_host := host_for(played())
	var empty_result: Dictionary = Save.reset("user://b2-reset-empty.json", empty_host)
	check(empty_result.ok and empty_result.archived.is_empty(), "空槽位重置生成新档")
	var bad_path := "user://b2-reset-bad-intent.json"
	var bad_hashes := fixture(bad_path)
	Tx.new().write_verified(bad_path + Tx.INTENT, '{"mark":"../other"}')
	check(not Save.read_recoverable(bad_path, empty_host.save_registry).ok, "损坏或越界意图拒绝恢复")
	check(FileAccess.get_sha256(bad_path) == bad_hashes.main and not Save.write(bad_path, empty_host).ok, "坏意图不改原槽且阻止覆盖")
	Tx.new().write_verified(bad_path + Tx.INTENT, "{")
	check(not Save.read_recoverable(bad_path, empty_host.save_registry).ok, "截断 JSON 意图平稳拒绝且保留证据")
	empty_host.free()
	var busy := host_for(played())
	busy.save_registry.busy_query = func(): return true
	check(not Save.reset("user://busy.json", busy).ok, "稳定态忙门禁拒绝重置")
	busy.free()
	if main != null: main.queue_free()
	await process_frame
	finish()

func crash_case(phase: String) -> void:
	var parts := phase.split(":")
	var point: String = parts[1]
	var path := crash_root + "/crash-" + point + ".json"
	var host := host_for(played())
	if parts[0] == "seed":
		fixture(path, point == "future")
		var tx := InjectedTx.new()
		tx.killed_at = "replace" if point == "future" else point
		print("[b2-reset-crash] 即将中止 ", point)
		tx.run(path, host, Save, "fixed")
		check(false, "崩溃注入必须中止进程")
	else:
		var journal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + Tx.INTENT))
		check(not Save.write(path, host).ok and not Save.read(path).ok, "恢复前普通读写均拒绝未完成重置")
		var result: Dictionary = Save.read_recoverable(path, host.save_registry)
		if point == "future":
			check(result.get("future", false), "跨进程回滚未来原档后仍保护")
		else:
			check(result.ok and result.get("reset_recovered", false), "跨进程启动识别意图并恢复")
			check(result.snapshot.economy.inventory.counts.coins == (80 if point == "commit" else 654), "跨进程恢复确定的新旧状态")
		if point != "commit":
			for original in journal.originals:
				check(FileAccess.get_sha256(path + original.suffix) == original.hash, "未提交重置回滚原始字节 " + original.suffix)
		else:
			check(not FileAccess.file_exists(path + ".bak"), "已提交重置不复活旧备份")
		check(not Tx.new().pending(path), "恢复后移除意图")
		var again: Dictionary = Save.read_recoverable(path, host.save_registry)
		check(again.get("future", false) if point == "future" else again.ok, "恢复操作幂等")
	host.free()
	finish()

func finish() -> void:
	print("[b2-reset-atomic] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
