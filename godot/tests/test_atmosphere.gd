extends SceneTree
## Visual contracts: readable blue water, warm moving boat light, sunrise/daylight.
var checks := 0
var failures := 0
var main
var evidence := {}
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func shot(label: String) -> Image:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://outputs/atmosphere-"+label+".png")
	return img
func stats(img: Image, rect: Rect2i) -> Dictionary:
	var sum := Vector3.ZERO
	var lum := 0.0
	var square := 0.0
	var n := 0
	for y in range(rect.position.y,rect.end.y,2):
		for x in range(rect.position.x,rect.end.x,2):
			var c := img.get_pixel(x,y)
			sum += Vector3(c.r,c.g,c.b)
			lum += c.get_luminance(); square += c.get_luminance()*c.get_luminance(); n += 1
	return {"rgb":str(sum/n),"r":sum.x/n,"b":sum.z/n,"lum":lum/n,"std":sqrt(maxf(0.0,square/n-pow(lum/n,2.0)))}
func depth_probe(scheme: String) -> void:
	main.water_node.use_scheme(scheme);main.daylight_rig.apply(21.0)
	main.boat.hide()
	main.cam.target=Vector3(48,0.6,40);main.cam.distance=32.0;main.cam.refresh()
	var fixture:=Node3D.new();root.add_child(fixture)
	var markers: Array[MeshInstance3D]=[]
	for data in [[-3.0,0.6],[3.0,5.0]]:
		var marker:=MeshInstance3D.new()
		var box:=BoxMesh.new();box.size=Vector3(1.8,0.3,1.8);marker.mesh=box
		marker.position=Vector3(48.0+data[0],1.12-data[1]-0.15,40.0)
		var material:=StandardMaterial3D.new();material.albedo_color=Color(0.9,0.55,0.2);material.roughness=0.8
		marker.material_override=material;fixture.add_child(marker);markers.append(marker)
	var lamp:=OmniLight3D.new();lamp.position=Vector3(48,5,40);lamp.light_energy=8.0;lamp.omni_range=24.0
	fixture.add_child(lamp)
	var covered:=await shot("depth-"+scheme+"-covered")
	# Keep the geometry/depth buffer fixed; only switch its reflectance. Hiding
	# it would also change water opacity and contaminate the transmission delta.
	for marker in markers:marker.material_override.albedo_color=Color.BLACK
	var water_background:=await shot("depth-"+scheme+"-water-background")
	main.water_node.hide()
	for marker in markers:marker.material_override.albedo_color=Color(0.9,0.55,0.2)
	var bare:=await shot("depth-"+scheme+"-bare")
	for marker in markers:marker.material_override.albedo_color=Color.BLACK
	var bare_background:=await shot("depth-"+scheme+"-bare-background")
	var ratios:=[]
	for index in markers.size():
		# Locate the rendered fixture itself. The viewport can have a different
		# content scale from the window coordinates used by unproject_position.
		var center:=Vector2.ZERO
		var count:=0
		var x0:=0 if index==0 else bare.get_width()/2
		var x1:=bare.get_width()/2 if index==0 else bare.get_width()
		for y in range(0,bare.get_height(),2):
			for x in range(x0,x1,2):
				var pixel:=bare.get_pixel(x,y)
				if pixel.r>0.4 and pixel.r>pixel.b+0.12:
					center+=Vector2(x,y);count+=1
		check(count>30,"depth fixture pixels found "+scheme)
		var point: Vector2=center/maxi(count,1)
		var rect:=Rect2i(Vector2i(point)-Vector2i(7,7),Vector2i(14,14))
		var surface_contrast: float=stats(covered,rect).r-stats(water_background,rect).r
		var bare_contrast: float=stats(bare,rect).r-stats(bare_background,rect).r
		check(bare_contrast>0.05,"underwater depth fixture is visibly lit "+scheme)
		ratios.append(surface_contrast/maxf(bare_contrast,0.001))
	check(ratios[0]>0.20,"night shallow water transmits the submerged object "+scheme)
	check(ratios[0]>ratios[1]+0.12,"night transmission decreases with actual water depth "+scheme)
	evidence["depth_"+scheme]={"shallow_0_6m":ratios[0],"deep_5m":ratios[1]}
	fixture.queue_free();await process_frame
	main.water_node.show();main.boat.show()
func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("FAIL atmosphere requires a real renderer");quit(1);return
	preload("res://tools/lighting_capture_profile.gd").prepare()
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false;main.world_clock.paused=true;main.weather_service.paused=true
	main.process_mode=Node.PROCESS_MODE_DISABLED
	main.cam.follow_enabled=false
	main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide();main.get_node("Birds").hide()
	if main.start_screen!=null:main.start_screen.hide()
	main.cam.target=Vector3(2.4,2.6,7.2);main.cam.distance=42.0
	main.cam.orbit_dir=Vector3(-0.6,0.75,0.8);main.cam.refresh()
	var rig=main.daylight_rig
	check(rig._home_lights.size()==3,"home lamps retained")
	check(rig._boat_lights.size()==1,"one bow lantern captured by sole lighting writer")
	var day_water := {}
	for pair in [["dawn",6.0],["morning",9.0],["noon",12.0],["afternoon",15.0],["sunset",18.0],["night",21.0],["midnight",0.0]]:
		rig.apply(pair[1])
		var img:=await shot(pair[0])
		var water:=stats(img,Rect2i(920,70,300,160))
		evidence[pair[0]]=water
		if pair[0]=="morning":day_water=water
		if pair[0]=="night":
			check(water.lum>0.025 and water.lum<day_water.lum*0.8,"night sea remains visible and darker than day")
			check(water.b>water.r*1.5,"night sea is blue")
			check(water.std>0.002,"night sea retains visible wave variation")
			check(main.get_node("World/Lights/Sun").light_energy==0.0,"night has no sunlight")
		if pair[0]=="dawn":check(rig.sun_angles().x<8.0,"06:00 sunrise stays near horizon")
		if pair[0]=="afternoon":check(main.get_node("World/Lights/Sun").light_energy>0.45,"afternoon keeps morning-strength sunshine")
	# Controlled on/off comparison, beyond the home's lamp ranges.
	main.boat.place_at(Vector3(26,1.12,25),0.0)
	main.cam.target=main.boat.global_position+Vector3.UP*0.5;main.cam.distance=16.0;main.cam.refresh()
	rig.apply(21.0)
	var on:=await shot("boat-lamp-on")
	var lamp: Light3D=main.boat.get_node("Model/BoatLamp")
	var original_energy: float=rig._boat_lights[0].energy
	check(lamp.light_energy>0.0,"bow lamp lights at night")
	rig._boat_lights[0].energy=0.0;rig.apply(21.0)
	var off:=await shot("boat-lamp-off")
	var boat_rect:=Rect2()
	var found:=false
	for visual in main.boat.model.find_children("*","VisualInstance3D",true,false):
		if visual is Light3D:continue
		var box: AABB=visual.global_transform*visual.get_aabb()
		for i in 8:
			var point: Vector2=main.cam.unproject_position(box.get_endpoint(i))
			if not found:boat_rect=Rect2(point,Vector2.ZERO);found=true
			else:boat_rect=boat_rect.expand(point)
	var warm_pixels:=0
	var water_pixels:=0
	for y in range(0,on.get_height(),2):
		for x in range(0,on.get_width(),2):
			var delta:=on.get_pixel(x,y)-off.get_pixel(x,y)
			if delta.r>0.018 and delta.r>delta.b*1.15:
				warm_pixels+=1
				if not boat_rect.grow(5.0).has_point(Vector2(x,y)):water_pixels+=1
	check(warm_pixels>30,"bow lamp visibly illuminates boat and surroundings")
	check(water_pixels>15,"bow lamp leaves a warm reflection on the sea outside the hull")
	evidence.boat={"warm_pixels":warm_pixels,"reflection_pixels":water_pixels,"bounds":str(boat_rect)}
	# This light is not registered with DaylightRig. Only Godot's real lighting
	# can respond to its color, position and visibility; no rig.apply call follows.
	var native := OmniLight3D.new()
	var screen:=Vector2(1050,180)
	var ray_origin: Vector3=main.cam.project_ray_origin(screen)
	var ray_dir: Vector3=main.cam.project_ray_normal(screen)
	var target: Vector3=ray_origin+ray_dir*((1.12-ray_origin.y)/ray_dir.y)
	native.position=target+Vector3.UP*2.0
	native.omni_range=7.0;native.light_energy=3.0;native.light_color=Color(1.0,0.35,0.08)
	root.add_child(native)
	var lit:=await shot("native-light-on")
	var rect:=Rect2i(Vector2i(screen)-Vector2i(22,22),Vector2i(44,44)).intersection(Rect2i(0,0,lit.get_width(),lit.get_height()))
	var area_before:=stats(off,rect)
	var area_lit:=stats(lit,rect)
	check(area_lit.r>area_before.r+0.02,"unregistered real light directly illuminates water")
	check(area_lit.r-area_before.r>area_lit.b-area_before.b,"water responds to the actual lamp color")
	native.position+=Vector3(-9.0,0.0,0.0)
	var moved:=await shot("native-light-moved")
	var area_moved:=stats(moved,rect)
	check(area_moved.r<area_lit.r-0.015,"moving the actual light removes its old water highlight")
	native.queue_free();await process_frame
	# With every actual light and ambient source off, the water must go dark.
	for entry in rig._fill_lights+rig._home_lights+rig._boat_lights:entry.node.light_energy=0.0
	rig._water_moon.light_energy=0.0
	var environment: Environment=main.get_node("World/WorldEnvironment").environment
	environment.ambient_light_energy=0.0;environment.background_energy_multiplier=0.0
	var black:=await shot("all-lights-off")
	var black_stats:=stats(black,Rect2i(920,70,300,160))
	check(black_stats.lum<0.015,"without light the sea does not glow by itself")
	evidence.native_light={"before":area_before,"on":area_lit,"moved":area_moved,"all_lights_off":black_stats}
	rig._boat_lights[0].energy=original_energy
	# Every water scheme must retain the night floor and the same lamp source.
	main.cam.target=Vector3(2.4,2.6,7.2);main.cam.distance=42.0;main.cam.refresh()
	main.water_node.use_scheme("absorption");rig.apply(21.0)
	var alternate:=await shot("night-absorption")
	var alt_stats:=stats(alternate,Rect2i(920,70,300,160))
	check(alt_stats.lum>0.025 and alt_stats.std>0.002,"absorption scheme also has readable night waves")
	check(rig._water_moon.light_energy>0.0,"absorption water receives the same real moonlight")
	evidence.absorption=alt_stats
	await depth_probe("original")
	await depth_probe("absorption")
	var offsets: Dictionary=rig.offsets_snapshot()
	var game_weather: String=main.weather_service.kind
	for season in ["spring","summer","autumn","winter"]:
		for weather in ["clear","cloudy","rain"]:
			for hour in [6.0,15.0,21.0]:
				rig.set_preview(hour,season,weather)
				var sun: DirectionalLight3D=main.get_node("World/Lights/Sun")
				var env: Environment=main.get_node("World/WorldEnvironment").environment
				check(is_finite(sun.light_energy) and sun.light_energy>=0.0 and env.ambient_light_energy>=0.0,
					"season/weather preset remains valid %s/%s/%s" % [season,weather,hour])
	rig.clear_preview()
	check(rig.offsets_snapshot()==offsets,"all saved season/weather/daypart offsets remain intact")
	check(main.weather_service.kind==game_weather,"lighting previews never change actual weather")
	main.water_node.use_scheme("original");rig.apply(9.0)
	check(lamp.light_energy==0.0,"bow lantern fades out by morning")
	var file:=FileAccess.open("res://outputs/atmosphere.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[atmosphere] %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
