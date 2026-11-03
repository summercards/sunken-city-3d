extends RefCounted
## Presentation source for this project's existing node-driven character.
## 2.4s: reach, lift, overhead hold, tuck into satchel, settle.
const DURATION := 2.4
const Produce = preload("res://src/crops/harvest_visual.gd")
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
var bag: Node3D
var flap: Node3D
var prop: Node3D
var strap: MeshInstance3D

func build(actor) -> void:
	bag = Node3D.new()
	bag.name = "Satchel"
	bag.position = Vector3(0.19, 0.49, 0.05)
	bag.scale=Vector3.ONE*Dimensions.BAG_SCALE
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
	strap = MeshInstance3D.new()
	strap.name = "SatchelStrap"
	var box := BoxMesh.new(); box.size = Vector3(0.025,0.42,0.014)
	strap.mesh = box; strap.material_override = actor._mat(Color("#72533e"))
	strap.position = Vector3(0.015,0.65,0.10); strap.rotation.z = -0.65
	actor.body_pivot.add_child(strap)

func fit_body(actor, shape: Dictionary) -> void:
	# Put the bag behind the hanging hand and outside the widest shirt section.
	bag.position=Vector3(0.15*float(shape.width)*1.10+0.102,float(shape.hip_y)+0.07,-0.095)
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]=[]
	for i in 25:
		var t:=i/24.0
		var y: float=lerpf(0.79,float(shape.hip_y)+0.06,t)
		var radius: float=preload("res://src/avatar/avatar_morphology.gd").shirt_radius_at(y,shape)
		var x:=lerpf(-0.060*float(shape.width),0.145*float(shape.width),t)
		var half_width:=Dimensions.SHIRT_HALF.x*float(shape.width)*radius
		var half_depth:=Dimensions.SHIRT_HALF.z*float(shape.depth)*radius
		var z:=half_depth*sqrt(maxf(0.0,1.0-pow(x/maxf(half_width,0.001),2)))+0.013
		points.append(Vector3(x,y,z))
	for i in points.size()-1:
		var sideways:=Vector3(0.011,0.007,0)
		for vertex in [points[i]-sideways,points[i+1]-sideways,points[i+1]+sideways,points[i]-sideways,points[i+1]+sideways,points[i]+sideways]: surface.add_vertex(vertex)
	surface.generate_normals(); strap.mesh=surface.commit()
	strap.transform=Transform3D.IDENTITY
	strap.material_override=actor._mat(Color("#72533e"))
	strap.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED

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
	if is_instance_valid(bag): bag.scale = Vector3.ONE*Dimensions.BAG_SCALE

func sample(actor, delta: float) -> void:
	var p := clampf(actor.action_progress() + delta / DURATION, 0.0, 1.0)
	var reach := Vector3(0,0.46,0.35)
	var overhead := Vector3(0,actor._avatar_visual.overhead_height(actor),0.08)
	var mouth := bag.position + Vector3(0,0.128,0.02)*Dimensions.BAG_SCALE
	var center := reach
	var bend := 0.30 * _ease(p,0.0,0.15) * (1.0-_ease(p,0.16,0.39))
	var lift := _ease(p,0.16,0.44)
	var tuck := _ease(p,0.62,0.82)
	var settle := _ease(p,0.90,1.0)
	if p >= 0.16:
		center = reach.lerp(overhead,lift)
		# Carry the object around the front of the head, rather than through it.
		center.z+=sqrt(maxf(0.0,sin(lift*PI)))*0.44
	if p >= 0.62:
		center = overhead.lerp(mouth,tuck)
		center.z += sqrt(maxf(0.0,sin(tuck*PI)))*0.65
	if p >= 0.84: center = mouth.lerp(bag.position,_ease(p,0.84,0.92))
	center.z=maxf(center.z,actor._avatar_visual.carry_front_clearance(actor,center.y))
	actor.body_pivot.rotation.x = bend
	actor.body_pivot.position.y = sin(lift*PI)*0.025
	actor.head_pivot.rotation.x = -0.12*lift*(1.0-tuck)
	actor.head_pivot.rotation.z = 0.05*sin(tuck*PI)
	# Raise the shoulders slightly and allow stylized sleeve extension; solve
	# both wrists against the produce, rather than making it float above hands.
	var shoulders := lift*(1.0-settle)
	actor.left_arm.position = actor.avatar_shoulder(-1)+Vector3(-0.015,0,0)*shoulders
	actor.right_arm.position = actor.avatar_shoulder(1)+Vector3(0.015,0,0)*shoulders
	# The wide reference head needs the raised arms to arc in front of the
	# cheeks. Wrists still support the item's front/lower corners.
	var front_clearance: float=actor.avatar_arm_front_clearance()*lift*(1.0-tuck)
	var left := center + Vector3(-0.16,-0.16,front_clearance)
	var right := center + Vector3(0.16,-0.16,front_clearance)
	if p>=0.60:
		# Release the left hand before the item crosses toward the right bag.
		# Its independent outward/front arc cannot follow the item through belly.
		var retreat:=_ease(p,0.60,0.82)
		var release_front: float=actor.avatar_arm_front_clearance()
		left=(overhead+Vector3(-0.16,-0.16,release_front)).lerp(actor.avatar_rest_hand(-1),retreat)
		left.x-=sin(retreat*PI)*0.17
		left.z+=sin(retreat*PI)*0.10
	right = right.lerp(mouth+Vector3(0.035,-0.04,0.02),tuck)
	left = actor.avatar_rest_hand(-1).lerp(left,_ease(p,0.0,0.14))
	right = actor.avatar_rest_hand(1).lerp(right,_ease(p,0.0,0.14))
	left = left.lerp(actor.avatar_rest_hand(-1),settle)
	right = right.lerp(actor.avatar_rest_hand(1),settle)
	_pose_arm(actor.left_arm,actor.left_elbow,left,-1.0)
	_pose_arm(actor.right_arm,actor.right_elbow,right,1.0)
	if is_instance_valid(prop):
		prop.visible = p >= 0.13 and p < 0.92
		prop.position = center
		prop.rotation = Vector3(0,0.18*sin(lift*PI),-0.10*sin(tuck*PI))
		prop.scale = Vector3.ONE*(1.0-0.90*_ease(p,0.84,0.92))
	flap.rotation.x = -1.55*_ease(p,0.65,0.77)*(1.0-_ease(p,0.91,0.98))
	bag.scale = Vector3.ONE*Dimensions.BAG_SCALE*(1.0+0.06*sin(_ease(p,0.87,1.0)*PI))

func _ease(p: float, from: float, to: float) -> float:
	return smoothstep(from,to,p)

func _pose_arm(arm: Node3D, elbow: Node3D, hand: Vector3, side: float) -> void:
	var offset := hand-arm.position
	var distance := maxf(offset.length(),0.001)
	var clearance:=smoothstep(0.72,1.10,hand.y)
	var stretch := maxf(1.0,distance/((Dimensions.UPPER_ARM+Dimensions.LOWER_ARM)*lerpf(1.0,0.72,clearance)))
	var upper := Dimensions.UPPER_ARM*stretch
	var lower := Dimensions.LOWER_ARM*stretch
	var direction := offset/distance
	var axis := Vector3(side*0.85,-1.0,1.0)
	var bend := (axis-direction*axis.dot(direction)).normalized()
	var along := clampf((distance*distance+upper*upper-lower*lower)/(2.0*distance),0.0,upper)
	var joint := arm.position+direction*along+bend*sqrt(maxf(0.0,upper*upper-along*along))
	set_arm_length(arm,elbow,stretch)
	arm.quaternion = Quaternion(Vector3.DOWN,(joint-arm.position).normalized())
	elbow.quaternion = Quaternion(Vector3.DOWN,(arm.basis.inverse()*(hand-joint)).normalized())

static func set_arm_length(_arm: Node3D, elbow: Node3D, stretch: float) -> void:
	# Pose controls only. Skeleton helper bones stretch the continuous mesh
	# along its length; the next joint never inherits width scale or shear.
	elbow.position.y=-Dimensions.UPPER_ARM*stretch
	var hand: Node3D=elbow.get_node("Hand")
	hand.position.y=-Dimensions.LOWER_ARM*stretch
