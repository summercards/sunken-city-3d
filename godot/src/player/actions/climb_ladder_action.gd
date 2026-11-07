extends RefCounted
## SEA-MOVE-R25: deterministic ladder traversal between authored endpoints.
## The ladder is a special action, not a walkable rectangle and not a teleport.

const SPEED := 1.35
const END_TOLERANCE := 0.025

func prepare(c, start: Vector3, end: Vector3, subject: Node3D) -> Dictionary:
	if c.mode() != 0 or c.machine.current in ["diving", "sleeping", "interacting", "boarding"]:
		return {"ok": false}
	if subject == null or not is_instance_valid(subject):
		return {"ok": false}
	if start.distance_to(end) < 0.25:
		return {"ok": false}
	return {"ok": true, "start": start, "end": end, "subject": subject}

func step(c, delta: float) -> bool:
	var from: Vector3 = c.climb_from
	var to: Vector3 = c.climb_to
	var distance := from.distance_to(to)
	if distance < 0.001:
		return true
	c.climb_progress = clampf(c.climb_progress + SPEED * maxf(delta, 0.0) / distance, 0.0, 1.0)
	var next: Vector3 = from.lerp(to, c.climb_progress)
	# A ladder is not a walkable floor. ActorController disables floor collision
	# on the climbing transition, then this authored trajectory moves the capsule
	# continuously along the ladder centerline. This is an action path, not a
	# one-frame teleport and cannot be used by ordinary walking.
	c.actor.global_position = next
	c.actor.rotation.y = atan2((to - from).x, (to - from).z)
	return c.climb_progress >= 1.0 - END_TOLERANCE
