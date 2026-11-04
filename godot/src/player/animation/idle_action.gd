extends RefCounted
## Natural indie-style idle & preview motion: organic breathing, subtle weight shift,
## gentle wrist/arm sway, and responsive turn/customize micro-reactions.
func sample(a, delta: float) -> void:
	var k := clampf(delta * 5.0, 0.0, 1.0)
	var t: float = a._t
	var breath := sin(t * 1.75) * 0.014
	var sway := sin(t * 0.85) * 0.022
	var nod := sin(t * 1.15 + 0.6) * 0.032
	var look_yaw := sin(t * 0.52) * 0.22 + sin(t * 1.18) * 0.05
	var pulse: float = float(a.get("_customize_pulse")) if "_customize_pulse" in a else 0.0
	var turn_vel: float = float(a.get("_turn_velocity")) if "_turn_velocity" in a else 0.0
	var step_phase := sin(t * 11.0) * clampf(absf(turn_vel) * 2.5, 0.0, 1.0)
	var arm_Rest := float(a._avatar_factors.get("arm_rest", 0.50))
	var pulse_wave := sin(pulse * PI) * 0.14 if pulse > 0.0 else 0.0
	a.left_arm.rotation.x = lerpf(a.left_arm.rotation.x, 0.045 + sin(t * 1.35) * 0.045 - pulse_wave + step_phase * 0.15, k)
	a.right_arm.rotation.x = lerpf(a.right_arm.rotation.x, -0.045 - sin(t * 1.35) * 0.045 - pulse_wave - step_phase * 0.15, k)
	a.left_arm.rotation.z = lerpf(a.left_arm.rotation.z, -arm_Rest - maxf(0.0, breath) * 0.6 - pulse_wave * 0.25, k)
	a.right_arm.rotation.z = lerpf(a.right_arm.rotation.z, arm_Rest + maxf(0.0, breath) * 0.6 + pulse_wave * 0.25, k)
	a.left_elbow.rotation.x = lerpf(a.left_elbow.rotation.x, -0.075 - pulse_wave * 1.1, k)
	a.right_elbow.rotation.x = lerpf(a.right_elbow.rotation.x, -0.075 - pulse_wave * 1.1, k)
	a.left_leg.rotation.x = lerpf(a.left_leg.rotation.x, -step_phase * 0.20, k)
	a.right_leg.rotation.x = lerpf(a.right_leg.rotation.x, step_phase * 0.20, k)
	a.left_knee.rotation.x = lerpf(a.left_knee.rotation.x, maxf(0.0, step_phase) * 0.24, k)
	a.right_knee.rotation.x = lerpf(a.right_knee.rotation.x, maxf(0.0, -step_phase) * 0.24, k)
	a.body_pivot.rotation.x = lerpf(a.body_pivot.rotation.x, sin(t * 1.75 - 0.4) * 0.015 - pulse_wave * 0.12, k)
	a.body_pivot.rotation.z = lerpf(a.body_pivot.rotation.z, sway * 0.65, k)
	a.body_pivot.position.y = breath + absf(step_phase) * 0.012 + sin(pulse * PI) * 0.016
	a.head_pivot.rotation.y = lerpf(a.head_pivot.rotation.y, look_yaw + clampf(turn_vel * 0.35, -0.25, 0.25), k)
	a.head_pivot.rotation.x = lerpf(a.head_pivot.rotation.x, nod - pulse_wave * 0.25, k)
	a.head_pivot.rotation.z = lerpf(a.head_pivot.rotation.z, -sway * 0.9, k)
