extends RefCounted
## Presentation source for this project's existing node-driven character.
## 2.4s: reach, lift, overhead hold, tuck into satchel, settle.
const DURATION := 2.4
const Produce = preload("res://src/crops/harvest_visual.gd")
var bag: Node3D
var flap: Node3D
var prop: Node3D

func build(actor) -> void:
	bag = Node3D.new()
	bag.name = "Satchel"
	bag.position = Vector3(0.29, 0.49, 0.08)
	actor.body_pivot.add_child(bag)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0; sphere.height = 2.0
	sphere.radial_segments = 16; sphere.rings = 8
	actor._blob(bag, Color("#aa7550"), Vector3.ZERO, Vector3(0.13,0.15,0.10), sphere)
	actor._blob(bag, Color("#654b3c"), Vector3(0,0.13,0), Vector3(0.11,0.025,0.075), sphere)
	flap = Node3D.new()
	flap.name = "Flap"
	flap.position = Vector3(0,0.135,-0.06)
	bag.add_child(flap)
	actor._blob(flap, Color("#d6ac76"), Vector3(0,-0.02,0.07), Vector3(0.13,0.045,0.10), sphere)
	actor._blob(flap, actor.Gold, Vector3(0,-0.045,0.15), Vector3(0.022,0.022,0.012), sphere)
	# Diagonal cloth strap across the chest, below the face.
	var strap := MeshInstance3D.new()
	strap.name = "SatchelStrap"
	var box := BoxMesh.new(); box.size = Vector3(0.038,0.54,0.018)
	strap.mesh = box; strap.material_override = actor._mat(Color("#72533e"))
	strap.position = Vector3(0.015,0.70,0.154); strap.rotation.z = -0.86
	actor.body_pivot.add_child(strap)

func prepare(actor, crop_id: String) -> void:
	clear()
	prop = Produce.create(crop_id)
	if prop == null: return
	prop.name = "ReceivedItem"
	prop.visible = false
	actor.body_pivot.add_child(prop)

func clear() -> void:
	if is_instance_valid(prop):
		prop.get_parent().remove_child(prop)
		prop.queue_free()
	prop = null
	if is_instance_valid(flap): flap.rotation = Vector3.ZERO
	if is_instance_valid(bag): bag.scale = Vector3.ONE

func sample(actor, delta: float) -> void:
	var p := clampf(actor.action_progress() + delta / DURATION, 0.0, 1.0)
	var reach := Vector3(0,0.46,0.35)
	var overhead := Vector3(0,1.60,0.08)
	var mouth := bag.position + Vector3(0,0.15,0.02)
	var center := reach
	var bend := 0.30 * _ease(p,0.0,0.15) * (1.0-_ease(p,0.16,0.39))
	var lift := _ease(p,0.16,0.44)
	var tuck := _ease(p,0.62,0.84)
	var settle := _ease(p,0.90,1.0)
	if p >= 0.16: center = reach.lerp(overhead,lift)
	if p >= 0.62:
		center = overhead.lerp(mouth,tuck)
		center.z += sin(tuck*PI)*0.21
	if p >= 0.84: center = mouth.lerp(bag.position,_ease(p,0.84,0.92))
	actor.body_pivot.rotation.x = bend
	actor.body_pivot.position.y = sin(lift*PI)*0.025
	actor.head_pivot.rotation.x = -0.12*lift*(1.0-tuck)
	actor.head_pivot.rotation.z = 0.05*sin(tuck*PI)
	# Raise the shoulders slightly and allow stylized sleeve extension; solve
	# both wrists against the produce, rather than making it float above hands.
	var shoulders := lift*(1.0-settle)
	actor.left_arm.position = Vector3(-0.255-0.045*shoulders,0.84+0.12*shoulders,0)
	actor.right_arm.position = Vector3(0.255+0.045*shoulders,0.84+0.12*shoulders,0)
	var left := center + Vector3(-0.16,-0.16,0)
	var right := center + Vector3(0.16,-0.16,0)
	left = left.lerp(Vector3(-0.26,0.53,0.03),_ease(p,0.70,0.88))
	right = right.lerp(mouth+Vector3(0.035,-0.04,0.02),tuck)
	left = Vector3(-0.26,0.53,0.03).lerp(left,_ease(p,0.0,0.14))
	right = Vector3(0.26,0.53,0.03).lerp(right,_ease(p,0.0,0.14))
	left = left.lerp(Vector3(-0.255,0.515,0.006),settle)
	right = right.lerp(Vector3(0.255,0.515,0.006),settle)
	_pose_arm(actor.left_arm,actor.left_elbow,left,-1.0)
	_pose_arm(actor.right_arm,actor.right_elbow,right,1.0)
	if is_instance_valid(prop):
		prop.visible = p >= 0.13 and p < 0.92
		prop.position = center
		prop.rotation = Vector3(0,0.18*sin(lift*PI),-0.10*sin(tuck*PI))
		prop.scale = Vector3.ONE*(1.0-0.90*_ease(p,0.84,0.92))
	flap.rotation.x = -1.55*_ease(p,0.65,0.77)*(1.0-_ease(p,0.91,0.98))
	bag.scale = Vector3.ONE*(1.0+0.06*sin(_ease(p,0.87,1.0)*PI))

func _ease(p: float, from: float, to: float) -> float:
	return smoothstep(from,to,p)

func _pose_arm(arm: Node3D, elbow: Node3D, hand: Vector3, side: float) -> void:
	var offset := hand-arm.position
	var distance := maxf(offset.length(),0.001)
	var stretch := maxf(1.0,distance/0.315)
	var upper := 0.17*stretch
	var lower := 0.155*stretch
	var direction := offset/distance
	var axis := Vector3(side,0,0.65)
	var bend := (axis-direction*axis.dot(direction)).normalized()
	var along := clampf((distance*distance+upper*upper-lower*lower)/(2.0*distance),0.0,upper)
	var joint := arm.position+direction*along+bend*sqrt(maxf(0.0,upper*upper-along*along))
	set_arm_length(arm,elbow,stretch)
	arm.quaternion = Quaternion(Vector3.DOWN,(joint-arm.position).normalized())
	elbow.quaternion = Quaternion(Vector3.DOWN,(arm.basis.inverse()*(hand-joint)).normalized())

static func set_arm_length(arm: Node3D, elbow: Node3D, stretch: float) -> void:
	# Lengthen sleeves without shearing the bent forearm or enlarging the hands.
	elbow.position.y = -0.17*stretch
	var upper: Node3D = arm.get_child(0)
	upper.position.y = -0.09*stretch; upper.scale.y = stretch
	var lower: Node3D = elbow.get_child(0)
	lower.position.y = -0.06*stretch; lower.scale.y = stretch
	var hand: Node3D = elbow.get_child(1)
	hand.position.y = -0.155*stretch
