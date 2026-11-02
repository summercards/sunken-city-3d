@tool
extends EditorScenePostImport
## Persist shared palette bindings into imported resources, before runtime.
const PALETTE_MAT := preload("res://assets/materials/fishery/matte.tres")
func _post_import(scene: Node) -> Object:
	bind(scene)
	return scene
func bind(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			node.set_surface_override_material(surface,PALETTE_MAT)
	for child in node.get_children(): bind(child)
