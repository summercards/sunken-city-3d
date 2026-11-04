extends SceneTree
## Real geometry contacts over whole strokes, morph extremes and state changes.
const Support = preload("res://tests/avatar_customization_support.gd")
var checks := 0
var failures := 0
var world: Node3D
var boat
var actor
var controller
var camera: Camera3D
var evidence := {}
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<=12: printerr("FAIL ",label)
func bounds(node: Node3D, reference: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for mi in node.find_children("*","MeshInstance3D",true,false):
		var b: AABB=reference.global_transform.affine_inverse()*mi.global_transform*mi.mesh.get_aabb()
		result=b if not found else result.merge(b)
		found=true
	return result
func stroke(phase: float, effort: float, turn: float, delta: float) -> void:
	boat._stroke=phase;boat._row_blend=effort;boat._sailing=effort>0.0
	boat._vel=boat.cruise_speed()*effort;boat._turn_rate=turn*boat.TURN_RATE
	boat._animate_oars(0.0)
	actor._process(delta)
func fixture() -> void:
	world=Node3D.new();root.add_child(world)
	boat=preload("res://src/navigation/boat.gd").new();world.add_child(boat);boat.build()
	actor=preload("res://src/player/character.gd").new();boat.add_child(actor);actor.build();actor.set_grounded_motion(false)
	actor.set_process(false);actor.rowing_query=boat.rowing_state;actor.rowing_pose_query=boat.rowing_pose
	controller=preload("res://src/player/actor_controller.gd").new()
	controller.configure(actor,boat,world,null,{"notify":func(_s): pass,"landing":func(): return null})
	controller.restore_pose({"mode":1})
func inspect_contacts() -> void:
	var bench: AABB=bounds(boat.model.get_node("Parts/bench_020"),boat.model)
	var original_root: Transform3D=actor.transform
	var worst_grip := 0.0
	var worst_seat := 0.0
	var min_blade := INF
	var max_blade := -INF
	var seat_penetrations := 0
	var min_hand_forward := INF
	var min_elbow_forward := INF
	var max_elbow_twist := 0.0
	var max_elbow_fold := 0.0
	var max_hinge_step := 0.0
	var boards: Array[AABB]=[]
	for mi in boat.model.get_node("Parts/bench_020").find_children("*","MeshInstance3D",true,false):
		var b: AABB=boat.model.global_transform.affine_inverse()*mi.global_transform*mi.mesh.get_aabb()
		if b.size.x>1.0: boards.append(b.grow(-0.012))
	var cases := [Support.profile()]
	for build in [0.0,1.0]:
		for legs in [0.0,1.0]:
			for arms in [0.0,1.0]: cases.append(Support.profile({"body_type":"pear"},{"body_build":build,"leg_length":legs,"arm_girth":arms}))
	for profile_index in cases.size():
		actor.apply_avatar(cases[profile_index])
		for fps in [30,60,120]:
			for effort in [0.0,0.35,1.0]:
				for turn in [-1.0,0.0,1.0]:
					var previous_axes: Array[Vector3]=[]
					for frame in 24:
						var phase:=TAU*frame/24.0
						boat.model.rotation=Vector3(0.035*sin(phase),0.018*cos(phase),0.075*sin(phase+0.2))
						boat.model.position.y=0.012*sin(phase*2.0)
						stroke(phase,effort,turn,1.0/fps)
						var pose: Dictionary=boat.rowing_pose()
						var gap: float=maxf(actor.left_elbow.get_node("Hand").global_position.distance_to(pose.left_grip),actor.right_elbow.get_node("Hand").global_position.distance_to(pose.right_grip))
						worst_grip=maxf(worst_grip,gap)
						check(gap<0.008,"both palms grip actual handles case=%d fps=%d effort=%.2f phase=%.2f gap=%.5f"%[profile_index,fps,effort,phase,gap])
						var current_axes: Array[Vector3]=[]
						for pair in [[actor.left_arm,actor.left_elbow],[actor.right_arm,actor.right_elbow]]:
							var shoulder: Node3D=pair[0]
							var elbow: Node3D=pair[1]
							var palm: Vector3=actor.body_pivot.to_local(elbow.get_node("Hand").global_position)
							var joint: Vector3=actor.body_pivot.to_local(elbow.global_position)
							var front: float=palm.z-shoulder.position.z
							var elbow_front: float=joint.z-shoulder.position.z
							var twist: float=elbow.basis.x.distance_to(Vector3.RIGHT)
							var upper: Vector3=(joint-shoulder.position).normalized()
							var lower: Vector3=(palm-joint).normalized()
							var fold:=rad_to_deg(acos(clampf(upper.dot(lower),-1.0,1.0)))
							min_hand_forward=minf(min_hand_forward,front);min_elbow_forward=minf(min_elbow_forward,elbow_front)
							max_elbow_twist=maxf(max_elbow_twist,twist);max_elbow_fold=maxf(max_elbow_fold,fold)
							check(front>=0.04,"grip stays in front of shoulder, not behind body %.5f"%front)
							check(upper.z>=-sin(deg_to_rad(35.0)),"upper arm stays within modest backward swing, not reaching behind torso %.2fdeg"%rad_to_deg(asin(clampf(-upper.z,-1.0,1.0))))
							check(twist<0.001,"forearm bends on the same hinge without axial twist %.5f"%twist)
							check(fold<140.0,"elbow is not overfolded %.2fdeg"%fold)
							current_axes.append(shoulder.basis.x)
						if previous_axes.size()==2:
							for side_index in 2:
								var step:=rad_to_deg(acos(clampf(previous_axes[side_index].dot(current_axes[side_index]),-1.0,1.0)))
								max_hinge_step=maxf(max_hinge_step,step)
								check(step<45.0,"hinge frame stays continuous across stroke %.2fdeg"%step)
						previous_axes=current_axes
						# Actual upper-trouser mesh underside, not a seat constant alone.
						var pelvis: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Pelvis")
						var low:=INF
						for p in Support.points(pelvis,boat.model): low=minf(low,p.y)
						var seat_gap:=absf(low-bench.end.y)
						worst_seat=maxf(worst_seat,seat_gap)
						check(seat_gap<0.025,"pelvis remains on actual bench gap=%.5f"%seat_gap)
						check(actor.transform==original_root,"animation leaves gameplay root unchanged")
						if fps==60 and turn==0.0:
							var penetrations:=0
							for id in ["leg.L","leg.R"]:
								for vertex in actor.limb_skinning.deformed_points(id):
									var p: Vector3=boat.model.to_local(actor.limb_skinning.to_global(vertex))
									for plank in boards:
										if plank.has_point(p): penetrations+=1
								seat_penetrations+=penetrations
								check(penetrations==0,"bent skinned legs clear the real seat boards case=%d phase=%.2f vertices=%d"%[profile_index,phase,penetrations])
						if profile_index==0 and effort==1.0:
							var blade: Vector3=boat.model.to_local(boat.oar_blade_positions()[0])
							min_blade=minf(min_blade,blade.y);max_blade=maxf(max_blade,blade.y)
	check(min_blade<0.0 and max_blade>0.3,"shortened blades enter water and recover %.4f..%.4f"%[min_blade,max_blade])
	evidence={"max_palm_gap_m":worst_grip,"max_pelvis_seat_gap_m":worst_seat,"leg_seat_penetrations":seat_penetrations,"blade_y_m":[min_blade,max_blade],"bench_top_m":bench.end.y,"profiles":cases.size(),"min_hand_forward_m":min_hand_forward,"min_elbow_forward_m":min_elbow_forward,"max_elbow_twist_basis_error":max_elbow_twist,"max_elbow_fold_deg":max_elbow_fold,"expected_faults":[],"unexecuted":["touch/gamepad","all appearance combinations"]}
	print("[measure] ",JSON.stringify(evidence))
	evidence.max_hinge_step_deg=max_hinge_step
func lifecycle() -> void:
	controller.cancel();actor._process(1.0/60.0)
	check(actor._boat_seated and actor.animation_state()=="rowing","cancel/stop keeps the seated base pose")
	controller.restore_pose({"mode":0,"player":[0,2,0]});actor._process(1.0/60.0)
	check(not actor._boat_seated and actor.animation_state()=="idle" and absf(actor.body_pivot.position.z)<0.0001,"restore ashore removes seat offset and folded legs")
	controller.restore_pose({"mode":1});actor._process(1.0/60.0)
	check(actor._boat_seated and actor.get_parent()==boat,"boarding and restored boat state share the seat")
	actor.set_diving(true);actor.set_boat_seated(false);actor._process(1.0/60.0)
	check(actor.animation_state()=="swimming","diving leaves seated action")
	actor.set_diving(false);controller.restore_pose({"mode":1})
func setup_render() -> void:
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("#4c9aaa")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("#d5e4e7");environment.environment.ambient_light_energy=0.65
	world.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-30,0);sun.light_energy=1.5;sun.shadow_enabled=true;world.add_child(sun)
	var water:=MeshInstance3D.new();var mesh:=PlaneMesh.new();mesh.size=Vector2(200,200);water.mesh=mesh
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("#087c96");mat.roughness=.25;water.material_override=mat;world.add_child(water)
	boat.position.y=0.24;water.position.y=0.24
	camera=Camera3D.new();world.add_child(camera);camera.current=true;camera.fov=36
func shot(label: String, direction: Vector3) -> void:
	camera.position=boat.position+direction.normalized()*11.0;camera.look_at(boat.position+Vector3(0,.5,0))
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/rowing-fit-"+label+".png")
func run() -> void:
	fixture()
	inspect_contacts()
	lifecycle()
	if DisplayServer.get_name()!="headless":
		preload("res://tools/lighting_capture_profile.gd").prepare();setup_render()
		actor.apply_avatar(Support.profile({"hair_style":"curly","hair_color":"sage","hat":"none","top":"vest"}))
		boat.model.transform=Transform3D.IDENTITY
		stroke(0.0,1.0,0.0,1.0/60.0);await shot("pull",Vector3(-.65,.90,.80))
		stroke(PI,1.0,0.0,1.0/60.0);await shot("recovery",Vector3(-.65,.90,.80))
		stroke(PI*.5,1.0,0.0,1.0/60.0);await shot("side",Vector3(1,.45,0))
		stroke(0.0,0.0,0.0,1.0/60.0);await shot("idle",Vector3(-.65,.90,.80))
	var file:=FileAccess.open("res://outputs/rowing-fit.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	world.queue_free();await process_frame
	print("[rowing-fit] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
