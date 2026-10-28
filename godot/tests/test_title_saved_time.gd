extends SceneTree
## Cold boot real saved times, hold their lighting through the actual GUI entry,
## and verify the translated composition at three window sizes.
var checks:=0
var failures:=0
var main
var evidence: Dictionary={}
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func lighting() -> Dictionary:
	var sun: DirectionalLight3D=main.get_node("World/Lights/Sun")
	var env: Environment=main.world_env.environment
	var water: ShaderMaterial=main._active_water_mat()
	var result: Dictionary={"sun":sun.light_energy,"sun_color":sun.light_color,"sun_basis":sun.global_basis,
		"ambient":env.ambient_light_energy,"sky":env.background_energy_multiplier,"contrast":env.adjustment_contrast,
		"water_shallow":water.get_shader_parameter("body_shallow"),"water_deep":water.get_shader_parameter("body_deep"),
		"water_sun":water.get_shader_parameter("sun_highlight_strength")}
	for i in main.daylight_rig._home_lights.size():result["home_lamp_"+str(i)]=main.daylight_rig._home_lights[i].node.light_energy
	return result
func shot(label: String) -> void:
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/title-"+label+".png")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("FAIL title saved-time requires real renderer");quit(1);return
	var variant:="night"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--title-fixture="):variant=arg.trim_prefix("--title-fixture=")
	var saved=preload("res://src/save/save_game.gd")
	var fixture:="user://title-clock-"+variant+".json"
	var expected: Dictionary=saved.read(fixture)
	check(expected.get("ok",false),"valid seeded "+variant+" save exists")
	if not expected.get("ok",false):quit(1);return
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(fixture),ProjectSettings.globalize_path(saved.SLOT_PATH))==OK,"stage default slot in isolated user directory")
	preload("res://tools/lighting_capture_profile.gd").prepare()
	root.content_scale_size=Vector2i(1600,1000)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false
	var clock: Dictionary=main.world_clock.to_dict()
	check(main._title_active and main.start_screen!=null,"cold boot shows start screen")
	var saved_clock: Dictionary=expected.snapshot.time
	check(int(clock.day)==int(saved_clock.day) and float(clock.seconds)==float(saved_clock.seconds)
		and float(clock.day_length)==float(saved_clock.day_length),"cold boot restores saved day and exact clock")
	check(is_equal_approx(main.daylight_rig.hour(),clock.seconds/3600.0),"first title frame uses saved lighting time")
	var title_light:=lighting()
	await create_timer(2.1).timeout
	check(main.world_clock.to_dict()==clock,"title does not advance saved time")
	check(lighting()==title_light,"revealing the title does not replace saved lighting")
	var old:=Camera3D.new();old.keep_aspect=Camera3D.KEEP_HEIGHT;old.fov=31.0;root.add_child(old)
	var direction:=Vector3(-0.50,0.53,0.69).normalized()
	var right:=Vector3.UP.cross(direction).normalized()
	var old_target:=Vector3(0.5,6.8,4.0)+right*12.0
	old.position=old_target+direction*64.0;old.look_at(old_target)
	check(main.cam.global_basis.is_equal_approx(old.global_basis),"title viewing angle is unchanged")
	check(is_equal_approx(main.cam.fov,old.fov),"title lens remains unchanged")
	for extent in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=extent
		for i in 4:await process_frame
		main.start_screen._layout()
		var view: Vector2=root.get_visible_rect().size
		var old_house: Vector2=old.unproject_position(Vector3(5,5,6))
		var house: Vector2=main.cam.unproject_position(Vector3(5,5,6))
		check(absf(house.x-old_house.x)<0.2,"horizontal composition retained "+str(extent))
		check(house.y<old_house.y-view.y*0.07,"house moved up in frame "+str(extent))
		var button: Button=main.start_screen.start_button
		var bounds: Rect2=button.get_global_rect()
		check(root.get_visible_rect().encloses(bounds),"start button stays inside viewport "+str(extent))
		check(bounds.get_center().x>view.x*0.82,"start text moved right into clear water "+str(extent))
		await shot(variant+"-%dx%d" % [extent.x,extent.y])
	old.queue_free();await process_frame
	# Freeze only for the transition comparison; the title itself already proved
	# it freezes a normally running clock without changing its paused flag.
	main.world_clock.paused=true
	var button: Button=main.start_screen.start_button
	var point: Vector2=button.get_global_transform_with_canvas()*(button.size*0.5)
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=point;click.pressed=pressed
		root.push_input(click,true);await process_frame
	var continuous:=true
	for i in 130:
		await process_frame
		continuous=continuous and lighting()==title_light
		if not main._title_active:break
	check(not main._title_active and main.start_screen==null,"actual start click completes the camera transition")
	check(continuous and lighting()==title_light,"sun, sea and house lights stay identical through entry")
	check(main.world_clock.to_dict()==clock,"transition preserves restored save time")
	check(main.hud.visible and main.cam.process_mode!=Node.PROCESS_MODE_DISABLED,"game camera and HUD resume")
	await shot(variant+"-entered")
	main.world_clock.paused=false
	await create_timer(0.15).timeout
	check(main.world_clock.seconds>float(clock.seconds),"clock resumes after entry")
	evidence={"variant":variant,"time":clock,"sun":title_light.sun,"ambient":title_light.ambient,"sky":title_light.sky,"continuous":continuous}
	var file:=FileAccess.open("res://outputs/title-"+variant+".json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[title-saved] %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
