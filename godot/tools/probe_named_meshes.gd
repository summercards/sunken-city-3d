extends SceneTree
## 只读：按名字过滤，列出某节点下每个网格的世界包围盒（按最低点排序）。
## 用来在真实模型里找「外挂楼梯 / 女儿墙 / 楼板」这类构件的准确位置。
##
##   --script res://tools/probe_named_meshes.gd -- --path=... --filter=stair

var main: Node


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	for i in 24:
		await process_frame
	var path := "World/SeaStructures/neon_garden_quarter/Visual/LeftBuilding"
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			path = arg.substr(7)
		elif arg.begins_with("--filter="):
			filter = arg.substr(9).to_lower()
	var node: Node3D = main.get_node_or_null(path) as Node3D
	if node == null:
		print("[named] 找不到 ", path)
		quit(2)
		return
	var rows: Array = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		if filter != "" and not str(m.name).to_lower().contains(filter):
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		rows.append([b.position.y, str(m.name), b])
	rows.sort_custom(func(a, c): return a[0] < c[0])
	print("[named] %s filter='%s' count=%d" % [path, filter, rows.size()])
	for r in rows.slice(0, 60):
		var b: AABB = r[2]
		print("[named] y %7.2f..%7.2f  x %7.2f..%7.2f  z %7.2f..%7.2f  %s" % [
			b.position.y, b.end.y, b.position.x, b.end.x, b.position.z, b.end.z, str(r[1])])
	quit(0)
