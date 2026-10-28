@tool
extends "res://src/ambient/scene_component.gd"
## Independent scenery identity; no collision, resources, progression or input.
const PALETTE_MATERIAL = preload("res://assets/materials/submerged_neighborhood/matte.tres")

func _ready() -> void:
	_bind(self)

func _bind(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in node.mesh.get_surface_count():
			node.set_surface_override_material(surface, PALETTE_MATERIAL)
	for child in node.get_children(): _bind(child)
