extends RefCounted
## Composition registers feature-owned serializers. Validate ALL before changing ANY.
signal restored
const Contract = preload("res://src/core/record_contract.gd")
var _entries: Dictionary = {}
var _restoring := false

func register(id: String, capture: Callable, apply: Callable, schema: Dictionary, defaults: Dictionary, validator := Callable(), event_sources: Array = []) -> void:
	assert(not _entries.has(id), "Duplicate snapshot owner: " + id)
	assert(capture.is_valid() and apply.is_valid())
	var sources: Array=[]
	for source in event_sources:
		assert(is_instance_valid(source))
		sources.append(weakref(source))
	_entries[id] = {"capture":capture, "apply":apply, "schema":schema.duplicate(true), "defaults":defaults.duplicate(true), "validator":validator,"event_sources":sources}

var snapshot_validator: Callable
var busy_query: Callable
func is_busy() -> bool: return _restoring or (busy_query.is_valid() and busy_query.call())
func is_restoring() -> bool: return _restoring

func capture() -> Dictionary:
	if is_busy(): return {}
	var data := {}
	for id in _entries: data[id] = _entries[id].capture.call().duplicate(true)
	return data

func defaults() -> Dictionary:
	var result := {}
	for id in _entries: result[id] = _entries[id].defaults.duplicate(true)
	return result

func validate(data: Dictionary) -> String:
	for id in _entries:
		if not data.has(id): return "存档缺少模块 " + id
		var error := Contract.check(data[id], _entries[id].schema, id)
		if error != "": return error
		if _entries[id].validator.is_valid():
			error = _entries[id].validator.call(data[id])
			if error != "": return error
	if snapshot_validator.is_valid(): return snapshot_validator.call(data)
	return ""

## 可选 owner 协议只捕获进程内瞬态，不混入 capture()/defaults() 的持久字段。
## 不涵盖 restored 消费者的 UI/路线投影；外层磁盘事务失败不重开已关闭的面板。
func capture_runtime() -> Dictionary:
	var runtime := {}
	for id in _entries:
		var owner: Object = _entries[id].apply.get_object()
		if owner != null and owner.has_method("capture_runtime") and owner.has_method("restore_runtime"):
			runtime[id] = owner.capture_runtime()
	return runtime

func restore_runtime(runtime: Dictionary) -> void:
	for id in runtime:
		var owner: Object = _entries[id].apply.get_object()
		if owner != null: owner.restore_runtime(runtime[id])

func restore(data: Dictionary) -> Dictionary:
	if is_busy(): return {"ok":false,"reason":"正在恢复或结算"}
	var error := validate(data)
	if error != "": return {"ok":false,"reason":error}
	var runtime := capture_runtime()
	var before := {}
	for id in _entries:
		before[id] = _entries[id].capture.call().duplicate(true)
	_restoring = true
	# Suppress intermediate owner signals; listeners see only a complete snapshot or no restore.
	var blocked := {}
	for entry in _entries.values():
		for source_ref in entry.event_sources:
			var source = source_ref.get_ref()
			if source == null or blocked.has(source.get_instance_id()): continue
			blocked[source.get_instance_id()]={"source":source_ref,"previous":source.is_blocking_signals()}
			source.set_block_signals(true)
	var failure := ""
	for id in _entries:
		var result: Variant = _entries[id].apply.call(data[id].duplicate(true))
		if result is bool and not result:
			failure = "恢复模块失败：" + id
			break
		if result is Dictionary and result.get("ok") is bool and not result.ok:
			failure = str(result.get("reason", "恢复模块失败：" + id))
			break
	if failure != "":
		var rollback_failure := ""
		for id in _entries:
			var rollback: Variant = _entries[id].apply.call(before[id].duplicate(true))
			if rollback is bool and not rollback:
				rollback_failure = "恢复失败且回滚模块失败：" + id
			elif rollback is Dictionary and rollback.get("ok") is bool and not rollback.ok:
				rollback_failure = "恢复失败且回滚模块失败：" + id
		if rollback_failure == "": restore_runtime(runtime)
		for item in blocked.values():
			var source = item.source.get_ref()
			if source != null: source.set_block_signals(item.previous)
		_restoring = false
		return {"ok":false,"reason":rollback_failure if rollback_failure != "" else failure,"rollback_ok":rollback_failure == ""}
	for item in blocked.values():
		var source = item.source.get_ref()
		if source != null: source.set_block_signals(item.previous)
	_restoring = false
	restored.emit()
	return {"ok":true,"reason":""}

func clear() -> void:
	snapshot_validator = Callable()
	busy_query = Callable()
	_entries.clear()
