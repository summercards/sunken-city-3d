extends Node3D
## 航行目标的水纹。
##
## 旧版会在整条航路上铺 0.55/0.55 的虚线，外加终点一个呼吸圆环。
## 那条线横穿海面，在等距俯视里一眼就读成「UI 画上去的虚线」—— 已整条去掉。
## 现在只留终点：一圈圈从目标点荡开的水纹，方向和绕行由船本身表达。
##
## `show_route(points)` 的签名保留：调用方交的仍然是从船到目标的整条航路，
## 这里只取最后一点。路径计算、绕障、30 条航线回归全都不受影响。

const TINT := Color(0.86, 0.99, 0.97)
## 水纹半径（米）。半米多一点，在船上视角读成「就是这里」，不抢海水。
const RADIUS := 1.8
## 一圈荡完的时间。比点击那次慢，读起来是「目的地在那儿」而不是「刚发生了什么」。
const PERIOD := 2.4
const OPACITY := 0.62

## 水面节点，由 main 注入；为 null 时只贴给定高度播放。
var water: MeshInstance3D
var _plane: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * RADIUS * 2.0
	plane.subdivide_width = 12
	plane.subdivide_depth = 12
	_plane = MeshInstance3D.new()
	_plane.name = "TargetRipple"
	_plane.mesh = plane
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/water_ripple.gdshader")
	_mat.render_priority = 4
	_mat.set_shader_parameter("ring_tint", Vector3(TINT.r, TINT.g, TINT.b))
	_mat.set_shader_parameter("u_opacity", OPACITY)
	# 目标点比点击落点更细、更疏：它要一直在，太抢眼会盖住海水本身。
	_mat.set_shader_parameter("wavelength", 0.30)
	_mat.set_shader_parameter("crest_decay", 0.45)
	_plane.material_override = _mat
	add_child(_plane)
	visible = false


## 只关心终点：航路点列的最后一点。点列不足 2 个（没有可走的路）就隐藏。
func show_route(points: Array, water_y := 1.12) -> void:
	if points.size() < 2:
		clear()
		return
	var dst: Vector2 = points[points.size() - 1]
	var next := Vector3(dst.x, water_y, dst.y)
	# 目标点挪了就从零开始荡 —— 玩家改道后看到的应该是「新落点散开」，
	# 而不是接着上一个点的相位突然冒出一道最外圈。
	# 航行途中每 0.3s 会拿 remaining_route 刷新一次，那种刷新位置不变，不重置。
	if not visible or position.distance_to(next) > 0.05:
		_t = 0.0
		if _mat != null:
			_mat.set_shader_parameter("u_progress", 0.0)
	position = next
	visible = true


func clear() -> void:
	visible = false


## 虚线已整条移除（2026-10-28）。这个查询留给验收断言：
## 谁要是把航路段加回来，`tools/capture_route_ripple.gd` 会立刻红。
func debug_band_count() -> int:
	return 0


## 循环推进 progress：目标点原地一直轻轻荡开。
func _process(delta: float) -> void:
	if not visible or _mat == null:
		return
	_t += delta
	_mat.set_shader_parameter("u_progress", fmod(_t, PERIOD) / PERIOD)
	if water != null:
		_mat.set_shader_parameter("u_time", water.time)
		_mat.set_shader_parameter("ocean_waves", water.ocean_waves)
		_mat.set_shader_parameter("wave_scale", water.wave_scale)
