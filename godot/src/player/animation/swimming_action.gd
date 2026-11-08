extends RefCounted
## 第三人称潜水姿态：avatar 的脸朝 +Z，所有前伸和俯仰都以 +Z 为前方。
## 这里仅消费 Character 已平滑的表现值，不触碰位移、碰撞或海面动作。
func sample(a, _delta: float) -> void:
	var speed: float = clampf(a.swim_speed_ratio / 1.65, 0.0, 1.0)
	var effort: float = smoothstep(0.0, 0.18, speed)
	var sprint: float = clampf(a.swim_sprint_blend, 0.0, 1.0)
	var stroke: float = sin(a._swim_phase)
	var counter_stroke: float = sin(a._swim_phase + PI)
	var breathe: float = sin(a._t * 1.55)
	var suspended: float = 1.0 - effort

	# +X rotation makes the +Z-facing nose dip; climbing therefore pitches back.
	var forward_pitch: float = lerpf(0.035, 0.72, effort) + sprint * 0.10 - a.swim_vertical_ratio * 0.40
	a.body_pivot.rotation.x = forward_pitch + breathe * 0.018 * suspended
	a.body_pivot.rotation.z = -a.swim_turn_ratio * (0.055 + 0.075 * effort)
	# Rotate around torso, not the feet: a streamlined stroke must not swing the
	# entire visual body out of the capsule centre as pitch changes.
	var torso_center := Vector3(0.0, 0.90, 0.0)
	a.body_pivot.position = torso_center - a.body_pivot.basis * torso_center
	a.body_pivot.position.y += breathe * (0.006 + 0.014 * suspended)

	# Alternating front crawl: negative X swings the hanging limb toward +Z.
	# The neutral pose stays slightly forward even while hovering.
	var arm_reach := lerpf(0.10, 0.48, effort) * lerpf(1.0, 1.12, sprint)
	a.left_arm.rotation.x = -0.67 - stroke * arm_reach
	a.right_arm.rotation.x = -0.67 - counter_stroke * arm_reach
	var elbow_fold := lerpf(0.12, 0.30, effort) + absf(stroke) * 0.10
	a.left_elbow.rotation.x = -elbow_fold - maxf(0.0, stroke) * 0.08
	a.right_elbow.rotation.x = -elbow_fold - maxf(0.0, counter_stroke) * 0.08

	# Small alternating flutter kick; knees remain softly flexed rather than snapping.
	var kick := lerpf(0.045, 0.22, effort) * lerpf(1.0, 1.16, sprint)
	a.left_leg.rotation.x = -0.035 + stroke * kick
	a.right_leg.rotation.x = -0.035 + counter_stroke * kick
	var knee_fold := lerpf(0.035, 0.13, effort) + maxf(0.0, -stroke) * 0.10
	a.left_knee.rotation.x = knee_fold
	a.right_knee.rotation.x = lerpf(0.035, 0.13, effort) + maxf(0.0, -counter_stroke) * 0.10

	# Head follows the waterline subtly, while leaving the dive mask clear of the hat.
	a.head_pivot.rotation.x = -a.swim_vertical_ratio * 0.08 - a.body_pivot.rotation.x * 0.16
	a.head_pivot.rotation.z = -a.swim_turn_ratio * 0.035
