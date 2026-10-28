extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func descendants(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():out.append_array(descendants(child))
	return out
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.world_clock.paused=true
	main.weather_service.paused=true
	for i in 4:await process_frame
	var surface=main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海上区域")
	var count := 0
	for node in descendants(surface):
		if not node is MultiMeshInstance3D:continue
		var key: String=node.get_meta("asset_component")
		if not (key.begins_with("platform_board") or key.begins_with("dock_board") or key in ["terrace","concrete_slab"]):continue
		var mm: MultiMesh=node.multimesh
		for i in mm.instance_count:
			var box: AABB=node.global_transform*mm.get_instance_transform(i)*mm.mesh.get_aabb()
			check(box.size.y>=.17 and box.size.y<=.221,"thin floor/bridge actual world thickness "+key+" "+str(box.size.y))
			if box.end.y<2.0:check(absf(box.end.y-1.38)<.003,"ground deck and landing share 1.38m top "+key)
			count+=1
	check(count>=30,"all floor and bridge planks measured")
	main.hud.hide();main.markers.hide();main.ribbon.hide()
	main._calendar_label.hide()
	if main.start_screen != null:main.start_screen.hide()
	main.cam.suspend_follow()
	main.cam.target=Vector3(2.4,2.6,7.2);main.cam.distance=30;main.cam.orbit_dir=Vector3(-.6,.75,.8);main.cam.refresh()
	var evidence := {"planks_measured":count,"frames":[]}
	for hour in [7.0,9.0,11.0,13.0,15.0,17.0,18.0,19.0,21.0]:
		main.world_clock.seconds=hour*3600.0
		main.daylight_rig.apply(hour)
		for i in 18:await process_frame
		var sun=main.get_node("World/Lights/Sun")
		var env=main.get_node("World/WorldEnvironment").environment
		evidence.frames.append({"hour":hour,"sun":sun.light_energy,"ambient":env.ambient_light_energy,"sky":env.background_energy_multiplier})
		if hour>=19:check(sun.light_energy==0.0 and env.ambient_light_energy>0.0,"night has moon ambience without sunlight at "+str(hour))
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/cabin-daypart-%02d.png" % int(hour))
	# Both shipped water schemes share readable blue night water and lamp reflections.
	main.water_node.use_scheme("absorption")
	main.daylight_rig.apply(19.0)
	for i in 18:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/cabin-daypart-19-absorption.png")
	main.water_node.use_scheme("original")
	main.daylight_rig.apply(9.0)
	var file:=FileAccess.open("res://outputs/cabin-dayparts.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	main.queue_free();await process_frame
	print("[cabin-dayparts] %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
