@tool
extends Node3D
## 一株植物。
##
## 生长：网页版是按建造等级把整组 `scale` 从 0 放到 1，这里保留同一手法，
##       所以「长出来」的手感和原版一致。
## 摆动：原版 `rotation.z = sin(t*.9+phase)*.025`，本节点照搬，按区块风力加成。
## 特效：`effect` 是区块专用植物的专属名称，由 PlantField 收集后统一成
##       区块级发射器（见 plant_effect.gd），避免每株都挂粒子。

const MeshIO = preload("res://scripts/plants/mesh_io.gd")
const BakeStore = preload("res://scripts/world/bake_store.gd")

@export var plant_id := ""
@export var mesh_path := ""
@export var shared := false
@export var effect := ""
@export var sway_amplitude := 0.025
@export var wind_strength := 1.0
@export var growth := 1.0

var _target_growth := 1.0
var _t := 0.0
var _phase := 0.0
var _mesh_node: MeshInstance3D


func _ready() -> void:
	_phase = float(absi(hash(plant_id)) % 628) / 100.0
	var mesh: ArrayMesh = MeshIO.load_mesh(mesh_path)
	if mesh == null:
		return
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "Mesh"
	_mesh_node.mesh = mesh
	_mesh_node.material_override = BakeStore.material(-1, true, false, false, true)
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_node)
	_apply_growth(growth)


## 立即设定生长进度（0=刚冒芽，1=长成）。
func set_growth(value: float) -> void:
	_target_growth = clampf(value, 0.0, 1.5)
	_apply_growth(_target_growth)


func grow_to(value: float) -> void:
	_target_growth = clampf(value, 0.0, 1.5)


func _apply_growth(value: float) -> void:
	growth = value
	visible = value > 0.02
	var s := maxf(0.02, value)
	scale = Vector3(s, s, s)


func _process(delta: float) -> void:
	# 编辑器里只做静态摆放，不摆也不长，免得场景一打开就到处抖。
	if Engine.is_editor_hint():
		return
	_t += delta
	# 生长的缓动：原版是 smoothstep 在 0.38 的窗口里放出来
	if not is_equal_approx(growth, _target_growth):
		var step := clampf(delta / 0.38, 0.0, 1.0)
		_apply_growth(lerpf(growth, _target_growth, step))
	if _mesh_node == null:
		return
	var amp := sway_amplitude * wind_strength
	rotation.z = sin(_t * 0.9 + _phase) * amp
	rotation.x = cos(_t * 0.7 + _phase) * amp * 0.72
