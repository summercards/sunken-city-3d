extends "res://src/core/state.gd"
## 键盘自由行走（2026-11-05）。与 walking 并列：walking 消费一条点击求出的折线，
## strolling 每帧消费一个方向；两者都只驱动 CharacterMotor，不改玩法状态。
func enter(_payload: Dictionary) -> void:
	context.walk_path.clear()
	context.after_walk = Callable()
	context.actor.set_rowing(false)
	context.actor.set_walking(true)
func tick(delta: float) -> void:
	if context.ports.has("input_blocked") and bool(context.ports.input_blocked.call()):
		context.move_intent = Vector3.ZERO
		context.set_sprint_held(false)
	context.stride.step(context, delta)
func exit() -> void:
	context.walk_path.clear()
	context.move_velocity = Vector3.ZERO
	context.actor.walk_speed_ratio = 0.0
	context.actor.set_walking(false)
