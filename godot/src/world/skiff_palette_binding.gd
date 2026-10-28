@tool
extends "res://src/ambient/scene_component.gd"
## Shared public palette, same UV swatches as the Blender source; real scene lights.
const MATERIALS = {
	"Matte": preload("res://assets/materials/reference_skiff/matte.tres"),
	"Metal": preload("res://assets/materials/reference_skiff/metal.tres"),
	"Gloss": preload("res://assets/materials/reference_skiff/gloss.tres")
}
func _ready() -> void:
	bind(self)
func bind(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for surface in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(surface)
			var role := "Matte"
			if material != null:
				for key in MATERIALS:
					if key in material.resource_name: role = key
			node.set_surface_override_material(surface, MATERIALS[role])
	for child in node.get_children(): bind(child)
