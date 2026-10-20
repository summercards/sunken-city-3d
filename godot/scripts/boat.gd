extends Node3D
class_name Boat
## 小船：模型来自网页版烘焙，运动与起伏在 Godot 内重建。

signal arrived(zone_id: String, landing_id: String)

const WATER_LEVEL := 1.12
const BASE := "res://assets/baked/"
## 巡航速度。网页版 `sailDuration = 曲线长度 / 3.6`，这里取同一量级。
const SPEED := 3.4

var model: Node3D
var _mats: Array[ShaderMaterial] = []
var _sailing := false
## 折线航路（世界 xz）：由 SailNav 规划，最后一个点就是泊位本身。
var route: Array = []
var _wp := 0
var _vel := 0.0
## 到达判定：离泊位这么近且速度低于阈值才停稳（否则会「贴上去就瞬移」）。
## 到达判定的距离与速度必须**同时**满足；速度阈值要给得比「最后一段的目标速度」宽，
## 否则船会以 0.35m/s 在泊位旁无限打转（比例控制永远收不到 0）。
const ARRIVE_DIST := 0.45
const ARRIVE_SPEED := 0.70
const ACCEL := 2.2
const BRAKE := 3.0
## 最大转向角速度（rad/s）。划桨船不是快艇：0.95 约等于「一秒转 55°」，
## 转弯半径 ~3.6m，配合降速才有「船在慢慢摆头」的感觉。
const TURN_RATE := 0.95
var _yaw_from := 0.0
var _yaw_to := 0.0
## 靠妥后还剩多少弧度要转正（按 TURN_RATE 慢慢拧）。
var _dock_left := 0.0
## 划桨相位（0..TAU 循环）与转向速率（给侧倾用）。
var _stroke := 0.0
var _turn_rate := 0.0
## 两根桨。
var _oar_l: Node3D
var _oar_r: Node3D
## 手动航行的目标（点水面划过去）：没有区块、没有泊位朝向。
var manual := false
var _t := 0.0
var _duration := 1.0
var _to_zone := ""
var _to_landing := ""
var _speed_actual := 0.0


func build() -> void:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(BASE + "boat.json"))
	if meta == null:
		push_error("boat.json 解析失败")
		return
	var verts := _read_f32("boat_geoms.bin")
	var idx := _read_i32("boat_geoms_idx.bin")
	var inst := _read_f32("boat_instances.bin")

	model = Node3D.new()
	model.name = "Model"
	add_child(model)

	var meshes: Array[Mesh] = []
	for g in meta.geoms:
		meshes.append(_make_mesh(g, verts, idx))

	for b in meta.batches:
		var count := int(b.count)
		if count <= 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[int(b.geom)]
		mm.instance_count = count
		var off := int(b.instOff) * 16
		mm.buffer = inst.slice(off, off + count * 16)
		var mat := _make_material(bool(b.tint), bool(b.unlit), bool(b.alpha))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		model.add_child(mmi)
	_build_oars()


func _make_material(tint: bool, unlit: bool, alpha: bool) -> ShaderMaterial:
	var path := "res://shaders/unlit.gdshader"
	if not unlit:
		path = "res://shaders/toon.gdshader"
	if alpha:
		path = path.replace(".gdshader", "_alpha.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	mat.set_shader_parameter("use_texture", false)
	mat.set_shader_parameter("depth_tint", tint)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	_mats.append(mat)
	return mat


func place_at(pos: Vector3, yaw: float) -> void:
	position = Vector3(pos.x, WATER_LEVEL, pos.z)
	rotation.y = yaw
	route.clear()
	route.append(Vector2(pos.x, pos.z))
	_wp = 0
	_vel = 0.0
	_yaw_from = yaw
	_yaw_to = yaw
	_sailing = false


## 出航。`path` 是 SailNav 规划好的折线（世界 xz，首点≈当前位置、末点=泊位）；
## 不传就退化成直线（没有岸线数据的老场景/测试也能用）。
func sail_to(pos: Vector3, yaw: float, zone_id: String, landing_id: String, path: Array = []) -> void:
	if landing_id != "manual":
		manual = false
	_yaw_from = rotation.y
	_yaw_to = yaw
	_to_zone = zone_id
	_to_landing = landing_id
	_sailing = true
	_wp = 0
	_vel = 0.0
	route.clear()
	var goal := Vector2(pos.x, pos.z)
	if path.size() >= 2:
		for p in path:
			route.append(p as Vector2)
		# 规划的终点可能是「最近可通行格」，补上真正的泊位，最后一小段直着靠岸。
		if route[route.size() - 1].distance_to(goal) > 0.05:
			route.append(goal)
	else:
		route.append(Vector2(position.x, position.z))
		route.append(goal)
	_duration = maxf(0.4, _path_length() / SPEED)


func _path_length() -> float:
	var sum := 0.0
	for i in range(1, route.size()):
		sum += (route[i] as Vector2).distance_to(route[i - 1])
	return sum


## 剩余航程（给 HUD/航线预览用）。
func remaining_distance() -> float:
	if not _sailing or route.is_empty():
		return 0.0
	var here := Vector2(position.x, position.z)
	var sum := here.distance_to(route[mini(_wp, route.size() - 1)])
	for i in range(_wp + 1, route.size()):
		sum += (route[i] as Vector2).distance_to(route[i - 1])
	return sum


## 船头朝向的前向（模型跟网页版一致：船头朝 -Z）。
func _forward(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## 手动航行：点水面划到某个点。没有区块/泊位朝向，到站只发 arrived("", "manual")。
func sail_to_point(pos: Vector3, path: Array = []) -> void:
	manual = true
	sail_to(pos, rotation.y, "", "manual", path)


func starts_sailing() -> bool:
	return _sailing


## 已划过的航路（给航线预览裁掉已经走过的部分）。
func remaining_route() -> Array:
	if not _sailing or route.is_empty():
		return []
	var out: Array = [Vector2(position.x, position.z)]
	for i in range(mini(_wp, route.size() - 1), route.size()):
		out.append(route[i])
	return out


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _sailing:
		_steer(delta)
	else:
		_speed_actual = lerp(_speed_actual, 0.0, clamp(delta * 6.0, 0.0, 1.0))
		if _dock_left > 0.0:
			var want := _yaw_to
			var err2 := angle_difference(rotation.y, want)
			var step2 := minf(absf(err2), TURN_RATE * delta)
			rotation.y += signf(err2) * step2
			_dock_left = maxf(0.0, absf(angle_difference(rotation.y, want)))

	position.y = WATER_LEVEL + sin(now * 2.1) * 0.065
	if model == null:
		return
	_animate_oars(delta)
	if not _sailing:
		# 停泊时轻轻摇（浪），航行时收平。
		model.rotation.z = lerp(model.rotation.z, sin(now * 1.7) * 0.04, clamp(delta * 5.0, 0.0, 1.0))
		model.rotation.x = lerp(model.rotation.x, cos(now * 1.35) * 0.03, clamp(delta * 5.0, 0.0, 1.0))
		model.rotation.y = lerp(model.rotation.y, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		model.position.y = lerp(model.position.y, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	else:
		# 航行：船身向转弯内侧倾、随每桨左右轻摆、桨频带一点点上下起伏。
		var bank := clampf(-_turn_rate * 0.22, -0.09, 0.09)
		model.rotation.z = lerp(model.rotation.z, bank + sin(_stroke) * 0.012,
			clamp(delta * 6.0, 0.0, 1.0))
		model.rotation.x = lerp(model.rotation.x, -0.012 + sin(_stroke * 2.0) * 0.008,
			clamp(delta * 6.0, 0.0, 1.0))
		model.rotation.y = sin(_stroke) * 0.018
		model.position.y = sin(_stroke * 2.0) * 0.012


## 每帧的航行积分：先算「该去哪儿、该多快」，再限幅转向、限幅加速。
##
## 旧版是起点到终点的 smoothstep 插值：位置永远在直线上，速度不受转向影响，
## 所以「贴着岛绕过去」根本不可能，靠岸也是硬停。这里改成真运动学：
##   · 逐段追航点，到段尾自动切下一个；
##   · 速度有加减速，转弯时降速，接近泊位按刹车距离提前收油；
##   · 朝向按最大角速度趋近目标航向，转不过来就绕大圈（这才是船）。
func _steer(delta: float) -> void:
	while _wp < route.size() - 1:
		var seg_to: Vector2 = route[_wp]
		if Vector2(position.x, position.z).distance_to(seg_to) < 0.75:
			_wp += 1
		else:
			break
	var target: Vector2 = route[mini(_wp, route.size() - 1)]
	var here := Vector2(position.x, position.z)
	var to := target - here
	var dist := to.length()

	# 目标航向：船头朝 -Z，所以 yaw 与 (dx, dz) 的换算带两个负号。
	var want_yaw := rotation.y
	if dist > 0.05:
		want_yaw = atan2(-to.x, -to.y)


	# 转向：限角速度。转得越多航速越低（船不是坦克）。
	var err := angle_difference(rotation.y, want_yaw)
	var max_step := TURN_RATE * delta
	var turned := clampf(err, -max_step, max_step)
	rotation.y += turned
	_turn_rate = lerp(_turn_rate, turned / maxf(delta, 0.0001), 0.25)
	var align := 1.0 - clampf(absf(err) / PI, 0.0, 1.0)

	# 速度：巡航 × 对齐度，最后一段按刹车距离收油。
	var want_speed := SPEED * (0.35 + 0.65 * align)
	var final_left := dist
	if _wp >= route.size() - 1:
		# 最后一段用比例控制（速度 ∝ 剩余距离）：比「刹车距离公式」更稳，
		# 不会因为一帧推过头就绕着泊位打转。
		want_speed = minf(want_speed, dist * 1.0)
	if _vel < want_speed:
		_vel = minf(want_speed, _vel + ACCEL * delta)
	else:
		_vel = maxf(want_speed, _vel - BRAKE * 1.4 * delta)

	# 沿船头方向前进：转向不足时自然会向外飘，不会横向平移。
	# 每划一桨推一下（±9%），比匀速平移「有划船感」。
	var surge := 1.0 + sin(_stroke) * 0.09
	var step := _forward(rotation.y) * _vel * surge * delta
	position.x += step.x
	position.z += step.y
	_speed_actual = _vel

	if _wp >= route.size() - 1 and dist <= ARRIVE_DIST and _vel <= ARRIVE_SPEED:
		_sailing = false
		_vel = 0.0
		_speed_actual = 0.0
		position = Vector3(target.x, WATER_LEVEL, target.y)
		# 到站后先在原地把船身摆正（按同样的角速度上限慢慢拧，不硬 snap），
		# `arrived` 立刻发出去：玩法不等这几百毫秒，视觉上像是在靠妥。
		_dock_left = absf(angle_difference(rotation.y, _yaw_to))
		arrived.emit(_to_zone, _to_landing)


## 两根桨：俯视镜头下这是「在划船」最直观的信号。
## 桨挂在船体两侧，绕 Y 前后划、绕 Z 入水出水；划船时随桨频摆动，停泊时收起来。
func _build_oars() -> void:
	_oar_l = _make_oar(-1.0)
	_oar_r = _make_oar(1.0)


func _make_oar(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "OarL" if side < 0.0 else "OarR"
	# 桨架就设在舷边（船宽 3m → 舷边 ±1.5，留一点内收），桨杆**只向外伸**：
	# 这样杆不会从船体中间穿过去，俯视下也不会被船身挡掉一半。
	pivot.position = Vector3(1.05 * side, 0.34, 0.10)
	add_child(pivot)
	var shaft := BoxMesh.new()
	shaft.size = Vector3(2.35, 0.08, 0.10)
	var mi := MeshInstance3D.new()
	mi.mesh = shaft
	mi.position = Vector3(1.18 * side, 0.0, 0.0)
	mi.material_override = _flat(Color("#8a5f30"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(mi)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.72, 0.035, 0.42)
	var bmi := MeshInstance3D.new()
	bmi.mesh = blade
	bmi.position = Vector3(2.30 * side, -0.03, 0.0)
	bmi.material_override = _flat(Color("#f0d7a8"))
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(bmi)
	return pivot


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


## 桨频跟速度走：停=收桨，慢=2.0 次/秒，满速=3.0 次/秒。
func _animate_oars(delta: float) -> void:
	if _oar_l == null or _oar_r == null:
		return
	var rate := 0.0
	if _sailing and _vel > 0.2:
		rate = 2.0 + 1.0 * clampf(_vel / SPEED, 0.0, 1.0)
	_stroke = fmod(_stroke + delta * rate * TAU, TAU)
	if rate <= 0.0:
		# 没在划：桨收回船内（直接藏起来）。停泊时两根桨横在船外很怪。
		_oar_l.visible = false
		_oar_r.visible = false
		return
	_oar_l.visible = true
	_oar_r.visible = true
	var swing := sin(_stroke)
	var dip := cos(_stroke)
	# 桨**基本垂直于船身**，只在 ±24° 内前后摆 —— 摆幅再大，俯视下桨就压到船头上了。
	_oar_l.rotation.y = 0.0 + swing * 0.30
	_oar_r.rotation.y = 0.0 - swing * 0.30
	_oar_l.rotation.z = 0.10 + dip * 0.16
	_oar_r.rotation.z = -0.10 - dip * 0.16


func wake_uniform() -> Vector4:
	return Vector4(position.x, position.z, rotation.y, _speed_actual)


func _read_f32(file_name: String) -> PackedFloat32Array:
	var f := FileAccess.open(BASE + file_name, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes.to_float32_array()


func _read_i32(file_name: String) -> PackedInt32Array:
	var f := FileAccess.open(BASE + file_name, FileAccess.READ)
	if f == null:
		return PackedInt32Array()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes.to_int32_array()


func _slice_vec3(src: PackedFloat32Array, off: int, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	for i in count:
		var k := off + i * 3
		out[i] = Vector3(src[k], src[k + 1], src[k + 2])
	return out


func _slice_vec2(src: PackedFloat32Array, off: int, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var k := off + i * 2
		out[i] = Vector2(src[k], src[k + 1])
	return out


func _make_mesh(g: Dictionary, verts: PackedFloat32Array, indices: PackedInt32Array) -> ArrayMesh:
	var vc := int(g.vcount)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _slice_vec3(verts, int(g.pOff), vc)
	if int(g.nOff) >= 0:
		arrays[Mesh.ARRAY_NORMAL] = _slice_vec3(verts, int(g.nOff), vc)
	if int(g.tOff) >= 0:
		arrays[Mesh.ARRAY_TEX_UV] = _slice_vec2(verts, int(g.tOff), vc)
	if int(g.icount) > 0:
		arrays[Mesh.ARRAY_INDEX] = indices.slice(int(g.iOff), int(g.iOff) + int(g.icount))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
