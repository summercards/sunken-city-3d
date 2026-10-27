extends "res://src/player/states/walking.gd"
func enter(payload: Dictionary) -> void:
	super.enter(payload)
	context.auto_target=payload.get("subject")
	context.interactor.preferred_target=context.auto_target
func tick(delta: float) -> void:
	if not is_instance_valid(context.auto_target):
		context.cancel()
	elif context.ground.step(context,delta):
		machine.change("interacting")
