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
			var box: AABB=surface.global_transform.affine_inverse()*child.global_transform*mm.get_instance_transform(i)*mm.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
			if key=="house": check(absf(box.size.x-8.625)<.001,"original main wall enlarged exactly 50 percent")
			if key.begins_with("platform_board") or key.begins_with("dock_board"):check(absf(box.end.y-2.15)<.002,"main deck height 2.15m")
			if key in ["foundation","pier"]:check(absf(box.position.y-1.12)<.002,"foundation touches preserved waterline base")
			if key=="entry":check(box.get_center().z>3.0,"entry faces game +Z")
		for s in mm.mesh.get_surface_count():
			var mat: ShaderMaterial=mm.mesh.surface_get_material(s)
			check(mat!=null and mat.get_shader_parameter("palette").resource_path=="res://assets/textures/shared/sea_cabin_timber_8x8_512.png","single shared palette binding")
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
			var box: AABB=base.global_transform.affine_inverse()*node.global_transform*mm.get_instance_transform(i)*mm.mesh.get_aabb()
			lower_bounds=box if lower_first else lower_bounds.merge(box);lower_first=false
			check(box.end.y<=1.461,"new base below upper ground deck")
			if key=="roof_slab":check(absf(box.end.y-1.46)<.002,"new base roof meets wood deck underside")
		for si in mm.mesh.get_surface_count():
			var mat: ShaderMaterial=mm.mesh.surface_get_material(si)
			check(mat!=null and mat.get_shader_parameter("palette").resource_path=="res://assets/textures/shared/sea_cabin_timber_8x8_512.png","new base shared palette")
	check(slabs==7,"seven storeys in new submerged base")
	check(lower_instances==lower_data.instances.size(),"new base instance manifest matches")
	check(lower_triangles==int(lower_metrics.expanded_triangles_after),"new base triangle count matches optimized export")
	check(lower_ids.has("facade_bay") and lower_ids.has("blue_column"),"new stepped window bays and structural columns loaded")

	# 水面 / 平台 / 基座三段关系：用世界坐标断言，任何位移或缩放回归都会在这里失败
	var water := 1.12
	var deck_bottom := INF;var deck_top := -INF;var deck_rect := Rect2();var deck_first := true
	for child in descendants(surface):
		if not child is MultiMeshInstance3D:continue
		var dmm: MultiMesh=child.multimesh;var dkey: String=child.get_meta("asset_component")
		if not (dkey.begins_with("platform_board") or dkey=="concrete_slab"):continue
		for i in dmm.instance_count:
			var wb: AABB=child.global_transform*dmm.get_instance_transform(i)*dmm.mesh.get_aabb()
			if wb.end.y>3.5:continue  # 后排水泥屋顶不属于甲板层
			deck_bottom=minf(deck_bottom,wb.position.y);deck_top=maxf(deck_top,wb.end.y)
			var dr := Rect2(wb.position.x,wb.position.z,wb.size.x,wb.size.z)
			deck_rect=dr if deck_first else deck_rect.merge(dr);deck_first=false
	check(absf(deck_bottom-water-0.04)<0.011,"deck board underside floats 0.04m above waterline")
	check(absf(deck_top-1.38)<0.005,"thin walkable deck top is 1.38m")
	var base_rect := Rect2();var base_first := true;var base_roof := -INF;var roof_rect := Rect2()
	for node in descendants(base):
		if not node is MultiMeshInstance3D:continue
		var bmm: MultiMesh=node.multimesh;var bkey: String=node.get_meta("asset_component")
		var flora: bool=bkey in ["leaf_cluster","edge_cluster","vine_long","vine_short","pink_flower","white_flower","yellow_buds"]
		for i in bmm.instance_count:
			var wb: AABB=node.global_transform*bmm.get_instance_transform(i)*bmm.mesh.get_aabb()
			if bkey=="roof_slab":
				base_roof=maxf(base_roof,wb.end.y)
				roof_rect=Rect2(wb.position.x,wb.position.z,wb.size.x,wb.size.z)
			if flora:continue
			var br := Rect2(wb.position.x,wb.position.z,wb.size.x,wb.size.z)
			base_rect=br if base_first else base_rect.merge(br);base_first=false
	check(absf(base_roof-deck_bottom)<0.005,"submerged base roof flush with deck underside")
	check(absf(roof_rect.size.x-16.241)<0.03,"base top face widened to 16.24m (1.450x)")
	check(absf(roof_rect.size.y-17.770)<0.03,"base top face deepened to 17.77m (1.431x)")
	# 顶面必须盖住整座上层建筑（不含外伸栈桥），这是用户要求的可见关系
	var upper_rect := Rect2()
	for module in surface.get_children():
		if "栈桥" in module.name:continue
		for child in descendants(module):
			if not child is MultiMeshInstance3D:continue
			var umm: MultiMesh=child.multimesh
			for i in umm.instance_count:
				var ub: AABB=child.global_transform*umm.get_instance_transform(i)*umm.mesh.get_aabb()
				var ur := Rect2(ub.position.x,ub.position.z,ub.size.x,ub.size.z)
				upper_rect=ur if upper_rect.size==Vector2.ZERO else upper_rect.merge(ur)
	check(upper_rect.size.x<roof_rect.size.x and upper_rect.size.y<roof_rect.size.y,"base top face larger than the whole upper building")
	check(roof_rect.position.x<upper_rect.position.x-0.35 and roof_rect.end.x>upper_rect.end.x+0.35,"base top face overhangs upper building by 0.40m on X")
	check(roof_rect.position.y<upper_rect.position.y-0.35 and roof_rect.end.y>upper_rect.end.y+0.35,"base top face overhangs upper building by 0.40m on Z")
	check(base_rect.size.x>deck_rect.size.x and base_rect.size.y>deck_rect.size.y,"base footprint larger than upper deck in both axes")

	var salvage: Node3D=models.get_node("绞盘打捞台")
	check(salvage.position.is_equal_approx(Vector3(-5,0,4.15)),"current authored independent salvage placement preserved")
	var main_landing: Node3D=zone.landing_point("main");var plot: Node3D=main.farm_field.find("home_plot")
	check(main_landing.ground().contains_world(main_landing.stand_position().x,main_landing.stand_position().z),"landing stands on new dock")
	check(not main_landing.ground().path_between(main_landing.stand_position(),plot.global_position).is_empty(),"new dock to farm plot reachable")
	var data: Dictionary=main_landing.data()
	check(main._is_open_water(data.boatPark[0],data.boatPark[2]),"new boat park on navigable water")
	check(zone.landing_point("salvage").stand_position().is_equal_approx(Vector3(-11.6,1.33,12.6)),"salvage landing unchanged")
	var evidence := {"lower_components":lower_ids.size(),"lower_instances":lower_instances,"lower_triangles":lower_triangles,"lower_bounds_min":[lower_bounds.position.x,lower_bounds.position.y,lower_bounds.position.z],"lower_bounds_size":[lower_bounds.size.x,lower_bounds.size.y,lower_bounds.size.z],"component_count":component_ids.size(),"expanded_triangles":triangles,"bounds_min":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_size":[bounds.size.x,bounds.size.y,bounds.size.z],"front_godot":[0,0,1],"yaw_degrees":0,"uniform_source_scale":1.15,"revision_scale":1.5,"total_scale_over_v003":1.725,"deck_y":deck_top,"deck_underside_y":deck_bottom,"water_y":water,"base_roof_y":base_roof,"base_rect":[base_rect.position.x,base_rect.position.y,base_rect.size.x,base_rect.size.y],"deck_rect":[deck_rect.position.x,deck_rect.position.y,deck_rect.size.x,deck_rect.size.y],"base_scale":[1.4501,1.0,1.4308],"roof_rect":[roof_rect.position.x,roof_rect.position.y,roof_rect.size.x,roof_rect.size.y],"upper_rect":[upper_rect.position.x,upper_rect.position.y,upper_rect.size.x,upper_rect.size.y],"checks":checks,"failures":failures}
	var file := FileAccess.open("res://outputs/solar-cabin-runtime.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	if DisplayServer.get_name()!="headless":
		main.hud.hide();main.markers.hide();main.ribbon.hide();main.cam.suspend_follow()
		await shot("front",Vector3(4.3,5.0,5.5),38.0,Vector3(-.6,.70,.8))
		await shot("back",Vector3(4.3,5.0,3.5),33.0,Vector3(.65,.6,-.8))
		await shot("top",Vector3(4.3,2.0,5.5),34.0,Vector3(.01,1,.01))
		await shot("lower",Vector3(5,-6,1.6),43.0,Vector3(-.7,.18,.8))
		await shot("rim",Vector3(-1.4,1.4,3.5),13.0,Vector3(-1,.14,.06))
		await shot("context",Vector3(2,1.12,6),52.0,Vector3(-.6,.8,.7))
	print("[solar-cabin] checks=",checks," failures=",failures)
	main.queue_free();await process_frame;quit(0 if failures==0 else 1)
