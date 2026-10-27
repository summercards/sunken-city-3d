extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.clear_interaction()
	context.actor.set_walking(false)
	context.actor.set_rowing(true)
func exit() -> void:
	context.actor.set_rowing(false)
