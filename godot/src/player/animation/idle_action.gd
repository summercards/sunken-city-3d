extends RefCounted
func sample(a, delta: float) -> void:
	# 待机：轻微呼吸与左右看
	var breath := sin(a._t * 1.5) * 0.012
	a.left_arm.rotation.x = lerp(a.left_arm.rotation.x, 0.05, clamp(delta * 4.0, 0.0, 1.0))
	a.right_arm.rotation.x = lerp(a.right_arm.rotation.x, -0.05, clamp(delta * 4.0, 0.0, 1.0))
	a.left_elbow.rotation.x = lerp(a.left_elbow.rotation.x, -0.22, clamp(delta * 4.0, 0.0, 1.0))
	a.right_elbow.rotation.x = lerp(a.right_elbow.rotation.x, -0.22, clamp(delta * 4.0, 0.0, 1.0))
	a.left_leg.rotation.x = lerp(a.left_leg.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	a.right_leg.rotation.x = lerp(a.right_leg.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	a.left_knee.rotation.x = lerp(a.left_knee.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	a.right_knee.rotation.x = lerp(a.right_knee.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	a.body_pivot.rotation.x = lerp(a.body_pivot.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	a.body_pivot.position.y = breath
	a.head_pivot.rotation.y = sin(a._t * 0.55) * 0.28
