extends RefCounted
## Query only. Commands and camera handoff remain with Main/ActorController.
const Motor = preload("res://src/player/character_motor.gd")
const STAND_RADIUS := 1.15
const ALIGNMENT := 0.85
const DOCKING_AREA := ^"DockEdge/DockingArea"

func hull_at_berth(vessel: Node3D, berth: Node3D) -> bool:
	var area := berth.get_node_or_null(DOCKING_AREA) as Area3D
	return area != null and area.overlaps_body(vessel)

func inspect(vessel: Node3D, actor: CharacterBody3D, berth: Node3D, afloat: bool, _neutral: bool) -> Dictionary:
	if not is_instance_valid(berth): return {"reason":"请靠近泊位"}
	var park := berth.get_node_or_null("BoatPark") as Marker3D
	if park == null: return {"reason":"请靠近泊位"}
	if not hull_at_berth(vessel, berth): return {"reason":"请把船靠近栈桥"}
	if berth.get_meta("check_park_clearance", false) and not vessel.hull_clear_at(Transform3D(park.global_basis, park.global_position)):
		return {"reason":"请保留泊位外侧的停船水面"}
	if not afloat and not _neutral:
		return {"reason":"松开方向键，等小船停稳"}
	var shore: Vector3 = berth.stand_position()
	if not afloat:
		if berth.get_meta("require_standing_on_dock", false):
			var floor: Node3D = berth.ground()
			var local := floor.to_local(actor.global_position)
			if not floor.rects.any(func(rect: Rect2): return rect.has_point(Vector2(local.x, local.z))):
				return {"reason":"请站到码头甲板上再上船"}
		if planar(actor.global_position-shore) > STAND_RADIUS or absf(actor.global_position.y-shore.y) > 0.20:
			return {"reason":"请走近泊位再上船"}
		if not safe_feet(actor, actor.global_position, 0.13, 0.12).is_finite():
			return {"reason":"请站稳在码头上"}
	var target := safe_feet(actor, shore, 0.25, 0.25)
	if not target.is_finite(): return {"reason":"岸上落脚点不安全"}
	return {"point": target, "dock_position": park.global_position, "dock_yaw": park.global_rotation.y}

func safe_feet(actor: CharacterBody3D, anchor: Vector3, above: float, below: float) -> Vector3:
	var collider := actor.get_node_or_null("BodyCollision") as CollisionShape3D
	if collider == null: return Vector3.INF
	var capsule := collider.shape as CapsuleShape3D
	if capsule == null: return Vector3.INF
	var space := actor.get_world_3d().direct_space_state
	var expected := Vector3.INF
	for unit: Vector3 in [Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var sample := anchor + unit * capsule.radius * 0.90
		var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * above, sample - Vector3.UP * below, Motor.SCENE_GROUND_LAYER)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.94: return Vector3.INF
		if unit == Vector3.ZERO: expected = hit.position
		elif absf(hit.position.y-expected.y) > 0.05: return Vector3.INF
	var feet := expected + Vector3.UP * 0.01
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet) * collider.transform
	query.collision_mask = Motor.SCENE_GROUND_LAYER | Motor.GROUND_LAYER | Motor.ACTOR_LAYER
	query.exclude = [actor.get_rid()]
	return feet if space.intersect_shape(query, 1).is_empty() else Vector3.INF

static func planar(vector: Vector3) -> float:
	return Vector2(vector.x, vector.z).length()
