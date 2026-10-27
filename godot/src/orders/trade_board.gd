@tool
extends "res://src/interaction/interactable.gd"
const Order_modelDependency = preload("res://src/orders/orders.gd")
var order_model: Order_modelDependency
## 世界里的码头订单板：一块立起来的木牌，钉着三张还没被领走的单子。
##
## 只负责「长得像回事 + 按 E 打开面板」；规则在 `src/orders/orders.gd`，
## 数值在 `assets/data/orders.json`，位置由 `tools/place_trade_board.py` 求解。
##
## 位置说明：上岸码头那一小块甲板被菜箱 / 施工牌 / 采集点占满了（0.35m 网格采样
## 找不到四角都不压墙的空地），所以板子立在更宽的**打捞浮台**上——
## 打捞一趟、上岸交单，动线反而更顺。

signal opened(board: Node3D)

const WOOD := Color("#a9773f")
const WOOD_DARK := Color("#7b5228")
const PAPER := Color("#f3ead2")
const INK := Color("#5d4a36")
const ACCENT := Color("#ffd479")

var zone_id := "zone1"
var _papers: Array = []
var _lamp: OmniLight3D
var _pendulum := 0.0


func setup(data: Dictionary) -> void:
	id = str(data.get("id", "dock_orders"))
	zone_id = str(data.get("zone", "zone1"))
	label = str(data.get("name", "码头订单板"))
	verb = "交易"
	priority = 5
	focus_radius = 2.6
	hold_time = 0.0
	accent = ACCENT
	position = Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	rotation.y = float(data.get("yaw", 0.0))
	name = "TradeBoard"


func _on_ready() -> void:
	_build_frame()
	_build_papers()
	_build_lamp()


func focus_text() -> String:
	var board = order_model
	if board == null:
		return "%s · %s" % [verb, label]
	var live := 0
	for s in board.offers():
		if s is Dictionary and not s.is_empty() and not s.has("refill"):
			live += 1
	if live == 0:
		return "%s · %s（正在收单）" % [verb, label]
	return "%s · %s（%d 张待交）" % [verb, label, live]


func interact(_actor: Node3D) -> Dictionary:
	opened.emit(self)
	return {}


func _on_tick(delta: float) -> void:
	if _lamp != null:
		# 灯在风里轻晃：静止的暖光会让整块板子看着像贴纸。
		_pendulum += delta * 1.4
		_lamp.light_energy = 0.55 + sin(_pendulum) * 0.08
	if not _papers.is_empty():
		for i in _papers.size():
			var p: Node3D = _papers[i]
			p.rotation.z = sin(_pendulum * 0.7 + float(i) * 1.9) * 0.02


# ---------------------------------------------------------------- 造型

func _build_frame() -> void:
	# 两根立柱
	for sx in [-0.52, 0.52]:
		_box(Vector3(0.10, 1.44, 0.10), Vector3(sx, 0.72, 0.0), WOOD_DARK)
	# 板面：略向后仰一点，俯视镜头里能同时看到板和钉在上面的纸
	var face := _box(Vector3(1.20, 0.76, 0.07), Vector3(0.0, 1.20, 0.0), WOOD)
	face.rotation.x = deg_to_rad(-6.0)
	# 顶棚
	var roof := _box(Vector3(1.38, 0.06, 0.34), Vector3(0.0, 1.66, 0.04), WOOD_DARK)
	roof.rotation.x = deg_to_rad(-9.0)
	# 板下的小柜台：既然是「交货」，总得有个放东西的地方
	_box(Vector3(1.24, 0.10, 0.28), Vector3(0.0, 0.86, 0.16), WOOD_DARK)


func _build_papers() -> void:
	# 三张纸对应板上三个格子（数量固定，位置由规则层的 slots 数量决定）
	var spots := [Vector3(-0.34, 1.30, 0.045), Vector3(0.02, 1.22, 0.045), Vector3(0.36, 1.31, 0.045)]
	for i in spots.size():
		var paper := _box(Vector3(0.30, 0.22, 0.012), spots[i], PAPER)
		paper.rotation.x = deg_to_rad(-6.0)
		paper.rotation.z = deg_to_rad([-2.5, 1.5, 3.2][i])
		paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 纸上两行「字」：细深色条，远看就是密密麻麻的手写单
		for row in 2:
			_box(Vector3(0.20 - float(row) * 0.05, 0.014, 0.004),
				spots[i] + Vector3(-0.02, 0.04 - float(row) * 0.055, 0.008), INK)
		_papers.append(paper)
	# 图钉
	for i in 3:
		_box(Vector3(0.026, 0.026, 0.02), spots[i] + Vector3(0.0, 0.10, 0.010), ACCENT)


func _build_lamp() -> void:
	_box(Vector3(0.04, 0.04, 0.26), Vector3(0.0, 1.60, 0.22), WOOD_DARK)
	var glass := CylinderMesh.new()
	glass.top_radius = 0.055
	glass.bottom_radius = 0.075
	glass.height = 0.16
	glass.radial_segments = 10
	var bulb := MeshInstance3D.new()
	bulb.name = "Lamp"
	bulb.mesh = glass
	bulb.position = Vector3(0.0, 1.50, 0.34)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.58)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.92
	bulb.material_override = mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)
	_lamp = OmniLight3D.new()
	_lamp.name = "LampLight"
	_lamp.position = Vector3(0.0, 1.44, 0.30)
	_lamp.light_color = Color(1.0, 0.86, 0.62)
	_lamp.light_energy = 0.55
	_lamp.omni_range = 3.4
	_lamp.shadow_enabled = false
	add_child(_lamp)


func _box(scl: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = scl
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.metallic = 0.0
	mi.material_override = mat
	add_child(mi)
	return mi
