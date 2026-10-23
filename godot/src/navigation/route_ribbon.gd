extends MeshInstance3D
## 航线预览：在航路上铺一条虚线，外加终点的呼吸圆环。
##
## 网页版没有这个 —— 玩家点了远处目的地只看到船慢慢开过去，不知道它会绕哪边。
## 加了岸线寻路之后航路会拐弯，就更需要「提前看见」：虚线告诉玩家「我会绕开那片楼」，
## 而不是让人以为船在乱走。
##
## 实现用 ImmediateMesh 直接生成竖条带（不做贴图滚动，省掉一套 UV 与时间 uniform）：
## 沿折线每 1.1m 放一小段 0.5m 长的横带，看起来就是虚线。只在航路变化时重建。

const COLOR := Color(0.66, 0.99, 0.90, 0.85)
const DEST_COLOR := Color(1.0, 0.82, 0.46, 0.9)
## 虚线段长 / 间隔 / 带宽。
const DASH := 0.55
const GAP := 0.55
const WIDTH := 0.34
## 水面着色器是 unshaded + depth_draw_never + render_priority 2，会盖住普通不透明物体；
## 所以虚线要抬到水面以上一点，并且让材质排在水的后面画。
const WATER_LIFT := 0.10
const WATER_Y := 1.12

var _mesh: ImmediateMesh
var _mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _route: Array = []
var _t := 0.0


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = COLOR
	# 与水面同层但不被水面覆盖：水面 priority=2，这里必须更大。
	_mat.render_priority = 6
	_mat.no_depth_test = false
	material_override = _mat

	# 终点圆环：一圈细环 + 缓慢呼吸，比一个点更容易在远景里看到。
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.02
	torus.rings = 28
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "DestRing"
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = DEST_COLOR
	_ring_mat.render_priority = 6
	_ring.material_override = _ring_mat
	add_child(_ring)

	visible = false


## 用世界 xz 点列铺一条虚线。点少于 2 个就隐藏。
func show_route(points: Array, water_y := WATER_Y) -> void:
	_route = points
	_mesh.clear_surfaces()
	visible = points.size() >= 2
	if not visible:
		_ring.visible = false
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var period := DASH + GAP
	var carry := 0.0
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var dir := (b - a) / seg
		var normal := Vector2(-dir.y, dir.x)
		# 按「第几段虚线」推进，不用累计浮点位置：
		# 老写法在 seg 末尾会剩 1e-9 米的余量，`at += 1e-9` 永远推不完（真的死循环过一次）。
		var k := 0
		var slot := -carry  # 这一段起点落在周期里的位置
		while true:
			var start_at := maxf(0.0, k * period - slot)
			if start_at >= seg - 0.01:
				break
			var end_at := minf(seg, k * period + DASH - slot)
			if end_at > start_at + 0.01:
				_add_band(a + dir * start_at, a + dir * end_at, normal, water_y)
			k += 1
			if k > 4000:
				break
		carry = fmod(carry + seg, period)
	_mesh.surface_end()

	var dst: Vector2 = points[points.size() - 1]
	_ring.visible = true
	_ring.position = Vector3(dst.x, water_y + WATER_LIFT, dst.y)


func clear() -> void:
	_route.clear()
	_mesh.clear_surfaces()
	visible = false
	_ring.visible = false


## 终点环缓慢缩放，让「这里是要去的地方」有存在感。
func _process(delta: float) -> void:
	if not visible or not _ring.visible:
		return
	_t += delta
	var s := 1.0 + sin(_t * 2.4) * 0.10
	_ring.scale = Vector3(s, 1.0, s)
	_ring_mat.albedo_color.a = 0.55 + sin(_t * 2.4 + 1.2) * 0.30


func _add_band(a: Vector2, b: Vector2, normal: Vector2, y: float) -> void:
	var half := normal * (WIDTH * 0.5)
	var y0 := y + WATER_LIFT
	var p0 := Vector3(a.x - half.x, y0, a.y - half.y)
	var p1 := Vector3(a.x + half.x, y0, a.y + half.y)
	var p2 := Vector3(b.x + half.x, y0, b.y + half.y)
	var p3 := Vector3(b.x - half.x, y0, b.y - half.y)
	_mesh.surface_add_vertex(p0)
	_mesh.surface_add_vertex(p1)
	_mesh.surface_add_vertex(p2)
	_mesh.surface_add_vertex(p0)
	_mesh.surface_add_vertex(p2)
	_mesh.surface_add_vertex(p3)
