extends SceneTree
## Dump each ranch component's surface → semantic material role mapping.
## The GLB names carry SEA_MATTE / SEA_METAL / SEA_GLOSS / SEA_EMISSION;
## we read them once and write the mapping to JSON so the .tscn files can
## serialize a palette override instead of relying on a white import default.

const KEYS := ["matte", "metal", "gloss", "emission"]

func _init() -> void:
	call_deferred("run")

func _role_of(m: Material) -> String:
	if m == null:
		return "matte"
	var name := m.resource_name.to_upper()
	for key in KEYS:
		if name.contains("SEA_" + key.to_upper()):
			return key
	return "matte"

func run() -> void:
	var dir := DirAccess.open("res://assets/models/facilities/rooftop_ranch/components")
	var out := {}
	var count := 0
	for key in dir.get_directories():
		var path := "res://assets/models/facilities/rooftop_ranch/components/%s/%s.glb" % [key, key]
		if not ResourceLoader.exists(path):
			print("MISSING ", path)
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			print("LOADFAIL ", path)
			continue
		var inst: Node = packed.instantiate()
		var rows: Array = []
		for mesh in inst.find_children("*", "VisualInstance3D", true, false):
			if not (mesh is MeshInstance3D):
				continue
			var mi: MeshInstance3D = mesh
			if mi.mesh == null:
				continue
			# 只记录真正的网格节点路径，组件根通常就是它。
			var rel := String(inst.get_path_to(mi))
			for s in mi.mesh.get_surface_count():
				rows.append({"node": rel, "surface": s, "role": _role_of(mi.mesh.surface_get_material(s)),
					"name": mi.mesh.surface_get_material(s).resource_name if mi.mesh.surface_get_material(s) != null else ""})
		out[key] = rows
		count += 1
		inst.free()
	var report := {"components": count, "map": out}
	var f := FileAccess.open("res://outputs/ranch_material_map.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("MAP components=", count, " surfaces=", JSON.stringify(out).count("surface"))
	quit(0)
