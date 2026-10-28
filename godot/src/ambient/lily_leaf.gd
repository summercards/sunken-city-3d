@tool
extends "res://src/ambient/scene_component.gd"
const Bake = preload("res://src/world/bake_store.gd")
@export var geometry_id := 679
@export var leaf_color := Color.WHITE
func _ready() -> void:
	component_kind="decoration";subcategory="water_plants";asset_id="SEA-DECO-WATER-LILY"
	set_meta("visual_only",true)
	var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true
	mm.mesh=Bake.geom(geometry_id);mm.instance_count=1
	mm.set_instance_transform(0,Transform3D.IDENTITY);mm.set_instance_color(0,leaf_color)
	var mesh := MultiMeshInstance3D.new();mesh.name="Leaf";mesh.multimesh=mm
	mesh.material_override=Bake.material(-1,false,false,false,false)
	mesh.set_meta("instance_transforms",[Transform3D.IDENTITY])
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
