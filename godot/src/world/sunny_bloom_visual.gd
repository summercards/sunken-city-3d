@tool
extends Node3D
## Component GLBs + Collection-style instances; root stays at identity.
@export_file("*.json") var instance_data_path: String = "res://assets/models/facilities/solar_cabin/instances.json"
@export_dir var component_directory: String = "res://scenes/components/solar_cabin"
const MATERIALS = {
	"Matte": preload("res://assets/materials/solar_cabin/sunny_matte.tres"),
	"Metal": preload("res://assets/materials/solar_cabin/sunny_metal.tres"),
	"Gloss": preload("res://assets/materials/solar_cabin/sunny_gloss.tres"),
	"Emission": preload("res://assets/materials/solar_cabin/sunny_emission.tres")}
@export var module_key: String = ""
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
	for entry in data.instances:
		if module_key != "" and entry.get("module", "") != module_key: continue
		if not groups.has(entry.component): groups[entry.component]=[]
		groups[entry.component].append(entry)
	for key in groups:
		var packed: PackedScene=load(component_directory+"/%s.tscn" % key)
		var imported: Node3D=packed.instantiate()
		var entries: Array=groups[key]
		for mi in meshes(imported):
			var mesh: ArrayMesh=mi.mesh.duplicate()
			for surface in mesh.get_surface_count():
				var mat: Material=mesh.surface_get_material(surface)
				var role: String="Matte"
				if mat != null:
					for candidate in MATERIALS:
						if candidate in mat.resource_name: role=candidate
				mesh.surface_set_material(surface,MATERIALS[role])
			var mm := MultiMesh.new()
			mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=entries.size()
			# 实例变换同时留一份在 meta 里：headless（dummy renderer）下
			# MultiMesh.get_instance_transform() 读回来是单位矩阵，阻挡派生会全部落在原点。
			var xforms: Array[Transform3D] = []
			for i in entries.size():
				var a: Array=entries[i].transform
				var basis := Basis(Vector3(a[0][0],a[1][0],a[2][0]),Vector3(a[0][1],a[1][1],a[2][1]),Vector3(a[0][2],a[1][2],a[2][2]))
				var xf: Transform3D = Transform3D(basis,Vector3(a[0][3],a[1][3],a[2][3]))*mi.transform
				mm.set_instance_transform(i, xf)
				xforms.append(xf)
			var visual := MultiMeshInstance3D.new();visual.name=key+"_"+str(component_meshes);visual.multimesh=mm
			visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;visual.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
			visual.set_meta("asset_component",key);visual.set_meta("category",entries[0].category)
			visual.set_meta("instance_transforms", xforms)
			add_child(visual);component_meshes+=1;visual_instances+=entries.size()
		imported.free()
