@tool
extends "res://src/world/sea_supply_zone.gd"
## Fixed platform: its deck and landing derive world heights from the authored root.
@export var deck_top_local := 0.42

func _register() -> void:
	super._register()
	for area in walk_areas:
		area.surface_y = to_global(Vector3(0, deck_top_local, 0)).y
		area.span_min = area.surface_y - 0.35
		area.span_max = area.surface_y + 0.35

func rebuild_blockers(water_y: float, height := 1.6) -> void:
	for landing in landing_points():
		var park := landing.get_node_or_null("BoatPark") as Node3D
		if park != null:
			park.global_position.y = water_y
	super.rebuild_blockers(water_y, height)
