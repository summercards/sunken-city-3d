extends SceneTree
## SEA-MOVE-R01：码头可行走矩形不得越过栈桥甲板。
##
## 走路不走物理碰撞 —— 站得住是因为 WalkArea.surface_y 把脚贴到那个高度。
## 所以「矩形越过甲板边缘」不会报错、不会崩，人物只是站在水面上。
## 这个专项把两处实测过的越界点钉成断言：它们必须落在行走区之外，
## 而码头本身、泊位站立点、菜箱、出货箱所在的点必须仍然可走。
##
## 数值来源：godot/tools/probe_deck_edges.gd（0.25 m 栅格 + 3×3 抖动）实测栈桥甲板
## 边界 x 0.60…5.85、z 12.90…17.90；改款前的矩形是 x 0.0…6.5、z 11.5…18.0。

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


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var zone: Node3D = main._zone_nodes.get("zone1", null)
	if zone == null:
		printerr("FAIL zone1 未加载")
		quit(1)
		return
	var area: Node3D = null
	for a in zone.walk_areas:
		if str(a.area_id) == "zone1_home_dock":
			area = a
			break
	if area == null:
		printerr("FAIL 找不到 zone1_home_dock")
		quit(1)
		return

	# 1) 主人截图圈出的两处：栈桥栏杆绳外侧。都不许是可行走面。
	#
	# 栈桥两侧各有一道栏杆绳（`bridge_rope` 实例），实测世界坐标：
	#   西侧绳 x 0.833…0.936，东侧绳 x 5.197…5.300，
	#   根部端头 z 11.117…11.853，末端端头 z 17.172…17.908，高出甲板 0.48…1.06 m。
	# 所以可行走的上限是「绳的内沿」而不是「甲板边」——
	# 早先按甲板边放矩形（x 0.6…5.8），人整个站在绳子外面走，看着像穿绳。
	check(not area.contains_world(0.60, 14.00), "西绳外 x=0.60 z=14.0 不可走")
	check(not area.contains_world(0.85, 16.50), "西绳内沿上 x=0.85 z=16.5 不可走")
	check(not area.contains_world(5.60, 14.00), "东绳外 x=5.60 z=14.0 不可走")
	check(not area.contains_world(5.30, 16.50), "东绳内沿上 x=5.30 z=16.5 不可走")
	check(not area.contains_world(3.00, 18.20), "末端绳外 x=3.00 z=18.2 不可走")

	# 2) 绳围出来的内部照旧能走。
	check(area.contains_world(1.30, 14.00), "西绳内 x=1.30 z=14.0 可走")
	check(area.contains_world(4.80, 16.50), "东绳内 x=4.80 z=16.5 可走")
	check(area.contains_world(3.00, 17.00), "末端绳内 x=3.00 z=17.0 可走")
	# 栈桥与主甲板的接缝必须连通，否则从船舱走不到泊位。
	check(area.contains_world(3.00, 12.20), "接缝 x=3.00 z=12.2 可走")

	# 3) 上岸站立点必须在行走区内 —— 矩形收窄不能把泊位本身切掉。
	for landing in zone.landing_points():
		if landing.ground() != area:
			continue
		var stand: Vector3 = landing.stand_position()
		check(area.contains_world(stand.x, stand.z),
			"泊位站立点 %s (%.2f, %.2f) 在行走区内" % [landing.landing_label, stand.x, stand.z])

	# 4) 甲板上的固定物件仍在行走区内（拾取/交互依赖站得住）。
	check(area.contains_world(3.00, 14.60), "出货箱位置 x=3.00 z=14.6 可走")

	# 5) 站位点必须按身影内收：脚在甲板上不等于人没进水。
	#    角色是斜俯视看到的一整只人，帽檐半径 0.54 m（probe_player_radius.gd 实测）。
	#    点甲板边缘时圆心若只夹到矩形边界，帽檐和肩膀会压在水面上。
	check(area.body_radius >= 0.36, "身影半径已声明（%.2f m）" % area.body_radius)
	var edge_points := [
		["栈桥东缘", Vector2(6.60, 14.20)],
		["栈桥西缘", Vector2(0.00, 14.20)],
		["栈桥末端", Vector2(3.00, 18.30)],
		["主甲板东沿", Vector2(9.90, 9.00)],
	]
	for item in edge_points:
		var want: Vector2 = item[1]
		var got: Vector2 = area.clamp_point(want.x, want.y)
		var local: Vector3 = area.to_local(Vector3(got.x, 0, got.y))
		var free: float = area.clearance(local.x, local.z)
		check(free + 0.02 >= area.body_radius,
			"%s 站位身影净空 %.2f ≥ %.2f（点 (%.2f,%.2f) → (%.2f,%.2f)）" % [
				item[0], free, area.body_radius, want.x, want.y, got.x, got.y])

	print("[walk-deck-fit] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
