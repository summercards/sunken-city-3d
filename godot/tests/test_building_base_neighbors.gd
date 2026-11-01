extends SceneTree
## SEA-BUILDING-R25：固定浮台自己的水下底座不能挡住扩建。
##
## 现场症状（2026-11-01 反馈）：浅水养殖台四面的新木板全部报「这里有既有建筑」，
## 只剩原本已经拼好的一侧能接。原因不是真的有人家的建筑 —— 是平台自己的
## 水下底座在水面线处生成的阻挡矩形跟平台轮廓一样大，而木板网格
## 2.15×2.575 与平台 6.45×5.15 不同步，贴着平台接的格子必然重叠约 0.2 米。
##
## 这条测试量的是行为：四边都能接、原有平台仍然不能覆盖、别的区块的阻挡照旧在。
var checks := 0
var failures := 0
var main
var economy
const Catalog = preload("res://src/building/building_catalog.gd")

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.title_camera.begin(main.cam)
	main.title_camera.finish(main.cam)
	main._enter_game()
	# 站到平台中北部，船从泊位开走：泊位旁那一格本来就因为船停着而不能建。
	main.restore_world_state({"zone":"zone5","landing":"main","mode":0,"player":[22.0,1.48,16.0],"far_sea":false})
	main.boat.place_at(Vector3(40.0, main.WATER_LEVEL, 40.0), 0.0)
	for i in 8: await process_frame
	economy = root.get_node("Economy")
	# 玩家的真实存档里可能已经有板子：这条只测「贴着固定平台能不能接」，
	# 所以先把布局清成新局状态（正式校验器照跑，不是绕过存档）。
	check(preload("res://src/building/building_service.gd").validate_snapshot(
		preload("res://src/building/building_service.gd").empty_snapshot()) == "", "empty layout fixture is valid")
	main.building.from_dict(preload("res://src/building/building_service.gd").empty_snapshot())
	main.building_world.sync()
	for i in 4: await process_frame
	economy.inventory.set_count("wood", 120)
	check(main.building.query().is_empty(), "aqua platform starts with no built boards")

	# --- 底座的阻挡已经不再算「别人家的建筑」---
	var base := Rect2(Vector2(Catalog.ORIGIN.x, Catalog.ORIGIN.z) + Catalog.BASE.position, Catalog.BASE.size)
	var overlapping := 0
	for shape in main._construction_obstacles():
		if main._shape_overlaps(shape, base): overlapping += 1
	check(overlapping == 0, "no obstacle overlaps the fixed platform footprint any more")
	var others := 0
	for zone in main._zone_nodes.values():
		if zone.zone_id == "zone5": continue
		if not zone.walk_areas.is_empty(): others += 1
	check(others >= 3, "other zones still contribute their own ground rects")

	# --- 四面都能接（泊位那一侧按设计保留上下船通道，单独断言）---
	var ring := [Vector2i(0,-1), Vector2i(1,-1), Vector2i(2,-1),
		Vector2i(0,2), Vector2i(1,2), Vector2i(2,2),
		Vector2i(3,0), Vector2i(3,1)]
	for cell: Vector2i in ring:
		var request := {"kind":"deck","x":cell.x,"z":cell.y,"px":0.0,"pz":0.0,"turn":0,"support":""}
		var reason: String = main.building.can_place(request)
		check(reason == "", "cell %s can join the platform: %s" % [str(cell), reason])
	# 西侧是泊位与上下船通道：这里必须继续拒绝，但原因要说得清是泊位，
	# 而不是「这里有既有建筑」——后者会让玩家以为是底座挡的。
	for cell: Vector2i in [Vector2i(-1,0), Vector2i(-1,1)]:
		var request := {"kind":"deck","x":cell.x,"z":cell.y,"px":0.0,"pz":0.0,"turn":0,"support":""}
		var reason: String = main.building.can_place(request)
		check(reason.contains("泊位") or reason.contains("通道"), "berth side stays closed with a berth reason: " + reason)

	# --- 原有平台本身仍然不能覆盖 ---
	for cell: Vector2i in [Vector2i(0,0), Vector2i(1,0), Vector2i(2,1)]:
		var request := {"kind":"deck","x":cell.x,"z":cell.y,"px":0.0,"pz":0.0,"turn":0,"support":""}
		check(main.building.can_place(request) != "", "authored platform cell %s is still protected" % str(cell))

	# --- 真的建出来：接出的板子成为可行走面 ---
	var built: Array[String] = []
	for cell: Vector2i in [Vector2i(1,-1), Vector2i(1,2)]:
		var result: Dictionary = main.building.begin({"kind":"deck","x":cell.x,"z":cell.y,"px":0.0,"pz":0.0,"turn":0,"support":""})
		check(result.get("ok", false), "board %s really builds: %s" % [str(cell), str(result.get("reason",""))])
		if result.get("ok", false): built.append(str(result.id))
	for i in 4: main.building.tick(1.5)
	for id in built:
		var row: Dictionary = main.building.row(id)
		check(float(row.get("left", 1.0)) == 0.0, "board %s finishes its timer" % id)
	var walk: Array = main.building_world.walk_rects(main.building.query())
	check(walk.size() > 1, "new boards join the walkable union")
	var north := Vector3(21.5, 1.48, 11.9)
	var south := Vector3(21.5, 1.48, 19.9)
	check(main._zone_nodes.zone5.area_at(north, 0.7) != null, "north board is walkable")
	check(main._zone_nodes.zone5.area_at(south, 0.7) != null, "south board is walkable")

	# --- 存档往返：接出来的板子还在 ---
	var written: Dictionary = preload("res://src/save/save_game.gd").write("user://join-north-south.json", main)
	check(written.get("ok", false), "save accepts boards joined on both long sides")
	var saved: Dictionary = preload("res://src/save/save_game.gd").read("user://join-north-south.json")
	check(preload("res://src/save/save_game.gd").restore(main, saved.snapshot).get("ok", false), "restore accepts the joined layout")
	for id in built:
		check(not main.building.row(id).is_empty(), "restored layout still contains " + id)

	main.queue_free()
	await process_frame
	print("[base-neighbors] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
