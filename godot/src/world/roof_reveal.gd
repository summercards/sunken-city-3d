extends Node3D
## Facility-local presentation only. The injected actor/mode query owns entry;
## this node owns temporary instance materials/visibility, never movement/save.
const DISSOLVE = preload("res://shaders/roof_reveal.gdshader")
@export var visual_path := NodePath("../Visual")
@export var enter_half_size := Vector2(5.12, 5.12)
@export var exit_margin := 0.32
@export var corner_radius := 1.35
@export var floor_height := 0.3
@export var floor_tolerance := 0.55
@export var open_seconds := 0.95
@export var close_seconds := 0.75
@export var feather_width := 1.05
var _subject: Node3D
var _ashore_query: Callable
var _visual: Node3D
var _roofs: Array[Node3D] = []
var _initial_visibility: Array[bool] = []
var _bindings: Array = []
var _materials: Array[ShaderMaterial] = []
var _bounds := AABB()
var _inside := false
var _amount := 0.0
var _center := Vector2.ZERO
var _using_reveal_materials := false

func _ready() -> void:
	_visual = get_node_or_null(visual_path) as Node3D
	if _visual == null:
		return
	var cache := {}
	var first := true
	for node in _visual.find_children("*", "Node3D", true, false):
		if not node.get_meta("roof_reveal", false):
			continue
		_roofs.append(node)
		_initial_visibility.append(node.visible)
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			var part: AABB = (_visual.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			_bounds = part if first else _bounds.merge(part)
			first = false
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as StandardMaterial3D
				if source == null:
					continue
				var key := source.get_instance_id()
				if not cache.has(key):
					var mat := ShaderMaterial.new()
					mat.shader = DISSOLVE
					mat.set_shader_parameter("palette", source.albedo_texture)
					mat.set_shader_parameter("tint", source.albedo_color)
					mat.set_shader_parameter("surface_roughness", source.roughness)
					mat.set_shader_parameter("surface_metallic", source.metallic)
					mat.set_shader_parameter("glow_tint", source.emission if source.emission_enabled else Color.BLACK)
					mat.set_shader_parameter("glow_energy", source.emission_energy_multiplier if source.emission_enabled else 0.0)
					cache[key] = mat
					_materials.append(mat)
				_bindings.append({"mesh":mesh,"surface":surface,"original":mesh.get_surface_override_material(surface),"reveal":cache[key]})

func configure_subject(actor: Node3D, ashore_query: Callable) -> void:
	_subject = actor
	_ashore_query = ashore_query

func _process(delta: float) -> void:
	advance(delta)

func _within_rounded_room(point: Vector2, margin: float) -> bool:
	var half := enter_half_size + Vector2.ONE * margin
	var radius := corner_radius + margin
	var q := point.abs() - (half - Vector2.ONE * radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() <= radius

func advance(delta: float) -> void:
	if not is_instance_valid(_visual) or not is_finite(delta) or delta < 0.0:
		return
	var wanted := false
	if is_instance_valid(_subject) and _ashore_query.is_valid() and bool(_ashore_query.call()):
		var local := _visual.to_local(_subject.global_position)
		wanted = absf(local.y - floor_height) <= floor_tolerance and _within_rounded_room(Vector2(local.x,local.z), exit_margin if _inside else 0.0)
		if wanted:
			_center = Vector2(local.x, local.z)
	_inside = wanted
	var seconds := open_seconds if _inside else close_seconds
	_amount = move_toward(_amount, 1.0 if _inside else 0.0, delta / maxf(seconds, 0.01))
	var active := _amount > 0.000001
	if active != _using_reveal_materials:
		for binding in _bindings:
			if is_instance_valid(binding.mesh):
				binding.mesh.set_surface_override_material(binding.surface, binding.reveal if active else binding.original)
		_using_reveal_materials = active
	var fully_open := _amount >= 0.999999
	for i in _roofs.size():
		_roofs[i].visible = _initial_visibility[i] and not fully_open
	if not active:
		return
	var reach := 0.0
	for x in [_bounds.position.x, _bounds.end.x]:
		for z in [_bounds.position.z, _bounds.end.z]:
			reach = maxf(reach, _center.distance_to(Vector2(x,z)))
	for mat in _materials:
		mat.set_shader_parameter("facility_inverse", _visual.global_transform.affine_inverse())
		mat.set_shader_parameter("reveal_center", _center)
		mat.set_shader_parameter("reveal_amount", _amount)
		mat.set_shader_parameter("reveal_reach", reach)
		mat.set_shader_parameter("feather_width", feather_width)

func snapshot() -> Dictionary:
	var visible_roots := 0
	for node in _roofs:
		if node.visible:
			visible_roots += 1
	return {"inside":_inside,"amount":_amount,"center":_center,"roof_roots":_roofs.size(),"visible_roofs":visible_roots,"bindings":_bindings.size(),"temporary_materials":_materials.size(),"using_reveal_materials":_using_reveal_materials}
