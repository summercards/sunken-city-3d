extends RefCounted
## 采样只看 Character 积分出来的步频相位（SEA-MOVE-R23）。
## 相位由地速驱动：慢走步幅小、频率低，跑步（当前最高速）就是原来的 6.4 rad/s。
func sample(a, _delta: float) -> void:
	var phase: float = a.walk_phase()
	var s := sin(phase)
	var c := cos(phase)
	a.left_arm.rotation.x = s * 0.66
	a.right_arm.rotation.x = -s * 0.66
	a.left_leg.rotation.x = -s * 0.54
	a.right_leg.rotation.x = s * 0.54
	a.left_knee.rotation.x = maxf(0.0, -s) * 0.48 + maxf(0.0, c) * 0.08
	a.right_knee.rotation.x = maxf(0.0, s) * 0.48 + maxf(0.0, -c) * 0.08
	a.left_elbow.rotation.x = -0.18 - maxf(0.0, s) * 0.12
	a.right_elbow.rotation.x = -0.18 - maxf(0.0, -s) * 0.12
	a.body_pivot.rotation.x = 0.045 + absf(c) * 0.015
	a.body_pivot.rotation.z = s * 0.032
	a.body_pivot.position.y = absf(s) * 0.024
	a.head_pivot.rotation.z = -s * 0.025
	a.head_pivot.rotation.x = -absf(s) * 0.02
