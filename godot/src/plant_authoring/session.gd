@tool
extends RefCounted
class_name PlantAuthoringSession
## 独立植物配方的唯一状态所有者。

signal changed

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")

var _recipe: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _saved_fingerprint := ""

func _init(species: String = "camphor") -> void:
	var selected := species if Recipe.SPECIES.has(species) else "camphor"
	_recipe = _deep_copy(Recipe.defaults(selected))

func snapshot() -> Dictionary:
	return _deep_copy(_recipe)

func apply_patch(patch: Dictionary) -> Dictionary:
	if patch.is_empty():
		return {"ok": false, "reason": "空修改"}
	var candidate := snapshot()
	for key in patch.keys():
		var field := str(key)
		if not candidate.has(field):
			return {"ok": false, "reason": "未知配方字段：%s" % field}
		candidate[field] = _deep_copy(patch[key])
	return _commit_candidate(candidate)

func load_recipe(data: Dictionary) -> Dictionary:
	var candidate := _deep_copy(data)
	var reason := _probe(candidate)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	_recipe = candidate
	_undo.clear()
	_redo.clear()
	_saved_fingerprint = _fingerprint(_recipe)
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func new_document(species: String = "camphor") -> Dictionary:
	var candidate_species := species if Recipe.SPECIES.has(species) else ""
	if candidate_species.is_empty():
		return {"ok": false, "reason": "未知植物种类：%s" % species}
	var candidate := _deep_copy(Recipe.defaults(candidate_species))
	var reason := _probe(candidate)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	_recipe = candidate
	_undo.clear()
	_redo.clear()
	_saved_fingerprint = ""
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.push_back(snapshot())
	_recipe = _deep_copy(_undo.pop_back())
	changed.emit()
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.push_back(snapshot())
	_recipe = _deep_copy(_redo.pop_back())
	changed.emit()
	return true

func is_dirty() -> bool:
	return _fingerprint(_recipe) != _saved_fingerprint

func mark_saved() -> void:
	_saved_fingerprint = _fingerprint(_recipe)

func _commit_candidate(candidate: Dictionary) -> Dictionary:
	var reason := _probe(candidate)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	if _fingerprint(candidate) == _fingerprint(_recipe):
		return {"ok": true, "reason": "未发生变化", "recipe": snapshot()}
	_undo.push_back(snapshot())
	_redo.clear()
	_recipe = _deep_copy(candidate)
	changed.emit()
	return {"ok": true, "reason": "", "recipe": snapshot()}

func _probe(candidate: Dictionary) -> String:
	var reason := Recipe.validate(candidate)
	if not reason.is_empty():
		return reason
	var build: Dictionary = Generator.build(candidate)
	var root := build.get("root") as Node
	if root != null:
		root.free()
	if not bool(build.get("ok", false)):
		return str(build.get("reason", "植物生成失败"))
	return ""

func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(value)

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
