@tool
extends "res://scripts/core/interactable.gd"
class_name GatherSpot
## 采集点：世界里的实体资源。
##
## 与旧实现的差别：
##   - 不是「点一下就进账」，而是走到跟前、按住 E 持续一段时间；
##   - 采完会枯竭并在原地再生（不同资源冷却不同），不是无限刷；
##   - 可以绑定建造前提（例如玻璃需要铁道站升到 2 级），未满足时给出原因；
##   - 产出带少量浮动（额外一份），由 id 派生的确定性随机决定，便于回归测试。

signal harvested(kind: String, amount: int, label: String)

## 资源元数据：标签、颜色、造型。
const KINDS := {
	"shell": {"label": "贝壳", "color": Color("#f4d9a8"), "shape": "shell", "respawn": 55.0, "hold": 1.0},
	"rope": {"label": "缆绳", "color": Color("#d9b483"), "shape": "rope", "respawn": 75.0, "hold": 1.3},
	"wood": {"label": "木料", "color": Color("#c08a52"), "shape": "log", "respawn": 80.0, "hold": 1.4},
	"parts": {"label": "零件", "color": Color("#b9c6d4"), "shape": "gear", "respawn": 95.0, "hold": 1.6},
	"glass": {"label": "玻璃", "color": Color("#9fe6e2"), "shape": "shard", "respawn": 110.0, "hold": 1.7},
	"seed": {"label": "种子", "color": Color("#a8d873"), "shape": "seed", "respawn": 60.0, "hold": 0.9},
	"fish": {"label": "鱼", "color": Color("#8fd2ef"), "shape": "fish", "respawn": 70.0, "hold": 1.2},
	"pearl": {"label": "珍珠", "color": Color("#f3f6ff"), "shape": "pearl", "respawn": 130.0, "hold": 1.8},
}

@export var kind: String = "wood"
@export var amount: int = 1
@export var respawn: float = 60.0
@export var bonus_chance: float = 0.18
## 建造前提：requires_site 达到 requires_level 才能采。
@export var requires_site: String = ""
@export var requires_level: int = 0

var available := true
var cooldown_left := 0.0

var _prop: Node3D
var _prop_mat: StandardMaterial3D
var _beacon: MeshInstance3D
var _shadow: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _rest_scale := Vector3.ONE


func setup(data: Dictionary) -> void:
	id = str(data.get("id", id))
	kind = str(data.get("kind", kind))
	var meta: Dictionary = KINDS.get(kind, {})
	label = str(data.get("label", meta.get("label", kind)))
	verb = "采集"
	amount = int(data.get("amount", 1))
	hold_time = float(data.get("hold", meta.get("hold", 1.2)))
	respawn = float(data.get("respawn", meta.get("respawn", 60.0)))
	priority = int(data.get("priority", 0))
	accent = meta.get("color", accent)
	requires_site = str(data.get("requires_site", ""))
	requires_level = int(data.get("requires_level", 0))
	position = Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	_rng.seed = hash(id)


func _on_ready() -> void:
	# 采集物在俯视镜头里只有十几像素，直接按真实尺寸做会看不见。
	# 统一放大到 1.45 倍，再加一颗缓慢起伏的信号珠（不是图标，只是让视线能抓到一个亮点）。
	_rest_scale = Vector3.ONE * 1.45
	_build_prop()
	_build_shadow()
	_build_beacon()


## 接触阴影：没有它，小物件会像贴纸一样浮在甲板上。
func _build_shadow() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.30
	disc.bottom_radius = 0.30
	disc.height = 0.008
	disc.radial_segments = 16
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	_shadow.mesh = disc
	_shadow.position = Vector3(0, 0.012, 0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.02, 0.10, 0.14, 0.20)
	_shadow.material_override = mat
	add_child(_shadow)


func _build_beacon() -> void:
	var beacon := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.055
	m.height = 0.11
	m.radial_segments = 8
	m.rings = 5
	beacon.mesh = m
	beacon.name = "Beacon"
	beacon.position = Vector3(0, 0.92, 0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.9)
	mat.emission_enabled = true
	mat.emission = accent
	mat.emission_energy_multiplier = 0.85
	beacon.material_override = mat
	add_child(beacon)
	_beacon = beacon
	# 只有「有货」时才亮；采空后靠冷却恢复，珠子也跟着暗下去。
	var tween := create_tween().set_loops()
	tween.tween_property(beacon, "position:y", 1.04, 1.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(beacon, "position:y", 0.90, 1.1).set_trans(Tween.TRANS_SINE)


func _on_tick(delta: float) -> void:
	if available:
		if _prop != null:
			_prop.position.y = 0.12 + sin(_t * 1.7) * 0.035
		return
	cooldown_left -= delta
	if cooldown_left <= 0.0:
		_restore()


func can_interact() -> bool:
	return available


func blocked_reason() -> String:
	if not available:
		return "还要 %.0f 秒才能再采" % maxf(cooldown_left, 0.0)
	if requires_site != "" and Economy.site_level(requires_site) < requires_level:
		return "需要 %s 升到 %d 级" % [str(Economy.SITES.get(requires_site, {}).get("name", requires_site)), requires_level]
	return ""


func interact(_actor: Node3D) -> Dictionary:
	var reason := blocked_reason()
	if reason != "":
		return {"blocked": reason}
	var gain := amount
	# 额外产出：小概率多一份。用 id 派生的随机，重跑脚本结果一致。
	if _rng.randf() < bonus_chance:
		gain += 1
	available = false
	cooldown_left = respawn
	_dim()
	harvested.emit(kind, gain, label)
	return {"kind": kind, "amount": gain}


## 测试/存档用：直接推进冷却。
func debug_advance(seconds: float) -> void:
	if available:
		return
	cooldown_left -= seconds
	if cooldown_left <= 0.0:
		_restore()


func seconds_left() -> float:
	return maxf(cooldown_left, 0.0)


## 存档用：把采集点摆回「还剩 N 秒」的状态。
## 0 秒 = 有货；大于 0 按枯竭处理（造型缩暗、信号珠熄灭），
## 必须走 _dim()，否则读档后物件看着还在、却采不了。
func restore_cooldown(seconds: float) -> void:
	var left := maxf(seconds, 0.0)
	if left <= 0.0:
		if not available:
			_restore()
		return
	available = false
	cooldown_left = left
	_dim()


func _restore() -> void:
	available = true
	cooldown_left = 0.0
	if _beacon != null:
		_beacon.visible = true
	if _shadow != null:
		_shadow.visible = true
	if _prop != null:
		var tw := create_tween()
		tw.tween_property(_prop, "scale", _rest_scale, 0.35).set_trans(Tween.TRANS_BACK)
	if _prop_mat != null:
		_prop_mat.albedo_color = _base_color()


func _dim() -> void:
	if _beacon != null:
		_beacon.visible = false
	if _shadow != null:
		_shadow.visible = false
	if _prop != null:
		_prop.scale = _rest_scale * 0.38
	if _prop_mat != null:
		var c := _base_color()
		_prop_mat.albedo_color = Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, 1.0)


func _base_color() -> Color:
	return accent


## 造型：每种资源一个可辨认的小物件，全部程序化生成，不依赖贴图。
func _build_prop() -> void:
	_prop = Node3D.new()
	_prop.name = "Prop"
	_prop.position = Vector3(0, 0.12, 0)
	_prop.scale = _rest_scale
	add_child(_prop)

	_prop_mat = StandardMaterial3D.new()
	_prop_mat.albedo_color = accent
	_prop_mat.roughness = 0.85
	_prop_mat.metallic = 0.0
	_prop_mat.rim_enabled = true
	_prop_mat.rim = 0.25

	var meta: Dictionary = KINDS.get(kind, {})
	match str(meta.get("shape", "seed")):
		"shell":
			_add_mesh(_prop, _sphere(0.17, 14, 8), Vector3(0, 0.10, 0), Vector3(1.25, 0.55, 1.0))
			_add_mesh(_prop, _cone(0.10, 0.22, 12), Vector3(0.02, 0.16, 0), Vector3.ONE, Vector3(0, 0, 0.35))
		"rope":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.13
			torus.outer_radius = 0.20
			torus.rings = 16
			_add_mesh(_prop, torus, Vector3(0, 0.10, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
			_add_mesh(_prop, torus, Vector3(0.03, 0.19, 0), Vector3(0.86, 0.86, 0.86), Vector3(PI * 0.5, 0.4, 0))
		"log":
			_add_mesh(_prop, _cylinder(0.11, 0.11, 0.62, 10), Vector3(0, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
			_add_mesh(_prop, _cylinder(0.115, 0.115, 0.06, 10), Vector3(0.30, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
		"gear":
			_add_mesh(_prop, _cylinder(0.16, 0.16, 0.09, 10), Vector3(0, 0.10, 0), Vector3.ONE)
			for i in 6:
				var a := TAU * float(i) / 6.0
				_add_mesh(_prop, _box(0.07, 0.045, 0.05), Vector3(cos(a) * 0.19, 0.10, sin(a) * 0.19), Vector3.ONE, Vector3(0, -a, 0))
		"shard":
			_add_mesh(_prop, _box(0.22, 0.34, 0.05), Vector3(0, 0.18, 0), Vector3.ONE, Vector3(0.18, 0.3, 0.42))
			_add_mesh(_prop, _box(0.13, 0.22, 0.04), Vector3(0.13, 0.12, 0.05), Vector3.ONE, Vector3(-0.2, 0.8, 0.3))
		"seed":
			_add_mesh(_prop, _sphere(0.13, 12, 8), Vector3(0, 0.12, 0), Vector3(1.0, 1.15, 1.0))
			_add_mesh(_prop, _cone(0.05, 0.16, 8), Vector3(0.02, 0.26, 0), Vector3.ONE, Vector3(0, 0, -0.4))
		"fish":
			_add_mesh(_prop, _capsule(0.09, 0.28, 8, 8), Vector3(0, 0.14, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
			_add_mesh(_prop, _box(0.02, 0.12, 0.10), Vector3(-0.16, 0.14, 0), Vector3.ONE, Vector3(0, 0, 0.5))
		"pearl":
			_add_mesh(_prop, _sphere(0.14, 16, 10), Vector3(0, 0.14, 0), Vector3.ONE)
			_add_mesh(_prop, _cylinder(0.22, 0.22, 0.06, 14), Vector3(0, 0.04, 0), Vector3.ONE)
		_:
			_add_mesh(_prop, _sphere(0.12, 12, 8), Vector3(0, 0.12, 0), Vector3.ONE)

	if requires_site != "":
		# 上锁的采集点：一根细立柱，远远就能看出这里还没解锁。
		var post := _cylinder(0.025, 0.025, 0.55, 6)
		var m := _add_mesh(_prop, post, Vector3(0, 0.28, 0), Vector3.ONE)
		var dark := _prop_mat.duplicate() as StandardMaterial3D
		dark.albedo_color = Color(0.55, 0.62, 0.66, 1.0)
		m.material_override = dark


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.material_override = _prop_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _sphere(r: float, seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _cone(r: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	return m


func _cylinder(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	return m


func _capsule(r: float, h: float, seg: int, rings: int) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m
