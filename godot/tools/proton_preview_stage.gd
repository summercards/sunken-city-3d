@tool
extends Node3D
## Editor/F6-only trial stage. No Main, save loading, inventory or gameplay writes.
func _ready() -> void:
	var roof: Node3D = $RooftopRanch
	roof.get_node("VegetationTurf").hide()
	roof.get_node("Camera3D").look_at(roof.to_global(Vector3(0, 4.5, 0)))
