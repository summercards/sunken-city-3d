extends "res://src/rendering/water_surface.gd"
## This scene reuses the original ocean renderer, not the legacy world clock.
const ShoreDistance = preload("res://src/rendering/shore_distance.gd")
const RenderFlags = preload("res://src/rendering/render_flags.gd")

@export var shore_roots: Array[Node3D] = []
@export var vessel_visual: Node3D
var _hull_visual: Node3D

func _ready() -> void:
	super._ready()
	var mat := current_material()
	mat.set_shader_parameter("water_level", global_position.y)
	mat.set_shader_parameter("u_reverse_z", RenderFlags.reverse_z())
	mat.set_shader_parameter("emission_gain", RenderFlags.water_emission_gain())
	_hull_visual = vessel_visual.get_node_or_null("Parts/hull_000") if vessel_visual != null else null
	# CSG generates its rendered mesh during deferred scene assembly.
	call_deferred("_bind_whitebox_shore")

func _bind_whitebox_shore() -> void:
	var atlas := ShoreDistance.new()
	atlas.cache_enabled = false
	atlas.include_csg = true
	atlas.rebuild(shore_roots, global_position.y, 512)
	shoreline = atlas
	atlas.bind(current_material())

func _process(delta: float) -> void:
	time += delta
	var mat := current_material()
	mat.set_shader_parameter("u_time", time)
	boat_contact.update_hull(vessel_visual, _hull_visual, mat)
