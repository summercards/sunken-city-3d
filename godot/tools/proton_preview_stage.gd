@tool
extends Node3D
## Editor/F6-only trial stage. No Main, save loading, inventory or gameplay writes.
func _ready() -> void:
	var turf=get_node_or_null("RooftopRanch/VegetationTurf")
	if turf!=null:turf.hide()
	$Camera3D.look_at(Vector3(0,4.5,0))
