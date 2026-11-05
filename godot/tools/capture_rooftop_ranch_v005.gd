extends SceneTree
## v006 isolated real-render acceptance: original top flight + deeply sunk building.
const OUT := "D:/projects/sea-work/ocean_rooftop_farm/v006_attachment_fix/"

func _init() -> void:
	call_deferred("run")

func shot(cam: Camera3D, name: String, target: Vector3, dir: Vector3, dist: float, fov := 34.0) -> void:
	cam.set_process(false)
	cam.follow_enabled = false
	cam.target = target
	cam.dir = dir.normalized()
	cam.distance = dist
	cam.cam_fov = fov
	cam.apply_pose()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT + name)
	if error != OK:
		printerr("ERROR: capture save failed ",error)
		quit(1)
	print("[ranch-shot] ",name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 取景工具：玩家上限是 77.8 m（SEA-CAMERA-R11），这里临时放开，保持屋顶牧场整组机位。
	main.cam.zoom_max = 260.0
	main._autosave_on = false
	main.set_process(false)
	for i in 16: await process_frame
	var ranch: Node3D = main._zone_nodes["rooftop_ranch"]
	var area: Node3D = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	var landing: Node3D = area.get_node("Landing_main")
	var park: Marker3D = landing.get_node("BoatPark")
	var state: Node = root.get_node("GameState")
	state.enter_zone("rooftop_ranch")
	state.landing_id = "main"
	state.set_mode(state.Mode.ON_BOAT)
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.actor_controller.reconcile_mode(state.Mode.ON_BOAT)
	if not main._step_ashore():
		printerr("ERROR: real boarding failed");quit(1);return
	for i in 600:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking(): break
	var cam: Camera3D = main.cam
	await shot(cam,"ranch_v006_sunken_overview.png",ranch.to_global(Vector3(0,59.5,0)),Vector3(0.85,0.65,1.0),95,34)
	await shot(cam,"ranch_v006_original_top_stair.png",ranch.to_global(Vector3(26.0,58.1,1.0)),Vector3(1.0,0.4,0.45),24,39)
	var destination := ranch.to_global(Vector3(0,60.05,6))
	if not main.actor_controller.start_walk(area,destination):
		printerr("ERROR: real roof walk failed");quit(1);return
	for i in 6000:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking(): break
	if main.player.global_position.distance_to(destination)>0.6:
		printerr("ERROR: capsule did not reach roof");quit(1);return
	await shot(cam,"ranch_v006_walkable_roof.png",ranch.to_global(Vector3(0,60.5,0)),Vector3(0.7,1.0,0.85),85,35)
	await shot(cam,"ranch_v006_front_attachments.png",ranch.to_global(Vector3(0,58.0,5)),Vector3(0.45,0.45,1.0),88,36)
	await shot(cam,"ranch_v006_parapet_moss.png",ranch.to_global(Vector3(-18,60.5,16.5)),Vector3(0.1,0.4,1.0),16,38)
	print("[ranch-shot] complete")
	quit(0)
