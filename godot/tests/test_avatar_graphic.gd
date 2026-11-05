extends SceneTree
## Real texture/animation/mesh evidence for user-reported upper-arm and hip gaps.
const Support=preload("res://tests/avatar_customization_support.gd")
const Catalog=preload("res://src/avatar/avatar_catalog.gd")
var checks:=0
var failures:=0
var actor
var camera: Camera3D
var caption: Label
var visual:=false
var sheets: Array[String]=[]

func pixel_diff(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-graphic] ","PASS " if ok else "FAIL ",label)

func settle() -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw

func screenshot(label: String) -> Image:
	caption.text=label
	await settle()
	var result:=root.get_texture().get_image(); result.convert(Image.FORMAT_RGBA8)
	return result

func save_sheet(name: String, entries: Array, columns: int, face: bool) -> void:
	if not visual: return
	var sheet:=Image.create(480*columns,480*ceili(float(entries.size())/columns),false,Image.FORMAT_RGBA8)
	sheet.fill(Color("#eee9da"))
	for i in entries.size():
		var entry: Dictionary=entries[i]
		actor.cancel_action("graphic-sheet"); actor.set_diving(false); actor._reset_action_pose()
		actor.apply_avatar(entry.get("profile",Support.profile({"hair_style":"undercut","fringe":"open","blush":"none"})))
		actor.set_preview_yaw(float(entry.get("yaw",0.0)))
		var expression: String=entry.get("expression","neutral")
		actor.preview_expression(expression,10.0)
		actor._avatar_visual.expression.sample(float(entry.get("clock",1.0)),"idle",0.0,0.0)
		var center: Vector3=actor.head_pivot.global_position+Vector3(0,-.04,0) if face else Vector3(0,.68,0)
		camera.size=.80 if face else 1.60
		camera.position=center+Vector3(.0,.02,4); camera.look_at(center)
		var frame: Image=await screenshot(str(entry.label))
		check(pixel_diff(frame.get_pixel(240,240),frame.get_pixel(5,470))>.02,"rendered foreground "+str(entry.label))
		sheet.blit_rect(frame,Rect2i(0,0,480,480),Vector2i((i%columns)*480,(i/columns)*480))
	check(sheet.save_png("res://outputs/avatar-graphic-"+name+".png")==OK,"native contact sheet "+name)
	sheets.append(name)

func ring_center(points: PackedVector3Array, ring: Dictionary) -> Vector3:
	var sum:=Vector3.ZERO
	for i in int(ring.count): sum+=points[int(ring.start)+i]
	return sum/float(ring.count)

func body_contract() -> void:
	# Ring distances and the reference silhouette below are authored at 1.0 scale;
	# multiply by SCALE so the same assertions hold for the enlarged body.
	var k: float=actor.Dimensions.SCALE
	for kind in ["balanced","pear","athletic","soft"]:
		for build in [0.0,.5,1.0]:
			actor.apply_avatar(Support.profile({"body_type":kind},{"body_build":build}))
			actor._reset_action_pose()
			var pelvis: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Pelvis")
			var solid:=Support.shirt_solid(pelvis,actor.body_pivot)
			var shirt: MeshInstance3D=actor.body_pivot.get_node("AvatarBody/Shirt")
			var shirt_solid:=Support.shirt_solid(shirt,actor.body_pivot)
			check(solid.bounds.end.y>shirt_solid.bounds.position.y+.02*k,"pelvis overlaps shirt hem "+kind+str(build))
			for limb in ["arm.L","arm.R"]:
				var data: Dictionary=actor.limb_skinning.surface_data(limb)
				var points: PackedVector3Array=actor.limb_skinning.deformed_points(limb)
				var centers:=PackedVector3Array()
				for ring in data.rings:
					if ring.distance>=.005*k and ring.distance<=.115*k: centers.append(ring_center(points,ring))
				var error:=0.0
				for c in centers: error=maxf(error,c.distance_to(Geometry3D.get_closest_point_to_segment(c,centers[0],centers[-1])))
				check(error<.001,"actual upper-arm centreline straight "+limb+kind+str(build)+" err="+str(error))
				var contact:=0
				for i in points.size():
					if data.uv2[i].x>=-.01*k and data.uv2[i].x<.025*k and Support.shirt_depth(points[i],shirt_solid)>.0005*k: contact+=1
				check(contact>3,"actual sleeve overlaps torso socket "+limb+kind+str(build)+" contacts="+str(contact))
			for limb in ["leg.L","leg.R"]:
				var data: Dictionary=actor.limb_skinning.surface_data(limb)
				var points: PackedVector3Array=actor.limb_skinning.deformed_points(limb)
				var contact:=0
				for i in points.size():
					if data.uv2[i].x<=.025*k and Support.shirt_depth(points[i],solid)>.001*k: contact+=1
				check(contact>12,"actual thigh attached inside pelvis "+limb+kind+str(build)+" contacts="+str(contact))
	# Independent sliders alter the actual mesh while leaving other axes intact.
	for id in ["head_width","arm_girth","leg_length"]:
		var samples: Array=[]
		for value in [0.0,1.0]:
			var profile:=Support.profile(); profile.morphs[id]=value
			actor.apply_avatar(profile); actor._reset_action_pose()
			if id=="head_width": samples.append(Support.bounds(Support.points(actor.head_pivot.get_node("AvatarHead/Face"),actor)).size)
			elif id=="arm_girth":
				var data: Dictionary=actor.limb_skinning.surface_data("arm.L")
				var points: PackedVector3Array=actor.limb_skinning.deformed_points("arm.L")
				for ring in data.rings:
					if absf(float(ring.distance)-.05*k)<.00001:
						var center:=ring_center(points,ring); var radius:=0.0
						for j in int(ring.count): radius=maxf(radius,center.distance_to(points[int(ring.start)+j]))
						samples.append(radius); break
			else: samples.append(actor.left_leg.position.y)
		if id=="head_width": check(samples[1].x>samples[0].x*1.2 and is_equal_approx(samples[1].y,samples[0].y),"horizontal head control changes actual width independently of height")
		else: check(float(samples[1])>float(samples[0])*1.2,"actual independent control "+id)
	var old:=Support.profile()
	for id in ["head_width","arm_girth","leg_length"]: old.morphs.erase(id)
	var profile_model=preload("res://src/avatar/avatar_profile.gd").new(); profile_model.from_dict(old)
	check(preload("res://src/avatar/avatar_profile.gd").validate_snapshot(old)=="" and profile_model.query().morphs.size()==9,"original six morph save gains explicit three new defaults")
	# Latest user's fat-body red lines. Infer the socket from the actual skinned
	# segment centreline rather than reading the production shoulder factors.
	actor.apply_avatar(Support.profile({}, {"body_build":1.0})); actor._reset_action_pose()
	for limb in ["arm.L","arm.R"]:
		var data: Dictionary=actor.limb_skinning.surface_data(limb)
		var points: PackedVector3Array=actor.limb_skinning.deformed_points(limb)
		var near:=Vector3.ZERO; var far:=Vector3.ZERO
		for ring in data.rings:
			if absf(float(ring.distance)-.005*k)<.00001: near=ring_center(points,ring)
			if absf(float(ring.distance)-.025*k)<.00001: far=ring_center(points,ring)
		var socket:=near-(far-near)*.25
		check(absf(absf(socket.x)-.145*k)<.015*k,"red-line actual socket horizontal "+limb+" x="+str(socket.x))
		check(absf(socket.y-.741*k)<.010*k,"red-line actual socket lowered "+limb+" y="+str(socket.y))
		for ring in data.rings:
			if absf(float(ring.distance)-actor.Dimensions.UPPER_ARM-actor.Dimensions.LOWER_ARM)<.00001:
				var wrist:=ring_center(points,ring)
				check(absf(wrist.x)>.31*k and absf(wrist.x)<.36*k and wrist.y>.39*k and wrist.y<.425*k,"red-line relaxed wrist silhouette "+limb+" at="+str(wrist))

func expression_contract() -> void:
	for option in Catalog.options("eyes"):
		actor.apply_avatar(Support.profile({"eyes":option.id,"hair_style":"undercut","fringe":"open"}))
		var eyes:=Support.meshes(actor,"eye")
		check(eyes.size()==2,"one graphic texture per eye, no layered gloss "+str(option.id))
		for eye in eyes:
			var mat: ShaderMaterial=eye.material_override
			var texture: Texture2D=mat.get_shader_parameter("eye_atlas")
			check(texture!=null and texture.get_width()==1024 and texture.get_height()==768,"production atlas loaded "+str(option.id))
	for option in Catalog.options("mouth"):
		actor.apply_avatar(Support.profile({"mouth":option.id}))
		var mouths:=Support.meshes(actor,"mouth")
		check(mouths.size()==1 and mouths[0].material_override is ShaderMaterial,"one textured graphic mouth "+str(option.id))
		var texture: Texture2D=mouths[0].material_override.get_shader_parameter("mouth_atlas")
		check(texture!=null and texture.get_width()==1024 and texture.get_height()==1024,"production mouth atlas loaded "+str(option.id))
	var p:=Support.profile(); actor.apply_avatar(p)
	var appearance: Dictionary=actor.get_meta("avatar_appearance").duplicate(true)
	for mode in ["neutral","happy","focused","surprised","concerned","calm"]:
		actor.preview_expression(mode,10)
		actor._avatar_visual.expression.sample(1.0,"idle",0.0,0.0)
		check(actor.expression_state().mode==mode,"independent preview expression "+mode)
		var active:=0
		for child in actor.head_pivot.get_node("AvatarHead/FaceDetails").get_children():
			if child.has_meta("avatar_expression") and child.visible: active+=1
		check(active==1,"exactly one brow/mouth expression visible "+mode)
	actor.preview_expression("auto")
	for entry in [["idle","neutral"],["watering","focused"],["swimming","calm"],["harvesting","happy"]]:
		actor._avatar_visual.expression.sample(1.0,entry[0],.5,0)
		check(actor.expression_state().mode==entry[1],"action emotion adapter "+entry[0])
	actor._avatar_visual.expression.sample(3.45,"idle",0,0)
	check(actor.expression_state().blink<.05,"blink closes texture aperture")
	actor._avatar_visual.expression.sample(1.0,"idle",0,0)
	check(actor.expression_state().blink>.95,"blink reopens original eye")
	check(actor.get_meta("avatar_appearance")==appearance and p==Support.profile(),"expressions never mutate saved identity")

func carry_contract() -> void:
	for hat in ["none","bucket","beanie","fedora"]:
		for head_size in [0.0,1.0]:
			actor.apply_avatar(Support.profile({"hat":hat,"hair_style":"high_ponytail"},{"head_size":head_size,"body_build":1.0-head_size}))
			for frame in 26:
				var failed_head:=0; var failed_hat:=0
				for crop in ["lettuce","tomato","pumpkin"]:
					Support.sample_action(actor,"harvesting",frame/25.0,crop)
					var result:=Support.produce_geometry(actor)
					failed_head+=int(result.head); failed_hat+=int(result.hat)
				check(failed_head==0 and failed_hat==0,"actual three produce shapes clear face/hat "+hat+" head="+str(head_size)+" frame="+str(frame)+" head/hat="+str(failed_head)+"/"+str(failed_hat))
				await process_frame

func expression_clip() -> void:
	if not visual: return
	actor.cancel_action("expression-clip"); actor._reset_action_pose()
	actor.apply_avatar(Support.profile({"hair_style":"side","blush":"none","eyes":"almond"}))
	camera.size=.80; var center: Vector3=actor.head_pivot.global_position+Vector3(0,-.04,0)
	camera.position=center+Vector3(0,.02,4); camera.look_at(center)
	DirAccess.make_dir_recursive_absolute("res://outputs/avatar-expression-clip")
	var valid:=true
	for frame in 48:
		var mode: String=["neutral","happy","focused","surprised","concerned","neutral"][frame/8]
		actor.preview_expression(mode,10); actor._avatar_visual.expression.sample(1.0+frame*.1,"idle",0,0)
		var rendered: Image=await screenshot(mode)
		valid=rendered.save_png("res://outputs/avatar-expression-clip/%03d.png"%frame)==OK and valid
	check(valid,"continuous native expression animation frames")

func run() -> void:
	visual=DisplayServer.get_name()!="headless"
	if visual: root.size=Vector2i(480,480); root.content_scale_size=Vector2i(480,480)
	var world:=Node3D.new(); root.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("#eee9da")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=.8; world.add_child(env)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-38,-28,0); light.light_energy=.7; world.add_child(light)
	actor=preload("res://src/player/character.gd").new(); world.add_child(actor); actor.build(); actor.set_process(false); actor.set_physics_process(false)
	camera=Camera3D.new(); camera.current=true; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; world.add_child(camera)
	var layer:=CanvasLayer.new(); root.add_child(layer); caption=Label.new(); caption.position=Vector2(10,8); caption.add_theme_font_size_override("font_size",18); caption.add_theme_color_override("font_color",Color("#554a42")); layer.add_child(caption)
	body_contract(); expression_contract(); await carry_contract()
	var entries: Array=[]
	for eye in Catalog.options("eyes"): entries.append({"label":str(eye.id),"profile":Support.profile({"eyes":eye.id,"hair_style":"undercut","fringe":"open","blush":"none"})})
	await save_sheet("eyes",entries,4,true)
	entries=[]
	for mouth in Catalog.options("mouth"): entries.append({"label":str(mouth.id),"profile":Support.profile({"mouth":mouth.id,"hair_style":"undercut","fringe":"open","blush":"none"})})
	await save_sheet("mouths",entries,4,true)
	entries=[]
	for mode in ["neutral","happy","focused","surprised","concerned","calm"]: entries.append({"label":mode,"expression":mode})
	entries.append({"label":"blink closed","clock":3.45}); entries.append({"label":"blink open","clock":1.0})
	await save_sheet("expressions",entries,4,true)
	if visual:
		# Actual GPU pixels must change, not only metadata or shader parameters.
		actor.preview_expression("neutral",10); actor._avatar_visual.expression.sample(1.0,"idle",0,0)
		var a: Image=await screenshot("animation pixel baseline")
		actor._avatar_visual.expression.sample(3.45,"idle",0,0)
		var b: Image=await screenshot("animation blink")
		var changed:=0
		for y in range(75,400):
			for x in range(60,420):
				if pixel_diff(a.get_pixel(x,y),b.get_pixel(x,y))>.08: changed+=1
		check(changed>150,"real GPU blink changes facial pixels count="+str(changed))
	for kind in ["balanced","pear","athletic","soft"]:
		entries=[]
		for build in [0.0,1.0]:
			for yaw in [0.0,PI/2,PI]:
				entries.append({"label":kind+" build="+str(build)+" yaw="+str(yaw),"yaw":yaw,"profile":Support.profile({"body_type":kind,"top":"stripe"},{"body_build":build})})
		await save_sheet("body-"+kind,entries,3,false)
	await expression_clip()
	actor.cancel_action("graphic-test"); world.queue_free(); layer.queue_free(); await process_frame
	print("[avatar-graphic] %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
