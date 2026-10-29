extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.actor.set_walking(false)
	context.actor.set_rowing(false)
func tick(_delta: float) -> void:
	if not is_instance_valid(context.auto_target):
		context.complete_interaction()
		return
	var blocked: bool = context.ports.input_blocked.call()
	var target: Node3D = context.auto_target
	var anchor: Vector3 = target.focus_position() if target.has_method("focus_position") else target.global_position
	context.interactor.auto_hold=not blocked and context.actor.global_position.distance_to(anchor)<=2.2
func exit() -> void:
	context.clear_interaction()
