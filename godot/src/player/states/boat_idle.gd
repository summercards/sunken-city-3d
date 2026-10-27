extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.actor.set_walking(false)
	context.actor.set_rowing(false)
