extends SceneTree
## One-time Terrain3D authoring pass, never attached to the running city.
const REPORT := "res://outputs/seabed-authoring.json"
var checks := 0
var failures: Array[String] = []
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		printerr("FAIL ", text)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	print("TRIANGLE_API ", ClassDB.class_get_method_list("TriangleMesh"))
	check(ClassDB.class_exists("Terrain3D"), "Terrain3D native extension loaded")
	if ClassDB.class_exists("Terrain3D"):
		var props: Array = ClassDB.class_get_property_list("Terrain3D")
		var wanted: Array = []
		for prop in props:
			var name := String(prop.get("name", ""))
			if name in ["data_directory", "data", "material", "collision_mode", "region_size", "vertex_spacing", "cast_shadows"]:
				wanted.append(prop)
		var methods: Array = ClassDB.class_get_method_list("Terrain3DData")
		var data_methods: Array = []
		for method in methods:
			var name := String(method.get("name", ""))
			if name in ["import_images", "update_maps", "save_directory", "add_region_blank", "set_height", "get_height"]:
				data_methods.append(method)
		print("TERRAIN_PROPS ", wanted)
		print("DATA_METHODS ", data_methods)
	DirAccess.make_dir_recursive_absolute("res://outputs")
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures.size()}, "\t"))
	f.close()
	print("[seabed-authoring] ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
