extends SceneTree
## Judge the boat's own lamp by water pixels, independent of the bright hull.
var checks := 0
var failures := 0
var main
var evidence := {}
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func shot(label: String) -> Image:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://outputs/boat-navigation-"+label+".png")
	return image
func water_delta(lit: Image, dark: Image, boat_pose: Transform3D, region: Rect2) -> Dictionary:
	var sum := Vector3.ZERO
	var warm := 0
	var count := 0
	var viewport: Vector2=main.cam.get_viewport().get_visible_rect().size
	for y in range(0,lit.get_height(),3):
		for x in range(0,lit.get_width(),3):
			var screen := Vector2((x+0.5)/lit.get_width(),(y+0.5)/lit.get_height())*viewport
			var origin: Vector3=main.cam.project_ray_origin(screen)
			var direction: Vector3=main.cam.project_ray_normal(screen)
			if direction.y>=-0.001:continue
			var p: Vector3=origin+direction*((1.12-origin.y)/direction.y)
			var local: Vector3=boat_pose.affine_inverse()*p
			if not region.has_point(Vector2(local.x,local.z)):continue
			var delta:=lit.get_pixel(x,y)-dark.get_pixel(x,y)
			sum+=Vector3(delta.r,delta.g,delta.b);count+=1
			if delta.r>0.04 and delta.r>delta.b*1.5:warm+=1
	return {"samples":count,"r":sum.x/maxi(count,1),"g":sum.y/maxi(count,1),"b":sum.z/maxi(count,1),"warm_fraction":float(warm)/maxi(count,1)}
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("FAIL real renderer required");quit(1);return
	preload("res://tools/lighting_capture_profile.gd").prepare()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.world_clock.paused=true;main.weather_service.paused=true
	main.process_mode=Node.PROCESS_MODE_DISABLED
	main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide();main.get_node("Birds").hide()
	if main.start_screen!=null:main.start_screen.hide()
	main.cam.follow_enabled=false
	main.boat.place_at(Vector3(26,1.12,25),0.0)
	main.cam.target=main.boat.global_position+Vector3.UP*0.4;main.cam.distance=18.0
	main.cam.orbit_dir=Vector3(-0.6,0.75,0.8);main.cam.refresh()
	var rig=main.daylight_rig
	var lamp: Light3D=main.boat.get_node("Model/BoatLamp")
	var energy: float=rig._boat_lights[0].energy
	check(rig._boat_lights.size()==1,"one physical navigation lantern")
	check(lamp.shadow_enabled,"boat and surrounding objects can occlude the real lamp")
	var pose: Transform3D=main.boat.global_transform
	for scheme in ["original","absorption"]:
		main.water_node.use_scheme(scheme);rig._boat_lights[0].energy=energy;rig.apply(21.0)
		var lit:=await shot(scheme+"-on")
		rig._boat_lights[0].energy=0.0;rig.apply(21.0)
		var off:=await shot(scheme+"-off")
		var near:=water_delta(lit,off,pose,Rect2(-4.0,-3.4,2.3,4.0))
		var far:=water_delta(lit,off,pose,Rect2(-9.0,-3.4,2.0,4.0))
		var opposite:=water_delta(lit,off,pose,Rect2(1.7,-3.4,2.3,4.0))
		check(near.samples>100,"visible water sampled outside port gunwale "+scheme)
		check(near.r>0.04 and near.g>0.012,"clear warm illumination on nearby sea "+scheme)
		check(near.r>near.b*1.5 and near.warm_fraction>0.25,"warm water pool is broad and distinct "+scheme)
		check(far.r<near.r*0.35,"light fades beyond the boat "+scheme)
		check(opposite.r<near.r*0.7,"hull and distance limit light on opposite side "+scheme)
		evidence[scheme]={"near":near,"far":far,"opposite":opposite}
		if scheme=="original":
			rig._boat_lights[0].energy=energy
			main.boat.place_at(Vector3(35,1.12,31),PI*0.5);rig.apply(21.0)
			var moved:=await shot("moved")
			var old_pool:=water_delta(moved,off,pose,Rect2(-4.0,-3.4,2.3,4.0))
			check(old_pool.r<near.r*0.25,"water light leaves the old position when the boat moves")
			evidence.old_pool_after_move=old_pool
			main.cam.target=main.boat.global_position+Vector3.UP*0.4;main.cam.refresh()
			await shot("turned-follow")
			main.boat.place_at(Vector3(26,1.12,25),0.0)
			main.cam.target=main.boat.global_position+Vector3.UP*0.4;main.cam.refresh()
	rig._boat_lights[0].energy=energy
	for hour in [9.0,13.0,17.0]:
		rig.apply(hour);check(lamp.light_energy==0.0,"navigation light off in approved daylight "+str(hour))
	check(main.boat.get_node("Model/BowLantern").instance_id=="boat/furnishing/bow_lantern","stable lantern identity retained")
	evidence.lamp={"local_position":str(lamp.position),"energy":energy,"range":lamp.get("spot_range"),"color":str(lamp.light_color)}
	var file:=FileAccess.open("res://outputs/boat-navigation-lamp.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[boat-navigation-lamp] %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
