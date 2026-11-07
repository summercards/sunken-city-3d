@tool
extends EditorScenePostImport
## Bind the same four public palette roles during official import, including
## editor previews. No runtime script repairs colours.
func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			var role: String = material.resource_name if material != null else ""
			for candidate in ["SEA_Matte", "SEA_Metal", "SEA_Gloss", "SEA_Emission"]:
				if str(mesh.name).ends_with(candidate) or role.begins_with(candidate):
					var file: String = candidate.trim_prefix("SEA_").to_lower()
					if file == "metal" and str(mesh.name).begins_with("sign_"):
						file = "metal_lettering"
					mesh.set_surface_override_material(surface, load("res://assets/materials/gift_kiosk/" + file + ".tres"))
	return scene
