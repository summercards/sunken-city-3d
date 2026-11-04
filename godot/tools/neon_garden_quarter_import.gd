@tool
extends EditorScenePostImport

const PALETTE := preload("res://assets/textures/shared/sea_cabin_timber_8x8_512.png")
const POSTER_PATH := "res://assets/textures/facilities/neon_garden_quarter/poster_atlas.png"

func _post_import(scene: Node) -> Object:
	var materials := {}
	for role in ["Matte", "Metal", "Gloss", "Emission", "Poster"]:
		var material := StandardMaterial3D.new()
		material.resource_name = "SEA_" + role
		material.albedo_texture = load(POSTER_PATH) if role == "Poster" else PALETTE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if role == "Poster" else BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 0.78
		if role == "Metal":
			material.metallic = 0.32
			material.roughness = 0.46
		elif role == "Gloss":
			material.metallic = 0.08
			material.roughness = 0.25
		elif role == "Emission":
			material.emission_enabled = true
			material.emission = Color.WHITE
			material.emission_texture = PALETTE
			material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			material.emission_energy_multiplier = 0.35
		elif role == "Poster":
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[material.resource_name] = material
	_bind(scene, materials)
	return scene

func _bind(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var imported: Material = node.mesh.surface_get_material(surface)
			if imported == null or not materials.has(imported.resource_name):
				push_error("Unknown neon garden surface role on " + str(node.name))
				continue
			node.set_surface_override_material(surface, materials[imported.resource_name])
	for child in node.get_children():
		_bind(child, materials)
