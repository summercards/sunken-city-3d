extends Node3D
## 海底世界（独立地图）。
##
## 与海面世界的关系：不是把相机压到水面下，而是切到一张独立的地图。
## 进入时隐藏海面上的所有物体、换掉 Environment 与相机；上浮时原样恢复。
##
## 地图本身按内容拆成四个区块场景（见 scenes/underwater/region_*.tscn）：
##   basin / neighborhood / reef / trench
## 本脚本只负责：状态机、游动与碰撞、相机、宝箱交互、区块标题。
##
## 数值对齐网页版 diving.js：
##   游速 3.8、相机距离 5~11（默认 10）、俯角 pitch 1.21；
##   下潜 2.2 秒缓入 -10m；搜索半径 3.4m、搜索 3 秒；
##   高度限制 [-223.5, -4.8]，水平 x∈[-50,50]、z∈[-170.5,48]。

signal depth_changed(depth: float)
signal zone_changed(name: String)
signal exited

const RenderFlagsLib = preload("res://src/rendering/render_flags.gd")
signal message(text: String)
## 氧气 / 头灯 / 已发现宝箱数。HUD 据此画左下的仪表。
signal air_changed(ratio: float, lamp_on: bool, found: int, total: int)

const WATER_LEVEL := 1.12
const SWIM_SPEED := 3.8
const SPRINT_SPEED := 6.2
const ENTER_TIME := 2.2
const ENTER_DEPTH := -10.0
const CAM_MIN := 5.0
const CAM_MAX := 11.0
const SEARCH_RADIUS := 3.4
const SEARCH_TIME := 3.0
const MOVE_MIN_Y := -223.5
const MOVE_MAX_Y := -4.8

## 宝箱的「发现」规则。**这是 F8 重做的核心**：
## 旧版五个宝箱一进水就在屏幕上列成清单、点一下就自动游过去，探索没有意义。
## 现在必须自己看见 —— 要么游到跟前，要么把头灯扫过去。
const DISCOVER_NEAR := 11.0
## 头灯照到能发现的距离。
const DISCOVER_LAMP := 26.0
## 头灯锥形：视线方向与指向宝箱方向的点积下限（约 55°）。
const DISCOVER_DOT := 0.55

const SWIM_DATA := "res://assets/baked/underwater/swim.json"
const MaterialLib = preload("res://src/diving/uw_materials.gd")
const CharacterScript = preload("res://src/player/character.gd")
const DiveAirLib = preload("res://src/diving/dive_air.gd")

@onready var regions_root: Node3D = $Regions
@onready var deco: Node3D = $Deco
@onready var camera: Camera3D = $DiveCamera
@onready var chests_root: Node3D = $Chests

var active := false
var phase := "surface"          # surface / enter / swim / exit
var diver_pos := Vector3.ZERO
var depth := 0.0

var _yaw := 0.0
var _pitch := 1.21
var _distance := 10.0
var _velocity := Vector3.ZERO
var _t := 0.0
var _enter_t := 0.0
var _exit_y := 0.0

var _surface_nodes: Array = []
var _world_env: WorldEnvironment
var _saved_env: Environment
var _uw_env: Environment
var _sky_material: ShaderMaterial
var _fog_material: ShaderMaterial
var _surface_zone := ""

var _solids: Array = []
var _terraces: Array = []
var _trench := []
var _chests: Array = []
var _chest_markers: Array = []
var _search: Dictionary = {}
var _search_t := 0.0
var _route: Array = []
var _drag := false
var _marker_layer: CanvasLayer
var _diver: Node3D
var _heading := 0.0
## 氧气与头灯（纯状态机，见 src/diving/dive_air.gd）。
var air = DiveAirLib.new()
## 每帧推给 HUD 的节流（不必每帧改 Label）。
var _air_emit_t := 0.0


func setup(surface_nodes: Array, world_env: WorldEnvironment) -> void:
	_surface_nodes = surface_nodes
	_world_env = world_env
	_saved_env = world_env.environment
	_build_environment()
	_build_fog_pass()
	_load_swim_data()
	_build_diver()
	_build_chests()
	# 海底世界常驻在场景里，但平时整棵树必须不可见 —— 否则它自带的
	# 平行光 / 点光会一起照亮海面，白天瞬间过曝。
	visible = false
	_build_markers()
	deco.setup(_fish_specs)


# ---------------------------------------------------------------- 进入 / 离开
func dive(_boat_pos: Vector3, zone_label := "") -> void:
	if active:
		return
	# 氧气耗尽被强制上浮后，得先在水面喘几秒 —— 失败有代价，但不扣资源。
	if not air.can_dive():
		message.emit("刚上浮，先喘口气（%.0f 秒）" % ceil(air.recover))
		return
	air.refill()
	_surface_zone = zone_label
	active = true
	phase = "enter"
	_enter_t = 0.0
	diver_pos = Vector3(0, WATER_LEVEL, 12)
	_yaw = 0.0
	_pitch = 1.21
	_distance = 10.0
	_velocity = Vector3.ZERO
	_route.clear()
	_search = {}
	_refresh_chest_visibility()

	visible = true
	_set_surface_visible(false)
	_world_env.environment = _uw_env
	camera.fov = 55.0
	camera.near = 0.12
	camera.current = true
	deco.visible = true
	chests_root.visible = true
	if _marker_layer != null:
		_marker_layer.visible = true
	_update_camera(0.0, true)
	_update_lamp()
	depth_changed.emit(0.0)
	_emit_air()


func surface() -> void:
	if not active or phase == "exit":
		return
	phase = "exit"
	_enter_t = 0.0
	_exit_y = diver_pos.y
	_route.clear()
	_search = {}
	if _marker_layer != null:
		_marker_layer.visible = false


func _finish_exit() -> void:
	active = false
	phase = "surface"
	# 灯必须关掉：海面材质与水下材质不是一套，但 uniform 会留在同一个
	# ShaderMaterial 缓存里，下次进水前如果没重设就会「灯没开却亮着」。
	MaterialLib.set_lamp(false, Vector3.ZERO, Vector3(0, 0, -1))
	visible = false
	_set_surface_visible(true)
	_world_env.environment = _saved_env
	camera.current = false
	deco.visible = false
	chests_root.visible = false
	depth = 0.0
	exited.emit()


func _set_surface_visible(on: bool) -> void:
	for n in _surface_nodes:
		if is_instance_valid(n):
			n.visible = on


# ---------------------------------------------------------------- 环境
func _build_environment() -> void:
	_uw_env = Environment.new()
	_uw_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/uw_sky.gdshader")
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_uw_env.sky = sky
	_sky_material = mat

	# 可见水色与环境辐照分开；天空 cubemap 提供网页版半球光的上下两色。
	_uw_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_uw_env.ambient_light_color = Color("#b9e9e2")
	_uw_env.ambient_light_energy = (1.9 / PI)
	_uw_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_uw_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Three ACES 输入倍率为 exposure/0.6，Godot 为 exposure*1.8。
	_uw_env.tonemap_exposure = 1.1 / (0.6 * 1.8)
	# 使 Godot ACES 白点归一化因子为 1，与 Three 的曲线一致。
	_uw_env.tonemap_white = 14.260244
	# 实体由 uw_fog 屏幕通道统一叠雾，透明材质自行衰减，避免环境雾重复叠加。
	_uw_env.fog_enabled = false


func _update_sky(depth_now: float) -> void:
	if _sky_material != null:
		_sky_material.set_shader_parameter("dive_depth", maxf(0.0, -diver_pos.y))
	_fog_material.set_shader_parameter("dive_depth", maxf(0.0, -diver_pos.y))
	MaterialLib.set_depth(maxf(0.0, -diver_pos.y))
	var deep := clampf((-diver_pos.y - 12.0) / 64.0, 0.0, 1.0)
	_uw_env.ambient_light_energy = (1.9 / PI) * (1.0 - deep * 0.6)


# ---------------------------------------------------------------- 数据 / 碰撞
var _fish_specs: Array = []


func _load_swim_data() -> void:
	var text := FileAccess.get_file_as_string(SWIM_DATA)
	if text.is_empty():
		push_error("读不到 " + SWIM_DATA)
		return
	var data: Variant = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		push_error("swim.json 解析失败")
		return
	_solids = data.get("solids", [])
	_terraces = data.get("terraces", [])
	_trench = data.get("trenchProfile", [])
	_fish_specs = data.get("fish", [])


func _bounds_at(y: float) -> Vector2:
	var d := clampf((-y - 6.0) / 70.0, 0.0, 1.0)
	return Vector2(30.0 - 16.0 * d, 49.0 - 15.0 * d)


## 海沟剖面：z 沿负方向从 -26 到 -172。
func _trench_section(z: float) -> Dictionary:
	if _trench.is_empty() or z > -26.0 or z < -172.0:
		return {}
	for i in range(_trench.size() - 1):
		var a: Array = _trench[i]
		var b: Array = _trench[i + 1]
		if z <= float(a[0]) and z >= float(b[0]):
			var u := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			var s := u * u * (3.0 - 2.0 * u)
			return {
				"floor": lerpf(float(a[1]), float(b[1]), s),
				"half": lerpf(float(a[2]), float(b[2]), s),
				"rim": lerpf(float(a[3]), float(b[3]), s),
				"center": lerpf(float(a[4]), float(b[4]), s),
			}
	return {}


func trench_floor_at(x: float, z: float) -> float:
	var s := _trench_section(z)
	if s.is_empty():
		return INF
	var u: float = absf((x - float(s.center)) / float(s.half))
	if u > 1.000001:
		return INF
	return float(s.floor) + (float(s.rim) - float(s.floor)) * pow(minf(1.0, u), 4.0)


func _trench_contains(p: Vector3, margin: float) -> bool:
	var s := _trench_section(p.z)
	if s.is_empty() or p.z < -171.0 + margin:
		return false
	if absf(p.x - float(s.center)) >= float(s.half) - margin:
		return false
	var floor_y := trench_floor_at(p.x, p.z)
	if not is_finite(floor_y):
		return false
	return p.y > floor_y + margin and p.y < 4.0


func _inside_basin(p: Vector3, margin: float) -> bool:
	var b := _bounds_at(p.y)
	var rx: float = b.x - margin
	var rz: float = b.y - margin
	var old := p.y > -75.0 + margin and rx > 0.5 and rz > 0.5 \
		and (p.x / rx) * (p.x / rx) + (p.z / rz) * (p.z / rz) < 1.0
	return old or _trench_contains(p, margin)


func blocked(p: Vector3, margin := 0.35) -> bool:
	if not _inside_basin(p, margin + 1.0):
		return true
	for s in _solids:
		if p.y < float(s.top) + 0.5 and p.y > float(s.bottom) \
			and absf(p.x - float(s.x)) < float(s.w) + margin \
			and absf(p.z - float(s.z)) < float(s.d) + margin:
			return true
	for t in _terraces:
		if p.y < float(t[4]) + 0.85 and p.y > -76.0:
			var ex: float = float(t[2]) * 0.85 + margin
			var ez: float = float(t[3]) * 0.8 + margin
			if ex > 0.01 and ez > 0.01:
				if ((p.x - float(t[0])) / ex) * ((p.x - float(t[0])) / ex) \
					+ ((p.z - float(t[1])) / ez) * ((p.z - float(t[1])) / ez) < 1.0:
					return true
	return false


# ---------------------------------------------------------------- 输入
func cancel_navigation() -> void:
	_route.clear()
	_route_target_chest = {}
	_search = {}
	_search_t = 0.0
	_velocity = Vector3.ZERO

func swim_to(destination: Vector3) -> bool:
	if not active or phase != "swim": return false
	destination.y = clampf(destination.y,MOVE_MIN_Y,MOVE_MAX_Y)
	if not _inside_basin(destination,1.0) or blocked(destination):
		message.emit("这里有障碍，请点击附近的开阔水域")
		return false
	var points := _plan_route(destination)
	if points.is_empty():
		message.emit("这里暂时游不过去，请换个目标")
		return false
	cancel_navigation()
	_route = points
	message.emit("正在游向目标 · 可点取消停止")
	return true

func swim_to_screen(screen: Vector2) -> bool:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.001: return false
	var distance := (diver_pos.y-origin.y)/direction.y
	if distance <= 0.0: return false
	return swim_to(origin+direction*distance)

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			swim_to_screen(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = clampf(_distance - 0.8, CAM_MIN, CAM_MAX)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = clampf(_distance + 0.8, CAM_MIN, CAM_MAX)
	elif event is InputEventMouseMotion and _drag and phase == "swim":
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch + mm.relative.y * 0.008, 0.35, 1.55)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE and phase == "swim":
			surface()
		elif k.pressed and not k.echo and k.keycode == KEY_F and phase == "swim":
			# F 开头灯。开着能照见 26m 内的宝箱，但每秒额外烧氧。
			_toggle_lamp()


func _process(delta: float) -> void:
	if not active:
		# 上浮之后氧气照样回、恢复冷却照样走。否则「被强制上浮 → 想再潜」
		# 会永远卡在冷却里（_process 在 inactive 时早退）。
		if air != null:
			air.update(delta, 0.0, false, false)
		return
	_t += delta
	var dt := minf(delta, 0.05)

	match phase:
		"enter":
			_enter_t += dt
			var blend := smoothstep(0.0, 1.0, minf(_enter_t / ENTER_TIME, 1.0))
			diver_pos.y = lerpf(WATER_LEVEL, ENTER_DEPTH, blend)
			if blend >= 1.0:
				phase = "swim"
		"exit":
			_enter_t += dt
			var blend := smoothstep(0.0, 1.0, minf(_enter_t / ENTER_TIME, 1.0))
			diver_pos.y = lerpf(_exit_y, WATER_LEVEL, blend)
			if blend >= 1.0:
				_finish_exit()
				return
		"swim":
			_update_swim(dt)

	depth = maxf(0.0, WATER_LEVEL - diver_pos.y)
	_update_camera(dt, phase == "enter" or phase == "exit")
	_update_lamp()
	deco.update(dt, _t, diver_pos, camera)
	_update_diver(dt)
	_update_sky(depth)
	_update_air(dt)
	_update_markers()
	depth_changed.emit(depth)
	zone_changed.emit(_zone_name())


func _update_swim(dt: float) -> void:
	var axis := func(a: int, b: int, c: int, d: int) -> float:
		var pos := 0.0
		if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b):
			pos += 1.0
		if Input.is_physical_key_pressed(c) or Input.is_physical_key_pressed(d):
			pos -= 1.0
		return pos

	var x: float = axis.call(KEY_D, KEY_RIGHT, KEY_A, KEY_LEFT)
	var z: float = axis.call(KEY_S, KEY_DOWN, KEY_W, KEY_UP)
	var y: float = axis.call(KEY_E, KEY_SPACE, KEY_Q, KEY_Q)
	var desired := Vector3(x, y * 0.7, z)
	if desired.length() > 1.0:
		desired = desired.normalized()
	# Shift 加速：省时间，但氧气消耗乘 1.9（见 dive_air.gd）。
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	desired = desired.rotated(Vector3.UP, _yaw) * (SPRINT_SPEED if sprint else SWIM_SPEED)
	if absf(x) + absf(y) + absf(z) > 0.01:
		cancel_navigation()

	if not _route.is_empty():
		var target: Vector3 = _route[0]
		var delta_v := target - diver_pos
		var length := delta_v.length()
		if length < 0.25:
			_route.pop_front()
			if _route.is_empty() and not _search.is_empty():
				_search_t = 0.0
		else:
			desired = delta_v.normalized() * minf(4.5, length * 3.0)

	_velocity = _velocity.lerp(desired, 1.0 - exp(-dt * 7.0))
	var next := diver_pos + _velocity * dt
	next.y = clampf(next.y, MOVE_MIN_Y, MOVE_MAX_Y)
	next.x = clampf(next.x, -50.0, 50.0)
	next.z = clampf(next.z, -170.5, 48.0)

	if not blocked(next):
		diver_pos = next
	else:
		# 逐轴回退：贴着台地边缘能滑过去，但不会穿下去。
		# 逐轴回退（Vector3 不支持按名字索引，只能逐个写）。
		var probe_y := Vector3(diver_pos.x, next.y, diver_pos.z)
		if not blocked(probe_y):
			diver_pos.y = next.y
		else:
			_velocity.y = 0.0
		var probe_x := Vector3(next.x, diver_pos.y, diver_pos.z)
		if not blocked(probe_x):
			diver_pos.x = next.x
		else:
			_velocity.x = 0.0
		var probe_z := Vector3(diver_pos.x, diver_pos.y, next.z)
		if not blocked(probe_z):
			diver_pos.z = next.z
		else:
			_velocity.z = 0.0

	# 搜索进度
	if not _search.is_empty():
		var chest: Dictionary = _search
		if not _route.is_empty():
			_search_t = 0.0
		elif diver_pos.distance_to(chest.pos) > SEARCH_RADIUS:
			_search = {}
			_search_t = 0.0
			message.emit("离宝箱太远了")
		else:
			_search_t += dt
			if _search_t >= SEARCH_TIME:
				_open_chest(chest)


func _update_camera(dt: float, snap: bool) -> void:
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var target := diver_pos + Vector3(0, 0.5, 0) + forward * 1.6
	var cam := diver_pos + forward * (-_distance) + Vector3(0, _distance * _pitch, 0)
	cam.y = minf(cam.y, WATER_LEVEL - 0.4)
	for i in 24:
		if not blocked(cam, 0.15):
			break
		cam = cam.lerp(diver_pos, 0.2)
	if snap:
		camera.global_position = cam
	else:
		camera.global_position = camera.global_position.lerp(cam, 1.0 - exp(-dt * 6.0))
	camera.look_at(target, Vector3.UP)


## 氧气推进。归零不是扣资源，而是强制上浮 —— 失败有代价，但不清空背包。
func _update_air(dt: float) -> void:
	var moving := _velocity.length() > 0.45
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT) and moving
	var event := air.update(dt, depth, moving, sprint)
	match event:
		"low":
			message.emit("余气不多 · 还剩 %d%%" % int(round(air.ratio() * 100.0)))
		"crit":
			message.emit("氧气见底！按 E 或点上浮回水面")
		"empty":
			message.emit("氧气耗尽 · 强制上浮")
			surface()
	_air_emit_t += dt
	if _air_emit_t >= 0.12:
		_air_emit_t = 0.0
		_emit_air()


func _emit_air() -> void:
	air_changed.emit(air.ratio(), air.lamp, discovered_count(), _chests.size())


## 头灯：位置与朝向跟着相机走（右键拖拽环视时灯也跟着扫）。
## 主光和补光走 PBR；这里推送额外头灯散射项。
func _update_lamp() -> void:
	var on: bool = bool(air.lamp) and phase != "surface"
	var basis := camera.global_transform.basis
	var pos := camera.global_position + basis * Vector3(0.34, -0.22, -0.1)
	var dir := -basis.z
	MaterialLib.set_lamp(on, pos, dir)


func _toggle_lamp() -> void:
	air.lamp = not air.lamp
	message.emit("头灯 " + ("开" if air.lamp else "关"))
	_emit_air()


func _update_diver(dt: float) -> void:
	if _diver == null:
		return
	_diver.position = diver_pos
	var flat := Vector2(_velocity.x, _velocity.z)
	if flat.length() > 0.15:
		_heading = atan2(-flat.y, flat.x)
	_diver.rotation.y = lerp_angle(_diver.rotation.y, _heading, minf(1.0, dt * 7.0))


## 调试用：把潜点瞬间挪到某处（回归截图用）。
func debug_teleport(p: Vector3) -> void:
	phase = "swim"
	diver_pos = p
	_velocity = Vector3.ZERO
	_update_camera(0.0, true)


## 诊断：冻住焦散/闪光的相位（负值恢复成跟 TIME 走）。
func freeze_time(t: float) -> void:
	MaterialLib.freeze_time(t)


## 诊断：把所有海底几何画成「正面绿 / 背面红」，用来看绕序有没有整体反掉。
func set_facing_debug(on: bool) -> void:
	MaterialLib.set_facing_debug(self, on)


## 取某个海底区块的节点（诊断与自检用）：按 `region` 字段找，不靠节点名。
func region_node(id: String) -> Node3D:
	for r in region_nodes():
		if str(r.get("region")) == id:
			return r
	return null


func _zone_name() -> String:
	if diver_pos.z < -78.0:
		return "北境沉船海沟"
	if diver_pos.z < -34.0:
		return "北境断层"
	return _surface_zone if _surface_zone != "" else "珊瑚礁盘"


# ---------------------------------------------------------------- 宝箱
## 水里的那个小人：另起一个角色实例，戴上潜水镜与氧气瓶。
## 不复用海面那个 —— 它挂在船锚下，潜水时整条船都隐藏了。
func _build_diver() -> void:
	_diver = CharacterScript.new()
	_diver.name = "Diver"
	add_child(_diver)
	_diver.build()
	_diver.set_diving(true)
	_diver.hat.visible = false
	MaterialLib.apply_to_standard_meshes(_diver)
	_diver.scale = Vector3.ONE * 1.25
	_diver.position = Vector3(0, WATER_LEVEL, 12)
	_diver.rotation.y = PI


func _build_chests() -> void:
	var text := FileAccess.get_file_as_string(SWIM_DATA)
	if text.is_empty():
		return
	var data: Variant = JSON.parse_string(text)
	for spec in data.get("chests", []):
		var pos_arr: Array = spec.pos
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var g := Node3D.new()
		g.name = "Chest%d" % int(spec.id)
		g.position = pos
		chests_root.add_child(g)

		var wood := _box(g, Color("#624a34"), Vector3(0, 0.4, 0), Vector3(1.35, 0.75, 0.85))
		for s in [-1, 1]:
			_box(g, Color("#d9b962"), Vector3(s * 0.45, 0.42, 0), Vector3(0.1, 0.8, 0.9))
		var lid := Node3D.new()
		lid.position = Vector3(0, 0.79, -0.43)
		g.add_child(lid)
		_box(lid, Color("#94714b"), Vector3(0, 0.12, 0.43), Vector3(1.42, 0.25, 0.92))
		for s in [-1, 1]:
			_box(lid, Color("#dfbf6b"), Vector3(s * 0.45, 0.14, 0.43), Vector3(0.11, 0.28, 0.94))
		_box(g, Color("#f2d887"), Vector3(0, 0.55, 0.46), Vector3(0.18, 0.23, 0.08))

		_chests.append({
			"id": int(spec.id),
			"name": str(spec.name),
			"pos": pos,
			"reward": spec.get("reward", {}),
			"node": g,
			"lid": lid,
			"opened": false,
			"discovered": false,
			"open_t": 0.0,
			"marker": null,
		})
		wood.name = "Body"


func _box(parent: Node3D, color: Color, pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := MaterialLib.from_color(color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _build_markers() -> void:
	_marker_layer = CanvasLayer.new()
	_marker_layer.name = "UwMarkers"
	_marker_layer.layer = 6
	_marker_layer.visible = false
	add_child(_marker_layer)
	var font := preload("res://src/ui/cozy_ui.gd").ui_font()
	for chest in _chests:
		var label := Label.new()
		label.text = "◇ " + chest.name
		label.add_theme_font_override("font", font)
		# 世界浮层字统一走 Cozy.world_text：大号、圆润、不勾边。
		preload("res://src/ui/cozy_ui.gd").world_text(label, 0.65, Color("#e8fdf4"))
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_marker_input.bind(chest))
		_marker_layer.add_child(label)
		chest.marker = label
		# 没发现的宝箱不给标签，否则又变成一张清单。
		label.visible = bool(chest.discovered)


func _on_marker_input(event: InputEvent, chest: Dictionary) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# 只能点自己已经发现的宝箱。没发现的连标签都没有，这里是双保险。
	if not bool(chest.discovered):
		return
	_visit_chest(chest)


## 头灯扫过 / 游到跟前，就算「发现」。发现后标签常驻（本次游戏内）。
func _scan_chests() -> void:
	var basis := camera.global_transform.basis
	var fwd := -basis.z
	var lamp_on: bool = bool(air.lamp) and phase == "swim"
	for chest in _chests:
		if bool(chest.discovered):
			continue
		var to: Vector3 = chest.pos - diver_pos
		var dist := to.length()
		var near: bool = dist <= DISCOVER_NEAR
		var lit: bool = false
		if lamp_on and dist <= DISCOVER_LAMP and dist > 0.01:
			lit = fwd.dot(to / dist) >= DISCOVER_DOT
		if not (near or lit):
			continue
		chest.discovered = true
		if chest.marker != null:
			chest.marker.visible = not chest.opened
		var left := _chests.size() - discovered_count()
		if left > 0:
			message.emit("发现 · %s（还剩 %d 处未发现）" % [chest.name, left])
		else:
			message.emit("发现 · %s（已找齐 %d 处）" % [chest.name, _chests.size()])


func _refresh_chest_visibility() -> void:
	for chest in _chests:
		if chest.marker != null:
			chest.marker.visible = bool(chest.discovered) and not bool(chest.opened)


func discovered_count() -> int:
	var n := 0
	for c in _chests:
		if bool(c.discovered) and not bool(c.opened):
			n += 1
	return n


func _update_markers() -> void:
	if _marker_layer == null or not _marker_layer.visible:
		return
	# 先看这一帧有没有新发现（头灯扫到 / 游到跟前），再更新标签。
	if phase == "swim":
		_scan_chests()
	for chest in _chests:
		var label: Label = chest.marker
		if label == null:
			continue
		if chest.opened or not bool(chest.discovered):
			label.visible = false
			continue
		var world: Vector3 = chest.pos + Vector3(0, 1.6, 0)
		if camera.is_position_behind(world):
			label.visible = false
			continue
		var screen := camera.unproject_position(world)
		var dist := diver_pos.distance_to(chest.pos)
		label.visible = dist <= 34.0 and absf(diver_pos.y - chest.pos.y) <= 21.0
		var w: float = label.get_minimum_size().x
		label.position = Vector2(screen.x - w * 0.5, screen.y - 14)
		if not _route.is_empty() and _route_target_chest == chest:
			label.text = "◇ 正在前往"
		elif dist < SEARCH_RADIUS:
			label.text = "◇ 搜索"
		else:
			label.text = "◇ %d m" % int(ceil(dist))
		var near := dist < SEARCH_RADIUS
		label.add_theme_color_override("font_color",
			Color("#fff3c9") if near else Color("#e8fdf4"))


var _route_target_chest: Dictionary = {}


func _visit_chest(chest: Dictionary) -> void:
	if phase != "swim" or chest.opened:
		return
	if not bool(chest.discovered):
		# 没发现的地方不给导航 —— 否则「探索」又变回点清单。
		message.emit("这里什么都看不见，先找到它")
		return
	if _search.get("id", -1) == chest.id:
		return
	cancel_navigation()
	if diver_pos.distance_to(chest.pos) <= SEARCH_RADIUS:
		_search = chest
		_search_t = 0.0
		message.emit("搜索 " + chest.name)
		return
	var destination: Vector3 = chest.pos + Vector3(
		1.6 if chest.pos.x < 0.0 else (-1.6 if chest.pos.x > 0.0 else 0.0), 1.45, 1.1)
	var points := _plan_route(destination)
	if points.is_empty():
		message.emit("前方礁石较密，先游到开阔水域")
		return
	_route = points
	_route_target_chest = chest
	_search = chest
	message.emit("正在游向 " + chest.name)


func _plan_route(destination: Vector3) -> Array:
	var start := diver_pos
	if _clear_segment(start, destination):
		return [destination]
	if blocked(destination):
		return []
	var step := 2.5
	var open: Array = []
	var best := {"key": Vector3i.ZERO, "p": start, "g": 0.0,
		"f": start.distance_to(destination), "parent": null}
	open.append(best)
	var visited := {Vector3i.ZERO: best}
	var finish: Variant = null
	var count := 0
	while not open.is_empty() and count < 4500:
		count += 1
		open.sort_custom(func(a, b): return float(a.f) > float(b.f))
		var node: Dictionary = open.pop_back()
		if node.get("closed", false):
			continue
		node["closed"] = true
		var np: Vector3 = node.p
		if np.distance_to(destination) < step * 1.8 and _clear_segment(np, destination):
			finish = node
			break
		for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var key: Vector3i = node.key + dir
			var p: Vector3 = start + Vector3(key) * step
			if not _inside_basin(p, 1.0) or p.y < MOVE_MIN_Y + 1.5 or p.y > MOVE_MAX_Y:
				continue
			if not _clear_segment(np, p):
				continue
			var g: float = float(node.g) + step
			if visited.has(key) and float(visited[key].g) <= g:
				continue
			var nxt := {"key": key, "p": p, "g": g,
				"f": g + p.distance_to(destination), "parent": node, "closed": false}
			visited[key] = nxt
			open.append(nxt)
	if finish == null:
		return []
	var path: Array = [destination]
	var cursor: Variant = finish
	while cursor != null and cursor.get("parent") != null:
		path.push_front(cursor.p)
		cursor = cursor.parent
	# 拉绳平滑
	var smooth: Array = []
	var anchor := start
	var i := 0
	while i < path.size():
		var last := i
		for j in range(i + 1, path.size()):
			if not _clear_segment(anchor, path[j]):
				break
			last = j
		smooth.append(path[last])
		anchor = path[last]
		i = last + 1
	return smooth


func _clear_segment(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / 0.6)))
	for i in range(1, steps + 1):
		if blocked(a.lerp(b, float(i) / float(steps))):
			return false
	return true


func _open_chest(chest: Dictionary) -> void:
	_search = {}
	_search_t = 0.0
	_route.clear()
	var reward: Dictionary = chest.reward
	for key in reward.keys():
		Economy.add_resource(str(key), int(reward[key]))
	chest.opened = true
	chest.discovered = true
	if chest.marker != null:
		chest.marker.visible = false
	var parts: Array = []
	for key in reward.keys():
		parts.append("%s +%d" % [_material_name(str(key)), int(reward[key])])
	message.emit("找到物资 · " + "  ".join(parts))
	_emit_air()


func _material_name(key: String) -> String:
	match key:
		"wood": return "木料"
		"parts": return "旧零件"
		"pearl": return "珍珠"
		"coins": return "海贝"
		"fish": return "鱼"
		_: return key


func _physics_process(_delta: float) -> void:
	for chest in _chests:
		if chest.opened:
			chest.open_t = minf(1.0, chest.open_t + 0.04)
			var lid: Node3D = chest.lid
			lid.rotation.x = lerpf(lid.rotation.x, -1.7, chest.open_t * 0.2)


# ---------------------------------------------------------------- 存档
## 潜水的进度只存「哪些宝箱被发现 / 打开」。氧气是**本次下潜内**的资源，
## 读档一律回到船上并满氧气，否则会出现「在船上却没气」的荒谬状态。
func to_dict() -> Dictionary:
	var found: Array = []
	var opened: Array = []
	for chest in _chests:
		if bool(chest.discovered):
			found.append(int(chest.id))
		if bool(chest.opened):
			opened.append(int(chest.id))
	return {"found": found, "opened": opened}


func from_dict(data: Dictionary) -> void:
	var found: Array = data.get("found", [])
	var opened: Array = data.get("opened", [])
	# 这是一份**全量**快照：先全部复位，再按档里的记录打回去。
	# 只做「加上」不做「清掉」的话，读旧档会把当前进度叠在新档上。
	for chest in _chests:
		chest.opened = false
		chest.discovered = false
		chest.open_t = 0.0
		if chest.lid != null:
			(chest.lid as Node3D).rotation.x = 0.0
	for chest in _chests:
		var id := int(chest.id)
		if opened.has(id) or opened.has(float(id)):
			chest.opened = true
			chest.discovered = true
			chest.open_t = 1.0
			if chest.lid != null:
				(chest.lid as Node3D).rotation.x = -1.7
		elif found.has(id) or found.has(float(id)):
			chest.discovered = true
	_refresh_chest_visibility()


# ---------------------------------------------------------------- 查询接口（供测试）
func chest_count() -> int:
	return _chests.size()


func opened_chests() -> int:
	var n := 0
	for c in _chests:
		if c.opened:
			n += 1
	return n


## 自检用：直接给某个宝箱打上「已发现」，不必真的游过去。
func debug_discover(index: int) -> void:
	if index < 0 or index >= _chests.size():
		return
	_chests[index].discovered = true
	_refresh_chest_visibility()


func region_nodes() -> Array:
	return regions_root.get_children() if regions_root != null else []


func search_state() -> Dictionary:
	return _search


func _build_fog_pass() -> void:
	var quad := MeshInstance3D.new()
	quad.name = "UnderwaterFogPass"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = load("res://shaders/uw_fog.gdshader")
	# Web(gl_compatibility) 不是 Reverse-Z，深度反投影要换算（否则水雾整片糊死）。
	_fog_material.set_shader_parameter("u_reverse_z", RenderFlagsLib.reverse_z())
	_fog_material.render_priority = -128
	quad.material_override = _fog_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	quad.extra_cull_margin = 16384.0
	camera.add_child(quad)
	quad.position.z = -1.0
