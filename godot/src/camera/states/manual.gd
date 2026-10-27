extends "res://src/core/state.gd"
func tick(delta: float) -> void:
	if not context.panning and context._velocity.length()>0.01:
		context.target+=Vector3(context._velocity.x,0,context._velocity.y)*delta
		context._velocity*=exp(-context.INERTIA_DAMP*delta)
		if context._velocity.length()<0.02: context._velocity=Vector2.ZERO
