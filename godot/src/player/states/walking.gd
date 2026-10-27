extends "res://src/core/state.gd"
func enter(payload: Dictionary) -> void:
	context.walk_area=payload.get("area")
	context.walk_target=payload.get("target",context.actor.global_position)
	context.walk_path.assign(payload.get("path",[]))
	if not context.walk_path.is_empty(): context.walk_path.pop_front()
	context.actor.set_rowing(false)
	context.actor.set_walking(not context.walk_path.is_empty())
func tick(delta: float) -> void:
	if context.ground.step(context,delta):
		var callback: Callable = context.after_walk
		context.after_walk=Callable()
		machine.change("ashore_idle")
		if callback.is_valid(): callback.call()
func exit() -> void:
	context.walk_path.clear()
	context.after_walk=Callable()
	context.actor.set_walking(false)
