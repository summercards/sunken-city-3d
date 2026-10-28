@tool
extends Node3D
## Component GLBs + Collection-style instances; root stays at identity.
@export_file("*.json") var instance_data_path: String = "res://assets/models/facilities/solar_cabin/instances.json"
@export_dir var component_directory: String = "res://scenes/components/solar_cabin"
const Component = preload("res://src/ambient/scene_component.gd")
const MOVABLE = ["pot","square_pot","roof_sofa","coffee_table","table","stool","sofa","vase","umbrella","bottle","cooler","mat","lantern"]
const WINDOWS = ["small_window","tall_window","narrow_window","entry","porch_side"]
const MATERIALS = {
	"Matte": preload("res://assets/materials/solar_cabin/sunny_matte.tres"),
	"Metal": preload("res://assets/materials/solar_cabin/sunny_metal.tres"),
	"Gloss": preload("res://assets/materials/solar_cabin/sunny_gloss.tres"),
	"Emission": preload("res://assets/materials/solar_cabin/sunny_emission.tres")}
@export var module_key: String = ""
## Components promoted to explicit TSCN instances (e.g. the functional dock box).
@export var excluded_components: PackedStringArray = []
var component_meshes := 0
var visual_instances := 0
func _ready() -> void:
	build()
func meshes(root_node: Node) -> Array:
	var out := []
	if root_node is MeshInstance3D: out.append(root_node)
	for c in root_node.get_children(): out.append_array(meshes(c))
	return out
func build() -> void:
	for c in get_children(): c.free()
	component_meshes=0;visual_instances=0
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(instance_data_path))
	var groups := {}
	for index in data.instances.size():
		var entry: Dictionary = data.instances[index].duplicate(true)
		entry["instance_id"] = entry.get("instance_id", "%s/%03d" % [component_directory.get_file(),index])
		if module_key != "" and entry.get("module", "") != module_key: continue
		if entry.component in excluded_components: continue
		if not groups.has(entry.component): groups[entry.component]=[]
		groups[entry.component].append(entry)
	for key in groups:
		var packed: PackedScene=load(component_directory+"/%s.tscn" % key)
		var imported: Node3D=packed.instantiate()
		var entries: Array=groups[key]
		var objects: Array = []
		if entries[0].category == "flora" or key in MOVABLE:
			for entry in entries:
				var object := Component.new()
				object.name = key+"_"+str(entry.instance_id).get_file()
				object.instance_id = entry.instance_id
				object.facility_id = "solar_cabin"
				object.asset_id = entry.asset_id
				object.component_kind = "upgrade_attachment" if entry.category == "flora" else "furnishing"
				object.subcategory = "plants" if entry.category == "flora" else "movable"
				object.movable = entry.category != "flora"
				object.unlock_level = int(entry.get("unlock_level",0))
				object.attachment_slot = str(entry.get("module",module_key))
				object.set_meta("visual_only",true)
				var a: Array = entry.transform
				object.position = Vector3(a[0][3],a[1][3],a[2][3])
				add_child(object)
				objects.append(object)
		for mi in meshes(imported):
			var mesh: ArrayMesh=mi.mesh.duplicate()
			for surface in mesh.get_surface_count():
				var mat: Material=mesh.surface_get_material(surface)
				var role: String="Matte"
				if mat != null:
					for candidate in MATERIALS:
						if candidate in mat.resource_name: role=candidate
				var material: ShaderMaterial = MATERIALS[role]
				if key in WINDOWS:
					material=material.duplicate()
					material.set_shader_parameter("home_window",role == "Gloss" if key in ["entry","porch_side"] else true)
					material.set_shader_parameter("home_window_recessed",key not in ["entry","porch_side"])
					material.set_shader_parameter("home_window_column",0 if key in ["entry","porch_side"] else 3)
				mesh.surface_set_material(surface,material)
			var sets: Array = [entries] if objects.is_empty() else entries.map(func(e): return [e])
			for set_index in sets.size():
				var subset: Array = sets[set_index]
				var mm := MultiMesh.new()
				mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=subset.size()
				var xforms: Array[Transform3D] = []
				for i in subset.size():
					var a: Array=subset[i].transform
					var basis := Basis(Vector3(a[0][0],a[1][0],a[2][0]),Vector3(a[0][1],a[1][1],a[2][1]),Vector3(a[0][2],a[1][2],a[2][2]))
					var xf: Transform3D = Transform3D(basis,Vector3(a[0][3],a[1][3],a[2][3]))*mi.transform
					if not objects.is_empty(): xf.origin -= objects[set_index].position
					mm.set_instance_transform(i, xf);xforms.append(xf)
				var visual := MultiMeshInstance3D.new();visual.name=key+"_"+str(component_meshes);visual.multimesh=mm
				visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;visual.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
				visual.set_meta("asset_component",key);visual.set_meta("category",entries[0].category)
				visual.set_meta("instance_transforms", xforms)
				if objects.is_empty(): add_child(visual)
				else: objects[set_index].add_child(visual)
				component_meshes+=1;visual_instances+=subset.size()
		imported.free()
