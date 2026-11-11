extends RefCounted
## Sole owner of surface actor control. Scene/UI depend on commands and snapshots.
signal state_changed(previous: String, current: String)
signal mode_changed(mode: int)
const Machine = preload("res://src/core/state_machine.gd")
## 玩家步频倍率。R29「移动动画加快一倍」定为 2.0；R30「再加快 10%」定为 2.0×1.1=2.2。
## 只写表现层相位，不改坐标、碰撞与地速；NPC 走 `Character.walk_phase_scale` 的默认 1.0。
const PLAYER_WALK_PHASE_SCALE := 2.2
var machine = Machine.new()
var actor: Node3D
var vessel: Node3D
var world: Node3D
var interactor: Node
var ports: Dictionary
var walk_path: Array[Vector3] = []
var walk_target := Vector3.ZERO
var walk_area: Node3D
var after_walk := Callable()
var auto_target: Node3D
var ground = preload("res://src/player/actions/walk_action.gd").new()
var stride = preload("res://src/player/actions/free_walk_action.gd").new()
var board = preload("res://src/player/actions/board_action.gd").new()
var disembark = preload("res://src/player/actions/disembark_action.gd").new()
var approach_action = preload("res://src/player/actions/approach_action.gd").new()
var climb_action = preload("res://src/player/actions/climb_ladder_action.gd").new()
var climb_from := Vector3.ZERO
var climb_to := Vector3.ZERO
var climb_progress := 0.0
var climb_subject: Node3D
## 键盘移动意图（世界 xz 方向，已归一化；零 = 没按键）。由 Main 每帧写入，
## 这里只负责「能不能转成一次行走」，不读键盘也不读镜头。
var move_intent := Vector3.ZERO
## 当前行走速度（世界 m/s）。自由行走自己积分加减速，点击走路不写它。
## 镜头前视、步频、测试都只读这一个量，不再各自猜速度。
var move_velocity := Vector3.ZERO
## Shift 小跑只改变岸上自由行走的目标速度；不读键，Main 每帧写入。
var sprint_held := false
var _support_area: Node3D
var _support_height := 0.0

func configure(body: Node3D, boat: Node3D, root: Node3D, interaction: Node, boundary: Dictionary) -> void:
	actor = body
	if "walk_phase_scale" in body:
		body.walk_phase_scale = PLAYER_WALK_PHASE_SCALE
	vessel = boat
	world = root
	interactor = interaction
	ports = boundary
	var nodes := {
		"sleeping":preload("res://src/player/states/sleeping.gd").new(),
		"climbing":preload("res://src/player/states/climbing.gd").new(),
		"ashore_idle":preload("res://src/player/states/ashore_idle.gd").new(),
		"walking":preload("res://src/player/states/walking.gd").new(),
		"strolling":preload("res://src/player/states/strolling.gd").new(),
		"approaching":preload("res://src/player/states/approaching.gd").new(),
		"interacting":preload("res://src/player/states/interacting.gd").new(),
		"boarding":preload("res://src/player/states/boarding.gd").new(),
		"boat_idle":preload("res://src/player/states/boat_idle.gd").new(),
		"sailing":preload("res://src/player/states/sailing.gd").new(),
		"diving":preload("res://src/player/states/diving.gd").new()}
	var edges := {
		"sleeping":["ashore_idle"],
		"climbing":["ashore_idle"],
		"ashore_idle":["walking","strolling","approaching","boarding","diving","interacting","climbing"],
		"walking":["ashore_idle","walking","strolling","approaching","boarding"],
		"strolling":["ashore_idle","walking","strolling","approaching","boarding"],
		"approaching":["ashore_idle","walking","strolling","approaching","interacting","boarding"],
		"interacting":["ashore_idle","walking","approaching","boarding","diving"],
		"boarding":["boat_idle"], "boat_idle":["walking","approaching","sailing","diving","boarding"],
		"sailing":["boat_idle"], "diving":["boat_idle","ashore_idle"]}
	machine.transitioned.connect(_transitioned)
	machine.configure(self, nodes, edges, "boat_idle")

func _transitioned(previous: String, current: String) -> void:
	if is_instance_valid(actor) and actor.has_method("set_boat_seated"):
		actor.set_boat_seated(current in ["boat_idle","boarding","sailing"])
	if is_instance_valid(actor) and actor.has_method("set_grounded_motion"):
		actor.set_grounded_motion(current in ["ashore_idle","walking","strolling","approaching","interacting","sleeping"])
		if current == "climbing":
			actor.set_grounded_motion(false)
	if is_instance_valid(actor) and actor.has_method("set_climbing"):
		actor.set_climbing(current == "climbing")
	if current != "strolling": sprint_held = false
	if is_instance_valid(actor) and actor.has_method("set_sprinting"):
		actor.set_sprinting(sprint_held)
	mode_changed.emit(mode())
	state_changed.emit(previous, current)

func mode() -> int:
	if machine.current == "diving": return 3
	if machine.current == "sailing": return 2
	return 1 if machine.current in ["boat_idle","boarding"] else 0

func walking() -> bool: return machine.current in ["walking","strolling","approaching"]
func climbing() -> bool: return machine.current == "climbing"
func state_id() -> String: return machine.current
func tick(delta: float) -> void:
	_carry_moving_support()
	machine.tick(delta)

func climb_ladder(start: Vector3, end: Vector3, subject: Node3D) -> Dictionary:
	if subject == null or not is_instance_valid(subject):
		return {"blocked": "梯子已经不在了"}
	if mode() != 0 or (ports.has("input_blocked") and bool(ports.input_blocked.call())):
		return {"blocked": "现在不能爬梯子"}
	var from := Vector3(actor.global_position.x, start.y, actor.global_position.z)
	var to := Vector3(actor.global_position.x, end.y, actor.global_position.z)
	var prepared := climb_action.prepare(self, from, to, subject)
	if not bool(prepared.get("ok", false)):
		return {"blocked": "梯子位置不适合攀爬"}
	clear_interaction()
	return {"event": "ladder_climb_started", "ok": machine.change("climbing", prepared, true)}

func _carry_moving_support() -> void:
	if mode() != 0 or not is_instance_valid(actor):
		_support_area = null
		return
	var area: Node3D = walk_area
	if not is_instance_valid(area) or not area.contains_position(actor.global_position, 0.5):
		area = null
		var zone: Variant = ports.zone.call() if ports.has("zone") else null
		if is_instance_valid(zone) and zone.has_method("area_at"):
			area = zone.area_at(actor.global_position, 0.5)
	if area == null or not area.get_meta("moving_support", false):
		_support_area = null
		return
	var height: float = area.surface_y
	if _support_area == area:
		var offset := Vector3(0, height - _support_height, 0)
		actor.carry_ground_support(offset)
		if walk_area == area:
			for i in walk_path.size():
				walk_path[i] += offset
			walk_target += offset
	else:
		# Heave is not a saved gameplay state. Restoring a position captured at
		# another phase attaches feet to the current support, rather than saving
		# a permanent air gap (or sinking the actor into the floor).
		actor.carry_ground_support(Vector3(0, height - actor.global_position.y, 0))
	_support_area = area
	_support_height = height
func notify(text: String) -> void: ports.notify.call(text)
func current_landing() -> Node3D: return ports.landing.call()

## 键盘移动的唯一写入口（SEA-MOVE-R20）。
##
## `dir` 是**世界**方向（Main 已按镜头朝向折算），长度只用于判「按没按」。
## 规则：
##   · 只有岸上（mode 0）能走；船上/潜水/入睡一律清零，船由 SEA-NAV 手动驾驶；
##   · 面板、过场、模态打开时不接管（`ports.input_blocked`）；
##   · 非零 → 进入 strolling 并打断点击走路/自动接近；
##   · 归零 → 只清意图，**不立刻换状态**：让 strolling 把速度收到 0 再回站定
##     （SEA-MOVE-R23）。立刻切状态会让减速那几帧没有任何人驱动，
##     表现为「松手瞬停」。
## 不做「按一下走一段」的节流：键盘是持续按住，速度由物理帧决定。
func set_sprint_held(on: bool) -> void:
	var blocked := ports.has("input_blocked") and bool(ports.input_blocked.call())
	sprint_held = on and not blocked and move_intent != Vector3.ZERO and mode() == 0 and machine.current == "strolling"
	if is_instance_valid(actor) and actor.has_method("set_sprinting"):
		actor.set_sprinting(sprint_held)

func set_move_intent(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	move_intent = flat.normalized() if flat.length_squared() > 0.000001 else Vector3.ZERO
	if not is_instance_valid(actor):
		return
	if move_intent == Vector3.ZERO:
		set_sprint_held(false)
		return
	if mode() != 0 or machine.current in ["diving","sleeping","boarding","interacting","climbing"]:
		move_intent = Vector3.ZERO
		set_sprint_held(false)
		return
	if ports.has("input_blocked") and bool(ports.input_blocked.call()):
		move_intent = Vector3.ZERO
		set_sprint_held(false)
		return
	if machine.current in ["ashore_idle","walking","approaching","strolling"]:
		clear_interaction()
		machine.change("strolling")

## 当前是否由键盘在走（HUD 用来区分「点过去」和「自己在走」）。
func strolling() -> bool: return machine.current == "strolling"

func start_walk(area: Node3D, target: Vector3) -> bool:
	var result: Dictionary = ground.prepare(self, area, target)
	if not result.get("ok", false): return false
	clear_interaction()
	if mode() != 0: disembark.execute(self, result.start)
	return machine.change("walking", {"area":area,"target":target,"path":result.path}, true)

func approach(target: Node3D) -> bool: return approach_action.execute(self,target)

func depart(action: Callable) -> bool:
	if mode() == 3: return false
	if mode() != 0:
		action.call()
		return true
	var landing := current_landing()
	if landing == null or not start_walk(landing.ground(),landing.stand_position()): return false
	after_walk = func():
		board_player()
		action.call()
	return true

func board_player() -> void: machine.change("boarding")

func clear_interaction() -> void:
	auto_target = null
	if interactor != null:
		interactor.cancel()

func cancel() -> void:
	if is_instance_valid(actor) and actor.has_method("cancel_action"): actor.cancel_action("cancelled")
	clear_interaction()
	move_intent = Vector3.ZERO
	sprint_held = false
	move_velocity = Vector3.ZERO
	if is_instance_valid(actor):
		actor.walk_speed_ratio = 0.0
		if actor.has_method("set_sprinting"): actor.set_sprinting(false)
	after_walk = Callable()
	walk_path.clear()
	if mode() == 3: return
	if mode() == 2: vessel.place_at(vessel.position,vessel.rotation.y)
	machine.change("ashore_idle" if mode()==0 else "boat_idle",{},true)

func reconcile_mode(value: int) -> void:
	# Compatibility projection for old debug/test entry points; normal commands own transitions.
	if value == mode(): return
	var next: String = ["ashore_idle","boat_idle","sailing","diving"][clampi(value,0,3)]
	machine.change(next,{},true)

func request_mode(value: int) -> bool:
	if value == mode(): return true
	if value == 1 and machine.current == "diving":
		board.execute(self)
	var next: String = ["ashore_idle","boat_idle","sailing","diving"][clampi(value,0,3)]
	return machine.change(next)

func complete_interaction() -> void:
	clear_interaction()
	if machine.current == "interacting": machine.change("ashore_idle")

func begin_sleep() -> void:
	cancel()
	machine.change("sleeping",{},true)

func snapshot() -> Dictionary:
	return {"state":state_id(),"mode":mode(),"walking":walking(),"target":walk_target,"path":walk_path.duplicate()}

func restore_pose(data: Dictionary) -> void:
	cancel()
	_support_area = null
	var pos: Array = data.get("player",[])
	var ashore := int(data.get("mode",1)) == 0 and pos.size()==3
	if ashore:
		if actor.get_parent()!=world: actor.reparent(world,true)
		actor.global_position = Vector3(pos[0],pos[1],pos[2])
	else:
		board.execute(self)
	actor.set_diving(false)
	machine.change("ashore_idle" if ashore else "boat_idle",{},true)
