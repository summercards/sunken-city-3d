extends SceneTree
## Actual renderer contact sheets plus real mouse/key/scroll input in the full
## dock editor at all supported desktop sizes. All output belongs to the runner.
const Support=preload("res://tests/avatar_customization_support.gd")
const Catalog=preload("res://src/avatar/avatar_catalog.gd")
const Save=preload("res://src/save/save_game.gd")
var checks:=0
var failures:=0
var main: Node
var preview: SubViewport
var actor
var camera: Camera3D
var caption: Label
var sheets: Array[String]=[]

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-customization-render] ","PASS " if ok else "FAIL ",label)
func settle(frames:=6) -> void:
	for i in frames: await process_frame
func mouse(point: Vector2,pressed: bool) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=point; root.push_input(motion,true)
	var event:=InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	root.push_input(event,true); await process_frame
func click(control: Control,fraction:=Vector2(.5,.5)) -> void:
	await settle(2)
	var point:=control.get_global_transform_with_canvas()*(control.size*fraction)
	await mouse(point,true); await mouse(point,false); await settle(3)
func key(code: Key,ctrl:=false,shift:=false) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new(); event.keycode=code; event.ctrl_pressed=ctrl; event.shift_pressed=shift; event.pressed=pressed
		root.push_input(event,true); await process_frame
	await settle(2)
func wheel(control: Control,count: int) -> void:
	var point:=control.get_global_transform_with_canvas()*(control.size*.5)
	for i in count:
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_WHEEL_DOWN; event.pressed=pressed; root.push_input(event,true); await process_frame
	await settle(3)
func reveal(editor,control: Control) -> void:
	editor.options_scroll.ensure_control_visible(control); await settle(3)
func shot(id: String) -> void:
	await settle(); await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://outputs/avatar-customization-"+id+".png")==OK,"actual full-game frame "+id)
func wait_phase(value: String) -> void:
	var deadline:=Time.get_ticks_msec()+8000
	while main.avatar_session.phase!=value and Time.get_ticks_msec()<deadline: await process_frame
	check(main.avatar_session.phase==value,"session reaches "+value)

func stage() -> void:
	preview=SubViewport.new(); preview.name="CustomizationQAStage"; preview.size=Vector2i(480,400); preview.own_world_3d=true
	preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS; preview.msaa_3d=Viewport.MSAA_2X; root.add_child(preview)
	var world:=Node3D.new(); preview.add_child(world)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color("#eee9da")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color.WHITE; env.environment.ambient_light_energy=.70; world.add_child(env)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-38,-28,0); sun.light_energy=.8; world.add_child(sun)
	actor=preload("res://src/player/character.gd").new(); world.add_child(actor); actor.build(); actor.set_process(false); actor.set_physics_process(false); actor._reset_action_pose()
	camera=Camera3D.new(); camera.current=true; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1.6; world.add_child(camera)
	var layer:=CanvasLayer.new(); preview.add_child(layer)
	caption=Label.new(); caption.position=Vector2(15,10); caption.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded()); caption.add_theme_font_size_override("font_size",18); caption.add_theme_color_override("font_color",Color("#554a42")); layer.add_child(caption)

func tile(profile: Dictionary,yaw: float,label: String,face:=false,action: String="idle",progress:=.52,crop: String="lettuce") -> Image:
	Support.sample_action(actor,"idle",0); actor.apply_avatar(profile); Support.sample_action(actor,action,progress,crop); actor.set_preview_yaw(yaw)
	caption.text=label
	var center: Vector3=actor.head_pivot.global_position if face else Vector3(0,.85 if action=="harvesting" else .75,0)
	camera.size=.88 if face else (2.25 if action=="harvesting" else 1.80)
	camera.position=center+Vector3(.10,.07,4.0); camera.look_at(center)
	await settle(3); await RenderingServer.frame_post_draw
	var image:=preview.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	var background:=image.get_pixel(image.get_width()-5,image.get_height()-5)
	var foreground:=0
	for y in range(48,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			var pixel:=image.get_pixel(x,y)
			if Vector3(pixel.r-background.r,pixel.g-background.g,pixel.b-background.b).length()>.12: foreground+=1
	check(foreground>1200,"real nonempty foreground "+label+" sampled_pixels="+str(foreground))
	return image

func contact_sheet(id: String,entries: Array,views: Array,face:=false) -> void:
	var sheet:=Image.create(480*views.size(),400*entries.size(),false,Image.FORMAT_RGBA8); sheet.fill(Color("#eee9da"))
	for row in entries.size():
		var previous: Image
		for column in views.size():
			var entry: Dictionary=entries[row]; var view: Dictionary=views[column]
			var image: Image=await tile(entry.profile,view.yaw,str(entry.id)+" / "+str(view.id),face,str(entry.get("action","idle")),float(entry.get("progress",.52)),str(entry.get("crop","lettuce")))
			if previous!=null:
				var different:=0
				for y in range(48,image.get_height(),2):
					for x in range(0,image.get_width(),2):
						var a:=image.get_pixel(x,y); var b:=previous.get_pixel(x,y)
						if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.12: different+=1
				check(different>500,"distinct rendered views "+str(entry.id)+"/"+str(view.id)+" changed="+str(different))
			previous=image
			sheet.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(column*480,row*400))
	check(sheet.save_png("res://outputs/avatar-customization-"+id+".png")==OK,"native renderer contact sheet "+id)
	sheets.append(id)

func gallery() -> void:
	stage()
	var views: Array=[{"id":"front","yaw":0.0},{"id":"side","yaw":PI/2},{"id":"back","yaw":PI}]
	var entries: Array=[]
	for option in Catalog.options("hair_style"):
		var accessory: String="ribbon" if entries.size()%2==0 else "band"
		entries.append({"id":str(option.id)+" / "+accessory,"profile":Support.profile({"hair_style":option.id,"hair_accessory":accessory,"hat":"none","blush":"peach"},{"hair_length":1.0,"hair_volume":1.0})})
		if entries.size()==4: await contact_sheet("hair-"+str(sheets.size()+1),entries,views); entries=[]
	if not entries.is_empty(): await contact_sheet("hair-final",entries,views)
	entries=[]
	for option in Catalog.options("eyes"):
		entries.append({"id":"eyes/"+str(option.id),"profile":Support.profile({"hair_style":"pixie","fringe":"open","eyes":option.id,"blush":"peach"},{"eye_spacing":1.0})})
		if entries.size()==4: await contact_sheet("eyes-"+str(sheets.size()+1),entries,[views[0]],true); entries=[]
	entries=[]
	for option in Catalog.options("beard"):
		entries.append({"id":"beard/"+str(option.id),"profile":Support.profile({"hair_style":"undercut","fringe":"open","beard":option.id,"blush":"freckles","glasses":"round"},{"head_size":1.0,"eye_spacing":0.0})})
	await contact_sheet("beards-textures",entries,[views[0],views[1]],true)
	entries=[]
	for hat in ["fedora","bucket","beanie"]:
		entries.append({"id":"hat/"+hat+" max-volume","profile":Support.profile({"hair_style":"high_ponytail","fringe":"straight","hat":hat,"beard":"goatee","glasses":"round"},{"head_size":1.0,"hair_length":1.0,"hair_volume":1.0,"hair_sweep":1.0})})
	await contact_sheet("hat-clearance",entries,views)
	entries=[]
	for shape in Catalog.options("body_type"):
		for build in [0.0,1.0]:
			entries.append({"id":str(shape.id)+" / build="+str(build),"profile":Support.profile({"body_type":shape.id,"hair_style":"low_ponytail","hat":"bucket","top":"vest","beard":"full"},{"body_build":build,"head_size":1.0-build,"hair_length":1.0,"hair_volume":1.0})})
		if entries.size()==4: await contact_sheet("body-"+str(sheets.size()+1),entries,views); entries=[]
	entries=[]
	for action in ["walking","rowing","planting","watering","harvesting","swimming"]:
		entries.append({"id":action+" / maximal","action":action,"profile":Support.profile({"body_type":"soft","hair_style":"long","hat":"fedora","beard":"full","glasses":"round"},{"body_build":1.0,"head_size":1.0,"hair_length":1.0,"hair_volume":1.0,"hair_sweep":1.0})})
		if entries.size()==3: await contact_sheet("actions-"+str(sheets.size()+1),entries,views); entries=[]
	for build in [0.0,1.0]:
		entries.append({"id":"harvest-tuck / build="+str(build),"action":"harvesting","progress":.8,"profile":Support.profile({"hair_style":"long","top":"vest","hat":"bucket","beard":"full"},{"body_build":build,"head_size":1.0,"hair_length":1.0,"hair_volume":1.0})})
	await contact_sheet("harvest-tuck",entries,views)
	for dimensions in [Vector2(0,1),Vector2(1,1),Vector2(.5,.5)]:
		entries=[]
		for progress in [.32,.36,.60,.68]:
			var crop: String="lettuce" if progress==.32 else ("tomato" if progress==.36 else "pumpkin")
			entries.append({"id":"%s %.2f / body%.1f head%.1f"%[crop,progress,dimensions.x,dimensions.y],"action":"harvesting","crop":crop,"progress":progress,"profile":Support.profile({"hair_style":"long","top":"vest","hat":"bucket","beard":"full"},{"body_build":dimensions.x,"head_size":dimensions.y,"hair_length":1.0,"hair_volume":1.0})})
		await contact_sheet("harvest-risk-body%.1f-head%.1f"%[dimensions.x,dimensions.y],entries,views)
	entries=[{"id":"dive-mask / max head + glasses","action":"swimming","profile":Support.profile({"hair_style":"long","beard":"full","glasses":"round","blush":"peach"},{"head_size":1.0,"eye_spacing":1.0,"hair_length":1.0,"hair_volume":1.0})}]
	await contact_sheet("dive-mask",entries,[views[0],views[1]],true)
	preview.queue_free(); await process_frame

func ui_flow() -> void:
	main=load("res://scenes/main.tscn").instantiate(); root.add_child(main); main._autosave_on=false
	main._place_new_traveler(); main._begin_avatar_edit(); await wait_phase("editing")
	var editor=main.avatar_session.editor
	if editor==null: return
	editor.name_input.text="捏人验收"; editor.name_input.text_changed.emit("捏人验收"); await click(editor.next_button)
	check(editor.step==1,"real mouse opens appearance editor")
	var committed: Dictionary=main.avatar_profile.query()
	var position: Vector3=main.player.global_position
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=resolution; await settle(8)
		var extent:=root.get_visible_rect()
		check(extent.encloses(editor.paper.get_global_rect()) and extent.encloses(editor.next_button.get_global_rect()) and extent.encloses(editor.buttons["view/face"].get_global_rect()),"paper/footer/view controls fit "+str(resolution))
		await click(editor.buttons["group/body"])
		var slider: HSlider=editor.morph_sliders.body_build
		await reveal(editor,slider)
		await click(slider,Vector2(.85,.5)); var changed: float=editor.draft.morphs.body_build
		check(changed>.7 and is_equal_approx(main.player.get_meta("avatar_morphs").body_build,changed),"real slider previews complete profile "+str(resolution))
		check(main.avatar_profile.query()==committed,"real preview keeps committed state isolated "+str(resolution))
		var current_slider: HSlider=editor.morph_sliders.body_build
		check(root.gui_get_focus_owner()==current_slider,"slider retains keyboard focus during live preview "+str(resolution))
		await key(KEY_RIGHT)
		check(editor.draft.morphs.body_build>changed,"real arrow key fine-tunes focused slider "+str(resolution))
		var fine: float=editor.draft.morphs.body_build
		await key(KEY_Z,true)
		check(is_equal_approx(editor.draft.morphs.body_build,changed),"real Ctrl+Z undoes one keyboard adjustment "+str(resolution))
		await key(KEY_Z,true,true)
		check(is_equal_approx(editor.draft.morphs.body_build,fine),"real Ctrl+Shift+Z restores adjustment "+str(resolution))
		for id in ["arm_girth","leg_length"]:
			await reveal(editor,editor.morph_sliders[id]); await click(editor.morph_sliders[id],Vector2(.72,.5))
			check(editor.draft.morphs[id]>.6 and main.player.get_meta("avatar_morphs")[id]>.6,"real independent shape slider "+id+" "+str(resolution))
		await click(editor.buttons["sub/head"])
		await click(editor.morph_sliders.head_width,Vector2(.7,.5))
		check(editor.draft.morphs.head_width>.6,"real horizontal head slider "+str(resolution))
		await click(editor.buttons["group/hair"]); await click(editor.buttons["hair_style/high_ponytail"])
		check(main.player.get_meta("avatar_appearance").hair_style=="high_ponytail","real choice previews ponytail "+str(resolution))
		await wheel(editor.options_scroll,8)
		var ribbon: Control=editor.buttons["hair_accessory/ribbon"]; await reveal(editor,ribbon)
		var retained: int=editor.options_scroll.scroll_vertical; await click(ribbon)
		check(retained>0 and retained==editor.options_scroll.scroll_vertical,"option selection keeps lower scroll position "+str(resolution))
		await click(editor.buttons["sub/diy"])
		for id in ["hair_length","hair_volume","hair_sweep"]:
			await reveal(editor,editor.morph_sliders[id]); await click(editor.morph_sliders[id],Vector2(.77,.5))
			check(editor.draft.morphs[id]>.65,"real DIY slider "+id+" "+str(resolution))
		await shot("ui-hair-"+str(resolution.x))
		await click(editor.buttons["group/eyes"]); await click(editor.buttons["eyes/sparkle"])
		await click(editor.buttons["sub/spacing"]); await click(editor.morph_sliders.eye_spacing,Vector2(.9,.5))
		check(editor.draft.appearance.eyes=="sparkle" and editor.draft.morphs.eye_spacing>.75,"real eyes and spacing controls "+str(resolution))
		await click(editor.buttons["group/face"]); await click(editor.buttons["sub/beard"]); await click(editor.buttons["beard/full"])
		await click(editor.buttons["sub/blush"]); await click(editor.buttons["blush/peach"])
		var emotion_draft: Dictionary=editor.draft.duplicate(true)
		for mode in ["happy","focused","surprised","concerned","neutral"]:
			await click(editor.buttons["expression/"+mode])
			check(main.player.expression_state().mode==mode and editor.draft==emotion_draft,"real emotion preview is transient "+mode+" "+str(resolution))
		await shot("ui-face-"+str(resolution.x))
		var draft_before: Dictionary=editor.draft.duplicate(true)
		var compare: Control=editor.buttons.compare; var point: Vector2=compare.get_global_transform_with_canvas()*(compare.size*.5)
		await mouse(point,true); await settle(3)
		check(main.player.get_meta("avatar_morphs")==committed.morphs and editor.draft==draft_before,"held compare previews original without mutating draft "+str(resolution))
		await mouse(Vector2(35,35),false); await settle(3)
		check(main.player.get_meta("avatar_morphs")==draft_before.morphs and editor.draft==draft_before,"compare release outside control restores draft "+str(resolution))
		check(main.player.global_position.is_equal_approx(position),"mouse/scroll/keys never move world actor "+str(resolution))
	# A multi-frame drag is one reversible transaction.
	await click(editor.buttons["group/body"]); await reveal(editor,editor.morph_sliders.body_build)
	var before_drag: float=editor.draft.morphs.body_build
	var drag: HSlider=editor.morph_sliders.body_build
	await mouse(drag.get_global_transform_with_canvas()*(drag.size*Vector2(before_drag,.5)),true)
	for fraction in [.65,.55,.40,.23]:
		var motion:=InputEventMouseMotion.new(); motion.position=drag.get_global_transform_with_canvas()*(drag.size*Vector2(fraction,.5)); motion.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(motion,true); await process_frame
	await mouse(drag.get_global_transform_with_canvas()*(drag.size*Vector2(.23,.5)),false)
	check(editor.draft.morphs.body_build<.35,"multi-frame real mouse drag changes body")
	await click(editor.buttons.undo)
	check(is_equal_approx(editor.draft.morphs.body_build,before_drag),"one Undo reverses the complete real drag")
	var hair_before: Dictionary=editor.draft.morphs.duplicate(true)
	await click(editor.buttons.group_reset)
	check(editor.draft.morphs.body_build==.5 and editor.draft.morphs.head_size==.5 and editor.draft.morphs.hair_length==hair_before.hair_length,"category reset changes only its morphs")
	await click(editor.buttons.undo)
	check(editor.draft.morphs==hair_before,"category reset is one undo transaction")
	await click(editor.buttons["view/body"]); await settle(30)
	var body_position: Vector3=main.cam.global_position
	await click(editor.buttons["view/face"]); await settle(30)
	check(main.cam.global_position.distance_to(body_position)>.1,"real face/body controls move camera")
	await click(editor.next_button)
	check(editor.step==2,"real confirmation page opens")
	await shot("ui-confirm")
	var expected: Dictionary=editor.draft.duplicate(true); expected.completed=true
	await click(editor.next_button); await wait_phase("idle")
	var disk:=Save.read(Save.SLOT_PATH)
	check(disk.get("ok",false) and disk.snapshot.profile==JSON.parse_string(JSON.stringify(expected)),"real UI save persists exact rich character to disk")
	check(main.player.global_position.is_equal_approx(position),"saving preserves original dock position")
	main._begin_avatar_edit(); await wait_phase("editing"); editor=main.avatar_session.editor
	editor.step=1; editor.render(); await click(editor.buttons["group/body"]); await click(editor.buttons["sub/head"]); await click(editor.morph_sliders.head_size,Vector2(.1,.5))
	check(main.avatar_profile.query()==expected,"reopened morph preview remains transactional")
	await click(editor.back_button); await click(editor.back_button); await wait_phase("idle")
	check(main.avatar_profile.query()==expected and main.player.get_meta("avatar_morphs")==expected.morphs,"real cancel restores all saved morphs")
	main.queue_free(); await process_frame

func run() -> void:
	check(DisplayServer.get_name()!="headless","visual suite uses native renderer")
	if DisplayServer.get_name()=="headless": quit(1); return
	DisplayServer.window_set_title("SEA Avatar QA · Visual verification")
	await gallery(); await ui_flow()
	print("[avatar-customization-render] %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
