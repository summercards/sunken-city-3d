extends "res://src/player/character.gd"
## Standalone land controller: no ActorController, WalkArea, or gameplay services.
const Feel = preload("res://src/player/actions/free_walk_action.gd")

@export var view: Camera3D
@export var reset_below_y := -3.0
var accept_input := true
var _spawn: Transform3D

func _ready() -> void:
	super._ready()
	set_grounded_motion(true)
	# The legacy motor sweeps custom displacements; the native slide solver
	# needs its own recovery margin on the convex ramp.
	safe_margin = 0.002
	floor_constant_speed = false
	build()
	walk_phase_scale = 2.2
	_spawn = global_transform

func _physics_process(delta: float) -> void:
	var axis := Input.get_vector(&"minimal_left", &"minimal_right", &"minimal_forward", &"minimal_back") if accept_input else Vector2.ZERO
	var forward := -view.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var intent := forward.cross(Vector3.UP) * axis.x - forward * axis.y
	var sprint := accept_input and Input.is_action_pressed(&"minimal_sprint")
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var alignment := 1.0
	if horizontal.length() > 0.20:
		alignment = lerpf(Feel.REVERSE_FLOOR, 1.0, (horizontal.normalized().dot(intent.normalized()) + 1.0) * 0.5)
	var target := intent * Feel.SPEED * (Feel.SPRINT_MULTIPLIER if sprint else 1.0) * alignment
	var tau := Feel.ACCEL_TAU if axis != Vector2.ZERO else Feel.DECEL_TAU
	horizontal = horizontal.lerp(target, 1.0 - exp(-delta / tau))
	if axis == Vector2.ZERO and horizontal.length() < Feel.STOP_SPEED:
		horizontal = Vector3.ZERO
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = minf(velocity.y, 0.0) - GRAVITY * delta
	move_and_slide()

	var actual := get_real_velocity()
	actual.y = 0.0
	var speed := actual.length()
	var facing := actual if speed > Feel.FACING_MIN_SPEED else intent
	if facing.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-delta / Feel.FACING_TAU))
	var walking := is_on_floor() and speed > Feel.STOP_SPEED
	walk_speed_ratio = clampf(speed / Feel.SPEED, 0.0, 1.5) if walking else 0.0
	set_walking(walking)
	set_sprinting(walking and sprint)

	# Open edges are not invisible walls; return to the apron after a fall.
	if global_position.y < reset_below_y:
		global_transform = _spawn
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		view.restore_follow(self)
