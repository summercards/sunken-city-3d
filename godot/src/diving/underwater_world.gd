extends Node3D
var give_resource: Callable
var give_rewards: Callable
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
const DiveAirLib = preload("res://src/diving/dive_air.gd")

@export var map_id := "dive_zone1"
@export var map_label := ""
@export_file("*.json") var swim_data_path: String = SWIM_DATA
## 旧数据的局部 ID / 零基鱼群索引；空数组表示不生成该类内容。
@export var chest_ids: Array[int] = [0, 1, 2, 3, 4]
@export var fish_indices: Array[int] = [0, 1, 2, 3, 4, 5, 6]
@export var chest_id_base := 0
## 旧导出顺序：0..32 街区楼体/桥/车辆，33..42 海沟沉船。
@export var neighborhood_solid_indices: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
@export var trench_solid_indices: Array[int] = [33, 34, 35, 36, 37, 38, 39, 40, 41, 42]
@export var neighborhood_collision_enabled := true
@export var trench_collision_enabled := true
@export var basin_closure_enabled := false
## 入水动作由调用方读取此坐标；旧入口的默认值保持不变。
@export var spawn_point := Vector3(0, 1.12, 12)

@onready var regions_root: Node3D = get_node_or_null("Regions") as Node3D
@onready var deco: Node3D = get_node_or_null("Deco") as Node3D
@onready var camera: Camera3D = get_node_or_null("DiveCamera") as Camera3D
@onready var chests_root: Node3D = get_node_or_null("Chests") as Node3D

var active := false
var _compat_phase_machine = preload("res://src/core/state_machine.gd").new()
var dive_controller: Node = null
var phase_machine:
	get: return dive_controller.machine if is_instance_valid(dive_controller) else _compat_phase_machine
var phase: String:
	get:
		var machine = phase_machine
		return machine.current if machine.current != "" else "surface"
	set(value): phase_machine.change(value)
var diver_pos := Vector3.ZERO
var depth := 0.0

var _t := 0.0
var _enter_t := 0.0
var _exit_y := 0.0

var _surface_nodes: Array = []
var _world_env: WorldEnvironment
var _saved_env: Environment
var _uw_env: Environment
var _sky_material: ShaderMaterial
var _fog_material: ShaderMaterial
var _sun_profile := {"direction":Vector3(0.5191,0.7787,-0.3523), "color":Color(1.0,0.955,0.8), "strength":1.0}

func underwater_surface_debug_materials() -> Array:
	var out: Array = []
	if deco != null and deco.has_method("underwater_surface_debug_materials"):
		out.append_array(deco.underwater_surface_debug_materials())
	return out

func underwater_surface_debug_runtime() -> Dictionary:
	return {"map": map_label if not map_label.is_empty() else map_id,
		"water_level": WATER_LEVEL, "view_depth": maxf(0.0, WATER_LEVEL - diver_pos.y),
		"sun_strength": float(_sun_profile.get("strength", 0.0))}

func configure_underwater_light(profile: Dictionary) -> void:
	_sun_profile = {"direction":profile.get("direction",Vector3(0.5191,0.7787,-0.3523)),
		"color":profile.get("color",Color(1.0,0.955,0.8)), "strength":clampf(float(profile.get("strength",1.0)),0.0,1.0),
		"surface":profile.get("surface", _sun_profile.get("surface", {})).duplicate()}
	if _sky_material != null: _apply_underwater_light()

func _apply_underwater_light() -> void:
	for mat in [_sky_material, _fog_material]:
		if mat == null: continue
		mat.set_shader_parameter("sun_direction",_sun_profile.direction)
		mat.set_shader_parameter("sun_color",_sun_profile.color)
		mat.set_shader_parameter("sun_strength",_sun_profile.strength)
	MaterialLib.set_water_level(WATER_LEVEL)
	MaterialLib.set_sun(_sun_profile.direction,_sun_profile.color,_sun_profile.strength)
	if deco != null and deco.has_method("configure_underwater_light"):
		deco.configure_underwater_light(_sun_profile)
var _surface_zone := ""

var _solids: Array = []
var _terraces: Array = []
var _trench := []
var _chests: Array = []
var _chest_markers: Array = []
var search_action = preload("res://src/diving/actions/search_action.gd").new()
var _search: Dictionary = {}
var _search_t := 0.0
var _route: Array = []
var _marker_layer: CanvasLayer
var _diver: Node3D
var _heading := 0.0
## 氧气与头灯（纯状态机，见 src/diving/dive_air.gd）。
var air = DiveAirLib.new()
## 每帧推给 HUD 的节流（不必每帧改 Label）。
var _air_emit_t := 0.0


func setup(surface_nodes: Array, world_env: WorldEnvironment) -> bool:
	var error := _map_structure_error(world_env)
	if not error.is_empty():
		push_error("潜水地图 %s 初始化失败: %s" % [map_id, error])
		return false
	if not _load_swim_data():
		return false
	error = _map_content_error()
	if not error.is_empty():
		push_error("潜水地图 %s 初始化失败: %s" % [map_id, error])
		return false
	_surface_nodes = surface_nodes
	_world_env = world_env
	_saved_env = world_env.environment
	_build_environment()
	_build_fog_pass()
	if basin_closure_enabled:
		_build_basin_closure()
	var controller_script = load("res://src/diving/dive_runtime_controller.gd")
	if controller_script == null:
		push_error("缺少 DiveRuntimeController")
		return false
	dive_controller = controller_script.new()
	dive_controller.name = "DiveRuntimeController"
	add_child(dive_controller)
	dive_controller.configure(self, camera, self, "Diver")
	var configured_air: Variant = dive_controller.get("air")
	if configured_air != null:
		air = configured_air
	_diver = dive_controller.character
	_build_chests()
	# 独立地图完成初始化后由 enter 状态显示，海面不持有此几何实例。
	visible = false
	_build_markers()
	deco.setup(_fish_specs)
	_apply_underwater_light()
	return true


# ---------------------------------------------------------------- 进入 / 离开
func dive(_boat_pos: Vector3, zone_label := "") -> void:
	if active or dive_controller == null:
		return
	if not air.can_dive():
		message.emit("刚上浮，先喘口气（%.0f 秒）" % ceil(air.recover))
		return
	dive_controller.begin({"zone": zone_label})


func surface() -> void:
	if active and dive_controller != null:
		dive_controller.request_surface()


func _finish_exit() -> void:
	if dive_controller != null and dive_controller.has_method("request_surface"):
		dive_controller.request_surface()


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
	# 天空 cubemap 已经乘 uw_depth_light 与 sun_strength；环境能量只保留固定基准。
	# 深度与夜间系数不在 CPU 侧重复相乘，避免浅层被二次压暗。
	_uw_env.ambient_light_energy = 2.6 / PI
	_uw_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_uw_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Three ACES 输入倍率为 exposure/0.6，Godot 为 exposure*1.8。
	_uw_env.tonemap_exposure = 1.1 / (0.6 * 1.8)
	# 使 Godot ACES 白点归一化因子为 1，与 Three 的曲线一致。
	_uw_env.tonemap_white = 14.260244
	# 实体由 uw_fog 屏幕通道统一叠雾，透明材质自行衰减，避免环境雾重复叠加。
	_uw_env.fog_enabled = false


func _update_sky(depth_now: float) -> void:
	var actual_depth := maxf(0.0, WATER_LEVEL - diver_pos.y)
	if _sky_material != null:
		_sky_material.set_shader_parameter("dive_depth", actual_depth)
	_fog_material.set_shader_parameter("dive_depth", actual_depth)
	_fog_material.set_shader_parameter("water_level", WATER_LEVEL)
	MaterialLib.set_depth(actual_depth)
	# 天空 cubemap 已经乘 uw_depth_light 与 sun_strength；这里不重复乘深度/夜间系数。
	# 仅提升固定环境基准，实际深层衰减由天空辐照一次控制；曝光、头灯和设施灯不变。
	_uw_env.ambient_light_energy = 2.6 / PI


# ---------------------------------------------------------------- 数据 / 碰撞
var _fish_specs: Array = []
var _chest_specs: Array = []


func _map_structure_error(world_env: WorldEnvironment) -> String:
	if not is_node_ready() or not is_inside_tree():
		return "必须在地图进入场景树且 ready 后调用 setup"
	if regions_root == null or deco == null or camera == null or chests_root == null:
		return "缺少 Regions / Deco / DiveCamera / Chests 必需节点"
	if not deco.has_method("setup") or not deco.has_method("update"):
		return "Deco 缺少鱼群装配接口"
	if not is_instance_valid(world_env) or not world_env.is_inside_tree():
		return "环境节点无效或不在场景树内"
	if not (get_node_or_null("WorldEnvironment") is WorldEnvironment):
		return "缺少地图本地 WorldEnvironment"
	if world_env != get_node_or_null("WorldEnvironment"):
		return "必须传入当前地图的本地 WorldEnvironment，不能引用已移出树的 Main 环境"
	if transform != Transform3D.IDENTITY or regions_root.transform != Transform3D.IDENTITY:
		return "地图根与 Regions 必须保持 baked 数据原坐标"
	if map_id.is_empty() or not spawn_point.is_finite():
		return "map_id 为空或出生点不是有限坐标"
	if not is_equal_approx(spawn_point.y, WATER_LEVEL):
		return "出生点 Y 必须等于入水动作使用的 WATER_LEVEL"
	if region_node("basin") == null:
		return "必须保留 basin 可见容器与台地"
	var has_neighborhood := region_node("neighborhood") != null
	var has_trench := region_node("trench") != null
	if neighborhood_collision_enabled != has_neighborhood or trench_collision_enabled != has_trench:
		return "街区 / 海沟碰撞开关必须与可见 region 同步"
	if basin_closure_enabled == has_trench:
		return "无海沟地图必须封闭北侧开口，有海沟地图不得封口"
	for region in region_nodes():
		if not region.visible:
			return "region 必须可见: " + str(region.name)
		# reef 是无碰撞装饰，可独立变换；其余 region 与 baked 坐标严格对齐。
		if str(region.get("region")) != "reef" and region.transform != Transform3D.IDENTITY:
			return "碰撞所属 region 必须保持原坐标，暂不接受未同步的变换"
		if region.get("instance_count") == null or int(region.get("instance_count")) <= 0:
			return "region 未成功装配几何: " + str(region.name)
	return ""


func _load_swim_data() -> bool:
	_solids = []
	_terraces = []
	_trench = []
	_fish_specs = []
	_chest_specs = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(swim_data_path))
	if not (data is Dictionary):
		push_error("潜水数据读取或解析失败: " + swim_data_path)
		return false
	for key in ["solids", "terraces", "trenchProfile", "fish", "chests"]:
		if not (data.get(key) is Array):
			push_error("潜水数据缺少数组: " + key)
			return false
	var solids: Array = data.solids
	# 归属依据 export_underwater.cjs 与旧生成器；沉船的十段碰撞不能归街区。
	for group_index in range(2):
		var enabled := neighborhood_collision_enabled if group_index == 0 else trench_collision_enabled
		if not enabled:
			continue
		var indices: Array[int] = neighborhood_solid_indices if group_index == 0 else trench_solid_indices
		for index in indices:
			var belongs := index >= 0 and index < 33 if group_index == 0 else index >= 33 and index < 43
			if not belongs or index >= solids.size() or not (solids[index] is Dictionary):
				push_error("潜水实体碰撞索引无效: " + str(index))
				return false
			var solid: Dictionary = solids[index]
			for key in ["x", "z", "w", "d", "top", "bottom"]:
				if not _finite_number(solid.get(key)):
					push_error("潜水实体碰撞字段无效: " + key)
					return false
			_solids.append(solid)
	_terraces = data.terraces
	if trench_collision_enabled:
		_trench = data.trenchProfile
	if _terraces.is_empty() or (trench_collision_enabled and _trench.size() < 2):
		push_error("潜水台地或海沟数据为空")
		return false
	for row in _terraces + _trench:
		if not (row is Array) or row.size() != 5:
			push_error("潜水台地 / 海沟数据行无效")
			return false
		for value in row:
			if not _finite_number(value):
				push_error("潜水台地 / 海沟坐标无效")
				return false
	for index in fish_indices:
		if index < 0 or index >= data.fish.size():
			push_error("潜水鱼群索引无效: " + str(index))
			return false
		var fish: Variant = data.fish[index]
		if not (fish is Dictionary) or not _coordinate_array(fish.get("center")):
			push_error("潜水鱼群坐标无效")
			return false
		_fish_specs.append(fish)
	for id in chest_ids:
		var matched := false
		for spec in data.chests:
			if not (spec is Dictionary) or not _finite_number(spec.get("id")):
				push_error("潜水宝箱数据无效")
				return false
			if int(spec.id) != id:
				continue
			if not _coordinate_array(spec.get("pos")) or not (spec.get("reward") is Dictionary) or not (spec.get("name") is String):
				push_error("潜水宝箱字段无效: " + str(id))
				return false
			_chest_specs.append(spec)
			matched = true
			break
		if not matched:
			push_error("潜水宝箱局部 ID 不存在: " + str(id))
			return false
	return true


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _coordinate_array(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _finite_number(value[0]) and _finite_number(value[1]) and _finite_number(value[2])


func _map_content_error() -> String:
	# 固定 XZ，从水面到 ENTER_DEPTH；与父线程 enter_action 的 spawn 约定一致。
	var end := Vector3(spawn_point.x, ENTER_DEPTH, spawn_point.z)
	if blocked(spawn_point) or not _clear_segment(spawn_point, end):
		return "出生点或完整下潜路径有阻挡"
	for spec in _chest_specs:
		var p := Vector3(float(spec.pos[0]), float(spec.pos[1]), float(spec.pos[2]))
		if not _inside_basin(p, 0.0):
			return "宝箱不在地图游泳容器内: " + str(spec.id)
		var destination := p + Vector3(1.6 if p.x < 0.0 else (-1.6 if p.x > 0.0 else 0.0), 1.45, 1.1)
		if blocked(destination):
			return "宝箱交互站位被阻挡: " + str(spec.id)
	return ""


## 原 basin 在北侧省略了海沟入口扇区；无 trench 时补回同一曲面的可见边界。
func _build_basin_closure() -> void:
	var closure := Node3D.new()
	closure.name = "BasinClosure"
	region_node("basin").add_child(closure)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(11):
		for k in range(48):
			if sin((float(k) + 0.5) / 48.0 * TAU) >= -0.72:
				continue
			var corners: Array[Vector3] = []
			for cell in [Vector2i(k, row), Vector2i(k, row + 1), Vector2i(k + 1, row), Vector2i(k + 1, row + 1)]:
				var y := 4.0 - float(cell.y) * 80.0 / 11.0
				var bounds := _bounds_at(y)
				var angle := float(cell.x) / 48.0 * TAU
				var ripple := 1.0 + sin(float(cell.x) * 0.93 + float(cell.y) * 0.7) * 0.024
				corners.append(Vector3(cos(angle) * (bounds.x + 1.0) * ripple, y, sin(angle) * (bounds.y + 1.0) * ripple))
			for index in [0, 1, 2, 1, 3, 2]:
				surface.add_vertex(corners[index])
	surface.generate_normals()
	var wall := MeshInstance3D.new()
	wall.name = "NorthBasinWall"
	wall.mesh = surface.commit()
	wall.material_override = MaterialLib.from_color(Color("#4b8797"), {"double_side": true})
	closure.add_child(wall)
	# 旧底板北缘到 z=-26；补齐容器在此以北的底面。
	_box(closure, Color("#407b88"), Vector3(0, -76, -38), Vector3(90, 2, 24))


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


# ---------------------------------------------------------------- 控制器适配
func dive_water_level() -> float:
	return WATER_LEVEL

func dive_begin(payload: Dictionary) -> void:
	# Session shares one Air model; returning from the 1m home entry must not
	# leak its local 0.5m breathing band into the original nine maps.
	air.surface_depth = DiveAirLib.SURFACE_DEPTH
	_surface_zone = str(payload.get("zone", ""))
	active = true
	_enter_t = 0.0
	visible = true
	_set_surface_visible(false)
	_world_env.environment = _uw_env
	camera.fov = dive_controller.FOV
	camera.near = 0.12
	camera.current = true
	deco.visible = true
	chests_root.visible = true
	if _marker_layer != null:
		_marker_layer.visible = true
	diver_pos = spawn_point
	_route.clear()
	_route_target_chest = {}
	_search = {}
	_search_t = 0.0
	_refresh_chest_visibility()
	_update_lamp()
	depth = 0.0
	depth_changed.emit(depth)
	_emit_air()

func dive_entry_ready() -> bool:
	# setup 已复核完整入水段，旧九图无需等待 Terrain3D 延迟提交。
	return active

func dive_entry_progress() -> float:
	return clampf(_enter_t / ENTER_TIME, 0.0, 1.0)

func dive_entry_tick(dt: float) -> bool:
	_enter_t = minf(_enter_t + maxf(dt, 0.0), ENTER_TIME)
	var blend := 1.0 - pow(1.0 - dive_entry_progress(), 3.0)
	# setup 已验证同 XZ 的完整连续通道；此处不走游泳夹限，避免第一帧被
	# MOVE_MAX_Y=-4.8 强行压入水中。旧九图 2.2s / Y=-10 终点保持。
	diver_pos.y = lerpf(spawn_point.y, ENTER_DEPTH, blend)
	return dive_entry_progress() >= 1.0

func dive_exit_begin() -> void:
	_enter_t = 0.0
	_exit_y = diver_pos.y
	_route.clear()
	_route_target_chest = {}
	_search = {}
	_search_t = 0.0
	if _marker_layer != null:
		_marker_layer.visible = false

func dive_exit_tick(dt: float) -> bool:
	_enter_t += dt
	var blend := smoothstep(0.0, 1.0, minf(_enter_t / ENTER_TIME, 1.0))
	diver_pos.y = lerpf(_exit_y, WATER_LEVEL, blend)
	return blend >= 1.0

func dive_end() -> void:
	active = false
	_route.clear()
	_route_target_chest = {}
	MaterialLib.set_lamp(false, Vector3.ZERO, Vector3(0, 0, -1))
	visible = false
	_set_surface_visible(true)
	_world_env.environment = _saved_env
	camera.current = false
	deco.visible = false
	chests_root.visible = false
	depth = 0.0
	exited.emit()

func dive_position() -> Vector3:
	return diver_pos

func dive_set_position(p: Vector3) -> void:
	diver_pos = p
	depth = maxf(0.0, WATER_LEVEL - diver_pos.y)

func dive_move(displacement: Vector3) -> Vector3:
	var before := diver_pos
	if not displacement.is_finite(): return Vector3.ZERO
	# 连续小段检测，不用终点检查冒充扫掠；低帧/冲刺也不能越过薄障碍。
	var steps := clampi(ceili(displacement.length() / 0.12), 1, 4096)
	var segment := displacement / float(steps)
	for i in steps:
		var next := diver_pos + segment
		next.y = clampf(next.y, MOVE_MIN_Y, MOVE_MAX_Y)
		next.x = clampf(next.x, -50.0, 50.0)
		next.z = clampf(next.z, -170.5, 48.0)
		if not blocked(next):
			diver_pos = next
		else:
			var probe_y := Vector3(diver_pos.x, next.y, diver_pos.z)
			if not blocked(probe_y): diver_pos.y = next.y
			var probe_x := Vector3(next.x, diver_pos.y, diver_pos.z)
			if not blocked(probe_x): diver_pos.x = next.x
			var probe_z := Vector3(diver_pos.x, diver_pos.y, next.z)
			if not blocked(probe_z): diver_pos.z = next.z
	return diver_pos - before

func dive_route(destination: Vector3) -> Array:
	destination.y = clampf(destination.y, MOVE_MIN_Y, MOVE_MAX_Y)
	if not _inside_basin(destination, 1.0) or blocked(destination):
		return []
	return _plan_route(destination)

func dive_cancel_content() -> void:
	_route.clear()
	_route_target_chest = {}
	_search = {}
	_search_t = 0.0

func dive_content_tick(dt: float) -> void:
	_t += dt
	depth = maxf(0.0, WATER_LEVEL - diver_pos.y)
	_sync_controller_route()
	if phase == "swim": _update_search(dt)
	_update_lamp()
	deco.update(dt, _t, diver_pos, camera)
	_update_sky(depth)
	_update_markers()
	depth_changed.emit(depth)
	zone_changed.emit(dive_zone_label())
	_air_emit_t += dt
	if _air_emit_t >= 0.12:
		_air_emit_t = 0.0
		_emit_air()

func _sync_controller_route() -> void:
	if dive_controller == null:
		return
	var route: Variant = dive_controller.get("route")
	if not (route is Array):
		route = dive_controller.get("_route")
	if route is Array:
		_route = route.duplicate()

func _update_search(dt: float) -> void:
	search_action.execute(self, dt)

func dive_camera_clip(target: Vector3, desired: Vector3, radius: float) -> Vector3:
	var distance := target.distance_to(desired)
	if distance <= 0.001:
		return desired
	var direction := (desired - target) / distance
	var steps := maxi(1, int(ceil(distance / 0.35)))
	var last := target
	for i in range(1, steps + 1):
		var sample := target + direction * (distance * float(i) / float(steps))
		if blocked(sample, radius):
			return last
		last = sample
	return desired

func dive_zone_label() -> String:
	return _zone_name()

func cancel_navigation() -> void:
	if dive_controller != null:
		dive_controller.cancel_navigation()
	else:
		dive_cancel_content()

func swim_to(destination: Vector3) -> bool:
	if dive_controller == null: return false
	var accepted: bool = dive_controller.swim_to(destination)
	_sync_controller_route()
	return accepted

func swim_to_screen(screen: Vector2) -> bool:
	return dive_controller.swim_to_screen(screen) if dive_controller != null else false

func _unhandled_input(_event: InputEvent) -> void:
	pass

func _process(delta: float) -> void:
	# Session owns surface recovery when this map is hosted transactionally.
	if not active and not has_meta("session_owned") and air != null:
		air.update(delta, 0.0, false, false)

func _update_swim(dt: float) -> void:
	if dive_controller != null:
		dive_controller.step_swim(dt)

func _update_camera(dt: float, snap: bool) -> void:
	if dive_controller != null:
		dive_controller.update_camera(dt, snap)

func _update_diver(dt: float) -> void:
	if dive_controller != null and dive_controller.has_method("update_character"):
		dive_controller.update_character(dt)


func _air_state():
	if dive_controller != null:
		var controller_air: Variant = dive_controller.get("air")
		if controller_air != null:
			return controller_air
	return air

func _controller_velocity() -> Vector3:
	if dive_controller != null:
		var value: Variant = dive_controller.get("velocity")
		if value is Vector3:
			return value
	return Vector3.ZERO

func _emit_air() -> void:
	var air_state = _air_state()
	air_changed.emit(air_state.ratio(), air_state.lamp, discovered_count(), _chests.size())


## 头灯：位置与朝向跟着相机走（右键拖拽环视时灯也跟着扫）。
## 主光和补光走 PBR；这里推送额外头灯散射项。
func _update_lamp() -> void:
	var on: bool = bool(_air_state().lamp) and phase != "surface"
	if camera == null:
		return
	var basis := camera.global_transform.basis
	var pos := camera.global_position + basis * Vector3(0.34, -0.22, -0.1)
	var dir := -basis.z
	MaterialLib.set_lamp(on, pos, dir)


func _toggle_lamp() -> void:
	var air_state = _air_state()
	air_state.lamp = not air_state.lamp
	message.emit("头灯 " + ("开" if air_state.lamp else "关"))
	_emit_air()


## 调试用：把潜点瞬间挪到某处（回归截图用）。
func debug_teleport(p: Vector3) -> void:
	if dive_controller != null:
		dive_controller.debug_teleport(p)


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
	var label := map_label if not map_label.is_empty() else _surface_zone
	if trench_collision_enabled and diver_pos.z < -78.0:
		return label + " · 北境沉船海沟" if not map_label.is_empty() else "北境沉船海沟"
	if trench_collision_enabled and diver_pos.z < -34.0:
		return label + " · 北境断层" if not map_label.is_empty() else "北境断层"
	return label if not label.is_empty() else "珊瑚礁盘"


# ---------------------------------------------------------------- 宝箱
func _build_chests() -> void:
	for spec in _chest_specs:
		var chest_id := int(spec.id) + chest_id_base
		var pos_arr: Array = spec.pos
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var g := Node3D.new()
		g.name = "Chest%d" % chest_id
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
			"id": chest_id,
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
	var lamp_on: bool = bool(_air_state().lamp) and phase == "swim"
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
	if diver_pos.distance_to(chest.pos) <= SEARCH_RADIUS:
		if dive_controller != null and dive_controller.has_method("cancel_navigation"):
			dive_controller.cancel_navigation()
		_search = chest
		_search_t = 0.0
		message.emit("搜索 " + chest.name)
		return
	var destination: Vector3 = chest.pos + Vector3(
		1.6 if chest.pos.x < 0.0 else (-1.6 if chest.pos.x > 0.0 else 0.0), 1.45, 1.1)
	var points := dive_route(destination)
	if points.is_empty():
		message.emit("前方礁石较密，先游到开阔水域")
		return
	if dive_controller == null or not dive_controller.navigate_path(points):
		message.emit("前方礁石较密，先游到开阔水域")
		return
	_route = points.duplicate()
	_route_target_chest = chest
	_search = chest
	_search_t = 0.0
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
	if bool(chest.get("opened",false)): return
	_search = {}
	_search_t = 0.0
	_route.clear()
	if dive_controller != null and dive_controller.has_method("cancel_navigation"):
		dive_controller.cancel_navigation()
	var reward: Dictionary = chest.reward
	if give_rewards.is_valid():
		if not bool(give_rewards.call(reward)):
			message.emit("背包装不下整份物资 · 宝箱仍保留，整理后再来")
			return
	else:
		# Compatibility for isolated historical content tools only.
		for key in reward.keys(): give_resource.call(str(key), int(reward[key]))
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
		"coins": return "瓶盖"
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

func toggle_lamp() -> void: _toggle_lamp()
func uses_underwater_environment() -> bool:
	return _world_env != null and _world_env.environment == _uw_env
