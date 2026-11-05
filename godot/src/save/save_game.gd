extends RefCounted
class_name SaveGame
## Storage consumes registered snapshots, never global state or actor/UI internals.
const VERSION := 4
const SLOT_PATH := "user://save_slot_0.json"
const Schema = preload("res://src/save/save_schema.gd")
const MAX_BYTES := 8 * 1024 * 1024

static func now_seconds() -> float: return Time.get_ticks_msec()/1000.0

static func encode(host: Node) -> Dictionary:
	var data: Dictionary = host.save_registry.capture()
	data.version = VERSION
	data.saved_at = Time.get_datetime_string_from_system()
	data.wall_time = int(Time.get_unix_time_from_system())
	return data

static func write(path: String, host: Node) -> Dictionary:
	if host.save_registry.is_busy(): return {"ok":false,"reason":"恢复或结算期间不能写入中间快照"}
	var snapshot := encode(host)
	var error := Schema.validate(snapshot)
	if error != "": return {"ok":false,"reason":error}
	error = host.save_registry.validate(snapshot)
	if error != "": return {"ok":false,"reason":error}
	# A missing/corrupt main file must not strand a backup created by a newer game.
	var backup := _read_one(path+".bak")
	if backup.get("future",false): return backup
	if FileAccess.file_exists(path):
		var existing := _read_one(path)
		if existing.get("future",false): return existing
		if not existing.ok and not _read_one(path+".bak").get("ok",false):
			return {"ok":false,"reason":"原存档损坏且无可用备份，请另存新槽位"}
	var text := JSON.stringify(snapshot,"\t")
	if not _write_text(path,text): return {"ok":false,"reason":"存档写入或替换失败","path":path}
	return {"ok":true,"reason":"","path":path,"bytes":text.to_utf8_buffer().size(),"snapshot":snapshot}

static func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"reason":"还没有存档"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"reason":"存档打不开"}
	if file.get_length()>MAX_BYTES: return {"ok":false,"reason":"存档过大"}
	return decode(file.get_as_text())

static func read(path: String) -> Dictionary:
	var result := _read_one(path)
	if result.ok or result.get("future",false): return result
	var backup := _read_one(path+".bak")
	if backup.get("future",false): return backup
	if backup.ok:
		backup.recovered = true
		backup.reason = "已从上次有效备份恢复"
		return backup
	return result

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size()>MAX_BYTES: return {"ok":false,"reason":"存档过大"}
	var parser := JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary: return {"ok":false,"reason":"存档不是有效 JSON"}
	var doc: Dictionary = parser.data
	var value: Variant = doc.get("version",0)
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)) or value<0:
		return {"ok":false,"reason":"存档版本格式错误"}
	var version := int(value)
	if version>VERSION: return {"ok":false,"future":true,"reason":"存档版本比当前游戏新，已保护原档"}
	if version==0:
		if not doc.get("inventory") is Dictionary: return {"ok":false,"reason":"旧存档缺少背包数据"}
		var econ := {}
		for key in ["inventory","ship_level","site_levels","facilities","site_work","farm","warehouse","orders","tracked_goal"]:
			if doc.has(key): econ[key]=doc[key]
		doc = {"economy":econ,"game":doc.get("game",{}),"gather":doc.get("gather",{}),"salvage_left":doc.get("salvage_left",0.0)}
	if version<2:
		if not doc.get("economy") is Dictionary: return {"ok":false,"reason":"旧存档缺少经济数据"}
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
		doc.time = {"day":1,"seconds":28800.0,"day_length":1200.0}
		doc.weather = {"kind":"clear","remaining":240.0,"seed":3701,"duration":240.0}
	if version<3 and doc.get("economy") is Dictionary and not doc.economy.has("daily_loop"):
		doc.economy.daily_loop = {"version":1,"cargo":{"capacity":48,"counts":{}},"last_morning":-1,"receipt":{}}
	if version<4: doc.building=preload("res://src/building/building_service.gd").empty_snapshot()
	doc.version=VERSION
	if not doc.has("profile"): doc.profile=preload("res://src/avatar/avatar_profile.gd").fresh(true)
	if not doc.has("room"):
		# 2026-11-05 新增的房间模块：旧 v4 档缺这一段，按初版床位置补，版本号不动。
		doc.room={"version":1,"bed":{"position":[-1.86,0.0,-1.425],"yaw":0.0},"inside":false}
	var error := Schema.validate(doc)
	if error!="": return {"ok":false,"reason":error}
	doc.profile=preload("res://src/avatar/avatar_profile.gd").normalize(doc.profile)
	return {"ok":true,"reason":"","snapshot":doc,"version":VERSION,"migrated":version<VERSION}

static func restore(host: Node, snapshot: Dictionary) -> Dictionary:
	snapshot=snapshot.duplicate(true)
	if not snapshot.has("profile"): snapshot.profile=preload("res://src/avatar/avatar_profile.gd").fresh(true)
	var error := Schema.validate(snapshot)
	if error!="": return {"ok":false,"reason":error}
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
	var base := path.get_basename()
	var ext := path.get_extension()
	var tail := "." + ext if ext != "" else ""
	var mark := stamp if stamp != "" else Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	var moved: Array[String] = []
	# 主档与备份都归档；`.tmp` 不碰 —— 那是没写完的中间产物，没有保留价值，
	# 下一次 write 会直接截断它。
	for suffix in ["", ".bak"]:
		var from: String = path + String(suffix)
		if not FileAccess.file_exists(from):
			continue
		var to := "%s_pre_reset-%s%s%s" % [base, mark, tail, suffix]
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) != OK:
			# 中途失败要如实报错，并把已经挪走的那份放回去 —— 只归档一半的槽位
			# 比不归档更糟：主档没了、备份还在，下次启动会「莫名回退」。
			for done in moved:
				var undo := String(done).replace("_pre_reset-" + mark, "")
				DirAccess.rename_absolute(ProjectSettings.globalize_path(done), ProjectSettings.globalize_path(undo))
			return {"ok":false,"reason":"旧存档无法归档，重置已取消","files":[]}
		moved.append(to)
	return {"ok":true,"reason":"","files":moved,"mark":mark}


static func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var temp := path+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.get_file_as_string(temp)!=text or not _read_one(temp).ok: return false
	if _read_one(path).get("ok",false):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak.tmp"))!=OK: return false
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".bak.tmp"),ProjectSettings.globalize_path(path+".bak"))!=OK: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))==OK
