extends RefCounted
func sample(a, _delta: float) -> void:
	var stroke: float = sin(a._t*3.2)
	a.body_pivot.rotation.x = 0.35
	a.left_arm.rotation.x = -0.8+stroke*0.45
	a.right_arm.rotation.x = -0.8-stroke*0.45
	a.left_elbow.rotation.x = -0.25
	a.right_elbow.rotation.x = -0.25
	a.left_leg.rotation.x = stroke*0.25
	a.right_leg.rotation.x = -stroke*0.25
