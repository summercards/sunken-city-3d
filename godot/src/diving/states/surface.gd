extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	if context.active: context.finish_exit_action.execute(context)
