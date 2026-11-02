extends SceneTree
## Topology + real skin weights + bone-only deformation, then current action poses.
const Catalog=preload("res://src/avatar/avatar_catalog.gd")
var checks:=0
var failures:=0
var actor
var skeleton: Skeleton3D
var camera: Camera3D
var caption: Label

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-skinning] ","PASS " if ok else "FAIL ",label)

func _edge(edges: Dictionary, a: int, b: int) -> void:
	var key: String="%d/%d" % [mini(a,b),maxi(a,b)]
	edges[key]=int(edges.get(key,0))+1

func topology(id: String) -> void:
	var data: Dictionary=skeleton.surface_data(id)
	var mesh: MeshInstance3D=skeleton.limb_mesh(id)
	check(mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count()==1 and mesh.skin!=null,"one skinned surface "+id)
	check(mesh.get_node(mesh.skeleton)==skeleton,"mesh uses actual Skeleton3D "+id)
	var edges: Dictionary={}; var adjacency: Dictionary={}
	var positions: PackedVector3Array=data.vertices
	var indices: PackedInt32Array=data.indices
	for i in range(0,indices.size(),3):
		var a: int=indices[i]; var b: int=indices[i+1]; var c: int=indices[i+2]
		_edge(edges,a,b); _edge(edges,b,c); _edge(edges,c,a)
		for pair in [[a,b],[b,c],[c,a],[b,a],[c,b],[a,c]]:
			if not adjacency.has(pair[0]): adjacency[pair[0]]=[]
			adjacency[pair[0]].append(pair[1])
	var closed:=true
	for count in edges.values(): closed=closed and count==2
	check(closed,"closed welded surface, no open elbow/knee ring "+id)
	var visited: Dictionary={0:true}; var queue: Array=[0]
	while not queue.is_empty():
		var at: int=queue.pop_back()
		for next in adjacency[at]:
			if not visited.has(next): visited[next]=true; queue.append(next)
	check(visited.size()==positions.size(),"all vertices form one connected limb "+id)
	var valid:=true; var blended:=0
	for i in positions.size():
		var total:=0.0; var influences:=0
		for j in 4:
			var weight: float=data.weights[i*4+j]; var bone: int=data.bones[i*4+j]
			valid=valid and is_finite(weight) and weight>=0 and bone>=0 and bone<skeleton.get_bone_count()
			total+=weight
			if weight>0.001: influences+=1
		valid=valid and absf(total-1.0)<0.00001
		if influences>1: blended+=1
	check(valid and blended>=144,"normalized multi-bone joint weights "+id+" blended="+str(blended))
	# Godot's clockwise triangle convention must agree with its own primitive.
	var primitive:=SphereMesh.new().get_mesh_arrays()
	var pv: PackedVector3Array=primitive[Mesh.ARRAY_VERTEX]; var pn: PackedVector3Array=primitive[Mesh.ARRAY_NORMAL]; var pi: PackedInt32Array=primitive[Mesh.ARRAY_INDEX]
	var expected:=0.0
	for t in range(0,pi.size(),3):
		var n: Vector3=(pv[pi[t+1]]-pv[pi[t]]).cross(pv[pi[t+2]]-pv[pi[t]])
		if n.length()>0.000001: expected=signf(n.dot(pn[pi[t]])); break
	var wrong:=0
	for t in range(0,indices.size(),3):
		var a: int=indices[t]; var b: int=indices[t+1]; var c: int=indices[t+2]
		var n: Vector3=(positions[b]-positions[a]).cross(positions[c]-positions[a])
		if n.dot(data.normals[a])*expected<-0.00000001: wrong+=1
	check(wrong==0,"outward normals and front-face winding "+id+" wrong="+str(wrong))

func shot(id: String, text: String) -> void:
	if DisplayServer.get_name()=="headless": return
	caption.text=text
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/avatar-skin-"+id+".png")==OK,"real renderer "+id)

func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("#eee9da")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=0.65; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-25,0); sun.light_energy=0.8; world.add_child(sun)
	actor=preload("res://src/player/character.gd").new(); world.add_child(actor); actor.build(); actor.set_process(false); actor._reset_action_pose()
	skeleton=actor.limb_skinning
	check(skeleton.get_bone_count()==21,"four hierarchical chains plus independent stretch helpers")
	for control in [actor.left_arm,actor.right_arm,actor.left_leg,actor.right_leg]:
		check(control.find_children("*","MeshInstance3D",true,false).is_empty(),"pose controls contain no old segment/joint meshes "+control.name)
	for id in skeleton.limb_ids(): topology(id)
	var shape: CapsuleShape3D=actor.get_node("BodyCollision").shape
	check(is_equal_approx(shape.radius,0.22) and is_equal_approx(shape.height,1.3),"gameplay capsule unchanged")
	var original: Dictionary={}
	for id in skeleton.limb_ids(): original[id]=skeleton.surface_data(id).vertices
	# Directly change a bone, without moving a control or a MeshInstance: this
	# proves that skin weights, rather than object transforms, bend the surface.
	var before: PackedVector3Array=skeleton.deformed_points("arm.L")
	var control_pose: Transform3D=actor.left_elbow.transform
	var bone: int=skeleton.find_bone("arm.L.lower")
	skeleton.set_bone_pose_rotation(bone,Quaternion(Vector3.RIGHT,-PI/2))
	var after: PackedVector3Array=skeleton.deformed_points("arm.L")
	var moved:=0
	for i in before.size():
		if before[i].distance_to(after[i])>0.01: moved+=1
	check(moved>200 and actor.left_elbow.transform==control_pose,"bone alone deforms the connected arm")
	actor.sync_visual_pose()
	for degrees in [0,30,60,90,120]:
		actor.left_elbow.rotation.x=-deg_to_rad(degrees); actor.right_elbow.rotation.x=-deg_to_rad(degrees)
		actor.left_knee.rotation.x=deg_to_rad(degrees); actor.right_knee.rotation.x=deg_to_rad(degrees)
		actor.sync_visual_pose()
		for id in skeleton.limb_ids():
			var points: PackedVector3Array=skeleton.deformed_points(id)
			var valid:=true
			for point in points: valid=valid and point.is_finite() and point.length()<3
			check(valid and skeleton.surface_data(id).vertices==original[id],"bone-deformed finite surface; rest vertices immutable %s %d" % [id,degrees])
			var data: Dictionary=skeleton.surface_data(id)
			var joint: float=actor.Dimensions.UPPER_ARM if str(id).begins_with("arm") else actor.Dimensions.THIGH
			for ring in data.rings:
				if absf(float(ring.distance)-joint)>0.000001: continue
				var center:=Vector3.ZERO
				for j in int(ring.count): center+=points[int(ring.start)+j]
				center/=float(ring.count)
				var radius:=INF
				for j in int(ring.count): radius=minf(radius,center.distance_to(points[int(ring.start)+j]))
				check(radius>0.008,"joint retains cross-section volume %s %d radius=%.4f" % [id,degrees,radius])
	actor._reset_action_pose()
	var appearance:=Catalog.defaults(); appearance.merge({"top":"vest","top_color":"plum","bottom":"trousers","bottom_color":"navy","hat":"none"},true)
	actor.apply_appearance(appearance)
	check(skeleton==actor.limb_skinning and skeleton.get_bone_count()==21,"changing outfit preserves rig and weights")
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1.8; camera.current=true
	world.add_child(camera); camera.position=Vector3(2.8,1.65,4.3); camera.look_at(Vector3.UP*0.7)
	var ui:=CanvasLayer.new(); root.add_child(ui); caption=Label.new(); caption.position=Vector2(36,25)
	caption.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded()); caption.add_theme_font_size_override("font_size",28); caption.add_theme_color_override("font_color",Color("#625744")); ui.add_child(caption)
	await shot("01-neutral","连续蒙皮网格 · 原比例站姿")
	if DisplayServer.get_name()!="headless":
		var image0:=root.get_texture().get_image()
		var region:=Rect2i(0,200,image0.get_width(),image0.get_height()-200)
		var before_pixels:=image0.get_region(region).get_data()
		var static_control: Transform3D=actor.left_elbow.transform
		skeleton.set_bone_pose_rotation(skeleton.find_bone("arm.L.lower"),Quaternion(Vector3.RIGHT,-PI/2))
		await shot("bone-only","仅旋转骨骼 · 控制节点和网格对象均不移动")
		var after_pixels:=root.get_texture().get_image().get_region(region).get_data()
		var changed:=0
		for i in range(0,before_pixels.size(),4):
			if before_pixels[i]!=after_pixels[i] or before_pixels[i+1]!=after_pixels[i+1] or before_pixels[i+2]!=after_pixels[i+2]: changed+=1
		check(changed>100 and actor.left_elbow.transform==static_control,"real GPU frame responds to bone only; changed pixels="+str(changed))
		actor.sync_visual_pose()
	actor.left_elbow.rotation.x=-PI/2; actor.right_elbow.rotation.x=-PI/2; actor.left_knee.rotation.x=PI/2; actor.right_knee.rotation.x=PI/2; actor.sync_visual_pose()
	await shot("02-bend90","肘 / 膝弯曲 90° · 骨骼权重过渡")
	camera.size=0.72; camera.position=Vector3(2.2,0.64,1.5); camera.look_at(Vector3(0.08,0.64,0.02))
	await shot("03-elbow-close","手臂一体 · 肘部近景")
	camera.position=Vector3(2.5,0.24,1.4); camera.look_at(Vector3(0.04,0.24,-0.02))
	await shot("04-knee-close","腿部一体 · 膝部近景")
	camera.size=1.8; camera.position=Vector3(2.8,1.65,4.3); camera.look_at(Vector3.UP*0.7)
	for id in ["walking","rowing","planting","watering","harvesting","swimming"]:
		actor.cancel_action("test"); actor.set_walking(false); actor.set_rowing(false); actor.set_diving(false)
		if id=="walking": actor.set_walking(true)
		elif id=="rowing": actor.set_rowing(true)
		elif id=="swimming": actor.set_diving(true)
		else: actor.play_action(id)
		actor._process(0.55 if id!="harvesting" else 1.23)
		camera.size=2.2 if id=="harvesting" else 1.8
		camera.position=Vector3(2.8,1.9 if id=="harvesting" else 1.65,4.3)
		camera.look_at(Vector3.UP*(0.9 if id=="harvesting" else 0.7))
		var points: PackedVector3Array=skeleton.deformed_points("arm.L")
		check(not points.is_empty() and skeleton.get_bone_global_pose(skeleton.find_bone("arm.L.lower")).origin.is_finite(),"current action drives bones "+id)
		if id=="harvesting":
			for part in ["arm.L","arm.R"]:
				var data: Dictionary=skeleton.surface_data(part)
				var deformed: PackedVector3Array=skeleton.deformed_points(part)
				var end: float=actor.Dimensions.UPPER_ARM+actor.Dimensions.LOWER_ARM
				for ring in data.rings:
					if absf(float(ring.distance)-end)>0.000001: continue
					var center:=Vector3.ZERO
					for j in int(ring.count): center+=deformed[int(ring.start)+j]
					center/=float(ring.count)
					var expected: Vector3=actor.body_pivot.to_local((actor.left_elbow if part=="arm.L" else actor.right_elbow).get_node("Hand").global_position)
					check(center.distance_to(expected)<0.002,"stretched skinned wrist reaches actual receive-item hand "+part)
		await shot("action-"+id,"当前动作骨骼适配 · "+id)
	var rig_report: Dictionary={"bone_count":skeleton.get_bone_count(),"bones":[],"limbs":{},"checks":checks,"failures":failures,"renderer":DisplayServer.get_name()}
	for i in skeleton.get_bone_count():
		var rest: Transform3D=skeleton.get_bone_rest(i)
		rig_report.bones.append({"id":skeleton.get_bone_name(i),"parent":skeleton.get_bone_parent(i),"rest_origin":[rest.origin.x,rest.origin.y,rest.origin.z]})
	for id in skeleton.limb_ids():
		var data: Dictionary=skeleton.surface_data(id)
		rig_report.limbs[id]={"vertices":data.vertices.size(),"triangles":data.indices.size()/3,"surfaces":skeleton.limb_mesh(id).mesh.get_surface_count(),"weights_per_vertex":4,"connected":true,"closed":true}
	var output:=FileAccess.open("res://outputs/avatar-skinning-contract.json",FileAccess.WRITE); output.store_string(JSON.stringify(rig_report,"\t")); output.close()
	actor.cancel_action("test"); world.queue_free(); ui.queue_free(); await process_frame
	print("[avatar-skinning] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
