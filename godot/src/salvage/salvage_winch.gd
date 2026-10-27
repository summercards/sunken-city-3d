@tool
extends "res://src/interaction/interactable.gd"
const RewardsDependency = preload("res://src/salvage/salvage_rewards.gd")
var rewards: RewardsDependency
## 世界里的绞盘打捞台。
##
## 旧版打捞是「点到上岸桩就进账 + 40 秒冷却」，世界里除了一个图标什么都没有。
## 现在它是一台真实的绞盘：木架、卷筒、摇柄、垂到水里的钩子。
## 走近按 E 打开打捞小游戏（见 `src/salvage/salvage.gd`），玩完才结算产出。
##
## 节点放在 zone1 的打捞浮台上（坐标由 `assets/data/build_sites.json` 之外单独给，
## 因为打捞台是固定设施而不是可升级建筑）。

signal opened(winch: Node3D)

const SalvageModelLib = preload("res://src/salvage/salvage.gd")

## 木头与金属的分色：与场景里其他道具保持同一套低饱和配色。
const WOOD := Color("#a9773f")
const WOOD_DARK := Color("#7b5228")
const IRON := Color("#5d6b74")
const ROPE := Color("#cbb287")
const ACCENT := Color("#ffd479")

## 冷却由 Economy 管，这里只负责问它。秒数给 UI 与焦点文案。
var zone_id := "zone1"
var _crane: Node3D
var _drum: Node3D
var _handle: Node3D
var _rope_pivot: Node3D
var _rope: MeshInstance3D
var _hook: Node3D
var _lamp_mat: StandardMaterial3D
var _spin := 0.0
var _idle := 0.0


func setup(data: Dictionary) -> void:
	id = str(data.get("id", "salvage_winch"))
	zone_id = str(data.get("zone", "zone1"))
	label = str(data.get("name", "绞盘打捞台"))
	verb = "打捞"
	priority = 4
	focus_radius = 2.6
	hold_time = 0.0
	accent = ACCENT
	position = Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	rotation.y = float(data.get("yaw", 0.0))
	name = "SalvageWinch"


func _on_ready() -> void:
	_build_crane()
	_build_drum()
	_build_rope()
	_build_lamp()


func can_interact() -> bool:
	return true


func blocked_reason() -> String:
	if rewards == null or not rewards.can_salvage(_now()):
		return "绞盘冷却中 · %.0f 秒" % rewards.salvage_cooldown_left(_now())
	return ""


func focus_text() -> String:
	var left := rewards.salvage_cooldown_left(_now())
	if left > 0.0:
		return "%s · 冷却 %.0f 秒" % [verb, left]
	return "%s · %s（按 E 下钩）" % [verb, label]


func interact(_actor: Node3D) -> Dictionary:
	var reason := blocked_reason()
	if reason != "":
		return {"blocked": reason}
	opened.emit(self)
	return {}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 收线成功时摇柄转几圈，给一个「真的在摇」的反馈。
func play_reel(turns := 2.0) -> void:
	if _handle == null:
		return
	var tw := create_tween()
	tw.tween_property(self, "_spin", _spin + TAU * turns, 0.9).set_trans(Tween.TRANS_CUBIC)
	tw.finished.connect(_apply_spin)


func play_snap() -> void:
	if _rope == null or _hook == null:
		return
	# 断线：绳子瞬间松掉、钩子缩回去，比单纯弹个 Toast 更容易看懂。
	_hook.visible = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rope, "scale:y", ROPE_LEN * 0.45, 0.12).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_rope, "position:y", -0.5 * ROPE_LEN * 0.45, 0.12)
	tw.chain().tween_callback(func() -> void:
		_hook.visible = true
		_rope.scale = Vector3(1.0, ROPE_LEN, 1.0)
		_rope.position = Vector3(0.0, -0.5 * ROPE_LEN, 0.0))


func _apply_spin() -> void:
	if _drum != null:
		_drum.rotation.x = _spin


## ---- 造型 -------------------------------------------------------------------
##
## 本地坐标 y=0 就是甲板面（节点 position 已经落在 walk 的 surface_y 上）。
## 所以立柱从 0 长到 1.30，卷筒吊在 0.95，悬臂在 1.18 伸出去，
## 绳子从悬臂末端一直垂到水下 —— 任何一项写成负值都会被甲板吞掉。

## 甲板上方的立柱高度。
const POST_H := 1.30
## 悬臂伸出去的长度（绳子的水平位置）。
const BOOM := 0.95
## 绳子垂下去的长度（从悬臂末端算，1.9m 够到水面以下）。
const ROPE_LEN := 1.95


func _build_crane() -> void:
	_crane = Node3D.new()
	_crane.name = "Frame"
	add_child(_crane)
	# 两根立柱
	_box(_crane, Vector3(0.42, POST_H * 0.5, 0.0), Vector3(0.12, POST_H, 0.12), WOOD_DARK)
	_box(_crane, Vector3(-0.42, POST_H * 0.5, 0.0), Vector3(0.12, POST_H, 0.12), WOOD_DARK)
	# 顶部横梁
	_box(_crane, Vector3(0.0, POST_H - 0.05, 0.0), Vector3(1.02, 0.10, 0.14), WOOD)
	# 悬臂：从横梁中点往水面方向伸出
	_box(_crane, Vector3(0.0, POST_H - 0.12, -BOOM * 0.5), Vector3(0.13, 0.10, BOOM + 0.10), WOOD)
	# 斜撑：从一根立柱中段撑到悬臂中段，免得看起来像根悬空的筷子
	var brace := _box(_crane, Vector3(0.0, POST_H - 0.34, -BOOM * 0.34),
		Vector3(0.07, 0.07, BOOM * 0.62), WOOD_DARK)
	brace.rotation.x = -0.42
	# 底座横木，压住两根立柱
	_box(_crane, Vector3(0.0, 0.06, 0.0), Vector3(1.06, 0.12, 0.34), WOOD_DARK)


func _build_drum() -> void:
	_drum = Node3D.new()
	_drum.name = "Drum"
	_drum.position = Vector3(0.0, 0.95, 0.0)
	add_child(_drum)
	# 卷筒轴沿 X：CylinderMesh 的轴是 Y，绕 Z 转 90° 放倒。
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 0.72
	cyl.radial_segments = 14
	var mi := MeshInstance3D.new()
	mi.name = "Barrel"
	mi.mesh = cyl
	mi.rotation.z = PI * 0.5
	mi.material_override = _mat(IRON)
	_drum.add_child(mi)
	# 摇柄：从卷筒一端伸出去，末端一根竖把手（随卷筒绕 X 转）
	_box(_drum, Vector3(0.48, 0.0, 0.0), Vector3(0.30, 0.05, 0.05), IRON)
	_box(_drum, Vector3(0.64, 0.12, 0.0), Vector3(0.06, 0.26, 0.06), WOOD)


func _build_rope() -> void:
	_rope_pivot = Node3D.new()
	_rope_pivot.name = "RopePivot"
	_rope_pivot.position = Vector3(0.0, POST_H - 0.12, -BOOM)
	add_child(_rope_pivot)

	var rope := CylinderMesh.new()
	rope.top_radius = 0.018
	rope.bottom_radius = 0.018
	rope.height = 1.0
	rope.radial_segments = 6
	_rope = MeshInstance3D.new()
	_rope.name = "Rope"
	_rope.mesh = rope
	_rope.material_override = _mat(ROPE)
	# 顶端钉在枢轴上：height 1 的圆柱中心在下移半长处，scale.y 就是绳长。
	_rope.position = Vector3(0.0, -0.5 * ROPE_LEN, 0.0)
	_rope.scale = Vector3(1.0, ROPE_LEN, 1.0)
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope_pivot.add_child(_rope)

	# 钩子挂在绳子的**末端**，但不做绳子的子节点 —— 否则会被绳长缩放拉变形。
	_hook = Node3D.new()
	_hook.name = "Hook"
	_hook.position = Vector3(0.0, -ROPE_LEN + 0.02, 0.0)
	_rope_pivot.add_child(_hook)
	var shank := _box(_hook, Vector3(0.0, -0.16, 0.0), Vector3(0.04, 0.34, 0.04), IRON)
	shank.rotation.x = 0.16
	var barb := _box(_hook, Vector3(0.0, -0.36, 0.07), Vector3(0.12, 0.04, 0.22), IRON)
	barb.rotation.x = -0.55


func _build_lamp() -> void:
	# 悬臂末端吊一盏小灯：打捞台在浮台尽头，夜里没有它容易找不到。
	var bulb := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.075
	s.height = 0.15
	s.radial_segments = 10
	s.rings = 6
	bulb.mesh = s
	bulb.name = "Lamp"
	# 挂在近侧立柱顶端：吊在悬臂末端会和绳子/钩子叠在一起，远处看像一团白点。
	bulb.position = Vector3(0.42, POST_H + 0.10, 0.0)
	_lamp_mat = _mat(ACCENT)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = ACCENT
	_lamp_mat.emission_energy_multiplier = 0.9
	bulb.material_override = _lamp_mat
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)


func _on_tick(delta: float) -> void:
	_idle += delta
	# 空闲时钩子轻轻晃，暗示「它在水里」。
	if _rope != null and _drum != null:
		_rope.rotation.z = sin(_idle * 0.9) * 0.05
		_rope.rotation.x = cos(_idle * 0.7) * 0.035
	if _lamp_mat != null:
		var ready := rewards != null and rewards.can_salvage(_now())
		_lamp_mat.emission_energy_multiplier = 0.9 if ready else 0.22


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _mat(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mat.metallic = 0.0 if not emissive else 0.0
	return mat
