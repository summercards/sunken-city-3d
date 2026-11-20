extends Node3D
## Owns the one land/boat handoff. The legacy bootstrap is not loaded.
const Skiff = preload("res://src/navigation/minimal_skiff.gd")
const Walker = preload("res://src/player/minimal_walker.gd")

@export_range(0.1, 3.0, 0.05) var approach_radius := 0.85
@export_range(0.1, 2.0, 0.05) var mooring_radius := 0.95
@export_range(1.0, 89.0, 1.0) var mooring_angle_deg := 24.0
@export_range(0.1, 5.0, 0.05) var max_transfer_gap := 3.6
@export_range(0.1, 2.0, 0.05) var max_transfer_rise := 0.75
@onready var _camera: OrbitCam = $Camera
@onready var _player: Walker = $Player
@onready var _boat: Skiff = $Boat
@onready var _dock: StaticBody3D = $Ramp
@onready var _shore: Marker3D = $Ramp/Berth/Shore
@onready var _park: Marker3D = $Ramp/Berth/BoatPark
@onready var _sign: Label3D = $Ramp/Berth/BerthSign
@onready var _status: Label = $Controls/Hint

enum BerthStatus { READY, APPROACH_SHORE, STAND_ON_DOCK, APPROACH_WATER, STOP, ALIGN, BLOCKED, UNSAFE_LANDING }
const READY_COLOR := Color("fff3c6")
const LOCATION_COLOR := Color("9cf5ef")

class BerthCheck:
	var status: BerthStatus
	var landing: Vector3

	func _init(value: BerthStatus, feet := Vector3.INF) -> void:
		status = value
		landing = feet

var _aboard := false
var _request := false
var _wait_for_neutral := false
var _focused := true
var _land_pan_bounds: Rect2

func _ready() -> void:
	_land_pan_bounds = _camera.pan_bounds
	_player.rowing_query = _boat.rowing_state
	_player.rowing_pose_query = _boat.rowing_pose
	_camera.restore_follow(_player)
	get_window().focus_exited.connect(_on_focus_exited)
	get_window().focus_entered.connect(func() -> void: _focused = true)

func aboard() -> bool:
	return _aboard

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not _focused:
		return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	match key:
		KEY_E: _request = true
		KEY_F: _camera.restore_follow(_subject())
		_: return
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	var axis := Input.get_vector(&"minimal_left", &"minimal_right", &"minimal_forward", &"minimal_back")
	var movement_held := (
		Input.is_action_pressed(&"minimal_left") or Input.is_action_pressed(&"minimal_right")
		or Input.is_action_pressed(&"minimal_forward") or Input.is_action_pressed(&"minimal_back")
		or Input.is_action_pressed(&"minimal_sprint"))
	if _wait_for_neutral and not movement_held:
		_wait_for_neutral = false
	if _request:
		_request = false
		_try_transfer()
	var accept_motion := _focused and not _wait_for_neutral
	_player.accept_input = accept_motion
	if _aboard:
		# Same horizontal screen basis as the walker. A key denotes a world
		# direction, not a rudder angle or reverse throttle relative to the hull.
		var forward := -_camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var intent := forward.cross(Vector3.UP) * axis.x - forward * axis.y
		_boat.advance(intent if accept_motion else Vector3.ZERO, delta, _park)
	_update_hint(_check_berth().status)

func _try_transfer() -> void:
	# Use the very same query as the live hint. Reject before mutating either
	# transform, collision mode or follow target, and use this check's landing.
	var result := _check_berth()
	if result.status != BerthStatus.READY:
		return
	var landing := result.landing
	if _aboard:
		_player.reparent(self, false)
		_player.global_transform = Transform3D(_shore.global_basis.orthonormalized(), landing)
		_player.set_boat_seated(false)
		_player.set_grounded_motion(true)
		_player.set_physics_process(true)
	else:
		_player.set_physics_process(false)
		_player.set_grounded_motion(false)
		_player.set_walking(false)
		_player.walk_speed_ratio = 0.0
		_player.reparent(_boat.seat, false)
		_player.transform = Transform3D.IDENTITY
		_player.set_boat_seated(true)
	_aboard = not _aboard
	_player.reset_physics_interpolation()
	_wait_for_neutral = true
	# Don't clamp a following boat to the old land observation rectangle.
	_camera.pan_bounds = Rect2() if _aboard else _land_pan_bounds
	_camera.follow_subject = _subject()
	# resume_follow clears pan but does not release OrbitCam's orbit button.
	_camera.rotating = false
	_camera.resume_follow()

func _check_berth() -> BerthCheck:
	if not _aboard:
		if _player.global_position.distance_to(_shore.global_position) > approach_radius:
			return BerthCheck.new(BerthStatus.APPROACH_SHORE)
		if not _player.is_on_floor() or _support_at(_player.global_position).get("collider") != _dock:
			return BerthCheck.new(BerthStatus.STAND_ON_DOCK)
	var offset := _boat.global_position - _park.global_position
	if Vector2(offset.x, offset.z).length() > mooring_radius:
		return BerthCheck.new(BerthStatus.APPROACH_WATER)
	if not _boat.is_still():
		return BerthCheck.new(BerthStatus.STOP)
	var alignment := absf(_boat.global_basis.z.dot(_park.global_basis.z.normalized()))
	if alignment < cos(deg_to_rad(mooring_angle_deg)):
		return BerthCheck.new(BerthStatus.ALIGN)
	if _boat.overlaps_shore(_boat.global_transform):
		return BerthCheck.new(BerthStatus.BLOCKED)
	var landing := _safe_landing()
	if not landing.is_finite():
		return BerthCheck.new(BerthStatus.UNSAFE_LANDING)
	return BerthCheck.new(BerthStatus.READY, landing)

func _safe_landing() -> Vector3:
	var anchor := _shore.global_position
	var gap := _boat.seat.global_position - anchor
	if Vector2(gap.x, gap.z).length() > max_transfer_gap or absf(gap.y) > max_transfer_rise:
		return Vector3.INF
	var collider: CollisionShape3D = _player.get_node("BodyCollision")
	var capsule := collider.shape as CapsuleShape3D
	var space := get_world_3d().direct_space_state
	# Check support under the entire landing footprint, not just a valid ray
	# far below the marker or one point on the lip. Require this pier's apron.
	var support := Vector3.INF
	for side in [Vector3.ZERO, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var sample: Vector3 = anchor + side * capsule.radius
		var hit := _support_at(sample)
		if hit.is_empty() or hit.collider != _dock or hit.normal.dot(Vector3.UP) < 0.95:
			return Vector3.INF
		if not support.is_finite():
			support = hit.position
		elif absf(hit.position.y - support.y) > 0.035:
			return Vector3.INF
	if support.y <= _boat.global_position.y:
		return Vector3.INF
	var feet := support + Vector3.UP * 0.012
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(_shore.global_basis.orthonormalized(), feet) * collider.transform
	# Probe the disabled player's capsule explicitly; the ordinary player mask
	# is zero on board. Also reject another actor standing in the landing space.
	query.collision_mask = Walker.GROUND_LAYER | Walker.ACTOR_LAYER
	query.exclude = [_player.get_rid()]
	return feet if space.intersect_shape(query, 1).is_empty() else Vector3.INF

func _support_at(sample: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 0.16, sample - Vector3.UP * 0.16, Walker.GROUND_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(ray)

func _subject() -> Node3D:
	return _boat if _aboard else _player

func _update_hint(state: BerthStatus) -> void:
	var action := "E 上岸" if _aboard else "E 上船"
	var message := ""
	match state:
		BerthStatus.READY: message = action
		BerthStatus.APPROACH_SHORE: message = "走近坡脚的泊位标记"
		BerthStatus.STAND_ON_DOCK: message = "请站稳在坡脚甲板上"
		BerthStatus.APPROACH_WATER: message = "划近泊位，沿甲板边停靠" if _aboard else "小船不在泊位，暂不能上船"
		BerthStatus.STOP: message = "松开方向键，等船停稳" if _aboard else "等小船停稳"
		BerthStatus.ALIGN: message = "让船身与甲板边平行" if _aboard else "船身还未对齐泊位"
		BerthStatus.BLOCKED: message = "船身被挡，请挪到有净空的位置" if _aboard else "泊位船身被挡"
		BerthStatus.UNSAFE_LANDING: message = "岸上落脚点不安全"
	var ready := state == BerthStatus.READY
	var sign_text := "泊位\n" + action if ready else "泊位"
	if _sign.text != sign_text:
		_sign.text = sign_text
		_sign.modulate = READY_COLOR if ready else LOCATION_COLOR
	var hint_text := "泊位 · " + message
	if _status.text != hint_text:
		_status.text = hint_text

func _on_focus_exited() -> void:
	_focused = false
	_request = false
	_wait_for_neutral = true
	_camera.rotating = false
	if _camera.panning:
		_camera.restore_follow(_subject())
