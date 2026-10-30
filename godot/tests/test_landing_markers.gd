extends SceneTree
## Dynamic marker density and presentation-state regression. Rendering is
## checked separately from geometry; no headless synthetic-input claims.
const Catalog = preload("res://src/building/building_catalog.gd")
var checks := 0
var failures := 0
var main: Node
var fixed_camera := Vector3.ZERO
var look_target := Vector3.ZERO
var evidence := {}

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func dynamic_rows() -> Array:
	var result: Array=[]
	for item in main.markers.items:
		if item.get("dynamic_build",false): result.append(item)
	return result

func marker(id: String) -> Dictionary:
	for item in dynamic_rows():
		if item.landing==id: return item
	return {}

func marker_ids() -> Array:
	var result: Array=[]
	for item in dynamic_rows(): result.append(str(item.landing))
	result.sort()
	return result

func pose_camera() -> void:
	main.cam.global_position=fixed_camera
	main.cam.look_at(look_target)
	main.cam.fov=42
	main.cam.make_current()

func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 20:
		pose_camera()
		main.markers._process(1.0/60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/landing-markers-"+name+".png")
	var actual: Camera3D=root.get_camera_3d()
	print("[landing-marker-shot] ",name," camera=",main.cam.global_position,
		" actual_camera=",actual.global_position if actual!=null else Vector3.INF,
		" actor=",main.player.global_position," world_visible=",main.building_world.is_visible_in_tree(),
		" instances=",main.building.query().size())
	# Keep the captured world alive through the renderer's pending readback.
	# The next test step may otherwise mutate all markers and free the scene
	# without another frame, leaving an apparently successful blank-sea image.
	for i in 5:
		pose_camera()
		main.markers._process(1.0/60.0)
		await process_frame

func sync_contract() -> void:
	var definitions: Array=[{"zone":"zone5","landing":"built:sync_probe:0","name":"测试登陆点",
		"world":Vector3(105.0,2.03,118.0),"dynamic_build":true}]
	main.markers.sync_dynamic_markers(definitions)
	var first: Dictionary=marker("built:sync_probe:0")
	check(not first.is_empty(),"sync creates one derived marker")
	if first.is_empty(): return
	first.near=0.75;first.size=45.0;first.visible=true
	first.screen=main.cam.unproject_position(first.world);first.draw_world=first.world
	main.markers.sync_dynamic_markers(definitions)
	var repeated: Dictionary=marker("built:sync_probe:0")
	check(is_same(first,repeated),"same landing ID retains its presentation object")
	check(repeated.near==0.75 and repeated.size==45.0,"sync retains hover interpolation and size")
	check(repeated.visible and repeated.screen.is_equal_approx(main.cam.unproject_position(definitions[0].world)),"sync keeps an onscreen marker visible with its current projected position")
	definitions[0].world=Vector3(105.2,2.03,118.0)
	definitions[0].name="移动后的登陆点"
	main.markers.sync_dynamic_markers(definitions)
	check(is_same(first,marker("built:sync_probe:0")) and first.world==definitions[0].world,"pose updates preserve marker identity")
	check(first.near==0.75 and first.visible,"pose update preserves live hover and visibility")
	main.markers.sync_dynamic_markers([])
	check(marker("built:sync_probe:0").is_empty(),"removed landing clears only its derived marker")

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.boat.set_process(false);main.cam.set_process(false);main.interactor.set_process(false)
	main.building_access.set_process(false);main.markers.set_process(false)
	root.get_node("Economy").set_process(false)
	await process_frame
	check(main.markers.has_method("sync_dynamic_markers"),"presentation owner exposes stable-ID synchronization")
	if not main.markers.has_method("sync_dynamic_markers"):
		main.queue_free();await process_frame
		print("[landing-markers] %d checks, %d failures"%[checks,failures])
		quit(1);return
	look_target=Vector3(105.0,1.48,118.0)
	fixed_camera=look_target+Vector3(-12,24,30)
	main.cam.follow_enabled=false;pose_camera()
	sync_contract()
	main._debug_teleport("zone5")
	main.boat.place_at(Vector3(98.0,1.12,118.0),0.0)
	main.actor_controller.restore_pose({"mode":1})
	root.get_node("Economy").inventory.set_count("wood",9999)
	var build_errors: Array=[]
	var rows_by_cell: Dictionary={}
	for x in range(40,46):
		for z in range(40,46):
			var result: Dictionary=main.building.begin({"kind":"deck","x":x,"z":z})
			if not result.ok: build_errors.append(str(Vector2i(x,z))+": "+str(result.reason))
			else: rows_by_cell[Vector2i(x,z)]=str(result.id)
			main.building.tick(3.0)
	for x in range(46,56):
		var result: Dictionary=main.building.begin({"kind":"deck","x":x,"z":43})
		if not result.ok: build_errors.append(str(Vector2i(x,43))+": "+str(result.reason))
		else: rows_by_cell[Vector2i(x,43)]=str(result.id)
		main.building.tick(3.0)
	check(build_errors.is_empty(),"remote platform fixture accepted: "+str(build_errors))
	await physics_frame;await physics_frame
	look_target=Catalog.ORIGIN+Vector3(Catalog.tile_rect(46,43).get_center().x,0,Catalog.tile_rect(46,43).get_center().y)
	fixed_camera=look_target+Vector3(-12,30,40)
	main.cam.follow_enabled=false;pose_camera()
	main.water_node.update_surface(0.0,main.boat,look_target)
	main.building_access.refresh_markers()
	var rows: Array=dynamic_rows()
	check(not rows.is_empty(),"large built platform offers landing markers")
	check(rows.size()<=main.building_access.MAX_MARKERS and rows.size()<=4,"dynamic display budget is at most four icons")
	check(main.building_access.MARKER_SPACING>=12.0,"marker spacing is at least twelve metres")
	var minimum:=INF
	var screen_minimum:=INF
	for i in rows.size():
		for j in range(i+1,rows.size()):
			minimum=minf(minimum,rows[i].world.distance_to(rows[j].world))
			screen_minimum=minf(screen_minimum,main.cam.unproject_position(rows[i].world).distance_to(main.cam.unproject_position(rows[j].world)))
	check(minimum>=main.building_access.MARKER_SPACING-0.001,"visible candidate anchors respect increased world spacing")
	check(screen_minimum>=main.building_access.MARKER_SCREEN_SPACING-0.001,"visible candidate anchors retain readable screen spacing")
	var ids: Array=marker_ids()
	evidence.sparse_ids=ids.duplicate();evidence.count=rows.size();evidence.minimum_spacing=minimum if is_finite(minimum) else null
	evidence.minimum_screen_spacing=screen_minimum if is_finite(screen_minimum) else null
	if rows.is_empty():
		main.queue_free();await process_frame
		print("[landing-markers] %d checks, %d failures"%[checks,failures])
		quit(1);return
	var focused: Dictionary=rows[0]
	var focused_id: String=focused.landing
	var pointer: Vector2=main.cam.unproject_position(focused.world)
	main.markers.pointer_query=func(): return pointer
	for i in 35: main.markers._process(1.0/60.0)
	check(focused.visible and focused.near>0.99 and focused.size>49.5,"actual hover reaches the expanded icon smoothly")
	await shot("before")
	var stable_refs:=true
	var visible_continuous:=true
	var hover_continuous:=true
	var stable_ids:=true
	for repeat in 5:
		main.building_access.refresh_markers()
		stable_refs=stable_refs and is_same(focused,marker(focused_id))
		visible_continuous=visible_continuous and focused.visible
		hover_continuous=hover_continuous and focused.near>0.99 and focused.size>49.5
		stable_ids=stable_ids and marker_ids()==ids
		main.markers._process(1.0/60.0)
	check(stable_refs,"periodic refresh reuses the hovered marker object")
	check(visible_continuous,"periodic refresh never drops the visible icon for a frame")
	check(hover_continuous,"periodic refresh never restarts hover size or colour")
	check(stable_ids,"unchanged layout and camera retain chosen landing IDs")
	await shot("after")
	var before_jitter: Array=marker_ids()
	main.boat.position+=Vector3(0.01,0,0.01)
	main.building_access.refresh_markers()
	check(marker_ids()==before_jitter,"centimetre boat movement does not reshuffle nearby icons")
	var fixed: Dictionary={"zone":"zone1","landing":"static_spacing_probe","name":"既有泊位",
		"world":focused.world,"draw_world":focused.world,"screen":Vector2.ZERO,"near":0.0,"size":30.0,"visible":false}
	main.markers.items.append(fixed)
	main.building_access.refresh_markers()
	var avoids_fixed:=true
	for item in dynamic_rows():
		if item.world.distance_to(fixed.world)<main.building_access.MARKER_SPACING-0.001: avoids_fixed=false
	check(avoids_fixed,"existing static landing suppresses redundant nearby dynamic icons")
	main.markers.items.erase(fixed)
	main.building_access.refresh_markers()
	# Active landing at the extension tip lies well outside the nearest24 boards.
	var active_id: String="built:%s:1"%str(rows_by_cell.get(Vector2i(55,43),"missing"))
	var active_data: Dictionary=main.building_access.landing_data(active_id)
	check(not active_data.is_empty(),"far active landing is a valid exposed edge")
	root.get_node("GameState").landing_id=active_id
	root.get_node("GameState").enter_zone("zone5")
	var active_at: Vector3=main.building_world.position_for({"kind":"deck","x":55,"z":43})
	main.actor_controller.restore_pose({"mode":0,"player":[active_at.x,active_at.y,active_at.z]})
	main.building_access.refresh_markers()
	check(not marker(active_id).is_empty(),"current return landing is retained beyond nearby candidate budget")
	check(dynamic_rows().size()<=main.building_access.MAX_MARKERS,"current landing stays inside total display budget")
	# Keep the return command visible even if a transient water query invalidates
	# its parking spot; this does not grant illegal navigation or change layout.
	if not active_data.is_empty():
		var original: Callable=main.navigation.shape_query
		var extra: Dictionary={"x":float(active_data.boatPark[0]),"z":float(active_data.boatPark[2]),"hx":1.0,"hz":1.0,"round":false}
		main.navigation.shape_query=func(): return original.call()+[extra]
		main.navigation.invalidate();main.building_access.refresh_markers()
		check(not marker(active_id).is_empty(),"active return icon does not flicker out under transient parking obstruction")
		main.navigation.shape_query=original;main.navigation.invalidate()
	evidence.identity_continuous=stable_refs;evidence.visible_continuous=visible_continuous;evidence.hover_continuous=hover_continuous
	evidence.active_id=active_id;evidence.renderer=DisplayServer.get_name()
	var output:=FileAccess.open("res://outputs/landing-markers.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence,"  "));output.close()
	print("[landing-marker-evidence] ",JSON.stringify(evidence))
	if DisplayServer.get_name()!="headless":
		for i in 5:
			pose_camera()
			main.markers._process(1.0/60.0)
			await process_frame
	main.queue_free();await process_frame
	print("[landing-markers] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
