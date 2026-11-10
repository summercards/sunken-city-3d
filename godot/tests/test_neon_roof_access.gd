extends SceneTree
## SEA-NAV-R23：霓虹花园左楼屋顶必须真的能上下。
##
## 2026-11-10 体检发现：这栋楼东侧本来就带一架 12 段双跑折返检修梯（模型里从楼基
## 一直做到局部 30.60），但场景里从来没有可走面 —— 玩家只能靠下船瞬移到屋顶，
## 落差 14.08 m，看着像「凭空出现」。
##
## 这一支锁五件事：
##   1. 检修梯水面以上那一段有走域，且是三角形（斜坡），不是压平的矩形；
##   2. 梯顶真的接得上屋顶面（高度差在 agent_max_climb 以内）；
##   3. 屋顶 ↔ 梯顶走得通（走 GroundSpace，不是「看着连」）；
##   4. 梯脚有浮台 + 直梯，浮台与平台之间没有可走面（必须靠梯子，不能白走）；
##   5. 浮台不是水面阻挡，船能停在它旁边（否则人会困在浮台上）。

var main: Node
var checks := 0
var failures := 0
var quarter: Node3D
var left: Node3D


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func settle(n := 4) -> void:
	for i in n:
		await process_frame


func area_of(zone: Node, area_id: String) -> Node3D:
	for child in zone.get_node("WalkAreas").get_children():
		if str(child.get("area_id")) == area_id:
			return child
	return null


## 楼体局部 → 世界（这栋楼在 main 里被转了 72°，直接写世界坐标会错）。
func local(x: float, y: float, z: float) -> Vector3:
	return left.to_global(Vector3(x, y, z))


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.boat.set_process(false)
	main.cam.set_process(false)
	root.get_node("Economy").set_process(false)
	root.get_node("Economy").ticking = false
	await settle(24)

	quarter = main._zone_nodes.get("neon_garden_quarter")
	check(quarter != null, "霓虹花园街区在主场景里")
	if quarter == null:
		quit(1)
		return
	left = quarter.get_node_or_null("Visual/LeftBuilding")
	check(left != null, "左楼模块存在")

	var stair: Node3D = area_of(quarter, "neon_garden_left_stair")
	var float_area: Node3D = area_of(quarter, "neon_garden_left_float")
	check(stair != null, "检修梯走域存在")
	check(float_area != null, "梯脚浮台走域存在")
	if stair == null or float_area == null:
		finish()
		return

	# 1. 斜坡走域：必须是三角形，且覆盖整个「水面以上、近船侧」的折返段。
	var tris: PackedVector3Array = stair.get("surface_triangles")
	check(tris.size() == 66, "走域是 22 个三角形（实际 %d 个顶点）" % tris.size())
	check((stair.get("rects") as Array).is_empty(), "不再靠压平的矩形冒充斜梯")
	check(float(stair.get("body_radius")) > 0.0, "走域交给共享烘焙（body_radius > 0）")
	var lowest := INF
	var highest := -INF
	for p in tris:
		var w: Vector3 = stair.to_global(p)
		lowest = minf(lowest, w.y)
		highest = maxf(highest, w.y)
	check(absf(lowest - 4.83) < 0.05, "走域底端在第一级可用平台 %.2f m" % lowest)
	check(absf(highest - 15.23) < 0.10, "走域顶端接到屋面 %.2f m" % highest)

	# 2. 梯顶 ↔ 屋顶面：差多少决定要不要额外台阶。
	var roof: Node3D = area_of(quarter, "neon_garden_left_roof")
	var stair_low: Vector3 = local(-4.89, 20.40, -1.98)    # 折返梯最低一级可用平台
	var stair_high: Vector3 = local(-4.89, 30.60, -1.98)   # 折返梯最高一级平台
	var bridge_exit: Vector3 = local(-1.60, 30.80, -1.80)  # 补桥出口（已在屋面上）
	check(roof != null, "屋顶走域存在")
	if roof != null:
		var top_support: Vector3 = stair.surface_point(stair_high)
		var bottom_support: Vector3 = stair.surface_point(stair_low)
		check(top_support.is_finite(), "梯顶平台落在梯子走域上")
		check(bottom_support.is_finite(), "梯脚平台落在梯子走域上")
		if bottom_support.is_finite():
			check(absf(bottom_support.y - 4.83) < 0.08,
				"梯脚平台在世界 4.83 m（实际 %.2f m）" % bottom_support.y)
		var roof_support: Vector3 = roof.surface_point(Vector3(bridge_exit.x, roof.surface_y, bridge_exit.z))
		check(roof_support.is_finite(), "补桥出口落在屋顶走域上")
		if top_support.is_finite() and roof_support.is_finite():
			var step := roof_support.y - top_support.y
			check(step > -0.05 and step <= 0.30,
				"梯顶到屋面是一级台阶（%.2f m，agent_max_climb 0.30）" % step)

	# 3. 屋顶 ↔ 梯顶 ↔ 梯脚：真的求一条路。
	var landing: Node3D = quarter.landing_point("main") if quarter.has_method("landing_point") else null
	check(landing != null, "霓虹花园有登岸点")
	if landing != null and quarter.ground_space != null:
		var stand: Vector3 = landing.stand_position()
		for pair in [["梯顶", stair_high], ["梯脚", stair_low]]:
			var goal: Vector3 = stair.surface_point(pair[1])
			var path: Array = quarter.ground_space.route(stand, goal)
			check(path.size() >= 2, "从屋顶能走到%s（路径 %d 点）" % [pair[0], path.size()])
			if path.size() >= 2:
				var last: Vector3 = path[path.size() - 1]
				var off := Vector2(last.x - goal.x, last.z - goal.z).length()
				check(off < 1.0, "%s路径终点落在目标上（偏 %.2f m）" % [pair[0], off])

	# 4. 浮台：水面高度 + 与平台之间没有可走面（这一段只能靠梯子）。
	check(absf(float(float_area.get("surface_y")) - 1.12) < 0.03,
		"浮台面在水面高度（%.2f m）" % float(float_area.get("surface_y")))
	check(not (float_area.get("rects") as Array).is_empty(), "浮台走域非空")
	var float_mid: Vector3 = local(-7.30, 16.69, -2.50)
	var flat: Vector3 = float_area.surface_point(Vector3(float_mid.x, 1.12, float_mid.z))
	check(flat.is_finite(), "浮台中心站得住")
	if quarter.ground_space != null and flat.is_finite():
		var no_path: Array = quarter.ground_space.route(flat, stair.surface_point(stair_low))
		check(no_path.is_empty(), "浮台与平台之间没有可走面（%d 点，应当靠梯子）" % no_path.size())

	# 5. 浮台不能变成水面阻挡，否则船靠不过来、人困在浮台上。
	if quarter.has_method("rebuild_blockers"):
		quarter.rebuild_blockers(1.12, 1.6)
	var blocked := false
	for r in quarter.water_block_rects:
		if (r as Rect2).has_point(Vector2(float_mid.x, float_mid.z)):
			blocked = true
	check(not blocked, "浮台所在水面不挡船")

	# 6. 造型与交互点。
	var foot: Node3D = quarter.get_node_or_null("Visual/StairFoot")
	check(foot != null, "梯脚造型已摆进场景")
	if foot != null:
		check(foot.get_meta("visual_only", false),
			"梯脚标了 visual_only（不参与水面阻挡派生）")
		var meshes := foot.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 18, "浮台有甲板/浮筒/梯子（%d 个网格）" % meshes.size())
		var deck := foot.get_node_or_null("Deck") as MeshInstance3D
		if deck != null and deck.mesh != null:
			var box: AABB = deck.global_transform * deck.mesh.get_aabb()
			check(absf(box.end.y - 1.12) < 0.05, "甲板上表面正好在水面（%.2f m）" % box.end.y)
		var rail := foot.get_node_or_null("Ladder/RailWest") as MeshInstance3D
		if rail != null and rail.mesh != null:
			var rail_box: AABB = rail.global_transform * rail.mesh.get_aabb()
			check(rail_box.position.y < 1.20, "梯脚底在水面（%.2f m）" % rail_box.position.y)
			check(rail_box.end.y > 4.83 and rail_box.end.y < 5.10,
				"梯顶到平台面并留扶手（%.2f m）" % rail_box.end.y)

	var bottom: Node = quarter.get_node_or_null("Ladders/StairFootBottom")
	var top: Node = quarter.get_node_or_null("Ladders/StairFootTop")
	check(bottom != null and top != null, "直梯上下各有一个交互点")
	if bottom != null and top != null:
		check(bottom.can_interact(), "梯脚交互点已接上攀爬系统")
		check(top.can_interact(), "梯顶交互点已接上攀爬系统")
		check(String(top.get("direction")) == "down", "梯顶那个点是往下爬")
		var dy: float = absf(bottom.global_position.y - top.global_position.y)
		check(dy > 3.0 and dy < 4.0, "两点高差是一架梯子（%.2f m）" % dy)
		# Interactor 会滤掉竖直偏移超过 2.5 m 的目标 —— 两端必须各自够得着。
		check(dy > 2.5, "高差超过 2.5 m，正因如此才必须放两个点")
		# 攀爬竖线（= 交互点 XZ）必须在两端的落脚面以内。climb_ladder 只认 Y，
		# 人沿自己脚下那条线升降；线一旦落到平台外，爬上去就会出现在半空。
		var column: Vector3 = bottom.global_position
		var up_support: Vector3 = stair.surface_point(Vector3(column.x, 4.83, column.z))
		check(up_support.is_finite(), "攀爬竖线顶端落在平台走域上")
		if up_support.is_finite():
			check(absf(up_support.y - 4.83) < 0.08,
				"攀爬竖线顶端就是第一级平台（%.2f m）" % up_support.y)
		var down_support: Vector3 = float_area.surface_point(Vector3(column.x, 1.12, column.z))
		check(down_support.is_finite(), "攀爬竖线底端落在浮台上")
		# 造型要贴着这根线，否则看起来像「抓着空气往上爬」。
		var rail_near := foot.get_node_or_null("Ladder") as Node3D if foot != null else null
		if rail_near != null:
			var off := Vector2(rail_near.global_position.x - column.x,
				rail_near.global_position.z - column.z).length()
			check(off < 0.45, "梯子造型贴着攀爬竖线（偏 %.2f m）" % off)

	finish()


func finish() -> void:
	main.queue_free()
	await process_frame
	print("[neon-roof-access] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
