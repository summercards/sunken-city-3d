@tool
extends Node3D
## 独立旧城氛围；仅拥有本子树的网格、材质与时钟，不触碰环境/水面/鱼群/头灯。
## 继承 uw_deco 的固定种子、MultiMesh 与 sample(time) 机制，不使用共享材质缓存。

const BEAM_SHADER = preload("res://shaders/sunroom_underwater_beam.gdshader")
const PARTICLE_SHADER = preload("res://shaders/sunroom_underwater_particles.gdshader")
const WATER_LEVEL := 1.12
const BUBBLE_TOP := WATER_LEVEL - 0.65
const BEAM_DOWN := Vector3(0.12, -1.0, 0.065)
const COLUMN_RADIUS := 0.8

@export var autonomous := true
@export var seed_value := 73191
@export_range(150, 240, 1) var bubble_count := 192
@export_range(120, 280, 1) var mote_count := 200
@export_range(8, 10, 1) var beam_count := 10
@export_range(0.0, 2.0, 0.01) var beam_gain := 1.0
@export_range(0.0, 2.0, 0.01) var particle_gain := 1.0
@export_range(0.0, 120.0, 0.1) var preview_time := 0.0:
	set(value):
		preview_time = value
		if Engine.is_editor_hint() and is_node_ready():
			sample(value)

var _built := false
var _clock := 0.0
var _bubble_mm: MultiMesh
var _mote_mm: MultiMesh
var _bubble_material: ShaderMaterial
var _mote_material: ShaderMaterial
var _beams: Array[MeshInstance3D] = []
var _bubble_specs: Array[Dictionary] = []
var _mote_specs: Array[Dictionary] = []


func _ready() -> void:
	_ensure_built()
	sample(preview_time)
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if autonomous and is_visible_in_tree():
		sample(_clock + delta)


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_bubble_material = _particle_material(true)
	_mote_material = _particle_material(false)
	_bubble_mm = _make_multimesh($Bubbles, bubble_count, _bubble_material)
	_mote_mm = _make_multimesh($Motes, mote_count, _mote_material)
	var columns := $BubbleColumns.get_children()
	for i in bubble_count:
		var column := columns[i % columns.size()] as Marker3D
		_bubble_specs.append({
			"origin": column.position,
			"phase": rng.randf(),
			"speed": rng.randf_range(0.36, 0.62),
			"diameter": rng.randf_range(0.055, 0.11) if i % 5 != 0 else rng.randf_range(0.13, 0.22),
			"angle": rng.randf_range(0.0, TAU),
			"orbit": rng.randf_range(0.10, 0.34),
			"alpha": rng.randf_range(0.64, 1.0),
		})
	for i in mote_count:
		var column := columns[i % columns.size()] as Marker3D
		var home_weight := i % 3 == 0
		var center := Vector3(7.0, -21.5, 20.0) if home_weight else column.position
		_mote_specs.append({
			"origin": center + Vector3(rng.randf_range(-7.0, 7.0), 1.5, rng.randf_range(-7.0, 7.0)),
			"phase": rng.randf(),
			"speed": rng.randf_range(0.045, 0.105),
			"diameter": rng.randf_range(0.026, 0.065),
			"angle": rng.randf_range(0.0, TAU),
			"alpha": rng.randf_range(0.32, 0.74),
		})
	var entries := $RayEntries.get_children()
	for i in mini(beam_count, entries.size()):
		var entry := entries[i] as Marker3D
		var length_m: float = entry.get_meta("length_m", 24.0)
		var radius: float = entry.get_meta("radius_m", 3.0)
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length_m
		mesh.radial_segments = 24
		mesh.rings = 1
		var beam := MeshInstance3D.new()
		beam.name = "Shaft%02d" % (i + 1)
		beam.mesh = mesh
		var axis := BEAM_DOWN.normalized()
		beam.position = entry.position + axis * length_m * 0.5
		beam.basis = Basis(Quaternion(Vector3.UP, -axis))
		var material := ShaderMaterial.new()
		material.shader = BEAM_SHADER
		material.set_shader_parameter("radius", radius)
		material.set_shader_parameter("beam_length", length_m)
		material.set_shader_parameter("phase", float(i) * 2.399963)
		material.set_shader_parameter("density", 0.085 + float(i % 3) * 0.008)
		material.set_shader_parameter("tint", Color(0.46, 0.77, 0.69).lerp(Color(0.40, 0.69, 0.78), float(i % 4) / 3.0))
		beam.material_override = material
		_prepare_geometry(beam)
		$LightShafts.add_child(beam)
		_beams.append(beam)


func _particle_material(is_bubble: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("bubble", is_bubble)
	material.set_shader_parameter("opacity", 0.42 if is_bubble else 0.23)
	material.set_shader_parameter("tint", Color(0.57, 0.80, 0.78) if is_bubble else Color(0.43, 0.71, 0.66))
	return material


func _make_multimesh(node: MultiMeshInstance3D, count: int, material: ShaderMaterial) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = count
	node.multimesh = mm
	node.material_override = material
	_prepare_geometry(node)
	# 完整覆盖固定列、低频摆动及 billboard 半径，不使用巨大强制可见包围盒。
	node.custom_aabb = AABB(Vector3(-98.0, -25.0, -95.0), Vector3(202.0, 27.0, 190.0))
	return mm


func _prepare_geometry(node: GeometryInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.extra_cull_margin = 0.5


func set_view_depth(depth: float) -> void:
	for beam in _beams:
		beam.material_override.set_shader_parameter("region_view_depth",depth)
	_bubble_material.set_shader_parameter("region_view_depth",depth)
	_mote_material.set_shader_parameter("region_view_depth",depth)

func sample(time: float) -> void:
	_ensure_built()
	_clock = maxf(time, 0.0)
	for i in _bubble_specs.size():
		var state := _bubble_state(_bubble_specs[i], _clock)
		_bubble_mm.set_instance_transform(i, state.transform)
		_bubble_mm.set_instance_color(i, Color(0.86, 1.0, 0.96, state.alpha))
	for i in _mote_specs.size():
		var state := _mote_state(_mote_specs[i], _clock)
		_mote_mm.set_instance_transform(i, state.transform)
		_mote_mm.set_instance_color(i, Color(0.88, 1.0, 0.91, state.alpha))
	for beam in _beams:
		var material := beam.material_override as ShaderMaterial
		material.set_shader_parameter("elapsed", _clock)
		material.set_shader_parameter("gain", beam_gain)
	_bubble_material.set_shader_parameter("gain", particle_gain)
	_mote_material.set_shader_parameter("gain", particle_gain)


func _bubble_state(spec: Dictionary, time: float) -> Dictionary:
	var origin: Vector3 = spec.origin
	var height := BUBBLE_TOP - origin.y
	var age := fposmod(float(spec.phase) * height + time * float(spec.speed), height)
	var angle := float(spec.angle) + time * 0.31
	var orbit: float = spec.orbit
	var p := origin + Vector3(sin(angle) * orbit + sin(angle * 0.63) * 0.13, age, cos(angle * 0.81) * orbit)
	var diameter := float(spec.diameter) * (1.0 + age / height * 0.28)
	var alpha := smoothstep(0.0, 0.85, age) * (1.0 - smoothstep(height - 2.8, height, age)) * float(spec.alpha)
	var size := Vector3(diameter, diameter * (1.06 + sin(angle) * 0.045), diameter)
	return {"transform": Transform3D(Basis().scaled(size), p), "alpha": alpha}


func _mote_state(spec: Dictionary, time: float) -> Dictionary:
	var origin: Vector3 = spec.origin
	var height := BUBBLE_TOP - 0.8 - origin.y
	var age := fposmod(float(spec.phase) * height + time * float(spec.speed), height)
	var angle := float(spec.angle) + time * 0.12
	var p := origin + Vector3(sin(angle) * 0.65, age, cos(angle * 0.74) * 0.55)
	var alpha := smoothstep(0.0, 1.8, age) * (1.0 - smoothstep(height - 2.0, height, age)) * float(spec.alpha)
	return {"transform": Transform3D(Basis().scaled(Vector3.ONE * float(spec.diameter)), p), "alpha": alpha}


## 不改当前时钟；返回指定时间的完整粒子变换，便于 time0/time2 逐实例比对。
func snapshot(time: float = -1.0) -> Dictionary:
	_ensure_built()
	var at := _clock if time < 0.0 else time
	var bubbles: Array[Dictionary] = []
	var motes: Array[Dictionary] = []
	var rays: Array[Dictionary] = []
	for spec in _bubble_specs:
		bubbles.append(_bubble_state(spec, at))
	for spec in _mote_specs:
		motes.append(_mote_state(spec, at))
	for i in _beams.size():
		var phase := float(i) * 2.399963
		var midpoint_flow := 0.84 + 0.10 * sin(3.55 + at * 0.31 + phase) + 0.06 * sin(-at * 0.19 + phase)
		rays.append({"transform": _beams[i].transform, "elapsed": at, "phase": phase, "midpoint_flow": midpoint_flow})
	return {"time": at, "seed": seed_value, "bubbles": bubbles, "motes": motes, "rays": rays, "statistics": statistics()}


func statistics() -> Dictionary:
	return {
		"nodes": 1 + find_children("*", "", true, false).size(),
		"bubble_columns": $BubbleColumns.get_child_count(),
		"bubble_instances": _bubble_specs.size(),
		"mote_instances": _mote_specs.size(),
		"beam_instances": _beams.size(),
		"multimeshes": 2,
		"draw_submissions": 2 + _beams.size(),
		"lights": 0,
		"particle_ceiling_y": BUBBLE_TOP,
		"column_clearance_radius": COLUMN_RADIUS,
	}


## 固定列最大水平包络包含摆动和最大泡半径；父线程可对该圆柱做屋顶净空验收。
func column_envelopes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for column in $BubbleColumns.get_children():
		result.append({"id": str(column.name), "bottom": column.position, "top_y": BUBBLE_TOP, "radius": COLUMN_RADIUS})
	return result
