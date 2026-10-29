extends SceneTree
## Isolated A/B evidence for deck draft and the scene-owned pole/flower placement.
const Catalog=preload("res://src/building/building_catalog.gd")
var checks:=0
var failures:=0
var main
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func shot(name: String, target: Vector3, distance: float, orbit: Vector3) -> void:
	main.cam.target=target;main.cam.distance=distance;main.cam.orbit_dir=orbit;main.cam.refresh()
	for i in 12:
		main._process(0.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/fit-"+name+".png")
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.cam.set_process(false)
	# The editor's current main scene hides Water; enable it only in this capture.
	main.water_node.show()
	root.get_node("Economy").set_process(false);main.world_clock.paused=true
	main.cam.suspend_follow()
	var station: Node3D=main._zone_nodes.zone1.get_node("Models/绞盘打捞台")
	var pole: Node3D=station.get_node("salvage_station/PoleAndFlowers")
	check(pole.position.is_equal_approx(Vector3(2.2,0,2.4)),"pole and flowers share horizontal offset")
	check(is_zero_approx(pole.position.y),"pole/flowers height unchanged")
	check(station.position.is_equal_approx(Vector3(-5,0,4.15)),"deck assembly placement unchanged")
	var above_clear:=true
	for vertex: Vector3 in pole.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.y>=1.119 and (pole.global_transform*vertex).z<=15.50: above_clear=false
	check(above_clear,"above-water pole/flowers clear original deck edge")
	pole.position=Vector3.ZERO
	await shot("station-before",Vector3(-12,4.7,13.4),24.0,Vector3(-0.5,0.7,0.5))
	pole.position=Vector3(2.2,0,2.4)
	await shot("station-after",Vector3(-12,4.7,13.4),24.0,Vector3(-0.5,0.7,0.5))
	main.water_node.hide()
	await shot("pole-full",Vector3(-12,-4.5,12.0),43.0,Vector3(-0.5,0.35,0.7))
	main.water_node.show()
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[21,1.48,16]});root.get_node("GameState").enter_zone("zone5")
	root.get_node("Economy").inventory.set_count("wood",20)
	var built: Dictionary=main.building.begin({"kind":"deck","x":3,"z":0})
	check(built.ok,"build east deck")
	check(main.building_world.contact_rects().is_empty(),"unfinished preview has no waterline")
	main.building.tick(3)
	for mat: ShaderMaterial in main.water_node.schemes.values():
		check("runtime_contact_count" in mat.shader.get_shader_uniform_list().map(func(u): return u.name),"water shader consumes runtime contacts")
		check(int(mat.get_shader_parameter("runtime_contact_count"))==1,"completed deck contacts both water schemes")
	var deck: Node3D=main.building_world.node_for(built.id)
	for mesh: MeshInstance3D in deck.get_children():
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		check(is_equal_approx(bounds.end.y,1.48) and is_equal_approx(bounds.position.y,0.98),"top unchanged and base submerged")
		mesh.mesh.size.y=0.10;mesh.position.y=-0.05
	main.water_node.set_runtime_contact_rects([])
	await shot("deck-before",Vector3(25,1.3,15.2),15.0,Vector3(-0.45,0.5,0.8))
	for mesh: MeshInstance3D in deck.get_children():
		mesh.mesh.size.y=0.50;mesh.position.y=-0.25
	main.water_node.set_runtime_contact_rects(main.building_world.contact_rects())
	await shot("deck-after",Vector3(25,1.3,15.2),15.0,Vector3(-0.45,0.5,0.8))
	main.water_node.use_scheme("absorption")
	await shot("deck-after-absorption",Vector3(25,1.3,15.2),15.0,Vector3(-0.45,0.5,0.8))
	main.queue_free();await process_frame
	print("[building-fit] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
