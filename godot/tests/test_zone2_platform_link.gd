extends SceneTree
## SEA-NAV-R21：横滨铁道东西站台必须走得通。
##
## 2026-11-10 体检发现：站台可走面是 10 条手写窄矩形，只盖住真实甲板的 2/3，
## 而且被水断开成 4 个孤岛 —— 玩家在登岸的白色平台上，走不到对面蓝顶楼。
##
## 这一支锁三件事：
##   1. 可走面从模型几何派生，不是手写矩形（模型改版后自动跟随）；
##   2. 东西两块站台之间有真实几何（跳板），不是隐形地面；
##   3. 从登岸点能真的走到东侧站台（走的是 GroundSpace，不是「看着连着」）。

var main: Node
var checks := 0
var failures := 0


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

	var zone: Node3D = main._zone_nodes.get("zone2")
	check(zone != null, "zone2 在主场景里")

	var station: Node3D = area_of(zone, "zone2_station") if zone != null else null
	check(station != null, "zone2_station 走域存在")
	if station != null:
		check(station.has_method("rebuild_derived"), "走域由模型派生（不是手写矩形）")
		var rects: Array = station.get("rects")
		check(rects.size() >= 20, "派生出的可行走矩形 ≥ 20（实际 %d）" % rects.size())
		var sy := float(station.get("surface_y"))
		# 甲板实测 2.65（东）/2.78（西）；旧手写值是 2.60，人会陷进台面 18 厘米。
		check(sy > 2.70 and sy < 2.86, "站立面贴住真实台面（%.2f m）" % sy)

	# 跳板：既要有几何，也要有可走面，两样缺一都只是「看着连着」。
	var gangway: Node3D = zone.get_node_or_null("Gangway") if zone != null else null
	check(gangway != null, "东西站台之间有跳板节点")
	if gangway != null:
		var meshes := gangway.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= 1, "跳板有真实几何（%d 个网格）" % meshes.size())
		var deck := gangway.get_node_or_null("Deck") as MeshInstance3D
		check(deck != null and deck.mesh != null, "跳板板面存在")
		if deck != null and deck.mesh != null:
			# 只量板面：扶手顶在 3.37，拿整棵子树的最大高度会量到栏杆上。
			var box: AABB = deck.global_transform * deck.mesh.get_aabb()
			check(box.end.y > 2.60 and box.end.y < 2.95, "跳板面在站台高度（顶面 %.2f m）" % box.end.y)

	var bridge: Node3D = area_of(zone, "zone2_gangway") if zone != null else null
	check(bridge != null, "跳板有自己的走域")
	if bridge != null:
		check(not (bridge.get("rects") as Array).is_empty(), "跳板走域非空")

	# 真的走一次：从登岸点到东侧站台。
	var landing: Node3D = zone.landing_point("main") if zone != null else null
	check(landing != null, "zone2 有登岸点")
	if landing != null and zone.ground_space != null:
		var start: Vector3 = landing.stand_position()
		var east := Vector3(-26.0, float(station.get("surface_y")), -21.5)
		var east_area: Node3D = zone.ground_space.area_at(east, 0.6)
		check(east_area != null, "东侧站台落在可走面上")
		var path: Array = zone.ground_space.route(start, east)
		check(path.size() >= 2, "登岸点能走到东侧站台（路径 %d 点）" % path.size())
		if path.size() >= 2:
			var last: Vector3 = path[path.size() - 1]
			check(Vector2(last.x - east.x, last.z - east.z).length() < 1.5,
				"路径终点落在东侧站台附近（偏 %.2f m）" % Vector2(last.x - east.x, last.z - east.z).length())

	main.queue_free()
	await process_frame
	print("[zone2-link] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
