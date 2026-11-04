extends SceneTree
## Read-only probe: find the walking deck height of each fire-stair landing /
## roof-entry component as Godot imports it. Reports up-facing triangle area
## grouped by local Y so the boarding deck is measured, not guessed.

const KEYS := ["stair_landing.022", "stair_landing.023", "stair_landing.024", "roof_entry", "roof", "turf_core", "stair_flight.022", "stair_flight.023"]

func _init() -> void:
	call_deferred("run")

func _hist(node: Node, ranch: Node3D) -> Dictionary:
	var inv: Transform3D = ranch.global_transform.affine_inverse()
	var bands := {}
	var planes := {}
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D):
			continue
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var n := idx.size() if idx.size() > 0 else verts.size()
			var i := 0
			while i + 2 < n:
				var a: Vector3 = xf * verts[idx[i] if idx.size() > 0 else i]
				var b: Vector3 = xf * verts[idx[i + 1] if idx.size() > 0 else i + 1]
				var c: Vector3 = xf * verts[idx[i + 2] if idx.size() > 0 else i + 2]
				i += 3
				var normal := (b - a).cross(c - a)
				if absf(normal.y) < 0.000001:
					continue
				if normal.y < 0.0:
					continue  # only up-facing
				var area := normal.length() * 0.5
				var key := snappedf((a.y + b.y + c.y) / 3.0, 0.05)
				bands[key] = float(bands.get(key, 0.0)) + area
				if maxf(a.y, maxf(b.y, c.y)) - minf(a.y, minf(b.y, c.y)) < 0.01:
					var box := AABB(a, Vector3.ZERO).expand(b).expand(c)
					planes[key] = (planes[key] as AABB).merge(box) if planes.has(key) else box
	var rows: Array = bands.keys()
	rows.sort()
	print("PLANES ", node.name, " ", planes)
	var out: Array = []
	for k in rows:
		out.append([k, snappedf(float(bands[k]), 0.01)])
	return {"bands": out.slice(maxi(0, out.size() - 8)), "top": rows[rows.size() - 1] if rows.size() > 0 else null}

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	var ranch: Node3D = main._zone_nodes["rooftop_ranch"]
	await process_frame
	await process_frame
	var models: Node = ranch.get_node("Models")
	print("RANCH_ROOT_Y ", ranch.global_transform.origin.y)
	for child in models.get_children():
		var name := String(child.name)
		var hit := false
		for key in KEYS:
			if name.ends_with(key):
				hit = true
				break
		if not hit:
			continue
		var info := _hist(child, ranch)
		print("DECK ", name, " top=", info["top"], " bands=", JSON.stringify(info["bands"]))
	# landing marker + walk area info as authored
	var area: Node3D = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access")
	var landing: Node3D = ranch.get_node("WalkAreas/Walk_rooftop_ranch_access/Landing_main")
	print("AREA surface_y=", area.surface_y, " span=", area.span_min, "..", area.span_max, " tris=", area.surface_triangles.size() / 3)
	print("LANDING local=", landing.position, " stand=", landing.global_position)
	print("BOATPARK local=", landing.get_node("BoatPark").position, " world=", landing.get_node("BoatPark").global_position)
	print("DOCKEDGE world=", landing.get_node("DockEdge").global_position)
	quit(0)
