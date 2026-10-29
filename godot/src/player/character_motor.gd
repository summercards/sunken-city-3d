extends CharacterBody3D
## SEA-MOVE: collision execution only. No input, animation, inventory or world rules.
const BODY_RADIUS := 0.22
const BODY_HEIGHT := 1.30
const GROUND_LAYER := 256
const ACTOR_LAYER := 512
const GRAVITY := 18.0
const SNAP := 0.16
var grounded_motion_enabled := false
var ground_contact := false
var _fall_speed := 0.0

func _ready() -> void:
	ensure_body()

func ensure_body() -> void:
	if get_node_or_null("BodyCollision") == null:
		var collider := CollisionShape3D.new()
		collider.name = "BodyCollision"
		var capsule := CapsuleShape3D.new()
		capsule.radius = BODY_RADIUS
		capsule.height = BODY_HEIGHT
		collider.shape = capsule
		collider.position.y = BODY_HEIGHT * 0.5
		add_child(collider)
	safe_margin = 0.0001
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = SNAP
	floor_constant_speed = true
	disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	_apply_motion_layers()

func set_grounded_motion(enabled: bool) -> void:
	grounded_motion_enabled = enabled
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	ground_contact = false
	_apply_motion_layers()

func _apply_motion_layers() -> void:
	collision_layer = ACTOR_LAYER if grounded_motion_enabled else 0
	collision_mask = GROUND_LAYER if grounded_motion_enabled else 0

## Explicit displacement keeps the existing speed independent of render rate.
## move_and_collide sweeps the actual capsule; there is no position-write fallback.
func move_ground(displacement: Vector3, delta: float) -> Dictionary:
	var before := global_position
	if not grounded_motion_enabled or not is_finite(delta) or delta <= 0.0 or not displacement.is_finite():
		return {"moved":Vector3.ZERO,"blocked":false,"grounded":ground_contact}
	var remaining := displacement
	var blocked := false
	for i in 4:
		if remaining.length_squared() < 0.000000001: break
		var hit := move_and_collide(remaining)
		if hit == null: break
		var normal := hit.get_normal()
		if normal.y < cos(floor_max_angle) and hit.get_remainder().length() > 0.001:
			blocked = true
		remaining = hit.get_remainder().slide(normal)
	# A short downward sweep follows the support surface and descending ramps.
	# Gravity is only accumulated when no support is found, never an inertia on XZ.
	var probe := Vector3.DOWN * maxf(SNAP, _fall_speed * delta)
	var support := move_and_collide(probe, true)
	ground_contact = support != null and support.get_normal().y >= cos(floor_max_angle)
	if ground_contact:
		move_and_collide(probe)
		_fall_speed = 0.0
	else:
		_fall_speed = minf(_fall_speed + GRAVITY * delta, 25.0)
		move_and_collide(Vector3.DOWN * _fall_speed * delta)
	var moved := global_position - before
	velocity = moved / delta
	return {"moved":moved,"blocked":blocked,"grounded":ground_contact}
