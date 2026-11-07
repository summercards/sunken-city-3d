extends SceneTree
## Actual shop, independently imported furniture, genuine capsule routes and counter.
var main: Node
var shop: Node3D
var area: Node3D
var reveal: Node3D
var checks:=0
var failures:=0
var evidence: Dictionary={"routes":[]}
func _init() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func point(x: float,z: float)->Vector3:
	var p:=shop.to_global(Vector3(x,.3,z));p.y=area.surface_y;return p
func run()->void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false);main.cam.set_process(false);main.boat.set_process(false)
	root.get_node("Economy").ticking=false
	for i in 8:await process_frame
	shop=main.get_node("World/SeaStructures/floating_shop");shop.set_physics_process(false);shop.set_motion_time(0);area=shop.walk_areas[0]
	reveal=shop.get_node("RoofReveal");reveal.set_process(false)
	var interior: Node3D=shop.get_node("Visual/Interior")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/gift_kiosk_interior/runtime_manifest.json"))
	check(interior.get_meta("asset_id")=="SEA-SCENE-GKI-ASSEMBLY","stable independent interior assembly")
	check(interior.get_node("Floor").get_child_count()==102,"102 independently instanced inset tiles")
	var swatches: Dictionary={}
	for tile in interior.get_node("Floor").get_children():swatches[str(tile.name).get_slice("_",1)]=true
	check(swatches.size()==3,"cream, blue and honey floor swatches")
	var triangles:=0
	for e in manifest.components:
		var prefab: PackedScene=load("res://scenes/components/facilities/gift_kiosk_interior/"+str(e.key)+".tscn")
		check(prefab!=null,"independent component loads "+str(e.key))
		var node:=prefab.instantiate() as Node3D
		check(node.transform==Transform3D.IDENTITY,"component root identity "+str(e.key))
		for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var mat:=mesh.get_active_material(surface) as StandardMaterial3D
				check(mat!=null and mat.albedo_texture.resource_path=="res://assets/textures/shared/sea_cozy_8x8_512.png","official shared palette "+str(e.key))
				check(mat!=null and mat.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST,"nearest palette filtering")
				var arrays: Array=mesh.mesh.surface_get_arrays(surface)
				triangles+=int((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3)
		node.free()
	check(triangles==17696,"11 optimized component triangle total")
	for row in manifest.instances+manifest.reused_instances:
		var group: String="Floor" if str(row.key).begins_with("tile_") else ("Plants" if row.key=="foliage" else "Furnishings")
		var n: Node3D=interior.get_node(group+"/"+str(row.name))
		var r: Array=row.rotation_euler_xyz;var s: Array=row.scale;var p: Array=row.position
		var expected:=Transform3D(Basis(Vector3.UP,float(r[2])).scaled_local(Vector3(float(s[0]),float(s[2]),float(s[1]))),Vector3(float(p[0]),float(p[2]),-float(p[1])))
		check(n.transform.is_equal_approx(expected),"full actual interior instance transform "+str(row.name))
		check(not n.get_meta("roof_reveal",false),"interior stays during roof reveal "+str(row.name))
	for p in [Vector2(-1.55,-2.65),Vector2(-1.95,1.45),Vector2(2.50,-2.40),Vector2(2.60,-1.10)]:
		check(not area.contains_position(point(p.x,p.y),.01),"real furniture excluded from capsule domain "+str(p))
	for p in [Vector2(0,0),Vector2(0,4.3),Vector2(-1.1,-.75),Vector2(-3.50,1.45),Vector2(1.15,-2.4)]:
		check(area.contains_position(point(p.x,p.y),.01),"entry and fixture access remain walkable "+str(p))
	var start:=point(0,7.4);main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]});main.actor_controller.walk_area=area
	var clock:=0.0
	for p in [Vector2(0,0),Vector2(-1.1,-.75),Vector2(1.15,-2.4),Vector2(-3.50,1.45),Vector2(0,0)]:
		check(main._start_walk(area,point(p.x,p.y)),"actual capsule route starts "+str(p))
		for i in 650:
			clock+=1.0/60.0;shop.set_motion_time(clock)
			await physics_frame
			main._update_walk(1.0/60.0);reveal.advance(1.0/60.0)
			if main.actor_controller.state_id()=="ashore_idle":break
		check(main.player.global_position.distance_to(point(p.x,p.y))<.18,"actual capsule reaches clear fixture aisle "+str(p))
		check(absf(main.player.global_position.y-area.surface_y)<.025,"floors and actor follow floating support")
		evidence.routes.append({"goal":str(p),"actual":str(main.player.global_position),"roof":reveal.snapshot()})
	reveal.advance(1)
	check(reveal.snapshot().visible_roofs==0,"roof opens around real indoor actor")
	for n in interior.get_children():check(n.is_visible_in_tree(),"all interior groups visible after roof opens")
	var counter: Node3D=shop.get_node("Objects/SupplyCounter")
	check(counter.position.distance_to(Vector3(-1.1,.3,-.75))<.2,"supply point now at real customer side of checkout")
	check(main._start_walk(area,counter.global_position),"real approach to new checkout")
	for i in 300:
		await physics_frame;main._update_walk(1.0/60.0)
		if main.actor_controller.state_id()=="ashore_idle":break
	counter.interact(main.player)
	check(main.shop_panel.is_open(),"existing general store panel opens from new counter")
	main.shop_panel.close()
	evidence["roof"]=reveal.snapshot();evidence["master_triangles"]=triangles;evidence["not_run"]=["low-end device performance","full unrelated feature suite"];evidence["expected_faults"]=[]
	var file:=FileAccess.open("res://outputs/gift-kiosk-interior-verification.json",FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "));file.close()
	main.queue_free();await process_frame
	print("[gift-kiosk-interior] ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
