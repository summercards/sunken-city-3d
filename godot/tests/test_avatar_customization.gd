extends SceneTree
## Incremental profile compatibility, real shape changes and independent
## penetrations in mixed extremes and action poses. No production audit gates.
const Support = preload("res://tests/avatar_customization_support.gd")
const Profile = preload("res://src/avatar/avatar_profile.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var diagnostics: Array[Dictionary] = []
var actor

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-customization] ","PASS " if ok else "FAIL ",label)

func profile_contract() -> void:
	var fresh := Profile.fresh()
	check(fresh.morphs.size()==9,"nine independently saved morph parameters")
	for id in Support.MORPHS:
		check(fresh.morphs.has(id) and fresh.morphs[id]==.5,"reference midpoint "+id)
		for invalid in [-.001,1.001,NAN,INF,"0.5",true,null]:
			var bad := fresh.duplicate(true); bad.morphs[id]=invalid
			check(Profile.validate_snapshot(bad)!="","reject malformed %s: %s"%[id,str(invalid)])
		var absent := fresh.duplicate(true); absent.morphs.erase(id)
		check((Profile.validate_snapshot(absent)!="")==(id in Profile.ORIGINAL_MORPHS),"original morph keys required; incremental morph keys have migration "+id)
	for invalid in [[],"",1,null]:
		var bad := fresh.duplicate(true); bad.morphs=invalid
		check(Profile.validate_snapshot(bad)!="","reject malformed morph container "+str(invalid))
	var old := fresh.duplicate(true); old.erase("morphs")
	for id in ["body_type","beard","beard_color","fringe","hair_accessory"]: old.appearance.erase(id)
	check(Profile.validate_snapshot(old)=="","intact original v1 profile accepted")
	var model := Profile.new(); model.from_dict(old)
	check(model.query().morphs==Catalog.morph_defaults() and model.query().appearance.body_type=="balanced","original v1 receives explicit morph and new-slot defaults")
	var draft := model.query(); draft.morphs.head_size=1.0; draft.appearance.beard="full"
	check(model.query().morphs.head_size==.5 and model.query().appearance.beard=="none","profile queries detach nested morph and appearance dictionaries")
	draft.extensions={"hair_diy":{"version":1,"knots":[.2,.7]}}; draft.design_refs={"top":"design:qa/001"}; draft.name="深海旅人"
	check(model.commit(draft).ok,"new parameters commit with design references")
	var detached := model.query(); detached.extensions.hair_diy.knots[0]=.9
	check(model.query().extensions.hair_diy.knots[0]==.2,"DIY extension deep copy survives commit")
	var decoded: Dictionary=JSON.parse_string(JSON.stringify(model.to_dict()))
	check(Profile.validate_snapshot(decoded)=="" and decoded==JSON.parse_string(JSON.stringify(model.query())),"all shape and DIY fields survive independent JSON serialization")
	for slot in ["eyes","hair_style","beard","body_type"]:
		check(Catalog.options(slot).size()>={"eyes":12,"hair_style":14,"beard":5,"body_type":4}[slot],"catalogue richness "+slot)

func width(path: String) -> float:
	return Support.bounds(Support.points(actor.get_node(path),actor)).size.x

func morphology() -> void:
	var p := Support.profile({"hair_style":"ponytail","hat":"none"})
	actor.apply_avatar(p)
	var narrow_face := 0.0; var wide_face := 0.0; var thin := 0.0; var heavy := 0.0
	for value in [0.0,1.0]:
		p.morphs.head_size=value; p.morphs.body_build=.5; actor.apply_avatar(p)
		var measured := Support.bounds(Support.points(actor.head_pivot.get_node("AvatarHead/Face"),actor)).size.x
		if value==0: narrow_face=measured
		else: wide_face=measured
	check(wide_face>narrow_face*1.12,"head slider changes actual face vertex width %.4f -> %.4f"%[narrow_face,wide_face])
	for value in [0.0,1.0]:
		p.morphs.head_size=.5; p.morphs.body_build=value; actor.apply_avatar(p)
		var measured := Support.bounds(Support.points(actor.body_pivot.get_node("AvatarBody/Shirt"),actor)).size.x
		if value==0: thin=measured
		else: heavy=measured
	check(heavy>thin*1.25,"build slider changes actual shirt vertex width %.4f -> %.4f"%[thin,heavy])
	var widths: Array[float] = []
	for value in [0.0,1.0]:
		p.morphs.eye_spacing=value; actor.apply_avatar(p)
		var head: Node3D=actor.head_pivot.get_node("AvatarHead")
		var centers: Array[Vector3]=[]
		for side in [-1,1]:
			var eye_points:=PackedVector3Array()
			for mesh in Support.meshes(head,"eye"):
				if mesh.get_meta("side",0)==side: eye_points.append_array(Support.points(mesh,head))
			centers.append(Support.bounds(eye_points).get_center())
		widths.append(absf(centers[1].x-centers[0].x))
	check(widths[1]>widths[0]*1.30,"eye slider moves actual eye mesh centers %.4f -> %.4f"%[widths[0],widths[1]])
	for id in ["hair_length","hair_volume","hair_sweep"]:
		var extremes: Array[PackedVector3Array]=[]
		for value in [0.0,1.0]:
			p.morphs=Catalog.morph_defaults(); p.morphs[id]=value; actor.apply_avatar(p)
			extremes.append(Support.part_points(actor,"hair",actor))
		var changed:=extremes[0].size()!=extremes[1].size()
		if not changed:
			for i in extremes[0].size():
				if extremes[0][i].distance_to(extremes[1][i])>.01: changed=true; break
		check(changed,"DIY "+id+" visibly changes actual hair vertices")
	# Each body type must produce a geometrically different silhouette.
	var fingerprints: Dictionary={}
	for option in Catalog.options("body_type"):
		p=Support.profile({"body_type":option.id}); actor.apply_avatar(p)
		var points:=Support.points(actor.body_pivot.get_node("AvatarBody/Shirt"),actor)
		fingerprints[hash(points)]=true
	check(fingerprints.size()==4,"four body styles produce four distinct actual shirt surfaces")

func blush_contract() -> void:
	for id in ["peach","freckles"]:
		actor.apply_avatar(Support.profile({"blush":id,"beard":"stubble"}))
		var patches := Support.meshes(actor,"blush")
		check(patches.size()==2,"paired conformal textured cheeks "+id)
		for patch in patches:
			var material: StandardMaterial3D=patch.material_override
			var texture: Texture2D=material.albedo_texture if material!=null else null
			check(patch.mesh is ArrayMesh and texture!=null and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"cheek uses actual transparent texture rather than solid blob "+id+"/"+patch.name)
			if texture==null: continue
			var image:=texture.get_image(); var low:=1.0; var high:=0.0
			for y in range(0,image.get_height(),4):
				for x in range(0,image.get_width(),4):
					var alpha:=image.get_pixel(x,y).a; low=minf(low,alpha); high=maxf(high,alpha)
			check(low<.05 and high>.2,"texture contains transparent edge and visible pigment "+id)
			var conformal:=true
			for point in Support.points(patch,actor.head_pivot.get_node("AvatarHead")):
				var scaled:=Vector3(point.x/Support.RADII.x,point.y/Support.RADII.y,point.z/Support.RADII.z)
				var gap: float=(scaled.length()-1)*.25
				conformal=conformal and gap>.0015 and gap<.006
			check(conformal,"cheek vertices remain within 1.5–6mm of face "+id)

func detector_contract() -> void:
	actor.apply_avatar(Support.profile({"body_type":"balanced"},{"body_build":1.0}))
	var solid:=Support.shirt_solid(actor.body_pivot.get_node("AvatarBody/Shirt"),actor.body_pivot)
	var center: Vector3=solid.bounds.get_center()
	check(Support.shirt_depth(center,solid)>.03,"independent actual-mesh detector recognizes solid shirt interior")
	check(Support.shirt_depth(center+Vector3(solid.bounds.size.x,0,0),solid)==0,"actual-mesh detector rejects exterior")
	var notch:=false
	for i in range(2,solid.levels.size()-2):
		var polygon: Array=solid.polygons[i]; var right:=-INF
		for p in polygon: right=maxf(right,p.x)
		if right<solid.bounds.end.x-.012:
			var point:=Vector3(right+.006,float(solid.levels[i]),0)
			if solid.bounds.has_point(point):
				check(Support.shirt_depth(point,solid)==0,"actual-mesh detector leaves concave waist gap empty")
				notch=true; break
	check(notch,"detector regression fixture contains a real waist gap inside outer bounds")

func tail_connections() -> void:
	for style in ["ponytail","high_ponytail","low_ponytail","braid"]:
		for volume in [0.0,1.0]:
			actor.apply_avatar(Support.profile({"hair_style":style,"hat":"none"},{"hair_length":1.0,"hair_volume":volume}))
			var gap:=Support.tail_attachment_gap(actor)
			check(is_finite(gap) and gap<.018,"actual scalp/tail surface contact %s volume%.0f gap=%.4fm"%[style,volume,gap])

func geometry_case(id: String) -> void:
	var result := Support.geometry(actor)
	diagnostics.append({"case":id,"geometry":result})
	check(result.finite and result.meshes>10 and result.samples>1000,id+" actual visible/skinned vertices finite, positive transforms")
	for field in ["hair_skull","hair_eye","arm_head","arm_shirt","hair_shirt","beard_shirt","hair_tank"]:
		check(result[field]==0,id+" no deep "+field+" penetration count="+str(result[field]))

func persistence() -> void:
	var main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); main._autosave_on=false
	var expected:=Support.profile({"body_type":"pear","hair_style":"high_ponytail","eyes":"sparkle","beard":"goatee","blush":"freckles","fringe":"open","hair_accessory":"ribbon"},{"body_build":.91,"head_size":.18,"eye_spacing":.87,"hair_length":.93,"hair_volume":.76,"hair_sweep":.13})
	expected.name="海风捏人"; expected.design_refs={"top":"design:qa/custom-07"}; expected.extensions={"diy":{"revision":7,"palette":["sea","sand"]}}
	check(main.avatar_profile.commit(expected).ok,"save fixture commits new rich appearance and all six morphs")
	main.player.apply_avatar(expected)
	check(main.save_game("",true).ok,"new rich avatar writes through whole-game atomic save")
	var disk:=Save.read(Save.SLOT_PATH)
	check(disk.get("ok",false) and disk.snapshot.profile==JSON.parse_string(JSON.stringify(expected)),"independent disk read preserves every morph, option and DIY field")
	if disk.get("ok",false):
		var broken: Dictionary=disk.snapshot.duplicate(true); broken.profile.morphs.body_build=1.01
		var before: Dictionary=main.save_registry.capture()
		check(not Save.restore(main,broken).ok,"malformed shape rejects whole-game restore")
		check(main.save_registry.capture()==before,"failed shape restore changes no game state")
		main.avatar_profile.from_dict(Profile.fresh())
		check(Save.restore(main,disk.snapshot).ok and main.avatar_profile.query()==disk.snapshot.profile,"whole-game restore recovers exact rich profile")
	main.queue_free(); await process_frame

func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	actor=preload("res://src/player/character.gd").new(); world.add_child(actor); actor.build(); actor.set_process(false); actor.set_physics_process(false); actor._reset_action_pose()
	if OS.get_environment("SEA_AVATAR_PROBE")=="produce":
		for dimensions in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(.5,.5)]:
			actor.apply_avatar(Support.profile({"hair_style":"long","beard":"full","hat":"bucket","top":"vest"},{"body_build":dimensions.x,"head_size":dimensions.y,"hair_length":1.0,"hair_volume":1.0}))
			for frame in 26:
				for crop in ["lettuce","tomato","pumpkin"]:
					Support.sample_action(actor,"harvesting",frame/25.0,crop)
					var report:=Support.produce_geometry(actor)
					if report.head>0: print("[avatar-customization-probe] body/head=",dimensions," progress=",frame/25.0," crop=",crop," ",JSON.stringify(report))
		world.queue_free(); await process_frame
		print("[avatar-customization-probe] diagnostic only; not acceptance")
		quit(0); return
	if OS.get_environment("SEA_AVATAR_PROBE")=="dense":
		for dimensions in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(.5,.5)]:
			actor.apply_avatar(Support.profile({"hair_style":"long","beard":"full","hat":"bucket","top":"vest"},{"body_build":dimensions.x,"head_size":dimensions.y,"head_width":1.0,"arm_girth":1.0,"leg_length":0.0,"hair_length":1.0,"hair_volume":1.0}))
			for progress in [.32,.36,.60,.64,.68]:
				Support.sample_action(actor,"harvesting",progress)
				print("[avatar-customization-probe] body/head=",dimensions," progress=",progress," ",JSON.stringify(Support.head_penetration_detail(actor)))
		world.queue_free(); await process_frame
		print("[avatar-customization-probe] diagnostic only; not acceptance")
		quit(0); return
	if OS.get_environment("SEA_AVATAR_PROBE")=="1":
		for head_size in [0.0,1.0]:
			actor.apply_avatar(Support.profile({"hair_style":"long","hat":"bucket","top":"vest"},{"body_build":1.0,"head_size":head_size,"head_width":1.0,"arm_girth":1.0,"leg_length":0.0}))
			Support.sample_action(actor,"harvesting",.12)
			print("[avatar-customization-probe] initial reach / head=",head_size," ",JSON.stringify(Support.penetration_detail(actor)))
		for entry in Support.cases():
			actor.apply_avatar(entry.profile); Support.sample_action(actor,"idle",0)
			var report:=Support.penetration_detail(actor)
			for id in report:
				if report[id].count>0: print("[avatar-customization-probe] ",entry.id," ",JSON.stringify(report))
		for kind in ["balanced","pear","athletic","soft"]:
			actor.apply_avatar(Support.profile({"body_type":kind},{"body_build":1.0})); Support.sample_action(actor,"idle",0)
			print("[avatar-customization-probe] idle/",kind," ",JSON.stringify(Support.penetration_detail(actor)))
		for build in [0.0,1.0]:
			actor.apply_avatar(Support.profile({"hair_style":"long","beard":"full","hat":"bucket","glasses":"round","top":"vest"},{"body_build":build,"head_size":1.0,"hair_length":1.0,"hair_volume":1.0,"hair_sweep":1.0}))
			Support.sample_action(actor,"harvesting",.8)
			print("[avatar-customization-probe] build=",build," ",JSON.stringify(Support.penetration_detail(actor)))
		world.queue_free(); await process_frame
		print("[avatar-customization-probe] diagnostic only; not acceptance")
		quit(0); return
	profile_contract()
	check(actor.has_method("apply_avatar"),"character exposes full-profile cosmetic adapter")
	if not actor.has_method("apply_avatar"): quit(1); return
	var original: Transform3D=actor.transform
	var skeleton: Skeleton3D=actor.limb_skinning
	var collision: CollisionShape3D=actor.get_node("BodyCollision")
	var shape: CapsuleShape3D=collision.shape
	morphology(); blush_contract(); detector_contract(); tail_connections()
	for entry in Support.cases():
		Support.sample_action(actor,"idle",0); actor.apply_avatar(entry.profile); geometry_case(entry.id)
		check(actor.transform==original and actor.scale.is_equal_approx(Vector3.ONE) and collision.shape==shape and is_equal_approx(shape.radius,.22) and is_equal_approx(shape.height,1.3) and actor.limb_skinning==skeleton,"cosmetic matrix preserves actor, collision and rig "+entry.id)
		await process_frame
	for style in ["long","high_ponytail","braid"]:
		for build in [0.0,1.0]:
			actor.apply_avatar(Support.profile({"hair_style":style,"beard":"full","hat":"bucket","glasses":"round","top":"vest"},{"body_build":build,"head_size":1.0,"head_width":1.0,"arm_girth":1.0,"leg_length":0.0,"hair_length":1.0,"hair_volume":1.0,"hair_sweep":1.0}))
			for action in ["walking","rowing","planting","watering","harvesting","swimming"]:
				for progress in [.2,.5,.8]:
					Support.sample_action(actor,action,progress); geometry_case("%s/build%.0f/%s/%.1f"%[style,build,action,progress])
					await process_frame
	# The tuck/return curve can cross the abdomen between broad action samples.
	# Densely sample actual arm skin at all four body/head extrema plus reference.
	for dimensions in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(.5,.5)]:
		actor.apply_avatar(Support.profile({"hair_style":"long","beard":"full","hat":"bucket","top":"vest"},{"body_build":dimensions.x,"head_size":dimensions.y,"head_width":1.0,"arm_girth":1.0,"leg_length":0.0,"hair_length":1.0,"hair_volume":1.0}))
		for frame in 26:
			var progress:=frame/25.0
			Support.sample_action(actor,"harvesting",progress)
			var result:=Support.arm_geometry(actor)
			var id:="harvest-dense/body%.1f/head%.1f/frame%02d"%[dimensions.x,dimensions.y,frame]
			diagnostics.append({"case":id,"geometry":result})
			check(result.finite and result.samples>1000,id+" actual arm skin finite")
			check(result.arm_head==0,id+" no deep arm/head penetration count="+str(result.arm_head))
			check(result.arm_shirt==0,id+" no deep arm/shirt penetration count="+str(result.arm_shirt))
			if result.arm_shirt>0: print("[avatar-customization-detail] ",id," ",JSON.stringify(Support.penetration_detail(actor)))
			if result.arm_head>0: print("[avatar-customization-detail] ",id," ",JSON.stringify(Support.head_penetration_detail(actor)))
			for crop in ["lettuce","tomato","pumpkin"]:
				Support.sample_action(actor,"harvesting",progress,crop)
				var produce:=Support.produce_geometry(actor)
				var expected_visibility: bool=produce.visible if progress<=.14 or progress>=.90 else true
				check(produce.finite and produce.visible==expected_visibility and (not produce.visible or produce.vertices>10),id+" actual "+crop+" mesh finite / visible through carrying interval")
				check(produce.head==0,id+" actual "+crop+" vertices and triangle centers clear head count="+str(produce.head))
				check(produce.hat==0,id+" actual "+crop+" vertices and triangle centers clear hat count="+str(produce.hat))
				if produce.head>0: print("[avatar-customization-detail] ",id," ",crop," ",JSON.stringify(produce))
			await process_frame
	world.queue_free(); await process_frame
	await persistence()
	var file:=FileAccess.open("res://outputs/avatar-customization-geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":diagnostics},"\t")); file.close()
	print("[avatar-customization] %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
