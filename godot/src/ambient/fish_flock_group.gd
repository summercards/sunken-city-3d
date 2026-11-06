extends Node3D
## Multiple surface fish-school variants owned by one visual-only group.
## Main injects the real water sampler once; no fishery/economy/state dependency.

func _ready() -> void:
	set_meta("visual_only", true)
	set_meta("water_layer", "surface")
	set_meta("water_layer_role", "none")

func set_water(water: MeshInstance3D) -> void:
	for child in get_children():
		if child.has_method("set_water"):
			child.set_water(water)
