extends RefCounted
## Simple procedural ladder pose. Motion progress is owned by ActorController;
## this sampler only exposes the hand-over-hand rhythm.

func sample(a, _delta: float) -> void:
	var phase := sin(a._t * 7.0)
	var lift := 0.18 + absf(phase) * 0.12
	a.left_arm.rotation.x = -0.75 - phase * 0.22
	a.right_arm.rotation.x = -0.75 + phase * 0.22
	a.left_arm.rotation.z = -0.12
	a.right_arm.rotation.z = 0.12
	a.left_leg.rotation.x = phase * 0.22
	a.right_leg.rotation.x = -phase * 0.22
	a.body_pivot.rotation.x = 0.10
	a.body_pivot.position.y = lift * 0.10
