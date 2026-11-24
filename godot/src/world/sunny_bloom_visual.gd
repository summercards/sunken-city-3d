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
var _generated: Array[Node] = []
var construction_parts: Array[Dictionary] = []
func _ready() -> void:
	build()
func meshes(root_node: Node) -> Array:
	var out := []
	if root_node is MeshInstance3D: out.append(root_node)
	for c in root_node.get_children(): out.append_array(meshes(c))
	return out
func build() -> void:
	for child in _generated:
		if is_instance_valid(child):
			child.free()
	_generated.clear()
	construction_parts.clear()
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
		var entries: Array=groups[key]
		var packed: PackedScene = load(entries[0].get("component_scene", component_directory+"/%s.tscn" % key))
		var imported: Node3D = packed.instantiate()
		var objects: Array = []
		var motion_roots: Array[Node3D] = []
		if entries[0].category == "flora" or key in MOVABLE or entries[0].has("drop"):
			for entry in entries:
				var object_name: String = key+"_"+str(entry.instance_id).get_file()
				var object = get_node_or_null(NodePath(object_name)) if entry.category == "flora" else null
				if object == null:
					object = Component.new() if key in MOVABLE or entry.category == "flora" else Node3D.new()
					object.name = object_name
					var authored: Array = entry.transform
					object.position = Vector3(authored[0][3], authored[1][3], authored[2][3])
					add_child(object)
					_generated.append(object)
				if key in MOVABLE or entry.category == "flora":
					object.instance_id = entry.instance_id
					object.facility_id = "solar_cabin"
					object.asset_id = entry.asset_id
					object.component_kind = "upgrade_attachment" if entry.category == "flora" else "furnishing"
					object.subcategory = "plants" if entry.category == "flora" else "movable"
					object.movable = entry.category != "flora"
					object.unlock_level = int(entry.get("unlock_level",0))
					object.attachment_slot = str(entry.get("module",module_key))
					object.set_meta("visual_only",true)
				object.set_meta("asset_component", key)
				object.set_meta("instance_id", entry.instance_id)
				objects.append(object)
				if entry.has("drop"):
					var moving := Node3D.new()
					moving.name = "ConstructionPose"
					object.add_child(moving)
					motion_roots.append(moving)
					construction_parts.append({"node": moving, "start": entry.drop[0], "rise": entry.rise})
		if entries[0].get("wind_animation", false):
			var umbrella: Node3D = objects[0]
			var pose := _entry_transform(entries[0])
			pose.origin -= umbrella.position
			imported.transform = pose
			motion_roots[0].add_child(imported)
			for mesh in meshes(imported):
				mesh.set_meta("asset_component", key)
			var player := imported.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if not Engine.is_editor_hint() and player != null and player.has_animation(&"wind"):
				player.get_animation(&"wind").loop_mode = Animation.LOOP_LINEAR
				player.play(&"wind")
			component_meshes += meshes(imported).size()
			visual_instances += 1
			continue
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
					var placement := _entry_transform(subset[i])
					var xf: Transform3D = placement * mi.transform
					if not objects.is_empty():
						xf.origin -= placement.origin
					mm.set_instance_transform(i, xf);xforms.append(xf)
				var visual := MultiMeshInstance3D.new();visual.name=key+"_"+str(component_meshes);visual.multimesh=mm
				visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;visual.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
				visual.set_meta("asset_component",key);visual.set_meta("category",entries[0].category)
				visual.set_meta("instance_transforms", xforms)
				if not motion_roots.is_empty():
					motion_roots[set_index].add_child(visual)
				elif objects.is_empty():
					add_child(visual)
				else:
					objects[set_index].add_child(visual)
				_generated.append(visual)
				component_meshes+=1;visual_instances+=subset.size()
		imported.free()

func _entry_transform(entry: Dictionary) -> Transform3D:
	var a: Array = entry.transform
	return Transform3D(Vector3(a[0][0], a[1][0], a[2][0]),
		Vector3(a[0][1], a[1][1], a[2][1]), Vector3(a[0][2], a[1][2], a[2][2]),
		Vector3(a[0][3], a[1][3], a[2][3]))
