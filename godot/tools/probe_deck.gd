extends SceneTree
## 甲板扫描：沿世界坐标直线采样，报告每个采样点上方最近的近水平面高度与来源节点。
##
## 用途：给「桥/梯该接在哪里」找真实甲板边缘。只看近水平三角形（|normal.y| >= 0.5），
## 竖直墙面不参与 —— 否则一根立柱就会把整条线判成「有面」。
##
## 用法：
##   godot --path <proj> --script res://tools/probe_deck.gd -- \
##       --zone=zone2 --line=-39,-21,-22,-21 --step=0.25 --band=-2,8 --top=2

var main: Node
var _cache := {}


func _init() -> void:
	call_deferred("run")


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	if "_autosave_on" in main:
		main.set("_autosave_on", false)
	for i in 30:
		await process_frame

	print("[deck] argv=", OS.get_cmdline_user_args())
	var zone_id := "zone2"
	var lines: Array = []
	var step := 0.25
	var band := Vector2(-2.0, 8.0)
	var top := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):
			zone_id = arg.substr(7)
		elif arg.begins_with("--line="):
			var nums: Array = []
			for seg in arg.substr(7).split(";"):
				for f in seg.split(","):
					nums.append(float(f))
			var i := 0
			while i + 3 < nums.size():
				lines.append(Vector4(nums[i], nums[i + 1], nums[i + 2], nums[i + 3]))
				i += 4
		elif arg.begins_with("--step="):
			step = float(arg.substr(7))
		elif arg.begins_with("--band="):
			var b := arg.substr(7).split(",")
			band = Vector2(float(b[0]), float(b[1]))
		elif arg.begins_with("--top="):
			top = int(arg.substr(6))

	var zones: Node = main.get_node_or_null("World/Zones")
	if zones == null:
		print("[deck] 没有 World/Zones")
		quit(2)
		return
	var zone: Node3D = null
	for child in zones.get_children():
		if str(child.get("zone_id")) == zone_id:
			zone = child
			break
	if zone == null:
		print("[deck] 找不到区块 %s" % zone_id)
		quit(2)
		return

	var meshes: Array = []
	_gather(zone, meshes)
	print("[deck] zone=%s meshes=%d lines=%d" % [zone_id, meshes.size(), lines.size()])

	for line in lines:
		var a := Vector2(line.x, line.y)
		var b := Vector2(line.z, line.w)
		var length := a.distance_to(b)
		var count := int(ceil(length / step))
		print("[deck] ---- line (%.2f,%.2f) -> (%.2f,%.2f) step=%.2f" % [a.x, a.y, b.x, b.y, step])
		for i in count + 1:
			var t := float(i) / float(maxi(1, count))
			var p := a.lerp(b, t)
			var hits := _column(meshes, p, band, top)
			var desc := []
			for h in hits:
				desc.append("%.2f@%s" % [h[1], h[0]])
			print("[deck] %.2f,%.2f %s" % [p.x, p.y, " ".join(desc) if not desc.is_empty() else "-"])
	quit(0)


func _column(meshes: Array, p: Vector2, band: Vector2, top: int) -> Array:
	var hits: Array = []
	for node in meshes:
		if not is_instance_valid(node):
			continue
		var mi := node as Node3D
		var mesh: Mesh = null
		var xf: Transform3D = mi.global_transform
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh if (node as MultiMeshInstance3D).multimesh != null else null
		if mesh == null:
			continue
		var key: int = node.get_instance_id()
		var arrays: Array = _cache.get(key, [])
		if arrays.is_empty():
			arrays = _arrays_of(mesh)
			_cache[key] = arrays
		var placements: Array = [xf]
		if node is MultiMeshInstance3D:
			placements = []
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			for inst in mm.instance_count:
				placements.append(xf * mm.get_instance_transform(inst))
		for place in placements:
			for s in arrays.size():
				var a: PackedVector3Array = arrays[s][0]
				var idx: PackedInt32Array = arrays[s][1]
				var n := idx.size()
				var i := 0
				while i + 2 < n:
					var va: Vector3 = place * a[idx[i]]
					var vb: Vector3 = place * a[idx[i + 1]]
					var vc: Vector3 = place * a[idx[i + 2]]
					i += 3
					var nrm := (vb - va).cross(vc - va)
					if nrm.length_squared() < 1e-12:
						continue
					if absf(nrm.normalized().y) < 0.5:
						continue
					var area2 := (vb.x - va.x) * (vc.z - va.z) - (vc.x - va.x) * (vb.z - va.z)
					if absf(area2) < 1e-9:
						continue
					var w0 := ((vb.x - p.x) * (vc.z - p.y) - (vc.x - p.x) * (vb.z - p.y)) / area2
					var w1 := ((vc.x - p.x) * (va.z - p.y) - (va.x - p.x) * (vc.z - p.y)) / area2
					var w2 := 1.0 - w0 - w1
					if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
						continue
					var y := (va.y + vb.y + vc.y) / 3.0
					if y < band.x or y > band.y:
						continue
					hits.append([str(main.get_path_to(mi)), y])
	hits.sort_custom(func(p1, p2): return p1[1] > p2[1])
	return hits.slice(0, top)


func _arrays_of(mesh: Mesh) -> Array:
	var out: Array = []
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts == null:
			continue
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if indices != null:
			idx = indices
		else:
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		out.append([verts, idx])
	return out


func _gather(node: Node, out_list: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D:
			out_list.append(child)
		_gather(child, out_list)
