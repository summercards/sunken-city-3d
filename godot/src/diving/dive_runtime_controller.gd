extends Node3D
## SEA-DIVE：十张地图唯一的潜水状态/输入/运动意图/第三人称镜头/角色/氧气所有者。
## 地图只提供入口、碰撞、路线、环境和探索内容；海面 ActorController 不参与本运行时。
const Machine = preload("res://src/core/state_machine.gd")
const CharacterScript = preload("res://src/player/character.gd")
const AirScript = preload("res://src/diving/dive_air.gd")
const BreathBubbles = preload("res://src/ambient/diver_breath_bubbles.gd")
const CRUISE_SPEED := 4.2
const SPRINT_SPEED := 7.0
const FOV := 72.0
const SPRINT_FOV := 78.0
const ZOOM_MIN := 4.0
const ZOOM_MAX := 13.0
const ACCEL_TAU := 0.22
const BRAKE_TAU := 0.16
const TURN_TAU := 0.14
const INPUT_ACTIONS := {
	"dive_left": [KEY_A, KEY_LEFT], "dive_right": [KEY_D, KEY_RIGHT],
	"dive_forward": [KEY_W, KEY_UP], "dive_back": [KEY_S, KEY_DOWN],
	"dive_up": [KEY_E, KEY_SPACE], "dive_down": [KEY_Q, KEY_CTRL],
	"dive_sprint": [KEY_SHIFT]}

class DiveState extends RefCounted:
	var machine
	var _owner: WeakRef
	var context:
		get: return _owner.get_ref() if _owner != null else null
		set(value): _owner = weakref(value) if value != null else null
	var id: String
	func _init(value: String) -> void: id = value
	func enter(payload: Dictionary) -> void: context._state_enter(id, payload)
	func exit() -> void: pass
	func tick(dt: float) -> void: context._state_tick(id, dt)
	func handle(_event: String, _payload: Dictionary) -> bool: return false

var machine = Machine.new()
var character: Character
var breath_bubbles: Node3D
var velocity := Vector3.ZERO
var yaw := 0.0
## 正值是俯看；负值抬头。镜头永不滚转。
var pitch := 0.14
var distance := 7.5
var sprinting := false
var route: Array = []
var air = AirScript.new()
var map: Node3D
var camera: Camera3D
var _drag := false
var _left_pressed := false
var _left_origin := Vector2.ZERO
var _left_moved := false
var _session_started := false
var _air_emit := 0.0
var _root_height := -0.78
var _look_yaw := 0.0
var _look_pitch := 0.14
var _boom_length := 7.5
var _camera_target := Vector3.ZERO
var _last_subject := Vector3.ZERO
var _camera_valid := false
var _facing := 0.0
var _turn_ratio := 0.0
var _blocked_seconds := 0.0
var _test_input_enabled := false
var _test_axis := Vector3.ZERO
var _test_sprint := false
var motion := "悬浮"
## 只由 Session 控制过场冻结；默认 false 保持预览与旧测试行为。
var transition_frozen := false:
	set(value):
		transition_frozen = value
		if value: reset_pointer()

func _ready() -> void:
	ensure_input_actions()
	machine.configure(self, {
		"surface": DiveState.new("surface"), "enter": DiveState.new("enter"),
		"swim": DiveState.new("swim"), "exit": DiveState.new("exit")}, {
		"surface": ["enter"], "enter": ["swim", "exit"],
		"swim": ["exit"], "exit": ["surface"]}, "surface")

static func ensure_input_actions() -> void:
	for action in INPUT_ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for code in INPUT_ACTIONS[action]:
			var exists := false
			for event in InputMap.action_get_events(action):
				if event is InputEventKey and event.physical_keycode == code: exists = true
			if not exists:
				var key := InputEventKey.new()
				key.physical_keycode = code
				InputMap.action_add_event(action, key)

func configure(p_map: Node3D, p_camera: Camera3D, visual_parent: Node3D, visual_name: String) -> void:
	map = p_map
	camera = p_camera
	air = map.get("air")
	character = CharacterScript.new()
	character.name = visual_name
	visual_parent.add_child(character)
	character.build()
	character.set_grounded_motion(false)
	character.visible = false
	character.set_process(false)
	breath_bubbles = BreathBubbles.new()
	breath_bubbles.name = "DiverBreathBubbles"
	add_child(breath_bubbles)
	breath_bubbles.configure(character, float(map.call("dive_water_level")))
	camera.fov = FOV
	camera.near = 0.12
	yaw = camera.rotation.y

func begin(payload: Dictionary = {}) -> bool:
	if map == null or machine.current != "surface" or not air.can_dive(): return false
	# Rebind the session-injected model; maps may also be previewed without a session.
	air = map.get("air")
	_session_started = true
	route.clear()
	velocity = Vector3.ZERO
	sprinting = false
	_camera_valid = false
	_drag = false
	_left_pressed = false
	air.refill()
	map.call("dive_begin", payload)
	machine.change("enter", payload)
	_emit_air()
	return true

func request_surface() -> void:
	if machine.current in ["enter", "swim"]: machine.change("exit")

func cancel_navigation() -> void:
	route.clear()
	_blocked_seconds = 0.0
	if map != null: map.call("dive_cancel_content")

func swim_to(dest: Vector3) -> bool:
	if transition_frozen or machine.current != "swim" or not dest.is_finite(): return false
	var points: Array = map.call("dive_route", dest)
	if points.is_empty():
		_emit_message("前方没有安全路线，请换个目标或手动绕行")
		return false
	cancel_navigation()
	return navigate_path(points)

func navigate_path(points: Array) -> bool:
	if transition_frozen or machine.current != "swim" or points.is_empty(): return false
	for point in points:
		if not (point is Vector3) or not point.is_finite(): return false
	route = points.duplicate()
	_blocked_seconds = 0.0
	return true

func swim_to_screen(screen: Vector2) -> bool:
	if machine.current != "swim": return false
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var current := _map_position()
	var t := 22.0
	if absf(direction.y) > 0.01:
		var plane_t := (current.y - origin.y) / direction.y
		if plane_t > 0.0: t = minf(plane_t, 65.0)
	var destination := origin + direction * t
	if current.distance_to(destination) > 45.0:
		destination = current + (destination - current).normalized() * 45.0
	return swim_to(destination)

func debug_teleport(p: Vector3) -> void:
	if map == null or not p.is_finite(): return
	cancel_navigation()
	map.call("dive_set_position", p)
	velocity = Vector3.ZERO
	if machine.current != "swim": machine.change("swim", {}, true)
	update_character(0.0)
	update_camera(0.0, true)

## 同一个运动入口供真实 InputMap 与隔离固定步测试使用，不提供位置写入旁路。
func set_motion_input(axis: Vector3, fast := false) -> void:
	_test_input_enabled = true
	_test_axis = axis.limit_length(1.0)
	_test_sprint = fast

func clear_motion_input() -> void:
	_test_input_enabled = false
	_test_axis = Vector3.ZERO
	_test_sprint = false

func _motion_input() -> Vector3:
	if _test_input_enabled: return _test_axis
	if not _drag and get_viewport().gui_get_focus_owner() is LineEdit: return Vector3.ZERO
	return Vector3(Input.get_axis("dive_left", "dive_right"),
		Input.get_axis("dive_down", "dive_up"), Input.get_axis("dive_forward", "dive_back")).limit_length(1.0)

func step_swim(dt: float) -> void:
	if transition_frozen: return
	if machine.current != "swim" or map == null or dt <= 0.0 or not is_finite(dt): return
	if bool(map.get_meta("underwater_surface_debug_open", false)):
		cancel_navigation()
		velocity = Vector3.ZERO
		motion = "调试面板"
		update_character(0.0)
		return
	var axis := _motion_input()
	var desired := Vector3.ZERO
	sprinting = (_test_sprint if _test_input_enabled else Input.is_action_pressed("dive_sprint")) and axis.length_squared() > 0.001
	if axis.length_squared() > 0.001:
		cancel_navigation()
		var basis := camera.global_basis
		desired = basis * Vector3(axis.x, 0.0, axis.z) + Vector3.UP * axis.y
		desired = desired.limit_length(1.0) * (SPRINT_SPEED if sprinting else CRUISE_SPEED)
	elif not route.is_empty():
		var to_target: Vector3 = route[0] - _map_position()
		if to_target.length() <= 0.30:
			route.pop_front()
		else:
			desired = to_target.normalized() * minf(CRUISE_SPEED, to_target.length() * 2.4)
	var tau := ACCEL_TAU if desired.length_squared() > 0.001 else BRAKE_TAU
	if desired.dot(velocity) < 0.0: tau = 0.13
	velocity = velocity.lerp(desired, 1.0 - exp(-dt / tau))
	if desired == Vector3.ZERO and velocity.length() < 0.035: velocity = Vector3.ZERO
	var moved: Vector3 = map.call("dive_move", velocity * dt)
	velocity = moved / dt
	if not route.is_empty() and desired.length() > 0.5 and velocity.length() < 0.12:
		_blocked_seconds += dt
		if _blocked_seconds > 0.7:
			cancel_navigation()
			_emit_message("前方被挡住了，已停止自动游动")
	else:
		_blocked_seconds = 0.0
	_sync_depth()
	var event: String = air.update(dt, float(map.get("depth")), velocity.length() > 0.20, sprinting)
	if event == "empty":
		_emit_message("氧气耗尽 · 正在上浮")
		request_surface()
	elif event == "crit": _emit_message("氧气危急 · 请上浮返回海面")
	elif event == "low": _emit_message("余气不多了 · 注意返程")
	_air_emit -= dt
	if _air_emit <= 0.0:
		_air_emit = 0.15
		_emit_air()
	motion = "加速游动" if sprinting else ("自动游动" if not route.is_empty() else ("游动" if velocity.length() > 0.2 else "悬浮"))
	update_character(dt)

func update_character(dt: float) -> void:
	if character == null or map == null: return
	character.global_position = _map_position() + Vector3(0.0, _root_height, 0.0)
	var horizontal := Vector2(velocity.x, velocity.z)
	_turn_ratio = 0.0
	if horizontal.length() > 0.12:
		var wanted := atan2(velocity.x, velocity.z)
		var difference := wrapf(wanted - _facing, -PI, PI)
		_turn_ratio = clampf(difference / 0.8, -1.0, 1.0)
		_facing = lerp_angle(_facing, wanted, 1.0 if dt <= 0.0 else 1.0 - exp(-dt / TURN_TAU))
	character.rotation.y = _facing
	character.set_swim_motion(velocity.length() / CRUISE_SPEED,
		clampf(velocity.y / CRUISE_SPEED, -1.0, 1.0), _turn_ratio, sprinting)

func update_camera(dt: float, snap := false) -> void:
	if camera == null or map == null or machine.current == "surface": return
	var subject := _map_position()
	var k := 1.0 if snap or dt <= 0.0 else 1.0 - exp(-dt / 0.07)
	_look_yaw = lerp_angle(_look_yaw, yaw, k)
	_look_pitch = lerpf(_look_pitch, clampf(pitch, -1.1, 1.15), k)
	var forward := Vector3(-sin(_look_yaw), 0.0, -cos(_look_yaw))
	var lead := velocity.limit_length(CRUISE_SPEED) * 0.10
	var target := subject + Vector3.UP * 0.40 + lead
	if not _camera_valid or snap:
		_camera_target = target
		_boom_length = distance
		_camera_valid = true
	else:
		# 主体位移直接继承，阻尼仅吃掉前视/方向变化，不让镜头拖着追游泳者。
		_camera_target += subject - _last_subject
		_camera_target = _camera_target.lerp(target, 1.0 - exp(-dt / 0.16))
	_last_subject = subject
	var orbit := Vector3(-forward.x * cos(_look_pitch), sin(_look_pitch), -forward.z * cos(_look_pitch)).normalized()
	var desired := _camera_target + orbit * clampf(distance, ZOOM_MIN, ZOOM_MAX)
	desired.y = minf(desired.y, float(map.call("dive_water_level")) - 0.3)
	var safe: Vector3 = map.call("dive_camera_clip", _camera_target, desired, 0.32)
	var safe_length := _camera_target.distance_to(safe)
	# 贴墙立即收回；离墙缓出，任何插值后再复验，禁止镜头插值穿过障碍。
	_boom_length = safe_length if snap or safe_length < _boom_length else lerpf(_boom_length, safe_length, k)
	var pose := _camera_target + (_camera_target.direction_to(safe) * minf(_boom_length, safe_length))
	pose = map.call("dive_camera_clip", _camera_target, pose, 0.32)
	camera.global_position = pose
	if camera.global_position.distance_to(_camera_target) > 0.01: camera.look_at(_camera_target, Vector3.UP)
	camera.fov = lerpf(camera.fov, SPRINT_FOV if sprinting else FOV, k * 0.4 if not snap else 1.0)

func snapshot() -> Dictionary:
	return {"phase": machine.current, "motion": motion, "position": _map_position(),
		"velocity": velocity, "speed": velocity.length(), "speed_ratio": velocity.length() / CRUISE_SPEED,
		"yaw": yaw, "pitch": pitch, "distance": distance, "sprinting": sprinting,
		"navigation": not route.is_empty(), "route": route.duplicate(), "camera_fov": camera.fov if camera != null else FOV,
		"air": air.ratio(), "lamp": air.lamp, "state_owner": "shared_dive_runtime"}

func toggle_lamp() -> void:
	if transition_frozen: return
	air.lamp = not air.lamp
	_emit_message("头灯 " + ("开启" if air.lamp else "关闭"))
	_emit_air()

func reset_pointer() -> void:
	_drag = false
	_left_pressed = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: reset_pointer()

func _exit_tree() -> void:
	# Core FSM states hold machine references. Break the graph on map unload.
	for state in machine.states.values():
		state.machine = null
		state.context = null
	machine.states.clear()
	machine.context = null

func _physics_process(dt: float) -> void:
	if not Engine.is_editor_hint():
		machine.tick(minf(dt, 0.1))
		sample_effects(dt)

## Pure ambient presentation: does not advance FSM, motion or oxygen.
func sample_effects(dt: float) -> void:
	if transition_frozen or breath_bubbles == null or map == null: return
	breath_bubbles.update_breath(dt, machine.current in ["enter", "swim"],
		velocity.length() / CRUISE_SPEED, maxf(0.0, float(map.call("dive_water_level")) - _map_position().y))

func _process(dt: float) -> void:
	if not Engine.is_editor_hint() and machine.current != "surface": update_camera(dt)

func _unhandled_input(event: InputEvent) -> void:
	if transition_frozen or Engine.is_editor_hint() or machine.current != "swim": return
	if map != null and bool(map.get_meta("underwater_surface_debug_open", false)):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_origin = event.position
				_left_pressed = true
				_left_moved = false
			elif _left_pressed:
				_left_pressed = false
				if not _left_moved and event.position.distance_to(_left_origin) <= 8.0: swim_to_screen(event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance + (-0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
		else: return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _left_pressed and event.position.distance_to(_left_origin) > 8.0: _left_moved = true
		if _drag:
			yaw -= event.relative.x * 0.004
			pitch = clampf(pitch + event.relative.y * 0.003, -1.1, 1.15)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code == KEY_F: toggle_lamp()
		elif code == KEY_R:
			yaw = _facing + PI
			pitch = 0.14
		else: return
		get_viewport().set_input_as_handled()

func _state_enter(id: String, _payload: Dictionary) -> void:
	match id:
		"surface":
			velocity = Vector3.ZERO
			sprinting = false
			reset_pointer()
			if character != null:
				character.set_diving(false)
				character.visible = false
				character.set_process(false)
			if _session_started:
				_session_started = false
				map.call("dive_end")
		"enter":
			character.set_diving(true)
			character.visible = true
			character.set_process(true)
			_facing = yaw + PI
			update_character(0.0)
			update_camera(0.0, true)
		"swim":
			if velocity.length_squared() < 0.01: _facing = yaw + PI
			update_character(0.0)
			update_camera(0.0, true)
		"exit":
			cancel_navigation()
			reset_pointer()
			map.call("dive_exit_begin")
			# Production session starts its iris immediately for manual/oxygen exit.
			# Low-level preview/test maps without a session retain the normal exit action.
			if map.has_meta("request_surface_transition"):
				var transition: Callable = map.get_meta("request_surface_transition")
				if transition.is_valid(): transition.call()

func _state_tick(id: String, dt: float) -> void:
	if map == null: return
	if transition_frozen and id != "enter": return
	match id:
		"enter":
			if bool(map.call("dive_entry_tick", dt)): machine.change("swim")
			_sync_depth()
			update_character(dt)
			map.call("dive_content_tick", 0.0)
		"swim":
			step_swim(dt)
			map.call("dive_content_tick", dt)
		"exit":
			var before := _map_position()
			var done: bool = map.call("dive_exit_tick", dt)
			velocity = (_map_position() - before) / maxf(dt, 0.001)
			_sync_depth()
			update_character(dt)
			map.call("dive_content_tick", 0.0)
			if done: machine.change("surface")

func _sync_depth() -> void:
	map.set("depth", maxf(0.0, float(map.call("dive_water_level")) - _map_position().y))

func _map_position() -> Vector3:
	return map.call("dive_position") if map != null else Vector3.ZERO

func _emit_air() -> void:
	if map != null:
		map.emit_signal("air_changed", air.ratio(), air.lamp, int(map.call("discovered_count")), int(map.call("chest_count")))

func _emit_message(text: String) -> void:
	if map != null: map.emit_signal("message", text)
