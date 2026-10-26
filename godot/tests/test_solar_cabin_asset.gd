extends SceneTree
## Current runtime model/scale/front/landing evidence. Use run_verification.py.
var checks := 0
var failures := 0
var main: Node
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)
func _init() -> void:
	call_deferred("run")
func triangle_count(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		count += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null and not a[Mesh.ARRAY_INDEX].is_empty() else a[Mesh.ARRAY_VERTEX].size()) / 3
	return count
func descendants(node: Node) -> Array:
	var result := [node]
	for child in node.get_children(): result.append_array(descendants(child))
	return result
func shot(label: String, target: Vector3, distance: float, orbit: Vector3) -> void:
	main.cam.target=target;main.cam.distance=distance;main.cam.orbit_dir=orbit;main.cam.refresh()
	for i in 18: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/solar-cabin-"+label+".png")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("This geometry probe needs the real renderer; run visual-solar-cabin.");quit(2);return
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;root.get_node("Economy").ticking=false
	for i in 3: await process_frame
	var zone: Node3D=main.get_node("World/Zones/Zone1HomeHarbor")
	var models: Node3D=zone.get_node("Models")
	for name in ["detail","unit_01","unit_02","unit_03"]: check(not models.get_node(name).visible,"old sea models retired "+name)
	var surface: Node3D=models.get_node("太阳能木屋/太阳能木屋-海上区域")
	check(surface.scale.is_equal_approx(Vector3.ONE),"prefab root scale one")
	var component_ids := {};var triangles := 0;var bounds := AABB();var first := true
	check(surface.get_child_count()==4,"four independent semantic modules")
	for child in descendants(surface):
		if not child is MultiMeshInstance3D:continue
		var mm: MultiMesh=child.multimesh;var key: String=child.get_meta("asset_component")
		component_ids[key]=true;triangles+=triangle_count(mm.mesh)*mm.instance_count
		for i in mm.instance_count:
			var box: AABB=mm.get_instance_transform(i)*mm.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
			if key=="house": check(absf(box.size.x-8.625)<.001,"original main wall enlarged exactly 50 percent")
			if key.begins_with("platform_board") or key.begins_with("dock_board"):check(absf(box.end.y-2.15)<.002,"main deck height 2.15m")
			if key in ["foundation","pier"]:check(absf(box.position.y-1.12)<.002,"foundation touches preserved waterline base")
			if key=="entry":check(box.get_center().z>3.0,"entry faces game +Z")
		for s in mm.mesh.get_surface_count():
			var mat: ShaderMaterial=mm.mesh.surface_get_material(s)
			check(mat!=null and mat.get_shader_parameter("palette").resource_path=="res://assets/textures/shared/sea_cabin_muted_8x8_512.png","single shared palette binding")
	check(component_ids.size()==49,"49 active source components loaded")
	for key in ["foundation","pier","vine","palm","deck_tile","sail","canopy_hook"]:check(not component_ids.has(key),"retired clutter/gray base: "+key)
	for key in ["umbrella","sofa","cooler","table","pot"]:check(component_ids.has(key),"right lounge retained: "+key)
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/solar_cabin/revision_metrics.json"))
	check(triangles==int(manifest.expanded_triangles_after),"expanded runtime triangles match optimized export")
	var base: Node3D=models.get_node("太阳能木屋/太阳能木屋-海下基座")
	var lower_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/bloom_lower_building/instances.json"))
	var lower_metrics: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/bloom_lower_building/revision_metrics.json"))
	var lower_ids := {};var lower_triangles := 0;var lower_instances := 0;var slabs := 0
	var lower_bounds := AABB();var lower_first := true
	for node in descendants(base):
		check(not node is MeshInstance3D,"no legacy submerged merged mesh remains")
		if not node is MultiMeshInstance3D:continue
		var mm: MultiMesh=node.multimesh;var key: String=node.get_meta("asset_component")
		lower_ids[key]=true;lower_triangles+=triangle_count(mm.mesh)*mm.instance_count;lower_instances+=mm.instance_count
		if key=="floor_slab":slabs=mm.instance_count
		for i in mm.instance_count:
			var box: AABB=mm.get_instance_transform(i)*mm.mesh.get_aabb()
			lower_bounds=box if lower_first else lower_bounds.merge(box);lower_first=false
			check(box.end.y<=1.461,"new base below upper ground deck")
			if key=="roof_slab":check(absf(box.end.y-1.46)<.002,"new base roof meets wood deck underside")
		for si in mm.mesh.get_surface_count():
			var mat: ShaderMaterial=mm.mesh.surface_get_material(si)
			check(mat!=null and mat.get_shader_parameter("palette").resource_path=="res://assets/textures/shared/sea_cabin_muted_8x8_512.png","new base shared palette")
	check(slabs==7,"seven storeys in new submerged base")
	check(lower_instances==lower_data.instances.size(),"new base instance manifest matches")
	check(lower_triangles==int(lower_metrics.expanded_triangles_after),"new base triangle count matches optimized export")
	check(lower_ids.has("facade_bay") and lower_ids.has("blue_column"),"new stepped window bays and structural columns loaded")

	var salvage: Node3D=models.get_node("绞盘打捞台")
	check(salvage.position.is_equal_approx(Vector3(-12,0,13)),"independent salvage unchanged")
	var main_landing: Node3D=zone.landing_point("main");var plot: Node3D=main.farm_field.find("home_plot")
	check(main_landing.ground().contains_world(main_landing.stand_position().x,main_landing.stand_position().z),"landing stands on new dock")
	check(not main_landing.ground().path_between(main_landing.stand_position(),plot.global_position).is_empty(),"new dock to farm plot reachable")
	var data: Dictionary=main_landing.data()
	check(main._is_open_water(data.boatPark[0],data.boatPark[2]),"new boat park on navigable water")
	check(zone.landing_point("salvage").stand_position().is_equal_approx(Vector3(-11.6,1.33,12.6)),"salvage landing unchanged")
	var evidence := {"lower_components":lower_ids.size(),"lower_instances":lower_instances,"lower_triangles":lower_triangles,"lower_bounds_min":[lower_bounds.position.x,lower_bounds.position.y,lower_bounds.position.z],"lower_bounds_size":[lower_bounds.size.x,lower_bounds.size.y,lower_bounds.size.z],"component_count":component_ids.size(),"expanded_triangles":triangles,"bounds_min":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_size":[bounds.size.x,bounds.size.y,bounds.size.z],"front_godot":[0,0,1],"yaw_degrees":0,"uniform_source_scale":1.15,"revision_scale":1.5,"total_scale_over_v003":1.725,"deck_y":2.15,"checks":checks,"failures":failures}
	var file := FileAccess.open("res://outputs/solar-cabin-runtime.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	if DisplayServer.get_name()!="headless":
		main.hud.hide();main.markers.hide();main.ribbon.hide();main.cam.suspend_follow()
		await shot("front",Vector3(4.3,5.0,5.5),38.0,Vector3(-.6,.70,.8))
		await shot("back",Vector3(4.3,5.0,3.5),33.0,Vector3(.65,.6,-.8))
		await shot("top",Vector3(4.3,2.0,5.5),34.0,Vector3(.01,1,.01))
		await shot("lower",Vector3(5,-6,1.6),43.0,Vector3(-.7,.18,.8))
		await shot("context",Vector3(2,1.12,6),52.0,Vector3(-.6,.8,.7))
	print("[solar-cabin] checks=",checks," failures=",failures)
	main.queue_free();await process_frame;quit(0 if failures==0 else 1)
