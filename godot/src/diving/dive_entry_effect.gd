extends Node3D
## 入水瞬间的短簇气泡：独立于呼吸、氧气与位移的世界空间表现。

const PARTICLE_SHADER = preload("res://shaders/sunroom_underwater_particles.gdshader")
const MAX_BUBBLES := 40
const ENTRY_BUBBLES := 16

var _character: Node3D
var _water_level := 0.0
var _mm: MultiMesh
var _material: ShaderMaterial
var _instances: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _started := false
var _states: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 28741
	_build_pool()
	set_process(false)

func configure(character: Node3D, water_level: float) -> void:
	_character = character
	_water_level = water_level if is_finite(water_level) else 0.0
	if is_node_ready():
		_material.set_shader_parameter("water_level", _water_level)
		_clear_pool()

func _build_pool() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = MAX_BUBBLES
	_material = ShaderMaterial.new()
	_material.shader = PARTICLE_SHADER
	_material.set_shader_parameter("bubble", true)
	_material.set_shader_parameter("opacity", 0.78)
	_material.set_shader_parameter("tint", Color(0.72, 0.99, 0.94))
	_material.set_shader_parameter("water_level", _water_level)
	_material.set_shader_parameter("water_fade", 1.0)
	_material.set_shader_parameter("soft_contact_distance", 0.08)
	_instances = MultiMeshInstance3D.new()
	_instances.name = "DiveEntryBubbleMultiMesh"
	_instances.multimesh = _mm
	_instances.material_override = _material
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_instances.custom_aabb = AABB(Vector3(-4.0, -4.0, -4.0), Vector3(8.0, 8.0, 8.0))
	add_child(_instances)
	_clear_pool()

func _clear_pool() -> void:
	_states.clear()
	if _mm == null: return
	for i in MAX_BUBBLES:
		_mm.set_instance_transform(i, Transform3D.IDENTITY)
		_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))

func begin_entry() -> void:
	# Controller guarantees one call per entry; reset the reusable presentation pool
	# when the same controller is used for a later dive.
	_started = true
	_clock = 0.0
	_clear_pool()
	var center := _character.global_position if _character != null and is_instance_valid(_character) else global_position
	var forward := _character.global_basis * Vector3(0.0, 0.0, 1.0) if _character != null and is_instance_valid(_character) else Vector3.FORWARD
	for i in ENTRY_BUBBLES:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(0.10, 0.42)
		var birth := center + Vector3(cos(angle) * radius, _rng.randf_range(0.72, 1.32), sin(angle) * radius)
		birth.y = minf(birth.y, _water_level - 0.28)
		_states.append({
			"birth_time": 0.0,
			"position": birth,
			"velocity": Vector3.UP * _rng.randf_range(0.62, 1.18) + forward * _rng.randf_range(-0.08, 0.10),
			"scale": _rng.randf_range(0.055, 0.095),
			"growth": _rng.randf_range(0.012, 0.024),
			"life": _rng.randf_range(1.25, 2.25),
			"phase": _rng.randf_range(0.0, TAU)
		})
	_write_instances()
	_update_bounds()

func update_entry(dt: float, _released: bool) -> void:
	if not _started or not is_finite(dt) or dt <= 0.0: return
	_clock += dt
	for i in range(_states.size() - 1, -1, -1):
		var state: Dictionary = _states[i]
		state.position += state.velocity * dt
		state.position.x += sin(_clock * 1.8 + float(state.phase)) * dt * 0.035
		state.position.z += cos(_clock * 1.5 + float(state.phase)) * dt * 0.030
		state.velocity.y += dt * 0.04
		state.scale = minf(float(state.scale) + float(state.growth) * dt, 0.15)
		if _clock - float(state.birth_time) >= float(state.life) or state.position.y >= _water_level - 0.08:
			_states.remove_at(i)
	_write_instances()
	_update_bounds()

func has_active_trail() -> bool:
	return _started and not _states.is_empty()

func snapshot() -> Dictionary:
	var bubbles: Array[Dictionary] = []
	for state in _states:
		bubbles.append({"position": state.position, "scale": float(state.scale),
			"birth_time": float(state.birth_time)})
	return {"started": _started, "active_count": bubbles.size(), "time": _clock,
		"positions": bubbles.map(func(item: Dictionary): return item.position),
		"bubbles": bubbles}

func _write_instances() -> void:
	if _mm == null: return
	for i in MAX_BUBBLES:
		if i >= _states.size():
			_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
			continue
		var state: Dictionary = _states[i]
		var age := _clock - float(state.birth_time)
		var life := float(state.life)
		var alpha := smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(life * 0.60, life, age))
		var size := float(state.scale)
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), to_local(state.position)))
		_mm.set_instance_color(i, Color(0.86, 1.0, 0.97, alpha))

func _update_bounds() -> void:
	if _instances == null: return
	var center := to_local(_character.global_position) if is_instance_valid(_character) else Vector3.ZERO
	var bounds := AABB(center - Vector3.ONE * 2.0, Vector3.ONE * 4.0)
	for state in _states:
		bounds = bounds.expand(to_local(state.position) + Vector3.ONE * 0.3)
		bounds = bounds.expand(to_local(state.position) - Vector3.ONE * 0.3)
	_instances.custom_aabb = bounds
