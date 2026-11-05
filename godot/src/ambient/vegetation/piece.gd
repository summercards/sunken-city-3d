@tool
extends Node3D
const Library = preload("res://src/ambient/vegetation/library.gd")
@export var asset_key := "grass_soft"
func _ready() -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Foliage"
	visual.mesh = Library.mesh(asset_key)
	visual.material_override = Library.material(asset_key)
	visual.extra_cull_margin = 0.55
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	set_meta("asset_id", Library.catalog()[asset_key].asset_id)
	set_meta("visual_only", true)
