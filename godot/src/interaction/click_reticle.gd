extends Node3D
## 点击落点环。
##
## 网页版点地面时没有反馈，玩家只能靠自己判断「点中了没有」。
## 这里在落点放一圈贴地的光环：快速扩开再淡出，同时留一个更小的实心点，
## 让「我要走到这儿」这件事一眼可见。航行目标也复用同一圈，只是颜色换成琥珀。

const RING_COLOR := Color(0.62, 0.98, 0.90, 0.95)
const SAIL_COLOR := Color(1.0, 0.80, 0.42, 0.95)

var _ring: MeshInstance3D
var _dot: MeshInstance3D
var _mat: StandardMaterial3D
var _dot_mat: StandardMaterial3D
var _tween: Tween


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.40
	torus.outer_radius = 0.50
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = RING_COLOR
	_ring.material_override = _mat
	add_child(_ring)

	var disc := CylinderMesh.new()
	disc.top_radius = 0.07
	disc.bottom_radius = 0.07
	disc.height = 0.004
	disc.radial_segments = 12
	_dot = MeshInstance3D.new()
	_dot.name = "Dot"
	_dot.mesh = disc
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dot_mat.albedo_color = RING_COLOR
	_dot.material_override = _dot_mat
	add_child(_dot)

	visible = false


## 在落点放一圈。`sailing` 为真时用琥珀色（航行目标），否则用青色（走路）。
func show_at(point: Vector3, sailing := false) -> void:
	position = Vector3(point.x, point.y + 0.02, point.z)
	var col := SAIL_COLOR if sailing else RING_COLOR
	_mat.albedo_color = col
	_dot_mat.albedo_color = col
	visible = true
	_ring.scale = Vector3.ONE * 0.55
	_dot.scale = Vector3.ONE
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_ring, "scale", Vector3.ONE * 1.15, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_mat, "albedo_color:a", 0.0, 0.62)
	_tween.tween_property(_dot_mat, "albedo_color:a", 0.35, 0.62)
	_tween.chain().tween_callback(func() -> void: visible = false)
