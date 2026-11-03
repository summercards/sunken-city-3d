extends SceneTree
## v005 实机取景：只露出一段消防梯，柱体大块缺损可见。

func _init() -> void:
	call_deferred("run")

func shot(root: Node, cam: Camera3D, name: String, target: Vector3, dir: Vector3, dist: float, fov := 34.0) -> void:
	cam.set_process(false)
	cam.follow_enabled = false
	cam.target = target
	cam.dir = dir.normalized()
	cam.distance = dist
	cam.cam_fov = fov
	cam.apply_pose()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/" + name)
	print("[v005-shot] ", name)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 12: await process_frame
	var ranch: Node3D = main._zone_nodes.get("rooftop_ranch", null)
	if ranch == null:
		print("[v005-shot] FAIL no ranch")
		quit(1); return
	var area: Node3D = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	var landing: Node3D = area.get_node("Landing_main")
	var park: Marker3D = landing.get_node("BoatPark")
	var stand: Vector3 = landing.stand_position()
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.player.reparent(main, true)
	main.player.global_position = stand
	main.actor_controller.reconcile_mode(0)
	var cam: Camera3D = main.cam
	await shot(root,cam,"rooftop_ranch_v005_sea.png",Vector3(stand.x,stand.y+1.0,stand.z),Vector3(1.0,0.22,0.25),42.0,30.0)
	await shot(root,cam,"rooftop_ranch_v005_single_stair.png",Vector3(stand.x+0.8,stand.y+1.0,stand.z),Vector3(0.75,0.28,0.58),12.0,36.0)
	# 侧面近景，专门看柱体大块崩口
	await shot(root,cam,"rooftop_ranch_v005_pier_damage.png",Vector3(ranch.global_position.x-18.0,ranch.global_position.y+28.0,ranch.global_position.z+15.0),Vector3(0.55,-0.05,-0.84),26.0,38.0)
	await shot(root,cam,"rooftop_ranch_v005_roof.png",Vector3(ranch.global_position.x,ranch.global_position.y+55.0,ranch.global_position.z),Vector3(-0.6,0.65,0.48),48.0,32.0)
	quit(0)
