@tool
extends Node3D
## Small, readable damage cue for the original ladder asset.
## It is an overlay only; the real ladder GLB remains the stable asset.

var _built := false

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#5a3b31")
	material.roughness = 0.9
	for spec in [
		[Vector3(0.78, 0.10, 0.16), Vector3(0.0, 0.85, 0.0), -0.22],
		[Vector3(0.68, 0.10, 0.16), Vector3(0.0, 1.62, 0.0), 0.28],
		[Vector3(0.56, 0.10, 0.15), Vector3(0.0, 2.38, 0.0), -0.16],
	]:
		var mesh := BoxMesh.new()
		mesh.size = spec[0]
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.position = spec[1]
		part.rotation.z = float(spec[2])
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(part)
	# A short split board at the foot makes the broken state readable from above.
	var split := MeshInstance3D.new()
	var split_mesh := BoxMesh.new()
	split_mesh.size = Vector3(0.18, 0.42, 0.12)
	split.mesh = split_mesh
	split.position = Vector3(0.34, 0.24, 0.0)
	split.rotation.z = -0.35
	split.material_override = material
	add_child(split)

func set_sunroom_damage(damaged: bool) -> void:
	visible = damaged
