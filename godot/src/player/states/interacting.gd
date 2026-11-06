extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.actor.set_walking(false)
	context.actor.set_rowing(false)
func tick(_delta: float) -> void:
	if not is_instance_valid(context.auto_target):
		context.complete_interaction()
		return
	var blocked: bool = context.ports.input_blocked.call()
	var target: Node3D = context.auto_target
	var anchor: Vector3 = target.focus_position() if target.has_method("focus_position") else target.global_position
	# 门槛跟着目标的「够得着半径」走，不再是写死的 2.2 米。
	# 固定门槛对放大后的家具是错的：床放大 1.5 倍后站位在 2.25 米，
	# 2.2 米门槛永远不成立 —— 人站在床边，auto_hold 却一直是 false。
	var reach := 2.2
	if target.has_method("effective_focus_radius"):
		reach = maxf(reach, float(target.effective_focus_radius()) + 0.6)
	context.interactor.auto_hold=not blocked and context.actor.global_position.distance_to(anchor)<=reach
func exit() -> void:
	context.clear_interaction()
