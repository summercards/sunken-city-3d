extends Node3D
## 潜水角色呼气泡：纯表现层，固定 MultiMesh 池，不拥有氧气、输入或角色移动。

const PARTICLE_SHADER = preload("res://shaders/sunroom_underwater_particles.gdshader")
const MAX_BUBBLES := 48
const MIN_BURST := 4
const MAX_BURST := 7
const MIN_INTERVAL := 2.0
const MAX_INTERVAL := 3.0

var _character: Node3D
var _water_level := 101.587442
var _mm: MultiMesh
var _material: ShaderMaterial
var _instances: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _emit_left := 0.0
var _burst_left := 0
var _burst_gap := 0.0
var _active := false
var _speed_ratio := 0.0
var _depth := 0.0
var _states: Array[Dictionary] = []

func _ready() -> void:
	_rng.seed = 90173
	_build_pool()
	_material.set_shader_parameter("water_level", _water_level)
	set_process(false)

func configure(character: Node3D, water_level: float) -> void:
	_character = character
	_water_level = water_level if is_finite(water_level) else 101.587442
	if not is_node_ready():
		return
	_material.set_shader_parameter("water_level", _water_level)
	_clear_pool()
	_emit_left = _rng.randf_range(MIN_INTERVAL, MAX_INTERVAL)

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
	_material.set_shader_parameter("opacity", 0.82)
	_material.set_shader_parameter("tint", Color(0.70, 0.98, 0.91))
	_material.set_shader_parameter("water_level", _water_level)
	_material.set_shader_parameter("water_fade", 1.0)
	_material.set_shader_parameter("soft_contact_distance", 0.08)
	_instances = MultiMeshInstance3D.new()
	_instances.name = "BreathBubbleMultiMesh"
	_instances.multimesh = _mm
	_instances.material_override = _material
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_instances.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))
	add_child(_instances)
	_clear_pool()

func _clear_pool() -> void:
	_states.clear()
	for i in MAX_BUBBLES:
		_mm.set_instance_transform(i, Transform3D.IDENTITY)
		_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))

func _process(_delta: float) -> void:
	pass

func update_breath(dt: float, active: bool, speed_ratio: float, depth: float) -> void:
	if not is_finite(dt) or dt < 0.0:
		return
	_clock += dt
	_active = active
	_speed_ratio = clampf(speed_ratio if is_finite(speed_ratio) else 0.0, 0.0, 1.65)
	_depth = maxf(depth if is_finite(depth) else 0.0, 0.0)
	_material.set_shader_parameter("dive_depth", _depth)
	_material.set_shader_parameter("region_view_depth", _depth)
	_material.set_shader_parameter("water_level", _water_level)
	if active:
		_emit_left -= dt * (1.0 + _speed_ratio * 0.45)
		if _emit_left <= 0.0 and _burst_left <= 0:
			_begin_burst()
		if _burst_left > 0:
			_burst_gap -= dt * (1.0 + _speed_ratio * 0.9)
			if _burst_gap <= 0.0:
				emit_one()
	else:
		_emit_left = minf(_emit_left, 0.45)
		_burst_left = 0
	for i in range(_states.size() - 1, -1, -1):
		_update_state(i, dt)
	_write_instances()
	# The pool stores world-space trails; center culling around the live head/trail,
	# not the map origin (home water surface is above Y=100m).
	var local_head := to_local(_head_position())
	var bounds := AABB(local_head - Vector3.ONE * 2.0, Vector3.ONE * 4.0)
	for state in _states:
		bounds = bounds.expand(to_local(state.position) + Vector3.ONE * 0.3)
		bounds = bounds.expand(to_local(state.position) - Vector3.ONE * 0.3)
	_instances.custom_aabb = bounds

func _begin_burst() -> void:
	_burst_left = _rng.randi_range(MIN_BURST, MAX_BURST)
	_burst_gap = 0.0
	_emit_left = _rng.randf_range(MIN_INTERVAL, MAX_INTERVAL) / (1.0 + _speed_ratio * 0.35)

func emit_one() -> void:
	if _character == null or not is_instance_valid(_character):
		_burst_left = 0
		return
	if _states.size() >= MAX_BUBBLES:
		_states.pop_front()
	var birth := _birth_position()
	# At the 1m entry pose the mask can sit in the surface meniscus. Spawn the
	# regulator exhaust just below it so it forms a short visible plume, not above water.
	birth.y = minf(birth.y, _water_level - 0.28)
	var forward := _character.global_basis * Vector3(0.0, 0.0, 1.0)
	_states.append({
		"birth_time": _clock,
		"position": birth,
		"velocity": Vector3.UP * _rng.randf_range(0.7, 1.3) + forward * _rng.randf_range(0.03, 0.10),
		"scale": _rng.randf_range(0.065, 0.095),
		"growth": _rng.randf_range(0.010, 0.024),
		"life": _rng.randf_range(3.0, 4.7),
		"phase": _rng.randf_range(0.0, TAU),
	})
	_burst_left -= 1
	_burst_gap = _rng.randf_range(0.07, 0.15)

func _head_position() -> Vector3:
	if _character == null or not is_instance_valid(_character):
		return Vector3.ZERO
	var head := _character.get("head_pivot") as Node3D
	return head.global_position if head != null else _character.global_position

func _birth_position() -> Vector3:
	var head := _character.get("head_pivot") as Node3D
	var mask := _character.get("mask") as Node3D
	var anchor := mask if mask != null and mask.visible else head
	if anchor == null:
		return _character.global_position + Vector3(0.0, 1.45, 0.22)
	# Avatar face is an ellipsoid reaching native Z=.253; mask frame adds .044.
	# Emit below the lens and in front of that surface, not inside the cheeks.
	return anchor.to_global(Vector3(0.0, -0.10, 0.32))

func _update_state(index: int, dt: float) -> void:
	var state := _states[index]
	state.position += state.velocity * dt
	state.position.x += sin(_clock * 1.7 + float(state.phase)) * dt * 0.035
	state.position.z += cos(_clock * 1.35 + float(state.phase)) * dt * 0.030
	state.velocity.y += dt * 0.035
	state.scale = minf(float(state.scale) + float(state.growth) * dt, 0.16)
	var age := _clock - float(state.birth_time)
	if state.position.y >= _water_level - 0.08 or age >= float(state.life):
		_states.remove_at(index)

func _write_instances() -> void:
	for i in MAX_BUBBLES:
		if i >= _states.size():
			_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
			continue
		var state := _states[i]
		var age := _clock - float(state.birth_time)
		var life := float(state.life)
		var alpha := smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(life * 0.62, life, age))
		var size := float(state.scale)
		var local_position := to_local(state.position)
		_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), local_position))
		_mm.set_instance_color(i, Color(0.86, 1.0, 0.96, alpha))

func snapshot() -> Dictionary:
	var bubbles: Array[Dictionary] = []
	for state in _states:
		bubbles.append({
			"birth_time": float(state.birth_time),
			"position": state.position,
			"scale": float(state.scale),
		})
	return {
		"head_pos": _head_position(),
		"water_level": _water_level,
		"time": _clock,
		"active": _active,
		"speed_ratio": _speed_ratio,
		"active_count": bubbles.size(),
		"positions": bubbles.map(func(item: Dictionary): return item.position),
		"bubbles": bubbles,
	}
