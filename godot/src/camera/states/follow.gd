extends "res://src/core/state.gd"
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
## The aim height follows the visual body scale; a fixed 0.7m would chase the
## enlarged traveler low and push the head toward the top of the frame.
func tick(_delta: float) -> void:
	if is_instance_valid(context.follow_subject):
		# 前视由 OrbitCam 按主体速度缓动（SEA-CAMERA-R14）：这只是「看远一点」，
		# 不改跟随误差、不改构图角度，手动接管时自动归零。
		context.target=context.follow_subject.global_position+Vector3.UP*Dimensions.CAMERA_FOCUS+context.lead()
