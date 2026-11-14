extends RefCounted
## 重置专用文件端口；测试通过子类覆写 I/O，不向生产宿主暴露故障回调。
## intent 未提交则回滚，已提交则收尾；仅支持单进程单写者、同文件系统 rename。
## flush/读回不等于目录 fsync，不能据此保证真实断电或设备故障的持久性。
const INTENT := ".reset-intent"
const STAGE := ".reset-stage"

func pending(path: String) -> bool:
	return FileAccess.file_exists(path + INTENT)

func run(path: String, host: Node, codec, stamp := "") -> Dictionary:
	var recovered := recover(path)
	if not recovered.ok: return recovered
	var runtime: Dictionary = host.save_registry.capture_runtime()
	var before: Dictionary = codec.encode(host)
	var fresh: Dictionary = host.save_registry.defaults()
	fresh.version = codec.VERSION
	fresh.saved_at = Time.get_datetime_string_from_system()
	fresh.wall_time = int(Time.get_unix_time_from_system())
	for snapshot in [before, fresh]:
		var validation: Dictionary = codec.Schema.validate_result(snapshot)
		if not validation.ok: return _failure(validation.reason)
		var error: String = host.save_registry.validate(snapshot)
		if error != "": return _failure(error)
	var prepared := _stage(path, fresh, host.save_registry, codec)
	if not prepared.ok: return prepared
	var mark := stamp if stamp != "" else Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	if not _valid_mark(mark): return _failure("归档标记格式错误")
	var base_mark := mark
	var index := 0
	while codec._archive_target_exists(path.get_basename(), mark, _tail(path)):
		index += 1
		mark = base_mark + "-" + str(index)
	var journal := {"version":1, "mark":mark, "committed":false, "fresh_hash":prepared.hash, "originals":[]}
	for suffix in ["", ".bak"]:
		var source: String = path + suffix
		if FileAccess.file_exists(source):
			var original_hash := _hash(source)
			if original_hash.length() != 64: return _failure("原存档无法校验，重置已取消")
			journal.originals.append({"suffix":suffix, "hash":original_hash})
	if not _journal(path, journal): return _failure("重置意图写入失败，原槽未改动")
	var archived: Array = []
	for original in journal.originals:
		var target := _archive_path(path, mark, original.suffix)
		if not copy_verified(path + original.suffix, target, original.hash):
			return _abort(path, host, before, runtime, false, "旧存档归档失败", archived)
		archived.append(target)
	# 原槽此时仍完整；apply 失败既不丢槽，也不依赖归档反推内存。
	var applied: Dictionary = host.save_registry.restore(fresh)
	# registry 已负责失败回滚；不能再 restore 一次并发布伪成功事件。
	if not applied.ok:
		var aborted := _abort(path, host, before, runtime, false, applied.reason, archived)
		aborted.rollback_ok = aborted.rollback_ok and applied.get("rollback_ok", true)
		return aborted
	# restored 的正式投影可能规范化种群等状态，落盘使用实际完成态。
	fresh = codec.encode(host)
	prepared = _stage(path, fresh, host.save_registry, codec)
	if not prepared.ok: return _abort(path, host, before, runtime, true, prepared.reason, archived)
	journal.fresh_hash = prepared.hash
	if not _journal(path, journal): return _abort(path, host, before, runtime, true, "重置意图更新失败", archived)
	if rename_file(path + STAGE, path) != OK:
		return _abort(path, host, before, runtime, true, "新档最后替换失败", archived)
	if remove_file(path + ".bak") != OK:
		return _abort(path, host, before, runtime, true, "旧备份退出槽位失败", archived)
	journal.committed = true
	if not _journal(path, journal): return _abort(path, host, before, runtime, true, "重置提交标记写入失败", archived)
	var cleanup := recover(path)
	return {"ok":true, "reason":"" if cleanup.ok else "重置已提交，待启动清理意图", "archived":archived, "mark":mark, "snapshot":fresh, "cleanup_pending":not cleanup.ok}

func _abort(path: String, host: Node, before: Dictionary, runtime: Dictionary, applied: bool, reason: String, archived: Array) -> Dictionary:
	var disk := recover(path)
	var memory := {"ok":true}
	if applied:
		memory = host.save_registry.restore(before)
		if memory.ok: host.save_registry.restore_runtime(runtime)
	var result := _failure(reason)
	result.archived = archived
	result.rollback_ok = disk.ok and memory.ok
	result.recovery_required = not disk.ok
	if not disk.ok: result.reason += "；磁盘回滚待恢复：" + str(disk.reason)
	if not memory.ok: result.reason += "；内存回滚失败：" + str(memory.get("reason", ""))
	return result

func recover(path: String) -> Dictionary:
	if not pending(path): return {"ok":true, "reason":"", "archived":[]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path + INTENT)) != OK or not _valid_journal(parser.data):
		return _failure("重置意图损坏，已保护槽位，请保留所有重置文件")
	var journal: Dictionary = parser.data
	if journal.committed:
		if _hash(path) != journal.fresh_hash:
			return _failure("已提交重置的新档不匹配，已保护槽位")
		for original in journal.originals:
			if _hash(_archive_path(path, journal.mark, original.suffix)) != original.hash:
				return _failure("已提交重置的归档不匹配，已保护槽位")
		if remove_file(path + ".bak") != OK: return _failure("重置备份清理失败")
	else:
		# 先验证全部恢复来源，再动任一槽位；未来档只比字节，不 decode/降存。
		var sources := {}
		for original in journal.originals:
			var source: String = path + original.suffix
			if _hash(source) != original.hash:
				source = _archive_path(path, journal.mark, original.suffix)
			if _hash(source) != original.hash:
				return _failure("重置回滚缺少原始字节，已保护槽位与归档")
			sources[original.suffix] = source
		for original in journal.originals:
			var target: String = path + original.suffix
			if sources[original.suffix] == target: continue
			if not copy_verified(sources[original.suffix], target + ".reset-rollback", original.hash):
				return _failure("重置回滚准备失败，意图与归档已保留")
			if rename_file(target + ".reset-rollback", target) != OK:
				return _failure("重置回滚替换失败，意图与归档已保留")
		for suffix in ["", ".bak"]:
			if not sources.has(suffix) and remove_file(path + suffix) != OK:
				return _failure("重置空槽回滚失败")
	for suffix in [STAGE, INTENT + ".tmp"]:
		if remove_file(path + suffix) != OK: return _failure("重置临时文件清理失败")
	if remove_file(path + INTENT) != OK: return _failure("重置意图清理失败")
	return {"ok":true, "reason":"", "archived":[], "reset_recovered":true, "reset_committed":journal.committed}

func _stage(path: String, snapshot: Dictionary, registry, codec) -> Dictionary:
	var validation: Dictionary = codec.Schema.validate_result(snapshot)
	if not validation.ok: return _failure(validation.reason)
	var error: String = registry.validate(snapshot)
	if error != "": return _failure(error)
	var text := JSON.stringify(snapshot, "\t")
	if text.to_utf8_buffer().size() > codec.MAX_BYTES: return _failure("重置新档过大")
	if not write_verified(path + STAGE, text): return _failure("重置新档准备写入失败")
	var reread: Dictionary = codec.validate_read_result(codec._read_one(path + STAGE), registry)
	if not reread.ok: return _failure("重置新档读回校验失败：" + str(reread.reason))
	return {"ok":true, "hash":_hash(path + STAGE)}

func _journal(path: String, data: Dictionary) -> bool:
	return write_verified(path + INTENT + ".tmp", JSON.stringify(data)) and rename_file(path + INTENT + ".tmp", path + INTENT) == OK

func write_verified(path: String, text: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK: return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var code := file.get_error()
	file.close()
	return code == OK and FileAccess.get_file_as_string(path) == text

func copy_verified(source: String, target: String, expected: String) -> bool:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) == OK and _hash(target) == expected

func rename_file(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))

func remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path): return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _tail(path: String) -> String:
	return "." + path.get_extension() if path.get_extension() != "" else ""

func _archive_path(path: String, mark: String, suffix: String) -> String:
	return path.get_basename() + "_pre_reset-" + mark + _tail(path) + suffix

func _valid_mark(mark: String) -> bool:
	return mark != "" and not mark.contains("/") and not mark.contains("\\") and not mark in [".", ".."]

func _valid_journal(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("version") != 1 or not value.get("committed") is bool: return false
	if not value.get("mark") is String or not _valid_mark(value.mark): return false
	if not value.get("fresh_hash") is String or value.fresh_hash.length() != 64: return false
	if not value.get("originals") is Array or value.originals.size() > 2: return false
	var seen := {}
	for item in value.originals:
		if not item is Dictionary: return false
		if not item.get("suffix") is String or not item.suffix in ["", ".bak"] or seen.has(item.suffix): return false
		if not item.get("hash") is String or item.hash.length() != 64: return false
		seen[item.suffix] = true
	return true

func _failure(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason, "archived":[]}
