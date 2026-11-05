extends RefCounted
## Independent geometric probes: inspect rendered resources and skin-deformed
## vertices, not the visual module's own safety report or configuration values.
const Profile = preload("res://src/avatar/avatar_profile.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const RADII := Vector3(0.258,0.25,0.253)
const MORPHS := ["body_build","head_size","eye_spacing","hair_length","hair_volume","hair_sweep","head_width","arm_girth","leg_length"]

static func profile(appearance := {}, morphs := {}) -> Dictionary:
	var result := Profile.fresh(true)
	result.appearance.merge(appearance,true); result.morphs.merge(morphs,true)
	return result

static func cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var styles := Catalog.options("hair_style")
	# Deterministic mixed extremes cover every hair, hat, beard, body and outfit.
	for i in 64:
		var appearance := {}
		for slot in ["hair_style","hat","beard","glasses","body_type","top","bottom","shoes","eyes","fringe","hair_accessory","blush"]:
			var options := Catalog.options(slot)
			var divisor: int={"hair_style":1,"hat":4,"beard":3,"glasses":5,"body_type":1,"top":16,"bottom":7,"shoes":9,"eyes":2,"fringe":11,"hair_accessory":13,"blush":17}[slot]
			appearance[slot] = options[int(i/divisor)%options.size()].id
		var morphs := {}
		for j in MORPHS.size(): morphs[MORPHS[j]] = float((i>>(j%6))&1)
		result.append({"id":"mix-%02d"%i,"profile":profile(appearance,morphs)})
	for i in 32:
		result.append({"id":"shape-new-%02d"%i,"profile":profile({"hair_style":"high_ponytail","hat":["none","bucket","beanie","fedora"][i%4],"beard":"full","body_type":["balanced","pear","athletic","soft"][i%4]},{"body_build":float((i>>3)&1),"head_size":float((i>>4)&1),"head_width":float(i&1),"arm_girth":float((i>>1)&1),"leg_length":float((i>>2)&1)})})
	# Include the default reference, plus long hair with all dimensional maxima.
	result.append({"id":"reference","profile":profile()})
	for style in styles:
		result.append({"id":"hair-"+str(style.id),"profile":profile({"hair_style":style.id,"hat":"none","beard":"full","glasses":"round","blush":"peach"},{"body_build":1.0,"head_size":0.0,"hair_length":1.0,"hair_volume":1.0})})
	return result

static func meshes(node: Node, part := "") -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.find_children("*","MeshInstance3D",true,false):
		if child.mesh != null and child.is_visible_in_tree() and (part=="" or str(child.get_meta("avatar_part",""))==part): result.append(child)
	return result

static func arrays(mesh: Mesh, surface: int) -> Array:
	if mesh is PrimitiveMesh: return mesh.get_mesh_arrays()
	return mesh.surface_get_arrays(surface)

static func points(node: MeshInstance3D, target: Node3D = null, centroids := false) -> PackedVector3Array:
	var result := PackedVector3Array()
	var transform := node.global_transform if target==null else target.global_transform.affine_inverse()*node.global_transform
	for surface in node.mesh.get_surface_count():
		var data := arrays(node.mesh,surface)
		if data.is_empty() or data[Mesh.ARRAY_VERTEX]==null: continue
		var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		for vertex in vertices: result.append(transform*vertex)
		if not centroids: continue
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		for i in range(0,indices.size() if not indices.is_empty() else vertices.size(),3):
			var a: int = i if indices.is_empty() else indices[i]
			var b: int = i+1 if indices.is_empty() else indices[i+1]
			var c: int = i+2 if indices.is_empty() else indices[i+2]
			result.append(transform*((vertices[a]+vertices[b]+vertices[c])/3.0))
	return result

static func bounds(points_: PackedVector3Array) -> AABB:
	if points_.is_empty(): return AABB()
	var result := AABB(points_[0],Vector3.ZERO)
	for p in points_: result=result.expand(p)
	return result

static func part_points(actor: Node3D, part: String, target: Node3D = null) -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh in meshes(actor,part): result.append_array(points(mesh,target))
	return result

static func shirt_solid(shirt: MeshInstance3D, target: Node3D) -> Dictionary:
	# Derive each horizontal polygon from actual triangles. This follows concave
	# waist/shoulder contours; a convex hull would falsely fill the waist gap.
	var transform := target.global_transform.affine_inverse()*shirt.global_transform
	var rings: Dictionary={}; var triangles: Array[Vector3]=[]
	for surface in shirt.mesh.get_surface_count():
		var data:=arrays(shirt.mesh,surface)
		var vertices: PackedVector3Array=data[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		for vertex in vertices:
			var p: Vector3=transform*vertex; var y:=snappedf(p.y,.000001)
			if not rings.has(y): rings[y]={}
			rings[y][Vector2(snappedf(p.x,.000001),snappedf(p.z,.000001))]=true
		for i in indices.size() if not indices.is_empty() else vertices.size(): triangles.append(transform*vertices[i if indices.is_empty() else indices[i]])
	var levels: Array=rings.keys(); levels.sort()
	var polygons: Array=[]
	for y in levels:
		var polygon: Array=rings[y].keys()
		polygon.sort_custom(func(a: Vector2,b: Vector2): return atan2(a.y,a.x)<atan2(b.y,b.x))
		polygons.append(polygon)
	return {"levels":levels,"polygons":polygons,"triangles":triangles,"bounds":bounds(points(shirt,target))}

static func nearest_triangle(point: Vector3,a: Vector3,b: Vector3,c: Vector3) -> Vector3:
	var ab:=b-a; var ac:=c-a; var ap:=point-a
	var d1:=ab.dot(ap); var d2:=ac.dot(ap)
	if d1<=0 and d2<=0: return a
	var bp:=point-b; var d3:=ab.dot(bp); var d4:=ac.dot(bp)
	if d3>=0 and d4<=d3: return b
	var vc:=d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0: return a+ab*(d1/(d1-d3))
	var cp:=point-c; var d5:=ab.dot(cp); var d6:=ac.dot(cp)
	if d6>=0 and d5<=d6: return c
	var vb:=d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0: return a+ac*(d2/(d2-d6))
	var va:=d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0: return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))
	var denominator:=va+vb+vc
	if absf(denominator)<.00000000000001: return a
	return a+ab*(vb/denominator)+ac*(vc/denominator)

static func shirt_depth(point: Vector3, solid: Dictionary) -> float:
	if not solid.bounds.has_point(point): return 0.0
	var levels: Array=solid.levels
	var lower: int=-1
	for i in levels.size()-1:
		if point.y>=levels[i] and point.y<=levels[i+1]: lower=i; break
	if lower<0: return 0.0
	var bottom: Array=solid.polygons[lower]; var top: Array=solid.polygons[lower+1]
	if bottom.size()!=top.size() or bottom.size()<3: return 0.0
	var blend:=inverse_lerp(float(levels[lower]),float(levels[lower+1]),point.y)
	var p2:=Vector2(point.x,point.z)
	for i in bottom.size():
		var a: Vector2=bottom[i].lerp(top[i],blend)
		var b: Vector2=bottom[(i+1)%bottom.size()].lerp(top[(i+1)%top.size()],blend)
		if (b-a).cross(p2-a)<-.0000001: return 0.0
	# The point is inside the actual section. Confirm depth against every real
	# surface triangle rather than using radial distance or an enclosing box.
	var depth:=INF; var triangles: Array=solid.triangles
	for i in range(0,triangles.size(),3):
		depth=minf(depth,point.distance_to(nearest_triangle(point,triangles[i],triangles[i+1],triangles[i+2])))
	return depth

## Sampling thresholds are authored in reference metres and follow body scale.
static func ref_threshold(metres: float) -> float:
	return metres*preload("res://src/avatar/avatar_dimensions.gd").SCALE

static func inside_shirt(point: Vector3, solid: Dictionary) -> bool:
	return shirt_depth(point,solid)>ref_threshold(.008)

static func penetration_detail(actor) -> Dictionary:
	var shirt: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Shirt")
	var solid:=shirt_solid(shirt,actor.body_pivot)
	var report: Dictionary={}
	for id in ["arm.L","arm.R"]:
		var data: Dictionary=actor.limb_skinning.surface_data(id)
		var deformed: PackedVector3Array=actor.limb_skinning.deformed_points(id)
		var worst:=0.0; var at:=Vector3.ZERO; var count:=0; var longitudinal:=0.0
		for i in deformed.size():
			if data.uv2[i].x<=ref_threshold(.09): continue
			var p: Vector3=actor.body_pivot.to_local(actor.limb_skinning.to_global(deformed[i]))
			var depth:=shirt_depth(p,solid)
			if depth<=.008: continue
			count+=1
			if depth>worst: worst=depth; at=p; longitudinal=data.uv2[i].x
		var arm: Node3D=actor.left_arm if id=="arm.L" else actor.right_arm
		var elbow: Node3D=actor.left_elbow if id=="arm.L" else actor.right_elbow
		report[id]={"count":count,"deepest_m":worst,"point_body":str(at),"distance_from_shoulder":longitudinal,"shoulder":str(actor.body_pivot.to_local(arm.global_position)),"elbow":str(actor.body_pivot.to_local(elbow.global_position)),"wrist":str(actor.body_pivot.to_local(elbow.get_node("Hand").global_position))}
	return report

static func arm_geometry(actor) -> Dictionary:
	var head: MeshInstance3D=actor.head_pivot.get_node("AvatarHead/Face")
	var shirt: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Shirt")
	var solid:=shirt_solid(shirt,actor.body_pivot)
	var result: Dictionary={"finite":true,"arm_head":0,"arm_shirt":0,"samples":0}
	for id in ["arm.L","arm.R"]:
		var data: Dictionary=actor.limb_skinning.surface_data(id)
		var deformed: PackedVector3Array=actor.limb_skinning.deformed_points(id)
		for i in deformed.size():
			var world: Vector3=actor.limb_skinning.to_global(deformed[i]); result.samples+=1
			result.finite=result.finite and world.is_finite() and actor.to_local(world).length()<4
			if data.uv2[i].x<ref_threshold(.065): continue
			if head.to_local(world).length_squared()<.94: result.arm_head+=1
			if data.uv2[i].x>ref_threshold(.09) and inside_shirt(actor.body_pivot.to_local(world),solid): result.arm_shirt+=1
	return result

static func head_penetration_detail(actor) -> Dictionary:
	var head: MeshInstance3D=actor.head_pivot.get_node("AvatarHead/Face")
	var report: Dictionary={}
	for id in ["arm.L","arm.R"]:
		var data: Dictionary=actor.limb_skinning.surface_data(id)
		var deformed: PackedVector3Array=actor.limb_skinning.deformed_points(id)
		var worst:=1.0; var at:=Vector3.ZERO; var count:=0; var longitudinal:=0.0
		for i in deformed.size():
			if data.uv2[i].x<=ref_threshold(.065): continue
			var world: Vector3=actor.limb_skinning.to_global(deformed[i])
			var q: Vector3=head.to_local(world)
			if q.length_squared()>=.94: continue
			count+=1
			if q.length_squared()<worst: worst=q.length_squared(); at=actor.body_pivot.to_local(world); longitudinal=data.uv2[i].x
		var arm: Node3D=actor.left_arm if id=="arm.L" else actor.right_arm
		var elbow: Node3D=actor.left_elbow if id=="arm.L" else actor.right_elbow
		report[id]={"count":count,"minimum_normalized_radius_squared":worst,"point_body":str(at),"distance_from_shoulder":longitudinal,"shoulder":str(actor.body_pivot.to_local(arm.global_position)),"elbow":str(actor.body_pivot.to_local(elbow.global_position)),"wrist":str(actor.body_pivot.to_local(elbow.get_node("Hand").global_position))}
	return report

static func produce_geometry(actor) -> Dictionary:
	var result: Dictionary={"finite":true,"visible":false,"vertices":0,"head":0,"hat":0,"minimum_normalized_radius_squared":INF,"point_body":"","center_body":""}
	var prop: Node3D=actor._item_receive.prop
	if not is_instance_valid(prop) or not prop.is_visible_in_tree(): return result
	result.visible=true
	result.center_body=str(actor.body_pivot.to_local(prop.global_position))
	var face: MeshInstance3D=actor.head_pivot.get_node("AvatarHead/Face")
	var hats: Array=[]
	for hat_mesh in meshes(actor.hat):
		hats.append({"transform":hat_mesh.global_transform.affine_inverse()*face.global_transform,"mesh":hat_mesh.mesh})
	for mesh in meshes(prop):
		for point in points(mesh,face,true):
			result.vertices+=1
			result.finite=result.finite and point.is_finite()
			if point.length_squared()<result.minimum_normalized_radius_squared:
				result.minimum_normalized_radius_squared=point.length_squared(); result.point_body=str(actor.body_pivot.to_local(face.to_global(point)))
			if point.length_squared()<.94: result.head+=1
			for hat in hats:
				var p: Vector3=hat.transform*point
				if hat.mesh is CylinderMesh:
					var cylinder: CylinderMesh=hat.mesh
					var radius:=lerpf(cylinder.bottom_radius,cylinder.top_radius,clampf(p.y/cylinder.height+.5,0,1))
					if absf(p.y)<cylinder.height*.5-.002 and Vector2(p.x,p.z).length()<radius-.002: result.hat+=1
				elif hat.mesh is SphereMesh:
					if p.length_squared()<.98: result.hat+=1
	return result

static func tail_attachment_gap(actor) -> float:
	var head: Node3D=actor.head_pivot.get_node("AvatarHead")
	var scalp: MeshInstance3D=head.get_node("Hair/Scalp")
	var scalp_points:=points(scalp,head)
	var minimum:=INF
	for mesh in meshes(head,"hair"):
		if mesh.get_meta("hair_zone","")!="ponytail": continue
		for p in points(mesh,head):
			if (p/RADII).length_squared()>2.4: continue
			for q in scalp_points: minimum=minf(minimum,p.distance_to(q))
	return minimum

static func geometry(actor: Node3D) -> Dictionary:
	var result := {"finite":true,"hair_skull":0,"hair_eye":0,"arm_head":0,"arm_shirt":0,"hair_shirt":0,"beard_shirt":0,"hair_tank":0,"samples":0,"meshes":0}
	var head: Node3D=actor.head_pivot.get_node("AvatarHead")
	var face: MeshInstance3D=head.get_node("Face")
	var shirt: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Shirt")
	var solid := shirt_solid(shirt,actor.body_pivot)
	var tank: MeshInstance3D=actor.gear.get_child(0) if actor.gear.visible and actor.gear.get_child_count()>0 else null
	var eyes: Array[Vector2] = []
	for side in ["EyeLeft","EyeRight"]:
		var eye := head.get_node_or_null("FaceDetails/"+side)
		if eye!=null: eyes.append(Vector2(eye.get_meta("eye_center",Vector2.ZERO)))
	for mesh in meshes(actor):
		result.meshes+=1
		result.finite=result.finite and mesh.global_transform.origin.is_finite() and mesh.global_transform.basis.determinant()>0.000000001
		var samples := points(mesh,head)
		for p in samples: result.finite=result.finite and p.is_finite() and p.length()<8
		result.samples+=samples.size()
		var part: String=str(mesh.get_meta("avatar_part",""))
		if part not in ["hair","beard"]: continue
		for p in points(mesh,head,true):
			var q := Vector3(p.x/RADII.x,p.y/RADII.y,p.z/RADII.z)
			if part=="hair":
				if q.length_squared()<.97: result.hair_skull+=1
				for center in eyes:
					if absf(p.x-center.x)<.034 and p.y>-.043 and p.y<.060:
						var front := RADII.z*sqrt(maxf(0,1-pow(p.x/RADII.x,2)-pow(p.y/RADII.y,2)))
						if p.z>=front-.001: result.hair_eye+=1
			var body_point: Vector3=actor.body_pivot.to_local(head.to_global(p))
			if inside_shirt(body_point,solid): result["hair_shirt" if part=="hair" else "beard_shirt"]+=1
			if part=="hair" and tank!=null and tank.mesh is CylinderMesh:
				var tank_point: Vector3=tank.to_local(head.to_global(p))
				if absf(tank_point.y)<tank.mesh.height*.5-.008 and Vector2(tank_point.x,tank_point.z).length()<minf(tank.mesh.top_radius,tank.mesh.bottom_radius)-.008: result.hair_tank+=1
	for id in actor.limb_skinning.limb_ids():
		var data: Dictionary=actor.limb_skinning.surface_data(id)
		var samples: PackedVector3Array=actor.limb_skinning.deformed_points(id)
		for i in samples.size():
			var world: Vector3=actor.limb_skinning.to_global(samples[i])
			result.finite=result.finite and world.is_finite() and actor.to_local(world).length()<4
			result.samples+=1
			if not str(id).begins_with("arm") or data.uv2[i].x<ref_threshold(.065): continue
			if face.to_local(world).length_squared()<.94: result.arm_head+=1
			# The first 9cm attach under a sleeve. Remaining exposed arm/hand
			# vertices must not disappear more than 8mm inside actual tailoring.
			if data.uv2[i].x>ref_threshold(.09) and inside_shirt(actor.body_pivot.to_local(world),solid): result.arm_shirt+=1
	return result

static func sample_action(actor, id: String, progress: float, crop: String="lettuce") -> void:
	actor.cancel_action("customization-qa"); actor.set_walking(false); actor.set_rowing(false); actor.set_diving(false); actor._reset_action_pose()
	if id=="walking": actor.set_walking(true)
	elif id=="rowing": actor.set_rowing(true)
	elif id=="swimming": actor.set_diving(true)
	elif id!="idle": actor.play_action(id,{"crop":crop} if id=="harvesting" else {})
	actor._process(progress*(2.4 if id=="harvesting" else 1.1))
	actor.sync_visual_pose()
