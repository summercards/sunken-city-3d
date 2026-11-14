@tool
extends RefCounted
class_name PlantAuthoringSession
## 唯一配方状态所有者；返回的预览 root 由调用者释放，查询在其存活时复用同一结果。

signal changed

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")

var _recipe: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _saved_fingerprint := ""
var _last_build: Dictionary = {}
var _merge_fingerprint := ""

func _init(species: String = "camphor") -> void:
	var selected := species if Recipe.SPECIES.has(species) else "camphor"
	_recipe = Recipe.normalized(Recipe.defaults(selected))

func snapshot() -> Dictionary:
	return _recipe.duplicate(true)

func fingerprint() -> String:
	return Recipe.fingerprint(_recipe)

func saved_fingerprint() -> String:
	return _saved_fingerprint

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func apply_patch(patch: Dictionary) -> Dictionary:
	if patch.is_empty():
		return _failure("空修改")
	var candidate := snapshot()
	for key in patch:
		if not (key is String) or not Recipe.KEYS.has(key):
			return _failure("未知配方字段：%s" % str(key))
		candidate[key] = patch[key]
	return preview_candidate(candidate)

func preview_candidate(candidate: Dictionary, merge_history: bool = false, expectedfp: String = "") -> Dictionary:
	var current := fingerprint()
	if not expectedfp.is_empty() and expectedfp != current:
		return _failure("候选已过期：配方指纹不匹配")
	if merge_history and (expectedfp.is_empty() or _merge_fingerprint != current or _undo.is_empty()):
		return _failure("合并历史必须承接上一次候选及其指纹")
	var next := Recipe.normalized(candidate)
	var reason := Recipe.validate(next)
	if not reason.is_empty():
		return _failure(reason)
	var nextfp := Recipe.fingerprint(next)
	if nextfp == current:
		return build()
	var generated := Generator.build(next)
	if not _successful(generated):
		return _reject_build(generated)
	if not merge_history:
		_undo.push_back(snapshot())
	_redo.clear()
	_recipe = next
	_last_build = generated
	_merge_fingerprint = nextfp
	changed.emit()
	return _result(generated)

func build() -> Dictionary:
	if not _successful(_last_build):
		var generated := Generator.build(snapshot())
		if not _successful(generated):
			return _reject_build(generated)
		_last_build = generated
	return _result(_last_build)

func load_recipe(data: Dictionary) -> Dictionary:
	return _replace_document(data, true)

func new_document(species: String = "camphor") -> Dictionary:
	if not Recipe.SPECIES.has(species):
		return _failure("未知植物种类：%s" % species)
	return _replace_document(Recipe.defaults(species), false)

func _replace_document(data: Dictionary, saved: bool) -> Dictionary:
	var next := Recipe.normalized(data)
	var reason := Recipe.validate(next)
	if not reason.is_empty():
		return _failure(reason)
	var generated := Generator.build(next)
	if not _successful(generated):
		return _reject_build(generated)
	_recipe = next
	_undo.clear()
	_redo.clear()
	_saved_fingerprint = Recipe.fingerprint(next) if saved else ""
	_merge_fingerprint = ""
	_last_build = generated
	changed.emit()
	return _result(generated)

func undo() -> bool:
	return _step_history(_undo, _redo)

func redo() -> bool:
	return _step_history(_redo, _undo)

func _step_history(source: Array[Dictionary], target: Array[Dictionary]) -> bool:
	if source.is_empty():
		return false
	var next: Dictionary = source.back().duplicate(true)
	var generated := Generator.build(next)
	if not _successful(generated):
		_reject_build(generated)
		return false
	target.push_back(snapshot())
	source.pop_back()
	_recipe = next
	_last_build = generated
	_merge_fingerprint = ""
	changed.emit()
	return true

func is_dirty() -> bool:
	return fingerprint() != _saved_fingerprint

func mark_saved(expectedfp: String = "") -> bool:
	if not expectedfp.is_empty() and expectedfp != fingerprint():
		return false
	_saved_fingerprint = fingerprint()
	_merge_fingerprint = ""
	return true

func export_draft() -> Dictionary:
	return {"version": 1, "recipe": snapshot(), "saved_fingerprint": _saved_fingerprint}

func restore_draft(draft: Dictionary) -> Dictionary:
	if draft.get("version") != 1 or not (draft.get("recipe") is Dictionary) or not (draft.get("saved_fingerprint") is String):
		return _failure("草稿结构非法")
	var saved: String = draft.saved_fingerprint
	if not saved.is_empty():
		var parser := JSON.new()
		if parser.parse(saved) != OK:
			return _failure("草稿保存指纹非法")
		var decoded: Variant = parser.data
		if not (decoded is Dictionary) or Recipe.fingerprint(decoded) != saved:
			return _failure("草稿保存指纹非法")
	var next := Recipe.normalized(draft.recipe)
	var reason := Recipe.validate(next)
	if not reason.is_empty():
		return _failure(reason)
	var generated := Generator.build(next)
	if not _successful(generated):
		return _reject_build(generated)
	_recipe = next
	_saved_fingerprint = saved
	_undo.clear()
	_redo.clear()
	_merge_fingerprint = ""
	_last_build = generated
	changed.emit()
	return _result(generated)

func _successful(generated: Dictionary) -> bool:
	return bool(generated.get("ok", false)) and is_instance_valid(generated.get("root"))

func _reject_build(generated: Dictionary) -> Dictionary:
	var root: Variant = generated.get("root")
	if is_instance_valid(root):
		root.free()
	return _failure(str(generated.get("reason", "植物生成失败")))

func _result(generated: Dictionary) -> Dictionary:
	var result := generated.duplicate(true)
	result.recipe = snapshot()
	result.fingerprint = fingerprint()
	return result

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "root": null, "branches": [], "stats": {}}
