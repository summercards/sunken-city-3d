@tool
extends "res://src/world/sea_supply_zone.gd"
## One owner drives the complete rigid floating support. Placement stays on the
## authored root; only the visual, walk declarations and interaction children heave.
signal support_moved

@export var motion_enabled := true
@export var heave_amplitude := 0.12
@export var heave_period := 6.8
@export var secondary_amplitude := 0.025
@export var deck_top_local := 0.3
var _motion_time := 0.0
var _heave := 0.0
var _water_line := 1.12

func _ready() -> void:
	process_physics_priority = -100
	super._ready()
	_pin_boat_park()
	set_physics_process(not Engine.is_editor_hint())

func _register() -> void:
	super._register()
	for area in walk_areas:
		area.surface_y = to_global(Vector3(0, deck_top_local, 0)).y
		area.span_min = area.surface_y - 0.35
		area.span_max = area.surface_y + 0.35
		area.set_meta("moving_support", true)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not motion_enabled:
		return
	set_motion_time(_motion_time + delta)

## Deterministic command also used by the isolated verification harness.
func set_motion_time(seconds: float) -> void:
	if not is_finite(seconds):
		return
	_motion_time = seconds
	var phase := TAU * seconds / maxf(heave_period, 0.1)
	var next := heave_amplitude * sin(phase) + secondary_amplitude * sin(phase * 1.71)
	var previous_height: float = walk_areas[0].surface_y if not walk_areas.is_empty() else global_position.y + deck_top_local
	_heave = next
	for path in ["Visual", "WalkAreas", "Objects"]:
		var child := get_node_or_null(path) as Node3D
		if child != null:
			child.position.y = _heave
	var height := to_global(Vector3(0, deck_top_local + _heave, 0)).y
	for area in walk_areas:
		area.surface_y = height
		area.span_min = height - 0.35
		area.span_max = height + 0.35
	if is_instance_valid(ground_space):
		ground_space.translate_projection(Vector3(0, height - previous_height, 0))
	_pin_boat_park()
	support_moved.emit()

func _pin_boat_park() -> void:
	for landing in landing_points():
		var park := landing.get_node_or_null("BoatPark") as Node3D
		if park != null:
			park.global_position.y = _water_line

func rebuild_blockers(water_y: float, height := 1.6) -> void:
	_water_line = water_y
	_pin_boat_park()
	super.rebuild_blockers(water_y, height)

func motion_snapshot() -> Dictionary:
	return {"time": _motion_time, "heave": _heave, "surface_y": walk_areas[0].surface_y if not walk_areas.is_empty() else 0.0}

func configure_view_subject(actor: Node3D, ashore_query: Callable, camera: Camera3D = null) -> void:
	var reveal := get_node_or_null("RoofReveal")
	if reveal != null:
		reveal.configure_subject(actor, ashore_query)
	var sightline := get_node_or_null("SightlineReveal")
	if sightline != null:
		sightline.configure_subject(actor, camera)
