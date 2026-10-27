extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.surface_action.execute(context)
func tick(dt: float) -> void:
	context._enter_t += dt
	var blend: float = smoothstep(0.0,1.0,minf(context._enter_t/context.ENTER_TIME,1.0))
	context.diver_pos.y = lerpf(context._exit_y,context.WATER_LEVEL,blend)
	if blend>=1.0: machine.change("surface")
