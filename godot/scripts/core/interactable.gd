@tool
extends Node3D
class_name Interactable
## 世界里的可交互物。
##
## 设计原则（与旧的「屏幕投影图标」路线相反）：
##   1. 物件本身在 3D 世界里，有体积、有朝向、有高度，不再是一张永远朝向相机的贴纸；
##   2. 能不能交互由玩家与它的空间关系决定（距离/朝向），不是屏幕像素距离；
##   3. 交互需要投入时间（hold_time），期间走动会中断；
##   4. UI 只反映「当前焦点」，不再把所有可点目标同时铺在屏幕上。
##
## 子类只负责：造型、can_interact()、interact()。

signal focus_changed(focused: bool)

@export var id: String = ""
@export var label: String = ""
@export var verb: String = "查看"
## 同距离下优先级高的先被选中（例如码头上的贝床优先于背景装饰）。
@export var priority: int = 0
## 进入焦点的最大距离（米）。实际取它与 Interactor.radius 的较小值。
@export var focus_radius: float = 2.4
## 需要持续按住的时间；0 表示瞬发。
@export var hold_time: float = 0.0
@export var accent: Color = Color("#8fe8d6")

var focused := false

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interactable")
	_build_focus_ring()
	_on_ready()


func _process(delta: float) -> void:
	# 编辑器里只摆静态造型：不呼吸、不自转，也不跑玩法 tick。
	if Engine.is_editor_hint():
		return
	_t += delta
	if _ring != null:
		# 呼吸 + 缓慢自转：远处的焦点也能被一眼看到。
		var s := 1.0 + sin(_t * 3.2) * 0.06
		_ring.scale = Vector3(s, 1.0, s)
		_ring.rotation.y += delta * 0.9
	_on_tick(delta)


## 子类钩子。
func _on_ready() -> void:
	pass


func _on_tick(_delta: float) -> void:
	pass


## 焦点文案，HUD 直接显示。
func focus_text() -> String:
	return "%s · %s" % [verb, label]


func can_interact() -> bool:
	return true


## 返回空字典表示什么都没有发生；返回 {"blocked": "原因"} 表示被规则挡住；
## 其余字典视为产出（由 Interactor 抛给上层）。
func interact(_actor: Node3D) -> Dictionary:
	return {}


func focus_enter() -> void:
	if focused:
		return
	focused = true
	if _ring != null:
		_ring.visible = true
	focus_changed.emit(true)


func focus_exit() -> void:
	if not focused:
		return
	focused = false
	if _ring != null:
		_ring.visible = false
	focus_changed.emit(false)


func _build_focus_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.44
	torus.outer_radius = 0.56
	torus.rings = 20
	torus.ring_segments = 8
	_ring = MeshInstance3D.new()
	_ring.name = "FocusRing"
	_ring.mesh = torus
	_ring.position = Vector3(0, 0.06, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.75)
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)
