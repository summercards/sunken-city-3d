@tool
extends Node3D
## 独立旧城氛围；仅拥有本子树的网格、材质与时钟，不触碰环境/水面/鱼群/头灯。
## 家园预算固定为192泡/200尘/10束：前96泡保留固定列，后96泡与全部尘埃使用悬浮世界场。

const BEAM_SHADER = preload("res://shaders/sunroom_underwater_beam.gdshader")
const PARTICLE_SHADER = preload("res://shaders/sunroom_underwater_particles.gdshader")
## 2026-11-08 第二轮把上街面到水面做到 120 米，气泡必须一路升到新水面。
const DEFAULT_WATER_LEVEL := 101.587442
const BUBBLE_SURFACE_CLEARANCE := 0.65
const BUBBLE_TOP_MARGIN := 0.12
const FIXED_BUBBLE_COUNT := 96
const SUSPENDED_EXTENT := Vector3(12.0, 8.0, 12.0)
const SUSPENDED_FADE := 1.5

## 悬浮场是世界空间的量化邻域：同一单元内移动 observer 不会拖着粒子走，
## 越过单元边界时由边缘 alpha 渐隐并换入新的确定性邻域。
const MOTE_BAND := 17.0
## 光柱基准长度。密度按长度反比缩放，长光柱才不会因为积分路径变长而糊成实心柱。
const BEAM_REFERENCE_LENGTH := 22.0
const BEAM_DOWN := Vector3(0.12, -1.0, 0.065)
const COLUMN_RADIUS := 0.8

@export var autonomous := true
@export var water_level := DEFAULT_WATER_LEVEL
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
var _observer := Vector3.ZERO
var _has_observer := false
var _sunlight_strength := 1.0

func configure_water(level: float) -> void:
	water_level = level if is_finite(level) else DEFAULT_WATER_LEVEL
	if _built:
		_rebuild_water_dependent_state()

func set_sunlight(strength: float) -> void:
	_sunlight_strength = clampf(strength if is_finite(strength) else 0.0, 0.0, 2.0)
	if _built:
		_apply_sunlight()

## 只更新世界场锚点；时间推进仍由 sample(time) 的唯一调用者负责。
func set_observer(world_position: Vector3) -> void:
	if not world_position.is_finite():
		return
	_observer = to_local(world_position)
	_has_observer = true
	if _built:
		_update_particle_aabb()

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
	_apply_sunlight()
	_bubble_mm = _make_multimesh($Bubbles, bubble_count, _bubble_material)
	_mote_mm = _make_multimesh($Motes, mote_count, _mote_material)
	var columns := $BubbleColumns.get_children()
	for i in bubble_count:
		var column := columns[i % columns.size()] as Marker3D
		var suspended := i >= FIXED_BUBBLE_COUNT
		_bubble_specs.append({
			"origin": column.position,
			"base": Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-12.0, 12.0)),
			"phase": rng.randf(),
			"speed": rng.randf_range(0.15, 0.45) if suspended else rng.randf_range(0.36, 0.62),
			"diameter": rng.randf_range(0.09, 0.18) if suspended and i % 7 != 0 else (0.22 if suspended else (rng.randf_range(0.055, 0.11) if i % 5 != 0 else rng.randf_range(0.13, 0.22))),
			"angle": rng.randf_range(0.0, TAU),
			"orbit": rng.randf_range(0.10, 0.34),
			"alpha": rng.randf_range(0.55, 0.95) if suspended else rng.randf_range(0.64, 1.0),
			"suspended": suspended,
		})
	for i in mote_count:
		var column := columns[i % columns.size()] as Marker3D
		var home_weight := i % 3 == 0
		var center := Vector3(7.0, -21.5, 20.0) if home_weight else column.position
		_mote_specs.append({
			"origin": center + Vector3(rng.randf_range(-7.0, 7.0), 1.5, rng.randf_range(-7.0, 7.0)),
			"base": Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-12.0, 12.0)),
			"phase": rng.randf(),
			"speed": rng.randf_range(0.03, 0.08),
			"diameter": rng.randf_range(0.025, 0.06),
			"angle": rng.randf_range(0.0, TAU),
			"alpha": rng.randf_range(0.24, 0.72),
		})
	var entries := $RayEntries.get_children()
	for i in mini(beam_count, entries.size()):
		var entry := entries[i] as Marker3D
		var length_m := 120.0
		var radius: float = entry.get_meta("radius_m", 3.0)
		entry.position.y = water_level - 1.0
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
		material.set_shader_parameter("density", (0.085 + float(i % 3) * 0.008) * BEAM_REFERENCE_LENGTH / length_m)
		material.set_shader_parameter("tint", Color(0.46, 0.77, 0.69).lerp(Color(0.40, 0.69, 0.78), float(i % 4) / 3.0))
		beam.material_override = material
		_prepare_geometry(beam)
		$LightShafts.add_child(beam)
		_beams.append(beam)


func _bubble_top() -> float:
	return water_level - BUBBLE_SURFACE_CLEARANCE - BUBBLE_TOP_MARGIN

func _rebuild_water_dependent_state() -> void:
	for material in [_bubble_material, _mote_material]:
		if material != null:
			material.set_shader_parameter("water_level", water_level)
	for i in _beams.size():
		var entry := $RayEntries.get_child(i) as Marker3D
		entry.position.y = water_level - 1.0
		var beam := _beams[i]
		beam.position = entry.position + BEAM_DOWN.normalized() * 120.0 * 0.5
		beam.material_override.set_shader_parameter("beam_length", 120.0)
	_update_particle_aabb()
	sample(_clock)

func _update_particle_aabb() -> void:
	var fixed := _fixed_particle_aabb()
	var field := _suspended_particle_aabb()
	var bounds := fixed.merge(field)
	if $Bubbles != null:
		$Bubbles.custom_aabb = bounds
	if $Motes != null:
		$Motes.custom_aabb = bounds

func _fixed_particle_aabb() -> AABB:
	var bounds := AABB()
	var first := true
	for column in $BubbleColumns.get_children():
		var point: Vector3 = column.position
		var box := AABB(point + Vector3(-COLUMN_RADIUS, 0.0, -COLUMN_RADIUS),
			Vector3(COLUMN_RADIUS * 2.0, _bubble_top() - point.y, COLUMN_RADIUS * 2.0))
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _suspended_anchor() -> Vector3:
	var center := _observer if _has_observer else Vector3.ZERO
	center.y = minf(center.y, _bubble_top() - SUSPENDED_EXTENT.y - 0.25)
	return center

func _suspended_particle_aabb() -> AABB:
	var anchor := _suspended_anchor()
	return AABB(anchor - SUSPENDED_EXTENT - Vector3.ONE * 0.3, SUSPENDED_EXTENT * 2.0 + Vector3.ONE * 0.6)

func _particle_world_aabb() -> AABB:
	return _world_aabb(_fixed_particle_aabb().merge(_suspended_particle_aabb()))

func _world_aabb(local_box: AABB) -> AABB:
	var result := AABB()
	var first := true
	for x in [local_box.position.x, local_box.end.x]:
		for y in [local_box.position.y, local_box.end.y]:
			for z in [local_box.position.z, local_box.end.z]:
				var point_box := AABB(to_global(Vector3(x, y, z)), Vector3.ZERO)
				result = point_box if first else result.merge(point_box)
				first = false
	return result

func _apply_sunlight() -> void:
	beam_gain = _sunlight_strength

func _particle_material(is_bubble: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("bubble", is_bubble)
	material.set_shader_parameter("opacity", 0.55 if is_bubble else 0.32)
	material.set_shader_parameter("tint", Color(0.65, 0.90, 0.95) if is_bubble else Color(0.58, 0.82, 0.86))
	material.set_shader_parameter("soft_contact_distance", 0.18)
	material.set_shader_parameter("water_level", water_level)
	material.set_shader_parameter("region_view_depth", 10.0)
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
	# 只覆盖固定列与当前悬浮邻域，不用16km级大盒让粒子逃避剔除。
	node.custom_aabb = _fixed_particle_aabb().merge(_suspended_particle_aabb())
	return mm


func _prepare_geometry(node: GeometryInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.extra_cull_margin = 0.5


func set_view_depth(depth: float) -> void:
	_ensure_built()
	for beam in _beams:
		beam.material_override.set_shader_parameter("region_view_depth", depth)
	if _bubble_material != null:
		_bubble_material.set_shader_parameter("region_view_depth", depth)
	if _mote_material != null:
		_mote_material.set_shader_parameter("region_view_depth", depth)

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
	_bubble_material.set_shader_parameter("water_level", water_level)
	_mote_material.set_shader_parameter("water_level", water_level)


func _field_edge_alpha(p: Vector3) -> float:
	if not _has_observer:
		return 1.0
	var anchor := _suspended_anchor()
	var delta := (p - anchor).abs()
	var edge := minf(SUSPENDED_EXTENT.x - delta.x,
		minf(SUSPENDED_EXTENT.y - delta.y, SUSPENDED_EXTENT.z - delta.z))
	return smoothstep(0.0, SUSPENDED_FADE, maxf(edge, 0.0))

func _wrap_field(absolute: Vector3, center: Vector3) -> Vector3:
	var lower := center - SUSPENDED_EXTENT
	var span := SUSPENDED_EXTENT * 2.0
	return lower + Vector3(fposmod(absolute.x - lower.x, span.x),
		fposmod(absolute.y - lower.y, span.y), fposmod(absolute.z - lower.z, span.z))

func _suspended_bubble_state(spec: Dictionary, time: float) -> Dictionary:
	var base: Vector3 = spec.base
	var height := SUSPENDED_EXTENT.y * 2.0
	var age := fposmod(base.y + float(spec.phase) * height + time * float(spec.speed), height)
	var angle := float(spec.angle) + time * 0.17
	var anchor := _suspended_anchor()
	var absolute := Vector3(base.x + sin(angle) * 0.18,
		base.y + float(spec.phase) * height + time * float(spec.speed),
		base.z + cos(angle * 0.81) * 0.18)
	var p := _wrap_field(absolute, anchor)
	var diameter := float(spec.diameter) * (1.0 + age / height * 0.28)
	var alpha := smoothstep(0.0, 1.0, age) * (1.0 - smoothstep(height - 1.8, height, age)) * float(spec.alpha) * _field_edge_alpha(p)
	var size := Vector3(diameter, diameter * (1.06 + sin(angle) * 0.045), diameter)
	return {"transform": Transform3D(Basis().scaled(size), p), "alpha": alpha, "world_position": to_global(p)}

func _bubble_state(spec: Dictionary, time: float) -> Dictionary:
	if bool(spec.get("suspended", false)) and _has_observer:
		return _suspended_bubble_state(spec, time)
	var origin: Vector3 = spec.origin
	var height := _bubble_top() - origin.y
	var age := fposmod(float(spec.phase) * height + time * float(spec.speed), height)
	var angle := float(spec.angle) + time * 0.31
	var orbit: float = spec.orbit
	var p := origin + Vector3(sin(angle) * orbit + sin(angle * 0.63) * 0.13, age, cos(angle * 0.81) * orbit)
	var diameter := float(spec.diameter) * (1.0 + age / height * 0.28)
	var alpha := smoothstep(0.0, 0.85, age) * (1.0 - smoothstep(height - 2.8, height, age)) * float(spec.alpha)
	var size := Vector3(diameter, diameter * (1.06 + sin(angle) * 0.045), diameter)
	return {"transform": Transform3D(Basis().scaled(size), p), "alpha": alpha, "world_position": to_global(p)}


func _suspended_mote_state(spec: Dictionary, time: float) -> Dictionary:
	var base: Vector3 = spec.base
	var height := SUSPENDED_EXTENT.y * 2.0
	var age := fposmod(base.y + float(spec.phase) * height + time * float(spec.speed), height)
	var angle := float(spec.angle) + time * 0.12
	var anchor := _suspended_anchor()
	var absolute := Vector3(base.x + sin(angle) * 0.65,
		base.y + float(spec.phase) * height + time * float(spec.speed),
		base.z + cos(angle * 0.74) * 0.55)
	var p := _wrap_field(absolute, anchor)
	var alpha := smoothstep(0.0, 1.2, age) * (1.0 - smoothstep(height - 1.5, height, age)) * float(spec.alpha) * _field_edge_alpha(p)
	return {"transform": Transform3D(Basis().scaled(Vector3.ONE * float(spec.diameter)), p), "alpha": alpha, "world_position": to_global(p)}

func _mote_state(spec: Dictionary, time: float) -> Dictionary:
	if _has_observer:
		return _suspended_mote_state(spec, time)
	var origin: Vector3 = spec.origin
	var height := minf(_bubble_top() - 0.8 - origin.y, MOTE_BAND)
	var age := fposmod(float(spec.phase) * height + time * float(spec.speed), height)
	var angle := float(spec.angle) + time * 0.12
	var p := origin + Vector3(sin(angle) * 0.65, age, cos(angle * 0.74) * 0.55)
	var alpha := smoothstep(0.0, 1.8, age) * (1.0 - smoothstep(height - 2.0, height, age)) * float(spec.alpha)
	return {"transform": Transform3D(Basis().scaled(Vector3.ONE * float(spec.diameter)), p), "alpha": alpha, "world_position": to_global(p)}


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
	var near_bubbles := 0
	var near_motes := 0
	if _has_observer:
		for state in bubbles:
			near_bubbles += int(float(state.alpha) > 0.0 and state.world_position.distance_to(to_global(_observer)) <= 12.0)
		for state in motes:
			near_motes += int(float(state.alpha) > 0.0 and state.world_position.distance_to(to_global(_observer)) <= 12.0)
	return {"time": at, "seed": seed_value, "observer": to_global(_observer) if _has_observer else null,
		"has_observer": _has_observer, "world_coverage": _particle_world_aabb(),
		"near_bubbles": near_bubbles, "near_motes": near_motes,
		"bubbles": bubbles, "motes": motes, "rays": rays, "statistics": statistics()}


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
		"particle_ceiling_y": _bubble_top(),
		"fixed_bubble_instances": mini(FIXED_BUBBLE_COUNT, _bubble_specs.size()),
		"suspended_bubble_instances": maxi(0, _bubble_specs.size() - FIXED_BUBBLE_COUNT),
		"suspended_mote_instances": _mote_specs.size(),
		"has_observer": _has_observer,
		"world_coverage": _particle_world_aabb(),
		"water_level": water_level,
		"sunlight_strength": _sunlight_strength,
		"column_clearance_radius": COLUMN_RADIUS,
	}


## 固定列最大水平包络包含摆动和最大泡半径；父线程可对该圆柱做屋顶净空验收。
func column_envelopes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for column in $BubbleColumns.get_children():
		result.append({"id": str(column.name), "bottom": column.position, "top_y": _bubble_top(), "radius": COLUMN_RADIUS, "source": "fixed"})
	return result

## 仅报告悬浮场的世界采样结果；固定列净空仍由 column_envelopes() 负责。
func suspended_snapshot(time: float = -1.0) -> Dictionary:
	_ensure_built()
	var at := _clock if time < 0.0 else time
	var bubbles: Array[Dictionary] = []
	for i in range(FIXED_BUBBLE_COUNT, _bubble_specs.size()):
		bubbles.append(_bubble_state(_bubble_specs[i], at))
	var motes: Array[Dictionary] = []
	for spec in _mote_specs:
		motes.append(_mote_state(spec, at))
	return {"time": at, "observer": to_global(_observer) if _has_observer else null,
		"has_observer": _has_observer, "world_coverage": _particle_world_aabb(),
		"bubbles": bubbles, "motes": motes}
