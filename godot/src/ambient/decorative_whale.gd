extends "res://src/ambient/scene_component.gd"
## 深海巨鲸：外观、配色和摆动节奏照网页版 `web/gameplay.js`（1249–1305 建模，3533–3543 巡游）。
##
## 网页版是四件东西拼起来的：
##   头部球 + 躯干球（两块椭球） / 两块 Box 胸鳍 / 圆锥尾段 / 一块 Box 尾鳍。
##
## 上一版读起来像一根灰青色香肠，原因不在参数而在构件：
## 多塞了一块椭球"腹部"、把尾段做成椭球、把尾鳍做成两片椭球、还加了两颗球状眼。
## 这四样网页版都没有，所以形状永远对不上。这里按网页版的构件表重建。
##
## 2026-10-28 第四次修订：材质退回普通标准材质。
##
## 此前走 `toon.gdshader` + `depth_tint` + `ambient_boost` + `uw_glow_amount` 三层补偿，
## 外加一圈背面外扩的青色描边壳 —— 效果很"演出"，但那是给水面巡游用的舞台光。
## 现在要求它像场景里的普通物体一样被光照、被阴影、被后处理统一处理，
## 所以只留一个深灰 StandardMaterial3D：不做自发光、不做深度染色、不做描边。
##
## 代价写在明面上：水下 4.5 m 处它比之前暗。这是普通材质的必然结果，
## 本次明确不再为它单独补偿 —— 要亮就让场景光照去亮，不在材质里作弊。
const BODY_COLOR := Color("#59606a")
## 鳍和尾鳍压暗半档。不是自发光，是纯 albedo 差，靠漫反射明暗读结构。
const FIN_COLOR := Color("#4c525b")
## 深灰不反光，不做金属。粗糙度给高，避免在浅水段被镜面反射打成一块亮斑。
const BODY_ROUGHNESS := 0.88

@export var orbit_radius := Vector2(8.0, 3.0)
@export var swim_speed := 0.16
## 垂直起伏幅度（网页版 0.65）。
@export var dive_sway := 0.65
@export var phase := 0.0
@export_range(0.2, 2.0, 0.05) var size_scale := 1.0

var body: Node3D
var tail: Node3D
var fluke: Node3D
var elapsed := 0.0


func _ready() -> void:
	component_kind = "decoration"
	subcategory = "animals"
	asset_id = "SEA-DECO-ANIMAL-WHALE"
	set_meta("visual_only", true)
	body = Node3D.new()
	body.name = "WhaleBody"
	body.scale = Vector3.ONE * size_scale
	add_child(body)
	_build()
	sample(0.0)


func _build() -> void:
	var skin := _mat(BODY_COLOR)
	var fin := _mat(FIN_COLOR)

	# ---- 躯干：网页版 SphereGeometry 半径 × scale ----
	var head_mesh := _sphere(18, 12)
	_torso_part("Head", head_mesh, Vector3(0, 0, 1.6), Vector3(1.4175, 1.107, 2.97), skin)
	var torso_mesh := _sphere(18, 12)
	_torso_part("Torso", torso_mesh, Vector3(0, 0, -0.8), Vector3(1.42, 1.207, 3.408), skin)

	# ---- 胸鳍：Box(2.6, 0.14, 0.85)，外撇并下压 ----
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for side in [-1.0, 1.0]:
		var pectoral := MeshInstance3D.new()
		# 名字必须唯一：同名兄弟会被 Godot 改成 @MeshInstance3D@3，
		# 之后任何按名字找鳍的代码/测试都会只找到一块。
		pectoral.name = "PectoralFinR" if side > 0.0 else "PectoralFinL"
		pectoral.mesh = box
		pectoral.material_override = fin
		pectoral.position = Vector3(side * 1.85, -0.35, 0.4)
		pectoral.rotation = Vector3(0.0, side * -0.35, side * -0.25)
		pectoral.scale = Vector3(2.6, 0.14, 0.85)
		body.add_child(pectoral)

	# ---- 尾段：圆锥，尖端朝 +Z ----
	tail = Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0, -3.2)
	body.add_child(tail)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.95
	cone.height = 3.6
	cone.radial_segments = 10
	cone.rings = 1
	var tail_seg := MeshInstance3D.new()
	tail_seg.name = "TailSegment"
	tail_seg.mesh = cone
	tail_seg.material_override = skin
	tail_seg.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	tail_seg.position = Vector3(0, 0, -1.6)
	tail.add_child(tail_seg)

	# ---- 尾鳍：一块水平 Box ----
	fluke = Node3D.new()
	fluke.name = "Fluke"
	fluke.position = Vector3(0, 0, -3.3)
	tail.add_child(fluke)
	var blade := MeshInstance3D.new()
	blade.name = "FlukeBlade"
	blade.mesh = box
	blade.material_override = fin
	blade.scale = Vector3(3.4, 0.14, 1.1)
	fluke.add_child(blade)


func sample(t: float) -> void:
	if body == null:
		return
	elapsed = t
	var angle := t * swim_speed + phase
	body.position = Vector3(
		cos(angle) * orbit_radius.x,
		sin(t * 0.55) * dive_sway,
		sin(angle) * orbit_radius.y)
	# 模型鼻尖朝 +Z；朝向取轨道切线（网页版用 lookAt 下一个采样点）。
	body.rotation.y = atan2(-sin(angle) * orbit_radius.x, cos(angle) * orbit_radius.y)
	tail.rotation.y = sin(t * 2.1) * 0.28
	fluke.rotation.x = cos(t * 2.1) * 0.35


func _process(delta: float) -> void:
	if is_visible_in_tree():
		elapsed += delta
		sample(elapsed)


# ---------------------------------------------------------------- 构件

func _torso_part(node_name: String, mesh: Mesh, at: Vector3, size: Vector3,
		mat: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = node_name
	part.mesh = mesh
	part.material_override = mat
	part.position = at
	part.scale = size
	body.add_child(part)
	return part


## 普通标准材质：只吃掉场景光照、阴影与后处理，自带的一切额外效果都不开。
##
## 明确不设的东西（每一条都是"看起来更酷但违背普通材质"的选项）：
##   emission_enabled —— 自发光。这正是本次要摘掉的东西。
##   shading_mode = UNSHADED —— 那就完全不接光照了。
##   toon 分档 —— 那会把明暗压成色阶，不是普通材质。
## 保留 roughness 高 / metallic 0，让它在浅水段不会被镜面反射打成亮块。
func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = BODY_ROUGHNESS
	mat.metallic = 0.0
	return mat


func _sphere(radial: int, rings: int) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = radial
	sphere.rings = rings
	return sphere
