extends RefCounted
class_name SaveGame
## Storage consumes registered snapshots, never global state or actor/UI internals.
const VERSION := 4
const SLOT_PATH := "user://save_slot_0.json"
const Schema = preload("res://src/save/save_schema.gd")
const MAX_BYTES := 8 * 1024 * 1024
const ResetTransaction = preload("res://src/save/reset_transaction.gd")
static var _reset_active := false

## 显式授权的重置允许归档未来档；常规 write/read 仍保持未来版本保护。
## 宿主的保护/自动存档配置不在此修改，调用者只在 ok 后提交配置。
static func reset(path: String, host: Node) -> Dictionary:
	if _reset_active or host.save_registry.is_busy():
		return {"ok":false,"reason":"正在恢复、重置或结算","archived":[]}
	_reset_active = true
	var result: Dictionary = ResetTransaction.new().run(path, host, load("res://src/save/save_game.gd"))
	_reset_active = false
	return result

static func now_seconds() -> float: return Time.get_ticks_msec()/1000.0

static func encode(host: Node) -> Dictionary:
	var data: Dictionary = host.save_registry.capture()
	data.version = VERSION
	data.saved_at = Time.get_datetime_string_from_system()
	data.wall_time = int(Time.get_unix_time_from_system())
	return data

static func write(path: String, host: Node) -> Dictionary:
	if _reset_active or ResetTransaction.new().pending(path):
		return {"ok":false,"reason":"重置事务未完成，请先恢复槽位"}
	if host.save_registry.is_busy(): return {"ok":false,"reason":"恢复或结算期间不能写入中间快照"}
	var snapshot := encode(host)
	var validation := Schema.validate_result(snapshot)
	if not validation.ok: return validation
	var error: String = host.save_registry.validate(snapshot)
	if error != "": return {"ok":false,"reason":error}
	# 未来主档和备份优先保护；轮换资格必须经过完整注册表校验。
	var existing := _read_one(path)
	var backup := _read_one(path+".bak")
	if existing.get("future",false): return existing
	if backup.get("future",false): return backup
	existing = validate_read_result(existing, host.save_registry)
	backup = validate_read_result(backup, host.save_registry)
	if FileAccess.file_exists(path) and not existing.ok and not backup.ok:
		return {"ok":false,"reason":"原存档损坏且无可用备份，请另存新槽位"}
	var text := JSON.stringify(snapshot,"\t")
	if not _write_text(path,text,existing.ok): return {"ok":false,"reason":"存档写入或替换失败","path":path}
	return {"ok":true,"reason":"","path":path,"bytes":text.to_utf8_buffer().size(),"snapshot":snapshot}

static func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"reason":"还没有存档"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"reason":"存档打不开"}
	if file.get_length()>MAX_BYTES: return {"ok":false,"reason":"存档过大"}
	return decode(file.get_as_text())

# 不传 registry 的旧接口仅保证 wire 有效；宿主加载应传入其完整注册表。
static func read(path: String, registry = null) -> Dictionary:
	if _reset_active or ResetTransaction.new().pending(path):
		return {"ok":false,"reason":"重置事务未完成，请使用 read_recoverable 恢复槽位"}
	var result := _read_one(path)
	var backup := _read_one(path+".bak")
	if result.get("future",false): return result
	if backup.get("future",false): return backup
	result = validate_read_result(result, registry)
	backup = validate_read_result(backup, registry)
	if result.ok: return result
	if backup.ok:
		backup.recovered = true
		backup.reason = "已从上次有效备份恢复"
		return backup
	return result

static func read_recoverable(path: String, registry) -> Dictionary:
	if registry == null: return {"ok":false,"reason":"完整恢复读取需要注册表"}
	if _reset_active or registry.is_busy(): return {"ok":false,"reason":"正在恢复、重置或结算"}
	var recovered: Dictionary = ResetTransaction.new().recover(path)
	if not recovered.ok: return recovered
	# 空槽重置在 intent 后中断，没有主档/bak也必须完成恢复并允许新开局。
	if recovered.get("reset_recovered", false) and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		var fresh: Dictionary = registry.defaults()
		fresh.version = VERSION
		return {"ok":true,"reason":"已恢复未提交的空槽重置","snapshot":fresh,"version":VERSION,"reset_recovered":true,"empty_slot":true}
	var result := read(path, registry)
	if recovered.get("reset_recovered", false):
		result.reset_recovered = true
		result.reset_committed = recovered.reset_committed
	return result

static func validate_read_result(result: Dictionary, registry) -> Dictionary:
	if not result.ok or registry == null: return result
	var error: String = registry.validate(result.snapshot)
	if error != "": return {"ok":false,"reason":error}
	var validated := result.duplicate(true)
	validated.semantic_validated = true
	return validated

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size()>MAX_BYTES: return {"ok":false,"reason":"存档过大"}
	var parser := JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary: return {"ok":false,"reason":"存档不是有效 JSON"}
	var doc: Dictionary = parser.data
	var value: Variant = doc.get("version",0)
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)) or value<0:
		return {"ok":false,"reason":"存档版本格式错误"}
	var future := Schema.future_error(doc)
	if future != "": return {"ok":false,"future":true,"reason":future}
	var version := int(value)
	if version==0:
		if not doc.get("inventory") is Dictionary: return {"ok":false,"reason":"旧存档缺少背包数据"}
		var econ := {}
		for key in ["inventory","ship_level","site_levels","facilities","site_work","farm","warehouse","orders","tracked_goal"]:
			if doc.has(key): econ[key]=doc[key]
		doc = {"economy":econ,"game":doc.get("game",{}),"gather":doc.get("gather",{}),"salvage_left":doc.get("salvage_left",0.0)}
	if not doc.get("economy") is Dictionary: return {"ok":false,"reason":"存档 economy 必须为对象"}
	if version<2:
		# Defaults are migration policy, never an excuse to accept a truncated v2 save.
		var defaults := {"warehouse":{"capacity":48,"counts":{}},"ship_level":1,"tracked_goal":"",
			"site_levels":{},"facilities":{},"site_work":{},"farm":{},"orders":{}}
		for key in defaults:
			if not doc.economy.has(key): doc.economy[key]=defaults[key]
		for key in ["game","gather","dive","pickups"]:
			if not doc.has(key): doc[key]={}
		if doc.pickups is Dictionary and doc.pickups.is_empty(): doc.pickups={"reset":true}
		if doc.dive is Dictionary:
			for key in ["found","opened"]:
				if not doc.dive.has(key): doc.dive[key]=[]
		var legacy_defaults := {
			"farm":{"version":1,"day":1,"watering_can":12,"selected_crop":"lettuce","plots":{}},
			"orders":{"slots":[]},
			"game":{"zone":"zone1","landing":"main","mode":1,"far_sea":false,"boat":[],"player":[]}}
		for id in legacy_defaults:
			var record: Variant = doc.get(id) if id=="game" else doc.economy.get(id)
			if not record is Dictionary: return {"ok":false,"reason":"旧存档模块格式错误: "+id}
			for key in legacy_defaults[id]:
				if not record.has(key): record[key]=legacy_defaults[id][key]
		if doc.economy.farm.plots is Dictionary:
			for plot in doc.economy.farm.plots.values():
				if not plot is Dictionary: continue
				var plot_defaults := {"crop":"","remaining":plot.get("total",0.0),"total":1.0 if plot.get("crop","")!="" else 0.0,"water":0.0,"harvests":0}
				for key in plot_defaults:
					if not plot.has(key): plot[key]=plot_defaults[key]
		doc.salvage = {"left":doc.get("salvage_left",0.0)}
		# 无时钟旧档以农田历史日次建立候选日历，不能把已玩多天的旧档迁回第 1 天。
		doc.time = {"day":doc.economy.farm.day,"seconds":28800.0,"day_length":1200.0}
		doc.weather = {"kind":"clear","remaining":240.0,"seed":3701,"duration":240.0}
	if version<3 and doc.get("economy") is Dictionary and not doc.economy.has("daily_loop"):
		doc.economy.daily_loop = {"version":1,"cargo":{"capacity":48,"counts":{}},"last_morning":-1,"receipt":{}}
	if version<4: doc.building=preload("res://src/building/building_service.gd").empty_snapshot()
	doc.version=VERSION
	_migrate_optional(doc)
	var validation := Schema.validate_result(doc)
	if not validation.ok: return validation
	doc.profile=preload("res://src/avatar/avatar_profile.gd").normalize(doc.profile)
	return {"ok":true,"reason":"","snapshot":doc,"version":VERSION,"migrated":version<VERSION}

static func _migrate_optional(snapshot: Dictionary) -> void:
	if not snapshot.has("profile"): snapshot.profile=preload("res://src/avatar/avatar_profile.gd").fresh(true)
	if not snapshot.has("room"):
		snapshot.room={"version":1,"bed":{"position":[-1.86,0.0,-1.425],"yaw":0.0},"inside":false}
	if not snapshot.has("npc"): snapshot.npc=preload("res://src/npc/npc_save_codec.gd").empty_snapshot()
	if snapshot.get("economy") is Dictionary and not snapshot.economy.has("sunroom"):
		snapshot.economy.sunroom=preload("res://src/facilities/sunroom_service.gd").new().to_dict()

static func restore(host: Node, snapshot: Dictionary) -> Dictionary:
	if _reset_active: return {"ok":false,"reason":"正在重置存档"}
	snapshot=snapshot.duplicate(true)
	_migrate_optional(snapshot)
	var validation := Schema.validate_result(snapshot)
	if not validation.ok: return validation
	snapshot.profile=preload("res://src/avatar/avatar_profile.gd").normalize(snapshot.profile)
	return host.save_registry.restore(snapshot)


## 把某个槽位的主档与备份**改名归档**，不是删除。
##
## 重置存档是玩家亲手执行的破坏性动作，但「亲手执行」不等于「愿意永久丢掉」。
## 改名之后：`read()` 按原槽位路径找不到任何东西（等于全新开局），而旧进度仍
## 留在磁盘上、还能用同一个 `read()` 打开 —— 想找回只改文件名就行。
##
## 归档名用 `_pre_reset-<时间戳>` 而不是盖掉 `.bak`：`.bak` 是「上一次写盘」的
## 单份回滚点，会被下一次写盘顶掉；归档必须留在写盘循环之外，否则重置完再存
## 一次档，旧进度就真没了。
##
## 返回 `files` 是已经归档出去的实际路径，调用方据此告诉玩家备份在哪。
static func archive(path: String, stamp := "") -> Dictionary:
	if _reset_active or ResetTransaction.new().pending(path):
		return {"ok":false,"reason":"重置事务未完成，不能移动槽位","files":[]}
	var base := path.get_basename()
	var ext := path.get_extension()
	var tail := "." + ext if ext != "" else ""
	var mark := stamp if stamp != "" else Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	if mark.contains("/") or mark.contains("\\") or mark in [".", ".."]:
		return {"ok":false,"reason":"归档标记格式错误","files":[]}
	var original_mark := mark
	var index := 0
	# 主档和备份共用唯一标记，连仅存在 .bak 的归档也不能被覆盖。
	while _archive_target_exists(base, mark, tail):
		index += 1
		mark = original_mark + "-" + str(index)
	var moved: Array[String] = []
	var origins: Array[String] = []
	for suffix in ["", ".bak"]:
		var from: String = path + String(suffix)
		if not FileAccess.file_exists(from): continue
		var to := "%s_pre_reset-%s%s%s" % [base, mark, tail, suffix]
		var code := DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
		if code != OK:
			var rollback_errors: Array = []
			var remaining: Array[String] = []
			for i in range(moved.size()-1, -1, -1):
				var undo_code := ERR_ALREADY_EXISTS
				if not FileAccess.file_exists(origins[i]):
					undo_code = DirAccess.rename_absolute(ProjectSettings.globalize_path(moved[i]), ProjectSettings.globalize_path(origins[i]))
				if undo_code != OK:
					rollback_errors.append({"from":moved[i],"to":origins[i],"code":undo_code})
					remaining.append(moved[i])
			return {"ok":false,"reason":"旧存档无法归档，重置已取消" if rollback_errors.is_empty() else "归档失败且回滚不完整，请保留归档文件", "code":code,"files":remaining,"rollback_errors":rollback_errors}
		moved.append(to)
		origins.append(from)
	return {"ok":true,"reason":"","files":moved,"mark":mark}

static func _archive_target_exists(base: String, mark: String, tail: String) -> bool:
	for suffix in ["", ".bak"]:
		var target := "%s_pre_reset-%s%s%s" % [base, mark, tail, suffix]
		if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)): return true
	return false


static func _write_text(path: String, text: String, rotate_backup: bool) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temp := path+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.get_file_as_string(temp)!=text or not _read_one(temp).ok: return false
	if rotate_backup:
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak.tmp"))!=OK: return false
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".bak.tmp"),ProjectSettings.globalize_path(path+".bak"))!=OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))==OK
