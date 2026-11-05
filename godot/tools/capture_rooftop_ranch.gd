extends SceneTree
## 顶层牧场的实机取景：验证「水面到底切在建筑哪一层」和「船能不能靠上平台」。
##
## 必须真实渲染（不加 --headless），输出到 res://outputs/：
##   rooftop_ranch_sea.png     —— 从海面看塔楼：水面切在保留段最下面那层消防梯平台下 0.26 米
##   rooftop_ranch_boarding.png—— 近景：船贴平台外沿，人站在平台上
##   rooftop_ranch_roof.png    —— 楼顶农场俯瞰
##
##   godot --path godot --resolution 1280x800 --script res://tools/capture_rooftop_ranch.gd -- --skip-title --nosave

var main: Node

func _init() -> void:
	call_deferred("run")

func _shot(name: String, target: Vector3, dir: Vector3, distance: float, fov := 34.0) -> void:
	main.cam.suspend_follow() if main.cam.has_method("suspend_follow") else main.cam.set_process(false)
	main.cam.target = target
	main.cam.dir = dir.normalized()
	main.cam.distance = distance
	main.cam.cam_fov = fov
	main.cam.apply_pose()
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/" + name)
	print("[ranch-shot] ", name)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 10:
		await process_frame
	var ranch: Node3D = main._zone_nodes.get("rooftop_ranch", null)
	if ranch == null:
		print("[ranch-shot] FAIL no rooftop_ranch in main")
		quit(1)
		return
	var area: Node3D = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	var landing: Node3D = area.get_node("Landing_main")
	var park: Marker3D = landing.get_node("BoatPark")
	var stand: Vector3 = landing.stand_position()
	print("[ranch-shot] root=", ranch.global_position, " stand=", stand, " park=", park.global_position)
	# 船靠到平台上，人站到甲板 —— 与真实靠泊同一条数据。
	main.boat.place_at(park.global_position, park.global_rotation.y)
	main.player.reparent(main, true)
	main.player.position = stand + Vector3(0.0, 0.02, 0.0)
	main.actor_controller.reconcile_mode(0)
	var state: Node = root.get_node("GameState")
	state.enter_zone("rooftop_ranch")
	state.landing_id = "main"
	for i in 6:
		await process_frame

	# 1) 海面全景：看清水面切在平台下面那一层。
	await _shot("rooftop_ranch_sea.png",
		Vector3(stand.x, stand.y + 1.2, stand.z),
		Vector3(1.0, 0.34, 0.20), 46.0, 30.0)
	# 2) 靠泊近景：船、平台、上楼梯口。
	await _shot("rooftop_ranch_boarding.png",
		Vector3(stand.x - 2.0, stand.y + 0.6, stand.z),
		Vector3(1.0, 0.26, 0.42), 14.0, 36.0)
	# 3) 楼顶农场。
	await _shot("rooftop_ranch_roof.png",
		Vector3(ranch.global_position.x, ranch.global_position.y + 60.0, ranch.global_position.z),
		Vector3(-0.62, 0.60, 0.50), 52.0, 32.0)
	quit(0)
