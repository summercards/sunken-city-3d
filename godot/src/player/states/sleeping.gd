extends "res://src/core/state.gd"
## Sleep flow owns the exit; no locomotion or interaction is evaluated here.
func enter(_payload: Dictionary) -> void:
	context.actor.set_walking(false)
	context.actor.set_rowing(false)
	context.clear_interaction()
