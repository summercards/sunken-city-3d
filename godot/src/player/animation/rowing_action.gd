extends RefCounted
func sample(a, delta: float) -> void:
	var rowing := Vector2(a._t*3.4,1.0)
	if a.rowing_query.is_valid(): rowing=a.rowing_query.call()
	# 双桨同相划动，人物、船桨和船体使用同一相位及出力。
	var s := sin(rowing.x)
	var blend := 1.0 - exp(-9.0 * delta)
	var arm := lerpf(0.05, -0.95 + s * 0.42, rowing.y)
	var elbow := lerpf(-0.22, -0.35 + s * 0.22, rowing.y)
	a.left_arm.rotation.x = lerpf(a.left_arm.rotation.x, arm, blend)
	a.right_arm.rotation.x = lerpf(a.right_arm.rotation.x, arm, blend)
	a.left_elbow.rotation.x = lerpf(a.left_elbow.rotation.x, elbow, blend)
	a.right_elbow.rotation.x = lerpf(a.right_elbow.rotation.x, elbow, blend)
	a.left_leg.rotation.x = lerpf(a.left_leg.rotation.x, 0.12 * rowing.y, blend)
	a.right_leg.rotation.x = lerpf(a.right_leg.rotation.x, 0.12 * rowing.y, blend)
	a.body_pivot.rotation.x = lerpf(a.body_pivot.rotation.x, (0.10 + s * 0.03) * rowing.y, blend)
	a.body_pivot.position.y = sin(rowing.x) * 0.012 * rowing.y
