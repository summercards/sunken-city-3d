extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.actor.set_walking(false)
	context.actor.set_rowing(false)
func tick(_delta: float) -> void:
	if not is_instance_valid(context.interaction_target):
		context.complete_interaction()
		return
	if not context.interactor.is_within_reach(context.interaction_target):
		context.complete_interaction()
		return
	if context.interactor.action_consumed():
		context.complete_interaction()
		return
	context.interactor.auto_hold = not bool(context.ports.input_blocked.call())
func exit() -> void:
	context.clear_interaction()
