extends SceneTree
const PATH := "res://scenes/underwater/sunroom_region.tscn"
var checks := 0
var failures := 0
var scene: Node3D
var report := {}
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func serialized_pose(text: String,node_name: String) -> Transform3D:
	var pattern := RegEx.new()
	pattern.compile('\\[node name="'+node_name+'"[^\\n]*\\]\\ntransform = Transform3D\\(([^\\n]+)\\)')
	var match = pattern.search(text)
	if match == null: return Transform3D.IDENTITY
	var a := match.get_string(1).split(",")
	return Transform3D(Vector3(float(a[0]),float(a[1]),float(a[2])),Vector3(float(a[3]),float(a[4]),float(a[5])),Vector3(float(a[6]),float(a[7]),float(a[8])),Vector3(float(a[9]),float(a[10]),float(a[11])))
func bounds_of(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh_node in node.find_children("*","MeshInstance3D",true,false):
		if mesh_node.mesh == null: continue
		var box: AABB = mesh_node.global_transform*mesh_node.mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	return bounds
func shot(tag: String,position: Vector3,target: Vector3) -> void:
	var camera: Camera3D = scene.get_node("Camera")
	camera.global_position=position
	camera.look_at(target)
	camera.make_current()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"real frame "+tag)
	if image!=null and not image.is_empty():
		if tag.begins_with("far-fog-") and tag!="far-fog-north":
			# Outer terrain is fully absorbed: scan for hard colour discontinuities,
			# excluding HUD and allowing a smooth vertical water gradient.
			var worst := 0.0
			for y in range(100,image.get_height()-2,3):
				for x in range(4,image.get_width()-4,4):
					var a := image.get_pixel(x,y)
					for b in [image.get_pixel(x+2,y),image.get_pixel(x,y+2)]:
						worst=maxf(worst,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
			check(worst<0.025,"far water pixel continuity "+tag+" max="+str(worst))
			report["pixel_continuity_"+tag]=worst
		check(image.save_png("res://outputs/sunroom-underwater-"+tag+".png")==OK,"saved "+tag)
func run() -> void:
	scene=load(PATH).instantiate()
	root.add_child(scene)
	current_scene=scene
	for i in 3: await process_frame
	check(scene.scene_file_path==PATH,"new independent scene")
	var main_text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var solar_text := FileAccess.get_file_as_string("res://scenes/facilities/solar_cabin.tscn")
	var city: Node3D = scene.get_node("ExistingModels/SunkenCity")
	var base: Node3D = scene.get_node("ExistingModels/SolarCabinBase")
	var seabed = scene.get_node("ExistingModels/SunkenSeabed")
	check(city.transform.is_equal_approx(serialized_pose(main_text,"SunkenCity")),"city pose equals current hand-placed source")
	check(base.transform.is_equal_approx(serialized_pose(solar_text,"太阳能木屋-海下基座")),"base pose and scale equal source")
	check(scene.get_node("Water").transform.is_equal_approx(serialized_pose(main_text,"Water")),"water level and pose equal source")
	check(is_equal_approx(scene.water_level,1.12),"same sea level 1.12")
	check(city.get_child_count()==388,"all 388 existing city instances reused")
	var reference: Node3D = load("res://scenes/world/sunken_city.tscn").instantiate()
	var identical := true
	for instance in reference.get_children():
		var actual: Node3D = city.get_node_or_null(NodePath(instance.name))
		identical = identical and actual!=null and actual.transform.is_equal_approx(instance.transform) and actual.scene_file_path==instance.scene_file_path
	check(identical,"all source instance transforms and packed paths retained")
	reference.free()
	check(scene.city_bounds==Rect2(-120,-120,240,240),"same 240m by 240m city domain")
	check(scene.terrain_bounds==Rect2(-512,-512,1024,1024),"same full 1024m terrain coverage")
	check(seabed.data.get_region_count()==4 and seabed.vertex_spacing==2.0,"same four-region 2m terrain data")
	check(seabed.data_directory=="res://terrain/sunken_seabed","same terrain source, no regenerated heightmap")
	var minimum := INF
	var maximum := -INF
	var total := 0
	for rz in range(-1,1):
		for rx in range(-1,1):
			var region = seabed.data.get_region(Vector2i(rx,rz))
			check(region!=null,"terrain region "+str(Vector2i(rx,rz)))
			if region==null: continue
			var image: Image = region.height_map
			for y in image.get_height():
				for x in image.get_width():
					var height := image.get_pixel(x,y).r
					minimum=minf(minimum,height)
					maximum=maxf(maximum,height)
					total+=1
	check(total==262144 and is_equal_approx(minimum,-62.0),"same full seabed pixels and -62m minimum")
	check(is_equal_approx(scene.water_level-minimum,63.12),"maximum seabed depth 63.12m")
	var bbox := bounds_of(city)
	check(bbox.size.x>=239.0 and bbox.size.z>=239.0,"reused city full horizontal mesh coverage")
	var ecological: Node3D = scene.get_node("Ecology")
	check(ecological.get_node("CoralClusters").get_child_count()==32,"32 individually editable coral clusters")
	check(ecological.get_node("FacilityLights").get_child_count()==24,"24 independently editable facility lamps")
	var grounded := 0
	var largest_grounding_delta := 0.0
	for item in scene.grounding_results:
		grounded+=int(item.ok)
		largest_grounding_delta=maxf(largest_grounding_delta,absf(float(item.position[1])-float(item.expected_y)))
	check(grounded==56,"all coral and lights grounded to real surfaces")
	check(largest_grounding_delta<0.001,"serialized editor layout already matches real support, no runtime jump")
	var lamp_bounds := []
	for assembly in ecological.get_node("FacilityLights").get_children():
		lamp_bounds.append({"name":str(assembly.name),"visual_bounds":str(bounds_of(assembly.get_node("Visual"))),"light_position":str(assembly.get_node("Point").global_position)})
	var lights := 0
	var shadow_lights := 0
	for i in range(1,9):
		var lamp: Node3D = ecological.get_node("FacilityLights/LightAssembly%02d" % i)
		check(lamp.get_node("Point").position.is_equal_approx(Vector3(1.075,6.8,0)),"street light source matches original lens "+str(i))
	for light in ecological.find_children("*","Light3D",true,false):
		lights+=1
		shadow_lights+=int(light.shadow_enabled)
		check(light.light_energy>0 and light.is_visible_in_tree(),"active real lamp "+str(light.name))
	check(lights==24 and shadow_lights<=4,"real underwater lights with bounded shadow cost")
	var total_fish := 0
	var fish_changed := 0
	for school in scene.get_node("FishSchools").get_children():
		total_fish+=school.members.size()
		school.sample(0)
		var first: Transform3D = school.transforms[0]
		school.sample(2.0)
		fish_changed+=int(not first.is_equal_approx(school.transforms[0]))
		check(school.position.y<scene.water_level-2.0 and not school.ride_water,"fish live below surface "+str(school.name))
	check(total_fish==138 and fish_changed==8,"eight animated schools, 138 fish")
	check(scene.collision_runtime.stats.proxy_count>=750,"standalone region has real mesh blocking")
	check(seabed.collision_mode==3,"local seabed enables full game collision")
	var environment_main: Environment = scene.get_node("WorldEnvironment").environment
	check(not environment_main.fog_enabled and scene.has_node("Camera/WaterFogPass"),"one common depth fog composite, no double environmental fog")
	check(environment_main.fog_density==1.0 and environment_main.fog_depth_end<=110,"far scenery fully dissolves before camera culling")
	check(environment_main.sky!=null and environment_main.fog_aerial_perspective==1.0 and environment_main.fog_sun_scatter==0,"background and terminal fog share gradient sky water color")
	check(scene.get_node("Camera").far>environment_main.fog_depth_end*3,"camera clipping hidden deep in fog")
	var atmosphere = scene.get_node("Atmosphere")
	var air_stats: Dictionary = atmosphere.statistics()
	check(air_stats.bubble_instances==192 and air_stats.mote_instances==200 and air_stats.beam_instances==10,"bubbles dust and real water shafts present")
	var zero: Dictionary = atmosphere.snapshot(0.0)
	var later: Dictionary = atmosphere.snapshot(2.0)
	check(not zero.bubbles[0].transform.is_equal_approx(later.bubbles[0].transform) and later.bubbles[0].transform.origin.y>zero.bubbles[0].transform.origin.y,"bubbles actually rise")
	check(not zero.motes[0].transform.is_equal_approx(later.motes[0].transform),"motes drift")
	check(zero.rays[0].midpoint_flow!=later.rays[0].midpoint_flow,"water shaft flow animates")
	var within_water := true
	for at in [0.0,2.0,20.0,60.0]:
		for bubble in atmosphere.snapshot(at).bubbles:
			within_water=within_water and bubble.transform.origin.y<scene.water_level-0.6
	check(within_water,"bubbles fade before breaching sea level")
	check(scene.get_node("Water").material_override.shader.code.find("fog_disabled")==-1,"opaque water ceiling participates in unified depth composite")
	check(not main_text.contains("sunroom_region.tscn"),"original main scene not rewired")
	# 家园海底按 2026-11-07 要求接进潜水路由；目录里只允许出现这一处世界对齐引用，
	# 九个海域来源与其宝箱基数不得被顺带改动。
	var catalog_text := FileAccess.get_file_as_string("res://src/diving/dive_map_catalog.gd")
	check(catalog_text.count("sunroom_region.tscn")==1,"home seabed is the only catalog use of this scene")
	report={"city_bounds":str(bbox),"city_domain":str(scene.city_bounds),"terrain_domain":str(scene.terrain_bounds),"water_level":scene.water_level,"height_min":minimum,"height_max":maximum,"max_depth":scene.water_level-minimum,"city_pose":str(city.transform),"base_pose":str(base.transform),"grounding":scene.grounding_results,"lamp_bounds":lamp_bounds,"fish":total_fish,"lights":lights,"shadow_lights":shadow_lights,"max_grounding_delta":largest_grounding_delta,"blocking":scene.collision_runtime.stats,"atmosphere":air_stats,"fog":{"mode":environment_main.fog_mode,"begin":environment_main.fog_depth_begin,"end":environment_main.fog_depth_end,"curve":environment_main.fog_depth_curve,"max_intensity":environment_main.fog_density}}
	if DisplayServer.get_name()!="headless":
		await shot("overview",Vector3(115,-3,150),Vector3(0,-17,0))
		await shot("home-base",Vector3(22,-5,34),Vector3(3,-12,4))
		await shot("coral-street",Vector3(-85,-11,78),Vector3(-98,-17,64))
		await shot("fish-shoal",Vector3(7,-7.5,31),Vector3(7,-8,19))
		await shot("coral-close",Vector3(-104,-14.5,84),Vector3(-98,-17,78))
		await shot("canal-lights",Vector3(-25,-15,-12),Vector3(-45,-22,-36))
		await shot("bridge",Vector3(48,-6,48),Vector3(20,-14,15))
		await shot("outer-slope",Vector3(-150,-24,60),Vector3(-115,-24,35))
		await shot("ray-street",Vector3(-67,-11,38),Vector3(-80,-9,23))
		var shafts_on: Image = root.get_texture().get_image()
		atmosphere.get_node("LightShafts").hide()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var shafts_off := root.get_texture().get_image()
		var lit_pixels := 0
		for y in range(100,shafts_on.get_height()-5,3):
			for x in range(5,shafts_on.get_width()-5,3):
				var lit := shafts_on.get_pixel(x,y)
				var unlit := shafts_off.get_pixel(x,y)
				if lit.get_luminance()-unlit.get_luminance()>0.008: lit_pixels+=1
		check(lit_pixels>150,"real shaft on/off render has visible illuminated pixels")
		report["shaft_lit_pixel_samples"]=lit_pixels
		atmosphere.get_node("LightShafts").show()
		await shot("bubble-close",Vector3(-75,-12.5,30),Vector3(-79,-11.5,25))
		await shot("deep-layer",Vector3(-170,-26,42),Vector3(-112,-19,35))
		await shot("far-fog-north",Vector3(0,-12,-18),Vector3(0,-12,-220))
		await shot("far-fog-edge",Vector3(415,-22,415),Vector3(600,-22,600))
		await shot("far-fog-corner-close",Vector3(495,-25,495),Vector3(560,-25,560))
		await shot("far-fog-west",Vector3(-470,-18,0),Vector3(-600,-18,0))
		var environment: Environment = scene.get_node("WorldEnvironment").environment
		var ambient: float = environment.ambient_light_energy
		var sun_energy: float = scene.get_node("SunRays").light_energy
		var fill_energy: float = scene.get_node("CoolFill").light_energy
		environment.ambient_light_energy=0.24
		scene.get_node("SunRays").light_energy=0.10
		scene.get_node("CoolFill").light_energy=0.05
		var close_lamp: Node3D = ecological.get_node("FacilityLights/LightAssembly09")
		var lamp_pos := close_lamp.global_position
		await shot("facility-lights-dim",lamp_pos+Vector3(-2,1.5,4),lamp_pos+Vector3(0,0.3,0))
		var street_lamp: Node3D = ecological.get_node("FacilityLights/LightAssembly01")
		await shot("street-lamp-dim",street_lamp.global_position+Vector3(-5,4,7),street_lamp.global_position+Vector3(0,3,0))
		await shot("street-lamp-head",street_lamp.global_position+Vector3(1,5.5,4),street_lamp.global_position+Vector3(1.1,6.8,0))
		environment.ambient_light_energy=ambient
		scene.get_node("SunRays").light_energy=sun_energy
		scene.get_node("CoolFill").light_energy=fill_energy
	FileAccess.open("res://outputs/sunroom-underwater-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	scene.queue_free()
	await process_frame
	print("[sunroom-underwater] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
