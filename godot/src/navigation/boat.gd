extends CharacterBody3D
class_name Boat
## 小船：独立 Blender 组件装配；运动、靠泊和起伏由 Boat 保持原契约。

signal navigation_blocked

var berth_query := Callable()
var _manual_hull: RefCounted
var _visual_heave := 0.0

func configure_formal_hull() -> void:
	var hull := get_node_or_null("HullCollision") as CollisionShape3D
	if hull == null: return
	_manual_hull = preload("res://src/navigation/formal_hull_motion.gd").new()
	_manual_hull.configure(self, hull)

func hull_clear() -> bool:
	return hull_clear_at(global_transform)

func hull_clear_at(pose: Transform3D) -> bool:
	return _manual_hull != null and not _manual_hull.overlaps_shore(pose)

func is_still() -> bool:
	return _manual_hull != null and _manual_hull.is_still()

func shore_contact() -> Object:
	return _manual_hull.shore_contact() if _manual_hull != null else null

func _physics_process(delta: float) -> void:
	if _manual_hull == null or not manual_drive: return
	var berth: Vector3 = berth_query.call(global_position) if berth_query.is_valid() else Vector3.INF
	var before: Object = _manual_hull.shore_contact()
	_manual_hull.advance(Vector3(drive_dir.x, 0.0, drive_dir.y), minf(delta, 0.05), berth, cruise_speed(), _power_requested)
	_vel = _manual_hull._speed
	_turn_rate = _manual_hull._turn_rate
	_speed_actual = velocity.length()
	_travel_dir = Vector2(velocity.x, velocity.z).normalized()
	if _manual_hull.shore_contact() != null and before == null:
		navigation_blocked.emit()
	if drive_dir == Vector2.ZERO and is_still():
		manual_drive = false

var _row_blend := 0.0
var _power_blend := 0.0
var _power_requested := false
var water_surface: MeshInstance3D
var _wave_pitch := 0.0
var _wave_roll := 0.0

const WATER_LEVEL := 1.12
const VISUAL_SCENE = preload("res://scenes/props/reference_skiff.tscn")
const RowingRig = preload("res://src/player/animation/rowing_rig.gd")
## 巡航速度。网页版 `sailDuration = 曲线长度 / 3.6`，这里取同一量级。
const SPEED := 2.6

var model: Node3D
const ACCEL := 2.2
const BRAKE := 3.0
const TURN_RATE := 1.8
const TURN_ACCEL := 4.6
const TURN_AT_REST := 0.55
const BRAKE_TAIL := 0.35

var _vel := 0.0
var _stroke := 0.0
var _turn_rate := 0.0
var _travel_dir := Vector2.ZERO
var _oar_l: Node3D
var _oar_r: Node3D
var _blade_l: Node
var _blade_r: Node
var manual_drive := false
var drive_dir := Vector2.ZERO
var _speed_actual := 0.0

func build() -> void:
	if is_instance_valid(model): return
	model = VISUAL_SCENE.instantiate()
	model.name = "Model"
	add_child(model)
	_oar_l = model.get_node("OarL")
	_oar_r = model.get_node("OarR")
	_animate_oars(0.0)
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


func place_at(pos: Vector3, yaw: float) -> void:
	position = Vector3(pos.x, WATER_LEVEL, pos.z)
	rotation.y = yaw
	stop_drive()

func _forward(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))

func set_drive(dir: Vector2, power := false) -> void:
	drive_dir = dir.limit_length()
	_power_requested = power and not drive_dir.is_zero_approx()
	if _manual_hull != null and drive_dir.length_squared() > 0.000001:
		manual_drive = true

func release_drive() -> void:
	drive_dir = Vector2.ZERO
	_power_requested = false

func driving() -> bool:
	return manual_drive

func starts_sailing() -> bool:
	return manual_drive

func stop_drive() -> void:
	if _manual_hull != null: _manual_hull.reset()
	manual_drive = false
	release_drive()
	_vel = 0.0
	_speed_actual = 0.0
	_turn_rate = 0.0
	_travel_dir = _forward(rotation.y)

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if water_surface != null:
		var center := Vector2(position.x, position.z)
		var f := _forward(rotation.y)
		var side := Vector2(cos(rotation.y), -sin(rotation.y))
		var bow: Vector3 = water_surface.sample_surface(center + f * 2.0)
		var stern: Vector3 = water_surface.sample_surface(center - f * 2.0)
		var port: Vector3 = water_surface.sample_surface(center - side * 1.0)
		var starboard: Vector3 = water_surface.sample_surface(center + side * 1.0)
		var response := 1.0 - exp(-5.0 * delta)
		_visual_heave = lerpf(_visual_heave, (bow.x + stern.x + port.x + starboard.x) * 0.25, response)
		_wave_pitch = lerpf(_wave_pitch, atan2(bow.x - stern.x, 4.0), response)
		_wave_roll = lerpf(_wave_roll, atan2(starboard.x - port.x, 2.0), response)
	else:
		_visual_heave = sin(now * 2.1) * 0.065
	if model == null:
		return
	_animate_oars(delta)
	if not manual_drive:
		# 停泊时轻轻摇（浪），航行时收平。
		model.rotation.z = lerp(model.rotation.z, _wave_roll, clamp(delta * 5.0, 0.0, 1.0))
		model.rotation.x = lerp(model.rotation.x, _wave_pitch, clamp(delta * 5.0, 0.0, 1.0))
		model.rotation.y = lerp(model.rotation.y, 0.0, clamp(delta * 4.0, 0.0, 1.0))
		model.position.y = lerp(model.position.y, _visual_heave, clamp(delta * 4.0, 0.0, 1.0))
	else:
		# 航行：船身向转弯内侧倾、随每桨左右轻摆、桨频带一点点上下起伏。
		var bank := clampf(-_turn_rate * 0.22, -0.09, 0.09)
		model.rotation.z = lerp(model.rotation.z, _wave_roll + bank + sin(_stroke) * 0.012,
			clamp(delta * 6.0, 0.0, 1.0))
		model.rotation.x = lerp(model.rotation.x, _wave_pitch - 0.012 + sin(_stroke * 2.0) * 0.008,
			clamp(delta * 6.0, 0.0, 1.0))
		model.rotation.y = sin(_stroke) * 0.018
		model.position.y = (_visual_heave) + sin(_stroke * 2.0) * 0.012


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


## 约每秒一桨；收桨/起桨连续混合，避免突然显示、隐藏。
func _animate_oars(delta: float) -> void:
	if _oar_l == null or _oar_r == null:
		return
	var effort := clampf(_vel / cruise_speed(), 0.0, 1.0) if manual_drive else 0.0
	var turn := clampf(_turn_rate / TURN_RATE, -1.0, 1.0)
	var power_target := effort if _power_requested and _manual_hull != null and _manual_hull.power_rowing else 0.0
	_power_blend = lerpf(_power_blend, power_target, 1.0 - exp(-6.0 * delta))
	var state := RowingRig.sample_oars(_oar_l, _oar_r, Vector2(_stroke, _row_blend), effort, turn, delta, _power_blend)
	_stroke = state.x
	_row_blend = state.y


func wake_uniform() -> Vector4:
	return Vector4(position.x, position.z, rotation.y, _speed_actual)

func travel_direction() -> Vector2:
	return _travel_dir if manual_drive and _travel_dir.length_squared() > 0.000001 else _forward(rotation.y)

func rowing_state() -> Vector2:
	return Vector2(_stroke, _row_blend)


## Read-only visual attachment contract; presentation never writes the vessel.
func boarding_position() -> Vector3:
	return model.transform * model.get_node("RowingSeat").position

func rowing_pose() -> Dictionary:
	var pose := RowingRig.contacts(model.get_node("RowingSeat"), _oar_l, _oar_r)
	pose["power"] = _power_blend
	return pose


## Read-only visual contacts. Rendering owns the resulting water effects.
func hull_visual() -> Node3D:
	return model.get_node_or_null("Parts/hull_000") if model!=null else null


## 点船体命中测试（供「点船 = 上船」用）。
##
## 点击命中随可见船模起伏，泊位交接另查物理船壳。
func pick_hull(screen: Vector2, camera: Camera3D) -> bool:
	if model == null or camera == null:
		return false
	var box := hull_local_aabb()
	if box.size.length() < 0.001:
		return false
	var inv := model.global_transform.affine_inverse()
	var origin := inv * camera.project_ray_origin(screen)
	var dir := inv.basis * camera.project_ray_normal(screen)
	return _ray_hits_aabb(origin, dir, box)


## 船体在 model 本地空间的包围盒。优先只用船壳，避免把伸出去的桨也算进来。
func hull_local_aabb() -> AABB:
	if model == null:
		return AABB()
	var root := hull_visual()
	if root == null:
		root = model
	var inv := model.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var xf: Transform3D = inv * (n as Node3D).global_transform
			var b: AABB = xf * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	return box


## 射线 vs AABB（slab 法）。方向不必归一化，只判是否相交。
static func _ray_hits_aabb(origin: Vector3, dir: Vector3, box: AABB) -> bool:
	var tmin := -INF
	var tmax := INF
	for axis in 3:
		var o: float = origin[axis]
		var d: float = dir[axis]
		var lo: float = box.position[axis]
		var hi: float = box.position[axis] + box.size[axis]
		if absf(d) < 1e-8:
			# 平行于这对平面：起点在板外就没戏。
			if o < lo or o > hi:
				return false
			continue
		var t1: float = (lo - o) / d
		var t2: float = (hi - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	return tmax >= 0.0

## 桨叶入水点来自组件自带的 BladeContact 挂点，随桨的划水与收桨姿态移动；
## 不再用固定距离推算落点。返回固定两侧，缺挂点的一侧给非有限值，调用方跳过。
func oar_blade_positions() -> PackedVector3Array:
	if _blade_l==null and _oar_l!=null:_blade_l=_oar_l.find_child("BladeContact",true,false)
	if _blade_r==null and _oar_r!=null:_blade_r=_oar_r.find_child("BladeContact",true,false)
	var positions := PackedVector3Array([Vector3.INF,Vector3.INF])
	if _blade_l!=null:positions[0]=(_blade_l as Node3D).global_position
	if _blade_r!=null:positions[1]=(_blade_r as Node3D).global_position
	return positions


func cruise_speed() -> float:
	return SPEED * (float(speed_multiplier.call()) if speed_multiplier.is_valid() else 1.0)


var speed_multiplier: Callable
