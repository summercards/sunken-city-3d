extends Node3D
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

func play_farm_action(_event: String) -> void:
	_farm_action_left = 1.1

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
	_walking = on


func set_rowing(on: bool) -> void:
	_rowing = on


func set_diving(on: bool) -> void:
	if gear:
		gear.visible = on
	if mask:
		mask.visible = on


func _process(delta: float) -> void:
	_t += delta
	var rowing := Vector2(_t * 3.4, 1.0)
	if get_parent().has_method("rowing_state"):
		rowing = get_parent().rowing_state()
		_rowing = rowing.y > 0.01
	if _farm_action_left > 0.0:
		_farm_action_left = maxf(0.0,_farm_action_left-delta)
		var bend := sin((1.0-_farm_action_left/1.1)*PI)
		body_pivot.rotation.x = bend*0.3
		left_arm.rotation.x = -bend*0.8
		right_arm.rotation.x = -bend*1.1
		return
	if _rowing:
		# 双桨同相划动，人物、船桨和船体使用同一相位及出力。
		var s := sin(rowing.x)
		var blend := 1.0 - exp(-9.0 * delta)
		var arm := lerpf(0.05, -0.95 + s * 0.42, rowing.y)
		var elbow := lerpf(-0.22, -0.35 + s * 0.22, rowing.y)
		left_arm.rotation.x = lerpf(left_arm.rotation.x, arm, blend)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, arm, blend)
		left_elbow.rotation.x = lerpf(left_elbow.rotation.x, elbow, blend)
		right_elbow.rotation.x = lerpf(right_elbow.rotation.x, elbow, blend)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.12 * rowing.y, blend)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.12 * rowing.y, blend)
		body_pivot.rotation.x = lerpf(body_pivot.rotation.x, (0.10 + s * 0.03) * rowing.y, blend)
		body_pivot.position.y = sin(rowing.x) * 0.012 * rowing.y
	elif _walking:
		var s := sin(_t * 6.4)
		left_arm.rotation.x = s * 0.7
		right_arm.rotation.x = -s * 0.7
		left_leg.rotation.x = -s * 0.55
		right_leg.rotation.x = s * 0.55
		left_knee.rotation.x = max(0.0, -s) * 0.5
		right_knee.rotation.x = max(0.0, s) * 0.5
		left_elbow.rotation.x = -0.18
		right_elbow.rotation.x = -0.18
		body_pivot.rotation.x = 0.04
		body_pivot.position.y = abs(sin(_t * 6.4)) * 0.022
	else:
		# 待机：轻微呼吸与左右看
		var breath := sin(_t * 1.5) * 0.012
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.05, clamp(delta * 4.0, 0.0, 1.0))
		right_arm.rotation.x = lerp(right_arm.rotation.x, -0.05, clamp(delta * 4.0, 0.0, 1.0))
		left_elbow.rotation.x = lerp(left_elbow.rotation.x, -0.22, clamp(delta * 4.0, 0.0, 1.0))
		right_elbow.rotation.x = lerp(right_elbow.rotation.x, -0.22, clamp(delta * 4.0, 0.0, 1.0))
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		left_knee.rotation.x = lerp(left_knee.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		right_knee.rotation.x = lerp(right_knee.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		body_pivot.rotation.x = lerp(body_pivot.rotation.x, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		body_pivot.position.y = breath
		head_pivot.rotation.y = sin(_t * 0.55) * 0.28
