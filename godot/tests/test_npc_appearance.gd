extends SceneTree
## runner入口：npc-appearance。只读角色数据，不实例化NPC服务或世界。
const Actor = preload("res://src/npc/npc_actor.gd")
const Base = preload("res://src/player/character.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Profile = preload("res://src/avatar/avatar_profile.gd")
const D = preload("res://src/avatar/avatar_dimensions.gd")
const Support = preload("res://tests/avatar_customization_support.gd")
const ACTIONS := ["idle","walking","rowing","planting","watering","harvesting","swimming"]
const PARTS := [["RopeCoil","RouteClasp"],["SeedPouch","LeafBrooch"],["ForeheadGoggles","SealedRecordTube"],["EarPencil","ToolBelt"],["LampBadge","ArchiveBook"],["PetalVisor","PruningShears"],["CargoTagClip","WaistPack"]]
var checks := 0
var failures := 0
var reports: Array = []
var geometry_samples: Array = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[npc-appearance] FAIL ",label)

# 捕获脚本复用同一动作采样；走路必须有真实步频输入，不能只翻布尔值。
static func sample(actor, action: String, seconds: float) -> void:
	actor.cancel_action("npc-appearance")
	actor.set_walking(false)
	actor.set_rowing(false)
	actor.set_diving(false)
	actor._reset_action_pose()
	actor._t = 0.0
	actor._walk_phase = 0.0
	actor.walk_speed_ratio = 1.0
	match action:
		"walking": actor.set_walking(true)
		"rowing": actor.set_rowing(true)
		"swimming": actor.set_diving(true)
		"planting", "watering", "harvesting": actor.play_action(action,{"crop":"lettuce"})
	actor._process(seconds)
	actor.sync_visual_pose()

func new_character(script):
	var actor = script.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	return actor

func mesh_signature(actor) -> Array:
	var result: Array = []
	# 独立比较原生Avatar真实网格、变形顶点及材质，排除职业配件和通用挎包。
	for path in ["AvatarBody","HeadLook/AvatarHead","HeadLook/AvatarHat"]:
		var part: Node3D = actor.body_pivot.get_node(path)
		for mesh in part.find_children("*","MeshInstance3D",true,false):
			if str(mesh.name).begins_with("NpcAccessory_"): continue
			var ancestor: Node = mesh.get_parent()
			var accessory := false
			while ancestor != part:
				if str(ancestor.name).begins_with("NpcAccessory_"): accessory = true
				ancestor = ancestor.get_parent()
			if accessory: continue
			var mat = mesh.material_override
			var tint: Variant = mat.albedo_color if mat is StandardMaterial3D else mat.get_shader_parameter("base_color")
			result.append([Support.points(mesh,actor.body_pivot),tint])
	for id in actor.limb_skinning.limb_ids():
		var mesh: MeshInstance3D = actor.limb_skinning.limb_mesh(id)
		var mat: ShaderMaterial = mesh.material_override
		var entry: Array = [actor.limb_skinning.deformed_points(id)]
		for key in ["skin_color","cloth_color","trouser_color","shoe_color","sleeve_end","trouser_end","shoe_start","sneakers"]:
			entry.append(mat.get_shader_parameter(key))
		result.append(entry)
	return result

func layout(actor) -> Array:
	var result: Array = []
	for part in actor.accessory_metrics().parts:
		result.append([part.id,part.parent,part.local_transform,part.vertices])
	return result

func check_accessory_geometry(actor, action: String) -> void:
	var head: Node3D = actor.head_pivot.get_node("AvatarHead")
	for part in actor.accessory_metrics().parts:
		var node: Node3D = actor.get_node(part.path)
		var skull_hits := 0
		var eye_hits := 0
		for mesh in Support.meshes(node):
			for p in Support.points(mesh,head,true):
				if (p/Support.RADII).length_squared()<.97: skull_hits += 1
				if absf(p.x)<.215 and p.y>-.15 and p.y<.095 and p.z>.18: eye_hits += 1
		check(skull_hits==0 and eye_hits==0,"独立实际三角形探针不穿颅挡脸 "+part.id+"/"+action)
		check(not node.find_children("*","CollisionObject3D",true,false).size(),"配件无玩法碰撞 "+part.id)

func check_avatar_clearance(actor, action: String, seconds: float) -> void:
	var head: Node3D = actor.head_pivot.get_node("AvatarHead")
	var face: Node3D = head.get_node("Face")
	var skull_hits := 0
	var eye_hits := 0
	var arm_hits := 0
	for mesh in Support.meshes(head,"hair"):
		for p in Support.points(mesh,head,true):
			if (p/Support.RADII).length_squared()<.97: skull_hits += 1
			if absf(p.x)<.215 and p.y>-.043 and p.y<.060 and p.z>.18: eye_hits += 1
	for id in actor.limb_skinning.limb_ids():
		if not str(id).begins_with("arm"): continue
		var data: Dictionary = actor.limb_skinning.surface_data(id)
		var points: PackedVector3Array = actor.limb_skinning.deformed_points(id)
		for i in points.size():
			if data.uv2[i].x<Support.ref_threshold(.065): continue
			if face.to_local(actor.limb_skinning.to_global(points[i])).length_squared()<.94: arm_hits += 1
	check(skull_hits==0 and eye_hits==0,"动作实际头发不穿颅遮眼 "+actor.npc_id+"/"+action)
	check(arm_hits==0,"动作实际手臂不穿头脸 "+actor.npc_id+"/"+action)
	geometry_samples.append({"npc_id":actor.npc_id,"action":action,"seconds":seconds,"hair_skull":skull_hits,"hair_eye":eye_hits,"arm_head":arm_hits})

func test_actor(row: Dictionary, index: int, reference) -> void:
	var actor = new_character(Actor)
	var original := row.duplicate(true)
	actor.configure(row)
	var report: Dictionary = actor.appearance_report()
	check(row == original,"configure不修改输入行 "+row.id)
	check(Profile.validate_snapshot(report.profile).is_empty(),"合法完整profile "+row.id)
	check(report.profile.appearance == Catalog.effective(row.appearance),"全部离散选项有效 "+row.id)
	for slot in row.appearance:
		check(Catalog.resolve(slot,str(row.appearance[slot])).get("id","") == row.appearance[slot],"源选项不依赖fallback "+row.id+"/"+slot)
	check(row.appearance.has("skin") and row.has("morphs"),"源行明确提供肤色和morphs "+row.id)
	check(report.profile.morphs == Catalog.effective_morphs(row.get("morphs",{})),"完整传递morphs "+row.id)
	reference.apply_avatar(report.profile)
	reference._reset_action_pose()
	actor._reset_action_pose()
	check(mesh_signature(actor) == mesh_signature(reference),"所有原生选项与独立Character真实几何材质一致 "+row.id)
	check(actor.head_pivot.get_node("AvatarHead/Face").material_override.albedo_color == Catalog.color(report.profile.appearance,"skin"),"肤色实际材质 "+row.id)
	check(report.geometry.hair.style == report.profile.appearance.hair_style,"发型实际模块 "+row.id)
	check(report.geometry.hair.minimum_skull_q >= .97,"头发不穿颅 "+row.id)
	check(actor.hat.get_child_count()>0 or report.profile.appearance.hat=="none","帽型实际几何 "+row.id)
	check(actor.scale == Vector3.ONE and actor.body_pivot.scale == Vector3.ONE,"根不重复乘1.5 "+row.id)
	var capsule: CapsuleShape3D = actor.get_node("BodyCollision").shape
	var capsule_id := capsule.get_instance_id()
	var collision_before := {"radius":capsule.radius,"height":capsule.height,"transform":actor.get_node("BodyCollision").transform}
	print("[npc-appearance] capsule %s radius=%.12f height=%.12f expected=%.12f/%.12f"%[row.id,capsule.radius,capsule.height,D.BODY_RADIUS,D.BODY_HEIGHT])
	check(is_equal_approx(capsule.radius,D.BODY_RADIUS) and is_equal_approx(capsule.height,D.BODY_HEIGHT),"碰撞保持（仅近似比较，不写碰撞） "+row.id)
	var initial := layout(actor)
	var node_count: int = actor.find_children("*","",true,false).size()
	for repeat in 3:
		actor.configure(row)
		check(layout(actor)==initial,"同帧configure幂等 "+row.id)
		check(actor.find_children("*","",true,false).size()==node_count,"重配无重复节点 "+row.id)
	check(actor.body_pivot.get_node("Satchel").visible == false and not actor.body_pivot.get_node("SatchelStrap").visible,"NPC不叠通用旅人包 "+row.id)
	var m: Dictionary = actor.accessory_metrics()
	check(m.root_count==2 and m.mesh_count>=8,"每人两个独立有细节配件 "+row.id)
	var ids: Array = []
	for part in m.parts: ids.append(part.id)
	check(ids==PARTS[index],"职业配件真实独特 "+row.id)
	# 捏人连续参数逐个扰动，必须确实改变原生Avatar网格/姿势，而不只是写元数据。
	var baseline := mesh_signature(actor)
	for morph in Catalog.morph_defaults():
		var changed: Dictionary = report.profile.duplicate(true)
		changed.morphs[morph] = 0.05 if float(changed.morphs[morph])>.5 else .95
		reference.apply_avatar(changed)
		reference._reset_action_pose()
		check(mesh_signature(reference)!=baseline,"morph实际生效 "+row.id+"/"+morph)
	for action in ACTIONS:
		var moved := false
		var previous: Array = []
		var previous_arms: Array = []
		var rig_moved := false
		var times: Array = [.11,.37,.69,1.10,1.60,2.15] if action=="harvesting" else [.11,.37,.69]
		for seconds in times:
			sample(actor,action,seconds)
			m = actor.accessory_metrics()
			check(actor.animation_state()==action,"沿用Character动作 "+row.id+"/"+action)
			check(m.finite and m.face_occlusion_vertices==0 and m.skull_penetration_vertices==0,"动作配件有限且不挡脸穿颅 "+row.id+"/"+action)
			check_accessory_geometry(actor,action)
			check_avatar_clearance(actor,action,seconds)
			var current: Array = []
			for part in m.parts:
				var node: Node3D = actor.get_node(part.path)
				check(node.transform.is_equal_approx(part.mount_transform),"挂点局部变换不漂移 "+part.id+"/"+action)
				var expected: Transform3D = node.get_parent().global_transform*part.mount_transform
				check(node.global_transform.is_equal_approx(expected),"动作父变换同步 "+part.id+"/"+action)
				current.append(node.global_transform)
			if not previous.is_empty() and current != previous: moved = true
			# 坐姿绕髋部驱动BodyPivot，部分臂长会令局部IK角度不变；验证实际世界骨架。
			var arms: Array = [actor.left_arm.global_transform,actor.right_arm.global_transform,actor.left_elbow.global_transform,actor.right_elbow.global_transform,actor.left_knee.global_transform,actor.right_knee.global_transform]
			if not previous_arms.is_empty() and arms != previous_arms: rig_moved = true
			previous_arms = arms
			previous = current
		# 游泳的躯干倾角固定而四肢摆动，腰挂件应固定随身，不额外乱摆。
		check(rig_moved,"原生骨架动作真实变化 "+row.id+"/"+action)
		check(moved or action=="swimming","三个采样配件同步角色父节点 "+row.id+"/"+action)
	actor.configure(row)
	check(actor.get_node("BodyCollision").shape.get_instance_id()==capsule_id,"重配不替换碰撞资源 "+row.id)
	check(capsule.radius==collision_before.radius and capsule.height==collision_before.height and actor.get_node("BodyCollision").transform==collision_before.transform,"重配前后碰撞实测值与变换完全不变 "+row.id)
	actor.clear_accessories()
	check(actor.accessory_metrics().root_count==0 and actor.find_children("NpcAccessory_*","Node3D",true,false).is_empty(),"全部根同步可卸载 "+row.id)
	actor.configure(row)
	check(layout(actor)==initial,"卸载后完整重建 "+row.id)
	var missing := row.duplicate(true)
	missing.accessory_id = ""
	actor.configure(missing)
	check(actor.accessory_metrics().root_count==0,"重配空配件不残留 "+row.id)
	actor.configure(row)
	var copy: Dictionary = actor.appearance_report()
	copy.profile.appearance.skin = "bad"
	check(actor.appearance_report().profile.appearance.skin != "bad","查询深副本 "+row.id)
	var final_report: Dictionary = actor.appearance_report()
	final_report["collision_measured"] = collision_before
	reports.append(final_report)
	actor.free()

func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/npc/npcs.json"))
	var rows: Array = source.npcs
	check(rows.size()==7,"七人齐全")
	var player = new_character(Base)
	player.build()
	var player_profile := Profile.fresh(true)
	player_profile.appearance.merge({"skin":"deep","hair_style":"curly","hat":"none"},true)
	player.apply_avatar(player_profile)
	player._reset_action_pose()
	var player_before := mesh_signature(player)
	var shape_before: Resource = player.get_node("BodyCollision").shape
	var profile_store := Profile.new()
	var stored_before := profile_store.query()
	var reference = new_character(Base)
	reference.build()
	var silhouettes := {}
	var hairs := {}
	var skins := {}
	var tops := {}
	for i in rows.size():
		var row: Dictionary = rows[i]
		var morphs: Dictionary = Catalog.effective_morphs(row.get("morphs",{}))
		silhouettes[JSON.stringify([row.appearance.body_type,morphs.body_build,morphs.head_size,morphs.head_width,morphs.leg_length])] = true
		hairs[row.appearance.hair_style] = true
		skins[str(row.appearance.get("skin",""))] = true
		tops[row.appearance.top_color] = true
		test_actor(row,i,reference)
	check(silhouettes.size()==7 and hairs.size()==7 and tops.size()==7 and skins.size()>=4,"七种轮廓发型衣色和至少四种肤色")
	check(mesh_signature(player)==player_before and player.get_node("BodyCollision").shape==shape_before,"旁路玩家真实网格材质和碰撞不变")
	check(player.get_meta("avatar_appearance")==player_profile.appearance and profile_store.query()==stored_before,"玩家档案未提交也未污染")
	check(player.body_pivot.get_node("Satchel").visible,"玩家通用挎包不受NPC隐藏影响")
	reference.free()
	player.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	var file := FileAccess.open("res://outputs/npc-appearance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"entry":"npc-appearance","checks":checks,"failures":failures,"actors":reports,"geometry_samples":geometry_samples},"\t"))
	file.close()
	await process_frame
	print("[npc-appearance] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
