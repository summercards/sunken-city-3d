extends SceneTree

const GullFlockScript = preload("res://src/ambient/building_gull_flock.gd")
const REPORT := "res://outputs/sea-fauna.json"

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

func nodes(root_node: Node) -> Array:
	var result: Array = [root_node]
	for child in root_node.get_children():
		result.append_array(nodes(child))
	return result

func gull_flocks() -> Array:
	var result: Array = []
	for node in nodes(main.get_node("World")):
		if node.has_method("set_hour") and node.get_script() == GullFlockScript:
			result.append(node)
	return result

func set_hour(hour: float) -> void:
	main.world_clock.seconds = hour * 3600.0
	main.world_clock.changed.emit(main.world_clock.query())

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	root.add_child(main)
	main.boat.set_process(false)
	main.boat.set_physics_process(false)
	for _i in 8:
		await process_frame

	var school_root: Node3D = main.get_node("World/Environment/Animals/SolarCabinFishSchools")
	var cabin: Node3D = main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋")
	var base: Node3D = cabin.get_node("太阳能木屋-海下基座")
	var base_footprint: Rect2 = main._subtree_xz_bounds(base)
	check(base_footprint.has_area(), "基座真实几何范围可读取")
	var expected := [6, 10, 14]
	for index in expected.size():
		var school: Node = school_root.get_child(index)
		check(school.members.size() == expected[index], "solar cabin fish variant count %d" % expected[index])
		check(school.get("_water") == main.water_node, "fish group receives the real water sampler")
		var first: Array = school.transforms.duplicate()
		school.sample(0.0)
		var t0: Transform3D = school.transforms[0]
		school.sample(0.7)
		var t1: Transform3D = school.transforms[0]
		check(not t0.is_equal_approx(t1), "fish body animation changes variant %d" % expected[index])
		school.sample(0.2)
		var fin_before: Transform3D = school.fin_transforms[0]
		school.sample(0.8)
		var fin_after: Transform3D = school.fin_transforms[0]
		check(not fin_before.is_equal_approx(fin_after), "fish tail animation changes %d" % expected[index])
		var half_length := 0.30 * float(school.size_scale)
		# 个体椭圆会旋转，X/Z 都须用长轴包络，不能把短轴当作 Z 上限。
		var orbit_bound := maxf(float(school.orbit_radius.x), float(school.orbit_radius.y)) * float(school.size_scale) * 1.26
		var bound_x := orbit_bound + float(school.spread_radius) + half_length + 0.1
		var bound_z := bound_x
		var center: Vector3 = school.global_position
		var envelope := Rect2(Vector2(center.x - bound_x, center.z - bound_z), Vector2(bound_x * 2.0, bound_z * 2.0))
		check(not envelope.intersects(base_footprint), "鱼群完整轨迹包络避开真实基座 %d" % expected[index])
		for member_index in school.transforms.size():
			var transform: Transform3D = school.transforms[member_index]
			var delta := transform.origin
			check(absf(delta.x) <= bound_x and absf(delta.z) <= bound_z, "fish variant %d stays within orbit+spread placement bound" % expected[index])
			var surface: Vector3 = main.water_node.sample_surface(Vector2(school.global_position.x + delta.x, school.global_position.z + delta.z))
			var member: Dictionary = school.members[member_index]
			var expected_y: float = school.submerged_y(surface.x, float(member.depth), float(member.scale))
			check(absf(transform.origin.y - expected_y) < 0.001, "fish variant %d follows wave depth" % expected[index])
		check(first.size() == expected[index], "fish transform buffer has declared count %d" % expected[index])

	var flocks := gull_flocks()
	check(flocks.size() == 2, "exactly solar cabin and rooftop ranch gull flocks are registered")
	var flock_names := []
	for flock in flocks:
		flock_names.append(String(flock.name))
		check(flock.get_parent().name in ["太阳能木屋", "rooftop_ranch", "RooftopRanch"], "gull flock belongs to an exposed real building")
		check(flock.get_meta("visual_only", false), "gull flock is visual-only")
	set_hour(9.0)
	for flock in flocks:
		check(flock.visible and flock.is_visible_in_tree(), "gull flock visible at 09:00")
		var bird: Node3D = flock.get_child(0)
		bird.set_process(false)
		bird.sample(0.0)
		var before_rotation := bird.rotation
		var before_wing: Transform3D = bird.get_child(1).transform
		bird.sample(0.25)
		check(not before_rotation.is_equal_approx(bird.rotation), "gull orientation changes")
		check(not before_wing.is_equal_approx(bird.get_child(1).transform), "gull wing flap changes")
		check(flock.global_basis.is_equal_approx(Basis.IDENTITY), "海鸥飞行平面不继承建筑旋转缩放")
		for gull: Node3D in flock.get_children():
			gull.set_process(false)
			for step in 49:
				gull.sample(float(step) * 0.5)
				var surface: Vector3 = main.water_node.sample_surface(Vector2(gull.global_position.x, gull.global_position.z))
				check(gull.global_position.y > main.water_node.global_position.y + surface.x + 1.0, "真实父变换下海鸥全轨迹高于海面")
	for hour in [5.5, 6.0, 17.99, 18.0, 18.5]:
		set_hour(hour)
		var daytime: bool = hour >= 6.0 and hour < 18.0
		for flock in flocks:
			check(flock.visible == daytime and flock.is_visible_in_tree() == daytime, "WorldClock 控制海鸥时段 %.2f" % hour)
			for gull in flock.get_children():
				check(gull.is_processing() == daytime, "昼夜同时切换海鸥动画")
	set_hour(9.0)
	main.room_controller._hide_outdoor(true)
	set_hour(9.0)
	for flock in flocks:
		check(flock.visible and not flock.is_visible_in_tree(), "ancestor-hidden gull cannot restore tree visibility indoors")
	main.room_controller._hide_outdoor(false)
	for flock in flocks:
		check(flock.is_visible_in_tree(), "gull flock returns with outdoor parent")

	for fauna in nodes(main.get_node("World")):
		if not (fauna.get_meta("visual_only", false) or fauna.get_script() == GullFlockScript):
			continue
		check(not (fauna is Area3D or fauna is CollisionObject3D or fauna is NavigationObstacle3D), "fauna has no collision/area/navigation node")
		check(not (fauna.has_method("request_interaction") and fauna.is_in_group("interactable")), "fauna has no interaction endpoint")
		for child in nodes(fauna):
			check(not (child is Area3D or child is CollisionObject3D or child is NavigationObstacle3D), "fauna subtree remains pure visual")

	var report := {"checks": checks, "failures": failures, "flocks": flock_names, "fish_counts": expected}
	FileAccess.open(REPORT, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("[sea-fauna] %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
