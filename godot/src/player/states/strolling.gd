extends "res://src/core/state.gd"
## 键盘自由行走（2026-11-05）。与 walking 并列：walking 消费一条点击求出的折线，
## strolling 每帧消费一个方向；两者都只驱动 CharacterMotor，不改玩法状态。
func enter(_payload: Dictionary) -> void:
	context.walk_path.clear()
	context.after_walk = Callable()
	context.actor.set_rowing(false)
	context.actor.set_walking(true)
func tick(delta: float) -> void:
	context.stride.step(context, delta)
func exit() -> void:
	context.walk_path.clear()
	context.actor.set_walking(false)
