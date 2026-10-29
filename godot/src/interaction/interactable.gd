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

## 热区锚点从哪来 —— 决定「交互判定、悬浮图标、聚焦环」三者共同的中心：
##   geometry —— 跟随子节点的视觉包围盒（默认）。视觉挪到哪，热区就跟到哪；
##               摆场景时只管挪模型，不用再回来对齐一个看不见的锚点。
##   node     —— 固定在自己原点。只有「没有视觉几何、或需要精确锚点」时才用。
##
## 之所以要有这个开关：以前锚点硬编码为节点原点，而视觉是带偏移的子节点。
## 为了把箱子摆到码头上，有人给 Visual 写了 -1.4 / +1.5 的偏移，热区却留在原地，
## 于是「箱子看得见、却要走回原位才能交互」——偏差实测 2.07 米（半径才 2.4）。
@export_enum("geometry", "node") var focus_anchor := "geometry"
## 在锚点上再叠的偏移。只影响判定与图标，不动物件本体。
@export var focus_offset := Vector3.ZERO
## 半径是否随视觉尺寸放大：大物件站到边上就够不着，靠这个兜住。
## 小物件不受影响（半径取 max，不会比 focus_radius 更小）。
@export var auto_radius := true
## 编辑器里选中本节点时，画出热区范围，方便边摆边看。
@export var show_heat_preview := true

var focused := false

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring_base_scale := Vector3.ONE
var _t := 0.0
## 几何锚点缓存：视觉没动就不重复算包围盒。
var _anchor_cache := Vector3.ZERO
var _anchor_stamp := Transform3D()
var _anchor_valid := false
var _heat: MeshInstance3D
var _heat_mat: StandardMaterial3D



func _ready() -> void:
	add_to_group("interactable")
	_build_focus_ring()
	_on_ready()
	_sync_ring_to_anchor()


func _process(delta: float) -> void:
	# 编辑器里只摆静态造型：不呼吸、不自转，也不跑玩法 tick。
	# 但锚点要跟着视觉走 —— 摆场景时挪动模型，热区预览必须同步。
	if Engine.is_editor_hint():
		_update_heat_preview()
		_sync_ring_to_anchor()
		return
	_t += delta
	if _ring != null:
		# 呼吸 + 缓慢自转：远处的焦点也能被一眼看到。
		# 缩放在「按热区半径算出的基准尺寸」上叠加，不能直接覆盖 ——
		# 否则环会退回固定大小，和热区对不上。
		var s := 1.0 + sin(_t * 3.2) * 0.06
		_ring.scale = Vector3(_ring_base_scale.x * s, 1.0, _ring_base_scale.z * s)
		_ring.rotation.y += delta * 0.9
		if focused:
			_sync_ring_to_anchor()
	_on_tick(delta)


## 热区锚点（世界坐标）—— 交互判定、悬浮图标、聚焦环共用的唯一真相源。
##
## 三个消费者必须都走这里，否则「看得见 / 点得到 / 走得到」会各说各话：
##   Interactor._refresh_target()  选目标时的距离
##   HoverCard                     悬浮卡片贴在哪
##   focus ring / heat preview     视觉反馈画在哪
func focus_position() -> Vector3:
	if focus_anchor == "node":
		return global_position + focus_offset
	return _geometry_anchor() + focus_offset


## 实际生效的热区半径。auto_radius 只会放大，不会缩小 focus_radius。
func effective_focus_radius() -> float:
	if not auto_radius:
		return focus_radius
	return maxf(focus_radius, _geometry_half_extent())


## 几何锚点：视觉包围盒的 XZ 中心 + 本节点自身的高度。
## Y 取节点原点是有意的 —— 环要贴在地面上，不能悬到箱子半腰。
func _geometry_anchor() -> Vector3:
	var vis := visual_root()
	if vis == null:
		return global_position
	var stamp := vis.global_transform
	if _anchor_valid and _anchor_stamp.is_equal_approx(stamp):
		return _anchor_cache
	var box := visual_aabb()
	if box.size.length() < 0.001:
		# 没有几何（纯逻辑交互点，如睡眠点）：退回自身原点。
		_anchor_cache = global_position
	else:
		var c := box.get_center()
		_anchor_cache = Vector3(c.x, global_position.y, c.z)
	_anchor_stamp = stamp
	_anchor_valid = true
	return _anchor_cache


## 视觉包围盒的 XZ 半尺寸，用于让大物件的热区跟着变大。
func _geometry_half_extent() -> float:
	var box := visual_aabb()
	if box.size.length() < 0.001:
		return 0.0
	return maxf(box.size.x, box.size.z) * 0.5


## 视觉根：优先叫 Visual 的子节点，否则取第一个非辅助子节点。
## 聚焦环、热区预览、阻挡体都不算视觉。
func visual_root() -> Node3D:
	var named := get_node_or_null("Visual")
	if named is Node3D:
		return named
	for c in get_children():
		if not (c is Node3D):
			continue
		if c == _ring or c == _heat:
			continue
		var n := String(c.name)
		if n == "FocusRing" or n == "HeatPreview" or n == "Blockers":
			continue
		return c
	return null


## 视觉包围盒（世界空间）。只读 mesh 自带的 aabb，不遍历顶点。
func visual_aabb() -> AABB:
	var root := visual_root()
	if root == null:
		return AABB()
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var b: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		elif n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			var b2: AABB = (n as Node3D).global_transform * (n as MultiMeshInstance3D).get_aabb()
			box = b2 if first else box.merge(b2)
			first = false
		stack.append_array(n.get_children())
	return box


## 把聚焦环挪到锚点。环是子节点，所以用局部坐标表达。
func _sync_ring_to_anchor() -> void:
	if _ring == null:
		return
	var local := focus_position() - global_position
	_ring.position = Vector3(local.x, 0.09, local.z)
	# 环要「围住」物件，不能埋在物件里 —— 大箱子的半宽比环本身还大，固定尺寸会被完全遮住。
	# 按半宽 + 余量定尺寸；小物件（采集点等）仍保持原来的观感。
	# 真正的判定范围由编辑器里的 heat preview 显示，两者不必一致。
	var half := _geometry_half_extent()
	var s := clampf((half + 0.35) / 0.56, 1.0, 3.0)
	_ring_base_scale = Vector3(s, 1.0, s)
	_ring.scale = _ring_base_scale


## 编辑器里选中本节点时显示热区圆盘：摆场景时能直接看见判定范围。
func _update_heat_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var want := show_heat_preview and _is_selected_in_editor()
	if want and _heat == null:
		_build_heat_preview()
	if _heat != null:
		_heat.visible = want
		if want:
			var local := focus_position() - global_position
			_heat.position = Vector3(local.x, 0.04, local.z)
			var r := effective_focus_radius()
			_heat.scale = Vector3(r, 1.0, r)
			_heat_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.16)


func _is_selected_in_editor() -> bool:
	if not Engine.is_editor_hint():
		return false
	var sel := EditorInterface.get_selection()
	if sel == null:
		return false
	for n in sel.get_selected_nodes():
		if n == self:
			return true
	return false


func _build_heat_preview() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_heat = MeshInstance3D.new()
	_heat.name = "HeatPreview"
	_heat.mesh = plane
	_heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_heat_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_heat_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.16)
	_heat.material_override = _heat_mat
	_heat.visible = false
	add_child(_heat)



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
