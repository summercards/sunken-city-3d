extends RefCounted
## 由 save-reset runner 在隔离 user:// 中执行，覆盖审计反例，不接触玩家档。
const Save = preload("res://src/save/save_game.gd")
const Schema = preload("res://src/save/save_schema.gd")

static func put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

static func run(host: Node, check: Callable) -> void:
	var good := Save.encode(host)
	var live: Dictionary = host.save_registry.capture()
	for version in [2, 3, 4]:
		var absent := Save.decode(JSON.stringify({"version":version}))
		check.call(not absent.ok and absent.reason != "", "缺 economy 返回结构化拒绝 v%d" % version)
		for value in [null, [], 3, "x", true]:
			var bad := Save.decode(JSON.stringify({"version":version,"economy":value}))
			check.call(not bad.ok and bad.reason != "" and not bad.get("future",false), "畸形 economy 拒绝且非 future v%d %s" % [version,str(value)])
			var path := "user://b1-malformed-%d-%s.json" % [version,typeof(value)]
			put(path, JSON.stringify({"version":version,"economy":value}))
			put(path+".bak", JSON.stringify(good))
			var recovered := Save.read(path, host.save_registry)
			check.call(recovered.ok and recovered.get("recovered",false), "畸形主档可回退有效 bak")
	# 遍历所有已声明版本上限，避免只修 NPC / 天气。
	var paths := [["version"],["profile","version"],["building","version"],["room","version"],["npc","version"],["weather","version"],
		["economy","farm","version"],["economy","daily_loop","version"],["economy","energy","version"],["economy","fishery","version"],["economy","sunroom","version"],["pickups","ocean","version"]]
	for keys in paths:
		var future := good.duplicate(true)
		var record: Dictionary = future
		for i in keys.size()-1:
			if not record.has(keys[i]): record[keys[i]] = {}
			record = record[keys[i]]
		record[keys[-1]] = 99
		var text := JSON.stringify(future)
		check.call(Save.decode(text).get("future",false) and Save.restore(host,future).get("future",false), "未来版本传播 %s" % str(keys))
		for suffix in ["", ".bak"]:
			var path := "user://b1-future-%s-%s.json" % [str(keys).sha256_text().left(8), "main" if suffix == "" else "bak"]
			put(path, JSON.stringify(good))
			put(path+".bak", JSON.stringify(good))
			put(path+suffix, text)
			var before := [FileAccess.get_sha256(path),FileAccess.get_sha256(path+".bak")]
			check.call(Save.read(path).get("future",false) and Save.read_recoverable(path,host.save_registry).get("future",false), "读取保护未来主档或 bak")
			check.call(Save.write(path,host).get("future",false) and before == [FileAccess.get_sha256(path),FileAccess.get_sha256(path+".bak")], "写入不覆盖未来主档或 bak")
		var backup_only := "user://b1-only-%s.json" % str(keys).sha256_text().left(8)
		put(backup_only+".bak",text)
		check.call(Save.read(backup_only).get("future",false) and Save.write(backup_only,host).get("future",false) and not FileAccess.file_exists(backup_only) and FileAccess.get_sha256(backup_only+".bak") == text.sha256_text(), "仅未来 bak 时不创建降级主档")
	for module in ["weather", "npc"]:
		for value in [null, true, "2", [], {}, 1.5, -1, 99.5]:
			var bad := good.duplicate(true)
			bad[module].version = value
			var result := Save.decode(JSON.stringify(bad))
			check.call(not result.ok and not result.get("future",false) and not Save.restore(host,bad).ok, "坏模块版本非 future %s %s" % [module,str(value)])
	for version in [0, 1, 2, 3, 4]:
		var old := good.duplicate(true)
		old.version = version
		if version == 0:
			old = good.economy.duplicate(true)
			old.version = 0
		check.call(Save.decode(JSON.stringify(old)).ok, "保留根旧档迁移 v%d" % version)
		if version < 2:
			var farm: Dictionary = old.farm if version == 0 else old.economy.farm
			farm.day = 7
			farm.erase("grow_day")
			var migrated := Save.decode(JSON.stringify(old))
			check.call(migrated.ok and migrated.snapshot.time.day == 7, "旧农田历史日次保留 v%d" % version)
	for version in [1, 2]:
		var weather := good.duplicate(true)
		weather.weather.version = version
		check.call(Save.decode(JSON.stringify(weather)).ok, "支持天气旧版本 %d" % version)
	var old_weather := good.duplicate(true)
	old_weather.weather.erase("version")
	check.call(Save.decode(JSON.stringify(old_weather)).ok, "支持无版本旧天气")
	for seconds in [21600.0, 25200.0]:
		for day in [1, 4, 5, 6, 1000000000]:
			for key in ["day", "grow_day"]:
				var candidate := good.duplicate(true)
				candidate.time = {"day":5,"seconds":seconds,"day_length":1200.0}
				candidate.economy.farm[key] = day
				check.call(Save.decode(JSON.stringify(candidate)).ok == (day <= 5), "06/07 时农田水位线 %s=%d" % [key,day])
	var old_farm := good.duplicate(true)
	old_farm.economy.farm.erase("grow_day")
	check.call(Save.decode(JSON.stringify(old_farm)).ok, "旧农田缺 grow_day 兼容")
	var future_date := good.duplicate(true)
	var npc_id: String = future_date.npc.graph.met.keys()[0]
	future_date.npc.graph.met[npc_id] = true
	future_date.npc.graph.last_talk_day[npc_id] = int(good.time.day)+1
	check.call(not Save.decode(JSON.stringify(future_date)).ok and not Save.restore(host,future_date).ok, "NPC 未来日期拒绝")
	var without_room := good.duplicate(true)
	without_room.erase("room")
	var decoded := Save.decode(JSON.stringify(without_room))
	var direct := Save.restore(host,without_room)
	var direct_room: Dictionary = host.save_registry.capture().room
	var from_decode := Save.restore(host,decoded.snapshot)
	check.call(decoded.ok and direct.ok and from_decode.ok and direct_room == host.save_registry.capture().room, "直接恢复和 decode 缺 room 迁移一致")
	check.call(Save.restore(host,good).ok, "恢复反例前完整基线")
	live = host.save_registry.capture()
	var bad_room := good.duplicate(true)
	bad_room.room = {}
	check.call(not Save.decode(JSON.stringify(bad_room)).ok and not Save.restore(host,bad_room).ok, "已有坏 room 不迁移")
	# Schema 接受、完整 registry 拒绝的候选；验证与择优不得执行 apply。
	var bad := good.duplicate(true)
	bad.room.bed.position = [999.0,0.0,999.0]
	var semantic_path := "user://b1-semantic.json"
	put(semantic_path,JSON.stringify(bad))
	put(semantic_path+".bak",JSON.stringify(good))
	var before_main := FileAccess.get_sha256(semantic_path)
	var before_bak := FileAccess.get_sha256(semantic_path+".bak")
	check.call(Schema.validate(bad) == "" and host.save_registry.validate(bad) != "", "语义坏档反例确实越过 wire 而被 registry 拒绝")
	check.call(Save.read(semantic_path).ok and not Save.validate_read_result(Save.read(semantic_path),host.save_registry).ok, "旧接口可由完整 registry 重新判定")
	var selected := Save.read_recoverable(semantic_path,host.save_registry)
	check.call(selected.ok and selected.get("recovered",false) and selected.get("semantic_validated",false), "完整语义校验后选择有效 bak")
	check.call(before_main == FileAccess.get_sha256(semantic_path) and before_bak == FileAccess.get_sha256(semantic_path+".bak") and live == host.save_registry.capture(), "择优不修改源文件及 owner")
	check.call(Save.write(semantic_path,host).ok and before_bak == FileAccess.get_sha256(semantic_path+".bak"), "不可恢复主档不污染有效 bak")
	put(semantic_path,JSON.stringify(bad))
	put(semantic_path+".bak",JSON.stringify(bad))
	check.call(not Save.read_recoverable(semantic_path,host.save_registry).ok and not Save.write(semantic_path,host).ok, "主备均语义坏时安全拒绝")
	var archive_path := "user://b1-archive.json"
	put(archive_path,JSON.stringify(good))
	put(archive_path+".bak",JSON.stringify(good))
	var first := Save.archive(archive_path,"FIXED")
	var hashes := [FileAccess.get_sha256(first.files[0]),FileAccess.get_sha256(first.files[1])]
	var newer := good.duplicate(true)
	newer.economy.inventory.counts.coins = 222
	put(archive_path,JSON.stringify(newer))
	put(archive_path+".bak",JSON.stringify(newer))
	var second := Save.archive(archive_path,"FIXED")
	check.call(first.ok and second.ok and first.mark != second.mark and first.files != second.files, "固定 stamp 分配唯一归档名")
	check.call(hashes == [FileAccess.get_sha256(first.files[0]),FileAccess.get_sha256(first.files[1])], "首次主备归档字节不变")
	check.call(Save.read(first.files[0]).ok and Save.read(second.files[0]).snapshot.economy.inventory.counts.coins == 222 and not FileAccess.file_exists(archive_path) and not FileAccess.file_exists(archive_path+".bak"), "主备归档完整且旧进度可读")
	put(archive_path.get_basename()+"_pre_reset-BAK_ONLY.json.bak","占用标记")
	put(archive_path,JSON.stringify(good))
	check.call(Save.archive(archive_path,"BAK_ONLY").mark != "BAK_ONLY", "仅备份目标存在也不覆盖")
	check.call(not Save.archive(archive_path,"../bad").ok, "非法 stamp 安全拒绝")
	check.call(live == host.save_registry.capture(), "B1 拒绝与校验不改变完整 owner 状态")
