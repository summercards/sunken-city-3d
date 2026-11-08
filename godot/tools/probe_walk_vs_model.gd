extends SceneTree
## 只读探针：「声明出来的可走面」与「模型真实表面」差多少。
##
## 存在的理由：WalkArea 的 surface_y / rects / surface_triangles 是手写或常量算出来的，
## 模型换了它们不会跟着走。这类偏差不会报错、不会崩，只会让角色浮在空中或踩进水里。
##
## 做法：把场景里可见网格临时建成三角碰撞（只在本进程内存里），
## 在可走面覆盖的 XZ 栅格上向下打射线，比较「抬明的站立高度」与「真实命中高度」。
##
##   godot --headless --path godot --script res://tools/probe_walk_vs_model.gd -- --scene=res://scenes/facilities/rooftop_ranch.tscn
##
## 输出：[walk-model] 每个可走面一行，含覆盖率、平均/最大偏差、最差点坐标。

const SAMPLE := 0.5
## 真实命中高度与声明高度差超过这个就算「不一致」。
const TOLERANCE := 0.15
## 允许穿过的表面朝上判定（法线 Y）。
const NORMAL_MIN := 0.45

var _space: PhysicsDirectSpaceState3D
var _bodies: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_path := "res://scenes/facilities/rooftop_ranch.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.substr(8)
	var packed: Variant = load(scene_path)
	if packed == null:
		print("[walk-model] FAIL 场景加载失败 %s" % scene_path)
		quit(1)
		return
	var scene: Node3D = (packed as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	_space = root.world_3d.direct_space_state
	_build_collision(scene)
	await physics_frame
	await physics_frame
	_report(scene_path, scene)
	for body in _bodies:
		(body as Node).queue_free()
	quit(0)


## 给可见网格建临时三角碰撞。MultiMesh 用实例变换逐份建。
func _build_collision(node: Node) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.is_visible_in_tree() and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var shape := mmi.multimesh.mesh.create_trimesh_shape()
			if shape != null:
				var xforms: Variant = mmi.get_meta("instance_transforms", null) \
					if mmi.has_meta("instance_transforms") else null
				for i in mmi.multimesh.instance_count:
					var local: Transform3D = (xforms[i] as Transform3D) \
						if xforms != null and i < (xforms as Array).size() \
						else mmi.multimesh.get_instance_transform(i)
					_attach(shape, mmi.global_transform * local)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			var shape := mi.mesh.create_trimesh_shape()
			if shape != null:
				_attach(shape, mi.global_transform)
	for child in node.get_children():
		_build_collision(child)


func _attach(shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_transform = xf
	_bodies.append(body)


func _report(scene_path: String, scene: Node) -> void:
	var total_over := 0
	var total_under := 0
	var total_ok := 0
	for area in _walk_areas(scene):
		var area_id := str(area.area_id)
		var sy := float(area.surface_y)
		var bound := _bounds(area.surface_triangles)
		if bound.size.x <= 0.0:
			print("[walk-model] %s 无 surface_triangles（旧矩形面），跳过逐格比对" % area_id)
			continue
		var scan := bound.grow(4.0)
		var nx := maxi(1, int(round(scan.size.x / SAMPLE)))
		var nz := maxi(1, int(round(scan.size.z / SAMPLE)))
		var over := []
		var under := []
		var ok := 0
		var dev_sum := 0.0
		var dev_max := 0.0
		var worst_at := Vector3.ZERO
		for j in nz:
			for i in nx:
				var x := scan.position.x + (float(i) + 0.5) * SAMPLE
				var z := scan.position.z + (float(j) + 0.5) * SAMPLE
				var declared: Vector3 = area.surface_point(Vector3(x, sy, z))
				var has_declared := declared.is_finite()
				var top := _surface_top(x, sy, z)
				var has_model := top != Vector3.INF
				if has_declared and has_model:
					var dev := absf(top.y - declared.y)
					dev_sum += dev
					if dev > dev_max:
						dev_max = dev
						worst_at = Vector3(x, declared.y, z)
					if dev > TOLERANCE:
						over.append([snappedf(x, 0.1), snappedf(z, 0.1),
							snappedf(declared.y, 0.01), snappedf(top.y, 0.01)])
					else:
						ok += 1
				elif has_declared:
					over.append([snappedf(x, 0.1), snappedf(z, 0.1), snappedf(declared.y, 0.01), 0.0])
				elif has_model and absf(top.y - sy) <= 0.6:
					under.append([snappedf(x, 0.1), snappedf(z, 0.1), snappedf(top.y, 0.01)])
		total_over += over.size()
		total_under += under.size()
		total_ok += ok
		print("[walk-model] %s ok=%d over=%d under=%d mean_dev=%.3f max_dev=%.3f surface_y=%.3f worst=(%.2f,%.2f)" % [
			area_id, ok, over.size(), under.size(),
			dev_sum / float(maxi(1, ok + over.size())), dev_max, sy, worst_at.x, worst_at.z])
		if not over.is_empty():
			print("     %s 声明有、模型不符 %d 格 例[x,z,声明Y,实测Y]:%s" % [
				area_id, over.size(), JSON.stringify(over.slice(0, 10))])
		if not under.is_empty():
			print("     %s 模型有、未声明 %d 格 例[x,z,实测Y]:%s" % [
				area_id, under.size(), JSON.stringify(under.slice(0, 10))])
	print("[walk-model] summary scene=%s ok=%d over=%d under=%d tolerance=%.2f" % [
		scene_path, total_ok, total_over, total_under, TOLERANCE])


## 该 XZ 处、声明高度附近最高的朝上表面。
func _surface_top(x: float, declared_y: float, z: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, declared_y + 6.0, z), Vector3(x, declared_y - 6.0, z))
	q.collide_with_areas = false
	var h: Dictionary = _space.intersect_ray(q)
	if h.is_empty():
		return Vector3.INF
	if absf((h.normal as Vector3).y) < NORMAL_MIN:
		return Vector3.INF
	return h.position as Vector3


func _ray(x: float, declared_y: float, z: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, declared_y + 2.0, z), Vector3(x, declared_y - 2.0, z))
	q.collide_with_areas = false
	var h: Dictionary = _space.intersect_ray(q)
	if h.is_empty():
		return Vector3.INF
	if absf((h.normal as Vector3).y) < NORMAL_MIN:
		return Vector3.INF
	return h.position as Vector3


func _walk_areas(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_method("surface_faces") and n.has_method("outlines") and "surface_triangles" in n:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB()
	var first := true
	for p in points:
		box = AABB(p, Vector3.ZERO) if first else box.expand(p)
		first = false
	return box
