@tool
extends RefCounted
class_name WorkshopSession
## SEA-WORKSHOP 的唯一编辑草稿所有者。

signal changed

const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")

var catalog: Dictionary = {}
var _recipe: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _saved_fingerprint := ""
var _last_build: Dictionary = {}

func _init(catalog_snapshot: Dictionary = {}) -> void:
	catalog = _copy_dict(catalog_snapshot) if not catalog_snapshot.is_empty() else _copy_dict(Catalog.definitions())
	_recipe = Recipe.normalized(Recipe.defaults())
	_saved_fingerprint = ""

func snapshot() -> Dictionary:
	return _copy_dict(_recipe)

func apply_patch(patch: Dictionary) -> Dictionary:
	if patch.is_empty():
		return {"ok": false, "reason": "空修改"}
	for key in patch.keys():
		if not _recipe.has(str(key)):
			return {"ok": false, "reason": "未知配方字段：%s" % str(key)}
	var candidate: Dictionary = snapshot()
	for key in patch.keys():
		candidate[str(key)] = _deep_copy(patch[key])
	_coerce_integer_fields(candidate)
	return _commit_candidate(candidate)

func replace_recipe(data: Dictionary) -> Dictionary:
	var candidate: Dictionary = _deep_copy(data) as Dictionary
	_coerce_integer_fields(candidate)
	var reason: String = Recipe.validate(candidate, catalog)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	return _commit_candidate(Recipe.normalized(candidate))

## 打开一个带 catalog 快照的已导出文档；成功后作为已保存状态载入。
func accept_loaded(data: Dictionary, catalog_snapshot: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _deep_copy(data) as Dictionary
	var next_catalog: Dictionary = _copy_dict(catalog_snapshot) if not catalog_snapshot.is_empty() else _copy_dict(catalog)
	var catalog_reason: String = Catalog.validate(next_catalog)
	if not catalog_reason.is_empty():
		return {"ok": false, "reason": catalog_reason}
	_coerce_integer_fields(candidate)
	var reason: String = Recipe.validate(candidate, next_catalog)
	if reason.is_empty():
		reason = _validate_shell_geometry(candidate, next_catalog)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	catalog = next_catalog
	_recipe = Recipe.normalized(candidate)
	_undo.clear()
	_redo.clear()
	_last_build.clear()
	_saved_fingerprint = _fingerprint(_recipe)
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func new_document(building_id: String = "", initial_recipe: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = Recipe.normalized(initial_recipe if not initial_recipe.is_empty() else Recipe.defaults())
	if building_id.is_empty():
		candidate["building_id"] = str(_recipe.get("building_id", candidate.get("building_id", "workshop_001")))
		candidate["revision"] = int(_recipe.get("revision", candidate.get("revision", 1)))
	else:
		candidate["building_id"] = building_id
	_coerce_integer_fields(candidate)
	var reason: String = Recipe.validate(candidate, catalog)
	if reason.is_empty():
		reason = _validate_shell_geometry(candidate, catalog)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	_recipe = candidate
	_undo.clear()
	_redo.clear()
	_last_build.clear()
	_saved_fingerprint = ""
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.push_back(_history_state())
	_restore_history(_undo.pop_back())
	_last_build.clear()
	changed.emit()
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.push_back(_history_state())
	_restore_history(_redo.pop_back())
	_last_build.clear()
	changed.emit()
	return true

func set_slot_override(slot_id: String, patch: Dictionary) -> Dictionary:
	if slot_id.strip_edges().is_empty():
		return {"ok": false, "reason": "slot_id 不能为空"}
	if patch.is_empty():
		return {"ok": false, "reason": "空槽位修改"}
	var overrides: Dictionary = _copy_dict(_recipe.get("slot_overrides", {}))
	var current: Dictionary = _copy_dict(overrides.get(slot_id, {}))
	for key in patch.keys():
		if not Recipe.SLOT_FIELDS.has(str(key)):
			return {"ok": false, "reason": "未知槽位字段：%s" % str(key)}
		current[str(key)] = _deep_copy(patch[key])
	overrides[slot_id] = current
	return apply_patch({"slot_overrides": overrides})

func set_vegetation_lock(slot_id: String, position: Array, growth_key: String, locked: bool = true) -> Dictionary:
	var locks: Array = _copy_array(_recipe.get("locked_vegetation", []))
	var kept: Array = []
	for item in locks:
		if item is Dictionary and str(item.get("slot_id", "")) != slot_id:
			kept.append(_deep_copy(item))
	if locked:
		kept.append({"slot_id": slot_id, "position": _deep_copy(position), "growth_key": growth_key})
	return apply_patch({"locked_vegetation": kept})

func is_dirty() -> bool:
	return _fingerprint(_recipe) != _saved_fingerprint

func mark_saved() -> void:
	_saved_fingerprint = _fingerprint(_recipe)

func sync_exported_revision(revision: int) -> Dictionary:
	var result: Dictionary = apply_patch({"revision": revision})
	if bool(result.get("ok", false)):
		mark_saved()
	return result

func build() -> Dictionary:
	var result: Dictionary = Generator.build(snapshot(), _copy_dict(catalog))
	if result.get("ok", false):
		_last_build = result
	return result

func _commit_candidate(candidate: Dictionary) -> Dictionary:
	_coerce_integer_fields(candidate)
	var reason: String = Recipe.validate(candidate, catalog)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var normalized: Dictionary = Recipe.normalized(candidate)
	reason = _validate_shell_geometry(normalized, catalog)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	if _fingerprint(normalized) == _fingerprint(_recipe):
		return {"ok": true, "reason": "未发生变化", "recipe": snapshot()}
	_undo.push_back(_history_state())
	_redo.clear()
	_recipe = normalized
	_last_build.clear()
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func replace_catalog(next_catalog: Dictionary) -> Dictionary:
	return replace_document(snapshot(), next_catalog)

func replace_document(next_recipe: Dictionary, next_catalog: Dictionary) -> Dictionary:
	var reason: String = Catalog.validate(next_catalog)
	if reason.is_empty():
		reason = Recipe.validate(next_recipe, next_catalog)
	if reason.is_empty():
		reason = _validate_shell_geometry(next_recipe, next_catalog)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	_undo.push_back(_history_state())
	_redo.clear()
	_recipe = Recipe.normalized(next_recipe)
	catalog = _copy_dict(next_catalog)
	_last_build.clear()
	_saved_fingerprint = ""
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func _validate_shell_geometry(recipe: Dictionary, candidate_catalog: Dictionary) -> String:
	if str(recipe.get("construction_mode", "modular_v1")) != "shell_v2":
		return ""
	var probe: Dictionary = Generator.build(recipe, candidate_catalog)
	var root: Node = probe.get("root") as Node
	if root != null:
		root.free()
	return "" if bool(probe.get("ok", false)) else str(probe.get("reason", "连续实体几何无效"))

func _history_state() -> Dictionary:
	return {"recipe": snapshot(), "catalog": _copy_dict(catalog)}

func _restore_history(state: Dictionary) -> void:
	_recipe = _copy_dict(state.recipe)
	catalog = _copy_dict(state.catalog)

func _coerce_integer_fields(data: Dictionary) -> void:
	for key in ["schema_version", "revision", "floors", "bevel_segments", "structure_seed", "damage_seed", "vegetation_seed"]:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		if (value is int) or (value is float and is_finite(float(value)) and floor(float(value)) == float(value)):
			data[key] = int(value)

func _fingerprint(value: Dictionary) -> String:
	return str(Recipe.fingerprint(value))

func _copy_dict(value: Dictionary) -> Dictionary:
	return _deep_copy(value) as Dictionary

func _copy_array(value: Array) -> Array:
	return _deep_copy(value) as Array

func _deep_copy(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[key] = _deep_copy(value[key])
		return result
	if value is Array:
		var result_array: Array = []
		for item in value:
			result_array.append(_deep_copy(item))
		return result_array
	return value
