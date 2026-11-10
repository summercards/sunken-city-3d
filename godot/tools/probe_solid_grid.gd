extends SceneTree
## 只读：在给定高度上，把某片区域「网格包围盒是否覆盖该点」打成 ASCII 图。
## 用来快速看清水面高度上到底哪里是实体（AABB 粗判，够用来找落脚点）。
##
##   --script res://tools/probe_solid_grid.gd -- --y=1.12 --rect=95,60,125,90 --step=1

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
	var y := 1.12
	## 采样坐标所在的节点：给了就在它的局部空间里打网格（往旋转过的建筑上挂东西时用）。
	var space: Node3D = null
	var rect := Rect2(95, 60, 30, 30)
	var step := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--y="):
			y = float(arg.substr(4))
		elif arg.begins_with("--rect="):
			var f := arg.substr(7).split(",")
			rect = Rect2(float(f[0]), float(f[1]), float(f[2]), float(f[3]))
		elif arg.begins_with("--step="):
			step = float(arg.substr(7))
		elif arg.begins_with("--space="):
			space = main.get_node_or_null(arg.substr(8)) as Node3D
	var root_node: Node = main
	for arg2 in OS.get_cmdline_user_args():
		if arg2.begins_with("--path="):
			root_node = main.get_node_or_null(arg2.substr(7))
	if root_node == null:
		print("[grid] 找不到节点")
		quit(2)
		return
	var boxes: Array = []
	for mi in root_node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		# 水面 / 海床 / 远景是一整张巨面，包围盒罩住全图，会把每个格子都判成实体。
		if b.size.x * b.size.z > 1500.0:
			continue
		boxes.append(b)
	print("[grid] y=%.2f boxes=%d rect=%s step=%.1f" % [y, boxes.size(), str(rect), step])
	var z := rect.position.y
	while z <= rect.end.y:
		var row := ""
		var x := rect.position.x
		while x <= rect.end.x:
			var hit := false
			var p := Vector3(x, y, z)
			if space != null:
				p = space.to_global(p)
			for b in boxes:
				if (b as AABB).has_point(p):
					hit = true
					break
			row += "#" if hit else "."
			x += step
		print("[grid] z=%7.2f %s" % [z, row])
		z += step
	print("[grid] x from %.1f to %.1f step %.1f" % [rect.position.x, rect.end.x, step])
	quit(0)
