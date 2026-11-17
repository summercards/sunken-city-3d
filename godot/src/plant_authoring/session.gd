@tool
extends RefCounted
class_name PlantAuthoringSession
## 唯一已应用状态所有者；配方与创作上下文一起提交，预览 root 由调用者释放。

signal changed

const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")
const HostAttachment = preload("res://src/plant_authoring/host_attachment.gd")

var _recipe: Dictionary = {}
var _authoring_context: Dictionary = {"host_binding": {}}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _saved_fingerprint := ""
var _saved_context: Dictionary = {"host_binding": {}}
var _last_build: Dictionary = {}
var _merge_fingerprint := ""
var _revision := 0
# 同步候选端口：接收生成结果，返回 {ok, reason}；不挂载 root，也不改 Session。
var candidate_validator: Callable = Callable()

func _init(species: String = "camphor") -> void:
	var selected := species if Recipe.SPECIES.has(species) else "camphor"
	_recipe = Recipe.normalized(Recipe.defaults(selected))

func snapshot() -> Dictionary:
	return _recipe.duplicate(true)

func authoring_context() -> Dictionary:
	return _authoring_context.duplicate(true)

func host_binding() -> Dictionary:
	return _authoring_context.host_binding.duplicate(true)

func state_snapshot() -> Dictionary:
	return {"recipe": snapshot(), "authoring_context": authoring_context()}

func state_fingerprint() -> String:
	return canonical_state_fingerprint(_recipe, _authoring_context)

static func canonical_state_fingerprint(recipe: Dictionary, context: Dictionary) -> String:
	return Recipe._stable_json({"recipe": Recipe.normalized(recipe), "authoring_context": _normalized_context(context)})

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
	if not expectedfp.is_empty() and expectedfp != fingerprint():
		return _failure("候选已过期：配方指纹不匹配")
	if merge_history and expectedfp.is_empty():
		return _failure("合并历史必须承接上一次候选及其指纹")
	# 保留旧接口的 expectedfp 语义：它只校验配方，完整状态由内部当前快照承接。
	return preview_candidate_with_context(candidate, authoring_context(), merge_history, state_fingerprint())

func preview_candidate_with_context(candidate: Dictionary, context: Dictionary, merge_history: bool = false, expected_state: String = "") -> Dictionary:
	var current := state_fingerprint()
	if not expected_state.is_empty() and expected_state != current:
		return _failure("候选已过期：配方或创作上下文不匹配")
	if merge_history and (expected_state.is_empty() or _merge_fingerprint != current or _undo.is_empty()):
		return _failure("合并历史必须承接上一次候选及其完整状态指纹")
	var reason := validate_context(context)
	if not reason.is_empty():
		return _failure(reason)
	var next := Recipe.normalized(candidate)
	reason = Recipe.validate(next)
	if not reason.is_empty():
		return _failure(reason)
	var next_context := _normalized_context(context)
	# 切物种不能把旧房屋坐标带给新树；new/load 也显式清空上下文。
	if next.species != _recipe.species:
		next_context = {"host_binding": {}}
	if canonical_state_fingerprint(next, next_context) == current:
		return build()
	var generated := _build_candidate(next)
	if not _successful(generated):
		return generated
	if not merge_history:
		_undo.push_back(state_snapshot())
	_redo.clear()
	_recipe = next
	_authoring_context = next_context
	_last_build = generated
	_revision += 1
	_merge_fingerprint = state_fingerprint()
	changed.emit()
	return _result(generated)

func _build_candidate(next: Dictionary) -> Dictionary:
	if Recipe.fingerprint(next) == fingerprint() and _successful(_last_build):
		return _last_build
	return _generate_candidate(next)

func _generate_candidate(next: Dictionary) -> Dictionary:
	var generated := Generator.build(next)
	if not _successful(generated):
		return _reject_build(generated)
	if candidate_validator.is_valid():
		var validation: Dictionary = candidate_validator.call(generated)
		if not bool(validation.get("ok", false)):
			generated.reason = str(validation.get("reason", "候选校验失败"))
			return _reject_build(generated)
	return generated

func build() -> Dictionary:
	if not _successful(_last_build):
		var generated := _generate_candidate(snapshot())
		if not _successful(generated):
			return generated
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
	var generated := _generate_candidate(next)
	if not _successful(generated):
		return generated
	_recipe = next
	_authoring_context = {"host_binding": {}}
	_saved_context = authoring_context()
	_undo.clear()
	_redo.clear()
	_saved_fingerprint = Recipe.fingerprint(next) if saved else ""
	_merge_fingerprint = ""
	_last_build = generated
	_revision += 1
	changed.emit()
	return _result(generated)

## 返回独立副本及事务版本。调用者必须按目标 recipe/context 预检，再原样提交。
func peek_history(direction: String) -> Dictionary:
	if direction not in ["undo", "redo"]:
		return {}
	var source := _undo if direction == "undo" else _redo
	if source.is_empty():
		return {}
	return {"direction": direction, "revision": _revision, "state": source.back().duplicate(true)}

func peek_undo() -> Dictionary:
	return peek_history("undo")

func peek_redo() -> Dictionary:
	return peek_history("redo")

func peek_undo_target() -> Dictionary:
	return peek_undo().get("state", {}).duplicate(true)

func peek_redo_target() -> Dictionary:
	return peek_redo().get("state", {}).duplicate(true)

func commit_transaction(transaction: Dictionary) -> Dictionary:
	return commit_history(transaction)

func commit_history(transaction: Dictionary) -> Dictionary:
	var direction := str(transaction.get("direction", ""))
	var expected := peek_history(direction)
	if expected.is_empty() or transaction != expected:
		return _failure("历史事务已过期或目标被修改")
	var next: Dictionary = expected.state
	var generated := _build_candidate(next.recipe)
	if not _successful(generated):
		return generated
	var source := _undo if direction == "undo" else _redo
	var target := _redo if direction == "undo" else _undo
	target.push_back(state_snapshot())
	source.pop_back()
	_recipe = next.recipe.duplicate(true)
	_authoring_context = next.authoring_context.duplicate(true)
	_last_build = generated
	_merge_fingerprint = ""
	_revision += 1
	changed.emit()
	return _result(generated)

func undo() -> bool:
	return bool(commit_history(peek_undo()).ok)

func redo() -> bool:
	return bool(commit_history(peek_redo()).ok)

func is_dirty() -> bool:
	return is_recipe_dirty() or is_context_dirty()

func is_recipe_dirty() -> bool:
	return fingerprint() != _saved_fingerprint

func is_context_dirty() -> bool:
	return Recipe._stable_json(_authoring_context) != Recipe._stable_json(_saved_context)

## 植物 bundle 只保存配方，不代表宿主结合描述已经落盘。
func mark_saved(expectedfp: String = "") -> bool:
	if not expectedfp.is_empty() and expectedfp != fingerprint():
		return false
	_saved_fingerprint = fingerprint()
	_merge_fingerprint = ""
	return true

## 结合描述引用配方及宿主，必须校验保存开始时的完整状态。
func mark_context_saved(expected_state: String) -> bool:
	if expected_state != state_fingerprint():
		return false
	_saved_context = authoring_context()
	_merge_fingerprint = ""
	return true

func export_draft() -> Dictionary:
	return {"version": 1, "recipe": snapshot(), "saved_fingerprint": _saved_fingerprint, "authoring_context": authoring_context(), "saved_authoring_context": _saved_context.duplicate(true)}

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
	var context: Variant = draft.get("authoring_context", {})
	var saved_context: Variant = draft.get("saved_authoring_context", {})
	for value in [context, saved_context]:
		var context_reason := validate_context(value)
		if not context_reason.is_empty():
			return _failure(context_reason)
	var next := Recipe.normalized(draft.recipe)
	var reason := Recipe.validate(next)
	if not reason.is_empty():
		return _failure(reason)
	var generated := _generate_candidate(next)
	if not _successful(generated):
		return generated
	_recipe = next
	_authoring_context = _normalized_context(context)
	_saved_context = _normalized_context(saved_context)
	_saved_fingerprint = saved
	_undo.clear()
	_redo.clear()
	_merge_fingerprint = ""
	_last_build = generated
	_revision += 1
	changed.emit()
	return _result(generated)

static func validate_context(context: Variant) -> String:
	if not context is Dictionary:
		return "创作上下文必须是字典"
	for key in context:
		if key != "host_binding":
			return "未知创作上下文字段：" + str(key)
	var binding: Variant = context.get("host_binding", {})
	if not binding is Dictionary:
		return "宿主绑定必须是字典"
	if binding.is_empty():
		return ""
	for key in binding:
		if key not in ["host_path", "matrix", "opening_id", "enabled"]:
			return "未知宿主绑定字段：" + str(key)
	if not binding.get("host_path") is String or not binding.get("opening_id") is String or not binding.get("enabled") is bool:
		return "宿主绑定字段非法"
	var path: String = binding.host_path
	if not path.begins_with("res://") or path.contains("..") or path.get_file() != "building.tscn":
		return "宿主绑定必须引用项目内的 building.tscn"
	var decoded := HostAttachment.decode_transform(binding.get("matrix"))
	return "" if bool(decoded.ok) else str(decoded.reason)

static func _normalized_context(context: Dictionary) -> Dictionary:
	return {"host_binding": context.get("host_binding", {}).duplicate(true)}

func _successful(generated: Dictionary) -> bool:
	return bool(generated.get("ok", false)) and is_instance_valid(generated.get("root"))

func _reject_build(generated: Dictionary) -> Dictionary:
	var root: Variant = generated.get("root")
	if is_instance_valid(root) and root != _last_build.get("root"):
		root.free()
	return _failure(str(generated.get("reason", "植物生成失败")))

func _result(generated: Dictionary) -> Dictionary:
	var result := generated.duplicate(true)
	result.recipe = snapshot()
	result.fingerprint = fingerprint()
	result.authoring_context = authoring_context()
	result.state_fingerprint = state_fingerprint()
	return result

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "root": null, "branches": [], "stats": {}}
