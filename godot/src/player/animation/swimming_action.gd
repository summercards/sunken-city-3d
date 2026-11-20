extends RefCounted
## Pose controls drive the existing 21-bone skin. +Y is headward at rest;
## +X pitch of PI/2 is horizontal, NOT a dive. Go past PI/2 for head-first travel.
func sample(a, _delta: float) -> void:
	var effort := smoothstep(0.03, 0.96, float(a.swim_speed_ratio))
	var sprint: float = a.swim_sprint_blend
	var descent := maxf(0.0, -a.swim_trim)
	var ascent := maxf(0.0, a.swim_trim)
	var bottom: float = a.swim_bottom
	var brace: float = a.swim_brace
	var reverse: float = a.swim_reverse
	var brake: float = a.swim_brake
	var turn: float = a.swim_turn_ratio
	var entry: float = a.swim_entry
	var duck := 0.0
	var hinge := 0.0
	var breathe := sin(float(a._t) * 1.55)
	if entry >= 0.0:
		# Start from the prepared glide; chest tips ahead of the legs, then
		# straighten into the descent. No cycle during the initial folding beat.
		duck = smoothstep(0.0, 0.20, entry) * (1.0 - smoothstep(0.50, 1.0, entry))
		hinge = smoothstep(0.0, 0.11, entry) * (1.0 - smoothstep(0.11, 0.32, entry))
		descent *= duck
		effort *= smoothstep(0.23, 0.43, entry) * (1.0 - smoothstep(0.78, 1.0, entry))
	var pitch := lerpf(1.12, 1.49, effort)
	pitch = lerpf(pitch, 2.91, maxf(descent * (1.0 - bottom), duck * 0.98))
	pitch = lerpf(pitch, 0.39, ascent)
	pitch = lerpf(pitch, 1.52, bottom * (1.0 - 0.80 * ascent))
	# Stay chest high at a wall, and tuck hands instead of reaching through it.
	pitch = lerpf(pitch, 0.48, brace * (1.0 - 0.72 * bottom))
	pitch = lerpf(pitch, 1.11, brake * 0.34)
	a.body_pivot.rotation.x = pitch + breathe * 0.012 * (1.0 - effort)
	a.body_pivot.rotation.z = -turn * (0.12 + 0.20 * effort) * (1.0 - 0.7 * maxf(brace, bottom))
	var center := Vector3(0.0, 0.78, 0.0)
	a.body_pivot.position = center - a.body_pivot.basis * center + Vector3.UP * (breathe * 0.012 * (1.0 - effort))
	var streamline := maxf(descent, duck)
	a.head_pivot.rotation.x = lerpf(-0.17 - 0.30 * effort, 0.06, streamline) - brace * 0.10
	a.head_pivot.rotation.y = turn * 0.29
	a.head_pivot.rotation.z = -turn * 0.035
	_limb(a, -1.0, a.left_arm, a.left_elbow, a.left_leg, a.left_knee, float(a._swim_phase),
		effort, sprint, streamline, hinge, bottom, brace, reverse, brake, turn)
	_limb(a, 1.0, a.right_arm, a.right_elbow, a.right_leg, a.right_knee, float(a._swim_phase),
		effort, sprint, streamline, hinge, bottom, brace, reverse, brake, turn)

func _limb(a, side: float, arm: Node3D, elbow: Node3D, hip: Node3D, knee: Node3D, phase: float,
		effort: float, sprint: float, streamline: float, hinge: float, bottom: float, brace: float,
		reverse: float, brake: float, turn: float) -> void:
	var beat := phase + (PI if side > 0.0 else 0.0)
	var power := effort * (1.0 - 0.80 * brace) * (1.0 - 0.65 * brake)
	var turn_beat := side * turn * power
	# Alternating hip -> knee -> ankle wave; compact bent-leg flutter at the floor.
	var hip_pitch := 0.03 + sin(beat) * (0.31 + 0.13 * sprint) * power * (1.0 - 0.77 * bottom)
	var knee_pitch := 0.12 + maxf(0.0, -sin(beat - 0.63)) * (0.28 + 0.16 * bottom) * power
	var ankle_pitch := 1.04 + sin(beat - 1.22) * 0.29 * power
	# Reverse has a distinct heel scoop/opening with an unpowered recovery;
	# it is not the forward flutter played backwards.
	var scoop := smoothstep(-0.65, 0.90, sin(phase))
	var back_power := reverse * power
	hip.rotation.x = lerpf(hip_pitch, -0.13 + scoop * 0.32, back_power) - hinge * 1.35 + turn_beat * 0.20
	hip.rotation.z = side * (0.045 + back_power * (0.09 + 0.23 * scoop))
	knee.rotation.x = lerpf(knee_pitch, 0.22 + scoop * 0.65, back_power) + bottom * 0.37 + brake * 0.19
	var foot := knee.get_node("Foot") as Node3D
	foot.rotation.x = lerpf(ankle_pitch, 0.23 + (1.0 - scoop) * 0.68, back_power) + bottom * 0.12
	foot.rotation.y = side * (back_power * (0.26 + 0.29 * scoop) + turn_beat * 0.36)
	# Arms quiet on the glide, reach headward only on the shallow entry fold.
	# Wide-head profiles retain outboard clearance, even during the reach.
	var open := maxf(brace, brake * 0.66)
	arm.rotation.x = lerpf(-0.42 + sin(beat + 0.9) * 0.16 * power, -0.16, streamline)
	arm.rotation.x = lerpf(arm.rotation.x, -2.46, hinge * 0.80)
	arm.rotation.x = lerpf(arm.rotation.x, -0.65, open)
	arm.rotation.z = side * (0.30 + float(a.avatar_arm_front_clearance()) * 0.22 + hinge * 0.24 + open * 0.45)
	elbow.rotation.x = -0.30 - 0.12 * (1.0 - effort) - open * 0.69
	elbow.rotation.z = side * (0.10 + open * 0.14)
