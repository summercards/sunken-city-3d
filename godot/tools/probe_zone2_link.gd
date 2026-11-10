extends SceneTree
## 临时探针：给 zone2 登岸点找一块真正落在派生走域上的站立点，
## 并量三块走域之间的实际路由。

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	for i in 24:
		await process_frame
	var zone: Node3D = main._zone_nodes.get("zone2")
	var gs = zone.ground_space
	var landing: Node3D = zone.landing_point("main")
	var data: Dictionary = landing.data()
	print("[p] stand=", data.get("landStand"), " park=", data.get("boatPark"), " edge=", data.get("dockEdge"))
	var west: Node3D = null
	for child in zone.get_node("WalkAreas").get_children():
		if str(child.get("area_id")) == "zone2_station":
			west = child
	var sy := float(west.get("surface_y"))
	print("[p] west sy=%.3f" % sy)
	# 在登岸点周围 3 米里找落在西侧走域上的格子
	var base := Vector3(-32.7, sy, -18.3)
	var found: Array = []
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			var p := base + Vector3(float(dx) * 0.25, 0.0, float(dz) * 0.25)
			if not west.contains_position(p, 0.05):
				continue
			found.append([p, west.clearance(p.x, p.z)])
	found.sort_custom(func(a, b): return a[1] > b[1])
	print("[p] cells=%d" % found.size())
	for i in mini(8, found.size()):
		print("[p] cand %s clr=%.2f" % [str(found[i][0]), float(found[i][1])])
	if not found.is_empty():
		var start: Vector3 = found[0][0]
		for k in {"gangway": Vector3(-30.3, 2.78, -21.0), "east_edge": Vector3(-29.6, 2.70, -21.0),
				"east_far": Vector3(-26.0, 2.70, -21.5)}:
			var p: Vector3 = {"gangway": Vector3(-30.3, 2.78, -21.0), "east_edge": Vector3(-29.6, 2.70, -21.0),
				"east_far": Vector3(-26.0, 2.70, -21.5)}[k]
			print("[p] route %-10s -> %d points" % [k, gs.route(start, p).size()])
	quit(0)
