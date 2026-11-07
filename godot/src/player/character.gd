extends "res://src/player/character_motor.gd"
class_name Character
## 原创圆润旅人；移动、节点动作与可替换外观独立维护。
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
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const AvatarCatalog = preload("res://src/avatar/avatar_catalog.gd")
const Morphology = preload("res://src/avatar/avatar_morphology.gd")

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
var limb_skinning

var _avatar_visual = preload("res://src/avatar/avatar_visual.gd").new()
var _avatar_morphs := AvatarCatalog.morph_defaults()
var _avatar_factors := Morphology.factors(_avatar_morphs,AvatarCatalog.defaults())

func apply_appearance(appearance: Dictionary) -> void:
	apply_avatar({"appearance":appearance,"morphs":_avatar_morphs})

func apply_avatar(profile: Dictionary) -> void:
	_avatar_morphs=AvatarCatalog.effective_morphs(profile.get("morphs",{}))
	var appearance: Dictionary=profile.get("appearance",AvatarCatalog.defaults())
	_avatar_factors=Morphology.factors(_avatar_morphs,appearance)
	if body_pivot != null:
		_avatar_visual.apply(self,appearance,_avatar_morphs,_avatar_factors)
		Morphology.apply(self,_avatar_factors)
		set_meta("avatar_morphs",_avatar_morphs.duplicate(true))

func avatar_shoulder(side: int) -> Vector3: return Morphology.shoulder(side,_avatar_factors)
func avatar_rest_hand(side: int) -> Vector3: return Morphology.rest_hand(side,_avatar_factors)
func avatar_portrait_scale() -> float:
	return maxf(1.0,float(_avatar_factors.head)*float(_avatar_factors.head_width)/0.95)
func avatar_arm_front_clearance() -> float:
	return (0.16+maxf(0.0,float(_avatar_factors.head)-1.0)*0.65+maxf(0.0,float(_avatar_factors.head_width)-0.95)*0.55+maxf(0.0,float(_avatar_factors.arm)-1.35)*0.12)*Dimensions.SCALE
func avatar_geometry_report() -> Dictionary:
	return {"factors":_avatar_factors.duplicate(true),"morphs":_avatar_morphs.duplicate(true),"face":_avatar_visual.face_metrics(),"hair":_avatar_visual.hair_metrics()}

func set_preview_yaw(value: float) -> void:
	if body_pivot != null:
		_turn_velocity = clampf(wrapf(value - body_pivot.rotation.y, -PI, PI) * 3.5, -1.5, 1.5)
		body_pivot.rotation.y = value

func trigger_customize_pulse() -> void:
	_customize_pulse = 1.0

func preview_expression(id: String, duration:=2.8) -> void:
	_avatar_visual.expression.preview(id,duration)
	_avatar_visual.expression.sample(_t,_action,action_progress(),0.0)

func expression_state() -> Dictionary: return _avatar_visual.expression.query()

var _t := 0.0
var _customize_pulse := 0.0
var _turn_velocity := 0.0
var _rowing := false
var _boat_seated := false
var _farm_action_left := 0.0
## 步频 ↔ 地速耦合（SEA-MOVE-R23）。
##
## 走路动画的相位原来直接吃 `_t * 6.4`：不管人走多快，腿都按同一个频率摆。
## 加减速一上来，这就成了「脚在原地划水」—— 起步时脚比身体快，停下时身体
## 还在滑。改成由 SEA-MOVE 每物理帧写 `walk_speed_ratio`（0…1.35），
## 这里积分真实相位，脚就永远踩在地上。
##
## 6.4 rad/s 是原采样频率，满速时相位推进与旧实现逐帧一致（不改变既有观感）；
## 下限 0.35 让「刚起步的 0.1 秒」也还有轻微摆动，不然像滑行。
const WALK_PHASE_RATE := 6.4
const WALK_PHASE_FLOOR := 0.35
var walk_speed_ratio := 0.0
var _walk_phase := 0.0
var _sprinting := false
var _run_blend := 0.0
const RUN_BLEND_TAU := 0.12
## 地速已经带来12%步频；短步再补足到约15%，而不是重复乘15%。
const JOG_PHASE_MULTIPLIER := 1.15 / 1.12

func set_sprinting(on: bool) -> void:
	# _action 要到表现帧才更新，起步只看已提交的基础动作，不能丢首帧。
	var can_jog := _walking and _base_action == "walking" and _action_playback.capture().is_empty()
	_sprinting = on and can_jog
	if not can_jog:
		_run_blend = 0.0

func sprinting() -> bool: return _sprinting
func run_blend() -> float: return _run_blend
func walk_phase() -> float: return _walk_phase

func play_farm_action(event: String, payload: Dictionary = {}) -> void:
	play_action("watering" if event in ["watered","浇水"] else ("harvesting" if event in ["harvested","收获"] else "planting"),payload)

## Successful gameplay commands may use this port for a crop produce item.
## It displays one representative item and never changes inventory quantities.
func play_receive_item(crop_id: String) -> int:
	return play_action("harvesting",{"crop":crop_id})

var _walking := false
var _climbing := false

func set_climbing(on: bool) -> void:
	_climbing = on
	if on:
		_base_action = "walking"
		cancel_action("climbing")
	elif _base_action == "walking" and not _walking:
		_base_action = "idle"

func build() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 12

	body_pivot = Node3D.new()
	body_pivot.name = "BodyPivot"
	add_child(body_pivot)

	head_pivot = Node3D.new()
	head_pivot.name = "HeadLook"
	head_pivot.position = Vector3(0, Dimensions.HEAD_CENTER, 0)
	body_pivot.add_child(head_pivot)

	# 四肢（pivot → 肘/膝 → 手脚）
	left_arm = _limb("LeftArm", Dimensions.shoulder(-1))
	right_arm = _limb("RightArm", Dimensions.shoulder(1))
	left_elbow = _elbow(left_arm, "LeftElbow", -1)
	right_elbow = _elbow(right_arm, "RightElbow", 1)
	left_leg = _limb("LeftLeg", Vector3(-Dimensions.HIP_X, Dimensions.HIP_Y, 0))
	right_leg = _limb("RightLeg", Vector3(Dimensions.HIP_X, Dimensions.HIP_Y, 0))
	left_knee = _knee(left_leg, "LeftKnee")
	right_knee = _knee(right_leg, "RightKnee")
	limb_skinning=preload("res://src/avatar/avatar_limb_skinning.gd").new()
	body_pivot.add_child(limb_skinning)
	limb_skinning.configure(self)
	_item_receive.build(self)

	# 潜水装备（默认隐藏，和网页版一致）
	gear = Node3D.new()
	gear.name = "DivingEquipment"
	gear.visible = false
	body_pivot.add_child(gear)
	var tank := CylinderMesh.new()
	tank.top_radius = 0.112*Dimensions.SCALE
	tank.bottom_radius = 0.112*Dimensions.SCALE
	tank.height = 0.32*Dimensions.SCALE
	tank.radial_segments = 16
	var tank_mi := MeshInstance3D.new()
	tank_mi.mesh = tank
	tank_mi.material_override = _mat(Color("#c4d5cb"), true)
	tank_mi.position = Vector3(0, 0.56, -0.205)*Dimensions.SCALE
	gear.add_child(tank_mi)

	mask = Node3D.new()
	mask.name = "DiveMask"
	mask.visible = false
	head_pivot.add_child(mask)
	mask.scale=Dimensions.HEAD_SCALE*Dimensions.SCALE
	preload("res://src/avatar/avatar_face.gd").new().build_dive_mask(mask)
	apply_appearance(preload("res://src/avatar/avatar_catalog.gd").defaults())


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
	pivot.name=name; pivot.position=pos; body_pivot.add_child(pivot)
	var guide:=Marker3D.new(); guide.name="UpperGuide"; pivot.add_child(guide)
	return pivot

func _elbow(parent: Node3D, name: String, _side: int) -> Node3D:
	var elbow:=Node3D.new(); elbow.name=name
	elbow.position=Vector3(0,-Dimensions.UPPER_ARM,0); parent.add_child(elbow)
	var guide:=Marker3D.new(); guide.name="ForearmGuide"; elbow.add_child(guide)
	var hand:=Marker3D.new(); hand.name="Hand"
	hand.position=Vector3(0,-Dimensions.LOWER_ARM,0.006*Dimensions.SCALE); elbow.add_child(hand)
	return elbow

func _knee(parent: Node3D, name: String) -> Node3D:
	var knee:=Node3D.new(); knee.name=name
	knee.position=Vector3(0,-Dimensions.THIGH,0); parent.add_child(knee)
	var guide:=Marker3D.new(); guide.name="ShinGuide"; knee.add_child(guide)
	var foot:=Marker3D.new(); foot.name="Foot"
	foot.position=Vector3(0,-Dimensions.SHIN,0.025*Dimensions.SCALE); knee.add_child(foot)
	return knee

func sync_visual_pose() -> void:
	if limb_skinning != null: limb_skinning.sync_pose()


func set_walking(on: bool) -> void:
	_walking=on
	if on:
		_base_action="walking"
		cancel_action("walking")
	else:
		if _base_action=="walking": _base_action="idle"
		set_sprinting(false)

func set_rowing(on: bool) -> void:
	_rowing=on
	if on:
		_base_action="rowing"
		set_sprinting(false)
		cancel_action("rowing")
	elif _base_action=="rowing" and not _boat_seated: _base_action="idle"

func set_boat_seated(on: bool) -> void:
	var leaving_seat := _boat_seated and not on
	_boat_seated=on
	if on:
		_base_action="rowing"
		set_sprinting(false)
	elif _base_action=="rowing": _base_action="idle"
	if leaving_seat: _reset_action_pose()

func set_diving(on: bool) -> void:
	_base_action = "swimming" if on else "idle"
	set_sprinting(false)
	cancel_action("diving" if on else "restore")
	if gear:
		gear.visible = on
	if mask:
		mask.visible = on


var rowing_query: Callable
var rowing_pose_query: Callable
var _action := "idle"
var _base_action := "idle"
var _last_action := ""
var _actions := {
	"swimming":preload("res://src/player/animation/swimming_action.gd").new(),
	"idle":preload("res://src/player/animation/idle_action.gd").new(),
	"walking":preload("res://src/player/animation/walking_action.gd").new(),
	"climbing":preload("res://src/player/animation/climbing_action.gd").new(),
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
	set_sprinting(false)
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
	body_pivot.position = Vector3.ZERO
	left_arm.position = avatar_shoulder(-1)
	right_arm.position = avatar_shoulder(1)
	left_arm.scale = Vector3.ONE
	right_arm.scale = Vector3.ONE
	left_elbow.rotation.z=-Morphology.REST_ELBOW_OUT
	right_elbow.rotation.z=Morphology.REST_ELBOW_OUT
	left_arm.rotation.z=-float(_avatar_factors.arm_rest)
	right_arm.rotation.z=float(_avatar_factors.arm_rest)
	_item_receive.set_arm_length(left_arm,left_elbow,float(_avatar_factors.arm_length))
	_item_receive.set_arm_length(right_arm,right_elbow,float(_avatar_factors.arm_length))
	left_elbow.get_node("Hand").position.z=0.006*Dimensions.SCALE
	right_elbow.get_node("Hand").position.z=0.006*Dimensions.SCALE
	_last_action = ""
	sync_visual_pose()

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
	_customize_pulse = maxf(0.0, _customize_pulse - delta * 2.2)
	_turn_velocity = move_toward(_turn_velocity, 0.0, delta * 4.5)
	if body_pivot==null: return
	var preserved_yaw := body_pivot.rotation.y
	var playback: Dictionary = _action_playback.capture()
	_action = str(playback.id) if not playback.is_empty() else _base_action
	_farm_action_left = _action_playback.remaining()
	if _last_action != _action:
		_reset_action_pose()
		body_pivot.rotation.y = preserved_yaw
		_last_action = _action
	# 步频只在本帧真的在走路时推进；其余状态冻结相位，切回走路时从脚下开始。
	if _action == "walking":
		var target_blend := 1.0 if _sprinting and walk_speed_ratio > 0.001 else 0.0
		_run_blend = lerpf(_run_blend, target_blend, 1.0 - exp(-delta / RUN_BLEND_TAU))
		if walk_speed_ratio > 0.001:
			var phase_rate := WALK_PHASE_RATE * maxf(WALK_PHASE_FLOOR, walk_speed_ratio)
			phase_rate *= lerpf(1.0, JOG_PHASE_MULTIPLIER, _run_blend)
			_walk_phase = fmod(_walk_phase + delta * phase_rate, TAU)
	else:
		_walk_phase = 0.0
		_sprinting = false
		_run_blend = 0.0
	_actions[_action].sample(self,delta)
	var visible_progress:=action_progress()
	if not playback.is_empty(): visible_progress=clampf((float(playback.elapsed)+delta)/float(playback.duration),0.0,1.0)
	_avatar_visual.expression.sample(_t,_action,visible_progress,delta)
	if not playback.is_empty():
		var completed: Dictionary = _action_playback.advance(delta)
		_farm_action_left = _action_playback.remaining()
		if not completed.is_empty():
			_item_receive.clear()
			_action_events.append({"kind":"finished","id":completed.id,"token":completed.token})
			_flush_action_events()
	sync_visual_pose()

func animation_state() -> String: return _action
