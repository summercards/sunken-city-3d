extends SceneTree
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	print("[fishery-site] ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
func scan(node: Node, rows: Array) -> void:
	var row := {"path":str(node.get_path()),"type":node.get_class()}
	if node is Node3D:
		row.position = vec(node.global_position)
		row.local_position = vec(node.position)
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = node.global_transform * node.mesh.get_aabb()
		row.bounds = {"min":vec(box.position),"max":vec(box.end)}
		row.mesh = node.mesh.resource_path
	rows.append(row)
	for child in node.get_children(): scan(child,rows)
func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.world_clock.paused = true
	main.weather_service.paused = true
	var site: Node3D = main.get_node("World/Zones/Zone1HomeHarbor/Models/绞盘打捞台")
	var area: Node3D = main.get_node("World/Zones/Zone1HomeHarbor/WalkAreas/Walk_zone1_salvage")
	var rows: Array = []
	scan(site,rows)
	var deck_faces: Array = []
	for mesh: MeshInstance3D in site.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "PoleAndFlowers": continue
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for index in range(0,faces.size(),3):
			var a := mesh.global_transform * faces[index]
			var b := mesh.global_transform * faces[index+1]
			var c := mesh.global_transform * faces[index+2]
			if maxf(absf(a.y-1.33),maxf(absf(b.y-1.33),absf(c.y-1.33))) < 0.012:
				deck_faces.append([vec(a),vec(b),vec(c)])
	var rects: Array = []
	for r: Rect2 in area.rects: rects.append([r.position.x,r.position.y,r.size.x,r.size.y])
	var result := {"site_nodes":rows,"walk_rects":rects,"surface_y":area.surface_y,"board":vec(main.trade_board.global_position),"landing":vec(area.get_node("Landing_salvage").global_position),"boat_park":vec(area.get_node("Landing_salvage/BoatPark").global_position)}
	result.deck_faces = deck_faces
	check(not rows.is_empty(),"formal site has inspectable geometry")
	check(site.get_node_or_null("salvage_station/PoleAndFlowers") != null,"utility pole remains a separate protected child")
	var output := FileAccess.open("res://outputs/fishery-site.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	if DisplayServer.get_name() != "headless":
		main.daylight_rig.apply(9)
		main.hud.hide()
		main.cam.suspend_follow()
		main.cam.target = Vector3(-13,1.1,15)
		main.cam.distance = 32
		main.cam.orbit_dir = Vector3(-0.45,0.8,0.6)
		main.cam.refresh()
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/fishery-site-before.png")
	print("[fishery-site] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
