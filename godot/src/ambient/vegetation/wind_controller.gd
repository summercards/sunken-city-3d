extends Node3D
## One owner in World. Pauses with the tree, freezes while World is hidden.
@export_range(0, 2) var strength := 1.1
@export var direction := Vector2(0.86, 0.5)
var elapsed := 0.0
var frozen := false
func _ready() -> void:
	add_to_group("vegetation_wind_owner")
	_publish()
func set_wind(value: float, heading: Vector2) -> void:
	strength = clampf(value, 0.0, 2.0)
	direction = heading.normalized() if heading.length_squared() > 0.001 else Vector2.RIGHT
	_publish()
func sample_at(seconds: float) -> void:
	elapsed = seconds
	_publish()
func _process(delta: float) -> void:
	if not is_visible_in_tree() or frozen: return
	elapsed += minf(delta, 0.1)
	RenderingServer.global_shader_parameter_set("vegetation_time", elapsed)
func _publish() -> void:
	RenderingServer.global_shader_parameter_set("vegetation_time", elapsed)
	RenderingServer.global_shader_parameter_set("vegetation_strength", strength)
	RenderingServer.global_shader_parameter_set("vegetation_direction", direction.normalized())
