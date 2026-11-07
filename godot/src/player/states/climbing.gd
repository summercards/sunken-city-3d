extends "res://src/core/state.gd"
## Vertical ladder traversal. It owns no payment and never changes the floor
## definition; the ladder interaction injects authored endpoints.

func enter(payload: Dictionary) -> void:
	context.climb_from = payload.get("start", context.actor.global_position)
	context.climb_to = payload.get("end", context.actor.global_position)
	context.climb_progress = 0.0
	context.climb_subject = payload.get("subject")
	context.move_intent = Vector3.ZERO
	context.move_velocity = Vector3.ZERO
	context.actor.set_rowing(false)
	context.actor.set_walking(false)
	context.actor.walk_speed_ratio = 0.0

func tick(delta: float) -> void:
	if context.climb_action.step(context, delta):
		context.notify("已经到达" if context.climb_to.y > context.climb_from.y else "回到一楼")
		machine.change("ashore_idle")

func exit() -> void:
	context.climb_progress = 0.0
	context.climb_subject = null
