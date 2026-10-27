extends "res://src/core/state.gd"
func tick(_delta: float) -> void:
	if is_instance_valid(context.follow_subject): context.target=context.follow_subject.global_position+Vector3.UP*0.7
