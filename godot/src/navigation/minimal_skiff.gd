extends CharacterBody3D
## The minimal scene's native water motor. ReferenceSkiff is presentation only;
## the hull proxy stays at the mean waterline and uses the real dock solids.
const LegacyTuning = preload("res://src/navigation/boat.gd")
const RowingRig = preload("res://src/player/animation/rowing_rig.gd")
const EDGE_RELEASE_SPEED := 1.4
const EDGE_RELEASE_RANGE := 1.8
const BERTH_ENTRY_SPEED := 0.8
const BERTH_SLOW_RANGE := 3.0
const CRUISE_TURN_START_RATIO := 0.72
const CRUISE_TURN_RATE_MULTIPLIER := 2.15
const CRUISE_TURN_ACCEL_MULTIPLIER := 3.8
const CRUISE_TURN_PROPULSION_DOT := 0.65

@export var water: MeshInstance3D
@export_range(0.1, 8.0, 0.1) var cruise_speed := LegacyTuning.SPEED
@export_range(0.1, 4.0, 0.1) var turn_speed := LegacyTuning.TURN_RATE
@onready var hull: CollisionShape3D = $HullCollision
@onready var model: Node3D = $Model
@onready var seat: Marker3D = $Model/RowingSeat
@onready var _left_oar: Node3D = $Model/OarL
@onready var _right_oar: Node3D = $Model/OarR

var _speed := 0.0
var _turn_rate := 0.0
var _row_state := Vector2.ZERO
var _last_contact: Object
var _blocked_intent := Vector3.ZERO
var _impact_position := Vector3.INF
var _impact_direction := Vector3.ZERO
var _travel_direction := Vector3.ZERO
var _cruise_turn := false

func _ready() -> void:
	# Initial horizontal placement and yaw are authored; the Ocean owns sea level.
	global_position.y = water.global_position.y

func advance(intent: Vector3, delta: float, berth: Marker3D) -> void:
	var strength := minf(intent.length(), 1.0)
	var direction := intent.normalized() if strength > 0.001 else Vector3.ZERO
	var ratio := clampf(_speed / cruise_speed, 0.0, 1.0)
	var limit := turn_speed * lerpf(LegacyTuning.TURN_AT_REST, 1.0, ratio)
	var accel := LegacyTuning.TURN_ACCEL
	var error := angle_difference(rotation.y, atan2(-direction.x, -direction.z)) if direction != Vector3.ZERO else 0.0
	if absf(absf(error) - PI) < 0.001:
		error = -PI if _turn_rate < 0.0 else PI
	var near_impact := _impact_position.is_finite() and global_position.distance_to(_impact_position) < EDGE_RELEASE_RANGE
	var berth_offset := berth.global_position - global_position
	var near_berth := Vector2(berth_offset.x, berth_offset.z).length_squared() <= BERTH_SLOW_RANGE * BERTH_SLOW_RANGE
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
		var slices := maxi(1, ceili(absf(_turn_rate) / turn_speed))
		var pose := global_transform
		for i in range(1, slices + 1):
			pose = global_transform.rotated_local(Vector3.UP, angle * float(i) / slices)
			if overlaps_shore(pose):
				turn_blocked = true
				_turn_rate = 0.0
				_cruise_turn = false
				break
		if not turn_blocked:
			global_basis = pose.basis.orthonormalized()

	if direction == Vector3.ZERO or direction.dot(_blocked_intent) < 0.999:
		_blocked_intent = Vector3.ZERO
	if _blocked_intent != Vector3.ZERO:
		velocity = Vector3.ZERO
		return

	var bow := -global_basis.z
	var alignment := bow.dot(direction)
	var target := 0.0
	var heading := _travel_direction
	var releasing_edge := near_impact and direction != Vector3.ZERO and direction.dot(_impact_direction) < 0.10
	var propulsion_dot := CRUISE_TURN_PROPULSION_DOT if _cruise_turn else 0.97
	if alignment > propulsion_dot:
		target = cruise_speed * strength * alignment * alignment
		heading = bow
	elif releasing_edge or (turn_blocked and absf(error) > 0.20):
		# Respond to an explicitly changed direction without waiting for the
		# entire turn. The low-speed step still uses the hull sweep below.
		target = minf(cruise_speed, EDGE_RELEASE_SPEED) * strength
		heading = direction
	var berth_limit := _approach_speed(direction, berth)
	target = minf(target, berth_limit * strength)
	var rate := LegacyTuning.ACCEL if target > _speed else LegacyTuning.BRAKE * lerpf(LegacyTuning.BRAKE_TAIL, 1.0, ratio)
	if berth_limit < cruise_speed and _speed > target:
		rate = LegacyTuning.BRAKE
	_speed = move_toward(_speed, target, rate * delta)
	if _speed < 0.02 and is_zero_approx(target):
		_speed = 0.0
	_travel_direction = heading
	var before := global_position
	_last_contact = null
	if _speed > 0.0:
		var step := _travel_direction * _speed * delta
		# Test before committing. Applying Godot's collision recovery every tick
		# against an oblique corner can creep sideways despite zero throttle speed.
		var hit := move_and_collide(step, true, safe_margin)
		var contact := hit.get_collider() if hit != null else _overlap_at(global_transform.translated(step))
		if is_instance_valid(contact):
			_last_contact = contact
			_blocked_intent = direction
			_impact_position = global_position
			_impact_direction = heading
			_speed = 0.0
		else:
			move_and_collide(step, false, safe_margin)
	velocity = (global_position - before) / delta

func _approach_speed(direction: Vector3, berth: Marker3D) -> float:
	if direction == Vector3.ZERO:
		return cruise_speed
	var to_berth := berth.global_position - global_position
	to_berth.y = 0.0
	var distance := to_berth.length()
	var axis := berth.global_basis.z
	axis.y = 0.0
	if distance >= BERTH_SLOW_RANGE or direction.dot(to_berth) <= distance * 0.35 \
			or absf(axis.normalized().dot(direction)) < cos(deg_to_rad(28.0)):
		return cruise_speed
	# A speed ceiling only: never steer, pull the hull to the marker, or move
	# it when input is released. Blend out smoothly toward open water.
	return lerpf(minf(cruise_speed, BERTH_ENTRY_SPEED), cruise_speed,
		smoothstep(0.95, BERTH_SLOW_RANGE, distance))

func _overlap_at(pose: Transform3D) -> Object:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = pose * hull.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var bodies := get_world_3d().direct_space_state.intersect_shape(query, 1)
	return null if bodies.is_empty() else bodies[0].collider

func overlaps_shore(pose: Transform3D) -> bool:
	return is_instance_valid(_overlap_at(pose))

func is_still() -> bool:
	return absf(_speed) < 0.02 and absf(_turn_rate) < 0.02 and velocity.length() < 0.02

func shore_contact() -> Object:
	return _last_contact if is_instance_valid(_last_contact) else null

func _physics_process(delta: float) -> void:
	# Use the same live height samples as the rendered water. Only the visual
	# rig (including the rider's seat) rocks; the planar hull cannot ride over a wall.
	var center := Vector2(global_position.x, global_position.z)
	var forward := Vector2(-global_basis.z.x, -global_basis.z.z)
	var side := Vector2(global_basis.x.x, global_basis.x.z)
	var bow: Vector3 = water.sample_surface(center + forward * 2.0)
	var stern: Vector3 = water.sample_surface(center - forward * 2.0)
	var port: Vector3 = water.sample_surface(center - side)
	var starboard: Vector3 = water.sample_surface(center + side)
	var response := 1.0 - exp(-5.0 * delta)
	model.position.y = lerpf(model.position.y, (bow.x + stern.x + port.x + starboard.x) * 0.25, response)
	model.rotation.x = lerpf(model.rotation.x, atan2(bow.x - stern.x, 4.0), response)
	model.rotation.z = lerpf(model.rotation.z, atan2(starboard.x - port.x, 2.0), response)

	var turn := clampf(_turn_rate / turn_speed, -1.0, 1.0)
	var effort := clampf(maxf(absf(_speed) / cruise_speed, 0.45 * absf(turn)), 0.0, 1.0)
	_row_state = RowingRig.sample_oars(_left_oar, _right_oar, _row_state, effort, turn, delta)

func rowing_state() -> Vector2:
	return _row_state

func rowing_pose() -> Dictionary:
	return RowingRig.contacts(seat, _left_oar, _right_oar)
