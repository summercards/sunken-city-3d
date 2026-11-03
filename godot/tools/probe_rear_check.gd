extends SceneTree
func _init() -> void:
	call_deferred("run")
func bounds(node: Node) -> AABB:
	var r := AABB()
	var first := true
	for m in node.find_children("*", "VisualInstance3D", true, false):
		if not (m is MeshInstance3D or m is MultiMeshInstance3D): continue
		var p: AABB = m.global_transform * m.get_aabb()
		r = p if first else r.merge(p)
		first = false
	return r
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	var zone = main.get_node("World/Zones/Zone1HomeHarbor")
	var base: AABB = bounds(zone.get_node("Models/太阳能木屋/太阳能木屋-海下基座"))
	var rear: AABB = bounds(main.get_node("World/UnderwaterScenery/rear_slab"))
	var br := Rect2(Vector2(base.position.x, base.position.z), Vector2(base.size.x, base.size.z))
	var rr := Rect2(Vector2(rear.position.x, rear.position.z), Vector2(rear.size.x, rear.size.z))
	print("[rear] base rect=", br, " rear rect=", rr, " intersects=", rr.intersects(br))
	print("[rear] overlap=", rr.intersection(br))
	quit(0)
