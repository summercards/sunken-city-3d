extends RefCounted
## Original procedural cosmetic source. Never touches the motor, collision or state.
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const Morphology = preload("res://src/avatar/avatar_morphology.gd")
var _face = preload("res://src/avatar/avatar_face.gd").new()
var _hair_module = preload("res://src/avatar/avatar_hair.gd").new()
var expression = preload("res://src/avatar/avatar_expression.gd").new()
var _native_head_top := -1.0
var _native_head_front := 0.0

func face_metrics() -> Dictionary: return _face.metrics()
func hair_metrics() -> Dictionary: return _hair_module.metrics()
func overhead_height(actor) -> float:
	if _native_head_top<0.0:
		_native_head_top=0.0
		for root in _roots:
			if not is_instance_valid(root) or root.get_parent()!=actor.head_pivot: continue
			for mesh in root.find_children("*","MeshInstance3D",true,false):
				var xf: Transform3D=actor.head_pivot.global_transform.affine_inverse()*mesh.global_transform
				var bounds: AABB=xf*mesh.mesh.get_aabb()
				_native_head_top=maxf(_native_head_top,bounds.end.y)
				_native_head_front=maxf(_native_head_front,bounds.end.z)
	return maxf(1.60,actor.head_pivot.position.y+_native_head_top*actor.head_pivot.scale.y+0.25)

func carry_front_clearance(actor, height: float) -> float:
	var top:=overhead_height(actor)-0.25
	var bottom: float=actor.head_pivot.position.y-0.22*actor.head_pivot.scale.y
	var crossing:=smoothstep(bottom-0.26,bottom-0.02,height)*(1.0-smoothstep(top+0.18,top+0.25,height))
	return crossing*(_native_head_front*actor.head_pivot.scale.z+0.25)
var _roots: Array[Node3D] = []
var _sphere: SphereMesh
var _materials: Dictionary = {}

func apply(actor, raw: Dictionary, morphs: Dictionary = {}, factors: Dictionary = {}) -> void:
	for node in _roots:
		if is_instance_valid(node): node.get_parent().remove_child(node); node.queue_free()
	_roots.clear()
	_native_head_top=-1.0
	_native_head_front=0.0
	_materials.clear()
	if _sphere == null:
		_sphere = SphereMesh.new(); _sphere.radius=1; _sphere.height=2
		_sphere.radial_segments=32; _sphere.rings=20
	var s := Catalog.effective(raw)
	var skin := Catalog.color(s,"skin")
	var shape := Morphology.factors(morphs,s) if factors.is_empty() else factors
	var top := Catalog.color(s,"top_color")
	var bottom := Catalog.color(s,"bottom_color")
	var shoe := Catalog.color(s,"shoe_color")
	var torso := _root(actor.body_pivot,"AvatarBody")
	torso.scale=Vector3(shape.width,1,shape.depth)
	var shirt:=_shirt(torso,top,shape)
	shirt.name="Shirt"
	_pelvis(torso,bottom,shape)
	_blob(torso,skin,Vector3(0,0.815,0),Vector3(0.045,0.042,0.045))
	_blob(torso,top.lightened(0.22),Vector3(0,0.8,0.015),Vector3(0.052,0.012,0.045))
	if s.top == "stripe":
		var striped:=ShaderMaterial.new(); striped.shader=preload("res://shaders/avatar_cloth.gdshader")
		striped.set_shader_parameter("base_color",top); shirt.material_override=striped
	elif s.top == "sailor":
		for side in [-1,1]:
			var collar := _blob(torso,Color("#fff0d3"),Vector3(side*0.043,0.755,Morphology.shirt_front(side*0.043,0.755,shape)+0.010),Vector3(0.023,0.065,0.012))
			collar.rotation.z=side*-0.55
		_blob(torso,Color("#d98672"),Vector3(0,0.70,Morphology.shirt_front(0,0.70,shape)+0.010),Vector3(0.018,0.034,0.012))
	elif s.top == "vest":
		for side in [-1,1]:
			var collar:=_blob(torso,Color("#d3e5ed"),Vector3(side*0.036,0.776,Morphology.shirt_front(side*0.036,0.776,shape)+0.010),Vector3(0.022,0.055,0.012))
			collar.rotation.z=side*-0.55
		for y in [0.69,0.63,0.57,0.51]: _blob(torso,top.darkened(0.25),Vector3(0,y,Morphology.shirt_front(0,y,shape)+0.006),Vector3(0.010,0.012,0.007))
	actor.limb_skinning.apply_appearance(s)
	var head := _root(actor.head_pivot,"AvatarHead")
	head.scale=Dimensions.HEAD_SCALE
	var face:=_blob(head,skin,Vector3.ZERO,Vector3(0.258,0.25,0.253))
	face.name="Face"
	for side in [-1,1]:
		var ear:=_blob(head,skin,Vector3(side*0.249,-0.016,0),Vector3(0.044,0.062,0.042))
		ear.name="EarLeft" if side<0 else "EarRight"
		_blob(head,skin.darkened(0.12),Vector3(side*0.27,-0.015,0.024),Vector3(0.018,0.033,0.012))
	_face.build(head,s,morphs)
	expression.bind(head.get_node("FaceDetails"))
	_hair_module.build(head,s,morphs)
	actor.hat=_root(actor.head_pivot,"AvatarHat")
	actor.hat.scale=Dimensions.HEAD_SCALE
	actor.hat.position.y=-0.018 if s.hat=="beanie" else -0.028
	if s.hat=="fedora": actor.hat.scale.z*=0.82
	_hat(actor.hat,s.hat,Catalog.color(s,"hat_color"))
	actor.set_meta("avatar_appearance",raw.duplicate(true))

func _root(parent: Node3D, id: String) -> Node3D:
	var node:=Node3D.new(); node.name=id; parent.add_child(node); _roots.append(node); return node

func _material(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not _materials.has(key):
		var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=0.84
		mat.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
		mat.rim_enabled=true; mat.rim=0.14; mat.rim_tint=0.35
		_materials[key]=mat
	return _materials[key]

func _tint(mesh: MeshInstance3D, color: Color) -> void: mesh.material_override=_material(color)

func _blob(parent: Node3D, color: Color, pos: Vector3, dimensions: Vector3) -> MeshInstance3D:
	var node:=MeshInstance3D.new(); node.mesh=_sphere; node.material_override=_material(color)
	node.position=pos; node.scale=dimensions; parent.add_child(node); return node

func _shirt(parent: Node3D, color: Color, shape: Dictionary) -> MeshInstance3D:
	# Rounded tailored silhouette: the sides remain nearly straight instead of
	# a sphere's large belly and pinched shoulders/hem.
	var rings:=Morphology.shirt_rings()
	for i in rings.size(): rings[i].y=Morphology.shirt_radius(rings[i].x,rings[i].y,shape)
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
	node.position=Vector3(0,shape.shirt_center,0); node.scale=Vector3(Dimensions.SHIRT_HALF.x,shape.shirt_half_y,Dimensions.SHIRT_HALF.z); parent.add_child(node); return node

func _pelvis(parent: Node3D, color: Color, shape: Dictionary) -> void:
	# A single rounded upper-trouser shell overlaps the shirt hem and the two
	# skinned thighs. No detached flattened sphere masquerades as the waist.
	var rings: Array[Vector3]=[Vector3(-0.055,0.012,0.015),Vector3(-0.037,0.092,0.065),Vector3(-0.018,0.132,0.079),Vector3(0.025,0.143,0.085),Vector3(0.055,0.135,0.077),Vector3(0.072,0.010,0.010)]
	for i in rings.size(): rings[i].x+=float(shape.hip_y)
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings.size()-1:
		for j in 48:
			var a:=TAU*j/48.0; var b:=TAU*(j+1)/48.0
			var p:=Vector3(cos(a)*rings[i].y,rings[i].x,sin(a)*rings[i].z)
			var q:=Vector3(cos(b)*rings[i].y,rings[i].x,sin(b)*rings[i].z)
			var r:=Vector3(cos(a)*rings[i+1].y,rings[i+1].x,sin(a)*rings[i+1].z)
			var t:=Vector3(cos(b)*rings[i+1].y,rings[i+1].x,sin(b)*rings[i+1].z)
			for vertex in [p,t,r,p,q,t]: surface.add_vertex(vertex)
	surface.generate_normals()
	var node:=MeshInstance3D.new(); node.name="Pelvis"; node.mesh=surface.commit(); node.material_override=_material(color)
	parent.add_child(node)

func _cylinder(parent: Node3D, color: Color, pos: Vector3, top: float, bottom: float, height: float) -> void:
	var mesh:=CylinderMesh.new(); mesh.top_radius=top; mesh.bottom_radius=bottom; mesh.height=height; mesh.radial_segments=40
	var node:=MeshInstance3D.new(); node.mesh=mesh; node.material_override=_material(color); node.position=pos; parent.add_child(node)

func _hat(parent: Node3D, style: String, color: Color) -> void:
	if style=="fedora":
		_cylinder(parent,color,Vector3(0,0.215,0),0.30,0.31,0.018)
		_cylinder(parent,color,Vector3(0,0.335,-0.01),0.215,0.25,0.19)
		_cylinder(parent,color.darkened(0.30),Vector3(0,0.2385,-0.01),0.248,0.251,0.035)
	elif style=="bucket":
		_cylinder(parent,color,Vector3(0,0.215,0),0.28,0.34,0.045)
		_cylinder(parent,color,Vector3(0,0.278,-0.01),0.19,0.25,0.12)
		_cylinder(parent,color.darkened(0.10),Vector3(0,0.24,-0.01),0.24,0.25,0.025)
	elif style=="beanie":
		_blob(parent,color,Vector3(0,0.16,-0.01),Vector3(0.275,0.17,0.27))
		_cylinder(parent,color.lightened(0.15),Vector3(0,0.16,0),0.269,0.269,0.06)
		_blob(parent,color,Vector3(0,0.335,0),Vector3(0.052,0.052,0.052))
