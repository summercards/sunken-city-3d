extends "res://src/core/state.gd"
func enter(payload: Dictionary) -> void:
	context.enter_action.execute(context,payload)
func tick(dt: float) -> void:
	context._enter_t += dt
	var blend: float = smoothstep(0.0,1.0,minf(context._enter_t/context.ENTER_TIME,1.0))
	context.diver_pos.y = lerpf(context.WATER_LEVEL,context.ENTER_DEPTH,blend)
	if blend>=1.0: machine.change("swim")
