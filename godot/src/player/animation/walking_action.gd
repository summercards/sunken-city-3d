extends RefCounted
func sample(a, delta: float) -> void:
	var s := sin(a._t * 6.4)
	a.left_arm.rotation.x = s * 0.7
	a.right_arm.rotation.x = -s * 0.7
	a.left_leg.rotation.x = -s * 0.55
	a.right_leg.rotation.x = s * 0.55
	a.left_knee.rotation.x = max(0.0, -s) * 0.5
	a.right_knee.rotation.x = max(0.0, s) * 0.5
	a.left_elbow.rotation.x = -0.18
	a.right_elbow.rotation.x = -0.18
	a.body_pivot.rotation.x = 0.04
	a.body_pivot.position.y = abs(sin(a._t * 6.4)) * 0.022
