extends SceneTree
## 只读探针：输出某块区域的「最高实体高度」栅格，用来对照甲板、走道与阻挡。
##
## 用法（必须真实渲染，不能 --headless）：
##   godot --path godot --script res://tools/probe_deck_map.gd -- --zone=zone1 --x0=-30 --x1=15 --z0=-10 --z1=30 --step=0.5
## 输出一行 [deckmap] + JSON，由 tools/plot_deck_map.py 画图。

const SCENES := {
	"zone1": "res://scenes/zones/zone1_home_harbor.tscn",
	"zone2": "res://scenes/zones/zone2_yokohama_station.tscn",
	"zone3": "res://scenes/zones/zone3_arc_farm.tscn",
	"zone4": "res://scenes/zones/zone4_far_shore.tscn",
	"zone5": "res://scenes/zones/zone5_aqua_platform.tscn",
	"environment": "res://scenes/world/environment.tscn",
}

var _bodies: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var zone_id := str(args.get("zone", "zone1"))
	var x0 := float(args.get("x0", "-30"))
	var x1 := float(args.get("x1", "15"))
	var z0 := float(args.get("z0", "-10"))
	var z1 := float(args.get("z1", "30"))
	var step := float(args.get("step", "0.5"))

	var packed: Variant = load(SCENES.get(zone_id, SCENES["zone1"]))
	var zone: Node3D = (packed as PackedScene).instantiate()
	root.add_child(zone)
	if zone_id != "environment" and zone_id != "zone1":
		# 其余区块的 origin 由 main 设置，探针按 zones.json 补上，便于世界坐标对照。
		var zones: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/data/zones.json"))
		for z in zones:
			if str(z.get("id", "")) == zone_id:
				var o: Array = z.get("origin", [0, 0, 0])
				zone.position = Vector3(float(o[0]), float(o[1]), float(o[2]))
	await process_frame
	await physics_frame
	_build(zone)
	await physics_frame
	await physics_frame

	var space := root.world_3d.direct_space_state
	var cols := int(round((x1 - x0) / step)) + 1
	var rows := int(round((z1 - z0) / step)) + 1
	var grid := []
	for j in rows:
		var row := []
		var z := z0 + float(j) * step
		for i in cols:
			var x := x0 + float(i) * step
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -40.0, z))
			var h: Dictionary = space.intersect_ray(q)
			row.append(snappedf((h.position as Vector3).y, 0.01) if not h.is_empty() else null)
		grid.append(row)
	var out := {"zone": zone_id, "x0": x0, "z0": z0, "step": step, "cols": cols, "rows": rows, "grid": grid}
	for b in _bodies:
		(b as Node).queue_free()
	zone.queue_free()
	print("[deckmap] " + JSON.stringify(out))
	quit(0)


func _build(node: Node) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.is_visible_in_tree() and mmi.multimesh != null:
				var shape: Shape3D = mmi.multimesh.mesh.create_trimesh_shape()
				if shape != null:
					for i in mmi.multimesh.instance_count:
						_attach(shape, mmi.global_transform * mmi.multimesh.get_instance_transform(i))
		elif child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				var shape: Shape3D = mi.mesh.create_trimesh_shape()
				if shape != null:
					_attach(shape, mi.global_transform)
		_build(child)


func _attach(shape: Shape3D, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.global_transform = xf
	root.add_child(body)
	_bodies.append(body)
