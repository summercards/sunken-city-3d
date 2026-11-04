extends "res://src/world/zone_scene.gd"
## Register the street foundation in the existing sea-structure navigation query.

func rebuild_blockers(water_y: float, height := 1.6) -> void:
	$Blockers.rebuild(water_y, height)
	water_block_rects = $Blockers.rects_world
