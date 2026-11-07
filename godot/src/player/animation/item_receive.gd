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
	bag.position = Vector3(0.19, 0.49, 0.05)*Dimensions.SCALE
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
	var box := BoxMesh.new(); box.size = Vector3(0.025,0.42,0.014)*Dimensions.SCALE
	strap.mesh = box; strap.material_override = actor._mat(Color("#72533e"))
	strap.position = Vector3(0.015,0.65,0.10)*Dimensions.SCALE; strap.rotation.z = -0.65
	actor.body_pivot.add_child(strap)

func fit_body(actor, shape: Dictionary) -> void:
	# Put the bag behind the hanging hand and outside the widest shirt section.
	var s:=Dimensions.SCALE
	bag.position=Vector3(0.15*float(shape.width)*1.10*s+0.102*s,float(shape.hip_y)+0.07*s,-0.095*s)
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]=[]
	for i in 25:
		var t:=i/24.0
		var y: float=lerpf(0.79*s,float(shape.hip_y)+0.06*s,t)
		var radius: float=preload("res://src/avatar/avatar_morphology.gd").shirt_radius_at(y,shape)
		var x:=lerpf(-0.060*float(shape.width)*s,0.145*float(shape.width)*s,t)
		var half_width:=Dimensions.SHIRT_HALF.x*float(shape.width)*radius*s
		var half_depth:=Dimensions.SHIRT_HALF.z*float(shape.depth)*radius*s
		var z:=half_depth*sqrt(maxf(0.0,1.0-pow(x/maxf(half_width,0.001),2)))+0.013*s
		points.append(Vector3(x,y,z))
	for i in points.size()-1:
		var sideways:=Vector3(0.011,0.007,0)*s
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
	var s:=Dimensions.SCALE
	var reach := Vector3(0,0.46,0.35)*s
	var overhead := Vector3(0,actor._avatar_visual.overhead_height(actor),0.08*s)
	var mouth := bag.position + Vector3(0,0.128,0.02)*Dimensions.BAG_SCALE
	var center := reach
	var bend := 0.30 * _ease(p,0.0,0.15) * (1.0-_ease(p,0.16,0.39))
	var lift := _ease(p,0.16,0.44)
	var tuck := _ease(p,0.62,0.82)
	if p >= 0.16:
		center = reach.lerp(overhead,lift)
		# Carry the object around the front of the head, rather than through it.
		center.z+=sqrt(maxf(0.0,sin(lift*PI)))*0.44*s
	if p >= 0.62:
		center = overhead.lerp(mouth,tuck)
		center.z += sqrt(maxf(0.0,sin(tuck*PI)))*0.65*s
	if p >= 0.84: center = mouth.lerp(bag.position,_ease(p,0.84,0.92))
	center.z=maxf(center.z,actor._avatar_visual.carry_front_clearance(actor,center.y))
	actor.body_pivot.rotation.x = bend
	actor.body_pivot.position.y = sin(lift*PI)*0.025*s
	actor.head_pivot.rotation.x = -0.12*lift*(1.0-tuck)
	actor.head_pivot.rotation.z = 0.05*sin(tuck*PI)
	# The produce follows its own display arc. Hands only suggest taking,
	# celebrating and putting away; never extend a limb to follow the prop.
	_pose_gesture(actor,actor.left_arm,actor.left_elbow,-1,p,lift)
	_pose_gesture(actor,actor.right_arm,actor.right_elbow,1,p,lift)
	if is_instance_valid(prop):
		prop.visible = p >= 0.13 and p < 0.92
		prop.position = center
		prop.rotation = Vector3(0,0.18*sin(lift*PI),-0.10*sin(tuck*PI))
		prop.scale = Vector3.ONE*(1.0-0.90*_ease(p,0.84,0.92))
	flap.rotation.x = -1.55*_ease(p,0.65,0.77)*(1.0-_ease(p,0.91,0.98))
	bag.scale = Vector3.ONE*Dimensions.BAG_SCALE*(1.0+0.06*sin(_ease(p,0.87,1.0)*PI))

func _ease(p: float, from: float, to: float) -> float:
	return smoothstep(from,to,p)

func _pose_gesture(actor, arm: Node3D, elbow: Node3D, side: int, p: float, lift: float) -> void:
	var rest: float = actor._avatar_factors.arm_rest
	var reach := _ease(p,0.0,0.14)
	var release := _ease(p,0.60,0.88) if side < 0 else _ease(p,0.66,1.0)
	var gesture := reach*(1.0-release)
	arm.position = actor.avatar_shoulder(side)
	set_arm_length(arm,elbow,float(actor._avatar_factors.arm_length))
	# Bend forward about the elbow's existing local hinge and keep the arms
	# outside the shirt, below the cheeks. The right hand settles slightly later.
	arm.rotation = Vector3(-lerpf(0.40,0.95,lift)*gesture,0,side*(rest+0.12*gesture))
	elbow.rotation = Vector3(-lerpf(0.75,1.05,lift)*gesture,0,side*actor.Morphology.REST_ELBOW_OUT)

static func set_arm_length(_arm: Node3D, elbow: Node3D, length_scale: float) -> void:
	# Only the avatar's authored body proportions determine segment lengths.
	elbow.position.y=-Dimensions.UPPER_ARM*length_scale
	var hand: Node3D=elbow.get_node("Hand")
	hand.position.y=-Dimensions.LOWER_ARM*length_scale
