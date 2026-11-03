@tool
extends "res://src/world/zone_scene.gd"
## 顶层牧场：视觉升级状态 + 楼顶与消防梯的行走/物理支撑。
## 不拥有经济、生产或存档规则，只把「能不能站、能不能走上去」做成真实数据。
##
## 水面位置按用户红线标定：图中红框是保留段消防梯最下面的一层平台，
## 该平台甲板 44.80 就在水面（44.54）上方 0.26 米 —— 和码头/浮店的登船高差一致。
## 船靠这一层平台上人，沿六段折返梯走 15.2 米上到 60 米的楼顶农场；
## 平台下方的断梯残段沉在水里，只作视觉残骸，不承诺可走。

@export_enum("unbuilt", "complete") var greenhouse_upgrade_state := "unbuilt":
	set(value):
		greenhouse_upgrade_state = value
		_apply_upgrade_state()

@export_enum("unbuilt", "complete") var water_tower_upgrade_state := "unbuilt":
	set(value):
		water_tower_upgrade_state = value
		_apply_upgrade_state()

## —— 楼体本地标高（米，+Y 向上）——
const WATER_LOCAL_Y := 44.54      ## 水面；世界高度 1.12
const BOARD_DECK_Y := 44.80       ## 上岸口：保留段最下面那层平台甲板
const ROOF_Y := 60.00             ## 楼顶草皮面
const BRIDGE_Y := 59.90           ## 顶层平台到楼顶的入口板

## 六段折返梯：lane A/B 两条梯道交替，每段升 2.5 米，合 15 米。
## low/high 两端都落在相邻平台的甲板边上，接缝共边，不留悬空。
const STAIR_RUNS := [
	{"x0": 24.16, "x1": 25.84, "low_z": -3.00, "high_z": 1.20, "low_y": 44.80, "high_y": 47.30},
	{"x0": 26.16, "x1": 27.84, "low_z": 1.20, "high_z": -3.00, "low_y": 47.30, "high_y": 49.80},
	{"x0": 24.16, "x1": 25.84, "low_z": -3.00, "high_z": 1.20, "low_y": 49.80, "high_y": 52.30},
	{"x0": 26.16, "x1": 27.84, "low_z": 1.20, "high_z": -3.00, "low_y": 52.30, "high_y": 54.80},
	{"x0": 24.16, "x1": 25.84, "low_z": -3.00, "high_z": 1.20, "low_y": 54.80, "high_y": 57.30},
	{"x0": 26.16, "x1": 27.84, "low_z": 1.20, "high_z": -3.00, "low_y": 57.30, "high_y": 59.80},
]

## 七层平台，甲板标高与真实组件量出来的一致（44.8 / 47.3 / … / 59.8）。
const LANDING_DECKS := [
	{"x0": 23.90, "x1": 28.10, "z0": -4.80, "z1": -3.00, "y": 44.80},
	{"x0": 23.90, "x1": 28.10, "z0": 1.20, "z1": 3.00, "y": 47.30},
	{"x0": 23.90, "x1": 28.10, "z0": -4.80, "z1": -3.00, "y": 49.80},
	{"x0": 23.90, "x1": 28.10, "z0": 1.20, "z1": 3.00, "y": 52.30},
	{"x0": 23.90, "x1": 28.10, "z0": -4.80, "z1": -3.00, "y": 54.80},
	{"x0": 23.90, "x1": 28.10, "z0": 1.20, "z1": 3.00, "y": 57.30},
	{"x0": 24.80, "x1": 28.10, "z0": -4.80, "z1": -3.00, "y": 59.80},
]

## 楼顶可走范围（女儿墙内沿再收 0.15 米，留出身影余量）。
const ROOF_MIN_X := -23.50
const ROOF_MAX_X := 23.50
const ROOF_MIN_Z := -15.50
const ROOF_MAX_Z := 15.50

## 楼顶上占地的实体：这些地方不是地面，要挖掉，同时给角色一层物理阻挡。
## rect = [x0, z0, x1, z1]（本地 XZ），top = 顶部标高。
const ROOF_CUTS := [
	{"id": "UpperTerrace", "rect": [-21.30, 3.20, -10.70, 12.80], "top": 65.85},
	{"id": "Shed", "rect": [-9.50, 7.20, -4.60, 10.80], "top": 63.61},
	{"id": "Coop", "rect": [-18.90, -0.65, -15.10, 2.40], "top": 62.32},
	{"id": "Greenhouse", "rect": [3.20, -12.20, 10.80, -2.80], "top": 63.84},
	{"id": "WaterTower", "rect": [15.50, -13.20, 20.90, -6.80], "top": 66.10},
]

func _ready() -> void:
	_author_walk_surfaces()
	_author_roof_obstacles()
	super._ready()
	_apply_upgrade_state()

func set_greenhouse_upgrade_state(state: String, instant := false) -> void:
	if state != "unbuilt" and state != "complete":
		return
	greenhouse_upgrade_state = state
	_apply_upgrade_state()

func set_water_tower_upgrade_state(state: String, instant := false) -> void:
	if state != "unbuilt" and state != "complete":
		return
	water_tower_upgrade_state = state
	_apply_upgrade_state()

func set_upgrade_state(state: String, instant := false) -> void:
	## 兼容旧入口；新代码应按温室/水塔分别切换。
	if state != "unbuilt" and state != "complete":
		return
	greenhouse_upgrade_state = state
	water_tower_upgrade_state = state
	_apply_upgrade_state()

## 水面/甲板的本地标高，供调试与验收查询。
func water_local_y() -> float:
	return WATER_LOCAL_Y

func board_deck_local_y() -> float:
	return BOARD_DECK_Y

## 行走面：七层平台 + 六段斜坡 + 入口板 + 挖过洞的楼顶。
## 全部用本地坐标三角形，跟着根节点走；父节点移动不需要重算。
func _author_walk_surfaces() -> void:
	var area := get_node_or_null("WalkAreas/Walk_rooftop_ranch_access")
	if area == null:
		return
	var faces := PackedVector3Array()
	for deck: Dictionary in LANDING_DECKS:
		_add_rect(faces, deck.x0, deck.z0, deck.x1, deck.z1, deck.y)
	for run: Dictionary in STAIR_RUNS:
		_add_ramp(faces, run.x0, run.x1, run.low_z, run.high_z, run.low_y, run.high_y)
	# 顶层开放平台到楼顶的入口板（真件 roof_entry 跨在屋檐上），做成连续斜板：
	# 高端必须正好压在屋檐边（x=23.5）且高度等于楼顶 60.0 —— 差 0.06 米就会被
	# GroundSpace 的边界墙判定成台阶并封死，表现就是「走到梯顶迈不进楼顶」。
	_add_ramp_x(faces, -5.10, -2.70, 24.80, ROOF_MAX_X, 59.80, ROOF_Y)
	for piece: Array in _roof_pieces():
		_add_rect(faces, piece[0], piece[1], piece[2], piece[3], ROOF_Y)
	faces = _upward(faces)
	area.surface_triangles = faces
	area.physical_surface_triangles = faces
	area.surface_y = global_position.y + ROOF_Y
	area.span_min = global_position.y + WATER_LOCAL_Y
	area.span_max = global_position.y + ROOF_Y + 0.30

## 楼顶矩形减去被实体占掉的部分，切成若干可走矩形。
func _roof_pieces() -> Array:
	var pieces: Array = [[ROOF_MIN_X, ROOF_MIN_Z, ROOF_MAX_X, ROOF_MAX_Z]]
	for cut: Dictionary in ROOF_CUTS:
		var rect: Array = cut.rect
		var next: Array = []
		for piece: Array in pieces:
			next.append_array(_subtract(piece, rect))
		pieces = next
	return pieces

## 矩形相减：把 a 中与 b 相交的部分切成上下左右四块。
func _subtract(a: Array, b: Array) -> Array:
	var ax0: float = a[0]
	var az0: float = a[1]
	var ax1: float = a[2]
	var az1: float = a[3]
	var bx0: float = b[0]
	var bz0: float = b[1]
	var bx1: float = b[2]
	var bz1: float = b[3]
	if bx1 <= ax0 or bx0 >= ax1 or bz1 <= az0 or bz0 >= az1:
		return [a]
	var out: Array = []
	if bz0 > az0:
		out.append([ax0, az0, ax1, minf(bz0, az1)])
	if bz1 < az1:
		out.append([ax0, maxf(bz1, az0), ax1, az1])
	var mid_z0 := maxf(bz0, az0)
	var mid_z1 := minf(bz1, az1)
	if bx0 > ax0:
		out.append([ax0, mid_z0, minf(bx0, ax1), mid_z1])
	if bx1 < ax1:
		out.append([maxf(bx1, ax0), mid_z0, ax1, mid_z1])
	return out

## 角色物理阻挡：楼顶实体不需要把整栋楼做成碰撞，只挡住真正走不进去的件。
## 行走面已经挖掉了这些区域，这两层是同一份数据的两种表达。
func _author_roof_obstacles() -> void:
	if Engine.is_editor_hint():
		return
	var existing := get_node_or_null("ActorObstacles")
	if existing != null:
		remove_child(existing)
		existing.free()
	var obstacles := Node3D.new()
	obstacles.name = "ActorObstacles"
	add_child(obstacles)
	for cut: Dictionary in ROOF_CUTS:
		var rect: Array = cut.rect
		var cx := (float(rect[0]) + float(rect[2])) * 0.5
		var cz := (float(rect[1]) + float(rect[3])) * 0.5
		var sx := absf(float(rect[2]) - float(rect[0]))
		var sz := absf(float(rect[3]) - float(rect[1]))
		var top: float = cut.top
		var height := maxf(top - ROOF_Y, 1.2)
		_add_obstacle(obstacles, str(cut.id),
			Vector3(cx, ROOF_Y + height * 0.5, cz), Vector3(sx, height, sz))

func _add_obstacle(parent: Node3D, id: String, local_position: Vector3, size: Vector3) -> void:
	var body := preload("res://src/navigation/actor_collision_body.gd").new()
	body.name = id
	body.position = local_position
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

func _add_rect(out: PackedVector3Array, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	if absf(x1 - x0) < 0.01 or absf(z1 - z0) < 0.01:
		return
	var a := Vector3(x0, y, z0)
	var b := Vector3(x0, y, z1)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x1, y, z0)
	# 逆时针朝上（法线 +Y），GroundSpace 与射线都按这个绕序判定。
	_add_tri(out, a, c, b)
	_add_tri(out, a, d, c)

## 斜坡：两端分别落在两块平台的甲板边上，整段连续，不靠台阶缝走路。
func _add_ramp(out: PackedVector3Array, x0: float, x1: float, low_z: float, high_z: float,
		low_y: float, high_y: float) -> void:
	var a := Vector3(x0, low_y, low_z)
	var b := Vector3(x1, low_y, low_z)
	var c := Vector3(x1, high_y, high_z)
	var d := Vector3(x0, high_y, high_z)
	_add_tri(out, a, c, b)
	_add_tri(out, a, d, c)

## 沿 X 方向的斜板（入口板从平台 59.8 抬到楼顶 60.0）。
func _add_ramp_x(out: PackedVector3Array, z0: float, z1: float, low_x: float, high_x: float,
		low_y: float, high_y: float) -> void:
	var a := Vector3(low_x, low_y, z0)
	var b := Vector3(low_x, low_y, z1)
	var c := Vector3(high_x, high_y, z1)
	var d := Vector3(high_x, high_y, z0)
	_add_tri(out, a, b, c)
	_add_tri(out, a, c, d)

func _add_tri(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	out.append(a)
	out.append(b)
	out.append(c)

## 统一成法线朝上的绕序：射线命中、导航烘焙和物理地板都按同一套绕序判定。
func _upward(source: PackedVector3Array) -> PackedVector3Array:
	var faces := source.duplicate()
	for i in range(0, faces.size() - 2, 3):
		if (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).y < 0.0:
			var swap := faces[i + 1]
			faces[i + 1] = faces[i + 2]
			faces[i + 2] = swap
	return faces

func _apply_upgrade_state() -> void:
	var root := get_node_or_null("Models")
	if root == null:
		return
	for child in root.get_children():
		var asset_id := str(child.get_meta("asset_id", ""))
		if asset_id == "SEA-SCENE-ORF2-GREENHOUSE_UNBUILT":
			child.visible = greenhouse_upgrade_state == "unbuilt"
		elif asset_id == "SEA-SCENE-ORF2-GREENHOUSE_COMPLETE":
			child.visible = greenhouse_upgrade_state == "complete"
		elif asset_id == "SEA-SCENE-ORF2-WATER_TOWER_UNBUILT":
			child.visible = water_tower_upgrade_state == "unbuilt"
		elif asset_id == "SEA-SCENE-ORF2-WATER_TOWER_COMPLETE":
			child.visible = water_tower_upgrade_state == "complete"
