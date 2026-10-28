extends SceneTree
## Real renderer regression: dock box, native P input, warm home lamps and boat pixels.
var checks := 0
var failures := 0
var main
var evidence := {"frames":[],"boat":{}}

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func bounds(node: Node) -> AABB:
	var box := AABB()
	var found := false
	for visual in node.find_children("*","VisualInstance3D",true,false):
		if visual is Light3D:continue
		var part: AABB=visual.global_transform*visual.get_aabb()
		box=box.merge(part) if found else part
		found=true
	return box

func key(code: int) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code;event.pressed=pressed
		root.push_input(event,true)
		await process_frame
	for i in 3:await process_frame

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		root.push_input(event,true)
		await process_frame
	await create_timer(0.28).timeout

func snapshot(label: String) -> Image:
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	var result: Image=root.get_texture().get_image()
	result.save_png("res://outputs/home-"+label+".png")
	return result

func projected_rect(box: AABB) -> Rect2:
	var rect:=Rect2(main.cam.unproject_position(box.position),Vector2.ZERO)
	for i in 8:rect=rect.expand(main.cam.unproject_position(box.get_endpoint(i)))
	return rect

func mean_color(img: Image, area: Rect2) -> Color:
	var rect: Rect2i=Rect2i(area).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	var sum:=Vector3.ZERO
	var n:=0
	for y in range(rect.position.y,rect.end.y,2):
		for x in range(rect.position.x,rect.end.x,2):
			var c:=img.get_pixel(x,y)
			sum+=Vector3(c.r,c.g,c.b);n+=1
	return Color(sum.x/maxi(n,1),sum.y/maxi(n,1),sum.z/maxi(n,1))

func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("FAIL home-lighting requires a real renderer and GUI input")
		quit(1);return
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false;main.set_process(false)
	main.world_clock.paused=true;main.weather_service.paused=true
	main.cam.set_process(false);main.cam.follow_enabled=false
	main.boat.set_process(false)
	for i in 6:await process_frame
	# Native viewport input exercises both the tool and the modal switch route.
	await key(KEY_P)
	check(main.grade.visible,"P opens the debug panel in minimum scope")
	check(not main.hud._backdrop.visible,"P leaves scene colors untouched")
	await snapshot("debug-p")
	await key(KEY_P)
	check(not main.grade.visible,"P closes the debug panel")
	await key(KEY_B)
	check(main.hud.is_panel_open(),"B opens pocket before switching tools")
	await key(KEY_P)
	check(main.grade.visible and not main.hud.is_panel_open(),"P switches from pocket to debug panel")
	await key(KEY_ESCAPE)
	check(not main.grade.visible and not main.hud.menu.active,"Esc closes P without opening pause menu")
	var base: float=main.daylight_rig.base_of("sun","light_energy")
	main.grade._slot="morning"
	main.grade._light_write("sun_energy",base*0.8)
	main.daylight_rig.apply(9.0)
	check(is_equal_approx(main.get_node("World/Lights/Sun").light_energy,base*0.8),"P lighting controls edit the selected daypart")
	check(is_equal_approx(float(main.grade._light_read("sun_energy")),base),"P no longer moves the authored baseline")
	main.daylight_rig.apply(19.0)
	check(is_equal_approx(float(main.grade._light_scene_read("sun_energy")),0.0),"P reads what the night actually renders")
	check(main.get_node("World/Lights/Sun").light_energy==0.0,"editing one daypart never restores sunlight at night")
	check(main.daylight_rig.offset_count("spring","clear","night")==0,"the morning edit does not leak into the night daypart")
	main.daylight_rig.apply(9.0)
	check(is_equal_approx(main.get_node("World/Lights/Sun").light_energy,base*0.8),"P edit survives a night and morning cycle")
	main.grade._light_write("sun_energy",base)
	main.daylight_rig.apply(9.0)
	var cabin=main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋")
	var box=main._zone_nodes.zone1.get_node("Objects/ShippingBox")
	var visual=box.get_node_or_null("Visual")
	check(visual!=null and visual.is_visible_in_tree(),"functional dock box owns a visible PackedScene")
	if visual==null:main.queue_free();quit(1);return
	var box_bounds:=bounds(visual)
	check(visual.asset_id=="SEA-SCENE-SBR-COOLER","shipping box retains its stable asset")
	check(absf(box_bounds.position.y-box.global_position.y)<0.003,"box bottom rests on dock, never floats or sinks")
	check(Vector2(box_bounds.get_center().x,box_bounds.get_center().z).distance_to(Vector2(box.global_position.x,box.global_position.z))<0.1,"box geometry and interaction share an anchor")
	check(main._zone_nodes.zone1.landing_point("main").ground().contains_world(box.global_position.x,box.global_position.z),"box is on the accessible dock")
	var old_coolers:=0
	for node in cabin.find_children("*","MultiMeshInstance3D",true,false):
		if node.get_meta("asset_component","")=="cooler":old_coolers+=1
	check(old_coolers==0,"old cabin cooler retired without duplicate models")
	evidence.box={"position":str(box.global_position),"bounds":str(box_bounds),"asset_id":visual.asset_id}
	main.cam.target=Vector3(2.4,2.6,7.2);main.cam.distance=54
	main.cam.orbit_dir=Vector3(-.6,.75,.8);main.cam.refresh()
	var screen: Vector2=main.cam.unproject_position(box_bounds.get_center())
	check(root.get_visible_rect().has_point(screen),"box is inside the review camera")
	var hit: Dictionary=main.hover._pick(screen)
	check(hit.get("node")==box,"visible box body picks its shipping interaction")
	await click(screen)
	check(main.hud.world_actions.is_open(),"actual box click opens world actions")
	await snapshot("box-actions")
	main.hud.world_actions.close(true)
	main.hud.hide();main.markers.hide();main.ribbon.hide();main._calendar_label.hide()
	check(main.daylight_rig._home_lights.size()==3,"three authored home lantern lights captured")
	var last_energy:=0.0
	for hour in [9.0,18.5,19.0,0.0,6.0,7.0]:
		main.daylight_rig.apply(hour)
		var energy:=0.0
		for lamp in main.daylight_rig._home_lights:energy+=lamp.node.light_energy
		if hour in [9.0,7.0]:check(energy==0.0,"home lamps turn off in daylight %s" % hour)
		if hour==18.5:check(energy>0.0,"lamps fade on at dusk")
		if hour==19.0:check(energy>last_energy,"lamps reach night strength")
		if hour in [19.0,0.0]:
			check(energy>0.0,"night home remains lit %s" % hour)
			check(main.get_node("World/Lights/Sun").light_energy==0.0 and main.get_node("World/WorldEnvironment").environment.ambient_light_energy>0.0,"warm local lamps coexist with readable blue night")
		if hour==6.0:check(energy>0.0 and energy<last_energy,"lamps fade out through dawn")
		last_energy=energy
		evidence.frames.append({"hour":hour,"lamp_energy":energy})
		if hour in [9.0,19.0]:await snapshot("day" if hour==9.0 else "night")
	# All details react to the same real lights. Pixel comparisons use one fixed
	# camera and no room lamp in range, then add one controlled local test light.
	for mat in main.boat._mats:
		check(not mat.shader.resource_path.get_file().begins_with("unlit"),"boat detail receives scene lights")
		check(is_zero_approx(float(mat.get_shader_parameter("ambient_boost"))),"boat has no emissive fill")
	main.boat.place_at(Vector3(25,1.12,25),0.0)
	main.cam.target=main.boat.global_position+Vector3.UP*0.6;main.cam.distance=14;main.cam.refresh()
	var boat_box:=bounds(main.boat.model)
	var boat_rect:=projected_rect(boat_box)
	check(root.get_visible_rect().encloses(boat_rect),"whole boat stays inside close review camera")
	main.daylight_rig.apply(9.0)
	var day_image:=await snapshot("boat-day")
	var day:=mean_color(day_image,boat_rect)
	var bow_energy: float=main.daylight_rig._boat_lights[0].energy
	main.daylight_rig._boat_lights[0].energy=0.0
	main.daylight_rig.apply(19.0)
	var dark_image:=await snapshot("boat-dark")
	var dark:=mean_color(dark_image,boat_rect)
	check(day.get_luminance()>0.06,"daylight boat is visible")
	check(dark.get_luminance()<day.get_luminance()*0.4,"boat is dimmer in moonlight without a local lamp")
	var probe:=OmniLight3D.new()
	probe.position=main.boat.global_position+Vector3(-1.5,3.5,1.5)
	probe.omni_range=7.0;probe.light_energy=2.0;probe.light_color=Color(1.0,0.82,0.58)
	root.add_child(probe)
	var lit_image:=await snapshot("boat-local-light")
	var lit:=mean_color(lit_image,boat_rect)
	check(lit.get_luminance()>dark.get_luminance()+0.04,"same boat camera receives a real local light")
	check(lit.r-dark.r>lit.b-dark.b+0.01,"local light adds warmer color than the blue moonlit background")
	evidence.boat={"day":str(day),"dark":str(dark),"local_light":str(lit),"rect":str(boat_rect)}
	probe.queue_free();await process_frame
	main.daylight_rig._boat_lights[0].energy=bow_energy
	main.daylight_rig.apply(9.0)
	var file:=FileAccess.open("res://outputs/home-lighting.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[home-lighting] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
