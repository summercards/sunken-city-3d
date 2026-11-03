extends SceneTree
## Native final-source views of the latest user-marked shoulder sockets.
const Support=preload("res://tests/avatar_customization_support.gd")
var checks:=0
var failures:=0
var actor
var camera: Camera3D
var caption: Label

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("[avatar-shoulders] ","PASS " if ok else "FAIL ",label)

func tile(build: float,yaw: float,action: String="idle") -> Image:
	actor.cancel_action("shoulder-gallery"); actor.set_walking(false); actor.set_rowing(false); actor.set_diving(false)
	actor._reset_action_pose(); actor._t=0.0
	var profile:=Support.profile({},{"body_build":build})
	if action!="idle":profile.morphs.merge({"head_size":1.0,"head_width":1.0,"arm_girth":1.0,"leg_length":0.0},true)
	actor.apply_avatar(profile);Support.sample_action(actor,action,0.0 if action=="idle" else .52);actor.set_preview_yaw(yaw)
	camera.size=2.25 if action=="harvesting" else 1.60
	var center:=Vector3(0,.86 if action=="harvesting" else .68,0)
	camera.position=center+Vector3(0,.02,4.0);camera.look_at(center)
	caption.text=("纤细" if build==0 else ("标准" if build==.5 else "饱满"))+" · "+("正面" if yaw==0 else ("侧面" if yaw==PI/2 else "背面"))+" · "+action
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	var frame:=root.get_texture().get_image();frame.convert(Image.FORMAT_RGBA8)
	var background:=frame.get_pixel(3,470);var count:=0
	for y in range(40,470,3):
		for x in range(4,476,3):
			var pixel:=frame.get_pixel(x,y)
			if Vector3(pixel.r-background.r,pixel.g-background.g,pixel.b-background.b).length()>.12:count+=1
	check(count>800,"native nonempty shoulder view "+str(build)+"/"+action+"/"+str(yaw))
	return frame

func run() -> void:
	check(DisplayServer.get_name()!="headless","real renderer required")
	if DisplayServer.get_name()=="headless":quit(1);return
	root.size=Vector2i(480,480);root.content_scale_size=Vector2i(480,480)
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("#eee9da")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-38,-28,0);light.light_energy=.7;world.add_child(light)
	actor=preload("res://src/player/character.gd").new();world.add_child(actor);actor.build();actor.set_process(false);actor.set_physics_process(false)
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;world.add_child(camera)
	var layer:=CanvasLayer.new();root.add_child(layer);caption=Label.new();caption.position=Vector2(12,10)
	caption.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded());caption.add_theme_font_size_override("font_size",19);caption.add_theme_color_override("font_color",Color("#554a42"));layer.add_child(caption)
	var sheet:=Image.create(1440,1440,false,Image.FORMAT_RGBA8);sheet.fill(Color("#eee9da"))
	var builds: Array=[0.0,.5,1.0];var views: Array=[0.0,PI/2,PI]
	for row in builds.size():
		for column in views.size():
			var frame: Image=await tile(builds[row],views[column])
			sheet.blit_rect(frame,Rect2i(0,0,480,480),Vector2i(column*480,row*480))
			if row==2 and column==0:check(frame.save_png("res://outputs/avatar-shoulders-fat-front.png")==OK,"final fat front render")
	check(sheet.save_png("res://outputs/avatar-shoulders-fit.png")==OK,"three body builds / real front-side-back")
	var actions: Array=["walking","rowing","planting","watering","harvesting","swimming"]
	var action_sheet:=Image.create(1440,2880,false,Image.FORMAT_RGBA8);action_sheet.fill(Color("#eee9da"))
	for row in actions.size():
		for column in views.size():
			var frame: Image=await tile(1.0,views[column],actions[row])
			action_sheet.blit_rect(frame,Rect2i(0,0,480,480),Vector2i(column*480,row*480))
	check(action_sheet.save_png("res://outputs/avatar-shoulders-actions.png")==OK,"six current actions / real front-side-back")
	actor.cancel_action("verification-finish");world.queue_free();layer.queue_free();await process_frame
	print("[avatar-shoulders] %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
