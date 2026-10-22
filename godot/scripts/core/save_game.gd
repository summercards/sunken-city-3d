extends RefCounted
class_name SaveGame
## 存档与读档：把散落在经济 / 种植 / 采集 / 世界状态里的字段收成一份带版本号的 JSON。
##
## 设计要点：
##   - **只存相对时间**。引擎的 `Time.get_ticks_msec()` 每次启动都从 0 开始，
##     直接把绝对时间存进文件，重启后冷却会变成几十年（或者立刻失效）。
##     所以打捞冷却与采集冷却一律存「还剩多少秒」。
##   - **读档容错**。物品表 / 建造表 / 菜箱表改过之后，旧存档里的未知 id 直接跳过，
##     不让一次数据调整把玩家的档读废。
##   - **原子写入**。先写 `.tmp`、读回比对、再 rename 顶替，避免写一半断电留下半截 JSON。
##   - **版本化**。v0 = 早期没有 envelope 的扁平格式（只有 inventory/site_levels…），
##     读到就往上迁移；比本作新的版本拒绝读取，而不是猜。

const VERSION := 1
const SLOT_PATH := "user://save_slot_0.json"

## 世界状态里需要存进档的 GameState 字段。
const GAME_KEYS := ["zone", "landing", "mode", "far_sea"]


static func now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


## 把当前游戏状态收成一份可写盘的字典（不含绝对时间）。
static func encode(main: Node) -> Dictionary:
	var now := now_seconds()
	var economy_data: Dictionary = Economy.to_dict()
	# 绝对值不入档：跨进程没有意义，改成 salvage_left。
	economy_data.erase("salvage_ready_at")

	var gather_left := {}
	var field: Node = main.get("gather")
	if field != null:
		for spot in field.spots:
			var left: float = spot.seconds_left()
			if left > 0.01:
				gather_left[str(spot.id)] = left

	var game := {
		"zone": GameState.current_zone,
		"landing": GameState.landing_id,
		"mode": GameState.mode,
		"far_sea": GameState.far_sea_unlocked,
		"boat": _vec4(main.boat),
		"player": _vec3(main.player) if GameState.mode == GameState.Mode.ASHORE else [],
	}
	var dive_state := {}
	var dive_node: Node = main.get("dive")
	if dive_node != null and dive_node.has_method("to_dict"):
		dive_state = dive_node.to_dict()

	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"wall_time": int(Time.get_unix_time_from_system()),
		"game": game,
		"economy": economy_data,
		"salvage_left": Economy.salvage_cooldown_left(now),
		"gather": gather_left,
		"dive": dive_state,
	}


## 写档。返回 {ok, reason, path, bytes, snapshot}。
static func write(path: String, main: Node) -> Dictionary:
	var snap := encode(main)
	var text := JSON.stringify(snap, "\t")
	if not _write_text(path, text):
		return {"ok": false, "reason": "写入失败：%s" % path, "path": path}
	return {
		"ok": true, "reason": "", "path": path,
		"bytes": text.to_utf8_buffer().size(), "snapshot": snap,
	}


## 读档（只解码，不改游戏状态）。返回 {ok, reason, snapshot, version, migrated}。
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "还没有存档"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "存档打不开"}
	var text := f.get_as_text()
	f.close()
	return decode(text)


## 纯文本解码，便于 headless 断言（不依赖文件系统）。
static func decode(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "存档不是有效 JSON"}
	var doc: Dictionary = parsed
	var version := int(doc.get("version", 0))
	if version > VERSION:
		return {"ok": false, "reason": "存档版本 %d 比本作 %d 新" % [version, VERSION]}
	var migrated := false
	if version < 1:
		doc = _migrate_v0(doc)
		version = VERSION
		migrated = true
	doc["version"] = version

	if not (doc.get("economy") is Dictionary):
		return {"ok": false, "reason": "存档缺少经济数据"}
	if not (doc.get("game") is Dictionary):
		doc["game"] = {}
	if not (doc.get("gather") is Dictionary):
		doc["gather"] = {}
	if not doc.has("salvage_left"):
		doc["salvage_left"] = 0.0
	if not (doc.get("dive") is Dictionary):
		doc["dive"] = {}
	return {"ok": true, "reason": "", "snapshot": doc, "version": version, "migrated": migrated}


## 读档并应用。顺序很重要：先经济（背包/种植/建造），再采集冷却，最后世界与镜头。
static func restore(main: Node, snap: Dictionary) -> Dictionary:
	var now := now_seconds()
	var econ: Dictionary = snap.get("economy", {})
	Economy.from_dict(econ)
	# 冷却用「还剩多少秒」复原，跨进程也不会错。
	Economy.salvage_ready_at = now + maxf(float(snap.get("salvage_left", 0.0)), 0.0)

	var field: Node = main.get("gather")
	if field != null:
		for spot in field.spots:
			spot.restore_cooldown(0.0)
		var saved: Dictionary = snap.get("gather", {})
		for id in saved.keys():
			var spot: Node3D = field.find(str(id))
			if spot != null:
				spot.restore_cooldown(maxf(float(saved[id]), 0.0))

	# 海底进度（发现 / 打开过哪些宝箱）。氧气不在档里：读档一律回到船上。
	var dive_node: Node = main.get("dive")
	if dive_node != null and dive_node.has_method("from_dict"):
		dive_node.from_dict(snap.get("dive", {}))

	var game: Dictionary = snap.get("game", {})
	var zone_id := str(game.get("zone", GameState.current_zone))

	GameState.far_sea_unlocked = bool(game.get("far_sea", GameState.far_sea_unlocked))
	GameState.landing_id = str(game.get("landing", GameState.landing_id))

	var boat: Node3D = main.get("boat")
	var boat_state: Array = game.get("boat", [])
	if boat != null and boat_state.size() == 4:
		boat.place_at(
			Vector3(float(boat_state[0]), float(boat_state[1]), float(boat_state[2])),
			float(boat_state[3]))
	_restore_actor(main, game, boat)

	if GameState.current_zone != zone_id:
		GameState.enter_zone(zone_id)
	else:
		GameState.zone_changed.emit(zone_id)

	main._sync_zone_levels()
	var cam: Node = main.get("cam")
	if cam != null:
		cam.resume_follow()
		cam.target = main.player.global_position + Vector3.UP*0.7
		cam._apply()
	var markers: Node = main.get("markers")
	if markers != null:
		markers.set_highlight(zone_id)
	var hud: Node = main.get("hud")
	if hud != null:
		hud._refresh()
		if hud._panel_open:
			hud._refresh_panel()
	return {"ok": true, "reason": ""}


## 把小人放回存档里的位置（岸上）或甲板上（船上 / 潜水前）。
static func _restore_actor(main: Node, game: Dictionary, boat: Node3D) -> void:
	var player: Node3D = main.get("player")
	if player == null:
		return
	main._walk_path.clear()
	main._after_walk = Callable()
	var pos: Array = game.get("player", [])
	var ashore := int(game.get("mode", GameState.Mode.ON_BOAT)) == GameState.Mode.ASHORE
	if ashore and pos.size() == 3:
		player.reparent(main, true)
		player.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		player.set_walking(false)
		player.set_rowing(false)
		main._walking = false
		GameState.set_mode(GameState.Mode.ASHORE)
		return
	if boat != null and player.get_parent() != boat:
		player.reparent(boat, true)
	player.position = Vector3(0, 0.62, -0.30)
	player.rotation = Vector3.ZERO
	player.set_walking(false)
	player.set_rowing(true)
	main._walking = false
	# 存档时正在潜水：回到水面，不把玩家留在海底（氧气与相机状态不在档里）。
	GameState.set_mode(GameState.Mode.ON_BOAT)


## v0：早期原型直接存 `{"inventory":…, "site_levels":…}`，没有 envelope。
static func _migrate_v0(doc: Dictionary) -> Dictionary:
	var econ := {}
	for key in ["inventory", "ship_level", "site_levels", "facilities", "site_work", "farm"]:
		if doc.has(key):
			econ[key] = doc[key]
	return {
		"version": VERSION,
		"migrated_from": 0,
		"saved_at": str(doc.get("saved_at", "")),
		"game": doc.get("game", {}),
		"economy": econ,
		"salvage_left": float(doc.get("salvage_left", 0.0)),
		"gather": doc.get("gather", {}),
		"dive": {},
	}


static func _write_text(path: String, text: String) -> bool:
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# 读回比对，确认没有写半截，再原子顶替。
	var check := FileAccess.open(tmp, FileAccess.READ)
	if check == null:
		return false
	var back := check.get_as_text()
	check.close()
	if back != text or back.to_utf8_buffer().size() < 16:
		return false
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path)) == OK


static func _vec3(n: Node3D) -> Array:
	if n == null:
		return []
	return [n.position.x, n.position.y, n.position.z]


static func _vec4(n: Node3D) -> Array:
	if n == null:
		return []
	return [n.position.x, n.position.y, n.position.z, n.rotation.y]
