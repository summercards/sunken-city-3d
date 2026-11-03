extends SceneTree
## 验证十栋在 main.tscn 里是不是「真正独立的十个场景实例」。
## 不看文本，看运行时对象：场景来源、网格资源、契约脚本实例、互不影响性。

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame

	var street: Node3D = main.get_node_or_null("World/UnderwaterStreet")
	if street == null:
		print("[indep] FAIL: main.tscn 里找不到 World/UnderwaterStreet")
		quit(1)
		return

	var kids := street.get_children()
	print("[indep] children=", kids.size())

	var scenes := {}
	var meshes := {}
	var scripts := {}
	var positions := {}
	for c in kids:
		var packed: PackedScene = load(c.scene_file_path)
		var mesh_inst := _first_mesh(c)
		var mesh_res: Mesh = mesh_inst.mesh if mesh_inst else null
		print("[indep] ", c.name, " scene=", c.scene_file_path.get_file(),
			" mesh=", mesh_res.resource_path.get_file() if mesh_res else "-",
			" tris=", _tris(mesh_res),
			" script=", (c.get_script().resource_path.get_file() if c.get_script() else "-"),
			" pos=", c.global_position.snappedf(0.01))
		scenes[c.scene_file_path] = scenes.get(c.scene_file_path, 0) + 1
		if mesh_res:
			meshes[mesh_res.resource_path] = meshes.get(mesh_res.resource_path, 0) + 1
		if c.get_script():
			scripts[c.get_script().resource_path] = scripts.get(c.get_script().resource_path, 0) + 1
		positions[c.global_position.snappedf(0.01)] = positions.get(c.global_position.snappedf(0.01), 0) + 1

	print("[indep] 不同场景来源=", scenes.size(), " 不同网格资源=", meshes.size(),
		" 不同契约脚本=", scripts.size(), " 不同位置=", positions.size())

	# 独立性实测：挪动第一栋，其余九栋必须原地不动
	var target: Node3D = kids[0]
	var before := {}
	for c in kids:
		before[c.name] = c.global_position
	target.global_position += Vector3(5, 0, 0)
	await process_frame
	var moved := 0
	for c in kids:
		if c.name != target.name and not c.global_position.is_equal_approx(before[c.name]):
			moved += 1
	target.global_position = before[target.name]
	print("[indep] 移动一栋后被带着动的其它栋数=", moved)

	# 逐个是否都可寻址 + 有自己的 asset_id
	var ids := {}
	for c in kids:
		var aid = c.get("asset_id")
		ids[str(aid)] = ids.get(str(aid), 0) + 1
	print("[indep] 不同 asset_id 数=", ids.size())

	main.queue_free()
	await process_frame
	quit(0)


func _first_mesh(n: Node) -> MeshInstance3D:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		if m.mesh:
			return m
	return null


func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var total := 0
	for s in m.get_surface_count():
		var a: Array = m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		total += (idx.size() / 3) if idx != null else a[Mesh.ARRAY_VERTEX].size() / 3
	return total
