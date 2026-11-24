extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.actor.set_rowing(false)
	context.actor.set_walking(true)
func tick(delta: float) -> void:
	if context.ports.has("input_blocked") and bool(context.ports.input_blocked.call()):
		context.move_intent = Vector3.ZERO
		context.set_sprint_held(false)
	context.stride.step(context, delta)
func exit() -> void:
	context.move_velocity = Vector3.ZERO
	context.actor.walk_speed_ratio = 0.0
	context.actor.set_walking(false)
