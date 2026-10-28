extends RefCounted
## Sole owner of surface actor control. Scene/UI depend on commands and snapshots.
signal state_changed(previous: String, current: String)
signal mode_changed(mode: int)
const Machine = preload("res://src/core/state_machine.gd")
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
var board = preload("res://src/player/actions/board_action.gd").new()
var disembark = preload("res://src/player/actions/disembark_action.gd").new()
var approach_action = preload("res://src/player/actions/approach_action.gd").new()

func configure(body: Node3D, boat: Node3D, root: Node3D, interaction: Node, boundary: Dictionary) -> void:
	actor = body
	vessel = boat
	world = root
	interactor = interaction
	ports = boundary
	var nodes := {
		"sleeping":preload("res://src/player/states/sleeping.gd").new(),
		"ashore_idle":preload("res://src/player/states/ashore_idle.gd").new(),
		"walking":preload("res://src/player/states/walking.gd").new(),
		"approaching":preload("res://src/player/states/approaching.gd").new(),
		"interacting":preload("res://src/player/states/interacting.gd").new(),
		"boarding":preload("res://src/player/states/boarding.gd").new(),
		"boat_idle":preload("res://src/player/states/boat_idle.gd").new(),
		"sailing":preload("res://src/player/states/sailing.gd").new(),
		"diving":preload("res://src/player/states/diving.gd").new()}
	var edges := {
		"sleeping":["ashore_idle"],
		"ashore_idle":["walking","approaching","boarding","diving","interacting"],
		"walking":["ashore_idle","walking","approaching","boarding"],
		"approaching":["ashore_idle","walking","approaching","interacting","boarding"],
		"interacting":["ashore_idle","walking","approaching","boarding","diving"],
		"boarding":["boat_idle"], "boat_idle":["walking","approaching","sailing","diving","boarding"],
		"sailing":["boat_idle"], "diving":["boat_idle","ashore_idle"]}
	machine.transitioned.connect(_transitioned)
	machine.configure(self, nodes, edges, "boat_idle")

func _transitioned(previous: String, current: String) -> void:
	mode_changed.emit(mode())
	state_changed.emit(previous, current)

func mode() -> int:
	if machine.current == "diving": return 3
	if machine.current == "sailing": return 2
	return 1 if machine.current in ["boat_idle","boarding"] else 0

func walking() -> bool: return machine.current in ["walking","approaching"]
func state_id() -> String: return machine.current
func tick(delta: float) -> void: machine.tick(delta)
func notify(text: String) -> void: ports.notify.call(text)
func current_landing() -> Node3D: return ports.landing.call()

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
	clear_interaction()
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
	var pos: Array = data.get("player",[])
	var ashore := int(data.get("mode",1)) == 0 and pos.size()==3
	if ashore:
		if actor.get_parent()!=world: actor.reparent(world,true)
		actor.global_position = Vector3(pos[0],pos[1],pos[2])
	else:
		board.execute(self)
	actor.set_diving(false)
	machine.change("ashore_idle" if ashore else "boat_idle",{},true)
