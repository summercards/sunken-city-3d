extends SceneTree
## 仅在 run_verification.py 创建的工程副本运行；不实例化 Main，不访问存档。
## 固定步运动与真实物理提交分离；真实渲染只输出单图，不做截图对比。
const Shared = preload("res://src/diving/dive_runtime_controller.gd")
const Machine = preload("res://src/core/state_machine.gd")
const Catalog = preload("res://src/diving/dive_map_catalog.gd")
const DT := 1.0 / 60.0
const REPORT_PATH := "res://outputs/dive-control-report.json"
const STATES := ["surface", "enter", "swim", "exit"]
const EDGES := {"surface": ["enter"], "enter": ["swim", "exit"], "swim": ["exit"], "exit": ["surface"]}
const BINDINGS := {
	"dive_left": [KEY_A, KEY_LEFT], "dive_right": [KEY_D, KEY_RIGHT],
	"dive_forward": [KEY_W, KEY_UP], "dive_back": [KEY_S, KEY_DOWN],
	"dive_up": [KEY_E, KEY_SPACE], "dive_down": [KEY_Q, KEY_CTRL],
	"dive_sprint": [KEY_SHIFT]}

var checks := 0
var failures := 0
var report := {"test": "dive-control", "fixed_dt": DT, "maps": {}, "legacy_maps": {},
	"failure_labels": [], "renders": [], "isolation": "harness 工程副本；无 Main、无存档读写"}

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		report.failure_labels.append(label)
		printerr("[dive-control] FAIL ", label)

func v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func freeze(runtime) -> void:
	runtime.set_physics_process(false)
	runtime.set_process(false)
	runtime.character.set_process(false)
	runtime.reset_pointer()

func step(runtime, count := 1, dt := DT) -> void:
	for _i in count:
		runtime.machine.tick(dt)
		runtime.update_camera(dt)
		runtime.character._process(dt)

func position(runtime) -> Vector3:
	return runtime.map.dive_position()

func speed(runtime) -> float:
	return runtime.velocity.length()

func reset(runtime, point: Vector3) -> void:
	for action in BINDINGS:
		Input.action_release(action)
	runtime.clear_motion_input()
	runtime.reset_pointer()
	runtime.debug_teleport(point)
	runtime.yaw = 0.0
	runtime.pitch = 0.0
	runtime.distance = 7.5
	runtime.sprinting = false
	runtime.air.refill()
	runtime.update_camera(0.0, true)
	step(runtime, 90)

func button(runtime, code: MouseButton, pressed: bool, at := Vector2.ZERO) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = code
	event.pressed = pressed
	event.position = at
	runtime._unhandled_input(event)

func mouse(runtime, relative: Vector2, at := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = at
	runtime._unhandled_input(event)

func sphere_query(point: Vector3, radius: float) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	return query

func sphere_clear(map, point: Vector3, radius: float) -> bool:
	return map.get_world_3d().direct_space_state.intersect_shape(sphere_query(point, radius), 1).is_empty()

func capsule_clear(map, point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	return map.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func shared_contract(map, id: String) -> bool:
	var runtime = map.dive_controller
	check(runtime != null, id + "：存在潜水控制器")
	if runtime == null:
		return false
	check(runtime.get_script() == Shared, id + "：使用 shared controller script")
	check(runtime.machine.get_script() == Machine, id + "：使用同一 machine class")
	var keys: Array = runtime.machine.states.keys()
	keys.sort()
	var required := STATES.duplicate()
	required.sort()
	check(keys == required and runtime.machine.edges == EDGES, id + "：同样四个状态和合法边")
	var shared_states := true
	for state in runtime.machine.states.values():
		shared_states = shared_states and state is Shared.DiveState and state.context == runtime and state.machine == runtime.machine
	check(shared_states and runtime.machine.context == runtime, id + "：状态对象及 context 唯一归属 shared controller")
	check(map.phase_machine == runtime.machine and map._compat_phase_machine.current.is_empty()
		and map._compat_phase_machine.states.is_empty(), id + "：旧 phase machine 没有运行状态或 action owner")
	var owners := 0
	var retired := []
	var stack: Array = [map]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_script() == Shared:
			owners += 1
		if node.get_script() != null:
			var path: String = node.get_script().resource_path
			if path in ["res://src/diving/actions/enter_action.gd", "res://src/diving/actions/surface_action.gd",
				"res://src/diving/actions/swim_action.gd", "res://src/diving/actions/camera_action.gd",
				"res://src/diving/actions/diver_pose_action.gd", "res://src/diving/actions/finish_exit_action.gd"]:
				retired.append(str(node.get_path()))
		stack.append_array(node.get_children())
	check(owners == 1 and retired.is_empty(), id + "：无旧 phase action 节点或重复 controller")
	check(is_equal_approx(runtime.camera.fov, 72.0), id + "：实际相机 FOV72")
	check(runtime.air == map.air, id + "：氧气实例与地图相同")
	return true

func test_input_map() -> void:
	# 不在测试里补绑按键：必须由正式控制器的 _ready 建立。
	for action in BINDINGS:
		check(InputMap.has_action(action), "InputMap：" + action)
		if not InputMap.has_action(action):
			continue
		for code in BINDINGS[action]:
			var exists := false
			for event in InputMap.action_get_events(action):
				if event is InputEventKey and event.physical_keycode == code:
					exists = true
			check(exists, "%s：物理按键 %s" % [action, OS.get_keycode_string(code)])

func old_map(id: String):
	var entry: Dictionary = Catalog.get_map(id)
	var packed := load(str(entry.scene_path)) as PackedScene
	check(packed != null, id + "：场景可加载")
	if packed == null:
		return null
	var map = packed.instantiate()
	root.add_child(map)
	current_scene = map
	map.set_process(false)
	map.set_physics_process(false)
	var setup_ok: bool = map.setup([], map.get_node("WorldEnvironment"))
	check(setup_ok, id + "：root.add_child 后 setup([], env)")
	if not setup_ok or not shared_contract(map, id):
		map.free()
		return null
	var runtime = map.dive_controller
	freeze(runtime)
	check(not runtime.machine.change("swim") and runtime.machine.current == "surface", id + "：拒绝 surface→swim")
	check(not runtime.machine.change("exit") and runtime.machine.current == "surface", id + "：拒绝 surface→exit")
	check(runtime.begin({"zone": id}) and runtime.machine.current == "enter", id + "：合法 surface→enter")
	check(not runtime.begin(), id + "：重复 begin 被拒绝")
	runtime.machine.tick(map.ENTER_TIME)
	runtime.character.set_process(false)
	check(runtime.machine.current == "swim" and map.phase == "swim", id + "：ENTER_TIME 固定步进入 swim")
	check(not runtime.machine.change("surface") and runtime.machine.current == "swim", id + "：拒绝 swim→surface")
	check(not runtime.machine.change("missing") and runtime.machine.current == "swim", id + "：拒绝不存在状态")
	report.legacy_maps[id] = {"script": runtime.get_script().resource_path,
		"machine": runtime.machine.get_script().resource_path, "states": runtime.machine.states.keys(),
		"fov": runtime.camera.fov, "air_shared": runtime.air == map.air}
	return map

func finish_map(map, id: String) -> void:
	var runtime = map.dive_controller
	var events := []
	map.exited.connect(func(): events.append("end"))
	runtime.request_surface()
	check(runtime.machine.current == "exit", id + "：合法 swim→exit")
	check(not runtime.machine.change("swim") and runtime.machine.current == "exit", id + "：拒绝 exit→swim")
	for _i in 240:
		step(runtime)
		if runtime.machine.current == "surface":
			break
	check(runtime.machine.current == "surface" and map.phase == "surface", id + "：合法 exit→surface")
	check(events.size() == 1 and not runtime.character.visible, id + "：dive_end 及 exited 仅发生一次")
	step(runtime, 5)
	check(events.size() == 1 and runtime.velocity == Vector3.ZERO, id + "：surface 不重复 end 且速度归零")
	check(not runtime.character.gear.visible and not runtime.character.mask.visible, id + "：返回后装备隐藏")
	if id == "home":
		check(not map._diving, "home：dive_end 清除潜水标记")
	else:
		check(not map.active, id + "：dive_end 清除 active")
	# machine.states 与 state.machine 是强引用环，夹具销毁前释放测试持有的FSM图。
	for state in runtime.machine.states.values():
		state.machine = null
		state.context = null
	runtime.machine.states.clear()
	runtime.machine.context = null
	current_scene = null
	root.remove_child(map)
	map.free()

func safe_test_origin(map, id: String) -> Vector3:
	if id == "zone1":
		var point := Vector3(0.0, -10.0, 12.0)
		check(not map.blocked(point), "zone1：固定步起点具有地图净空")
		return point
	# 从当前实景寻找足够宽的水域，不依赖 Base/Base2 的手摆坐标。
	var entry: Vector3 = map.dive_position()
	var offsets := [Vector2.ZERO, Vector2(35, 0), Vector2(-35, 0), Vector2(0, 35), Vector2(0, -35),
		Vector2(60, 60), Vector2(-60, 60), Vector2(60, -60), Vector2(-60, -60)]
	for y in [map.water_level - 15.0, map.water_level - 28.0, entry.y]:
		for offset in offsets:
			var point := Vector3(entry.x + offset.x, float(y), entry.z + offset.y)
			if map._dive_point_in_bounds(point) and capsule_clear(map, point) and sphere_clear(map, point, 17.0):
				check(true, "home：实际几何查询找到固定步净空水域")
				return point
	check(false, "home：实际几何查询找到固定步净空水域")
	return Vector3(NAN, NAN, NAN)

func test_motion(runtime, origin: Vector3, id: String, values: Dictionary) -> void:
	reset(runtime, origin)
	var before := position(runtime)
	Input.action_press("dive_forward")
	step(runtime, 12)
	Input.action_release("dive_forward")
	check(not runtime._drag and position(runtime).distance_to(before) > 0.10, id + "：Input.action_press 前进不需要右键")
	values.input_action_distance = position(runtime).distance_to(before)
	reset(runtime, origin)
	runtime.set_motion_input(Vector3(0, 0, -1), false)
	step(runtime)
	var first_speed := speed(runtime)
	step(runtime, 11)
	var early_speed := speed(runtime)
	var accel_distance := origin.distance_to(position(runtime))
	step(runtime, 108)
	var cruise := speed(runtime)
	check(first_speed > 0.10 and first_speed < 1.0 and early_speed > first_speed and early_speed < 4.1,
		id + "：巡航起步有可测加速过渡")
	check(absf(cruise - 4.2) < 0.08, id + "：实际巡航 4.2m/s")
	var before_sprint := position(runtime)
	runtime.set_motion_input(Vector3(0, 0, -1), true)
	step(runtime)
	var sprint_first := speed(runtime)
	step(runtime, 89)
	var sprint := speed(runtime)
	check(sprint_first > cruise and sprint_first < 6.0, id + "：Shift 加速不是瞬时变速")
	check(absf(sprint - 7.0) < 0.08, id + "：实际冲刺 7m/s")
	check(runtime.camera.fov > 77.7 and runtime.camera.fov <= 78.01, id + "：真实冲刺驱动 FOV 到78")
	values.sprint_fov = runtime.camera.fov
	values.sprint_distance = before_sprint.distance_to(position(runtime))
	var brake_start := position(runtime)
	runtime.set_motion_input(Vector3.ZERO)
	step(runtime)
	var brake_first := speed(runtime)
	step(runtime, 89)
	var brake_end := position(runtime)
	var brake_distance := brake_start.distance_to(brake_end)
	step(runtime, 60)
	var drift := brake_end.distance_to(position(runtime))
	check(brake_first > 1.0 and brake_first < sprint, id + "：松开后保留短暂惯性再刹停")
	check(brake_distance > 0.3 and brake_distance < 1.8, id + "：刹停距离合理且非瞬停")
	check(speed(runtime) < 0.001 and drift < 0.001, id + "：刹停后无持续漂移")
	check(absf(runtime.camera.fov - 72.0) < 0.1, id + "：实际松开加速后 FOV 回72")
	reset(runtime, origin)
	runtime.set_motion_input(Vector3.RIGHT)
	step(runtime, 60)
	var prior_velocity: Vector3 = runtime.velocity
	var prior_forward: Vector3 = runtime.character.global_basis.z
	runtime.set_motion_input(Vector3.LEFT)
	step(runtime)
	var reversal_first: Vector3 = runtime.velocity
	step(runtime, 59)
	var reversed_velocity: Vector3 = runtime.velocity
	var forward: Vector3 = runtime.character.global_basis.z
	var turn_angle := rad_to_deg(prior_forward.angle_to(forward))
	check(prior_velocity.x > 4.0 and reversal_first.x > 0.0 and reversed_velocity.x < -4.0,
		id + "：相反输入先减速再反向而非瞬间翻转")
	check(turn_angle > 160.0, id + "：反向后角色产生真实转角")
	check(forward.normalized().dot(reversed_velocity.normalized()) > 0.98, id + "：角色正Z朝实际运动方向")
	values.merge({"first_speed": first_speed, "accel_0_2s_speed": early_speed, "accel_0_2s_distance": accel_distance,
		"cruise_speed": cruise, "sprint_first_speed": sprint_first, "sprint_speed": sprint,
		"brake_first_speed": brake_first, "brake_distance": brake_distance, "stopped_drift": drift,
		"reverse_first_velocity": v3(reversal_first), "reverse_final_velocity": v3(reversed_velocity),
		"turn_degrees": turn_angle, "facing_error_degrees": rad_to_deg(forward.angle_to(reversed_velocity))})
	# 验证注入轴的 x右/y上/z后语义；方向取实际位移而不是读取输入缓存。
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		reset(runtime, origin)
		runtime.set_motion_input(axis)
		step(runtime, 30)
		check((position(runtime) - origin).dot(axis) > 0.4, id + "：运动轴 " + str(axis))
	runtime.clear_motion_input()

func safe_screen_target(runtime) -> Dictionary:
	var camera: Camera3D = runtime.camera
	var current := position(runtime)
	var rect: Rect2 = root.get_visible_rect()
	for x in [-2.0, 0.0, 2.0]:
		for z in [-3.0, -5.0, -7.0]:
			var point := current + Vector3(x, 0, z)
			if camera.is_position_behind(point):
				continue
			var screen := camera.unproject_position(point)
			if not rect.has_point(screen):
				continue
			# 保证点击射线能与角色所在水深平面相交，不使用水平射线的22m回退点。
			var ray := camera.project_ray_normal(screen)
			if absf(ray.y) < 0.02:
				continue
			var route: Array = runtime.map.dive_route(point)
			if not route.is_empty():
				return {"point": point, "screen": screen}
	return {}

func test_pointer(runtime, origin: Vector3, id: String, values: Dictionary) -> void:
	reset(runtime, origin)
	runtime.pitch = 0.3
	runtime.update_camera(0.0, true)
	var candidate := safe_screen_target(runtime)
	check(not candidate.is_empty(), id + "：选择实际可见、安全路线世界点")
	if not candidate.is_empty():
		var screen: Vector2 = candidate.screen
		button(runtime, MOUSE_BUTTON_LEFT, true, screen)
		mouse(runtime, Vector2(25, 12), screen + Vector2(25, 12))
		button(runtime, MOUSE_BUTTON_LEFT, false, screen + Vector2(25, 12))
		check(runtime.route.is_empty(), id + "：left drag 不触发导航")
		button(runtime, MOUSE_BUTTON_LEFT, true, screen)
		button(runtime, MOUSE_BUTTON_LEFT, false, screen + Vector2(1, 0))
		check(not runtime.route.is_empty(), id + "：短点击真实投影建立路线")
		if not runtime.route.is_empty():
			var endpoint: Vector3 = runtime.route.back()
			check(endpoint.distance_to(candidate.point) < 0.5, id + "：点击路线终点对应安全世界坐标")
			values.click_endpoint_error = endpoint.distance_to(candidate.point)
		step(runtime, 25)
		var nav_speed := speed(runtime)
		check(nav_speed > 0.3, id + "：点击导航产生实际速度")
		runtime.cancel_navigation()
		var cancel_position := position(runtime)
		check(runtime.route.is_empty() and is_equal_approx(speed(runtime), nav_speed), id + "：取消只清路线不硬清速度")
		step(runtime)
		var cancel_first := speed(runtime)
		check(cancel_first > 0.1 and cancel_first < nav_speed, id + "：取消后惯性刹车")
		step(runtime, 90)
		check(speed(runtime) < 0.001 and runtime.route.is_empty(), id + "：取消后终止自动游动")
		values.cancel_brake_distance = cancel_position.distance_to(position(runtime))
	var p0: float = runtime.pitch
	button(runtime, MOUSE_BUTTON_RIGHT, true)
	mouse(runtime, Vector2(30, 180))
	step(runtime, 30)
	var pdown: float = runtime.pitch
	var down_forward: Vector3 = -runtime.camera.global_basis.z
	mouse(runtime, Vector2(-15, -400))
	step(runtime, 30)
	var pup: float = runtime.pitch
	var up_forward: Vector3 = -runtime.camera.global_basis.z
	button(runtime, MOUSE_BUTTON_RIGHT, false)
	check(pdown > p0 and down_forward.y < -0.3, id + "：鼠标俯视改变 pitch 及实际相机方向")
	check(pup < 0.0 and up_forward.y > 0.2, id + "：鼠标仰视改变 pitch 及实际相机方向")
	for _i in 30:
		button(runtime, MOUSE_BUTTON_WHEEL_UP, true)
	var minimum: float = runtime.distance
	button(runtime, MOUSE_BUTTON_WHEEL_UP, true)
	check(is_equal_approx(minimum, 4.0) and is_equal_approx(runtime.distance, 4.0), id + "：滚轮4m下限")
	for _i in 30:
		button(runtime, MOUSE_BUTTON_WHEEL_DOWN, true)
	var maximum: float = runtime.distance
	button(runtime, MOUSE_BUTTON_WHEEL_DOWN, true)
	check(is_equal_approx(maximum, 13.0) and is_equal_approx(runtime.distance, 13.0), id + "：滚轮13m上限")
	# 同一按键通过场景树真实派发，检查地图兼容输入没有二次 toggle。
	var lamp_before: bool = runtime.air.lamp
	var messages := []
	var listener := func(text: String):
		if text.begins_with("头灯"):
			messages.append(text)
	runtime.map.message.connect(listener)
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	root.push_input(f, true)
	var lamp_after: bool = runtime.air.lamp
	f.echo = true
	root.push_input(f, true)
	f.echo = false
	f.pressed = false
	root.push_input(f, true)
	check(lamp_after != lamp_before and runtime.air.lamp == lamp_after and messages.size() == 1,
		id + "：真实F按下只切换一次，echo/release不再切换")
	runtime.map.message.disconnect(listener)
	values.mouse = {"pitch_before": p0, "pitch_down": pdown, "pitch_up": pup,
		"look_down_y": down_forward.y, "look_up_y": up_forward.y, "zoom_min": minimum, "zoom_max": maximum}
	runtime.clear_motion_input()

func phase_advance(runtime, count: int) -> float:
	var total := 0.0
	for _i in count:
		var before: float = runtime.character.swim_snapshot().phase
		step(runtime)
		var after: float = runtime.character.swim_snapshot().phase
		total += fposmod(after - before, TAU)
	return total / (float(count) * DT)

func test_animation(runtime, origin: Vector3, id: String, values: Dictionary) -> void:
	reset(runtime, origin)
	var character = runtime.character
	check(character.visible and character.gear.is_visible_in_tree() and character.mask.is_visible_in_tree()
		and not character.hat.visible, id + "：装备面罩可见、帽子隐藏")
	var hover_hz := phase_advance(runtime, 30)
	var hover_snapshot: Dictionary = character.swim_snapshot()
	check(hover_snapshot.action == "swimming" and float(hover_snapshot.speed_ratio) < 0.01,
		id + "：悬浮快照速度接近零")
	runtime.set_motion_input(Vector3(0, 0, -1))
	step(runtime, 90)
	var cruise_actual := speed(runtime)
	var cruise_snapshot: Dictionary = character.swim_snapshot()
	var cruise_hz := phase_advance(runtime, 20)
	check(absf(float(cruise_snapshot.speed_ratio) - cruise_actual / 4.2) < 0.05,
		id + "：swim_snapshot 跟随实际巡航速度")
	reset(runtime, origin)
	runtime.set_motion_input(Vector3(0, 0, -1), true)
	step(runtime, 90)
	var sprint_actual := speed(runtime)
	var sprint_snapshot: Dictionary = character.swim_snapshot()
	var sprint_hz := phase_advance(runtime, 20)
	check(absf(float(sprint_snapshot.speed_ratio) - minf(sprint_actual / 4.2, 1.65)) < 0.05
		and sprint_snapshot.sprint and float(sprint_snapshot.sprint_blend) > 0.95,
		id + "：swim_snapshot 跟随实际冲刺速度与混合")
	check(sprint_hz > cruise_hz + 0.5 and cruise_hz > hover_hz + 0.5,
		id + "：真实相位展开测量，悬浮/巡航/冲刺频率不同")
	# 保持有运动意图、用旧地图真实容器边界阻挡，证明表现不是单纯吃输入轴。
	if id == "zone1":
		reset(runtime, Vector3(0, runtime.map.MOVE_MAX_Y, 12))
		runtime.set_motion_input(Vector3.UP, true)
		step(runtime, 90)
		check(speed(runtime) < 0.001 and float(character.swim_snapshot().speed_ratio) < 0.02,
			"zone1：持续冲刺输入被真实边界阻挡时动画速度降零")
	values.animation = {"hover_rad_s": hover_hz, "cruise_rad_s": cruise_hz, "sprint_rad_s": sprint_hz,
		"cruise_actual_speed": cruise_actual, "cruise_ratio": cruise_snapshot.speed_ratio,
		"sprint_actual_speed": sprint_actual, "sprint_ratio": sprint_snapshot.speed_ratio}
	runtime.clear_motion_input()

func test_oxygen(runtime, origin: Vector3, id: String, values: Dictionary) -> void:
	var measurements := []
	# 独立的标定样本，不用 air.drain_rate() 作为自身的预期答案。
	for sample in [
		{"depth": 10.0, "fast": false, "move": false, "lamp": false, "rate": 0.9265},
		{"depth": 10.0, "fast": false, "move": true, "lamp": false, "rate": 1.250775},
		{"depth": 20.0, "fast": true, "move": true, "lamp": false, "rate": 1.9057},
		{"depth": 20.0, "fast": false, "move": false, "lamp": true, "rate": 1.303}]:
		var point := Vector3(origin.x, float(runtime.map.dive_water_level()) - float(sample.depth), origin.z)
		reset(runtime, point)
		runtime.air.lamp = sample.lamp
		if sample.move:
			runtime.set_motion_input(Vector3.RIGHT, sample.fast)
			step(runtime, 20)
		else:
			runtime.set_motion_input(Vector3.ZERO)
		runtime.air.air = 80.0
		var before := position(runtime)
		# 故意把相机摆到完全不同深度，先 tick 再更新相机。
		runtime.camera.global_position = Vector3(before.x, float(runtime.map.dive_water_level()) - 2.0, before.z)
		runtime.machine.tick(DT)
		var loss: float = 80.0 - runtime.air.air
		var expected_loss: float = float(sample.rate) * DT
		check(runtime.air == runtime.map.air, id + "：消耗仍作用于同一氧气实例")
		check(absf(float(runtime.map.depth) - float(sample.depth)) < 0.01, id + "：氧气深度来自角色位置")
		check(absf(loss - expected_loss) < 0.00002,
			id + "：速度/深度/灯标定样本每tick精确消耗一次 " + str(sample))
		check(not sample.move or speed(runtime) > 0.2, id + "：移动耗氧样本确实在游动")
		measurements.append({"sample": sample, "actual_loss": loss, "expected_loss": expected_loss,
			"actual_speed": speed(runtime), "depth": runtime.map.depth, "camera_depth": 2.0})
	# 关闭自动物理后，真实物理帧等待不应另扣一次氧气。
	values.oxygen = measurements
	runtime.clear_motion_input()

func test_camera(runtime, origin: Vector3, id: String, values: Dictionary) -> void:
	reset(runtime, origin)
	var poses := []
	for look in [Vector2(0, 0.6), Vector2(1.2, -0.7), Vector2(-2.2, 0.25)]:
		runtime.yaw = look.x
		runtime.pitch = look.y
		runtime.update_camera(0.0, true)
		var camera: Camera3D = runtime.camera
		var forward: Vector3 = -camera.global_basis.z
		var roll_dot := camera.global_basis.x.dot(Vector3.UP)
		check(absf(roll_dot) < 0.0001, id + "：不同yaw/pitch下实际相机无roll")
		check(camera.global_position.is_finite() and forward.is_finite()
			and camera.fov >= 71.99 and camera.fov <= 78.01, id + "：相机位置及FOV有效")
		poses.append({"position": v3(camera.global_position), "forward": v3(forward),
			"yaw": look.x, "pitch": look.y, "roll_dot": roll_dot, "fov": camera.fov})
	values.camera_poses = poses
	if id == "zone1":
		var target := origin + Vector3.UP * 0.4
		var requested := target + Vector3.RIGHT * 45.0
		var clipped: Vector3 = runtime.map.dive_camera_clip(target, requested, 0.32)
		check(target.distance_to(clipped) < target.distance_to(requested) - 1.0, "zone1：实际blocked采样缩回镜头")
		var safe := true
		for i in 51:
			if runtime.map.blocked(target.lerp(clipped, float(i) / 50.0), 0.32):
				safe = false
		check(safe, "zone1：整条相机臂采样不穿地图阻挡")
		# 同一障碍方向让控制器实际摆镜头，而非只测地图 API。
		runtime.distance = 13.0
		runtime.yaw = PI / 2.0
		runtime.pitch = 0.0
		runtime.update_camera(0.0, true)
		var actual: Vector3 = runtime.camera.global_position
		check(not runtime.map.blocked(actual, 0.32), "zone1：控制器最终相机球不在blocked内")
		values.camera_collision = {"requested": v3(requested), "clipped": v3(clipped),
			"requested_length": target.distance_to(requested), "safe_length": target.distance_to(clipped),
			"actual_camera": v3(actual)}
	else:
		test_home_collision(runtime, values)
	runtime.clear_motion_input()

func test_home_collision(runtime, values: Dictionary) -> void:
	var map = runtime.map
	var nearby: Vector3 = map.dive_position()
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var found := false
	# 对实际街区周边发射线；不添加测试墙、不改场景手摆。
	for y in [nearby.y, nearby.y - 10.0, float(map.water_level) - 20.0]:
		if found:
			break
		var ray_origin := Vector3(nearby.x, float(y), nearby.z)
		for i in 32:
			var angle := TAU * float(i) / 32.0
			var direction := Vector3(cos(angle), 0, sin(angle))
			var ray := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + direction * 100.0, 1)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or not hit.collider.has_meta("proxy_source_path"):
				continue
			var normal: Vector3 = hit.normal.normalized()
			if absf(normal.y) > 0.3:
				continue
			var target: Vector3 = hit.position + normal * 2.0
			var subject := target - Vector3.UP * 0.4
			if not map._dive_point_in_bounds(subject) or not capsule_clear(map, subject) or not sphere_clear(map, target, 0.32):
				continue
			var desired: Vector3 = hit.position - normal * 4.0
			var safe: Vector3 = map.dive_camera_clip(target, desired, 0.32)
			check(target.distance_to(safe) < target.distance_to(desired) - 1.0, "home：真实几何球扫掠clip缩回")
			check(sphere_clear(map, safe, 0.32), "home：clip终点0.32m球无穿透")
			runtime.debug_teleport(subject)
			runtime.distance = 7.5
			var orbit: Vector3 = (desired - target).normalized()
			runtime.yaw = atan2(orbit.x, orbit.z)
			runtime.pitch = asin(orbit.y)
			runtime.update_camera(0.0, true)
			var actual: Vector3 = runtime.camera.global_position
			check(target.distance_to(actual) < 3.0 and sphere_clear(map, actual, 0.32), "home：控制器实际相机臂贴墙收回且球不穿透")
			var query := sphere_query(target, 0.32)
			query.motion = actual - target
			var cast := space.cast_motion(query)
			check(cast.is_empty() or float(cast[0]) > 0.999, "home：相机完整球扫掠路径不穿透")
			values.camera_collision = {"source_path": str(hit.collider.get_meta("proxy_source_path")),
				"surface": v3(hit.position), "target": v3(target), "desired": v3(desired), "clipped": v3(safe),
				"actual_camera": v3(actual), "requested_length": target.distance_to(desired),
				"safe_length": target.distance_to(safe), "actual_boom": target.distance_to(actual)}
			found = true
			break
	check(found, "home：找到真实周边模型而非人工障碍进行相机碰撞验收")

func render_map(runtime, point: Vector3, id: String, values: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	reset(runtime, point)
	runtime.pitch = 0.14
	# 每个真实显示帧后手动固定步并显式更新镜头，不让自动 _process 影响稳定判据。
	var stable := false
	for _i in 12:
		var before: Transform3D = runtime.camera.global_transform
		step(runtime, 8)
		if id == "home":
			runtime.map._process(DT)
		await process_frame
		if before.origin.distance_to(runtime.camera.global_position) < 0.002 \
			and before.basis.z.angle_to(runtime.camera.global_basis.z) < 0.001:
			stable = true
	check(stable, id + "：固定步后相机稳定再抓真实帧")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), id + "：真实渲染帧非空")
	if image == null or image.is_empty():
		return
	var path := "res://outputs/dive-control-" + id + ".png"
	check(image.save_png(path) == OK, id + "：运行画面保存到工程副本outputs")
	report.renders.append(path)
	values.render_camera = {"position": v3(runtime.camera.global_position), "fov": runtime.camera.fov,
		"pitch": runtime.pitch, "yaw": runtime.yaw}

func test_runtime(map, id: String) -> void:
	var runtime = map.dive_controller
	var entry := position(runtime)
	var values := {"entry": v3(entry)}
	report.maps[id] = values
	var origin := safe_test_origin(map, id)
	if not origin.is_finite():
		return
	values.fixed_step_origin = v3(origin)
	test_motion(runtime, origin, id, values)
	test_pointer(runtime, origin, id, values)
	test_animation(runtime, origin, id, values)
	test_oxygen(runtime, origin, id, values)
	var air_before: float = runtime.air.air
	for _i in 3:
		await physics_frame
	check(absf(runtime.air.air - air_before) < 0.000001, id + "：自动physics禁用后真实物理帧不重复耗氧")
	test_camera(runtime, origin, id, values)
	await render_map(runtime, entry, id, values)
	runtime.clear_motion_input()

func test_home() -> void:
	var packed := load(str(Catalog.get_map("home_seabed").scene_path)) as PackedScene
	check(packed != null, "home：正式场景加载")
	if packed == null:
		return
	var map = packed.instantiate()
	root.add_child(map)
	current_scene = map
	map.set_process(false)
	map.set_physics_process(false)
	if not shared_contract(map, "home"):
		map.free()
		return
	var base: Node3D = map.get_node_or_null("ExistingModels/SolarCabinBase2")
	if base == null:
		base = map.get_node_or_null("ExistingModels/SolarCabinBase")
	check(base != null, "home：适配当前Base2/Base节点且不改手摆")
	var base_transform: Transform3D = base.transform if base != null else Transform3D.IDENTITY
	var runtime = map.dive_controller
	freeze(runtime)
	check(map.begin_dive(Vector3(7, 101.587442, 5)), "home：begin_dive 使用真实指定世界入水点")
	runtime.character.set_process(false)
	for _i in 120:
		await physics_frame
		if map.entry_verified or runtime.machine.current != "enter":
			break
	check(map.entry_verified and runtime.machine.current == "enter", "home：等待entry_verified真实物理提交，不强改标记")
	if not map.entry_verified:
		current_scene = null
		root.remove_child(map)
		map.free()
		return
	check(capsule_clear(map, map.dive_position()), "home：真实入水胶囊净空")
	var air_at_entry: float = runtime.air.air
	runtime.machine.tick(DT)
	check(runtime.machine.current == "swim" and is_equal_approx(runtime.air.air, air_at_entry), "home：合法enter→swim，入水tick不额外扣气")
	runtime.character.set_process(false)
	await test_runtime(map, "home")
	check(base == null or base.transform.is_equal_approx(base_transform), "home：Base2手摆transform保持原样")
	finish_map(map, "home")

func finish() -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "工程副本 JSON 报告可写")
	report.checks = checks
	report.failures = failures
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[dive-control] %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func run() -> void:
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	var user_slot: String = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	if not user_slot.begins_with("sea-verification/") or not project_root.trim_suffix("/").ends_with("/project"):
		check(false, "仅允许run_verification.py的隔离工程副本，拒绝主工程运行")
		print("[dive-control] %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs")) == OK, "副本outputs可用")
	var economy := root.get_node_or_null("Economy")
	if economy != null:
		economy.set_process(false)
		economy.set_physics_process(false)
	check(Catalog.source_ids().size() == 9, "九个旧source_ids完整覆盖")
	for id in Catalog.source_ids():
		var map = old_map(id)
		if map == null:
			continue
		if id == "zone1":
			test_input_map()
			await test_runtime(map, id)
		finish_map(map, id)
	await test_home()
	if DisplayServer.get_name() != "headless":
		check(report.renders.size() == 2, "真实显示模式仅保存home和zone1两张运行画面")
	finish()
