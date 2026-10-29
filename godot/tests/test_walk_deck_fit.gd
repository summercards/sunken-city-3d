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

	# 1) 主人截图圈出的两处：栈桥左缘外侧、右缘外侧。都不许再是可行走面。
	check(not area.contains_world(0.20, 14.00), "栈桥左缘外 x=0.20 z=14.0 不可走")
	check(not area.contains_world(0.30, 16.50), "栈桥左缘外 x=0.30 z=16.5 不可走")
	check(not area.contains_world(6.30, 14.00), "栈桥右缘外 x=6.30 z=14.0 不可走")
	check(not area.contains_world(3.00, 18.20), "栈桥末端外 x=3.00 z=18.2 不可走")

	# 2) 栈桥本身照旧能走：左右各留 0.25 m 内缩，末端内缩 0.1 m。
	check(area.contains_world(0.90, 14.00), "栈桥左缘内 x=0.90 z=14.0 可走")
	check(area.contains_world(5.50, 16.50), "栈桥右缘内 x=5.50 z=16.5 可走")
	check(area.contains_world(3.00, 17.80), "栈桥末端内 x=3.00 z=17.8 可走")
	# 栈桥与主甲板的接缝必须连通，否则从船舱走不到泊位。
	check(area.contains_world(3.00, 12.20), "接缝 x=3.00 z=12.2 可走")
	check(area.contains_world(3.00, 12.95), "接缝 x=3.00 z=12.95 可走")

	# 3) 上岸站立点必须在行走区内 —— 矩形收窄不能把泊位本身切掉。
	for landing in zone.landing_points():
		if landing.ground() != area:
			continue
		var stand: Vector3 = landing.stand_position()
		check(area.contains_world(stand.x, stand.z),
			"泊位站立点 %s (%.2f, %.2f) 在行走区内" % [landing.landing_label, stand.x, stand.z])

	# 4) 甲板上的固定物件仍在行走区内（拾取/交互依赖站得住）。
	check(area.contains_world(3.00, 14.60), "出货箱位置 x=3.00 z=14.6 可走")

	print("[walk-deck-fit] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
