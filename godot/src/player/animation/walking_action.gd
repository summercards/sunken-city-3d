extends RefCounted
## 同一连续地速相位，平滑混合步行与短步轻跑；不修改玩法根位移。
func sample(a, _delta: float) -> void:
	var phase: float = a.walk_phase()
	var s := sin(phase)
	var c := cos(phase)
	var jog: float = a.run_blend()
	# 轻跑靠更快的短步、回收腿与屈肘区分，不靠把走路幅度整体放大。
	var arm_swing := lerpf(0.66, 0.55, jog)
	var stride := lerpf(0.54, 0.54 * 1.12 / 1.15, jog)
	a.left_arm.rotation.x = s * arm_swing
	a.right_arm.rotation.x = -s * arm_swing
	a.left_leg.rotation.x = -s * stride
	a.right_leg.rotation.x = s * stride
	var knee_lift := lerpf(0.48, 0.86, jog)
	var knee_rest := 0.10 * jog
	a.left_knee.rotation.x = knee_rest + maxf(0.0, -s) * knee_lift + maxf(0.0, c) * 0.08
	a.right_knee.rotation.x = knee_rest + maxf(0.0, s) * knee_lift + maxf(0.0, -c) * 0.08
	var elbow_rest := lerpf(-0.18, -0.82, jog)
	a.left_elbow.rotation.x = elbow_rest - maxf(0.0, s) * 0.12
	a.right_elbow.rotation.x = elbow_rest - maxf(0.0, -s) * 0.12
	a.body_pivot.rotation.x = lerpf(0.045, 0.12, jog) + absf(c) * 0.015
	a.body_pivot.rotation.z = s * lerpf(0.032, 0.024, jog)
	a.body_pivot.position.y = absf(s) * lerpf(0.024, 0.032, jog)
	a.head_pivot.rotation.z = -s * 0.025
	a.head_pivot.rotation.x = -absf(s) * 0.02 - jog * 0.035
