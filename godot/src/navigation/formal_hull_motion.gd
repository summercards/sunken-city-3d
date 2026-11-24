extends RefCounted
## Native sweep for the formal Boat. Invoked only by Boat on a physics tick.
const EDGE_RELEASE_SPEED := 1.4
const EDGE_RELEASE_RANGE := 1.8
const BERTH_ENTRY_SPEED := 0.8
const BERTH_SLOW_RANGE := 3.0
const POWER_BERTH_SLOW_RANGE := 4.5
const POWER_SPEED_MULTIPLIER := 1.5
const POWER_ACCEL_MULTIPLIER := 1.45
const OPEN_TURN_RATE := 2.8
const OPEN_TURN_ACCEL := 8.0
const OPEN_TURN_AT_REST := 0.68
const MAX_ROTATION_STEP := 0.03
const EDGE_SWEEP_MARGIN := 0.001
const CRUISE_TURN_START_RATIO := 0.72
const CRUISE_TURN_RATE_MULTIPLIER := 2.15
const CRUISE_TURN_ACCEL_MULTIPLIER := 3.8
const CRUISE_TURN_PROPULSION_DOT := 0.65

var vessel: CharacterBody3D
var hull: CollisionShape3D
var _speed := 0.0
var _turn_rate := 0.0
var _last_contact: Object
var _impact_position := Vector3.INF
var _impact_direction := Vector3.ZERO
var _escape_heading := Vector3.ZERO
var _travel_direction := Vector3.ZERO
var _cruise_turn := false
var power_rowing := false

func configure(body: CharacterBody3D, shape: CollisionShape3D) -> void:
	vessel = body
	hull = shape

func reset() -> void:
	_speed = 0.0
	_turn_rate = 0.0
	_last_contact = null
	_impact_position = Vector3.INF
	_impact_direction = Vector3.ZERO
	_escape_heading = Vector3.ZERO
	_travel_direction = Vector3.ZERO
	_cruise_turn = false
	power_rowing = false
	vessel.velocity = Vector3.ZERO

func advance(intent: Vector3, delta: float, berth: Vector3, cruise_speed: float, power: bool) -> void:
	var strength := minf(intent.length(), 1.0)
	var direction := intent.normalized() if strength > 0.001 else Vector3.ZERO
	var ratio := clampf(_speed / cruise_speed, 0.0, 1.0)
	var error := angle_difference(vessel.rotation.y, atan2(-direction.x, -direction.z)) if direction != Vector3.ZERO else 0.0
	if absf(absf(error) - PI) < 0.001:
		error = -PI if _turn_rate < 0.0 else PI
	var near_impact := _impact_position.is_finite() and vessel.global_position.distance_to(_impact_position) < EDGE_RELEASE_RANGE
	var berth_offset := berth - vessel.global_position
	var near_berth := berth.is_finite() and Vector2(berth_offset.x, berth_offset.z).length_squared() <= BERTH_SLOW_RANGE * BERTH_SLOW_RANGE
	var precise_turn := near_berth or near_impact
	var turn_speed: float = vessel.TURN_RATE if precise_turn else OPEN_TURN_RATE
	var turn_at_rest: float = vessel.TURN_AT_REST if precise_turn else OPEN_TURN_AT_REST
	var limit := turn_speed * lerpf(turn_at_rest, 1.0, ratio)
	var accel: float = vessel.TURN_ACCEL if precise_turn else OPEN_TURN_ACCEL
	if direction == Vector3.ZERO or near_berth or near_impact or absf(error) <= deg_to_rad(10.0):
		_cruise_turn = false
	elif ratio >= CRUISE_TURN_START_RATIO and absf(error) >= deg_to_rad(40.0):
		# Keep the quicker response through the turn, even while the hull brakes.
		_cruise_turn = true
	if _cruise_turn:
		limit = turn_speed * CRUISE_TURN_RATE_MULTIPLIER
		accel *= CRUISE_TURN_ACCEL_MULTIPLIER
	var target_rate := clampf(error * 5.0, -limit, limit)
	if _cruise_turn:
		# Shed angular velocity near the target so the faster turn can settle.
		target_rate = signf(error) * minf(absf(target_rate), sqrt(2.0 * accel * absf(error)))
	_turn_rate = move_toward(_turn_rate, target_rate, accel * delta)
	var turn_blocked := false
	if not is_zero_approx(_turn_rate):
		# Check intermediate orientations too: the quicker turn must not sample
		# rotation more coarsely than the original cruise turn at this tick rate.
		var angle := _turn_rate * delta
		var slices := maxi(1, ceili(absf(angle) / MAX_ROTATION_STEP))
		var pose: Transform3D = vessel.global_transform
		for i in range(1, slices + 1):
			pose = vessel.global_transform.rotated_local(Vector3.UP, angle * float(i) / slices)
			if overlaps_shore(pose):
				turn_blocked = true
				_turn_rate = 0.0
				_cruise_turn = false
				break
		if not turn_blocked:
			vessel.global_basis = pose.basis.orthonormalized()

	var bow: Vector3 = -vessel.global_basis.z
	var alignment := bow.dot(direction)
	var target := 0.0
	var heading := _travel_direction
	var releasing_edge := near_impact and direction != Vector3.ZERO and direction.dot(_impact_direction) < 0.10
	var propulsion_dot := 0.97 if precise_turn else 0.90
	if _cruise_turn:
		propulsion_dot = CRUISE_TURN_PROPULSION_DOT
	if direction.dot(_escape_heading) < 0.99 or alignment > propulsion_dot:
		_escape_heading = Vector3.ZERO
	if turn_blocked:
		_escape_heading = direction
	var escaping := _escape_heading != Vector3.ZERO
	power_rowing = power and direction != Vector3.ZERO and not precise_turn and not escaping
	var drive_speed := cruise_speed * (POWER_SPEED_MULTIPLIER if power_rowing else 1.0)
	if releasing_edge or escaping:
		# Free the hull with a short translation when its bow cannot swing.
		target = minf(cruise_speed, EDGE_RELEASE_SPEED) * strength
		heading = direction
		_speed = minf(_speed, EDGE_RELEASE_SPEED)
	elif alignment > propulsion_dot:
		target = drive_speed * strength * alignment * alignment
		heading = bow
	var berth_limit := _approach_speed(direction, berth, cruise_speed, drive_speed)
	target = minf(target, berth_limit * strength)
	var rate: float = vessel.ACCEL * (POWER_ACCEL_MULTIPLIER if power_rowing else 1.0) if target > _speed else vessel.BRAKE * lerpf(vessel.BRAKE_TAIL, 1.0, ratio)
	if berth_limit < drive_speed and _speed > target:
		rate = vessel.BRAKE
	# Repeated contact while steering out of a corner must not restart the
	# acceleration ramp every frame. The short escape step is swept below.
	_speed = target if escaping else move_toward(_speed, target, rate * delta)
	if _speed < 0.02 and is_zero_approx(target):
		_speed = 0.0
	_travel_direction = heading
	var before: Vector3 = vessel.global_position
	_last_contact = null
	if _speed > 0.0:
		_move_hull(_travel_direction * _speed * delta, direction, delta, escaping)
	vessel.velocity = (vessel.global_position - before) / delta

func _move_hull(step: Vector3, direction: Vector3, delta: float, freeing_turn: bool) -> void:
	var margin := EDGE_SWEEP_MARGIN if freeing_turn else vessel.safe_margin
	var hit: KinematicCollision3D = vessel.move_and_collide(step, true, margin)
	_last_contact = hit.get_collider() if hit != null else _overlap_at(vessel.global_transform.translated(step))
	if not is_instance_valid(_last_contact):
		vessel.move_and_collide(step, false, margin)
		return
	_impact_position = vessel.global_position
	_impact_direction = step.normalized()
	power_rowing = false
	_speed = 0.0
	if direction == Vector3.ZERO:
		return
	var slide_distance := minf(step.length(), EDGE_RELEASE_SPEED * delta)
	if freeing_turn:
		# A diagonal request may be clear on one axis even at a corner where
		# the first contact normal points into the other wall.
		var x := Vector3(direction.x, 0, 0)
		var z := Vector3(0, 0, direction.z)
		var first := x if absf(direction.x) >= absf(direction.z) else z
		var second := direction - first
		if _try_slide(first * slide_distance, delta) or _try_slide(second * slide_distance, delta):
			return
	if hit == null:
		return
	var normal := hit.get_normal().slide(Vector3.UP).normalized()
	if normal.is_zero_approx():
		return
	# Give the requested heading priority when it opens clearance. Otherwise
	# keep its tangent component and a small separation from the contacted wall.
	var slide := direction
	var outward := direction.dot(normal)
	if outward <= 0.0:
		slide = direction.slide(normal)
		if slide.length_squared() < 0.01:
			return
		slide += normal * 0.12
	_try_slide(slide.limit_length() * slide_distance, delta)

func _try_slide(step: Vector3, delta: float) -> bool:
	if step.length_squared() < 0.00000001:
		return false
	if vessel.test_move(vessel.global_transform, step, null, EDGE_SWEEP_MARGIN) or overlaps_shore(vessel.global_transform.translated(step)):
		return false
	vessel.move_and_collide(step, false, EDGE_SWEEP_MARGIN)
	_speed = step.length() / delta
	_travel_direction = step.normalized()
	return true

func _approach_speed(direction: Vector3, berth: Vector3, cruise_speed: float, drive_speed: float) -> float:
	if direction == Vector3.ZERO or not berth.is_finite(): return drive_speed
	var to_berth: Vector3 = berth - vessel.global_position
	to_berth.y = 0.0
	var distance := to_berth.length()
	var base_limit := cruise_speed
	if distance <= 0.08 or direction.dot(to_berth) > distance * 0.35:
		base_limit = lerpf(minf(cruise_speed, BERTH_ENTRY_SPEED), cruise_speed, smoothstep(0.95, BERTH_SLOW_RANGE, distance))
	return base_limit + (drive_speed - cruise_speed) * smoothstep(BERTH_SLOW_RANGE, POWER_BERTH_SLOW_RANGE, distance)

func _overlap_at(pose: Transform3D) -> Object:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = pose * hull.transform
	query.collision_mask = vessel.collision_mask
	query.exclude = [vessel.get_rid()]
	var bodies := vessel.get_world_3d().direct_space_state.intersect_shape(query, 1)
	return null if bodies.is_empty() else bodies[0].collider

func overlaps_shore(pose: Transform3D) -> bool:
	return is_instance_valid(_overlap_at(pose))

func is_still() -> bool:
	return absf(_speed) < 0.02 and absf(_turn_rate) < 0.02 and vessel.velocity.length() < 0.02

func shore_contact() -> Object:
	return _last_contact if is_instance_valid(_last_contact) else null

