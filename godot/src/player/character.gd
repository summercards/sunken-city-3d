extends "res://src/player/character_motor.gd"
class_name Character
## 程序化小人（对齐网页版 character-art.js 的轮廓与配色）。
##
## 网页版用一个 Torso/Head/四肢 pivot 组成，靠 gameplay 更新旋转；
## 这里保持同样的骨架层级，动画在 _process 里按状态驱动。

const Cloth := Color("#ed934d")
const Dark := Color("#244757")
const SkinTone := Color("#ffdbb8")
const Gold := Color("#edc064")
const Rubber := Color("#18333e")
const Hair := Color("#55372f")
const HairLight := Color("#79503a")
const Lip := Color("#bd786f")

var body_pivot: Node3D
var head_pivot: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_knee: Node3D
var right_knee: Node3D
var hat: Node3D
var gear: Node3D
var mask: Node3D

var _t := 0.0
var _rowing := false
var _farm_action_left := 0.0

func play_farm_action(event: String, payload: Dictionary = {}) -> void:
	play_action("watering" if event in ["watered","浇水"] else ("harvesting" if event in ["harvested","收获"] else "planting"),payload)

## Successful gameplay commands may use this port for a crop produce item.
## It displays one representative item and never changes inventory quantities.
func play_receive_item(crop_id: String) -> int:
	return play_action("harvesting",{"crop":crop_id})

var _walking := false


func build() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 12

	body_pivot = Node3D.new()
	body_pivot.name = "BodyPivot"
	add_child(body_pivot)

	# 躯干：上身工装 + 深色腰带
	_blob(body_pivot, Cloth, Vector3(0, 0.62, 0), Vector3(0.218, 0.33, 0.153), sphere)
	_blob(body_pivot, Dark, Vector3(0, 0.30, 0), Vector3(0.21, 0.065, 0.154), sphere)
	_blob(body_pivot, Gold, Vector3(0, 0.55, 0.162), Vector3(0.012, 0.16, 0.012), sphere)

	head_pivot = Node3D.new()
	head_pivot.name = "HeadLook"
	head_pivot.position = Vector3(0, 0.98, 0)
	body_pivot.add_child(head_pivot)

	_blob(head_pivot, SkinTone, Vector3.ZERO, Vector3(0.2016, 0.21, 0.2037), sphere)
	# 头发（上半球）
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.214
	hair_mesh.height = 0.428
	hair_mesh.is_hemisphere = true
	hair_mesh.radial_segments = 24
	hair_mesh.rings = 10
	var hair := MeshInstance3D.new()
	hair.mesh = hair_mesh
	hair.material_override = _mat(Hair)
	hair.position = Vector3(0, 0.0, 0)
	hair.scale = Vector3(1, 0.85, 1)
	head_pivot.add_child(hair)

	# 刘海与鬓角
	var fringe := _blob(head_pivot, Hair, Vector3(-0.065, 0.104, 0.15), Vector3(0.145, 0.055, 0.064), sphere)
	fringe.rotation.z = -0.3
	_blob(head_pivot, Hair, Vector3(-0.176, 0.018, 0.075), Vector3(0.049, 0.135, 0.081), sphere)
	_blob(head_pivot, Hair, Vector3(0.181, 0.015, 0.025), Vector3(0.036, 0.12, 0.087), sphere)

	# 眼睛 / 腮红 / 嘴
	for s in [-1, 1]:
		_blob(head_pivot, Rubber, Vector3(s * 0.072, 0.015, 0.192), Vector3(0.023, 0.033, 0.014), sphere)
		_blob(head_pivot, Color("#fff7dc"), Vector3(s * 0.067, 0.025, 0.204), Vector3(0.007, 0.01, 0.004), sphere)
		_blob(head_pivot, Color("#e99b83"), Vector3(s * 0.115, -0.056, 0.173), Vector3(0.036, 0.017, 0.008), sphere)
	_blob(head_pivot, SkinTone, Vector3(0, -0.025, 0.203), Vector3(0.027, 0.03, 0.025), sphere)
	_blob(head_pivot, Lip, Vector3(0, -0.088, 0.185), Vector3(0.031, 0.012, 0.01), sphere)

	# 渔夫帽
	hat = Node3D.new()
	hat.position = Vector3(0, 0.19, -0.01)
	hat.rotation.x = -0.08
	head_pivot.add_child(hat)
	var brim := CylinderMesh.new()
	brim.top_radius = 0.33
	brim.bottom_radius = 0.34
	brim.height = 0.045
	brim.radial_segments = 28
	var brim_mi := MeshInstance3D.new()
	brim_mi.mesh = brim
	brim_mi.material_override = _mat(Gold)
	hat.add_child(brim_mi)
	var crown := CylinderMesh.new()
	crown.top_radius = 0.18
	crown.bottom_radius = 0.215
	crown.height = 0.16
	crown.radial_segments = 24
	var crown_mi := MeshInstance3D.new()
	crown_mi.mesh = crown
	crown_mi.material_override = _mat(Color("#d8a94f"))
	crown_mi.position = Vector3(0, 0.09, 0)
	hat.add_child(crown_mi)

	# 四肢（pivot → 肘/膝 → 手脚）
	left_arm = _limb("LeftArm", Vector3(-0.255, 0.84, 0))
	right_arm = _limb("RightArm", Vector3(0.255, 0.84, 0))
	left_elbow = _elbow(left_arm, "LeftElbow", -1)
	right_elbow = _elbow(right_arm, "RightElbow", 1)
	left_leg = _limb("LeftLeg", Vector3(-0.14, 0.34, 0))
	right_leg = _limb("RightLeg", Vector3(0.14, 0.34, 0))
	left_knee = _knee(left_leg, "LeftKnee")
	right_knee = _knee(right_leg, "RightKnee")
	_item_receive.build(self)

	# 潜水装备（默认隐藏，和网页版一致）
	gear = Node3D.new()
	gear.name = "DivingEquipment"
	gear.visible = false
	body_pivot.add_child(gear)
	var tank := CylinderMesh.new()
	tank.top_radius = 0.112
	tank.bottom_radius = 0.112
	tank.height = 0.32
	tank.radial_segments = 16
	var tank_mi := MeshInstance3D.new()
	tank_mi.mesh = tank
	tank_mi.material_override = _mat(Color("#c4d5cb"), true)
	tank_mi.position = Vector3(0, 0.56, -0.205)
	gear.add_child(tank_mi)

	mask = Node3D.new()
	mask.name = "DiveMask"
	mask.visible = false
	head_pivot.add_child(mask)
	_blob(mask, Rubber, Vector3(0, 0.013, 0.19), Vector3(0.204, 0.102, 0.06), sphere)


func _mat(color: Color, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.62 if metal else 0.78
	m.metallic = 0.35 if metal else 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


func _blob(parent: Node3D, color: Color, pos: Vector3, scale: Vector3, mesh: SphereMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _limb(name: String, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = pos
	body_pivot.add_child(pivot)
	var cap := CapsuleMesh.new()
	cap.radius = 0.068
	cap.height = 0.24
	cap.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	mi.material_override = _mat(Cloth if name.ends_with("Arm") else Dark)
	mi.position = Vector3(0, -0.09, 0)
	pivot.add_child(mi)
	return pivot


func _elbow(parent: Node3D, name: String, side: int) -> Node3D:
	var elbow := Node3D.new()
	elbow.name = name
	elbow.position = Vector3(0, -0.17, 0)
	parent.add_child(elbow)
	var cap := CapsuleMesh.new()
	cap.radius = 0.056
	cap.height = 0.16
	cap.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	mi.material_override = _mat(Cloth)
	mi.position = Vector3(0, -0.06, 0)
	elbow.add_child(mi)
	var hand := SphereMesh.new()
	hand.radius = 1.0
	hand.height = 2.0
	var hmi := MeshInstance3D.new()
	hmi.mesh = hand
	hmi.material_override = _mat(SkinTone)
	hmi.position = Vector3(0, -0.155, 0.006)
	hmi.scale = Vector3(0.058, 0.068, 0.045)
	elbow.add_child(hmi)
	return elbow


func _knee(parent: Node3D, name: String) -> Node3D:
	var knee := Node3D.new()
	knee.name = name
	knee.position = Vector3(0, -0.13, 0)
	parent.add_child(knee)
	var cap := CapsuleMesh.new()
	cap.radius = 0.056
	cap.height = 0.14
	cap.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	mi.material_override = _mat(Dark)
	mi.position = Vector3(0, -0.05, 0)
	knee.add_child(mi)
	var foot := SphereMesh.new()
	foot.radius = 1.0
	foot.height = 2.0
	var fmi := MeshInstance3D.new()
	fmi.mesh = foot
	fmi.material_override = _mat(Rubber)
	fmi.position = Vector3(0, -0.13, 0.035)
	fmi.scale = Vector3(0.066, 0.046, 0.105)
	knee.add_child(fmi)
	return knee


func set_walking(on: bool) -> void:
	_walking=on
	if on:
		_base_action="walking"
		cancel_action("walking")
	elif _base_action=="walking": _base_action="idle"

func set_rowing(on: bool) -> void:
	_rowing=on
	if on:
		_base_action="rowing"
		cancel_action("rowing")
	elif _base_action=="rowing": _base_action="idle"

func set_diving(on: bool) -> void:
	_base_action = "swimming" if on else "idle"
	cancel_action("diving" if on else "restore")
	if gear:
		gear.visible = on
	if mask:
		mask.visible = on


var rowing_query: Callable
var _action := "idle"
var _base_action := "idle"
var _last_action := ""
var _actions := {
	"swimming":preload("res://src/player/animation/swimming_action.gd").new(),
	"idle":preload("res://src/player/animation/idle_action.gd").new(),
	"walking":preload("res://src/player/animation/walking_action.gd").new(),
	"rowing":preload("res://src/player/animation/rowing_action.gd").new(),
	"planting":preload("res://src/player/animation/planting_action.gd").new(),
	"watering":preload("res://src/player/animation/watering_action.gd").new(),
	"harvesting":preload("res://src/player/animation/harvesting_action.gd").new()}

## These events report presentation only. Inventory, interaction completion and
## rewards remain owned by their gameplay services, never by an animation event.
signal action_started(action_id: String, token: int)
signal action_finished(action_id: String, token: int)
signal action_cancelled(action_id: String, token: int, reason: String)
var _item_receive = preload("res://src/player/animation/item_receive.gd").new()
var _action_durations := {"planting":1.1,"watering":1.1,"harvesting":2.4}
var _action_playback = preload("res://src/player/animation/action_playback.gd").new()
var _action_events: Array[Dictionary] = []
var _dispatching_action_events := false

## Add future inspect/collect/tool clips without coupling character code to a
## gameplay service. A sampler implements sample(character, delta), like the
## existing seven procedural clips. Existing clips cannot be silently replaced.
func register_action(action_id: String, sampler: RefCounted, duration: float) -> bool:
	if action_id.is_empty() or _actions.has(action_id) or sampler == null or not sampler.has_method("sample"):
		return false
	if not is_finite(duration) or duration <= 0.0: return false
	_actions[action_id] = sampler
	_action_durations[action_id] = duration
	return true

## Returns a unique token, or 0 without changing the current action on rejection.
func play_action(action_id: String, context: Dictionary = {}) -> int:
	if not _action_durations.has(action_id): return 0
	if action_id == "harvesting" and not _item_receive.Produce.supports(str(context.get("crop","lettuce"))): return 0
	var result: Dictionary = _action_playback.start(action_id, float(_action_durations[action_id]))
	if result.is_empty(): return 0
	_item_receive.clear()
	_reset_action_pose()
	if action_id == "harvesting": _item_receive.prepare(self,str(context.get("crop","lettuce")))
	_farm_action_left = _action_playback.remaining()
	_action = action_id
	_last_action = ""
	if not result.replaced.is_empty():
		_action_events.append({"kind":"cancelled","id":result.replaced.id,"token":result.replaced.token,"reason":"replaced"})
	_action_events.append({"kind":"started","id":action_id,"token":result.token})
	_flush_action_events()
	return int(result.token)

func cancel_action(reason: String = "cancelled") -> bool:
	var previous: Dictionary = _action_playback.cancel()
	_farm_action_left = 0.0
	if previous.is_empty(): return false
	_item_receive.clear()
	_reset_action_pose()
	_action = _base_action
	_action_events.append({"kind":"cancelled","id":previous.id,"token":previous.token,"reason":reason})
	_flush_action_events()
	return true

func action_progress() -> float: return _action_playback.progress()
func action_playback() -> Dictionary: return _action_playback.capture()

func _reset_action_pose() -> void:
	if body_pivot == null: return
	for joint in [body_pivot,head_pivot,left_arm,right_arm,left_elbow,right_elbow,left_leg,right_leg,left_knee,right_knee]:
		joint.rotation = Vector3.ZERO
	body_pivot.position.y = 0.0
	left_arm.position = Vector3(-0.255,0.84,0)
	right_arm.position = Vector3(0.255,0.84,0)
	left_arm.scale = Vector3.ONE
	right_arm.scale = Vector3.ONE
	_item_receive.set_arm_length(left_arm,left_elbow,1.0)
	_item_receive.set_arm_length(right_arm,right_elbow,1.0)
	_last_action = ""

func _flush_action_events() -> void:
	if _dispatching_action_events: return
	_dispatching_action_events = true
	while not _action_events.is_empty():
		var event: Dictionary = _action_events.pop_front()
		match event.kind:
			"started": action_started.emit(str(event.id), int(event.token))
			"finished": action_finished.emit(str(event.id), int(event.token))
			"cancelled": action_cancelled.emit(str(event.id), int(event.token), str(event.reason))
	_dispatching_action_events = false

func _process(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0: return
	_t += delta
	if body_pivot==null: return
	var playback: Dictionary = _action_playback.capture()
	_action = str(playback.id) if not playback.is_empty() else _base_action
	_farm_action_left = _action_playback.remaining()
	if _last_action != _action:
		_reset_action_pose()
		_last_action = _action
	_actions[_action].sample(self,delta)
	if not playback.is_empty():
		var completed: Dictionary = _action_playback.advance(delta)
		_farm_action_left = _action_playback.remaining()
		if not completed.is_empty():
			_item_receive.clear()
			_action_events.append({"kind":"finished","id":completed.id,"token":completed.token})
			_flush_action_events()

func animation_state() -> String: return _action
