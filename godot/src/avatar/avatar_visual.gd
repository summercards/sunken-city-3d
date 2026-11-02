extends RefCounted
## Original procedural cosmetic source. Never touches the motor, collision or state.
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
var _roots: Array[Node3D] = []
var _sphere: SphereMesh
var _materials: Dictionary = {}

func apply(actor, raw: Dictionary) -> void:
	for node in _roots:
		if is_instance_valid(node): node.get_parent().remove_child(node); node.queue_free()
	_roots.clear()
	_materials.clear()
	if _sphere == null:
		_sphere = SphereMesh.new(); _sphere.radius=1; _sphere.height=2
		_sphere.radial_segments=32; _sphere.rings=20
	var s := Catalog.effective(raw)
	var skin := Catalog.color(s,"skin")
	var hair := Catalog.color(s,"hair_color")
	var top := Catalog.color(s,"top_color")
	var bottom := Catalog.color(s,"bottom_color")
	var shoe := Catalog.color(s,"shoe_color")
	var torso := _root(actor.body_pivot,"AvatarBody")
	var shirt:=_shirt(torso,top)
	shirt.name="Shirt"
	_blob(torso,bottom,Vector3(0,0.427,0),Vector3(0.100,0.036,0.077))
	_blob(torso,skin,Vector3(0,0.815,0),Vector3(0.045,0.042,0.045))
	_blob(torso,top.lightened(0.22),Vector3(0,0.8,0.015),Vector3(0.072,0.012,0.051))
	if s.top == "stripe":
		var striped:=ShaderMaterial.new(); striped.shader=preload("res://shaders/avatar_cloth.gdshader")
		striped.set_shader_parameter("base_color",top); shirt.material_override=striped
	elif s.top == "sailor":
		for side in [-1,1]:
			var collar := _blob(torso,Color("#fff0d3"),Vector3(side*0.043,0.755,0.085),Vector3(0.023,0.065,0.012))
			collar.rotation.z=side*-0.55
		_blob(torso,Color("#d98672"),Vector3(0,0.70,0.10),Vector3(0.018,0.034,0.012))
	elif s.top == "vest":
		for side in [-1,1]:
			var collar:=_blob(torso,Color("#d3e5ed"),Vector3(side*0.036,0.776,0.073),Vector3(0.022,0.055,0.012))
			collar.rotation.z=side*-0.55
		for y in [0.69,0.63,0.57,0.51]: _blob(torso,top.darkened(0.25),Vector3(0,y,0.099),Vector3(0.010,0.012,0.007))
	actor.limb_skinning.apply_appearance(s)
	var head := _root(actor.head_pivot,"AvatarHead")
	head.scale=Dimensions.HEAD_SCALE
	var face:=_blob(head,skin,Vector3.ZERO,Vector3(0.258,0.25,0.253))
	face.name="Face"
	for side in [-1,1]:
		var ear:=_blob(head,skin,Vector3(side*0.249,-0.016,0),Vector3(0.044,0.062,0.042))
		ear.name="EarLeft" if side<0 else "EarRight"
		_blob(head,skin.darkened(0.12),Vector3(side*0.27,-0.015,0.024),Vector3(0.018,0.033,0.012))
	_hair(head,s.hair_style,hair,s.hat!="none")
	for side in [-1,1]:
		var x: float=side*0.092
		var eye := Vector3(x,0.005,0.238)
		if s.eyes == "smile":
			_arc(head,Color("#403932"),eye,0.036,0.017,0.011,0,PI)
		else:
			var eye_size := Vector3(0.047,0.067,0.013)
			if s.eyes=="oval": eye_size=Vector3(0.048,0.052,0.013)
			if s.eyes=="sleepy": eye_size=Vector3(0.049,0.038,0.013)
			_blob(head,Color("#fff8e8"),eye,eye_size)
			_blob(head,Catalog.color(s,"eye_color"),eye+Vector3(0,-0.003,0.013),eye_size*Vector3(0.64,0.85,0.6))
			_blob(head,Color("#303039"),eye+Vector3(0,-0.003,0.020),eye_size*Vector3(0.33,0.65,0.4))
			_blob(head,Color("#fffbf1"),eye+Vector3(-0.009,0.019,0.025),Vector3(0.010,0.014,0.004))
		var brow := _blob(head,hair,Vector3(x,0.098,0.220),Vector3(0.046,0.009,0.009))
		brow.rotation.z=side*(0.16 if s.brows=="soft" else (0.37 if s.brows=="arch" else 0.0))
		if s.blush == "peach": _blob(head,Color("#df9a87"),Vector3(side*0.163,-0.069,0.192),Vector3(0.040,0.021,0.008))
		elif s.blush == "freckles":
			for offset in [-1,0,1]: _blob(head,Color("#aa7250"),Vector3(side*(0.141+offset*0.021),-0.065+abs(offset)*0.009,0.205),Vector3(0.005,0.006,0.005))
	var nose_size := Vector3(0.028,0.029,0.030)
	if s.nose=="oval": nose_size=Vector3(0.024,0.040,0.027)
	if s.nose=="tiny": nose_size*=0.65
	_blob(head,skin.darkened(0.035),Vector3(0,-0.04,0.255),nose_size)
	var lip := Color("#995f55")
	if s.mouth=="oh":
		_blob(head,lip,Vector3(0,-0.116,0.225),Vector3(0.018,0.025,0.009))
	elif s.mouth=="calm":
		_blob(head,lip,Vector3(0,-0.114,0.227),Vector3(0.028,0.006,0.008))
	else:
		_arc(head,lip,Vector3(0,-0.095,0.233),0.048 if s.mouth=="wide" else 0.032,0.032,0.007,PI,TAU)
	actor.hat=_root(actor.head_pivot,"AvatarHat")
	actor.hat.scale=Dimensions.HEAD_SCALE
	if s.hat=="fedora": actor.hat.scale.z*=0.82
	_hat(actor.hat,s.hat,Catalog.color(s,"hat_color"))
	if s.glasses!="none":
		for side in [-1,1]:
			_arc(head,Color("#6b6259"),Vector3(side*0.094,0.008,0.270),0.063,0.075 if s.glasses=="round" else 0.052,0.007,0,TAU)
		_blob(head,Color("#6b6259"),Vector3(0,0.02,0.272),Vector3(0.035,0.006,0.006))
	actor.set_meta("avatar_appearance",raw.duplicate(true))

func _root(parent: Node3D, id: String) -> Node3D:
	var node:=Node3D.new(); node.name=id; parent.add_child(node); _roots.append(node); return node

func _material(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not _materials.has(key):
		var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=0.9
		mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
		_materials[key]=mat
	return _materials[key]

func _tint(mesh: MeshInstance3D, color: Color) -> void: mesh.material_override=_material(color)

func _blob(parent: Node3D, color: Color, pos: Vector3, dimensions: Vector3) -> MeshInstance3D:
	var node:=MeshInstance3D.new(); node.mesh=_sphere; node.material_override=_material(color)
	node.position=pos; node.scale=dimensions; parent.add_child(node); return node

func _shirt(parent: Node3D, color: Color) -> MeshInstance3D:
	# Rounded tailored silhouette: the sides remain nearly straight instead of
	# a sphere's large belly and pinched shoulders/hem.
	var rings: Array[Vector2]=[Vector2(-1.01,0.01),Vector2(-1,0.82),Vector2(-0.95,0.99),Vector2(-0.86,1),Vector2(0.60,0.82),Vector2(0.88,0.72),Vector2(1,0.56),Vector2(1.01,0.01)]
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings.size()-1:
		for j in 32:
			var a:=TAU*j/32.0; var b:=TAU*(j+1)/32.0
			var p:=Vector3(cos(a)*rings[i].y,rings[i].x,sin(a)*rings[i].y)
			var q:=Vector3(cos(b)*rings[i].y,rings[i].x,sin(b)*rings[i].y)
			var r:=Vector3(cos(a)*rings[i+1].y,rings[i+1].x,sin(a)*rings[i+1].y)
			var t:=Vector3(cos(b)*rings[i+1].y,rings[i+1].x,sin(b)*rings[i+1].y)
			for vertex in [p,t,r,p,q,t]: surface.add_vertex(vertex)
	surface.generate_normals()
	var node:=MeshInstance3D.new(); node.mesh=surface.commit(); node.material_override=_material(color)
	node.position=Vector3(0,Dimensions.SHIRT_CENTER,0); node.scale=Dimensions.SHIRT_HALF; parent.add_child(node); return node

func _cylinder(parent: Node3D, color: Color, pos: Vector3, top: float, bottom: float, height: float) -> void:
	var mesh:=CylinderMesh.new(); mesh.top_radius=top; mesh.bottom_radius=bottom; mesh.height=height; mesh.radial_segments=40
	var node:=MeshInstance3D.new(); node.mesh=mesh; node.material_override=_material(color); node.position=pos; parent.add_child(node)

func _hair(head: Node3D, style: String, color: Color, covered: bool) -> void:
	_blob(head,color,Vector3(0,0.158,-0.015),Vector3(0.266,0.119,0.252))
	for i in 5:
		var x: float=(i-2)*0.075
		var fringe:=_blob(head,color,Vector3(x,0.135+(0.022*i if style=="side" else -0.016*abs(i-2)),0.19-abs(x)*0.20),Vector3(0.064,0.085 if style=="crop" else 0.10,0.065))
		fringe.rotation.z=-0.3 if style=="side" else (i-2)*0.10
	for side in [-1,1]:
		_blob(head,color,Vector3(side*0.224,0.034,-0.006),Vector3(0.047,0.10 if style in ["crop","side"] else 0.18,0.145))
	if style in ["bob","wave"]:
		_blob(head,color,Vector3(0,0.002,-0.16),Vector3(0.231,0.229,0.115))
	if style=="wave":
		for side in [-1,1]:
			for i in 3: _blob(head,color.lightened(0.015*i),Vector3(side*(0.22+0.012*(i%2)),-0.04-i*0.055,0.002),Vector3(0.075,0.07,0.12))
	if style=="bun" and not covered: _blob(head,color,Vector3(0,0.281,-0.075),Vector3(0.11,0.10,0.10))
	if style=="twin" and not covered:
		for side in [-1,1]: _blob(head,color,Vector3(side*0.23,0.17,-0.09),Vector3(0.10,0.10,0.10))

func _hat(parent: Node3D, style: String, color: Color) -> void:
	if style=="fedora":
		_cylinder(parent,color,Vector3(0,0.215,0),0.30,0.31,0.018)
		_cylinder(parent,color,Vector3(0,0.335,-0.01),0.215,0.25,0.19)
		_cylinder(parent,color.darkened(0.30),Vector3(0,0.255,-0.01),0.248,0.251,0.035)
	elif style=="bucket":
		_cylinder(parent,color,Vector3(0,0.215,0),0.28,0.34,0.045)
		_cylinder(parent,color,Vector3(0,0.278,-0.01),0.19,0.25,0.12)
		_cylinder(parent,color.darkened(0.10),Vector3(0,0.24,-0.01),0.24,0.25,0.025)
	elif style=="beanie":
		_blob(parent,color,Vector3(0,0.16,-0.01),Vector3(0.275,0.17,0.27))
		_cylinder(parent,color.lightened(0.15),Vector3(0,0.16,0),0.269,0.269,0.06)
		_blob(parent,color,Vector3(0,0.335,0),Vector3(0.052,0.052,0.052))

func _arc(parent: Node3D, color: Color, center: Vector3, width: float, height: float, radius: float, start: float, end: float) -> void:
	var mesh:=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps:=24
	for i in steps:
		var a:=lerpf(start,end,float(i)/steps); var b:=lerpf(start,end,float(i+1)/steps)
		var p:=center+Vector3(cos(a)*width,sin(a)*height,0)
		var q:=center+Vector3(cos(b)*width,sin(b)*height,0)
		for j in 6:
			var r:=TAU*j/6; var t:=TAU*(j+1)/6
			var n:=Vector3(cos(a)*cos(r),sin(a)*cos(r),sin(r))
			var m:=Vector3(cos(b)*cos(r),sin(b)*cos(r),sin(r))
			var u:=Vector3(cos(a)*cos(t),sin(a)*cos(t),sin(t))
			var v:=Vector3(cos(b)*cos(t),sin(b)*cos(t),sin(t))
			for pair in [[p+n*radius,n],[q+m*radius,m],[q+v*radius,v],[p+n*radius,n],[q+v*radius,v],[p+u*radius,u]]:
				mesh.surface_set_normal(pair[1]); mesh.surface_add_vertex(pair[0])
	mesh.surface_end()
	var node:=MeshInstance3D.new(); node.mesh=mesh; node.material_override=_material(color); parent.add_child(node)
