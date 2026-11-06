extends SceneTree

const OUT := "res://outputs/sea-fauna-render"
var checks := 0
var failures := 0
var main: Node

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func shot(name: String, target: Vector3, direction: Vector3, distance: float) -> void:
	check(main.water_node.is_visible_in_tree(), "正式截图始终保留真实水面 " + name)
	main.cam.set_process(false)
	main.cam.follow_enabled = false
	main.cam.target = target
	main.cam.dir = direction.normalized()
	main.cam.distance = distance
	main.cam.apply_pose()
	for _i in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and image.get_width() > 0 and image.get_height() > 0, "render frame " + name)
	check(image.save_png(OUT + "/" + name + ".png") == OK, "save render frame " + name)

func set_hour(hour: float) -> void:
	main.world_clock.paused = true
	main.world_clock.seconds = hour * 3600.0
	main.world_clock.changed.emit(main.world_clock.query())
	main.daylight_rig.apply(hour)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	root.add_child(main)
	main.boat.set_process(false)
	main.boat.set_physics_process(false)
	main.weather_service.set_weather("clear")
	for _i in 16:
		await process_frame
	if main._title_active:
		main.title_camera.finish(main.cam)
		main._resume_after_avatar_or_title()
	var cabin: Node3D = main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋")
	var ranch: Node3D = main.get_node("World/SeaStructures/rooftop_ranch")
	var fish: Node3D = main.get_node("World/Environment/Animals/SolarCabinFishSchools")
	var near_school: Node3D = fish.get_node("NearSchool")
	var fish_focus := near_school.global_position - Vector3.UP * 0.8
	var cabin_focus := cabin.to_global(Vector3(0, 12, 0))
	var ranch_focus := ranch.to_global(Vector3(0, 60, 0))
	check(main.water_node.visible and main.water_node.is_visible_in_tree(), "formal render keeps the real water visible")
	set_hour(9.0)
	check(main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/SolarCabinGulls").is_visible_in_tree(), "solar cabin gulls visible in clear day")
	check(ranch.get_node("RooftopRanchGulls").is_visible_in_tree(), "rooftop ranch gulls visible in clear day")
	check(main.player.is_visible_in_tree(), "正式玩家机位保留真实角色")
	var player_focus: Vector3 = main.player.global_position + Vector3.UP * 1.0
	await shot("sea_fauna_day_player_77_8m", player_focus, Vector3(-0.5, 0.7, 0.5), 77.8)
	check(is_equal_approx(main.cam.global_position.distance_to(main.cam.target), 77.8), "真实玩家机位距离为 77.8m")
	check(not main.cam.is_position_behind(main.player.global_position), "真实角色位于玩家机位前方")
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).has_point(main.cam.unproject_position(main.player.global_position)), "真实角色位于正式画面内")
	await shot("fish_schools_day_close", fish_focus, Vector3(0.72, 0.54, 1.0), 10.0)
	await shot("solar_cabin_gulls_day", cabin_focus, Vector3(0.74, 0.52, 1.0), 20.0)
	await shot("rooftop_ranch_gulls_day", ranch_focus, Vector3(0.76, 0.52, 1.0), 52.0)
	set_hour(18.5)
	check(not main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/SolarCabinGulls").is_visible_in_tree(), "solar cabin gulls hidden at night")
	check(not ranch.get_node("RooftopRanchGulls").is_visible_in_tree(), "rooftop ranch gulls hidden at night")
	await shot("sea_fauna_night_no_gulls", Vector3(0, 1, 0), Vector3(0.72, 0.54, 1.0), 77.8)
	var report := {"checks": checks, "failures": failures, "frames": ["sea_fauna_day_player_77_8m", "fish_schools_day_close", "solar_cabin_gulls_day", "rooftop_ranch_gulls_day", "sea_fauna_night_no_gulls"], "water_visible": main.water_node.is_visible_in_tree(), "day_hour": 9.0, "night_hour": 18.5, "player_distance": 77.8}
	FileAccess.open("res://outputs/sea-fauna-render.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("[sea-fauna-render] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
