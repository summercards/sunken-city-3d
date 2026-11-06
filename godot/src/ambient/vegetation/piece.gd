@tool
extends Node3D
const Library = preload("res://src/ambient/vegetation/library.gd")
@export var asset_key := "grass_soft"
@export_range(0.0, 1.0) var wind_phase := 0.0
@export_range(0.0, 1.0) var variation := 0.0
func _ready() -> void:
	# Match the same instance shader channels as the baked turf batches.
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = Library.mesh(asset_key)
	mesh.instance_count = 1
	mesh.set_instance_transform(0, Transform3D.IDENTITY)
	mesh.set_instance_custom_data(0, Color(wind_phase, variation, 1.0, 1.0))
	var visual := MultiMeshInstance3D.new()
	visual.name = "Foliage"
	visual.multimesh = mesh
	visual.material_override = Library.material(asset_key)
	visual.extra_cull_margin = 0.55
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	set_meta("asset_id", Library.catalog()[asset_key].asset_id)
	set_meta("visual_only", true)
