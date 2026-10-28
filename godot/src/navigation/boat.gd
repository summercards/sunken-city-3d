extends Node3D
class_name Boat
## 小船：模型来自网页版烘焙，运动与起伏在 Godot 内重建。

signal arrived(zone_id: String, landing_id: String)
signal navigation_blocked

## 主场景提供岸线判定；轨迹圆角与每步运动共用它。
var segment_clear := Callable()
var _row_blend := 0.0
var water_surface: MeshInstance3D
var _wave_pitch := 0.0
var _wave_roll := 0.0

const WATER_LEVEL := 1.12
const BASE := "res://assets/baked/"
## boat.json geometries 34..40 are the seven createBoatEdgeStroke tubes from
## index.html, not hull parts. Keep the source bake intact; retire only these overlays.
const LEGACY_FOAM_GEOMETRIES := [34, 35, 36, 37, 38, 39, 40]
## 巡航速度。网页版 `sailDuration = 曲线长度 / 3.6`，这里取同一量级。
const SPEED := 2.6

var model: Node3D
var _mats: Array[ShaderMaterial] = []
var _sailing := false
## 折线航路（世界 xz）：由 SailNav 规划，最后一个点就是泊位本身。
var route: Array = []
var _wp := 0
var _vel := 0.0
## 到达判定：离泊位这么近且速度低于阈值才停稳（否则会「贴上去就瞬移」）。
## 位置误差小于 1.5cm 且低速才完成；保留真实位置，不在最后一帧吸附泊位。
const ARRIVE_DIST := 0.015
const ARRIVE_SPEED := 0.15
const ACCEL := 2.2
const BRAKE := 3.0
## 最大转向角速度（rad/s）。划桨船不是快艇：0.95 约等于「一秒转 55°」，
## 转弯半径 ~3.6m，配合降速才有「船在慢慢摆头」的感觉。
const TURN_RATE := 1.8
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
		if int(b.geom) in LEGACY_FOAM_GEOMETRIES and bool(b.unlit) and bool(b.alpha):
			continue
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
	# A short timber post lifts the lantern clear of the gunwale. The existing
	# wall bracket fixes to its outside face; this fitting shares the boat motion.
	var lamp_post := MeshInstance3D.new()
	lamp_post.name = "NavigationLampPost"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.10,1.20,0.10)
	lamp_post.mesh = post_mesh
	lamp_post.position = Vector3(-0.90,0.95,-1.35)
	lamp_post.material_override = _flat(Color("#715334"))
	model.add_child(lamp_post)
	# Hang the reused lantern outside the port bow. Its wall bracket faces the
	# gunwale, while the glass and real light face open water instead of the chest.
	var lantern := preload("res://scenes/components/solar_cabin/lantern.tscn").instantiate()
	lantern.name = "BowLantern"
	# 复用组件也要有稳定实例 ID：场景装饰检查按 describe().instance_id 判唯一，
	# 留空会直接判失败（`empty instance_id`），而且以后摆放/存档没有稳定键可用。
	lantern.instance_id = "boat/furnishing/bow_lantern"
	lantern.position = Vector3(-1.08,0.95,-1.35)
	lantern.rotation.y = -PI*0.5
	model.add_child(lantern)
	# The opaque baked glass must not shadow the light inside its own housing.
	for visual in lantern.find_children("*","MeshInstance3D",true,false):
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in visual.mesh.get_surface_count():
			var material: ShaderMaterial = visual.get_active_material(surface) as ShaderMaterial
			var emission: Variant = material.get_shader_parameter("emission_value") if material != null else null
			if emission != null and float(emission) > 0.0:
				material=material.duplicate()
				material.set_shader_parameter("emission_value",0.65)
				visual.set_surface_override_material(surface,material)
	var lamp := SpotLight3D.new()
	lamp.name = "BoatLamp"
	lamp.position = Vector3(-1.13,1.17,-1.35)
	lamp.light_color = Color(1.0,0.65,0.28)
	# The hooded beam clears the gunwale instead of overexposing the near plank.
	lamp.basis = Basis.looking_at(Vector3(-0.55,-0.83,-0.08).normalized(),Vector3.UP)
	lamp.light_energy = 8.0
	lamp.spot_range = 9.0
	lamp.spot_attenuation = 1.0
	lamp.spot_angle = 60.0
	lamp.spot_angle_attenuation = 0.7
	lamp.light_specular = 0.35
	lamp.shadow_enabled = true
	lamp.add_to_group("boat_lamps")
	model.add_child(lamp)


func _make_material(tint: bool, _unlit: bool, alpha: bool) -> ShaderMaterial:
	# Baked unlit flags belong to the old web presentation. All boat surfaces,
	# including the net and trim, receive the same real lights as the house.
	var path := "res://shaders/toon.gdshader"
	if alpha:
		path = path.replace(".gdshader", "_alpha.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	mat.set_shader_parameter("use_texture", false)
	mat.set_shader_parameter("depth_tint", tint)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	mat.set_shader_parameter("albedo_tint", Vector3.ONE)
	mat.set_shader_parameter("ambient_boost", 0.0)
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
	_dock_left = 0.0
	_wp = 1
	# 中途改道保留速度与划桨相位，避免每次点击都急停重启。
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
	route = _rounded_route(route)
	_duration = maxf(0.4, _path_length() / cruise_speed())


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

	if water_surface != null:
		var center := Vector2(position.x, position.z)
		var f := _forward(rotation.y)
		var side := Vector2(cos(rotation.y), -sin(rotation.y))
		var bow: Vector3 = water_surface.sample_surface(center + f * 2.0)
		var stern: Vector3 = water_surface.sample_surface(center - f * 2.0)
		var port: Vector3 = water_surface.sample_surface(center - side * 1.0)
		var starboard: Vector3 = water_surface.sample_surface(center + side * 1.0)
		var response := 1.0 - exp(-5.0 * delta)
		position.y = lerpf(position.y, WATER_LEVEL + (bow.x + stern.x + port.x + starboard.x) * 0.25, response)
		_wave_pitch = lerpf(_wave_pitch, atan2(bow.x - stern.x, 4.0), response)
		_wave_roll = lerpf(_wave_roll, atan2(starboard.x - port.x, 2.0), response)
	else:
		position.y = WATER_LEVEL + sin(now * 2.1) * 0.065
	if model == null:
		return
	_animate_oars(delta)
	if not _sailing:
		# 停泊时轻轻摇（浪），航行时收平。
		model.rotation.z = lerp(model.rotation.z, _wave_roll, clamp(delta * 5.0, 0.0, 1.0))
		model.rotation.x = lerp(model.rotation.x, _wave_pitch, clamp(delta * 5.0, 0.0, 1.0))
		model.rotation.y = lerp(model.rotation.y, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		model.position.y = lerp(model.position.y, 0.0, clamp(delta * 4.0, 0.0, 1.0))
	else:
		# 航行：船身向转弯内侧倾、随每桨左右轻摆、桨频带一点点上下起伏。
		var bank := clampf(-_turn_rate * 0.22, -0.09, 0.09)
		model.rotation.z = lerp(model.rotation.z, _wave_roll + bank + sin(_stroke) * 0.012,
			clamp(delta * 6.0, 0.0, 1.0))
		model.rotation.x = lerp(model.rotation.x, _wave_pitch - 0.012 + sin(_stroke * 2.0) * 0.008,
			clamp(delta * 6.0, 0.0, 1.0))
		model.rotation.y = sin(_stroke) * 0.018
		model.position.y = sin(_stroke * 2.0) * 0.012


## 对可安全切角的折线生成相切圆角；岸边保留原折线，靠减速转向通过。
func _rounded_route(points: Array) -> Array:
	if points.size() < 3:
		return points.duplicate()
	var out: Array = [points[0]]
	for i in range(1, points.size() - 1):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var c: Vector2 = points[i + 1]
		var trim := minf(1.8, minf(a.distance_to(b), b.distance_to(c)) * 0.3)
		var entry := b.move_toward(a, trim)
		var leave := b.move_toward(c, trim)
		var curve: Array = [entry]
		for j in range(1, 13):
			var t := float(j) / 12.0
			curve.append(entry.lerp(b, t).lerp(b.lerp(leave, t), t))
		var valid := _clear(out.back(), entry)
		for j in range(1, curve.size()):
			valid = valid and _clear(curve[j - 1], curve[j])
		if valid:
			out.append_array(curve)
		else:
			out.append(b)
	out.append(points.back())
	return out

func _clear(a: Vector2, b: Vector2) -> bool:
	return not segment_clear.is_valid() or bool(segment_clear.call(a, b))

## 弧长推进保持在经过校验的航路上；提前看向前方，速度服从转弯与刹车距离。
func _steer(delta: float) -> void:
	# 帧率波动时也保持同样的转向/制动结果。
	var left := minf(delta, 0.25)
	while left > 0.00001 and _sailing:
		var dt := minf(left, 1.0 / 120.0)
		_advance_route(dt)
		left -= dt

func _ahead(distance: float) -> Vector2:
	var p := Vector2(position.x, position.z)
	for i in range(_wp, route.size()):
		var next: Vector2 = route[i]
		var length := p.distance_to(next)
		if length >= distance:
			return p.move_toward(next, distance)
		distance -= length
		p = next
	return p

func _advance_route(delta: float) -> void:
	if route.size() < 2:
		_sailing = false
		return
	var here := Vector2(position.x, position.z)
	while _wp < route.size() - 1 and here.distance_to(route[_wp]) < 0.001:
		_wp += 1
	var to := _ahead(0.45 + _vel * 0.22) - here
	var desired := rotation.y if to.length() < 0.001 else atan2(-to.x, -to.y)
	var error := angle_difference(rotation.y, desired)
	var turned := clampf(error * (1.0 - exp(-7.0 * delta)), -TURN_RATE * delta, TURN_RATE * delta)
	rotation.y += turned
	_turn_rate = lerpf(_turn_rate, turned / delta, 1.0 - exp(-7.0 * delta))
	var remaining := remaining_distance()
	var alignment := pow(maxf(0.0, cos(error)), 2.0)
	var wanted := cruise_speed() * alignment
	# 尖角提前减速；圆角的方向变化小，可连续通过。
	if _wp < route.size() - 1:
		var incoming: Vector2 = (route[_wp] - here).normalized()
		var outgoing: Vector2 = (route[_wp + 1] - route[_wp]).normalized()
		var turn := absf(incoming.angle_to(outgoing))
		var corner_speed := cruise_speed() * pow(maxf(0.0, cos(turn)), 2.0)
		wanted = minf(wanted, sqrt(corner_speed * corner_speed + 2.0 * BRAKE * here.distance_to(route[_wp])))
	wanted = minf(wanted, minf(sqrt(2.0 * BRAKE * remaining), remaining * 1.8))
	_vel = move_toward(_vel, wanted, (ACCEL if wanted > _vel else BRAKE) * delta)
	var budget := _vel * delta
	while budget > 0.0:
		var next: Vector2 = route[_wp]
		var distance := here.distance_to(next)
		var step := minf(distance, budget)
		var moved := here.move_toward(next, step)
		if not _clear(here, moved):
			_sailing = false
			_vel = 0.0
			_speed_actual = 0.0
			navigation_blocked.emit()
			return
		here = moved
		budget -= step
		if step >= distance and _wp < route.size() - 1:
			_wp += 1
		else:
			break
	position.x = here.x
	position.z = here.y
	_speed_actual = _vel
	if remaining_distance() <= ARRIVE_DIST and _vel <= ARRIVE_SPEED:
		_sailing = false
		_vel = 0.0
		# 保留真实终点附近的位置；不做最后半米瞬移。
		if manual:
			_yaw_to = rotation.y
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


## 约每秒一桨；收桨/起桨连续混合，避免突然显示、隐藏。
func _animate_oars(delta: float) -> void:
	if _oar_l == null or _oar_r == null:
		return
	var effort := clampf(_vel / cruise_speed(), 0.0, 1.0) if _sailing else 0.0
	_row_blend = lerpf(_row_blend, effort, 1.0 - exp(-4.0 * delta))
	_stroke = fmod(_stroke + delta * (0.65 + _row_blend * 0.45) * TAU, TAU)
	_oar_l.visible = true
	_oar_r.visible = true
	var swing := sin(_stroke)
	var dip := cos(_stroke)
	var turn := clampf(_turn_rate / TURN_RATE, -1.0, 1.0)
	_oar_l.rotation.y = lerpf(1.1, swing * 0.30 * (1.0 - turn * 0.3), _row_blend)
	_oar_r.rotation.y = lerpf(-1.1, -swing * 0.30 * (1.0 + turn * 0.3), _row_blend)
	_oar_l.rotation.z = lerpf(-0.3, 0.10 + dip * 0.16, _row_blend)
	_oar_r.rotation.z = lerpf(0.3, -0.10 - dip * 0.16, _row_blend)


func wake_uniform() -> Vector4:
	return Vector4(position.x, position.z, rotation.y, _speed_actual)

func rowing_state() -> Vector2:
	return Vector2(_stroke, _row_blend)


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


func cruise_speed() -> float:
	return SPEED * (float(speed_multiplier.call()) if speed_multiplier.is_valid() else 1.0)


var speed_multiplier: Callable
