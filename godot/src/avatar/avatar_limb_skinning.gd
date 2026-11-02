extends Skeleton3D
## Real GPU skinning: four continuous indexed meshes, no separate elbow/knee solids.
## Existing action nodes are non-rendering pose controls; this is the only limb view.
const Dimensions = preload("res://src/avatar/avatar_dimensions.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const SIDES := 24
var _chains: Dictionary = {}
var _mesh_data: Dictionary = {}
var _skin: Skin
var _appearance: Dictionary = {}

func configure(actor) -> void:
	name="LimbSkeleton"
	add_bone("root")
	set_bone_rest(0,Transform3D.IDENTITY)
	for row in [["arm.L",actor.left_arm,actor.left_elbow,actor.left_elbow.get_node("Hand"),Dimensions.UPPER_ARM,Dimensions.LOWER_ARM,-1.0],
		["arm.R",actor.right_arm,actor.right_elbow,actor.right_elbow.get_node("Hand"),Dimensions.UPPER_ARM,Dimensions.LOWER_ARM,1.0],
		["leg.L",actor.left_leg,actor.left_knee,actor.left_knee.get_node("Foot"),Dimensions.THIGH,Dimensions.SHIN,-1.0],
		["leg.R",actor.right_leg,actor.right_knee,actor.right_knee.get_node("Foot"),Dimensions.THIGH,Dimensions.SHIN,1.0]]:
		var id: String=row[0]
		var upper:=_bone(id+".upper",0,row[1].transform)
		var lower:=_bone(id+".lower",upper,row[2].transform)
		var tip:=_bone(id+".tip",lower,row[3].transform)
		# Scale helpers are children of the rotation controls. They lengthen a
		# segment without passing non-uniform scale/shear into the next joint.
		var upper_skin:=_bone(id+".upper_skin",upper,Transform3D.IDENTITY)
		var lower_skin:=_bone(id+".lower_skin",lower,Transform3D.IDENTITY)
		_chains[id]={"upper":upper,"lower":lower,"tip":tip,"upper_skin":upper_skin,"lower_skin":lower_skin,
			"controls":[weakref(row[1]),weakref(row[2]),weakref(row[3])],"lengths":Vector2(row[4],row[5]),"side":row[6]}
	reset_bone_poses()
	_skin=Skin.new()
	for bone in get_bone_count(): _skin.add_bind(bone,get_bone_global_rest(bone).affine_inverse())
	for id in _chains: _build_limb(id)
	apply_appearance(Catalog.defaults())
	sync_pose()

func _bone(id: String, parent: int, rest: Transform3D) -> int:
	var bone:=get_bone_count(); add_bone(id); set_bone_parent(bone,parent); set_bone_rest(bone,rest); return bone

func sync_pose() -> void:
	for chain in _chains.values():
		var upper: Node3D=chain.controls[0].get_ref()
		var lower: Node3D=chain.controls[1].get_ref()
		var tip: Node3D=chain.controls[2].get_ref()
		if upper==null or lower==null or tip==null: continue
		set_bone_pose(chain.upper,upper.transform)
		set_bone_pose(chain.lower,lower.transform)
		set_bone_pose(chain.tip,tip.transform)
		set_bone_pose_scale(chain.upper_skin,Vector3(1,absf(lower.position.y)/chain.lengths.x,1))
		set_bone_pose_scale(chain.lower_skin,Vector3(1,absf(tip.position.y)/chain.lengths.y,1))

func apply_appearance(raw: Dictionary) -> void:
	_appearance=Catalog.effective(raw)
	for id in _mesh_data:
		var mat: ShaderMaterial=_mesh_data[id].mesh.material_override
		mat.set_shader_parameter("skin_color",Catalog.color(_appearance,"skin"))
		mat.set_shader_parameter("cloth_color",Color("#c0d9e8") if _appearance.top=="vest" else Catalog.color(_appearance,"top_color"))
		mat.set_shader_parameter("trouser_color",Catalog.color(_appearance,"bottom_color"))
		mat.set_shader_parameter("shoe_color",Catalog.color(_appearance,"shoe_color"))
		mat.set_shader_parameter("sole_color",Color("#403b43") if _appearance.shoes=="dress" else Color("#f6edd9"))
		mat.set_shader_parameter("sleeve_end",0.315 if _appearance.top=="vest" else 0.115)
		mat.set_shader_parameter("trouser_end",0.18 if _appearance.bottom=="shorts" else 1.0)
		mat.set_shader_parameter("shoe_start",0.303 if _appearance.shoes=="boots" else 0.341)
		mat.set_shader_parameter("sneakers",_appearance.shoes=="sneakers")

func _profile(id: String) -> Array[Vector4]:
	var knee: float=_chains[id].lengths.x
	var end: float=knee+_chains[id].lengths.y
	if id.begins_with("arm"):
		return [Vector4(-0.025,0,0,0),Vector4(-0.020,0.018,0.018,0),Vector4(-0.010,0.029,0.029,0),
			Vector4(0.005,0.034,0.032,0),Vector4(0.025,0.034,0.032,0),Vector4(0.05,0.034,0.032,0),
			Vector4(0.08,0.034,0.032,0),Vector4(0.105,0.033,0.031,0),Vector4(0.115,0.032,0.030,0),
			Vector4(knee-0.045,0.031,0.029,0),Vector4(knee-0.032,0.0305,0.029,0),Vector4(knee-0.020,0.030,0.0285,0),
			Vector4(knee-0.010,0.0295,0.028,0),Vector4(knee,0.029,0.028,0),Vector4(knee+0.010,0.029,0.028,0),
			Vector4(knee+0.020,0.029,0.028,0),Vector4(knee+0.032,0.029,0.028,0),Vector4(knee+0.045,0.0285,0.0275,0),
			Vector4(0.25,0.027,0.026,0),Vector4(0.285,0.025,0.024,0),Vector4(0.315,0.024,0.023,0.002),
			Vector4(end-0.020,0.028,0.026,0.004),Vector4(end-0.010,0.039,0.034,0.006),Vector4(end,0.043,0.040,0.006),
			Vector4(end+0.016,0.040,0.037,0.006),Vector4(end+0.032,0.030,0.028,0.006),Vector4(end+0.043,0.016,0.015,0.006),Vector4(end+0.047,0,0,0.006)]
	return [Vector4(-0.025,0,0,0),Vector4(-0.018,0.022,0.022,0),Vector4(-0.005,0.032,0.030,0),Vector4(0.015,0.034,0.032,0),
		Vector4(0.05,0.034,0.032,0),Vector4(0.10,0.034,0.032,0),Vector4(0.15,0.0335,0.032,0),
		Vector4(knee-0.04,0.033,0.0315,0),Vector4(knee-0.025,0.0325,0.031,0),Vector4(knee-0.012,0.032,0.031,0),
		Vector4(knee,0.032,0.031,0),Vector4(knee+0.012,0.032,0.031,0),Vector4(knee+0.025,0.0325,0.031,0),
		Vector4(knee+0.04,0.033,0.031,0),Vector4(knee+0.065,0.034,0.031,0),
		Vector4(end-0.065,0.031,0.029,0),Vector4(end-0.045,0.027,0.027,0.003),Vector4(end-0.025,0.027,0.032,0.008),
		Vector4(end-0.012,0.034,0.052,0.018),Vector4(end,0.043,0.075,0.025),Vector4(end+0.012,0.044,0.080,0.025),
		Vector4(end+0.024,0.043,0.076,0.025),Vector4(end+0.032,0.036,0.064,0.025),Vector4(end+0.035,0,0,0.025)]

func _weights(d: float, chain: Dictionary) -> Vector3:
	var end: float=chain.lengths.x+chain.lengths.y
	var distal:=smoothstep(end-0.035,end+0.020,d)
	var bend:=smoothstep(chain.lengths.x-0.045,chain.lengths.x+0.045,d)
	return Vector3((1-bend)*(1-distal),bend*(1-distal),distal)

func _build_limb(id: String) -> void:
	var chain: Dictionary=_chains[id]
	var profile:=_profile(id)
	var origin: Vector3=get_bone_global_rest(chain.upper).origin
	var vertices:=PackedVector3Array(); var normals:=PackedVector3Array()
	var uv:=PackedVector2Array(); var uv2:=PackedVector2Array()
	var bones:=PackedInt32Array(); var weights:=PackedFloat32Array(); var indices:=PackedInt32Array()
	var rings: Array[Dictionary]=[]
	for i in profile.size():
		var p: Vector4=profile[i]
		var count:=1 if p.y==0 else SIDES
		var start:=vertices.size()
		var prev: Vector4=profile[maxi(0,i-1)]; var next: Vector4=profile[mini(profile.size()-1,i+1)]
		var step:=maxf(next.x-prev.x,0.0001)
		var side_offset:=0.0
		if id.begins_with("arm"):
			side_offset=float(chain.side)*(-0.024*(1.0-smoothstep(-0.02,0.045,p.x))+0.018*smoothstep(0.0,0.05,p.x)*(1.0-smoothstep(0.105,chain.lengths.x,p.x)))
		for j in count:
			var angle:=TAU*j/SIDES
			vertices.append(origin+Vector3(side_offset+cos(angle)*p.y,-p.x,p.w+sin(angle)*p.z))
			var normal:=Vector3.UP if i==0 else Vector3.DOWN
			if count>1:
				var tangent:=Vector3(-sin(angle)*p.y,0,cos(angle)*p.z)
				var longitudinal:=Vector3((next.y-prev.y)/step*cos(angle),-1,(next.w-prev.w)/step+(next.z-prev.z)/step*sin(angle))
				normal=tangent.cross(longitudinal).normalized()
			normals.append(normal)
			uv.append(Vector2(float(j)/SIDES,(p.x+0.025)/(profile[-1].x+0.025)))
			uv2.append(Vector2(p.x,p.x-(chain.lengths.x+chain.lengths.y)))
			var blend:=_weights(p.x,chain)
			bones.append_array(PackedInt32Array([chain.upper_skin,chain.lower_skin,chain.tip,0]))
			weights.append_array(PackedFloat32Array([blend.x,blend.y,blend.z,0]))
		rings.append({"start":start,"count":count,"distance":p.x})
	for i in rings.size()-1:
		var a: Dictionary=rings[i]; var b: Dictionary=rings[i+1]
		for j in SIDES:
			var n: int=(j+1)%SIDES
			if a.count==1: indices.append_array(PackedInt32Array([a.start,b.start+n,b.start+j]))
			elif b.count==1: indices.append_array(PackedInt32Array([a.start+j,a.start+n,b.start]))
			else: indices.append_array(PackedInt32Array([a.start+j,b.start+n,b.start+j,a.start+j,a.start+n,b.start+n]))
	# Godot's front faces use clockwise winding (the cross product points inward).
	for i in range(0,indices.size(),3):
		var swap: int=indices[i+1]; indices[i+1]=indices[i+2]; indices[i+2]=swap
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_TEX_UV2]=uv2
	arrays[Mesh.ARRAY_BONES]=bones; arrays[Mesh.ARRAY_WEIGHTS]=weights; arrays[Mesh.ARRAY_INDEX]=indices
	var resource:=ArrayMesh.new(); resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var mesh:=MeshInstance3D.new(); mesh.name=id.replace(".","_")+"_Continuous"; mesh.mesh=resource; mesh.skin=_skin
	add_child(mesh); mesh.skeleton=mesh.get_path_to(self)
	mesh.custom_aabb=AABB(Vector3(-2,-1.5,-2),Vector3(4,4.5,4))
	var mat:=ShaderMaterial.new(); mat.shader=preload("res://shaders/avatar_limb.gdshader")
	mat.set_shader_parameter("is_leg",id.begins_with("leg")); mesh.material_override=mat
	_mesh_data[id]={"mesh":mesh,"vertices":vertices,"normals":normals,"bones":bones,"weights":weights,"indices":indices,"uv2":uv2,"rings":rings}

func limb_ids() -> Array: return _mesh_data.keys()
func limb_mesh(id: String) -> MeshInstance3D: return _mesh_data[id].mesh
func surface_data(id: String) -> Dictionary:
	var data: Dictionary=_mesh_data[id].duplicate(true); data.erase("mesh"); return data

## Read-only validation/query port; production renders the GPU-skinned mesh.
func deformed_points(id: String, region := "all") -> PackedVector3Array:
	var data: Dictionary=_mesh_data[id]; var chain: Dictionary=_chains[id]
	var transforms: Array[Transform3D]=[]
	for bone in get_bone_count(): transforms.append(get_bone_global_pose(bone)*_skin.get_bind_pose(bone))
	var result:=PackedVector3Array()
	for i in data.vertices.size():
		var d: float=data.uv2[i].x
		if region=="shoulder" and d>0.13: continue
		if region=="foot" and d<chain.lengths.x+chain.lengths.y-0.04: continue
		var point:=Vector3.ZERO
		for influence in 4:
			var slot: int=i*4+influence
			point+=(transforms[data.bones[slot]]*data.vertices[i])*data.weights[slot]
		result.append(point)
	return result
