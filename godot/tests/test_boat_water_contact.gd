extends SceneTree
## Exercise real hull geometry, blade immersion, both water materials and native frames.
var main
var checks := 0
var failures := 0
var evidence := {}
var clock := 0.0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func tick(dt: float, move := false) -> void:
	clock+=dt
	main.water_node.time=clock
	if move:main.boat.position.z-=dt*1.8
	main.boat._animate_oars(dt)
	main.water_node.update_surface(clock,main.boat,main.cam.target)
func shot(label: String) -> Image:
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.save_png("res://outputs/boat-water-"+label+".png")
	return image
func changed(a: Image,b: Image) -> int:
	var count := 0
	for y in range(0,a.get_height(),2):
		for x in range(0,a.get_width(),2):
			var d:=a.get_pixel(x,y)-b.get_pixel(x,y)
			if maxf(absf(d.r),maxf(absf(d.g),absf(d.b)))>.035:count+=1
	return count
func run() -> void:
	var visual:=DisplayServer.get_name()!="headless"
	if visual:preload("res://tools/lighting_capture_profile.gd").prepare()
	# 挂点是隐形契约：桨叶 GLB 换了形状，这里先失败，不让水纹静默漂到旧位置。
	var oar_pack: Node3D=load("res://scenes/components/reference_skiff/oar.tscn").instantiate()
	var blade: MeshInstance3D=null
	for m in oar_pack.find_children("*","MeshInstance3D",true,false):
		var piece := m as MeshInstance3D
		if piece.mesh!=null and piece.mesh.get_aabb().size.x>1.0 and piece.mesh.get_aabb().size.z>0.3:blade=piece
	var marker: Marker3D=oar_pack.get_node_or_null("BladeContact") as Marker3D
	check(blade!=null and marker!=null,"authored blade and contact marker exist")
	if blade!=null and marker!=null:
		var blade_box: AABB=blade.mesh.get_aabb()
		check(is_equal_approx(marker.position.x,blade_box.end.x) and is_equal_approx(marker.position.y,blade_box.position.y),"blade contact marker pinned to authored blade tip")
	oar_pack.free()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.process_mode=Node.PROCESS_MODE_DISABLED
	main.boat.set_process(false);main.cam.set_process(false);main.cam.follow_enabled=false
	main.boat.place_at(Vector3(26,1.12,25),0.0);main.boat.model.transform=Transform3D.IDENTITY
	var surface=main.water_node
	var waves: float=surface.wave_scale
	surface.wave_scale=0.0
	main.boat._sailing=false;tick(.1)
	var contact=surface.boat_contact
	check(contact.outline.size()>=8 and contact.outline.size()<=24,"waterline sliced from real hull with bounded contour")
	var width:=0.0
	for p in contact.outline:width=maxf(width,absf(p.x))
	check(width>.55 and width<1.29,"draft contour follows immersed hull, excludes gunwale/oars/motor")
	check(contact.touch_count==0,"no blade splash while boat is idle")
	var old: Vector4=contact.world_outline[0]
	main.boat.position.x+=5.0;main.boat.rotation.y=PI*.5;tick(.1)
	check(contact.world_outline[0].distance_to(old)>3.0,"hull contact translates and rotates with vessel")
	main.boat.place_at(Vector3(26,1.12,25),0.0)
	main.boat._sailing=true;main.boat._vel=main.boat.cruise_speed();main.boat._speed_actual=1.8
	for i in 240:tick(1.0/60.0)
	check(contact.touch_count>=6 and contact.touch_count<=12,"blade entry emits once per side per stroke")
	var sides := [false,false]
	for touch in contact.last_touches:
		sides[int(touch.side)]=true
		check(touch.position.y<=touch.surface_y+.016,"splash happens at real water entry")
		check(absf(touch.position.x-main.boat.position.x)>3.0,"splash follows authored blade, replaces old fixed 2.6m offset")
	check(sides[0] and sides[1],"both oars create water contact")
	var before: int=contact.touch_count
	main.boat._sailing=false;main.boat._vel=0;main.boat._speed_actual=0
	for i in 240:tick(1.0/60.0)
	check(contact.touch_count==before,"stopping creates no new blade splashes")
	for rp in surface._ripples:check(clock-rp.z>3.2,"old rings expire in world space after stopping")
	surface.wave_scale=waves
	if visual:
		main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide();main.get_node("Birds").hide();main.player.hide()
		if main.start_screen!=null:main.start_screen.hide()
		main.cam.distance=16;main.cam.orbit_dir=Vector3(-.65,1.15,.8)
		for scheme in ["original","absorption"]:
			check(surface.use_scheme(scheme),"switch water "+scheme)
			main.boat.place_at(Vector3(26,1.12,25),0);main.cam.target=main.boat.position+Vector3.UP*.3;main.cam.refresh()
			main.daylight_rig.apply(9.0);tick(.05)
			var mat: ShaderMaterial=surface.current_material()
			check(int(mat.get_shader_parameter("boat_hull_count"))==contact.outline.size(),"fresh contour reaches newly selected water "+scheme)
			var on:=await shot(scheme+"-idle-on")
			mat.set_shader_parameter("boat_contact_strength",0.0)
			var off:=await shot(scheme+"-idle-off")
			var hull_pixels:=changed(on,off)
			check(hull_pixels>60,"stationary draft visibly disturbs sea "+scheme)
			mat.set_shader_parameter("boat_contact_strength",1.0)
			main.boat._sailing=true;main.boat._vel=main.boat.cruise_speed();main.boat._speed_actual=1.8
			var start: int=contact.touch_count
			for i in 100:
				tick(1.0/60.0,true)
				if contact.touch_count>start:break
			for i in 20:tick(1.0/60.0,true)
			main.cam.target=main.boat.position+Vector3.UP*.3;main.cam.refresh()
			var rowing:=await shot(scheme+"-rowing-on")
			mat.set_shader_parameter("boat_oar_strength",0.0)
			var no_oars:=await shot(scheme+"-rowing-off")
			var oar_pixels:=changed(rowing,no_oars)
			check(oar_pixels>25,"blade entry rings visible outside hull "+scheme)
			mat.set_shader_parameter("boat_oar_strength",1.0)
			for i in 28:tick(1.0/60.0,true)
			main.cam.target=main.boat.position+Vector3.UP*.3;main.cam.refresh();await shot(scheme+"-rowing-spread")
			# Close pass over one blade: the splash has to read as a rowed stroke
			# at the distance the player actually watches it, not only in a
			# whole-boat wide shot.
			var blade_at: Vector3=contact.last_touches[-1].position
			main.cam.target=Vector3(blade_at.x,main.boat.position.y,blade_at.z)
			main.cam.distance=7.0;main.cam.refresh();tick(.05)
			var close_on:=await shot(scheme+"-blade-close")
			mat.set_shader_parameter("boat_oar_strength",0.0)
			var close_off:=await shot(scheme+"-blade-close-off")
			check(changed(close_on,close_off)>120,"blade splash holds up at player distance "+scheme)
			mat.set_shader_parameter("boat_oar_strength",1.0)
			main.cam.distance=16;main.cam.orbit_dir=Vector3(-.65,1.15,.8)
			main.boat._sailing=false;main.boat._vel=0;main.boat._speed_actual=0
			for i in 210:tick(1.0/60.0)
			var stopped:=await shot(scheme+"-stopped")
			mat.set_shader_parameter("boat_oar_strength",0.0)
			var expired:=await shot(scheme+"-expired-off")
			check(changed(stopped,expired)<4,"stopped blade rings disappear "+scheme)
			mat.set_shader_parameter("boat_oar_strength",1.0)
			main.daylight_rig.apply(21.0);tick(.05);await shot(scheme+"-night")
			evidence[scheme]={"hull_changed_samples":hull_pixels,"oar_changed_samples":oar_pixels}
		surface.use_scheme("original");main.daylight_rig.apply(9.0)
		var landing: Dictionary=main._current_landing().data()
		main.boat.place_at(Vector3(landing.boatPark[0],1.12,landing.boatPark[2]),float(landing.boatYaw))
		main.cam.target=main.boat.position+Vector3(0,.5,-2);main.cam.distance=27;main.cam.refresh();tick(.05);await shot("docked")
	evidence.checks=checks;evidence.failures=failures;evidence.hull_points=contact.outline.size();evidence.blade_touches=contact.touch_count
	evidence.expected_faults=[];evidence.unexecuted=["mobile device/GPU performance","manual gamepad sailing"]
	var f:=FileAccess.open("res://outputs/boat-water-contact.json",FileAccess.WRITE);f.store_string(JSON.stringify(evidence,"\t"));f.close()
	main.queue_free();await process_frame
	print("[boat-water-contact] %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
