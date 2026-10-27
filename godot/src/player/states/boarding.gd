extends "res://src/core/state.gd"
func enter(_payload: Dictionary) -> void:
	context.board.execute(context)
	machine.change("boat_idle")
