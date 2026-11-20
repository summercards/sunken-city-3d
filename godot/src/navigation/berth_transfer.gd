extends RefCounted
## Query only. Commands and camera handoff remain with Main/ActorController.
const GROUND_MASK := 256
const TRANSFER_MASK := 256 | 512
const MOORING_RADIUS := 1.35
const STAND_RADIUS := 1.15
const MAX_ACROSS := 4.2
const MAX_RISE := 1.3
const ALIGNMENT := 0.85

func inspect(vessel: Node3D, actor: CharacterBody3D, berth: Node3D, afloat: bool, neutral: bool) -> Dictionary:
	if not is_instance_valid(berth): return {"reason":"请靠近泊位"}
	var park := berth.get_node_or_null("BoatPark") as Marker3D
	if park == null or planar(vessel.global_position - park.global_position) > MOORING_RADIUS:
		return {"reason":"请划近泊位"}
	if not neutral or not vessel.is_still(): return {"reason":"松开方向键，等小船停稳"}
	if absf(vessel.global_basis.z.dot(park.global_basis.z.normalized())) < ALIGNMENT:
		return {"reason":"请让船身沿泊位方向停靠"}
	if not vessel.hull_clear(): return {"reason":"小船船身被挡"}
	var shore: Vector3 = berth.stand_position()
	if not afloat:
		if planar(actor.global_position-shore) > STAND_RADIUS or absf(actor.global_position.y-shore.y) > 0.20:
			return {"reason":"请走近泊位再上船"}
		if not _safe_feet(berth, actor, actor.global_position).is_finite():
			return {"reason":"请站稳在码头上"}
	var seat: Vector3 = vessel.to_global(vessel.boarding_position())
	if planar(seat-shore) > MAX_ACROSS or absf(seat.y-shore.y) > MAX_RISE:
		return {"reason":"船与落脚点太远"}
	var target := _safe_feet(berth, actor, shore)
	if not target.is_finite(): return {"reason":"岸上落脚点不安全"}
	return {"point": target}

func _safe_feet(berth: Node3D, actor: CharacterBody3D, anchor: Vector3) -> Vector3:
	var area: Node3D = berth.ground()
	var collider := actor.get_node_or_null("BodyCollision") as CollisionShape3D
	if area == null or collider == null: return Vector3.INF
	var capsule := collider.shape as CapsuleShape3D
	if capsule == null: return Vector3.INF
	var space := actor.get_world_3d().direct_space_state
	var expected: Vector3 = area.surface_point(anchor)
	if not expected.is_finite() or absf(expected.y - anchor.y) > 0.12: return Vector3.INF
	for unit: Vector3 in [Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var sample := expected + unit * capsule.radius * 0.90
		var foot: Vector3 = area.surface_point(sample)
		if not foot.is_finite() or absf(foot.y-expected.y) > 0.05: return Vector3.INF
		var ray := PhysicsRayQueryParameters3D.create(sample+Vector3.UP*0.13, sample-Vector3.UP*0.12, GROUND_MASK)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or absf(hit.position.y-foot.y) > 0.04 or hit.normal.y < 0.94: return Vector3.INF
	var feet := expected + Vector3.UP * 0.01
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet) * collider.transform
	query.collision_mask = TRANSFER_MASK
	query.exclude = [actor.get_rid()]
	return feet if space.intersect_shape(query, 1).is_empty() else Vector3.INF

static func planar(vector: Vector3) -> float:
	return Vector2(vector.x, vector.z).length()
