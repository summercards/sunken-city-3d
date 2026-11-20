@tool
extends EditorScenePostImport
## Restore the public palette to each semantic surface; do not repair materials at runtime.
const ROLES := {
	"SEA_Matte": "matte", "SEA_Metal": "metal", "SEA_Gloss": "gloss", "SEA_Emission": "emission",
}

func _post_import(scene: Node) -> Object:
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			var role := original.resource_name if original != null else ""
			if not ROLES.has(role):
				push_error("Arcade mesh has an unknown palette role: %s (%s)" % [mesh.name, role])
				continue
			mesh.set_surface_override_material(surface, load("res://assets/materials/rooftop_arcade/" + ROLES[role] + ".tres"))
	return scene
