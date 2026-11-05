extends SceneTree
## 划船装配尺寸探针：只读，输出船体部件与坐姿角色的实际米制关系。
## 用于把「角色放大后桨架/座位/握点该往哪挪」变成可复算的数，而不是看图猜。
const Support = preload("res://tests/avatar_customization_support.gd")
var world: Node3D

func _init() -> void: call_deferred("run")

func bounds(node: Node3D, reference: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for mi in node.find_children("*","MeshInstance3D",true,false):
		var b: AABB=reference.global_transform.affine_inverse()*mi.global_transform*mi.mesh.get_aabb()
		result=b if not found else result.merge(b)
		found=true
	return result

func run() -> void:
	world=Node3D.new();root.add_child(world)
	var boat=preload("res://src/navigation/boat.gd").new();world.add_child(boat);boat.build()
	var actor=preload("res://src/player/character.gd").new();boat.add_child(actor);actor.build();actor.set_grounded_motion(false)
	actor.set_process(false);actor.rowing_query=boat.rowing_state;actor.rowing_pose_query=boat.rowing_pose
	actor.apply_avatar(Support.profile())
	var controller=preload("res://src/player/actor_controller.gd").new()
	controller.configure(actor,boat,world,null,{"notify":func(_s): pass,"landing":func(): return null})
	controller.restore_pose({"mode":1})
	boat.model.transform=Transform3D.IDENTITY

	var model: Node3D=boat.model
	var parts := {}
	for name in ["hull_000","gunwale_001","bench_019","bench_020","bench_021","outboard_032","floor_board_002","floor_board_003"]:
		var node: Node3D=model.get_node_or_null("Parts/"+name)
		if node!=null:
			var b:=bounds(node,model)
			parts[name]={"min":[snappedf(b.position.x,0.001),snappedf(b.position.y,0.001),snappedf(b.position.z,0.001)],
				"max":[snappedf(b.end.x,0.001),snappedf(b.end.y,0.001),snappedf(b.end.z,0.001)]}
	# 真实站姿尺寸：胶囊与整体视觉高度（未坐下的状态，用于核对门洞/舱室净高）。
	var collider: CollisionShape3D=actor.get_node("BodyCollision")
	var capsule: CapsuleShape3D=collider.shape
	controller.restore_pose({"mode":0,"player":[0,0,0]});actor._process(1.0/60.0)
	var standing:=bounds(actor.body_pivot,world)
	var hair_top:=standing.end.y
	actor.apply_avatar(Support.profile({"hat":"fedora"}));actor._process(1.0/60.0)
	var hat_top:=bounds(actor.body_pivot,world).end.y
	# 头部滑块两极 + 礼帽：门洞净高只有 2.06 m，这一组是最坏情况。
	var tallest:=0.0
	for head_size in [0.0,1.0]:
		var profile:=Support.profile({"hat":"fedora"}); profile.morphs["head_size"]=head_size
		actor.apply_avatar(profile);actor._process(1.0/60.0)
		tallest=maxf(tallest,bounds(actor.body_pivot,world).end.y)
	actor.apply_avatar(Support.profile());actor._process(1.0/60.0)
	controller.restore_pose({"mode":1});actor._process(1.0/60.0)
	var visual:=bounds(actor.body_pivot,world)
	# 坐姿：满力中段相位。
	boat._stroke=0.0;boat._row_blend=1.0;boat._sailing=true;boat._vel=boat.cruise_speed();boat._turn_rate=0.0
	boat._animate_oars(0.0)
	actor._process(1.0/60.0)
	var seat: Transform3D=boat.rowing_pose().seat
	var grip: Dictionary=boat.rowing_pose()
	var blade_points: Array=[]
	for p in boat.oar_blade_positions():
		blade_points.append([snappedf(p.x,0.001),snappedf(p.y,0.001),snappedf(p.z,0.001)])
	var report := {
		"capsule":{"radius":capsule.radius,"height":capsule.height},
		"standing":{"hair_top_m":snappedf(hair_top,0.001),"hat_top_m":snappedf(hat_top,0.001),
			"tallest_hat_head_extreme_m":snappedf(tallest,0.001),
			"shoulder_y_m":snappedf(actor.left_arm.global_position.y,0.001),
			"head_center_y_m":snappedf(actor.head_pivot.global_position.y,0.001)},
		"room_door_opening_m":2.06,
		"room_ceiling_m":2.75,
		"bed_length_m":2.03,
		"parts":parts,
		"seat":[snappedf(seat.origin.x,0.001),snappedf(seat.origin.y,0.001),snappedf(seat.origin.z,0.001)],
		"grip_left":[snappedf(grip.left_grip.x,0.001),snappedf(grip.left_grip.y,0.001),snappedf(grip.left_grip.z,0.001)],
		"grip_right":[snappedf(grip.right_grip.x,0.001),snappedf(grip.right_grip.y,0.001),snappedf(grip.right_grip.z,0.001)],
		"blade":blade_points,
	}
	var joints := {}
	for pair in [["shoulder.L",actor.left_arm],["elbow.L",actor.left_elbow],["hand.L",actor.left_elbow.get_node("Hand")],
		["shoulder.R",actor.right_arm],["hand.R",actor.right_elbow.get_node("Hand")],
		["hip.L",actor.left_leg],["knee.L",actor.left_knee],["foot.L",actor.left_knee.get_node("Foot")]]:
		var p: Vector3=model.to_local(pair[1].global_position)
		joints[pair[0]]=[snappedf(p.x,0.001),snappedf(p.y,0.001),snappedf(p.z,0.001)]
	report.joints=joints
	var pelvis: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Pelvis")
	var pb:=bounds(pelvis,model)
	report.pelvis=[[snappedf(pb.position.x,0.001),snappedf(pb.position.y,0.001),snappedf(pb.position.z,0.001)],
		[snappedf(pb.end.x,0.001),snappedf(pb.end.y,0.001),snappedf(pb.end.z,0.001)]]
	print("[rowing-scale] ",JSON.stringify(report))
	world.queue_free();await process_frame
	quit(0)
