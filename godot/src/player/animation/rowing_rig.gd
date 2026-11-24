extends RefCounted
## Shared presentation: the original skiff's stroke and real attachment points.
## No input, hull movement, scene bootstrap or gameplay state.

static func sample_oars(left: Node3D, right: Node3D, state: Vector2, effort: float, turn: float, delta: float, power := 0.0) -> Vector2:
	var blend := lerpf(state.y, effort, 1.0 - exp(-4.0 * delta))
	var stroke := fmod(state.x + delta * (0.65 + blend * 0.45 + power * 0.30) * TAU, TAU)
	left.visible = true
	right.visible = true
	var swing := sin(stroke)
	var dip := cos(stroke)
	var sweep := 0.06 + power * 0.05
	left.rotation.y = lerpf(0.08, swing * sweep * (1.0 - turn * 0.3), blend)
	right.rotation.y = lerpf(-0.08, -swing * sweep * (1.0 + turn * 0.3), blend)
	# The authored oarlocks sit on the higher gunwale; blades still dip below
	# the original waterline on the power stroke and clear it on recovery.
	var lift := 0.14 + power * 0.03
	left.rotation.z = lerpf(0.22, 0.36 + dip * lift, blend)
	right.rotation.z = lerpf(-0.22, -0.36 - dip * lift, blend)
	return Vector2(stroke, blend)

static func contacts(seat: Node3D, left: Node3D, right: Node3D) -> Dictionary:
	return {"seat": seat.global_transform,
		"left_grip": left.get_node("OarLVisual/Grip").global_position,
		"right_grip": right.get_node("OarRVisual/Grip").global_position}
