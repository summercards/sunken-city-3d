extends Node3D
## 海底世界的动态部分：鱼群 / 气泡 / 光柱 / 浮游微粒 / 水面顶盖 / 灯光。
##
## 静态几何在 region_*.tscn 里（glb 资产），这里只放「每帧要动」的东西。
## 数值全部对齐网页版 underwater-art.js：
##   鱼群 7 群 × 18 条，绕群心做椭圆巡游；
##   气泡 96 个，从 6 个热泉口升起，13 秒一循环；
##   光柱 9 道，始终朝向相机；
##   微粒 180 颗，缓慢上浮到水面后回到 -75m。

const MaterialLib = preload("res://src/diving/uw_materials.gd")
const WATER_LEVEL := 1.12

const FISH_COUNT := 18
const BUBBLE_COUNT := 96
const MOTE_COUNT := 180

## 网页版里的 vents 常量（热泉口）。
const VENTS := [
	Vector3(-7, -18, 3), Vector3(7, -31, -7), Vector3(-6, -46, -19),
	Vector3(7, -59, 12), Vector3(1, -74, -27), Vector3(-8, -14, -10),
]

var _fish: Array = []          # [{mmi, center, phase, members:[{offset, phase}]}]
var _bubbles: MultiMeshInstance3D
var _bubble_mm: MultiMesh
var _beams: Array = []
var _motes: MultiMeshInstance3D
var _mote_pos: PackedVector3Array
var _ceiling: MeshInstance3D
var _key: DirectionalLight3D
var _fill: OmniLight3D
var _t := 0.0

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
		school.autonomous=false;school.orbit_radius=Vector2(6,3);school.spread_radius=6.2
		school.seed_value=71+i
		# 配色按网页版 underwater-art.js 轮换；材质由水下材质库注入，保留深度雾与头灯。
		school.palette="dive";school.palette_index=i
		school.phase=float(spec.get("phase",0))
		var center: Array=spec.get("center",[0,-13,0])
		school.position=Vector3(center[0],center[1],center[2]);add_child(school)
		school.apply_underwater_materials(MaterialLib)
		_fish.append({"mmi":school,"component":school})


func _build_bubbles() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 9
	sphere.rings = 7

	var mat := MaterialLib.from_color(Color("#d3fff1"), {
		"alpha": true, "opacity": 0.38, "roughness": 0.1, "metallic": 0.15,
	})

	_bubbles = MultiMeshInstance3D.new()
	_bubbles.name = "VentBubbles"
	_bubbles.multimesh = _bubble_mm
	_bubbles.material_override = mat
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
	# 微粒用小球而不是 billboard 薄片：180 个实例的开销可以忽略，
	# 省掉一个 billboard 着色器，也避免贴着镜头时出现薄片侧影。
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 5
	dot.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 1.0, 0.88, 0.32)

	_mote_pos = PackedVector3Array()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = MOTE_COUNT
	for i in MOTE_COUNT:
		var p := Vector3(
			-35.0 + _rng.randf() * 65.0,
			-75.0 + _rng.randf() * 75.0,
			-35.0 + _rng.randf() * 65.0)
		_mote_pos.append(p)
		mm.set_instance_transform(i, Transform3D(Basis(), p))

	_motes = MultiMeshInstance3D.new()
	_motes.name = "Motes"
	_motes.multimesh = mm
	_motes.material_override = mat
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
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
	_update_fish(t)
	_update_bubbles(t)
	_update_beams(cam)
	_update_motes(dt)
	_update_lights(diver)
	if _ceiling != null:
		# 水膜跟着人走，潜到海沟深处也能看到头顶的水面。
		_ceiling.global_position = Vector3(diver.x, WATER_LEVEL, diver.z)


func _update_fish(t: float) -> void:
	for school in _fish: school.component.sample(t)


func _update_bubbles(t: float) -> void:
	if _bubble_mm == null:
		return
	for i in BUBBLE_COUNT:
		var v: Vector3 = VENTS[i % VENTS.size()]
		var age: float = fmod(t * 0.85 + float(i) * 0.71, 13.0)
		var pos := Vector3(
			v.x + sin(t * 0.8 + float(i)) * 0.17,
			v.y + age,
			v.z + cos(t * 0.65 + float(i)) * 0.14)
		var s: float = 0.035 + float(i % 4) * 0.018 + age * 0.006
		_bubble_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pos))


func _update_beams(cam: Camera3D) -> void:
	for beam in _beams:
		var b: MeshInstance3D = beam
		var d := cam.global_position - b.position
		b.rotation.y = atan2(d.x, d.z)


func _update_motes(dt: float) -> void:
	if _motes == null:
		return
	var mm: MultiMesh = _motes.multimesh
	for i in MOTE_COUNT:
		var p: Vector3 = _mote_pos[i]
		p.y += dt * 0.18
		if p.y > 0.0:
			p.y = -75.0
		_mote_pos[i] = p
		mm.set_instance_transform(i, Transform3D(Basis(), p))


func _update_lights(diver: Vector3) -> void:
	var deep: float = clampf((-diver.y - 12.0) / 64.0, 0.0, 1.0)
	if _key != null:
		_key.light_energy = (3.0 / PI) * (1.0 - deep * 0.75)
	if _fill != null:
		_fill.global_position = diver + Vector3(0, 2, 3)
