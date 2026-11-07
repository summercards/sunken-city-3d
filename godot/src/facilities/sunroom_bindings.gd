extends RefCounted
## Small composition helper kept outside Main's business rules.

static func climb(actor_controller, from: Vector3, to: Vector3, subject: Node3D) -> Dictionary:
	return actor_controller.climb_ladder(from, to, subject)
