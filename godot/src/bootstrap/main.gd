extends Node3D
## sea Godot 版主场景。
##
## 结构（装配式：场景内容都在 tscn 里，代码只负责接线）：
##   Environment/Lights  —— 对齐网页版的灯光与雾
##   World/Environment   —— scenes/world/environment.tscn（外围沉没街区）
##   World/Zones/<区块>  —— scenes/zones/*.tscn，每个区块一个场景
##   Water               —— 原生水面着色器
##   Boat / Birds        —— 原生动画
##   Camera / HUD / 锚标 —— 原生交互
##
## 调试：`Godot --path . -- --capture` 会在 outputs/godot-preview.png 落一张图后退出。

const SailNavLib = preload("res://src/navigation/sail_nav.gd")
var navigation = preload("res://src/navigation/water_navigation.gd").new()
const WATER_LEVEL := 1.12
## 渲染后端差异（Reverse-Z 只存在于 Forward+），详见该脚本。
const RenderFlagsLib = preload("res://src/rendering/render_flags.gd")
const OrbitCamScript = preload("res://src/camera/orbit_camera.gd")
const WaterSurfaceScript = preload("res://src/rendering/water_surface.gd")
const BoatScript = preload("res://src/navigation/boat.gd")
const HUDScript = preload("res://src/ui/hud.gd")
const MarkersScript = preload("res://src/ui/landing_markers.gd")
const CharacterScript = preload("res://src/player/character.gd")
const PropsScript = preload("res://src/pickups/sea_props.gd")
const UnderwaterScene = preload("res://scenes/underwater/underwater_world.tscn")
const GatherFieldScript = preload("res://src/gathering/gather_field.gd")
const BuildFieldScript = preload("res://src/construction/build_field.gd")
const FarmFieldScript = preload("res://src/farming/farm_field.gd")
const InteractorScript = preload("res://src/interaction/interactor.gd")
const PromptScript = preload("res://src/interaction/interact_prompt.gd")
const ColorGradeScript = preload("res://src/rendering/color_grade_panel.gd")
const CameraPanelScript = preload("res://src/camera/camera_panel.gd")
const HoverCardScript = preload("res://src/interaction/hover_card.gd")
const ClickReticleScript = preload("res://src/interaction/click_reticle.gd")
const SalvagePanelScript = preload("res://src/salvage/salvage_panel.gd")
const SalvageWinchScript = preload("res://src/salvage/salvage_winch.gd")
const TradeBoardScript = preload("res://src/orders/trade_board.gd")
const OrderPanelScript = preload("res://src/orders/order_panel.gd")
const SalvageModelLib = preload("res://src/salvage/salvage.gd")
const RouteRibbonScript = preload("res://src/navigation/route_ribbon.gd")
const ItemDB = preload("res://src/inventory/item_db.gd")
const SaveGameLib = preload("res://src/save/save_game.gd")

## 自动存档间隔（秒）：太勤会在航行中反复写盘，太稀又容易丢进度。
const AUTOSAVE_SECONDS := 120.0

var cam: Camera3D
var boat: Node3D
var bird_root: Node3D
var world_root: Node3D
var environment: Node3D
var zones_root: Node3D
var hud: CanvasLayer
var markers: CanvasLayer
var water_mat: ShaderMaterial
var water_node: MeshInstance3D
var world_env: WorldEnvironment
var player: Node3D
var building = preload("res://src/building/building_service.gd").new()
var building_world: Node3D
var building_boundary: RefCounted
var building_controller: Node3D
var props: Node3D
var build_field: Node3D
var farm_field: Node3D
var dive: Node
var gather: Node3D
var interactor: Node3D
## 故意不加静态类型：ColorGradePanel 的 set_open/set_values 在 CanvasLayer 基类上不存在。
var grade = null
## 相机面板（C 键）：一键把镜头送到最近/最远，便于观察细节与全景。
var cam_panel = null
var prompt: CanvasLayer
## 悬停铭牌 / 落点环 / 打捞面板：网页版里都是「操作反馈」，这里各自一个节点。
var hover = null
var reticle: Node3D
var salvage_panel = null
var salvage_winch: Node3D
## 码头订单板：世界里的板子 + 面板。规则在 `Economy.orders`（OrderBoard）。
var trade_board: Node3D
var order_panel = null
## 航线预览（虚线 + 终点环）与水面寻路栅格（第一次开船时才建，约 10ms）。
var ribbon: Node3D
## 岸线形状缓存（判断「点的是水面还是陆地」）。
var _shore_shapes: Array = []
## 手动航行的航线刷新节流。
var _ribbon_left := 0.0
## 上一帧的相机距离（判断是否在缩放）。
var _zoom_seen := 0.0
## 点击某个可交互物后自动走过去的目标；到位后自动按住 E。
var actor_controller = preload("res://src/player/actor_controller.gd").new()
var _auto_target: Node3D:
	get: return actor_controller.auto_target
	set(value): actor_controller.auto_target = value
## 截图/回归用：把鼠标「钉」在某个屏幕位置（真实鼠标在 headless 截图里永远在 0,0）。
var _debug_mouse := ""
var _surface_lights: Array = []

var _zone_nodes: Dictionary = {}
var _walk_target: Vector3:
	get: return actor_controller.walk_target
	set(value): actor_controller.walk_target = value
var _walk_area: Node3D:
	get: return actor_controller.walk_area
	set(value): actor_controller.walk_area = value
var _walking: bool:
	get: return actor_controller.walking()
	set(value):
		if not value and actor_controller.walking():
			actor_controller.machine.change("interacting" if is_instance_valid(_auto_target) else "ashore_idle",{},true)
var _walk_path: Array[Vector3]:
	get: return actor_controller.walk_path
	set(value): actor_controller.walk_path = value
var _after_walk: Callable:
	get: return actor_controller.after_walk
	set(value): actor_controller.after_walk = value
const WALK_SPEED := 2.3

var _t := 0.0
var _ripples := PackedVector4Array()
var _press_pos := Vector2.ZERO
var _world_press := false
var _dragged := false
var _pending_pick := {}
## 拾取进度条（漂流浮木 / 鱼群）。故意不加静态类型：
## PickupProgress 的 begin/set_ratio/refresh 等方法不在 CanvasLayer 基类上。
var pickup_progress = null
## 一次海上拾取的生命周期。**这是玩法状态，不是表现状态。**
##
##   IDLE      —— 没有拾取。
##   SAILING   —— 点了浮木/鱼群，船正朝它划过去。这一段**没有任何进度**，
##                因为人还没开始捞，只是在赶路。
##   GATHERING —— 船**已经停稳**、目标在打捞范围内，正在捞。进度从这个阶段
##                的第一帧才出现，走完才结算。
##
## 为什么要分成三段：早先拿「剩余航程 / 总航程」当进度，结果船还在划、
## 人还没碰到东西，条就已经在走了 —— 玩家读到的是「我明明还没开始捞」。
## 拾取本来就是「停下来做的动作」，所以先停下、再开始、才有进度。
const PICK_PHASE_IDLE := 0
const PICK_PHASE_SAILING := 1
const PICK_PHASE_GATHERING := 2

## 打捞耗时（秒）。这是本轮新增的玩法时长（原先到站瞬收）。
##   浮木 1.2 秒：木头捆就在船舷边，弯腰一捞。
##   鱼群 1.6 秒：要下网兜一圈，比捞木头慢一点。
## 只决定「停下之后捞多久」，不影响航速、奖励数量与掉率。
const PICK_GATHER_CRATE := 1.2
const PICK_GATHER_FISH := 1.6

var _pick_phase := PICK_PHASE_IDLE
## 当前阶段剩余秒数（只有 GATHERING 用）。
var _pick_left := 0.0
## 当前这次打捞的总时长（用来算比例，避免每帧再查类型）。
var _pick_span := 1.0
## 点登陆标记时的意图：靠妥这一趟之后是否直接上岸。
## 玩家点「浅水养殖台」想要的是「过去并站上去」，不是「开过去还坐在船里」。
## 中途取消/改道必须清掉，否则下一条航线会莫名把人送下船。
var _ashore_on_arrival := false
## 存档：当前槽位路径、自动存档倒计时、是否允许自动存档（截图/自检时关掉）。
var _save_path := SaveGameLib.SLOT_PATH
var _autosave_left := AUTOSAVE_SECONDS
var _autosave_on := true
var _save_protected := false
var save_registry = preload("res://src/save/snapshot_registry.gd").new()
var world_clock = preload("res://src/time/world_clock.gd").new()
var weather_service = preload("res://src/weather/weather_service.gd").new()
var weather_view: Node2D
## 昼夜光照。时段不再靠屏幕叠加伪造，而是真的去动太阳、环境光、天空与水面反射；
## 资源里的值是它的09:00基准，见 `src/rendering/daylight_rig.gd`。
## 不写 `DaylightRig` 类型注解：新脚本首次导入前全局类名还没注册，
## 带注解会让整个主场景在这一帧解析失败。
var daylight_rig
var sleep_cycle: Node
var sleep_curtain: CanvasLayer
var _sleep_ui_layers: Array = []
var _sleep_calendar_visible := false
var _calendar_label: Label


const CozyUI = preload("res://src/ui/cozy_ui.gd")
func _cozy_node_added(node: Node) -> void:
	if node is Control and is_ancestor_of(node): CozyUI.apply_instance.call_deferred(node.get_instance_id())

func _apply_cozy_ui() -> void:
	CozyUI.apply_tree(self)

var start_screen: CanvasLayer
var title_camera = preload("res://src/camera/title_camera.gd").new()
var _title_active := false
var _title_layers: Array = []
var _title_props: Dictionary = {}
var _title_economy_ticking := true
const Scope = preload("res://src/core/play_scope.gd")
const MaterialParamGuard = preload("res://src/rendering/material_param_guard.gd")

func _ready() -> void:
	# 材质参数只存在 .tres 里，编辑器保存时可能整批被清空且不报错（详见该脚本注释）。
	# 先把缺的补回内存，任何几何都不会因此变白。
	MaterialParamGuard.enforce()
	# 水面是接近纯色的大渐变，8 位输出会出现一圈圈可见色阶（网页版有轻微噪声盖住）。
	# 开启去色带比往 shader 里掺噪点干净，也不会让静态截图变脏。
	get_viewport().use_debanding = true
	navigation.shape_query = func(): return _water_shapes() + (building_world.water_shapes() if building_world!=null else [])
	Zones.zone_enabled_query = Scope.zone_enabled
	if Scope.minimal(): navigation.allowed_area = Scope.SAIL_BOUNDS
	Zones.far_sea_query = func() -> bool: return GameState.far_sea_unlocked
	_setup_environment()
	_setup_lights()
	_setup_scene()
	_setup_gather()
	_setup_build()
	_setup_farm()
	_setup_water()
	_setup_boat()
	_setup_birds()
	_setup_camera()
	_setup_camera_panel()
	_setup_markers()
	_setup_player()
	cam.follow_subject = player
	cam.target = player.global_position + Vector3.UP*0.7
	cam.apply_pose()
	_setup_props()
	_setup_pickup_progress()
	_setup_dive()
	_setup_hud()
	_setup_shipping_box()
	_setup_prompt()
	_setup_grade()
	_setup_salvage()
	_setup_trade()
	_setup_hover()
	_setup_ribbon()
	_apply_play_scope()
	hud.presenter_sources = {"camera":cam_panel,"grade":grade,"orders":order_panel,"salvage":salvage_panel,"prompt":prompt,"hover":hover}
	_setup_actor_controller()
	_setup_calendar()
	_setup_sleep()
	_setup_building()
	_setup_save_registry()
	# 水面阻挡要遍历所有组件的三角形（五个区块合计约 0.5s）。放到一帧后再算，
	# 免得第一次点水面时忽然卡一下；算完 _shore_shapes 就固定，运行期只做查询。
	call_deferred("_warm_water_shapes")
	get_tree().node_added.connect(_cozy_node_added)
	call_deferred("_apply_cozy_ui")
	_log_render_settings()
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest"):
		_autosave_on = false
		var t: Node = load("res://tests/integration/selftest.gd").new()
		add_child(t)
		return
	# 读档必须在 --zone / --grant 这些调试参数之前：
	# 否则存档会把调试参数覆盖掉（或者反过来，看起来像「存档丢了」）。
	for a in args:
		if a.begins_with("--savepath="):
			# 槽位也要先定：--saveshot 在同一条参数表里可能排在它前面。
			_save_path = a.trim_prefix("--savepath=")
	var explicit_load := false
	for a in args:
		if a == "--load" or a.begins_with("--load="):
			explicit_load = true
			if a.begins_with("--load="): _save_path = a.trim_prefix("--load=")
	if explicit_load or (not args.has("--nosave") and not args.has("--capture") and (FileAccess.file_exists(_save_path) or FileAccess.file_exists(_save_path+".bak"))):
		var loaded := load_game()
		_save_protected = not loaded.get("ok",false)
		if _save_protected: _autosave_on = false
	if args.has("--capture"):
		_autosave_on = false
		_capture_after_settle()
	# 先处理作物选择：--farm=… 会立刻播种，晚一步就会种成默认作物。
	for a in args:
		if a.begins_with("--crop=") and Economy.farm != null:
			Economy.farm.selected_crop = a.trim_prefix("--crop=")
	for a in args:
		if a.begins_with("--zoom="):
			# 数字=米数；也可以写 near / mid / far / farthest / default / 40%
			# 这些都是「相机定位」：测试工具需要一键到最近或最远再截图。
			var spec := a.trim_prefix("--zoom=")
			if spec.is_valid_float():
				var z := float(spec)
				if z < cam.zoom_min:
					cam.zoom_min = maxf(6.0, z * 0.8)
				cam.set_distance(z)
			elif cam_panel != null:
				cam_panel.snap_to(spec)
		if a == "--panel":
			hud.toggle_panel()
		if a.begins_with("--tab="):
			hud.open_tab(a.trim_prefix("--tab="))
		if a == "--dive":
			_on_dive()
		if a == "--salvage":
			_try_salvage()
		if a.begins_with("--salvage="):
			# 调试：把打捞推进到指定阶段（drop / reel / done），截图核对用。
			_try_salvage()
			if salvage_panel != null and salvage_panel.is_open():
				_debug_salvage_to(a.trim_prefix("--salvage="))
		if a.begins_with("--mouse="):
			_debug_mouse = a.trim_prefix("--mouse=")
		if a == "--nosave":
			_autosave_on = false
		if a == "--saveshot":
			# 调试：立刻存一次并弹提示（截图核对存档反馈用）。
			# 提示给 12 秒：截图前要等画面稳定，默认 2.6 秒会先淡出，截到的是空药丸。
			_autosave_on = false
			save_game("", false, 12.0)
		if a == "--orders":
			# 调试：启动就打开订单板面板（截图核对用）。
			_open_orders(trade_board)
		if a == "--winchinfo":
			_dump_winch()
		if a.begins_with("--sailto="):
			# 调试：立刻朝某个区块出航（截图核对航线预览与绕岛用）。
			_on_destination(a.trim_prefix("--sailto="))
		if a.begins_with("--focusboat"):
			cam.target = boat.position
			cam.apply_pose()
		if a.begins_with("--autosail="):
			_autosail(a.trim_prefix("--autosail="))
		if a.begins_with("--zone="):
			_debug_teleport(a.trim_prefix("--zone="))
		if a.begins_with("--source="):
			_debug_source(a.trim_prefix("--source="))
		if a.begins_with("--uwat="):
			var xyz := a.trim_prefix("--uwat=").split(",")
			if xyz.size() == 3 and dive != null:
				dive.debug_teleport(Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])))
		if a == "--uwfreeze":
			# 诊断：把焦散/闪光冻住。帧间差异如果消失，说明「闪」来自时间动画而不是深度竞争。
			dive.freeze_time(3.0)
		if a.begins_with("--uwnear="):
			# 诊断：改水下相机近裁剪面。深度精度 ∝ far/near，near 越小越容易 z-fighting。
			if dive != null and dive.camera != null:
				dive.camera.near = float(a.trim_prefix("--uwnear="))
		if a == "--uwfacing":
			# 诊断：海底几何画成「正面绿 / 背面红」。大片红 = 绕序反了。
			if dive != null:
				dive.set_facing_debug(true)
		if a.begins_with("--uwhide="):
			# 诊断：按类别藏掉动态装饰（fish / beam / bubble / mote / ceiling / all）。
			# 用来分清「闪 / 穿模」到底来自静态几何还是这些会动的东西。
			if dive != null and dive.deco != null:
				for kind in a.trim_prefix("--uwhide=").split(","):
					dive.deco.hide_kind(kind)
		if a.begins_with("--uwair="):
			# 调试：把氧气设到某个比例（截图核对告警配色用）。
			if dive != null:
				dive.air.air = dive.air.MAX * clampf(float(a.trim_prefix("--uwair=")), 0.0, 1.0)
		if a == "--uwlamp=off":
			if dive != null:
				dive.air.lamp = false
		if a == "--uwlamp=on":
			if dive != null:
				dive.air.lamp = true
		if a.begins_with("--uwchest="):
			# 调试：直接把第 N 个宝箱标成已发现（截图核对标签用）。
			if dive != null:
				dive.debug_discover(int(a.trim_prefix("--uwchest=")))
		if a.begins_with("--orbit="):
			# 调试：--orbit=0.9,-0.2（水平/俯角增量，弧度）
			var rot := a.trim_prefix("--orbit=").split(",")
			if rot.size() == 2:
				cam.orbit(float(rot[0]), float(rot[1]))
				cam.apply_pose()
		if a.begins_with("--look="):
			# 调试：把镜头对准世界坐标（截图核对采集点/建筑细节用）。
			var look := a.trim_prefix("--look=").split(",")
			if look.size() == 3:
				cam.target = Vector3(float(look[0]), float(look[1]), float(look[2]))
				cam.apply_pose()
		if a == "--campanel" and cam_panel != null:
			# 调试：启动就打开相机面板（截图核对面板本身用）。
			cam_panel.set_open(true)
		if a == "--grade" and grade != null:
			# 调试：启动就打开滤镜面板（截图核对用）。
			grade.set_open(true)
		if a.begins_with("--grade=") and grade != null:
			# 调试：--grade=0.96,1.05,1.06,1.08（曝光,亮度,对比度,饱和度）
			var parts := a.trim_prefix("--grade=").split(",")
			if parts.size() == 4:
				grade.set_values(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
		if a == "--light" and grade != null:
			# 调试：直接翻到「光照」页（环境 + 太阳），截图核对用。
			grade.set_open(true)
			grade.set_tab("light")
		if a == "--water" and grade != null:
			# 调试：直接翻到「水面」页，省得每次按 P 再点一下。
			grade.set_open(true)
			grade.set_tab("water")
		if a == "--water-abs" and grade != null:
			# 调试：起手就切到吸收式那套水，并翻到同一页。
			grade.set_water_scheme("absorption")
			grade.set_open(true)
			grade.set_tab("water")
		if a.begins_with("--grant="):
			# 调试：给物品（截图/演示用）。格式 --grant=wood:12,parts:5
			for pair in a.trim_prefix("--grant=").split(","):
				if pair == "":
					continue
				var kv := pair.split(":")
				if kv.size() == 2:
					Economy.give({kv[0]: int(kv[1])})
		if a.begins_with("--build="):
			# 调试：直接开工某个建造点（截图核对脚手架/进度条用）。
			# 可再给 --buildp=0.45 指定进度。
			var bid := a.trim_prefix("--build=")
			Economy.give({"coins": 60, "wood": 20, "parts": 12})
			Economy.begin_site_upgrade(bid)
		if a.begins_with("--sites="):
			# 调试：把所有建造点提到同一等级（截图/演示用）。
			var lv := int(a.trim_prefix("--sites="))
			for sid in Economy.SITES.keys():
				Economy.site_levels[str(sid)] = lv
			_sync_zone_levels()
		if a == "--farm=ready" or a == "--farm=mid":
			# 调试：把所有菜箱直接推到某个生长阶段（截图/演示用）。
			if Economy.farm != null:
				Economy.give({str(Economy.farm.crop_def(Economy.farm.selected_crop).seed): 18})
				for row in Economy.farm.plot_specs():
					var pid := str(row.get("id", ""))
					Economy.farm.plant(pid, Economy.farm.selected_crop)
					Economy.farm.debug_set_growth(pid,0.0 if a == "--farm=ready" else 0.45,a != "--farm=mid")
		if a.begins_with("--buildp="):
			var ratio := clampf(float(a.trim_prefix("--buildp=")), 0.0, 0.99)
			for bid in Economy.site_work.keys():
				var w: Dictionary = Economy.site_work[bid]
				w.left = float(w.total) * (1.0 - ratio)
		if a.begins_with("--stand="):
			# 调试：把小人直接放到世界坐标（核对采集点是否真的落在甲板上）。
			var pos := a.trim_prefix("--stand=").split(",")
			if pos.size() == 3:
				player.reparent(self, true)
				player.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
				player.set_rowing(false)
				player.set_walking(false)
				actor_controller.reconcile_mode(GameState.Mode.ASHORE)
				_walking = false

	if not args.has("--skip-title") and not args.has("--capture"):
		_begin_title()


func _setup_environment() -> void:
	# 场景里有就照用，运行时一个数都不改 —— 否则在编辑器里调的灯光/环境会被代码覆盖。
	world_env = get_node_or_null("World/WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		return
	world_env = _make_world_environment()


## 兜底：场景里没有 WorldEnvironment 时（老场景 / 测试）才程序化建一份。
## 数值与 assets/materials/world_env.tres 保持一致，改一边记得改另一边。
func _make_world_environment() -> WorldEnvironment:
	var world := WorldEnvironment.new()
	var env := (load("res://assets/materials/world_env.tres") as Environment).duplicate() as Environment
	world.environment = env
	add_child(world)
	return world


## 启动时把「这次到底用了什么渲染设置」打一行出来。
## 从编辑器启动和从命令行启动曾出现观感不一致，有这行就能一眼看出跑的是不是同一份设置
## （灯值/色调映射/渲染后端/去色带/视口尺寸）。
func _log_render_settings() -> void:
	var sun := get_node_or_null("World/Lights/Sun") as DirectionalLight3D
	if sun == null:
		sun = get_node_or_null("Sun") as DirectionalLight3D
	print("[render] method=%s adapter=%s size=%s debanding=%s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
		str(get_viewport().get_visible_rect().size),
		str(get_viewport().use_debanding)])
	print("[render] tonemap=%d exposure=%.2f sun=%.2f ambient=%.2f ambient_color=%s" % [
		world_env.environment.tonemap_mode,
		world_env.environment.tonemap_exposure,
		sun.light_energy if sun != null else -1.0,
		world_env.environment.ambient_light_energy,
		world_env.environment.ambient_light_color.to_html(false)])
	print("[render] water_shader_mtime=%d" % FileAccess.get_modified_time("res://shaders/water.gdshader"))


# ---------------------------------------------------------------- 存档 / 读档

## 存档（F5）。潜水 / 打捞进行中不存：这两套状态没有比赛状态可以序列化，
## 硬存会把玩家丢在一个「面板没了但钩子还在水里」的缝里。
func save_game(path := "", quiet := false, toast_seconds := 2.6) -> Dictionary:
	if dive != null and dive.active:
		if not quiet:
			hud.toast("潜水时不能存档，先上浮")
		return {"ok": false, "reason": "潜水时不能存档"}
	if salvage_panel != null and salvage_panel.is_open():
		if not quiet:
			hud.toast("收线时不能存档，先结算这一趟")
		return {"ok": false, "reason": "打捞进行中不能存档"}
	var target := path if path != "" else _save_path
	if _save_protected and target == _save_path:
		return {"ok":false,"reason":"Original slot protected after failed load; choose another slot"}
	var res: Dictionary = SaveGameLib.write(target, self)
	_autosave_left = AUTOSAVE_SECONDS
	if not quiet:
		if res.get("ok", false):
			hud.toast("已存档 · %s · 背包 %d/%d 格" % [
				Time.get_time_string_from_system().substr(0, 5),
				Economy.inventory.slots_used(), Economy.inventory.capacity()], toast_seconds)
		else:
			hud.toast(str(res.get("reason", "存档失败")), toast_seconds)
	print("[save] %s -> %s (%d bytes)" % [target, "ok" if res.get("ok", false) else res.get("reason", ""), int(res.get("bytes", 0))])
	return res


## 读档（F9）。失败时保留当前局面，只弹提示，不把玩家踢回主菜单。
func load_game(path := "") -> Dictionary:
	if dive != null and dive.active:
		hud.toast("潜水时不能读档，先上浮")
		return {"ok": false, "reason": "潜水时不能读档"}
	var target := path if path != "" else _save_path
	var doc: Dictionary = SaveGameLib.read(target)
	if not doc.get("ok", false):
		hud.toast(str(doc.get("reason", "读档失败")))
		print("[save] load %s failed: %s" % [target, doc.get("reason", "")])
		return doc
	var res: Dictionary = SaveGameLib.restore(self, doc.get("snapshot", {}))
	if not res.get("ok",false):
		hud.toast(str(res.reason))
		return res
	_save_protected = false
	_autosave_left = AUTOSAVE_SECONDS
	# 读档后如果人已经在岸上，同样按「岸上免费补满」给满水壶。
	# 存档里可能存着 0 滴水 —— 那是旧版本卡死局留下的，不该让它继续卡住。
	if actor_controller != null and actor_controller.mode() == 0 and Economy.farm != null:
		Economy.farm.refill()
	hud.toast("已读档 · %s" % str(doc.get("snapshot", {}).get("saved_at", "上次进度")))
	print("[save] load %s ok (v%d%s)" % [target, int(doc.get("version", 0)),
		", migrated" if doc.get("migrated", false) else ""])
	return res


func _setup_lights() -> void:
	var holder := get_node_or_null("World/Lights")
	if holder != null:
		_surface_lights.clear()
		for c in holder.get_children():
			if c is DirectionalLight3D:
				_surface_lights.append(c)
		if not _surface_lights.is_empty():
			# 灯光是场景资产：位置/朝向/颜色都在 .tscn 里，运行时不再重建。
			return
	var hemi := DirectionalLight3D.new()
	_surface_lights.append(hemi)
	hemi.name = "HemisphereFill"
	hemi.light_color = Color("#a3d9cf")
	hemi.light_energy = 0.10
	hemi.shadow_enabled = false
	hemi.light_specular = 0.0
	hemi.position = Vector3(-25, 14, -18)
	add_child(hemi)
	hemi.look_at(Vector3.ZERO, Vector3.UP)

	var violet := DirectionalLight3D.new()
	_surface_lights.append(violet)
	violet.name = "VioletShadow"
	violet.light_color = Color("#8b91c6")
	violet.light_energy = 0.07
	violet.shadow_enabled = false
	violet.light_specular = 0.0
	violet.position = Vector3(-18, 20, 22)
	add_child(violet)
	violet.look_at(Vector3.ZERO, Vector3.UP)

	# 半球光的「地面色」：从下往上的冷蓝补光
	var ground := DirectionalLight3D.new()
	_surface_lights.append(ground)
	ground.name = "GroundBounce"
	ground.light_color = Color("#184fb8")
	ground.light_energy = 0.10
	ground.shadow_enabled = false
	ground.light_specular = 0.0
	ground.position = Vector3(0, -40, 0)
	add_child(ground)
	ground.look_at(Vector3.ZERO, Vector3.FORWARD)

	var sun := DirectionalLight3D.new()
	_surface_lights.append(sun)
	sun.name = "Sun"
	sun.light_color = Color("#fff1be")
	sun.light_energy = 0.58
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# 相机在 108m 外，阴影正交框要覆盖到场景，否则整个街区都落在框外。
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 0.8
	sun.position = Vector3(28, 42, -19)
	sun.light_angular_distance = 1.2
	add_child(sun)
	sun.look_at(Vector3.ZERO, Vector3.UP)
	sun.shadow_enabled = true


## 区块与环境都来自场景实例，这里只建立索引。
## 缺节点直接报错，避免"改了 tscn 忘了保存"变成静默空白画面。
func _setup_scene() -> void:
	world_root = get_node_or_null("World")
	if world_root == null:
		push_error("main.tscn 缺少 World 节点")
		return
	environment = world_root.get_node_or_null("Environment")
	zones_root = world_root.get_node_or_null("Zones")
	if zones_root == null:
		push_error("main.tscn 缺少 World/Zones")
		return
	_zone_nodes.clear()
	for child in zones_root.get_children():
		if "zone_id" in child and not str(child.zone_id).is_empty():
			_zone_nodes[child.zone_id] = child
			Zones.bind_scene(child)
	if _zone_nodes.is_empty():
		push_error("World/Zones 下没有区块场景实例")
	_sync_zone_levels()


## 建造等级 → 植物生长进度
func _sync_zone_levels() -> void:
	var site_of := {
		"zone1": "home_cabin",
		"zone2": "yokohama_station",
		"zone3": "rooftop_planter",
		"zone5": "shallow_aquaculture",
	}
	for zid in _zone_nodes.keys():
		var node: Node3D = _zone_nodes[zid]
		var site: String = site_of.get(zid, "")
		var level: int = Economy.site_level(site) if site != "" else 2
		node.set_zone_level(maxi(level, 1))


## 当前区块里，屏幕点命中的可行走区域（含落点）
func pick_walk_at(screen: Vector2) -> Dictionary:
	var zone: Node3D = _zone_nodes.get(GameState.current_zone, null)
	if zone == null:
		return {}
	var origin: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	return zone.pick_walk(origin, dir)


func _try_walk(screen: Vector2) -> bool:
	if dive.active or boat.starts_sailing():
		return false
	var hit: Dictionary = pick_walk_at(screen)
	if hit.is_empty():
		return false
	var area: Node3D = hit.area
	var point: Vector3 = hit.point
	_auto_target = null
	_cancel_pending_pick()
	interactor.auto_hold = false
	if _start_walk(area, Vector3(point.x, area.surface_y, point.z)):
		reticle.show_at(Vector3(point.x,area.surface_y,point.z))
	# 点击了地面就消费输入；不通的地面不能继续被解释成水面航行。
	return true


func _current_landing() -> Node3D:
	var zone: Node3D = _zone_nodes.get(GameState.current_zone)
	return zone.landing_point(GameState.landing_id) if zone != null else null


func _start_walk(area: Node3D, target: Vector3) -> bool:
	return actor_controller.start_walk(area,target)

## 离岸必须先沿同一块地面走回上岸点；到位后才上船并执行航行。
func _depart(action: Callable) -> bool:
	return actor_controller.depart(action)

## 点击水面：划过去。
##
## 网页版在 IDLE_ASHORE 时只允许点甲板走路，船上模式才点水面。
## 但玩家真正想做的是「我点哪儿，船就去哪儿」，所以这里合并了：
##   · 在岸上点水面 → 先上船，再划过去（船就停在泊位，不用额外操作）；
##   · 已在船上/航行中 → 直接改道（可以中途换目标）。
## 目标点必须是开阔水面：落在岸线形状里（pad 0.9m）就拒绝并提示。
func _try_sail_to(screen: Vector2) -> bool:
	if dive != null and dive.active:
		return false
	if boat == null:
		return false
	var point: Variant = _water_point(screen)
	if point == null:
		return false
	var p: Vector3 = point
	if boat.position.distance_to(p) < 1.2:
		hud.toast("就在这儿")
		return true
	var path := plan_route_to(p.x, p.z)
	if path.is_empty():
		hud.toast("这里没有可通行航路")
		return true
	_cancel_pending_pick()
	_ashore_on_arrival = false
	# 落点不再叠加第二套波纹：目标点的水纹（ribbon）从零开始散，
	# 位置和点击点重合，再放一个准星只会多出一圈相位不同的干扰。
	return _depart(func() -> void:
		actor_controller.request_mode(GameState.Mode.SAILING)
		boat.sail_to_point(p, path)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL))



## 屏幕点 → 水面上的世界坐标。没点到水面返回 null。
func _water_point(screen: Vector2) -> Variant:
	if cam == null:
		return null
	var origin: Vector3 = cam.project_ray_origin(screen)
	var d: Vector3 = cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return null
	var t := (WATER_LEVEL - origin.y) / d.y
	if t <= 0.0:
		return null
	var p := origin + d * t
	if not _is_open_water(p.x, p.z):
		return null
	return p


## 岸线形状内（外扩 0.9m）算陆地；再超出场景范围也不让划。
func _is_open_water(x: float, z: float) -> bool:
	return navigation.is_open_water(x,z)


## 水面阻挡形状的唯一入口。
##
## 组成分两段，各自有明确所有者：
##   1. 区块内：场景里每个组件自己的 BlockerSet 派生（替换模型即替换阻挡）；
##   2. 远景：shore_environment.json —— 只有烘焙几何、没有组件场景的水街区。
## 旧的 shore.json 只在这两段都为空时兜底（离线工具/测试环境可能没实例化场景）。
func _warm_water_shapes() -> void:
	_water_shapes()


func _water_shapes() -> Array:
	if not _shore_shapes.is_empty():
		return _shore_shapes
	var zones_root: Node = get_node_or_null("World/Zones")
	if zones_root != null:
		for zone in zones_root.get_children():
			if zone.has_method("rebuild_blockers"):
				zone.rebuild_blockers(WATER_LEVEL, 1.6)
				var rects: Array = zone.water_block_rects
				for r in rects:
					_shore_shapes.append({"x": (r as Rect2).get_center().x,
						"z": (r as Rect2).get_center().y,
						"hx": (r as Rect2).size.x * 0.5, "hz": (r as Rect2).size.y * 0.5,
						"round": false})
	var env: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/baked/shore_environment.json"))
	if env is Dictionary and env.has("shapes"):
		_shore_shapes.append_array(env.shapes)
	if _shore_shapes.is_empty():
		var legacy: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/baked/shore.json"))
		if legacy is Dictionary and legacy.has("shapes"):
			_shore_shapes = legacy.shapes
	return _shore_shapes


## 下船：把小人从船锚挂到世界上，落在离目标最近的可站立点
func _disembark_near(area: Node3D, _target: Vector3) -> void:
	var landing := _current_landing()
	if landing != null and landing.ground()==area:
		actor_controller.disembark.execute(actor_controller,landing.stand_position())

## 回到船上
func _board_player() -> void:
	actor_controller.board_player()

func _update_walk(delta: float) -> void:
	actor_controller.tick(delta)

func _setup_water() -> void:
	water_node = get_node_or_null("World/Water") as MeshInstance3D
	if water_node == null:
		# 兜底：老场景没有水面节点时现建一块（尺寸与场景里的 PlaneMesh 一致）。
		var plane := PlaneMesh.new()
		plane.size = Vector2(640, 640)
		var water := WaterSurfaceScript.new()
		water.name = "Water"
		water.mesh = plane
		water.position = Vector3(0, WATER_LEVEL, 0)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		water_node = water

	# 材质是 assets/materials/water.tres，可以在编辑器里调水色/雾/岸线强度。
	water_mat = water_node.material_override as ShaderMaterial
	if water_mat == null:
		water_mat = ShaderMaterial.new()
		water_mat.shader = load("res://shaders/water.gdshader")
		water_mat.render_priority = 2
		water_node.material_override = water_mat
	# 两套水都注册到这个节点：`material_override` 永远是当前生效的那份，
	# P 面板的「方案」和 `--water-abs` 都只调 `use_scheme()`。
	_ripples.resize(8)
	for i in 8:
		_ripples[i] = Vector4(0, 0, -100, 0)
	if water_node.has_method("register_scheme"):
		water_node.register_scheme("original", water_mat, false)
		var absorption: ShaderMaterial = load("res://assets/materials/water_absorption.tres") as ShaderMaterial
		if absorption != null:
			water_node.register_scheme("absorption", absorption)
		for id in water_node.schemes:
			_runtime_water_params(water_node.schemes[id], String(id))
	else:
		_runtime_water_params(water_mat)
	# 这张距离图要遍历场景几何（本机约 4 秒），是 _ready 里最长的一段；
	# 期间 HUD 还没建好，_unhandled_input 必须自己挡住输入（见那里的早退）。
	_set_shore_uniforms()
	if water_node.has_method("update_surface"):
		water_node.wake = get_node_or_null("World/BoatWake")


## 「每帧/每次启动都不同」的参数。静态外观交给资源文件，这里只处理运行时量。
## 两套材质都要写一遍：漏了的那套切过去会是一帧黑水。
## `scheme` 只影响兼容后端的发光补偿：两套水的发光量级不同，系数各拟合各的。
func _runtime_water_params(mat: ShaderMaterial, scheme := "original") -> void:
	if mat == null:
		return
	mat.set_shader_parameter("u_time", 0.0)
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	# 深度纹理的 NDC 约定随渲染后端不同，Web(gl_compatibility) 必须换算。
	mat.set_shader_parameter("u_reverse_z", RenderFlagsLib.reverse_z())
	# 水面是纯自发光材质，兼容后端对 EMISSION 的解码比 Forward+ 暗一档多。
	mat.set_shader_parameter("emission_gain", RenderFlagsLib.water_emission_gain(scheme))
	mat.set_shader_parameter("u_ripples", _ripples)
	mat.set_shader_parameter("u_ripple_count", 0)


## 当前生效的那份水面材质。切换方案后统一从这里取，别抓着 `water_mat` 不放。
func _active_water_mat() -> ShaderMaterial:
	if water_node != null and water_node.has_method("current_material"):
		var live: ShaderMaterial = water_node.current_material()
		if live != null:
			return live
	return water_mat


func _set_shore_uniforms() -> void:
	# Slice actual visible scene geometry at sea level; no hand-authored shore boxes.
	var shore_region: Rect2 = get_node("Camera").pan_bounds.grow(24.0)
	var shore_roots: Array = [_zone_nodes["zone1"],_zone_nodes["zone5"]] if Scope.minimal() else [get_node("World/Environment"),get_node("World/Zones")]
	water_node.rebuild_shoreline(shore_roots,shore_region)


func _setup_boat() -> void:
	boat = get_node_or_null("Boat") as Node3D
	if boat == null:
		boat = BoatScript.new()
		boat.name = "Boat"
		add_child(boat)
	boat.build()
	boat.segment_clear = _water_segment_clear
	if water_node.has_method("sample_surface"):
		boat.water_surface = water_node
		# 水面装饰鱼群与船、漂流物共用同一套波浪采样：鱼要跟着浪面走，
		# 沉深才是相对浪面的恒定值（否则浪峰浪谷会把鱼顶出水面或压得太深）。
		var animals := get_node_or_null("World/Environment/Animals")
		if animals != null:
			for school in animals.get_children():
				if school.has_method("set_water"):
					school.set_water(water_node)
	boat.navigation_blocked.connect(func() -> void:
		_cancel_pending_pick()
		_ashore_on_arrival = false
		actor_controller.request_mode(GameState.Mode.ON_BOAT)
		player.set_rowing(false)
		if ribbon != null:
			ribbon.clear()
		if hud != null:
			hud.toast("前方靠岸过近，请重新选择航路"))
	var l := Zones.landing("zone1", "main")
	boat.place_at(Vector3(l.boatPark[0], WATER_LEVEL, l.boatPark[2]), float(l.boatYaw))
	boat.arrived.connect(_on_boat_arrived)


func _setup_birds() -> void:
	bird_root = get_node_or_null("Birds") as Node3D
	if bird_root == null:
		bird_root = Node3D.new()
		bird_root.name = "Birds"
		bird_root.set_script(load("res://src/ambient/birds.gd"))
		add_child(bird_root)
	bird_root.build()


func _setup_camera() -> void:
	cam = get_node_or_null("Camera") as Camera3D
	if cam == null:
		cam = OrbitCamScript.new()
		cam.name = "Camera"
		add_child(cam)
		cam.setup(Vector3(-53.55, 78.12, 53.35), Vector3(0.45, 1.75, -0.65))
	else:
		# 场景里的机位（target / orbit_dir / distance）就是真源，按它铺一次。
		cam.call("refresh")


func _setup_markers() -> void:
	markers = get_node_or_null("LandingMarkers") as CanvasLayer
	if markers == null:
		markers = MarkersScript.new()
		markers.name = "LandingMarkers"
		add_child(markers)
	markers.zones = Zones
	markers.build(cam)
	markers.pointer_query=_pointer_pos
	markers.world_query = _landing_icon_world
	markers.set_highlight(GameState.current_zone)


## 靠岸图标贴在哪（每帧由 LandingMarkers 调用）。
##
## 同一个图标承担两个方向，所以它得贴在「点下去会被操作的那个东西」上：
##   · 人在岸上、船正停在这个泊位 → 点它等于上船，图标贴到船上；
##   · 其余情况（人在船上 / 船不在泊位）→ 点它等于靠岸或换泊位，留在码头边缘。
## 以前一律钉在 dockEdge，而船就停在旁边 2.5 米处，视觉上图标像压在船上：
## 于是「点船」看起来像「点了码头的图标」，动作来源说不清。
func _landing_icon_world(zone_id: String, landing_id: String, fallback: Vector3) -> Vector3:
	if GameState.mode != GameState.Mode.ASHORE or boat == null:
		return fallback
	if zone_id != GameState.current_zone or landing_id != GameState.landing_id:
		return fallback
	var l: Dictionary = Zones.landing(zone_id, landing_id)
	if l.is_empty():
		return fallback
	var park := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	# starts_sailing() 不在 Node3D 基类上：不显式写 bool，整条表达式会退化成
	# Variant，Godot 推不出类型直接报解析错误，整个 main.gd 加载不了。
	var sailing: bool = boat.starts_sailing()
	if sailing or boat.position.distance_to(park) > 1.0:
		return fallback
	# 抬到船舱上方，和 dockEdge 的 +0.55 观感一致，不被船体挡住。
	return boat.global_position + Vector3.UP * 1.35


## 点船体 = 上船。
##
## 只有「船正停在当前泊位、人还在岸上」才成立 —— 其余情况点船不该改变航路，
## 否则站在岸上点到一搜停远的船会被莫名其妙送过去。
## 动作本身复用 _select_landing 的上船分支，避免两套上船路径跑出不同结果。
func _click_boat(screen: Vector2) -> bool:
	if GameState.mode != GameState.Mode.ASHORE or boat == null:
		return false
	if not boat.pick_hull(screen, cam):
		return false
	var l: Dictionary = Zones.landing(GameState.current_zone, GameState.landing_id)
	if l.is_empty():
		return false
	var park := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	var sailing: bool = boat.starts_sailing()
	if sailing or boat.position.distance_to(park) > 1.0:
		hud.toast("船不在泊位，先用登陆点把它叫回来")
		return true
	_select_landing({"zone": GameState.current_zone, "landing": GameState.landing_id})
	return true


func _setup_player() -> void:
	# 小人挂在船锚下：船走人走，船转人转（网页版同理）。
	# 场景里已经有 Explorer 时沿用它（编辑器里摆的初始站位生效）。
	player = boat.get_node_or_null("Explorer") as Node3D
	if player == null:
		player = CharacterScript.new()
		player.name = "Explorer"
		boat.add_child(player)
		player.position = Vector3(0, 0.62, -0.30)
	player.build()
	player.scale = Vector3(1.0, 1.0, 1.0)
	player.set_rowing(true)
	# 交互探测器跟着人走：它只认世界里的 Interactable，与相机/屏幕无关。
	interactor = InteractorScript.new()
	interactor.name = "Interactor"
	interactor.active = false
	player.add_child(interactor)


## 世界里的采集点：从 assets/data/gather_spots.json 生成，坐标是与区块同一套世界坐标。
func _setup_gather() -> void:
	gather = get_node_or_null("World/Gameplay/GatherField") as Node3D
	if gather == null:
		gather = GatherFieldScript.new()
		gather.name = "GatherField"
		add_child(gather)
	gather.construction = Economy.construction
	gather.build()
	gather.collected.connect(_on_gathered)
	gather.blocked.connect(func(reason: String) -> void:
		if hud != null:
			hud.toast(reason))


## 世界里的建造牌：从 assets/data/build_sites.json 生成。
func _setup_build() -> void:
	build_field = get_node_or_null("World/Gameplay/BuildField") as Node3D
	if build_field == null:
		build_field = BuildFieldScript.new()
		build_field.name = "BuildField"
		add_child(build_field)
	build_field.construction = Economy.construction
	build_field.build()
	build_field.work_started.connect(func(_id: String, site: String, seconds: float) -> void:
		hud.toast("开工 · %s（%d 秒）" % [site, int(round(seconds))]))
	build_field.finished.connect(func(_id: String, level: int) -> void:
		_sync_zone_levels()
		hud.toast("竣工 · %s 升到 Lv.%d" % [_id_name(_id), level], 2.6))


## 世界里的菜箱：区块中独立场景负责位置，FarmField 登记，规则在 Economy.farm。
func _setup_farm() -> void:
	farm_field = get_node_or_null("World/Gameplay/FarmField") as Node3D
	if farm_field == null:
		farm_field = FarmFieldScript.new()
		farm_field.name = "FarmField"
		add_child(farm_field)
	farm_field.farm_model = Economy.farm
	farm_field.build()
	farm_field.acted.connect(_on_farm_acted)
	for plot in farm_field.plots:
		plot.use_action_menu = true
		plot.interaction_requested.connect(_open_plot_options)
	if Economy.farm != null and not Economy.farm.became_ready.is_connected(_on_crop_ready):
		Economy.farm.became_ready.connect(_on_crop_ready)


func _on_farm_acted(plot_id: String, event: String, payload: Dictionary) -> void:
	match event:
		"planted":
			hud.toast("播下 · %s（需 %d 个浇水日）" % [
				str(payload.get("name", "")), int(payload.get("days", 0))])
		"watered":
			hud.toast("浇水 · %s" % str(payload.get("name", "")))
		"harvested":
			var reward: Dictionary = payload.get("reward", {})
			var bits: Array = []
			for id in reward.keys():
				var item: Dictionary = ItemDB.get_item(str(id))
				bits.append("%s×%d" % [str(item.get("icon", "•")), int(reward[id])])
			hud.toast("收获 · %s  %s" % [str(payload.get("name", "")), " ".join(bits)], 2.2)
		_:
			pass


func _on_crop_ready(plot_id: String, crop_id: String) -> void:
	# 只在玩家当前所在区块提示，别在别的岛上喊「菜熟了」。
	var zone := ""
	if farm_field != null:
		var node: Node3D = farm_field.find(plot_id)
		if node != null:
			zone = str(node.zone_id)
	if zone != "" and zone != GameState.current_zone:
		return
	var name := str(Economy.farm.crop_def(crop_id).get("name", crop_id))
	hud.toast("熟了 · %s（%s）" % [name, _plot_name(plot_id)], 2.4)


func _plot_name(plot_id: String) -> String:
	var spec: Dictionary = Economy.farm.spec(plot_id) if Economy.farm != null else {}
	return str(spec.get("name", plot_id))


func _id_name(id: String) -> String:
	var spec: Dictionary = Economy.SITES.get(id, {})
	return str(spec.get("name", id))


func _setup_prompt() -> void:
	prompt = get_node_or_null("InteractPrompt") as CanvasLayer
	if prompt == null:
		prompt = PromptScript.new()
		prompt.name = "InteractPrompt"
		add_child(prompt)
	prompt.enabled = false
	prompt.action_requested.connect(func() -> void:
		if interactor.target != null: _approach(interactor.target))
	if interactor != null:
		interactor.action_started.connect(func(spot: Node3D) -> void:
			if spot.is_in_group("farm_plots") and spot.verb == "收获": player.play_farm_action(spot.verb))
		interactor.blocked.connect(func(reason: String) -> void:
			_auto_target = null
			interactor.auto_hold = false
			hud.toast(reason)
			if prompt != null:
				prompt.flash_blocked(reason))
		# 自动接近的流程里，动作一旦成功就不要再按着 E（否则会连采同一个点）。
		interactor.completed.connect(func(_spot: Node3D, _reward: Dictionary) -> void:
			prompt.celebrate()
			_auto_target = null
			interactor.auto_hold = false)


## ---- 打捞绞盘 ---------------------------------------------------------------

## 打捞台立在 zone1 打捞浮台靠水的一侧，悬臂朝外伸到水面。
## 位置从 zones.json 的 walk 矩形推出来（西边缘内缩 0.7m、z 取中点），不在这里写死坐标。
func _salvage_winch_spot() -> Vector3:
	for w in Zones.get_zone("zone1").get("walk", []):
		if str(w.get("id", "")) != "zone1_salvage":
			continue
		var rects: Array = w.get("rects", [])
		if rects.is_empty():
			continue
		var r: Array = rects[0]
		var x := float(r[0]) + 0.7
		var z := (float(r[2]) + float(r[3])) * 0.5
		return Vector3(x, float(w.get("y", 1.33)), z)
	return Vector3(-14.5, 1.33, 12.9)


func _setup_salvage() -> void:
	if salvage_winch == null:
		salvage_winch = get_node_or_null("SalvageWinch")
	if salvage_winch == null:
		var spot := _salvage_winch_spot()
		salvage_winch = SalvageWinchScript.new()
		salvage_winch.setup({
			"id": "salvage_winch", "zone": "zone1", "name": "绞盘打捞台",
			"x": spot.x, "y": spot.y, "z": spot.z, "yaw": PI * 0.5,
		})
		add_child(salvage_winch)
	salvage_winch.rewards = Economy.salvage
	salvage_winch.opened.connect(_open_salvage)

	salvage_panel = get_node_or_null("SalvagePanel")
	if salvage_panel == null:
		salvage_panel = SalvagePanelScript.new()
		salvage_panel.name = "SalvagePanel"
		add_child(salvage_panel)
	salvage_panel.finished.connect(_on_salvage_finished)


## 码头订单板：世界里的板子（位置由 tools/place_trade_board.py 求解）+ 面板。
func _setup_trade() -> void:
	trade_board = get_node_or_null("TradeBoard")
	if trade_board == null:
		var data: Dictionary = _load_json("res://assets/data/trade_board.json")
		var rows: Array = data.get("boards", [])
		if rows.is_empty():
			push_error("trade_board.json 里没有板子")
		else:
			trade_board = TradeBoardScript.new()
			trade_board.setup(rows[0])
			add_child(trade_board)
	if trade_board != null:
		trade_board.opened.connect(_open_orders)

	if trade_board != null: trade_board.order_model = Economy.orders
	order_panel = get_node_or_null("OrderPanel")
	if order_panel == null:
		order_panel = OrderPanelScript.new()
		order_panel.name = "OrderPanel"
		order_panel.inventory = Economy.inventory
		add_child(order_panel)
	order_panel.inventory = Economy.inventory
	order_panel.model = Economy.orders
	order_panel.fulfill_requested.connect(_on_order_fulfill)
	order_panel.reroll_requested.connect(_on_order_reroll)
	if Economy.orders != null:
		Economy.orders.fulfilled.connect(_on_order_fulfilled)
		Economy.orders.changed.connect(func() -> void:
			if order_panel != null and order_panel.is_open():
				order_panel.refresh())


func _open_orders(_board: Node3D) -> void:
	if Scope.minimal():
		hud.open_tab("shop")
		return
	if order_panel == null or order_panel.is_open():
		return
	order_panel.set_open(true)
	_auto_target = null
	if interactor != null:
		interactor.auto_hold = false


func _on_order_fulfill(uid: String) -> void:
	if Scope.minimal(): return
	if Economy.orders == null:
		return
	var res: Dictionary = Economy.orders.fulfill(uid)
	if not res.get("ok", false):
		order_panel.note(str(res.get("reason", "交付失败")))
		return
	order_panel.refresh()


func _on_order_reroll() -> void:
	if Scope.minimal(): return
	if Economy.orders == null:
		return
	var res: Dictionary = Economy.orders.reroll()
	if not res.get("ok", false):
		order_panel.note(str(res.get("reason", "换不了")))
		return
	order_panel.refresh()
	order_panel.note("换了一批新单子")


func _on_order_fulfilled(order: Dictionary, reward: Dictionary) -> void:
	var parts: Array = []
	for k in reward.keys():
		parts.append("%s×%d" % [ItemDB.label(str(k)), int(reward[k])])
	hud.toast("交单 · %s · %s" % [str(order.get("customer", "")), "  ".join(parts)], 3.2)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("找不到数据表：%s" % path)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


func _open_salvage(_winch: Node3D) -> void:
	if Scope.minimal(): return
	if salvage_panel == null or salvage_panel.is_open():
		return
	salvage_panel.begin()
	_auto_target = null
	if interactor != null:
		interactor.auto_hold = false
	hud.toast("下钩：按 E 停住钩子，再按住 E 收线")


func _on_salvage_finished(haul: Dictionary, ok: bool) -> void:
	if not ok and haul.is_empty():
		return  # 中途 ESC 退出：不结算、不进冷却，也不吓人
	if not ok:
		# 断线有代价：短冷却，但不至于让人干等（重试本身就是玩法的一部分）。
		Economy.salvage_ready_at = Time.get_ticks_msec() / 1000.0 + 8.0
		if salvage_winch != null:
			salvage_winch.play_snap()
		hud.toast("这一趟断了线 · 8 秒后才能再下钩")
		return
	var now := Time.get_ticks_msec() / 1000.0
	var got: Dictionary = Economy.commit_salvage(now, haul)
	if got.is_empty():
		hud.toast("材料仓满了，先把背包腾一腾")
		return
	if salvage_winch != null:
		salvage_winch.play_reel()
	var parts := PackedStringArray()
	for k in got.keys():
		parts.append("%s +%d" % [ItemDB.label(str(k)), int(got[k])])
	hud.toast("打捞上来 · " + "  ".join(parts))


## ---- 航行目标水纹 / 水面寻路 -------------------------------------------------

## 目标点只留一圈荡开的水纹，不再铺航路虚线（2026-10-28 按用户要求去掉）。
## 水面引用在这里注入，波纹才能贴着真实浪面走。
func _setup_ribbon() -> void:
	ribbon = get_node_or_null("RouteRibbon")
	if ribbon == null:
		ribbon = RouteRibbonScript.new()
		ribbon.name = "RouteRibbon"
		add_child(ribbon)
	ribbon.water = water_node


## 岸线栅格按需建一次：25 个形状 ≈ 268×265 格，一次十几毫秒，不值得每帧算。
##
## 用 `SailNavLib.create_nav_grid()`（src/navigation 中的正式算法）建矩形障碍，
## 再手工把圆形轮廓（圆弧农场塔、一座圆岛）补进 blocked —— 那个接口只吃 Rect2，
## 用外接正方形会把旁边 3m 的水道也堵死。
func nav_grid() -> Dictionary:
	return navigation.nav_grid()


## 巡航沿用原岸线网格；首尾或窄水道不能通过时，用精确水域网格重规划。
## 失败明确返回空路径，禁止穿岸直线兜底。
func plan_route_to(x: float, z: float) -> Array:
	return navigation.plan_route_to(Vector2(boat.position.x,boat.position.z),x,z)

func _valid_water_route(path: Variant) -> bool:
	return navigation.valid_route(path)

func _water_segment_clear(a: Vector2, b: Vector2) -> bool:
	return navigation.segment_clear(a,b)


## 出航统一入口：规划 → 交给船 → 铺航线预览。
## `then_ashore` 让「点登陆标记」这条链路一次走完：航行 → 靠妥 → 上岸。
func _sail_to_landing(l: Dictionary, zone_id: String, landing_id: String, then_ashore := false) -> bool:
	if l.is_empty():
		return false
	var goal := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	var path := plan_route_to(goal.x, goal.z)
	if path.is_empty():
		hud.toast("无法到达该泊位")
		return false
	_cancel_pending_pick()
	_ashore_on_arrival = then_ashore
	return _depart(func() -> void:
		boat.sail_to(goal, float(l.boatYaw), zone_id, landing_id, path)
		actor_controller.request_mode(GameState.Mode.SAILING)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		markers.set_highlight(zone_id))


## ---- 悬停铭牌 / 落点环 -------------------------------------------------------

## 落点环仍服务岸上走位（那里没有水面可荡）。
## 海面点击的反馈由 RouteRibbon 的终点水纹承担，见 _setup_ribbon。
func _setup_hover() -> void:
	reticle = get_node_or_null("ClickReticle")
	if reticle == null:
		reticle = ClickReticleScript.new()
		reticle.name = "ClickReticle"
		add_child(reticle)

	hover = get_node_or_null("HoverCard")
	if hover == null:
		hover = HoverCardScript.new()
		hover.name = "HoverCard"
		add_child(hover)
	hover.camera = cam
	hover.markers = markers
	hover.props = props
	# 走不到的目标不给悬停图标、不改指针 —— 有图标就等于「这里能点」，
	# 玩家点了却弹不出东西，只会觉得界面坏了。判定与点击提示共用同一个函数。
	hover.reach_gate = _land_reach_reason


## 悬停与自动交互每帧更新：面板打开 / 潜水时整体关掉，避免抢指针。
func _update_pointer_ui() -> void:
	if hover == null:
		return
	if markers != null: markers.visible = not hud.is_panel_open() and not hud.menu.active and not hud.menu.external_open()
	var panel_open: bool = (hud != null and hud.is_modal()) \
		or (hud != null and hud.world_actions.is_open()) \
		or (salvage_panel != null and salvage_panel.is_open()) \
		or (order_panel != null and order_panel.is_open()) \
		or (cam_panel != null and cam_panel.is_open()) \
		or (grade != null and grade.visible)
	hover.enabled = not dive.active and not panel_open \
		and (cam == null or not cam.panning)
	hover.current_zone = GameState.current_zone
	if hover.enabled:
		hover.update_hover(_pointer_pos())
	elif cam == null or not cam.panning:
		# 拖动镜头时别清指针：相机会把指针设成「抓取」，这里一清就抖成箭头。
		hover.clear()



## 调试：把打捞小游戏推进到某个阶段。只在截图/回归里用，不影响真实输入。
func _debug_salvage_to(stage: String) -> void:
	var m = salvage_panel.model
	if m == null:
		return
	if stage == "reel" or stage == "done":
		# Phase 从 IDLE=0 开始，DROP 是 1；按值写容易漏，这里用常量。
		while m.phase == SalvageModelLib.Phase.DROP and m.depth < 1.0:
			m.update(0.05, false)
		m.press()
		var guard := 0
		var target := 0.55 if stage == "reel" else 1.0
		while m.progress < target and not m.is_finished() and guard < 4000:
			m.update(0.016, m.tension < 0.60)
			guard += 1
		salvage_panel._sync()


## 调试：打印绞盘的实际世界包围盒（核对尺寸/落点用）。
func _dump_winch() -> void:
	var box := AABB()
	var first := true
	var stack: Array = [salvage_winch]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			print("[winch] ", mi.get_path(), " size=", b.size, " pos=", b.position)
			box = b if first else box.merge(b)
			first = false
		stack.append_array(n.get_children())
	print("[winch] total ", box.position, " size=", box.size,
		" node=", salvage_winch.position, " scale=", salvage_winch.scale)


## 缩放时给一句「缩放 62%」的反馈；手动航行时把已走过的航段从虚线上裁掉。
func _update_camera_feedback(delta: float) -> void:
	if cam != null and hud != null:
		hud.set_follow_locked(cam.follow_enabled)
		var d: float = cam.distance
		if absf(d - _zoom_seen) > maxf(0.4, _zoom_seen * 0.004):
			_zoom_seen = d
			hud.note_zoom(cam.zoom_ratio())
	if boat != null and boat.starts_sailing() and boat.manual and ribbon != null:
		_ribbon_left -= delta
		if _ribbon_left <= 0.0:
			_ribbon_left = 0.30
			ribbon.show_route(boat.remaining_route(), WATER_LEVEL)


## 鼠标位置：正常取真实指针；调试参数可以钉在绞盘或指定像素上。
func _pointer_pos() -> Vector2:
	if _debug_mouse.is_empty():
		return get_viewport().get_mouse_position()
	if _debug_mouse == "winch" and salvage_winch != null:
		return cam.unproject_position(salvage_winch.global_position + Vector3.UP * 0.75)
	var parts := _debug_mouse.split(",")
	if parts.size() >= 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return get_viewport().get_mouse_position()


## 点击「走过去」，到位后由 _update_pointer_ui 打开自动长按。
func _approach(node: Node3D) -> bool:
	if not actor_controller.approach(node): return false
	_cancel_pending_pick()
	if reticle != null: reticle.show_at(_walk_target)
	return true

## 点在悬停目标上：按类型分派（可交互物走过去 / 上岸桩开船 / 漂流物划过去）。
func _activate_hover(hit: Dictionary) -> bool:
	match str(hit.get("type", "")):
		"spot":
			# 把命中点的屏幕位置一并带过去：目标远到投影出屏时，
			# 气泡靠它钉在玩家点下去的地方，而不是「开一帧就关」。
			var at: Variant = hit.get("screen", Vector2.INF)
			_open_spot_bubbles(hit.node, at if at is Vector2 else Vector2.INF)
			return true
		"landing":
			_select_landing(hit.hit)
			return true
		"prop":
			_handle_prop_click(hit.hit)
			return true
	return false


## 滤镜面板（P 键开关）。场景里已经挂好时直接复用，别重复加一层。
## 相机面板：调试/观察用，不影响玩法。场景里挂好就复用。
func _setup_camera_panel() -> void:
	cam_panel = get_node_or_null("CameraPanel") as CanvasLayer
	if cam_panel == null:
		cam_panel = CameraPanelScript.new()
		cam_panel.name = "CameraPanel"
		add_child(cam_panel)
	cam_panel.bind_camera(cam)


func _setup_grade() -> void:
	grade = get_node_or_null("ColorGrade") as CanvasLayer
	if grade == null:
		grade = ColorGradeScript.new()
		grade.name = "ColorGrade"
		add_child(grade)


func _setup_props() -> void:
	props = get_node_or_null("World/Gameplay/SeaProps") as Node3D
	if props == null:
		props = PropsScript.new()
		props.name = "SeaProps"
		add_child(props)
	props.water_surface = water_node
	props.water_point_clear = func(p: Vector2) -> bool: return SailNavLib.is_free(nav_grid(), p.x, p.y)
	props.zones = Zones
	props.give_resource = Economy.add_resource
	props.can_receive = Economy.inventory.can_add
	props.blocked.connect(func(reason: String): hud.toast(reason))
	if Scope.minimal():
		props.spawn_area = Scope.HOME_WATER.grow(-3)
		props.crate_count = 6
		props.planks_only = true
		props.school_count = 4
	props.build()
	props.collected.connect(_on_crate_collected)
	props.fish_collected.connect(_on_fish_collected)


## 海上拾取的进度条：角色头顶的一条细进度，表示「船还有多远到货」。
##
## 单独一个模块（src/pickups/pickup_progress.gd），主场景只负责接线：
## 什么时候开始、进度是多少、什么时候收。
##
## 挂角色而不是挂目标：镜头跟着角色走，目标一偏出取景框条就一起消失，
## 玩家在最需要看进度的那几秒反而什么都没有。角色永远在画面里。
func _setup_pickup_progress() -> void:
	pickup_progress = preload("res://src/pickups/pickup_progress.gd").new()
	pickup_progress.name = "PickupProgress"
	add_child(pickup_progress)
	pickup_progress.camera = cam
	pickup_progress.subject = player


## 海底是独立地图：整棵 UnderwaterWorld 一直挂在主线里，平时隐藏，
## 下潜时切相机 + 换 Environment（海面物体整体隐藏）。
func _setup_dive() -> void:
	dive = get_node_or_null("Underwater")
	if dive == null:
		dive = UnderwaterScene.instantiate()
		dive.name = "Underwater"
		add_child(dive)
	# 海面灯光也要一起藏：海底有自己的一整套灯，混着会整体过曝。
	var hide_on_dive: Array = [world_root, water_node, boat, bird_root, markers, props, player]
	hide_on_dive.append_array(_surface_lights)
	dive.give_resource = Economy.add_resource
	dive.setup(hide_on_dive, world_env)
	dive.depth_changed.connect(_on_depth_changed)
	dive.zone_changed.connect(_on_dive_zone)
	dive.air_changed.connect(_on_dive_air)
	dive.message.connect(func(text: String) -> void: hud.toast(text))
	dive.exited.connect(_on_dive_exited)


func _setup_hud() -> void:
	hud = get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		hud = HUDScript.new()
		hud.economy = Economy
		hud.zones = Zones
		hud.game_state = GameState
		add_child(hud)
	hud.economy = Economy
	hud.zones = Zones
	hud.game_state = GameState
	hud.bind_models()
	hud.command_requested.connect(_on_click_command)
	hud.destination_pressed.connect(_on_destination)
	hud.dive_pressed.connect(_on_dive)
	hud.site_focus_requested.connect(_on_focus_site)
	hud.plot_focus_requested.connect(_on_focus_plot)
	hud.rest_requested.connect(_rest_for_day)
	hud.facility_build_requested.connect(_on_build_facility)
	hud.ship_upgrade_requested.connect(_on_upgrade_ship)
	# 背包满时只提示一次，连着刷同一句会盖住别的反馈。
	Economy.overflow.connect(func(id: String, amount: int) -> void:
		hud.toast("背包已满 · %s×%d 没能装下" % [ItemDB.label(id), amount], 3.0))


## 所有按钮和快捷键共享命令入口，取消不留下待执行动作。
func _cancel_action() -> void:
	if hud != null: hud.world_actions.close(true)
	actor_controller.cancel()
	_cancel_pending_pick()
	_ashore_on_arrival = false
	if dive.active: dive.cancel_navigation()
	if ribbon != null: ribbon.clear()
	hud.toast("已停止，可点击新的目标")

func _on_click_command(command: String) -> void:
	if _title_active or (sleep_cycle != null and sleep_cycle.busy): return
	if building_controller!=null and building_controller.active and command not in ["craft","save"]: building_controller.close()
	if not Scope.command_enabled(command): return
	if command != "cancel" and (salvage_panel.is_open() or order_panel.is_open()):
		hud.toast("请先关闭当前操作面板")
		return
	match command:
		"craft":
			cam_panel.set_open(false);grade.set_open(false);building_controller.open()
		"follow":
			cam.resume_follow()
			hud.toast("镜头跟随角色")
		"close":
			if hud.is_panel_open(): hud.toggle_panel()
		"bag", "notes", "plant", "build", "storage", "shop", "shipping":
			_auto_target = null
			interactor.auto_hold = false
			cam_panel.set_open(false)
			grade.set_open(false)
			hud.open_tab(command)
		"cancel":
			if salvage_panel.is_open(): salvage_panel.cancel()
			elif order_panel.is_open(): order_panel.set_open(false)
			else: _cancel_action()
		"save": save_game()
		"load":
			_cancel_action()
			load_game()
		"camera":
			if hud.is_panel_open(): hud.toggle_panel()
			grade.set_open(false)
			cam_panel.set_open(not cam_panel.is_open())
		"grade":
			if hud.is_panel_open(): hud.toggle_panel()
			cam_panel.set_open(false)
			grade.set_open(not grade.visible)
		"rise": dive.swim_to(dive.diver_pos + Vector3.UP*3.0)
		"descend": dive.swim_to(dive.diver_pos + Vector3.DOWN*3.0)
		"lamp": dive.toggle_lamp()


func _on_destination(zone_id: String) -> void:
	if _title_active: return
	if dive.active:
		hud.toast("请先上浮再选择航行目的地")
		return
	if not Zones.is_unlocked(zone_id):
		hud.toast("远海街町需要先升级船只")
		return
	if not _sail_to_landing(Zones.landing(zone_id, "main"), zone_id, "main"):
		return


func _on_boat_arrived(zone_id: String, landing_id: String) -> void:
	if ribbon != null:
		ribbon.clear()
	# 手动点水面划过来的：没有区块可切，停在原地继续等指令。
	if zone_id == "":
		player.set_rowing(false)
		actor_controller.request_mode(GameState.Mode.ON_BOAT)
		_ashore_on_arrival = false
		if not Scope.minimal(): hud.toast("已停船")
		return
	GameState.landing_id = landing_id
	GameState.enter_zone(zone_id)
	actor_controller.request_mode(GameState.Mode.ON_BOAT)
	markers.set_highlight(zone_id)
	player.set_rowing(false)
	var ashore := _ashore_on_arrival
	_ashore_on_arrival = false
	if ashore:
		# 玩家点的是登陆标记，不是泊位锚点：靠妥即上岸。
		if _step_ashore():
			hud.toast("靠岸 · " + Zones.label(zone_id))
			return
	if not Scope.minimal(): hud.toast("抵达 · " + Zones.label(zone_id))


## 按下必须发生在世界里；拖出去再拖回来也仍是拖动。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_world_press = false
		_dragged = false
	elif event is InputEventMouseMotion and _world_press:
		_dragged = _dragged or _press_pos.distance_to(event.position) >= 11.0

func _unhandled_input(event: InputEvent) -> void:
	if _title_active: return
	# 启动早期（场景/水面还在初始化）输入可能比 HUD 先到：这时没有任何可交互界面，
	# 直接放行，别把点击/按键丢给一个还不存在的节点。
	if hud == null or not is_instance_valid(hud):
		return
	# 潜水时输入归海底世界（游动 / 环视 / 宝箱），海面这边一律不响应。
	if dive != null and dive.active:
		return
	# 打捞面板打开时，E / 空格 / ESC 都归它。
	if salvage_panel != null and salvage_panel.is_open():
		return
	# 订单面板同理：它自己按 ESC 关，别的键点击都不该穿透到世界里。
	if order_panel != null and order_panel.is_open():
		return
	if building_controller!=null and building_controller.handle_input(event):
		get_viewport().set_input_as_handled();return
	# Tab / B 打开背包（建造也在这个面板里，切换页签即可）。
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		# F5 存档 / F9 读档：不占面板，随手就能按（面板开着也照样能用）。
		if key == KEY_F5:
			save_game()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F9:
			load_game()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_TAB or key == KEY_B:
			hud.toggle_panel()
			get_viewport().set_input_as_handled()
			return
		# ESC：先关面板，再取消「自动走过去」，与网页版 closeActionMenus 的层级一致。
		if key == KEY_ESCAPE:
			if hud.is_panel_open(): hud.toggle_panel()
			else: _cancel_action()
			get_viewport().set_input_as_handled()
			return
	if hud.is_panel_open():
		return
	if cam_panel != null and cam_panel.is_open():
		return
	if grade != null and grade.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_pos = mb.position
			_world_press = true
		elif _world_press and not _dragged and _press_pos.distance_to(mb.position) < 11.0:
			_world_press = false
			if dive.active:
				return
			# 悬停命中的目标优先：点图标 → 小人自己走过去，到位自动动手。
			if hover != null:
				# 在释放点重新命中，避免读取拖动前的旧目标。
				if _activate_hover(hover._pick(mb.position)):
					return
				# 走不到的可交互物：不弹菜单，只说明为什么过不去。
				# 这不是「多此一举的提示」—— 少了它，玩家点了远处箱子什么都没发生。
				var barred: Dictionary = hover._pick(mb.position, true)
				if str(barred.get("type", "")) == "spot":
					var why := str(barred.get("barred", ""))
					if why != "":
						hud.toast(why)
						return
			var prop: Dictionary = props.pick(mb.position, cam)
			if not prop.is_empty():
				_handle_prop_click(prop)
				return
			var hit: Dictionary = markers.pick(mb.position)
			if not hit.is_empty():
				_select_landing(hit)
				return
			# 点船体也上船：图标只覆盖一小圈，船比它大得多，
			# 点船头船尾都该算「要上这条船」。放在图标之后，
			# 让精确点图标的行为保持优先。
			if _click_boat(mb.position):
				return
			# 先看点在不在甲板上（走），不在就当作「点水面划船」。
			if _try_walk(mb.position):
				return
			if _try_sail_to(mb.position):
				return


## 点登陆标记：在船与岸之间来回。
##
## 一个标记承担两个方向，用「角色现在在哪」决定，而不是再分两个按钮：
##   · 已经在岸上 → 走回泊位、上船（"坐在船上"）；
##   · 已经在船上且就在这个泊位 → 上岸；
##   · 船还没停到这个泊位（含别的区块）→ 开过去，**靠妥后自动上岸**。
## 第三种是本次改动的重点：以前开到就跑完了，玩家还得再点一次标记。
func _select_landing(hit: Dictionary) -> void:
	var zone_id: String = hit.zone
	var landing_id: String = hit.landing
	var selected: Dictionary = Zones.landing(zone_id,landing_id)
	if selected.is_empty(): return
	var park := Vector3(float(selected.boatPark[0]),WATER_LEVEL,float(selected.boatPark[2]))
	# 显式写 bool：boat 声明为 Node3D，starts_sailing() 不在基类上，
	# 这里一旦用 `:=`，整条表达式就是 Variant，Godot 推不出类型会直接报解析错误，
	# 而 main.gd 解析失败会让整个游戏加载不了。2026-10-28 改鲸的场景后重导入时踩到过。
	var docked: bool = zone_id == GameState.current_zone and landing_id == GameState.landing_id \
		and not boat.starts_sailing() and boat.position.distance_to(park) < 1.0
	if docked:
		if GameState.mode == GameState.Mode.ASHORE:
			_ashore_on_arrival = false
			_depart(func() -> void: hud.toast("上船了 · 点水面或远方的登陆点出发"))
		else:
			_ashore_on_arrival = false
			_step_ashore()
		return
	if not Zones.is_unlocked(zone_id):
		hud.toast("远海街町需要先升级船只")
		return
	var l := Zones.landing(zone_id, landing_id)
	if not _sail_to_landing(l, zone_id, landing_id, true):
		return
	# 同上：目标水纹由 ribbon 负责，不再额外放一圈落点环。


## 靠泊后上岸的唯一入口：站在泊位上走过去，到位即 ashore_idle。
func _step_ashore() -> bool:
	var landing := _current_landing()
	if landing == null: return false
	if not _start_walk(landing.ground(), landing.stand_position()):
		hud.toast("这里上不了岸，请换个登陆点")
		return false
	if reticle != null: reticle.show_at(landing.stand_position())
	return true


func _handle_prop_click(prop: Dictionary) -> void:
	_ashore_on_arrival = false
	if GameState.mode == GameState.Mode.ASHORE:
		_depart(func() -> void: _handle_prop_click(prop))
		return
	if prop.type == "fish":
		var school: Dictionary = prop.item
		var target: Vector3 = school.base
		var goal := target + Vector3(2.1, 0, 0)
		var path := plan_route_to(goal.x, goal.z)
		if path.is_empty():
			# Shore-adjacent fish may have no room on their right; their own water point remains legal.
			goal = target
			path = plan_route_to(goal.x,goal.z)
		if path.is_empty():
			hud.toast("无法到达鱼群")
			return
		boat.sail_to(goal, boat.rotation.y, GameState.current_zone, GameState.landing_id, path)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		_begin_pick_sail({"type": "fish", "item": school})
	else:
		var crate: Dictionary = prop.item
		var target2: Vector3 = crate.base
		var goal2 := target2 + Vector3(1.4, 0, 0)
		var path2 := plan_route_to(goal2.x, goal2.z)
		if path2.is_empty():
			goal2=target2
			path2=plan_route_to(goal2.x,goal2.z)
		if path2.is_empty():
			hud.toast("无法到达漂流物")
			return
		boat.sail_to(goal2, boat.rotation.y, GameState.current_zone, GameState.landing_id, path2)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		_begin_pick_sail({"type": "crate", "item": crate})
	actor_controller.request_mode(GameState.Mode.SAILING)


## 点了浮木/鱼群：进入「航行」阶段。
##
## 这个阶段**不显示任何进度**：船还没到，人也还没开始捞。
## 条只是被重置成隐藏状态（清掉上一轮可能残留的满格）。
func _begin_pick_sail(pick: Dictionary) -> void:
	_pending_pick = pick
	_pick_phase = PICK_PHASE_SAILING
	_pick_left = 0.0
	if pickup_progress != null:
		pickup_progress.begin()
		pickup_progress.hide_bar()


## 船停稳且目标够得着：进入「打捞」阶段。
##
## 这里才是「开始拾取」的时刻 —— 进度条从这一帧起出现在角色头顶，
## 从 0 走到 1，走满才结算。时长按目标类型给（浮木 1.2 / 鱼群 1.6 秒）。
func _begin_pick_gather() -> void:
	_pick_phase = PICK_PHASE_GATHERING
	var is_fish: bool = str(_pending_pick.get("type", "")) == "fish"
	_pick_span = PICK_GATHER_FISH if is_fish else PICK_GATHER_CRATE
	_pick_left = _pick_span
	if pickup_progress != null:
		pickup_progress.begin()
		pickup_progress.set_ratio(0.0)
		pickup_progress.refresh()


## 打捞走完：真正结算（记账、移除目标、补货计时都在 props 里）。
##
## 只有结算成功才让条停在满格；背包满等失败情况直接收条，
## 不然玩家会看到一条满格的条却什么都没进包。
func _finish_pick() -> void:
	var pick: Dictionary = _pending_pick
	_pending_pick = {}
	_pick_phase = PICK_PHASE_IDLE
	_pick_left = 0.0
	var got := false
	if props != null:
		if str(pick.get("type", "")) == "fish":
			got = props.collect_fish(pick.item)
		else:
			got = not props.collect_crate(pick.item).is_empty()
	if pickup_progress != null:
		if got:
			pickup_progress.complete()
		else:
			pickup_progress.clear()


## 船停稳之后，目标是否真的在打捞范围内。
##
## 必须查这一下：船半路被岸线挡住也会「停」，那时候离目标还有几十米，
## 不校验就会在原地对着空气捞 1.2 秒，然后什么都没收到。
## 浮木沿用结算原本的 2.2 米，鱼群用 props 自己的捕捞半径。
func _pick_in_reach() -> bool:
	if props == null: return false
	var item: Dictionary = _pending_pick.get("item", {})
	var root = item.get("root")
	if not (root is Node3D) or not is_instance_valid(root): return false
	var d: float = Vector2(root.position.x - boat.position.x,
		root.position.z - boat.position.z).length()
	var reach: float = props.FISH_PICKUP_RADIUS \
		if str(_pending_pick.get("type", "")) == "fish" else 2.2
	return d <= reach


## 取消一次待拾取：清掉待办、退回空闲并收起进度条。
##
## 进度条必须跟着一起收：目标没了还挂着一条永远不走的条，比不画更误导。
func _cancel_pending_pick() -> void:
	_pending_pick = {}
	_pick_phase = PICK_PHASE_IDLE
	_pick_left = 0.0
	if pickup_progress != null:
		pickup_progress.clear()


## 每帧推进拾取。**航行段只判断「到没到」，打捞段才走进度。**
##
## 顺序即语义：
##   1. 航行中 → 条一直藏着（这一段是赶路，不是拾取）。
##   2. 船停了 → 够得着就开始打捞（条从 0 出现）；够不着就作废。
##   3. 打捞中 → 计时推进，条跟着走；走满结算。
func _update_pickup_progress(delta: float) -> void:
	if pickup_progress == null: return
	pickup_progress.tick(delta)
	if _pick_phase == PICK_PHASE_SAILING:
		if boat.starts_sailing():
			pickup_progress.hide_bar()
			return
		# 停稳了：够得着才算真的开始捞。
		if _pick_in_reach():
			_begin_pick_gather()
		else:
			_cancel_pending_pick()
		return
	if _pick_phase != PICK_PHASE_GATHERING: return
	# 潜水时暂停打捞（人不该一边下潜一边捞木头），进度也冻住。
	if dive.active: return
	_pick_left = maxf(_pick_left - delta, 0.0)
	pickup_progress.set_ratio(1.0 - _pick_left / maxf(_pick_span, 0.001))
	pickup_progress.refresh()
	if _pick_left <= 0.0:
		_finish_pick()


## 没有点击、船自己停在浮木旁边：同样走「停下 → 打捞」。
##
## 原先这里是 try_pickup 一停就瞬收。两条路径必须同一套语义：
## 只有停下来才捞得到东西，否则「点过去」要打捞、「自己划过去」瞬收，
## 玩家会觉得规则自相矛盾。
func _start_idle_pick() -> void:
	if _pick_phase != PICK_PHASE_IDLE: return
	if props == null or boat.starts_sailing() or dive.active: return
	var near: Dictionary = props.nearest_crate(boat.position, props.PICKUP_RADIUS)
	if near.is_empty(): return
	_pending_pick = {"type": "crate", "item": near}
	_begin_pick_gather()


func _on_crate_collected(_kind: String, label: String, reward: Dictionary) -> void:
	var parts: Array = []
	for k in reward.keys():
		parts.append("%s +%d" % [Economy.COLLECTIONS.get(k, {}).get("label", k), int(reward[k])])
	hud.toast("%s · %s" % [label, "  ".join(parts)])


func _on_fish_collected(_label: String) -> void:
	hud.toast("捞到 1 条鱼")


## 采集点进账：统一走背包，装不下的部分会被拦下并提示。
func _on_gathered(kind: String, amount: int, label: String, _spot: Node3D) -> void:
	var added: Dictionary = Economy.give({kind: amount})
	var got := int(added.get(kind, 0))
	if got <= 0:
		hud.toast("背包装不下 %s" % label)
		return
	var icon := ItemDB.icon(kind)
	hud.toast("%s  %s +%d" % [icon, label, got])


func _on_depth_changed(depth: float) -> void:
	hud.set_dive_depth(depth)


func _on_dive_air(ratio: float, lamp_on: bool, found: int, total: int) -> void:
	hud.set_dive_air(ratio, lamp_on, found, total)


func _on_dive_zone(name: String) -> void:
	hud.set_dive_zone(name)


func _on_dive_exited() -> void:
	actor_controller.request_mode(GameState.Mode.ON_BOAT)
	hud.set_diving(false)
	hud.toast("回到水面")


## 调试入口（`--salvage`）：忽略距离，直接开面板。
func _try_salvage() -> void:
	if Scope.minimal(): return
	var now := Time.get_ticks_msec() / 1000.0
	if not Economy.can_salvage(now):
		hud.toast("绞盘还在收线 · %.0f 秒" % Economy.salvage_cooldown_left(now))
		return
	_open_salvage(salvage_winch)


func _on_dive() -> void:
	if _title_active: return
	if Scope.minimal(): return
	if boat.starts_sailing():
		hud.toast("先靠岸或停船再潜水")
		return
	if dive.active:
		dive.surface()
		hud.set_diving(false)
		hud.toast("上浮")
		return
	_cancel_action()
	if hud.is_panel_open(): hud.toggle_panel()
	cam_panel.set_open(false)
	grade.set_open(false)
	dive.dive(boat.position, Zones.label(GameState.current_zone))
	# 氧气还没恢复时 dive() 会拒绝并自己发提示，别把 HUD 切成潜水模式。
	if not dive.active:
		return
	actor_controller.request_mode(GameState.Mode.DIVING)
	player.set_diving(true)
	hud.set_diving(true)
	hud.toast("下潜 · %s" % Zones.label(GameState.current_zone))


## 建造页直接进入前往和自动交付流程。
func _on_focus_site(id: String) -> void:
	if Scope.minimal(): return
	if build_field == null:
		return
	var node: Node3D = build_field.find(id)
	if node == null:
		hud.toast("找不到建造点：%s" % id)
		return
	if node.zone_id != GameState.current_zone:
		hud.toast("请先前往 " + Zones.label(node.zone_id))
		return
	_approach(node)


func _on_build_facility(id: String) -> void:
	if Scope.minimal(): return
	var r: Dictionary = Economy.build_facility(id)
	if r.ok:
		hud.toast("建成 · %s" % r.name)
	else:
		hud.toast(str(r.reason))


## 种植页的「前往」：把镜头挪到菜箱旁。
func _on_focus_plot(plot_id: String) -> void:
	if farm_field == null:
		return
	var node: Node3D = farm_field.find(plot_id)
	if node == null:
		hud.toast("找不到菜箱：%s" % plot_id)
		return
	if node.zone_id != GameState.current_zone:
		hud.toast("请先划船前往 " + Zones.label(node.zone_id))
		return
	_approach(node)


func _rest_for_day() -> void:
	if _title_active or sleep_cycle.busy: return
	if dive.active or boat.starts_sailing() or _walking or GameState.mode != GameState.Mode.ASHORE:
		hud.toast("请在岸上站定后休息")
		return
	sleep_cycle.request()


func _on_upgrade_ship() -> void:
	if Scope.minimal(): return
	var r: Dictionary = Economy.upgrade_ship()
	if r.ok:
		hud.toast("小船升到 Lv.%d" % int(r.level))
	else:
		hud.toast(str(r.reason))


func _process(delta: float) -> void:
	_t += delta
	if _title_active:
		_active_water_mat().set_shader_parameter("u_time",_t)
		if water_node.has_method("update_surface"): water_node.update_surface(_t,boat,cam.target)
		return
	sleep_cycle.advance(delta)
	if sleep_cycle.busy:
		if building_controller!=null and building_controller.active: building_controller.close()
		return
	if building_controller!=null: building_controller.tick(delta)
	weather_service.tick(delta)
	if weather_view != null:
		weather_view.present(world_clock.query(),weather_service.query(),dive.active)
		# 同一份时钟查询驱动真实光照；屏幕层只负责雨线。
		if daylight_rig != null:
			daylight_rig.apply(world_clock.query().hour)
		_calendar_label.text = world_clock.query().text + " · " + weather_service.query().label
		_calendar_label.visible = not dive.active
	if _autosave_on:
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			# 自动存档静默执行，不打断操作；F5 手动存档才有提示。
			save_game("", true)
	if environment != null and environment.has_method("update_time"):
		environment.update_time(_t)
	for zone in _zone_nodes.values():
		if zone.has_method("update_time"):
			zone.update_time(_t)
	_update_walk(delta)
	# 交互只在岸上、站定时开放：船上/航行中/潜水都不该出现采集提示。
	if interactor != null:
		interactor.active = (not dive.active) and (not _walking) \
			and GameState.mode == GameState.Mode.ASHORE and not hud.is_modal() \
			and not salvage_panel.is_open() and not order_panel.is_open()
	if prompt != null:
		prompt.update_from(interactor)
	_update_pointer_ui()
	_update_camera_feedback(delta)
	_active_water_mat().set_shader_parameter("u_time", _t)
	if water_node.has_method("update_surface") and not dive.active:
		water_node.update_surface(_t, boat, cam.target)
	# 拾取：推进当前这一轮（航行→打捞→结算都在里面）。
	_update_pickup_progress(delta)
	# 没有点击、船自己停在浮木旁边：也走同一套「停下才打捞」。
	# 顺序在推进之后：先让上一轮结算/收条，再考虑开新一轮。
	if props != null and not dive.active:
		_start_idle_pick()
	if boat != null:
		_active_water_mat().set_shader_parameter("u_boat", boat.wake_uniform())


## 调试用：切换静态几何来源（baked / models），用于两条路径的画面比对。
func _debug_source(src: String) -> void:
	for zone in _zone_nodes.values():
		if zone.has_method("set_geometry_source"):
			zone.set_geometry_source(src)


## 调试用：直接把船摆到指定区块的泊位并对齐镜头（回归截图用，不影响玩法）。
func _debug_teleport(zone_id: String) -> void:
	if not _zone_nodes.has(zone_id):
		return
	var l := Zones.landing(zone_id, "main")
	boat.place_at(Vector3(l.boatPark[0], WATER_LEVEL, l.boatPark[2]), float(l.boatYaw))
	GameState.enter_zone(zone_id)
	actor_controller.restore_pose({"mode":1})
	cam.focus_zone(Zones.get_zone(zone_id))
	cam.target = Vector3(l.boatPark[0], l.boatPark[1], l.boatPark[2])
	cam.apply_pose()
	markers.set_highlight(zone_id)
	_sync_zone_levels()


## 调试用：自动开往指定区块，方便回归截图。
func _autosail(zone_id: String) -> void:
	await get_tree().create_timer(0.4).timeout
	_on_destination(zone_id)


func _reward_parts(reward: Dictionary) -> Array:
	var parts: Array = []
	for k in reward.keys():
		parts.append("%s +%d" % [Economy.COLLECTIONS.get(k, {}).get("label", k), int(reward[k])])
	return parts


func _capture_after_settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var frames := 90
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("[capture] camera=", get_viewport().get_camera_3d().name if get_viewport().get_camera_3d() else "none",
		" env_is_uw=", dive.uses_underwater_environment() if dive != null else "n/a",
		" fov=", get_viewport().get_camera_3d().fov if get_viewport().get_camera_3d() else -1)
	if dive != null and dive.active:
		print("[capture] uw phase=", dive.phase,
			" diver=", dive.diver_pos,
			" cam=", dive.camera.global_position,
			" dir=", -dive.camera.global_transform.basis.z)
	if hud != null:
		# 提示条是唯一会「用完就消失」的 UI，截图回归时先确认它真的画得出来。
		var toast_info: Dictionary = hud.toast_snapshot()
		print("[capture] toast=%s rect=%s alpha=%.2f" % [toast_info.text,str(toast_info.rect),toast_info.alpha])
	var dir := ProjectSettings.globalize_path("res://outputs")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("godot-preview.png"))
	print("[capture] saved ", dir.path_join("godot-preview.png"))
	if OS.get_cmdline_user_args().has("--flicker"):
		await _probe_flicker(img, dir)
	get_tree().quit()


## 闪动取证：同一相机连拍两张（中间只隔一帧），交给 tools/compare_flicker.py 求差。
##
## 深度竞争（z-fighting）在相邻帧之间会「整块换颜色」，而鱼群/气泡/草的动画
## 是沿运动方向的小位移。两者的差异分布形态不同，所以只看统计量不够，
## 还要看差异图长什么样——渲染侧只负责可靠地把两张图落盘。
func _probe_flicker(first: Image, dir: String) -> void:
	first.save_png(dir.path_join("flicker-a.png"))
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var second := get_viewport().get_texture().get_image()
	second.save_png(dir.path_join("flicker-b.png"))
	print("[flicker] captured a/b %s" % str(second.get_size()))

func input_blocked() -> bool:
	return _title_active or (sleep_cycle != null and sleep_cycle.busy) or (hud != null and hud.is_modal()) or (salvage_panel != null and salvage_panel.is_open()) or (order_panel != null and order_panel.is_open()) or (cam_panel != null and cam_panel.is_open()) or (grade != null and grade.visible)

func _setup_actor_controller() -> void:
	actor_controller.mode_changed.connect(GameState.set_mode)
	actor_controller.configure(player,boat,self,interactor,{"landing":_current_landing,"zone":func(): return _zone_nodes.get(GameState.current_zone),"notify":func(text): hud.toast(text),"input_blocked":input_blocked})
	GameState.mode_changed.connect(actor_controller.reconcile_mode)
	cam.input_blocked = input_blocked
	player.rowing_query = boat.rowing_state
	boat.speed_multiplier = func() -> float: return 1.15 if Economy.ship_level>=3 else 1.0
	Economy.ship.upgraded.connect(func(_level): GameState.far_sea_unlocked=true)
	interactor.completed.connect(func(_spot,_reward): actor_controller.complete_interaction())
	interactor.blocked.connect(func(_reason): actor_controller.complete_interaction())
	# SEA-FARM-R02「水壶12份，岸上免费补满」：上岸那一刻补满。
	#
	# 这条以前只有文字没有实现，水壶见底后所有种下的格子都变成死局：
	# 浇水被拒、种植被拒、收获被拒，而界面上没有任何补水按钮。
	# 只认「非岸上 → 岸上」这一次跃迁：浇水后回到待机也是 mode 0，
	# 若按 mode==0 补，等于每浇一次就回满，水壶变成无限。
	var _last_mode := {"value": -1}
	actor_controller.mode_changed.connect(func(mode: int) -> void:
		var was: int = int(_last_mode.value)
		_last_mode.value = mode
		if mode == 0 and was != 0 and Economy.farm != null: Economy.farm.refill())

func _setup_calendar() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/world_time.json"))
	world_clock.configure(config.get("clock",{}))
	if Scope.minimal():
		Economy.daily.observe(world_clock.query())
		world_clock.changed.connect(Economy.daily.observe)
		Economy.daily.settled.connect(func(receipt: Dictionary): hud.toast("收货员已收走货物 · 瓶盖 +%d" % receipt.income if receipt.income>0 else "第 %d 天 · 新的一天，记得照料作物" % receipt.day,4.0))
	weather_service.configure(_load_json("res://assets/data/weather.json"))
	hud.calendar_query=world_clock.query
	hud.weather_query=weather_service.query
	var layer := CanvasLayer.new()
	layer.name = "WorldWeather"
	layer.layer = 0
	add_child(layer)
	weather_view = preload("res://src/weather/weather_presenter.gd").new()
	layer.add_child(weather_view)
	_calendar_label = hud.clock_label
	_calendar_label.text = world_clock.query().text + " · " + weather_service.query().label
	_setup_daylight()


## 昼夜光照装置。必须在 `_setup_water` 之后建 —— 它要把水面材质的天空反射
## 与太阳高光一起抄成基准，水面还没建就抄了个空。
##
## 抄完按存档时刻输出；开始画面与正式入场共用恢复后的同一世界时刻。
func _setup_daylight() -> void:
	daylight_rig = preload("res://src/rendering/daylight_rig.gd").new()
	daylight_rig.name = "DaylightRig"
	add_child(daylight_rig)
	# 水面会换方案，所以给的是查询而不是材质本身；换过之后装置自己重抄基准。
	daylight_rig.capture(self, _active_water_mat)
	# 分时段偏移按「季节 + 天气」分组：天气一变就换一套偏移，不用等面板开着。
	daylight_rig.set_scene_context(daylight_rig.season(), weather_service.kind)
	weather_service.changed.connect(func(_snapshot: Dictionary) -> void:
		if daylight_rig != null:
			daylight_rig.set_scene_context(daylight_rig.season(), weather_service.kind))
	daylight_rig.apply(world_clock.query().hour)

func _setup_building() -> void:
	building_world=preload("res://src/building/building_world.gd").new()
	building_world.name="BuildingWorld";add_child(building_world)
	var boundary=preload("res://src/building/building_boundary.gd").new()
	building_boundary=boundary
	boundary.world=building_world
	boundary.actor_query=func(): return {"mode":actor_controller.mode(),"zone":GameState.current_zone,"position":player.global_position}
	boundary.boat_query=func(): return boat.global_position
	boundary.obstacles_query=func():
		var result: Array=[]
		for zone in _zone_nodes.values():
			if zone.zone_id=="zone5": continue
			for ground in zone.walk_areas:
				for rect: Rect2 in ground.rects:
					var point: Vector3=ground.to_global(Vector3(rect.position.x,0,rect.position.y))
					result.append(Rect2(Vector2(point.x,point.z),rect.size))
		return result
	building.configure({"eligibility":boundary.eligibility,"space_reason":boundary.space_reason,"pay":Economy.inventory.pay})
	building_world.configure(building,_zone_nodes.zone5.walk_areas[0],farm_field,_bind_constructed_plot,func():
		navigation.invalidate()
		water_node.set_runtime_contact_rects(building_world.contact_rects()))
	building.completed.connect(func(_id): props.apply_population_scope())
	building_controller=preload("res://src/building/building_controller.gd").new();add_child(building_controller)
	building_controller.configure(building,building_world,cam,hud,Economy.inventory.all,actor_controller.cancel,
		_construction_stand_point,_construction_walk,_construction_actor_state)
	hud.material_shop=preload("res://src/building/material_shop.gd").new();hud.material_shop.inventory=Economy.inventory

func _bind_constructed_plot(plot: Node3D) -> void:
	plot.use_action_menu=true
	if not plot.interaction_requested.is_connected(_open_plot_options): plot.interaction_requested.connect(_open_plot_options)

## 施工时角色该站哪：目标格旁最近的、走得到的落脚点。
##
## 新木板格本身还不在可行走面上（要建完才算地面），所以不能直接把格心当目标 ——
## 沿「角色这一侧」的方向往外探几个半径，取第一个落在可走矩形里、且有通路的位置。
## 都探不到就退回到「把格心夹到最近的可行走面」，避免在平台边缘建造成死局。
func _construction_stand_point(center: Vector3) -> Vector3:
	var zone: Node = _zone_nodes.get("zone5")
	if zone == null: return Vector3.INF
	var actor: Vector3 = player.global_position
	var dir := actor - center
	dir.y = 0.0
	if dir.length() < 0.05: dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	for radius in [1.15, 1.5, 1.9, 2.4]:
		var probe: Vector3 = center + dir * radius
		for ground in zone.walk_areas:
			if not ground.contains_world(probe.x, probe.z): continue
			if ground.path_between(actor, probe).is_empty(): continue
			return Vector3(probe.x, ground.surface_y, probe.z)
	for ground in zone.walk_areas:
		var q: Vector2 = ground.clamp_point(center.x, center.z)
		var point := Vector3(q.x, ground.surface_y, q.y)
		if Vector2(point.x - center.x, point.z - center.z).length() < 0.35: continue
		if ground.path_between(actor, point).is_empty(): continue
		return point
	return Vector3.INF

## 施工前走过去。走不到就返回 false，由建造控制器说明原因，不给「原地开工」的捷径。
func _construction_walk(point: Vector3) -> bool:
	var zone: Node = _zone_nodes.get("zone5")
	if zone == null: return false
	var ground: Variant = zone.area_containing(point.x, point.z)
	if ground == null: return false
	if hud != null: hud.world_actions.close(true)
	return actor_controller.start_walk(ground, point)

func _construction_actor_state() -> Dictionary:
	return {"position": player.global_position, "walking": actor_controller.walking()}

func _restore_building(data: Dictionary) -> void:
	building_controller.close()
	building_world.reset_projection()
	building.from_dict(data)
	# Registry suppresses owner signals; the projection must exist before Farm restores.
	building_world.sync()

func _validate_building_world(snapshot: Dictionary) -> String:
	return validate_world_state(snapshot.game,snapshot.building.instances)

func _setup_save_registry() -> void:
	save_registry.busy_query = func(): return Economy.daily.is_settling() or sleep_cycle.busy or building.busy()
	var schemas: Dictionary = preload("res://src/save/save_schema.gd").schemas()
	save_registry.snapshot_validator = _validate_building_world
	save_registry.register("building",building.to_dict,_restore_building,schemas.building,building.to_dict(),building.validate_snapshot,[building])
	var owners := {"economy":Economy,"gather":gather,"pickups":props,"dive":dive,"salvage":Economy.salvage,"time":world_clock,"weather":weather_service}
	for id in owners:
		var owner = owners[id]
		var sources: Array = owner.snapshot_event_sources() if owner.has_method("snapshot_event_sources") else [owner]
		save_registry.register(id,owner.to_dict,owner.from_dict,schemas[id],owner.to_dict(),Callable(),sources)
	save_registry.register("game",capture_world_state,restore_world_state,schemas.game,capture_world_state(),Callable(),[GameState])
	save_registry.restored.connect(_after_restore)

func capture_world_state() -> Dictionary:
	var p := player.global_position
	var b := boat.position
	return {"zone":GameState.current_zone,"landing":GameState.landing_id,"mode":actor_controller.mode(),"far_sea":GameState.far_sea_unlocked,"boat":[b.x,b.y,b.z,boat.rotation.y],"player":[p.x,p.y,p.z] if actor_controller.mode()==0 else []}

func restore_world_state(data: Dictionary) -> void:
	data = data.duplicate(true)
	var old_pose: Array = data.get("boat",[])
	if Scope.minimal() and (not Scope.zone_enabled(str(data.get("zone","zone1"))) or (old_pose.size()==4 and not Scope.SAIL_BOUNDS.has_point(Vector2(old_pose[0],old_pose[2])))):
		data.merge({"zone":"zone1","landing":"main","mode":1,"boat":[],"player":[]},true)
	_cancel_pending_pick()
	_ashore_on_arrival = false
	actor_controller.cancel()
	GameState.far_sea_unlocked = bool(data.get("far_sea",false))
	var zone_id := str(data.get("zone","zone1"))
	if not _zone_nodes.has(zone_id): zone_id="zone1"
	GameState.landing_id = str(data.get("landing","main"))
	var pose: Array = data.get("boat",[])
	if pose.size()==4: boat.place_at(Vector3(pose[0],pose[1],pose[2]),pose[3])
	else:
		var landing: Dictionary = Zones.landing(zone_id,"main")
		boat.place_at(Vector3(landing.boatPark[0],WATER_LEVEL,landing.boatPark[2]),landing.boatYaw)
	var saved_player: Array = data.get("player",[])
	if int(data.get("mode",1)) == GameState.Mode.ASHORE and saved_player.size()==3:
		var ground = _zone_nodes[zone_id].area_containing(float(saved_player[0]),float(saved_player[2]))
		if ground != null: data.player = [saved_player[0],ground.surface_y,saved_player[2]]
	actor_controller.restore_pose(data)
	GameState.enter_zone(zone_id)

func _after_restore() -> void:
	if Scope.minimal(): Economy.daily.observe(world_clock.query())
	Economy.publish_restored()
	_sync_zone_levels()
	cam.restore_follow(player)
	markers.set_highlight(GameState.current_zone)
	hud.refresh_after_restore()

func _exit_tree() -> void:
	actor_controller.ports.clear()
	actor_controller.after_walk = Callable()
	save_registry.clear()
	navigation.shape_query = Callable()

func validate_world_state(data: Dictionary, layout: Variant = null) -> String:
	var pos: Array = data.get("player",[])
	if int(data.get("mode",1))==0 and pos.size()==3:
		var zone_id := str(data.get("zone","zone1"))
		if not _zone_nodes.has(zone_id): return "Unknown saved zone"
		if zone_id=="zone5" and layout!=null:
			if not building_world.contains_saved(Vector3(pos[0],pos[1],pos[2]),layout): return "Saved player is outside constructed ground"
		else:
			var area = _zone_nodes[zone_id].area_containing(float(pos[0]),float(pos[2]))
			if area==null or absf(area.surface_y-float(pos[1]))>0.5: return "Saved player is outside walkable ground"
	var pose: Array = data.get("boat",[])
	var candidate_nav = preload("res://src/navigation/water_navigation.gd").new()
	candidate_nav.shape_query=func(): return _water_shapes()+building_world.water_shapes(building.query() if layout==null else layout)
	if pose.size()==4 and not candidate_nav.is_geometric_water(float(pose[0]),float(pose[2])): return "Saved boat is outside navigable water"
	return ""

func _apply_play_scope() -> void:
	if not Scope.minimal(): return
	for id in _zone_nodes:
		if not Scope.zone_enabled(id):
			_zone_nodes[id].hide()
			_zone_nodes[id].process_mode = Node.PROCESS_MODE_DISABLED
	var distant := environment.get_node_or_null("StaticBatch")
	if distant: distant.hide()
	for field in [gather,build_field,salvage_winch]:
		field.hide()
		field.process_mode = Node.PROCESS_MODE_DISABLED
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node.is_visible_in_tree(): node.remove_from_group("interactable")
	trade_board.order_model = null
	var supply_landing = _zone_nodes["zone1"].landing_point("salvage")
	trade_board.position = supply_landing.stand_position()+Vector3(-1.6,0,-1.2)
	trade_board.label = "家园补给站 · 商店 / 仓库 / 出货箱"
	trade_board.verb = "打开"
	# Camera remains locked; P is an available lighting/debug tool in this scope.
	cam_panel.process_mode = Node.PROCESS_MODE_DISABLED

func _begin_title() -> void:
	_title_active = true
	daylight_rig.apply(world_clock.query().hour)
	_zone_nodes.zone1.get_node("Objects/SleepCheckpoint").hide()
	_title_economy_ticking = Economy.ticking
	Economy.ticking = false
	interactor.active = false
	for node in find_children("*","CanvasLayer",true,false):
		_title_layers.append({"node":node,"visible":node.visible,"process_mode":node.process_mode})
		node.hide()
		node.process_mode = Node.PROCESS_MODE_DISABLED
	_title_props = {"visible":props.visible,"process_mode":props.process_mode}
	props.hide()
	props.process_mode = Node.PROCESS_MODE_DISABLED
	title_camera.begin(cam)
	start_screen = preload("res://src/ui/start_screen.gd").new()
	start_screen.name = "StartScreen"
	add_child(start_screen)
	start_screen.start_requested.connect(_enter_game)

func _enter_game() -> void:
	if not _title_active: return
	var transition := create_tween()
	transition.tween_method(func(value: float): title_camera.blend(cam,value),0.0,1.0,1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_callback(func():
		title_camera.finish(cam)
		for entry in _title_layers:
			entry.node.visible = entry.visible
			entry.node.process_mode = entry.process_mode
		_title_layers.clear()
		props.visible = _title_props.visible
		props.process_mode = _title_props.process_mode
		_title_props.clear()
		_title_active = false
		_zone_nodes.zone1.get_node("Objects/SleepCheckpoint").show()
		daylight_rig.apply(world_clock.query().hour)
		Economy.ticking = _title_economy_ticking
		start_screen.queue_free()
		start_screen = null)


func _open_plot_options(plot_id: String) -> void:
	var plot: Node3D = farm_field.find(plot_id)
	if plot == null or _title_active: return
	_open_spot_bubbles(plot)

## 气泡锚点：和判定、悬浮图标同一个 `focus_position()`，只是抬到物体上半身。
##
## 以前这里用 `global_position`（节点原点），而判定用视觉包围盒中心 —— 出货箱两者
## 差 2 米，菜单会开在箱子旁边的空地上。目标整块投影出屏时返回 null，
## 由 `_open_spot_bubbles` 的屏幕兜底接住。
func _bubble_anchor(spot: Node3D) -> Callable:
	return func() -> Variant:
		if not is_instance_valid(spot) or not spot.is_visible_in_tree(): return null
		var base: Vector3 = spot.focus_position() if spot.has_method("focus_position") else spot.global_position
		var world: Vector3 = base+Vector3.UP*0.45
		if cam.is_position_behind(world): return null
		var screen: Vector2=cam.unproject_position(world)
		if not get_viewport().get_visible_rect().grow(24).has_point(screen): return null
		return screen

## 展开一处可交互物的操作菜单。
##
## 走不到就不弹（2026-10-29 二次修订）。上一版是「照弹菜单、把每一项涂灰写原因」，
## 玩家的反馈很直接：一个能点、能展开、全是灰的菜单，读起来就是界面坏了，
## 而且它出现的位置本身就在告诉玩家「这个东西现在能操作」。
## 现在的规则：
##   1. 陆地状态下走不到的目标，点它只 toast 一句原因，不弹菜单、不显示悬浮图标；
##   2. 够得着的目标照常弹，选项只反映业务规则（缺种子 / 已浇水）。
func _open_spot_bubbles(spot: Node3D, screen: Variant = Vector2.INF) -> void:
	if not is_instance_valid(spot): return
	var unreachable: String = _land_reach_reason(spot)
	if unreachable != "":
		hud.toast(unreachable)
		return
	actor_controller.cancel()
	var options: Array = []
	if spot.is_in_group("farm_plots"):
		var id := str(spot.plot_id)
		var phase: String = Economy.farm.phase(id)
		var access: String = Economy.farm.access_reason(id)
		if phase == "empty":
			var owned: Array = _owned_seeds()
			# 背包里有种子就一定弹二级：选哪一包、还剩几包，必须由玩家确认。
			# 以前「只有一种就直接种」会让手里拿着三包生菜的人点一下就没得选，
			# 也看不出刚才种掉的是哪一包。
			options.append({"id":"plant","icon":"plant","label":"种植","blocked":access if access!="" else ("背包里没有种子，可到商店购买" if owned.is_empty() else ""),"command":func(): _open_seed_bubbles(spot, screen)})
			# 空地才摆出「浇水 / 收获」两颗灰项，说明这格还能做什么。
			options.append({"id":"water","icon":"water","label":"浇水","blocked":access if access!="" else "种下种子后再浇水"})
			options.append({"id":"harvest","icon":"harvest","label":"收获","blocked":access if access!="" else "还没有成熟的作物"})
		elif phase == "ready":
			options.append({"id":"harvest","icon":"harvest","label":"收获","blocked":Economy.farm.blocked_reason(id),"command":func(): _queue_plot_action(spot,"harvest","")})
		else:
			# 已种植的格子只给「这一格现在该做的事」。
			# 从前这里也摆「种植」，灰着但排在第一个，玩家明明想浇水却先读到「种植」，
			# 会以为这格是空的、还要再种一次。
			var reason := access
			if reason=="" and not Economy.farm.is_dry(id): reason="今天已经浇过水了"
			if reason=="" and Economy.farm.watering_can<=0:
				# 水壶见底：这一格直接换成「补水并浇水」，一步到位，不再让玩家去翻页面。
				options.append({"id":"water","icon":"water","label":"补水并浇水","blocked":"",
					"command":func(): _queue_refill_and_water(spot)})
			else:
				options.append({"id":"water","icon":"water","label":"浇水","blocked":reason,"command":func(): _queue_plot_action(spot,"water","")})
	elif spot == trade_board and Scope.minimal():
		for service in [["shop","shop","商店"],["storage","bag","仓库"],["shipping","shipping","出货箱"]]:
			var tab := str(service[0])
			options.append({"id":tab,"icon":str(service[1]),"label":str(service[2]),"command":func(): _approach_command(spot,func() -> Dictionary:
				hud.open_tab(tab);return {"event":"service_opened"})})
	else:
		var icon := "hand"
		if spot.is_in_group("shipping_boxes"): icon="shipping"
		elif str(spot.id)=="home_sleep": icon="sleep"
		elif str(spot.verb).contains("采"): icon="harvest"
		elif str(spot.verb).contains("挖"): icon="dig"
		var blocked := str(spot.blocked_reason()) if spot.has_method("blocked_reason") else ""
		options.append({"id":"interact","icon":icon,"label":str(spot.verb),"blocked":blocked,"command":func(): _approach(spot)})
	hud.open_world_actions(_bubble_anchor(spot),options,"",screen)

## 这一处目标，从玩家脚下能不能走过去？空串表示能。
##
## 只看陆地：人在船上或水里时不做预检 —— 那种情况 `approach` 自己会先靠岸，
## 提前判死会让「在船上点岸上的箱子」变成一堆点不动的目标。
##
## 分三类原因，因为玩家能做的补救不一样：
##   别的区域 → 需要坐船过去；同一区域但断开 → 中间真的没有路。
##
## 悬停层每帧都会问，所以带 350ms 缓存：路径规划不算便宜，
## 全场景每个候选都现算会把悬停拖卡。过期就重算 —— 走两步之后结论可能就变了。
var _reach_cache := {}
const REACH_TTL_MS := 350

func _land_reach_reason(spot: Node3D) -> String:
	if actor_controller.mode() != 0: return ""
	if spot == null or not is_instance_valid(spot): return ""
	var key := spot.get_instance_id()
	var now := Time.get_ticks_msec()
	if _reach_cache.has(key):
		var cached: Dictionary = _reach_cache[key]
		if now - int(cached.stamp) < REACH_TTL_MS: return str(cached.reason)
	var reason := _compute_reach_reason(spot)
	if _reach_cache.size() > 128:
		for id in _reach_cache.keys():
			if now - int(_reach_cache[id].stamp) >= REACH_TTL_MS: _reach_cache.erase(id)
	_reach_cache[key] = {"reason": reason, "stamp": now}
	return reason

func _compute_reach_reason(spot: Node3D) -> String:
	# 站着的那一格不等于物体中心：培养土把中心从可行走面里挖掉了，
	# 用中心判可达会让「自己刚建好的菜箱」被说成走不过去。
	# 有 approach_points 就按它判 —— 那本来就是给「站到哪去操作」准备的。
	var points: Array = []
	if spot.has_meta("approach_points"):
		for p in spot.get_meta("approach_points"):
			points.append(p)
	if points.is_empty():
		points.append(spot.focus_position() if spot.has_method("focus_position") else spot.global_position)
	var here: Node = actor_controller.ports.zone.call()
	var from: Vector3 = actor_controller.actor.global_position
	var on_here := false
	if here != null:
		for p: Vector3 in points:
			var area: Variant = here.area_containing(p.x, p.z)
			if area == null: continue
			on_here = true
			if not (area as Node3D).path_between(from, p).is_empty(): return ""
	if on_here: return "那里走不过去，中间没有连通的路"
	for zone_id in _zone_nodes:
		var node: Node = _zone_nodes[zone_id]
		if node == null or node == here: continue
		for p2: Vector3 in points:
			if node.area_containing(p2.x, p2.z) != null:
				return "那边在别的区域，需要先坐船靠岸"
	return "那里是水面，走不过去"

func _owned_seeds() -> Array:
	var result: Array=[]
	for id in Economy.farm.crop_definitions():
		if Economy.inventory.count(str(Economy.farm.crop_def(id).seed))>0: result.append(id)
	return result

## 二级：选种子。每个气泡下面挂「生菜 ×3」这样的胶囊，
## 免得三个种子只剩图标 —— 生菜/番茄/南瓜的种子图标在小尺寸下几乎分不出。
func _open_seed_bubbles(plot: Node3D, screen: Variant = Vector2.INF) -> void:
	var options: Array=[]
	for raw in _owned_seeds():
		var crop := str(raw)
		var definition: Dictionary=Economy.farm.crop_def(crop)
		var count: int = Economy.inventory.count(str(definition.seed))
		options.append({"id":"seed:"+crop,"icon":"plant","item_icon":str(definition.seed),
			"label":str(definition.name),"caption":"%s ×%d" % [str(definition.name),count],
			"command":func(): _queue_plot_action(plot,"plant",crop)})
	hud.open_world_actions(_bubble_anchor(plot),options,"选择种子",screen)

func _approach_command(spot: Node3D, command: Callable) -> void:
	if _approach(spot): interactor.queue_command(spot,command)

func _queue_plot_action(plot: Node3D, action: String, crop: String) -> void:
	_approach_command(plot,func() -> Dictionary:
		if not is_instance_valid(plot): return {"blocked":"种植格已不可用"}
		var result: Dictionary=plot.perform(action,crop)
		if not result.has("blocked"):
			player.play_farm_action({"plant":"播种","water":"浇水","harvest":"收获"}.get(action,"查看"))
		return result)

## 水壶见底时的一步操作：补满淡水 → 立刻浇这一格。
##
## 拆分会有两种情况出问题：只补水不浇水，玩家还以为点失败了；先浇水再补水，
## 中间会弹一次「水壶空了」。合成一条命令，走完只掉一块水。
func _queue_refill_and_water(plot: Node3D) -> void:
	_approach_command(plot,func() -> Dictionary:
		if not is_instance_valid(plot): return {"blocked":"种植格已不可用"}
		Economy.farm.refill()
		var result: Dictionary=plot.perform("water","")
		if not result.has("blocked"):
			player.play_farm_action("浇水")
		return result)

func _setup_shipping_box() -> void:
	var box = _zone_nodes.zone1.get_node("Objects/ShippingBox")
	box.opened.connect(func(): hud.open_tab("shipping"))


func _setup_sleep() -> void:
	sleep_curtain = preload("res://src/ui/sleep_curtain.gd").new()
	sleep_curtain.name = "SleepCurtain"
	add_child(sleep_curtain)
	sleep_curtain.focus_query = func(): return cam.unproject_position(player.global_position+Vector3.UP*0.7)
	sleep_cycle = preload("res://src/time/sleep_cycle.gd").new()
	sleep_cycle.name = "SleepCycle"
	add_child(sleep_cycle)
	sleep_cycle.clock = world_clock
	sleep_cycle.curtain = sleep_curtain
	sleep_cycle.prepare = _prepare_sleep
	sleep_cycle.return_home = _wake_at_home
	sleep_cycle.woke.connect(func(_snapshot):
		_restore_sleep_ui()
		hud.toast("早上好 · 07:00 作物生长、出货箱收货",4.0)
		if _autosave_on: save_game("",true))
	_zone_nodes.zone1.get_node("Objects/SleepCheckpoint").sleep_requested.connect(_rest_for_day)

func _prepare_sleep() -> void:
	actor_controller.cancel()
	_cancel_pending_pick()
	if ribbon != null: ribbon.clear()
	interactor.active = false
	hud.menu.close_menu()
	hud.close_card()
	for presenter in [order_panel,cam_panel,grade]:
		presenter.set_open(false)
	salvage_panel.cancel()
	# Development/full-world saves may be underwater. Finish through the dive state machine.
	if dive.active: dive.phase_machine.change("surface",{},true)
	actor_controller.begin_sleep()
	# Keep rain/world rendering alive; hide gameplay UI until the iris is fully open.
	_sleep_ui_layers.clear()
	for layer in find_children("*","CanvasLayer",true,false):
		if layer==sleep_curtain or layer.name=="WorldWeather": continue
		_sleep_ui_layers.append({"node":layer,"visible":layer.visible})
		layer.hide()
	_sleep_calendar_visible = _calendar_label.visible
	_calendar_label.hide()
	_zone_nodes.zone1.get_node("Objects/SleepCheckpoint").hide()

func _restore_sleep_ui() -> void:
	for entry in _sleep_ui_layers:
		if is_instance_valid(entry.node): entry.node.visible=entry.visible
	_sleep_ui_layers.clear()
	_calendar_label.visible = _sleep_calendar_visible
	_zone_nodes.zone1.get_node("Objects/SleepCheckpoint").show()

func _wake_at_home() -> void:
	var checkpoint: Node3D = _zone_nodes.zone1.get_node("Objects/SleepCheckpoint")
	var pos := checkpoint.global_position+Vector3(0,0,0.8)
	restore_world_state({"zone":"zone1","landing":"main","mode":0,"player":[pos.x,pos.y,pos.z],"far_sea":GameState.far_sea_unlocked})
	cam.restore_follow(player)
	cam.target = player.global_position+Vector3.UP*0.7
	cam.apply_pose()
	markers.set_highlight("zone1")
	daylight_rig.apply(world_clock.query().hour)
	_calendar_label.text = world_clock.query().text + " · " + weather_service.query().label
	if not Scope.minimal(): Economy.farm.advance_day()
