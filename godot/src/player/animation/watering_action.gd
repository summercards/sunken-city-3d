extends RefCounted
func sample(a, delta: float) -> void:
	a._farm_action_left=maxf(0.0,a._farm_action_left-delta)
	var bend:=sin((1.0-a._farm_action_left/1.1)*PI)
	a.body_pivot.rotation.x=bend*0.22
	a.left_arm.rotation.x=-bend*0.8
	a.right_arm.rotation.x=-bend*1.1
