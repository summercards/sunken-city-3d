extends SceneTree
## 只读：沿屋顶中线的表面高度剖面。
## 用来确定「草皮/屋面从哪到哪」「女儿墙从哪开始」，而不是靠一个覆盖率数字猜。
##
##   godot --headless --path godot --script res://tools/probe_roof_profile.gd

const STEP := 0.25
var _space: PhysicsDirectSpaceState3D
var _bodies: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ranch: Node3D = (load("res://scenes/facilities/rooftop_ranch.tscn") as PackedScene).instantiate()
	root.add_child(ranch)
	await process_frame
	await physics_frame
	_space = root.world_3d.direct_space_state
	_build(ranch)
	await physics_frame
	await physics_frame
	var origin: Vector3 = ranch.global_position
	print("[roof] ranch origin=%s" % str(origin))
	for spec in [["x", -14.7], ["x", -14.0], ["x", -15.0]]:
		var axis: String = spec[0]
		var fixed: float = spec[1]
		print("[roof] --- 剖面 %s=%s ---" % [axis, str(fixed)])
		_profile(ranch, axis, fixed)
	for body in _bodies:
		(body as Node).queue_free()
	quit(0)


func _profile(ranch: Node3D, axis: String, fixed: float) -> void:
	var runs: Array = []
	var prev := ""
	var start := 0.0
	var t := -30.0
	while t <= 30.0:
		var x := t if axis == "x" else fixed
		var z := fixed if axis == "x" else t
		var hit := _top(x, z)
		var key := "none"
		if hit != Vector3.INF:
			key = "%.2f" % snappedf(hit.y, 0.02)
		if key != prev:
			if prev != "":
				runs.append([prev, snappedf(start, 0.05), snappedf(t - STEP, 0.05)])
			prev = key
			start = t
		t += STEP
	runs.append([prev, snappedf(start, 0.05), snappedf(30.0, 0.05)])
	for run: Array in runs:
		if float(run[2]) - float(run[1]) < STEP * 1.5:
			continue
		print("      y=%-6s %s %.2f → %.2f" % [run[0], axis, run[1], run[2]])


func _top(x: float, z: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -2.0, z))
	q.collide_with_areas = false
	var h: Dictionary = _space.intersect_ray(q)
	if h.is_empty():
		return Vector3.INF
	if absf((h.normal as Vector3).y) < 0.4:
		return Vector3.INF
	return h.position as Vector3


func _build(node: Node) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.is_visible_in_tree() and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var shape := mmi.multimesh.mesh.create_trimesh_shape()
			if shape != null:
				var xforms: Variant = mmi.get_meta("instance_transforms") if mmi.has_meta("instance_transforms") else null
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
		_build(child)


func _attach(shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_transform = xf
	_bodies.append(body)
