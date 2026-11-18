@tool
extends RefCounted
## 仅供单个建筑预览文档；节点寿命及分支引用全部交给原生 UndoRedo。

signal committed(name: String)
signal undone(name: String)
signal redone(name: String)
signal cleared
signal branch_discarded
signal changed

# 用脚本类本身作为省略标记；不借用 null 或原生类常量。
class OmittedArgument extends RefCounted:
	pass

var _undo: UndoRedo = UndoRedo.new()
var _action_name := ""
var _discarding_branch := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_undo):
		_undo.free()

# 第三参兼容 EditorUndoRedoManager 的场景上下文，不传给原生第三个 bool。
func create_action(name: String, merge_mode: int = UndoRedo.MERGE_DISABLE, _scene: Object = null, backward_undo_ops: bool = false) -> void:
	_action_name = name
	_discarding_branch = _undo.has_redo()
	_undo.create_action(name, merge_mode, backward_undo_ops)

func _operation(target: Object, method: StringName, args: Array) -> Callable:
	while not args.is_empty() and is_same(args.back(), OmittedArgument): args.pop_back()
	return Callable(target, method).bindv(args)

func add_do_method(target: Object, method: StringName, a: Variant = OmittedArgument, b: Variant = OmittedArgument, c: Variant = OmittedArgument, d: Variant = OmittedArgument, e: Variant = OmittedArgument) -> void:
	_undo.add_do_method(_operation(target, method, [a, b, c, d, e]))

func add_undo_method(target: Object, method: StringName, a: Variant = OmittedArgument, b: Variant = OmittedArgument, c: Variant = OmittedArgument, d: Variant = OmittedArgument, e: Variant = OmittedArgument) -> void:
	_undo.add_undo_method(_operation(target, method, [a, b, c, d, e]))

func add_do_reference(object: Object) -> void:
	_undo.add_do_reference(object)

func add_undo_reference(object: Object) -> void:
	_undo.add_undo_reference(object)

func commit_action(execute: bool = true) -> void:
	var name := _action_name
	var discarded := _discarding_branch
	_undo.commit_action(execute)
	_action_name = ""
	_discarding_branch = false
	if discarded: branch_discarded.emit()
	committed.emit(name)
	changed.emit()

func undo() -> bool:
	if not can_undo(): return false
	var name := _undo.get_current_action_name()
	var ok := _undo.undo()
	if ok:
		undone.emit(name)
		changed.emit()
	return ok

func redo() -> bool:
	if not can_redo(): return false
	var ok := _undo.redo()
	if ok:
		redone.emit(_undo.get_current_action_name())
		changed.emit()
	return ok

func can_undo() -> bool:
	return _undo.has_undo()

func can_redo() -> bool:
	return _undo.has_redo()

func clear_history() -> void:
	_undo.clear_history()
	_action_name = ""
	_discarding_branch = false
	cleared.emit()
	changed.emit()
