extends SceneTree
## SEA-NAV-R11：150m 可航区的跨文件契约。
##
## 这条范围横跨四个文件（可航区常量、几何硬界、相机平移范围、存档回位判定），
## 任何一处单独改动都会让「船能开多远」在雷达图和实际上不一致，而且不会报错。
## 所以用会失败的断言盯住它们，而不是靠注释。

const Scope = preload("res://src/core/play_scope.gd")
const WaterNav = preload("res://src/navigation/water_navigation.gd")

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED

	var area: Rect2 = main.navigation.allowed_area
	# --full-world 下 allowed_area 为空，可航范围整个交给几何硬界，
	# 150m 这条契约不适用。明确跳过，而不是让它变成一条假红。
	if not area.has_area():
		print("[sail-bounds] 0 checks, 0 failures (full-world: 范围由几何硬界承担，本条不适用)")
		quit(0)
		return
	check(area == Scope.SAIL_BOUNDS, "可航区等于 SEA-NAV 常量 " + str(area))
	check(is_equal_approx(area.size.x, 150.0) and is_equal_approx(area.size.y, 150.0),
		"可航区 150x150 " + str(area.size))
	check(area.has_point(Vector2(0, 0)), "原点在可航区")

	# 家园生活区仍是独立的小范围：采集物、出生点靠它，不能被可航区吞掉。
	check(area.encloses(Scope.HOME_WATER) and Scope.HOME_WATER != area,
		"可航区包住家园生活区且两者分开")

	# 五个登记泊位全部落在可航区内。
	for zone_id in ["zone1", "zone2", "zone3", "zone4", "zone5"]:
		var zone: Node = main._zone_nodes.get(zone_id)
		if zone == null:
			continue
		for point in zone.landing_points():
			var data: Dictionary = point.data()
			var p := Vector2(float(data.boatPark[0]), float(data.boatPark[2]))
			check(area.has_point(p), "泊位在可航区 " + zone_id + "/" + str(data.id))

	# 四个角落附近的开阔水面必须能规划出航路。
	var home: Node3D = main._zone_nodes["zone1"].landing_point("main")
	var home_data: Dictionary = home.data()
	var from := Vector2(float(home_data.boatPark[0]), float(home_data.boatPark[2]))
	for corner in [Vector2(60, 60), Vector2(-60, 60), Vector2(-60, -60), Vector2(60, -60)]:
		var open_here: bool = main.navigation.is_open_water(corner.x, corner.y)
		var route: Array = main.navigation.plan_route_to(from, corner.x, corner.y)
		check(open_here and not route.is_empty(),
			"可规划到 " + str(corner) + " open=" + str(open_here) + " wps=" + str(route.size()))

	# 边界内外各取一点：内合法、外拒绝。
	check(main.navigation.is_open_water(74.5, 0.0), "边界内 x=74.5 合法")
	check(not main.navigation.is_open_water(75.5, 0.0), "边界外 x=75.5 拒绝")
	check(main.navigation.is_open_water(0.0, 74.5), "边界内 z=74.5 合法")
	check(not main.navigation.is_open_water(0.0, 75.5), "边界外 z=75.5 拒绝")

	# 几何硬界与相机平移范围都必须包住可航区，否则边角会被静默切掉。
	check(WaterNav.WORLD_WATER.encloses(area), "几何硬界包住可航区 " + str(WaterNav.WORLD_WATER))
	var cam: Node = main.get_node("Camera")
	check(cam.pan_bounds.encloses(area), "相机平移范围包住可航区 " + str(cam.pan_bounds))

	print("[sail-bounds] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
