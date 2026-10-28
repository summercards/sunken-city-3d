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
	return ""

func restore(data: Dictionary) -> Dictionary:
	if is_busy(): return {"ok":false,"reason":"正在恢复或结算"}
	var error := validate(data)
	if error != "": return {"ok":false,"reason":error}
	_restoring = true
	# Suppress intermediate owner signals: listeners see the completed snapshot via restored.
	var blocked := {}
	for entry in _entries.values():
		for source_ref in entry.event_sources:
			var source = source_ref.get_ref()
			if source == null or blocked.has(source.get_instance_id()): continue
			blocked[source.get_instance_id()]={"source":source_ref,"previous":source.is_blocking_signals()}
			source.set_block_signals(true)
	# Apply functions are total on their validated domain; no IO or resource purchases.
	for id in _entries: _entries[id].apply.call(data[id].duplicate(true))
	for item in blocked.values():
		var source = item.source.get_ref()
		if source != null: source.set_block_signals(item.previous)
	_restoring = false
	restored.emit()
	return {"ok":true,"reason":""}

func clear() -> void:
	busy_query = Callable()
	_entries.clear()
