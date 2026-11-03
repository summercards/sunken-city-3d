@tool
extends EditorScenePostImport

const MATERIALS := {
	"SEA_MATTE": preload("res://assets/materials/floating_shop/matte.tres"),
	"SEA_METAL": preload("res://assets/materials/floating_shop/metal.tres"),
	"SEA_GLOSS": preload("res://assets/materials/floating_shop/gloss.tres"),
	"SEA_EMISSION": preload("res://assets/materials/floating_shop/emission.tres"),
}

func _post_import(scene: Node) -> Object:
	_bind(scene)
	return scene

func _bind(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(surface)
			var key: String = "SEA_MATTE"
			if source != null:
				var name: String = source.resource_name.to_upper()
				for candidate in MATERIALS.keys():
					if name.contains(candidate):
						key = candidate
						break
			node.set_surface_override_material(surface, MATERIALS[key])
	for child in node.get_children():
		_bind(child)
