extends "res://src/core/state.gd"
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
## The aim height follows the visual body scale; a fixed 0.7m would chase the
## enlarged traveler low and push the head toward the top of the frame.
func tick(_delta: float) -> void:
	if is_instance_valid(context.follow_subject): context.target=context.follow_subject.global_position+Vector3.UP*Dimensions.CAMERA_FOCUS
