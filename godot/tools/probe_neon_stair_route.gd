extends SceneTree
## 只读：霓虹花园检修梯逐级求路，找出导航网格断在哪一级。
##   --script res://tools/probe_neon_stair_route.gd

var main: Node
var quarter: Node3D
var left: Node3D


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	for i in 24:
		await process_frame
	quarter = main._zone_nodes.get("neon_garden_quarter")
	left = quarter.get_node("Visual/LeftBuilding")
	var areas: Node3D = quarter.get_node("WalkAreas")
	var stair: Node3D = null
	for child in areas.get_children():
		if str(child.get("area_id")) == "neon_garden_left_stair":
			stair = child
	if stair == null:
		print("[route] 找不到走域")
		quit(2)
		return
	var landing: Node3D = quarter.landing_point("main")
	var stand: Vector3 = landing.stand_position()
	print("[route] 登岸点 (%.2f, %.2f, %.2f)  ground_space=%s  polygons=%d" % [
		stand.x, stand.y, stand.z, str(quarter.ground_space != null),
		quarter.ground_space.navigation_polygons if quarter.ground_space != null else -1])
	# 5 个平台 + 4 段梯段中点，逐个求路
	var probes := [
		["L279 30.60", -4.89, 30.60, -1.98],
		["F278 29.33", -3.88, 29.33, -4.94],
		["L277 28.05", -4.89, 28.05, -7.90],
		["F276 26.78", -5.88, 26.78, -4.94],
		["L275 25.50", -4.89, 25.50, -1.98],
		["F274 24.23", -3.88, 24.23, -4.94],
		["L273 22.95", -4.89, 22.95, -7.90],
		["F272 21.68", -5.88, 21.68, -4.94],
		["L271 20.40", -4.89, 20.40, -1.98],
	]
	var previous: Vector3 = stand
	var previous_name := "登岸点"
	for entry in probes:
		var world: Vector3 = left.to_global(Vector3(entry[1], entry[2], entry[3]))
		var support: Vector3 = stair.surface_point(world)
		if not support.is_finite():
			print("[route] %-12s  走域无面" % entry[0])
			continue
		var path: Array = quarter.ground_space.route(stand, support)
		var hop: Array = quarter.ground_space.route(previous, support)
		print("[route] %-12s 面 y=%.2f  屋顶路径 %2d 点  上一格→本格 %2d 点" % [
			entry[0], support.y, path.size(), hop.size()])
		previous = support
		previous_name = entry[0]
	quit(0)
