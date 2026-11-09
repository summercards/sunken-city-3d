extends Node3D
## 海底世界的动态部分：鱼群 / 气泡 / 光柱 / 浮游微粒 / 水面顶盖 / 灯光。
##
## 静态几何在 region_*.tscn 里（glb 资产），这里只放「每帧要动」的东西。
## 数值全部对齐网页版 underwater-art.js：
##   鱼群 7 群 × 24 条，绕群心做椭圆巡游；
##   气泡 96 个：前48个从6个热泉口升起，后48个为相机邻域悬浮场；
##   光柱 9 道，始终朝向相机；
##   微粒 180 颗使用共享 QuadMM 粒子shader的稳定悬浮邻域。

const MaterialLib = preload("res://src/diving/uw_materials.gd")
const WATER_LEVEL := 1.12

const FISH_COUNT := 24
const BUBBLE_COUNT := 96
const MOTE_COUNT := 180
const PARTICLE_SHADER = preload("res://shaders/sunroom_underwater_particles.gdshader")
const FIXED_BUBBLE_COUNT := 48
const FIELD_EXTENT := Vector3(12.0, 8.0, 12.0)
const FIELD_FADE := 1.5

## 网页版里的 vents 常量（热泉口）。
const VENTS := [
	Vector3(-12, -18, 17), Vector3(7, -31, -7), Vector3(-6, -46, -19),
	Vector3(7, -59, 12), Vector3(1, -74, -27), Vector3(-8, -14, -10),
]

var _fish: Array = []          # [{mmi, center, phase, members:[{offset, phase}]}]
var _bubbles: MultiMeshInstance3D
var _bubble_mm: MultiMesh
var _beams: Array = []
var _motes: MultiMeshInstance3D
var _bubble_specs: Array[Dictionary] = []
var _mote_specs: Array[Dictionary] = []
var _observer := Vector3.ZERO
var _has_observer := false
var _ceiling: MeshInstance3D
var _key: DirectionalLight3D
var _fill: OmniLight3D
var _t := 0.0
var _sun_strength := 1.0

func configure_underwater_light(profile: Dictionary) -> void:
	_sun_strength = clampf(float(profile.get("strength",1.0)),0.0,1.0)
	if _ceiling != null:
		var mat: ShaderMaterial = _ceiling.material_override
		MaterialLib.configure_underside(mat, profile.get("surface", {}))
		mat.set_shader_parameter("sun_direction",profile.get("direction",Vector3(0.5191,0.7787,-0.3523)))
		mat.set_shader_parameter("sun_color",profile.get("color",Color(1.0,0.955,0.8)))
		mat.set_shader_parameter("sun_strength",_sun_strength)
	for beam in _beams:
		beam.material_override.set_shader_parameter("sun_strength",_sun_strength)

var _rng := RandomNumberGenerator.new()


func setup(fish_specs: Array) -> void:
	_rng.seed = 71
	_build_fish(fish_specs)
	_build_bubbles()
	_build_beams()
	_build_motes()
	_build_ceiling()
	_build_lights()


func _build_fish(specs: Array) -> void:
	var scene: PackedScene=preload("res://scenes/decorations/animals/fish_school.tscn")
	for i in specs.size():
		var spec: Dictionary=specs[i]
		var school=scene.instantiate()
		school.name="FishSchool%d" % i;school.instance_id="dive/fish/%02d" % i
		school.autonomous=false;school.count=FISH_COUNT
		school.orbit_radius=Vector2(7.0,3.8);school.spread_radius=7.0
		school.size_scale=1.12 if i < 3 else (1.06 if i < 5 else 1.0)
		school.seed_value=71+i
		# 配色按网页版 underwater-art.js 轮换；材质由水下材质库注入，保留深度雾与头灯。
		school.palette="dive";school.palette_index=i
		school.phase=float(spec.get("phase",0))
		var center: Array=spec.get("center",[0,-13,0])
		school.position=Vector3(center[0],center[1],center[2]);add_child(school)
		school.apply_underwater_materials(MaterialLib)
		_fish.append({"mmi":school,"component":school})


func _build_bubbles() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("bubble", true)
	mat.set_shader_parameter("opacity", 0.55)
	mat.set_shader_parameter("tint", Color(0.65, 0.90, 0.95))
	mat.set_shader_parameter("soft_contact_distance", 0.18)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	mat.set_shader_parameter("region_view_depth", 10.0)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_bubble_mm = MultiMesh.new()
	_bubble_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bubble_mm.use_colors = true
	_bubble_mm.mesh = quad
	_bubble_mm.instance_count = BUBBLE_COUNT
	_bubble_specs.clear()
	for i in BUBBLE_COUNT - FIXED_BUBBLE_COUNT:
		_bubble_specs.append({"base": Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-8.0, 8.0), _rng.randf_range(-12.0, 12.0)), "phase": _rng.randf(), "speed": _rng.randf_range(0.15, 0.45), "size": 0.22 if i % 11 == 0 else _rng.randf_range(0.09, 0.18)})
	_bubbles = MultiMeshInstance3D.new()
	_bubbles.name = "VentBubbles"
	_bubbles.multimesh = _bubble_mm
	_bubbles.material_override = mat
	for i in range(BUBBLE_COUNT - FIXED_BUBBLE_COUNT):
		_bubble_mm.set_instance_color(FIXED_BUBBLE_COUNT + i, Color(0.86, 1.0, 0.96, 0.78))
	_bubbles.custom_aabb = _particle_aabb()
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubbles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_bubbles)


func _build_beams() -> void:
	var shader: Shader = load("res://shaders/uw_beam.gdshader")
	for i in 9:
		var quad := QuadMesh.new()
		quad.size = Vector2(3.5 + float(i % 3), 60.0)
		var mi := MeshInstance3D.new()
		mi.name = "LightBeam%d" % i
		mi.mesh = quad
		mi.material_override = ShaderMaterial.new()
		mi.material_override.shader = shader
		mi.position = Vector3(-20.0 + i * 5.0, -28.0, -20.0 + float(i % 3) * 15.0)
		mi.rotation.z = -0.16
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		_beams.append(mi)


func _build_motes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("bubble", false)
	mat.set_shader_parameter("opacity", 0.32)
	mat.set_shader_parameter("tint", Color(0.58, 0.82, 0.86))
	mat.set_shader_parameter("soft_contact_distance", 0.18)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	mat.set_shader_parameter("region_view_depth", 10.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MOTE_COUNT
	for i in MOTE_COUNT:
		var p := Vector3(-35.0 + _rng.randf() * 65.0, -75.0 + _rng.randf() * 75.0, -35.0 + _rng.randf() * 65.0)
		_mote_specs.append({"base": Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-8.0, 8.0), _rng.randf_range(-12.0, 12.0)), "phase": _rng.randf(), "speed": _rng.randf_range(0.03, 0.08), "size": _rng.randf_range(0.025, 0.06), "alpha": _rng.randf_range(0.24, 0.72)})
		mm.set_instance_color(i, Color(0.88, 1.0, 0.91, 0.0))

	_motes = MultiMeshInstance3D.new()
	_motes.name = "Motes"
	_motes.multimesh = mm
	_motes.material_override = mat
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_motes.custom_aabb = _particle_aabb()
	add_child(_motes)


func _build_ceiling() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(420, 420)
	_ceiling = MeshInstance3D.new()
	_ceiling.name = "WaterCeiling"
	_ceiling.mesh = plane
	_ceiling.position = Vector3(0, WATER_LEVEL, 0)
	_ceiling.material_override = ShaderMaterial.new()
	_ceiling.material_override.shader = load("res://shaders/uw_ceiling.gdshader")
	MaterialLib.configure_underside(_ceiling.material_override)
	_ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ceiling.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_ceiling)


func _build_lights() -> void:
	_key = DirectionalLight3D.new()
	_key.name = "UnderwaterKey"
	_key.light_color = Color("#edffe3")
	_key.light_energy = (3.0 / PI)
	# 与网页版一致：主光投影。深度/绕序问题在实体材质和导入阶段修复。
	_key.shadow_enabled = true
	_key.shadow_bias = 0.05
	_key.shadow_normal_bias = 0.5
	_key.light_angular_distance = 0.5
	_key.directional_shadow_max_distance = 120.0
	add_child(_key)
	_key.look_at_from_position(Vector3(18, 24, 18), Vector3(-9, -40, -6), Vector3.UP)

	_fill = OmniLight3D.new()
	_fill.name = "DiverFill"
	_fill.light_color = Color("#a1f7ef")
	_fill.omni_range = 32.0
	_fill.light_energy = 55.0 / PI
	_fill.omni_attenuation = 2.0
	add_child(_fill)

	# 深沟里给巨型珊瑚补三盏冷光（网页版 north-trench.js 末尾）。
	for spec in [
		[Vector3(-18, -205, -125), Color("#67d9d9"), 1600.0],
		[Vector3(20, -207, -135), Color("#c6a2ef"), 1400.0],
		[Vector3(0, -199, -122), Color("#b9dfd2"), 1100.0],
	]:
		var lamp := OmniLight3D.new()
		lamp.position = spec[0]
		lamp.light_color = spec[1]
		lamp.omni_range = 65.0
		lamp.light_energy = float(spec[2]) / PI
		lamp.omni_attenuation = 2.0
		add_child(lamp)


## 诊断：按类别藏掉动态装饰，用来分清画面问题来自静态几何还是这些会动的东西。
## kind ∈ fish / beam / bubble / mote / ceiling / all
func hide_kind(kind: String) -> void:
	match kind:
		"fish":
			for school in _fish:
				(school.mmi as Node3D).visible = false
		"beam":
			for b in _beams:
				(b as Node3D).visible = false
		"bubble":
			if _bubbles != null:
				_bubbles.visible = false
		"mote":
			if _motes != null:
				_motes.visible = false
		"ceiling":
			if _ceiling != null:
				_ceiling.visible = false
		"all":
			visible = false


func update(dt: float, t: float, diver: Vector3, cam: Camera3D) -> void:
	_t = t
	if cam != null and cam.global_position.is_finite():
		_observer = to_local(cam.global_position)
		_has_observer = true
		_update_particle_aabb()
	_update_fish(t)
	_update_bubbles(t)
	_update_beams(cam)
	_update_motes(t)
	_update_lights(diver)
	for particles in [_bubbles, _motes]:
		if particles != null:
			particles.material_override.set_shader_parameter("region_view_depth", maxf(0.0, WATER_LEVEL-diver.y))
	if _ceiling != null:
		_ceiling.material_override.set_shader_parameter("elapsed",t)
		# 水膜跟着人走，潜到海沟深处也能看到头顶的水面。
		_ceiling.global_position = Vector3(diver.x, WATER_LEVEL, diver.z)


func _update_fish(t: float) -> void:
	for school in _fish: school.component.sample(t)


func _field_anchor() -> Vector3:
	return Vector3(_observer.x, minf(_observer.y, WATER_LEVEL - 1.02 - FIELD_EXTENT.y), _observer.z)

func _field_edge_alpha(p: Vector3) -> float:
	var anchor := _field_anchor()
	var delta := (p - anchor).abs()
	var edge := minf(FIELD_EXTENT.x - delta.x,
		minf(FIELD_EXTENT.y - delta.y, FIELD_EXTENT.z - delta.z))
	return smoothstep(0.0, FIELD_FADE, maxf(edge, 0.0))

func _particle_aabb() -> AABB:
	var fixed := AABB(VENTS[0] - Vector3(0.8, 0.0, 0.8), Vector3(1.6, WATER_LEVEL - VENTS[0].y, 1.6))
	for i in range(1, VENTS.size()):
		var vent: Vector3 = VENTS[i]
		fixed = fixed.merge(AABB(vent - Vector3(0.8, 0.0, 0.8), Vector3(1.6, WATER_LEVEL - vent.y, 1.6)))
	var field := AABB(_field_anchor() - FIELD_EXTENT - Vector3.ONE * 0.3, FIELD_EXTENT * 2.0 + Vector3.ONE * 0.6)
	return fixed.merge(field)

func _update_particle_aabb() -> void:
	var bounds := _particle_aabb()
	if _bubbles != null:
		_bubbles.custom_aabb = bounds
	if _motes != null:
		_motes.custom_aabb = bounds

func _wrap_field(absolute: Vector3, center: Vector3) -> Vector3:
	var lower := center - FIELD_EXTENT
	var span := FIELD_EXTENT * 2.0
	return lower + Vector3(fposmod(absolute.x - lower.x, span.x),
		fposmod(absolute.y - lower.y, span.y), fposmod(absolute.z - lower.z, span.z))

func _suspended_bubble_state(j: int, t: float) -> Dictionary:
	var spec: Dictionary = _bubble_specs[j]
	var base: Vector3 = spec.base
	var height := FIELD_EXTENT.y * 2.0
	var age: float = fposmod(base.y + float(spec.phase) * height + t * float(spec.speed), height)
	var anchor := _field_anchor()
	var absolute := Vector3(base.x + sin(t * 0.17 + j) * 0.18,
		base.y + float(spec.phase) * height + t * float(spec.speed),
		base.z + cos(t * 0.13 + j * 0.81) * 0.18)
	var pos := _wrap_field(absolute, anchor)
	var alpha := _field_edge_alpha(pos)
	alpha *= 1.0 - smoothstep(WATER_LEVEL - 2.0, WATER_LEVEL - 0.8, pos.y)
	var size := float(spec.size) * (1.0 + age / height * 0.28)
	return {"transform": Transform3D(Basis().scaled(Vector3.ONE * size), pos), "alpha": alpha}

func _suspended_mote_state(i: int, t: float) -> Dictionary:
	var spec: Dictionary = _mote_specs[i]
	var base: Vector3 = spec.base
	var height := FIELD_EXTENT.y * 2.0
	var age: float = fposmod(base.y + float(spec.phase) * height + t * float(spec.speed), height)
	var angle := float(i) * 2.399963 + t * 0.12
	var anchor := _field_anchor()
	var absolute := Vector3(base.x + sin(angle) * 0.65,
		base.y + float(spec.phase) * height + t * float(spec.speed),
		base.z + cos(angle * 0.74) * 0.55)
	var pos := _wrap_field(absolute, anchor)
	var alpha := smoothstep(0.0, 1.2, age) * (1.0 - smoothstep(height - 1.5, height, age)) * float(spec.alpha) * _field_edge_alpha(pos)
	alpha *= 1.0 - smoothstep(WATER_LEVEL - 2.0, WATER_LEVEL - 0.8, pos.y)
	return {"transform": Transform3D(Basis().scaled(Vector3.ONE * float(spec.size)), pos), "alpha": alpha}

func _update_bubbles(t: float) -> void:
	if _bubble_mm == null:
		return
	for i in BUBBLE_COUNT:
		var pos: Vector3
		var alpha := 0.78
		var s: float
		if i < FIXED_BUBBLE_COUNT or not _has_observer:
			var v: Vector3 = VENTS[i % VENTS.size()]
			var age: float = fmod(t * 0.85 + float(i) * 0.71, 13.0)
			pos = Vector3(v.x + sin(t * 0.8 + float(i)) * 0.17, v.y + age, v.z + cos(t * 0.65 + float(i)) * 0.14)
			s = 0.035 + float(i % 4) * 0.018 + age * 0.006
		else:
			var state := _suspended_bubble_state(i - FIXED_BUBBLE_COUNT, t)
			pos = state.transform.origin
			alpha = state.alpha
			s = state.transform.basis.get_scale().x
		_bubble_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pos))
		_bubble_mm.set_instance_color(i, Color(0.86, 1.0, 0.96, alpha))


func _update_beams(cam: Camera3D) -> void:
	for beam in _beams:
		var b: MeshInstance3D = beam
		var d := cam.global_position - b.position
		b.rotation.y = atan2(d.x, d.z)


func _update_motes(t: float) -> void:
	if _motes == null:
		return
	var mm: MultiMesh = _motes.multimesh
	for i in MOTE_COUNT:
		var state := _suspended_mote_state(i, t)
		mm.set_instance_transform(i, state.transform)
		mm.set_instance_color(i, Color(0.88, 1.0, 0.91, state.alpha))

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

func suspended_snapshot(t: float = -1.0) -> Dictionary:
	var at := _t if t < 0.0 else t
	var bubbles: Array[Dictionary] = []
	for i in range(FIXED_BUBBLE_COUNT, BUBBLE_COUNT):
		var state := _suspended_bubble_state(i - FIXED_BUBBLE_COUNT, at)
		bubbles.append({"world_position": to_global(state.transform.origin), "alpha": state.alpha, "transform":state.transform})
	var motes: Array[Dictionary] = []
	for i in MOTE_COUNT:
		var state := _suspended_mote_state(i, at)
		motes.append({"world_position": to_global(state.transform.origin), "alpha": state.alpha, "transform":state.transform})
	var near_bubbles := 0
	var near_motes := 0
	if _has_observer:
		var observer := to_global(_observer)
		for state in bubbles:
			near_bubbles += int(float(state.alpha) > 0.0 and state.world_position.distance_to(observer) <= 12.0)
		for state in motes:
			near_motes += int(float(state.alpha) > 0.0 and state.world_position.distance_to(observer) <= 12.0)
	return {"time": at, "observer": to_global(_observer) if _has_observer else null,
		"has_observer": _has_observer, "world_coverage": _world_aabb(_particle_aabb()),
		"near_bubbles": near_bubbles, "near_motes": near_motes,
		"bubbles": bubbles, "motes": motes}


func _update_lights(diver: Vector3) -> void:
	var deep: float = clampf((-diver.y - 12.0) / 64.0, 0.0, 1.0)
	if _key != null:
		_key.light_energy = (3.0 / PI) * (1.0 - deep * 0.75) * _sun_strength
	if _fill != null:
		_fill.global_position = diver + Vector3(0, 2, 3)
