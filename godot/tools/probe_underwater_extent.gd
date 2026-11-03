extends SceneTree
## 一次性探针：量出现有水下六栋与阳光房基座的真实世界包围盒，给新街景选落位用。
## 只读，不改场景。
func _init() -> void:
	call_deferred("run")


func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D or mesh is MultiMeshInstance3D):
			continue
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result


func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame
	print("[extent-probe] water_y=", main.water_node.global_position.y)
	var scenery: Node3D = main.get_node("World/UnderwaterScenery")
	for child in scenery.get_children():
		var b: AABB = bounds(child)
		print("[extent-probe] ", child.name, " min=", b.position, " max=", b.end, " size=", b.size)
	var base: Node3D = main.get_node("World/Zones/Zone1HomeHarbor/Models/太阳能木屋/太阳能木屋-海下基座")
	print("[extent-probe] base min=", bounds(base).position, " max=", bounds(base).end)
	print("[extent-probe] --- World children ---")
	for child in main.get_node("World").get_children():
		var b2: AABB = bounds(child)
		if b2.has_volume():
			print("[extent-probe] ", child.name, " min=", b2.position.snappedf(0.1), " max=", b2.end.snappedf(0.1))
	for child in main.get_node("World/Zones").get_children():
		var b3: AABB = bounds(child)
		print("[extent-probe] ZONE ", child.name, " min=", b3.position.snappedf(0.1), " max=", b3.end.snappedf(0.1))
	for child in main.get_node("World/Gameplay").get_children():
		var b4: AABB = bounds(child)
		if b4.has_volume():
			print("[extent-probe] GAMEPLAY ", child.name, " min=", b4.position.snappedf(0.1), " max=", b4.end.snappedf(0.1))
	var water = main.water_node
	print("[extent-probe] water node path=", water.get_path(), " pos=", water.global_position, " aabb=", water.get_aabb() if water.has_method("get_aabb") else "n/a")
	for c in water.find_children("*", "VisualInstance3D", true, false):
		print("[extent-probe] water mesh ", c.name, " aabb=", c.get_aabb())
	print("[extent-probe] camera limits? far=", main.cam.get("distance") if main.cam.get("distance") != null else "n/a")
	print("[extent-probe] done")
	main.queue_free()
	await process_frame
	quit(0)
