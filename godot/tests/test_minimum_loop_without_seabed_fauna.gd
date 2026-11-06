extends "res://tests/test_minimum_loop.gd"

const REMOVED_PATHS := [
	"World/SunkenSeabed",
	"World/Environment/Animals/SolarCabinFishSchools",
	"World/Zones/Zone1HomeHarbor/Models/太阳能木屋/SolarCabinGulls",
	"World/SeaStructures/rooftop_ranch/RooftopRanchGulls",
]

func instantiate_main() -> Node:
	var main: Node = super.instantiate_main()
	for path in REMOVED_PATHS:
		var node: Node = main.get_node(path)
		node.free()
		print("[visual-baseline-removed] ", path)
	return main
