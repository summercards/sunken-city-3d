extends SceneTree
## 临时诊断：把家园小屋子树里的节点类型和 mesh 情况打出来。
func _init() -> void:
	call_deferred("run")


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 12:
		await process_frame
	var cabin: Node3D = null
	for node in main.find_children("*", "Node3D", true, false):
		if node.name == "太阳能木屋":
			cabin = node
			break
	print("[cabin-dump] found=", cabin)
	if cabin != null:
		_dump(cabin, 0, 0)
		# 直接用 MeshInstance3D 类型统计
		var meshes := cabin.find_children("*", "MeshInstance3D", true, false)
		print("[cabin-dump] MeshInstance3D count=", meshes.size())
		var all := cabin.find_children("*", "", true, false)
		print("[cabin-dump] all descendants=", all.size())
	main.queue_free()
	await process_frame
	quit(0)


func _dump(node: Node, depth: int, count: int) -> void:
	if depth > 6 or count > 60:
		return
	print("[cabin-dump] ", "  ".repeat(depth), node.name, "  <", node.get_class(), ">")
	var i := 0
	for child in node.get_children():
		_dump(child, depth + 1, count + i)
		i += 1
