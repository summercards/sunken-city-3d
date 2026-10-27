extends "res://src/core/state.gd"
func tick(dt: float) -> void:
	context.swim_action.execute(context,dt)
