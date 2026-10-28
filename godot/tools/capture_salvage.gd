extends SceneTree
## 家园补给站（绞盘打捞台）近景：白模问题复现与修后核对。
func _init() -> void: call_deferred("run")

func shot(tag: String, target: Vector3, dist: float, orbit: Vector3) -> void:
	var main = root.get_node("Main")
	main.cam.target = target
	main.cam.distance = dist
	main.cam.orbit_dir = orbit
	main.cam.refresh()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/salvage-" + tag + "-" + str(OS.get_environment("SALV_SUFFIX")) + ".png")
	print("[salvage] ", tag)

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	root.add_child(main)
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.weather_service.set_weather("clear")
	var tag := str(OS.get_environment("SALV_TAG"))
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	main.cam.suspend_follow()
	var station: Node3D = main._zone_nodes["zone1"].get_node("Models/绞盘打捞台")
	var p := Vector3(-8.5, 1.8, 8.0)
	print("[salvage] node=", station.global_position, " aim=", p)
	await shot("a", Vector3(-13.5, 1.6, 12.5), 26.0, Vector3(-0.55, 0.62, 0.56))
	await shot("d", Vector3(-12.0, 3.4, 10.5), 11.0, Vector3(-0.5, 0.32, 0.8))
	await shot("b", Vector3(-13.5, 2.2, 12.5), 18.0, Vector3(-0.30, 0.72, 0.62))
	await shot("c", Vector3(-13.5, 2.2, 12.5), 24.0, Vector3(0.55, 0.5, -0.66))
	print("[visual-salvage] complete")
	quit()
