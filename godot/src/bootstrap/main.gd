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
const BodyScale = preload("res://src/avatar/avatar_dimensions.gd")
var navigation = preload("res://src/navigation/water_navigation.gd").new()
const WATER_LEVEL := 1.12
## 渲染后端差异（Reverse-Z 只存在于 Forward+），详见该脚本。
const RenderFlagsLib = preload("res://src/rendering/render_flags.gd")
const OrbitCamScript = preload("res://src/camera/orbit_camera.gd")
const WaterSurfaceScript = preload("res://src/rendering/water_surface.gd")
const BoatScript = preload("res://src/navigation/boat.gd")
const GullFlockScript = preload("res://src/ambient/building_gull_flock.gd")
const HUDScript = preload("res://src/ui/hud.gd")
const MarkersScript = preload("res://src/ui/landing_markers.gd")
const CharacterScript = preload("res://src/player/character.gd")
const PropsScript = preload("res://src/pickups/sea_props.gd")
const DiveSession = preload("res://src/diving/dive_session.gd")
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
const NpcServiceScript = preload("res://src/npc/npc_service.gd")
const NpcCatalog = preload("res://src/npc/npc_catalog.gd")
const ShopServiceScript = preload("res://src/shop/shop_service.gd")
const WorkshopHostScript = preload("res://src/workshop/host.gd")

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
var building_access: Node
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
## Authored fishery projection, driven only by FisheryModel.unlocked.
var _fishery_visual: Node3D
var _fishery_harvest: Node3D
var _fishery_marker: CanvasLayer
var _fishery_schools: Node3D
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
## SEA-ROOM：房间状态（床的摆放 / 在不在屋里）与进出过场。
## 房间是 `World/Interior` 下的一个区块（zone_id="room"），和其它区块共用行走接口。
var room_service = preload("res://src/room/room_service.gd").new()
var room_controller = preload("res://src/room/room_controller.gd").new()
var room: Node3D
var sunroom_surface: Node3D
var sunroom_view: Node3D
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
## 岸上行走速度的参考值（与 `free_walk_action.SPEED`、`walk_action.SPEED` 同值）。
## 2026-11-11 由 2.3 提到 2.8。真正的执行仍在这两个动作里，这里只是让文档里的数字有处可查。
const WALK_SPEED := 2.8
## 上船热区·到泊位站立点的半径（米）。走进这个圈，船边就出上船图标。
const BOAT_KEY_REACH := 2.4
## 上船热区·直接贴到船舷的半径（米）。码头很长、站立点在另一头时兜住玩家。
const BOAT_HULL_REACH := 3.0
## 岸上「朝谁操作」的仲裁带宽（与 Interactor.FACING_TIE 同值，见那里注释）。
const FACING_TIE := 0.08
## 靠妥容差（米）：船与泊位锚点的距离在这个范围内就算「停在泊位」。
##
## 旧值 1.0 太紧 —— 自动靠泊收在余速下常常停在 1.1–1.4 米，船明明贴着码头，
## 按 E 却说「船不在泊位」。上下船判定被抱怨「体验不好」有一部分来自这里。
## `_landing_is_docked`、点船体、登陆标记图标三处共用，不再各写一个数。
const DOCK_SETTLE_TOLERANCE := 1.6
## 按 E 上/下船后的冷却（秒）。切换是一次性动作：按住不放时键盘只会补 echo 事件，
## 但「走位到一半再按一下」会立刻反向 —— 表现为刚上船又上岸。0.35 秒足够过场起势，
## 又不会让有意连按失效（真连按通常是误触，本来就该被吞掉）。
const BOAT_KEY_COOLDOWN := 0.35
var _boat_key_left := 0.0

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
var npc_service = NpcServiceScript.new()
var shop_service = ShopServiceScript.new()
var npc_world_presenter
## 菜园桥招呼：台词表、气泡节点、当天是否已经喊过。
## 「今天喊过」只活在本次运行里：NPC 存档有严格字段校验，塞新字段会让旧档拒绝加载，
## 存档是核心资产，这里宁可不持久化。读档后当天可再喊一次，属已知取舍。
const GARDEN_GREETINGS := "res://assets/data/npc/greetings.json"
## 招呼触发半径（水平 XZ，米）。
##
## 原来 16 米要求把船贴到楼下才触发，玩家基本看不到。改为 32 米：
## 主航道正常经过就能触发，配合放大后的气泡在远处也读得清。
const GARDEN_GREETING_RADIUS := 32.0
## 气泡停留秒数：从「远处看到」到「读完一句」需要更久，4.5 秒在 32 米外偏短。
const GARDEN_GREETING_HOLD := 7.5
var _garden_lines: Array = []
var _garden_bubble: Control
var _garden_spoken_day := -1
var _garden_probe_cooldown := 0.0
var shop_panel
var npc_career_panel
var workshop_host
var _npc_previous_modal_query: Callable
var _npc_previous_modal_close: Callable
var _npc_previous_modal_input: Callable
var _npc_previous_modal_camera_query: Callable
var weather_view: Node2D
## 昼夜光照。时段不再靠屏幕叠加伪造，而是真的去动太阳、环境光、天空与水面反射；
## 资源里的值是它的09:00基准，见 `src/rendering/daylight_rig.gd`。
## 不写 `DaylightRig` 类型注解：新脚本首次导入前全局类名还没注册，
## 带注解会让整个主场景在这一帧解析失败。
var daylight_rig
var sleep_cycle: Node
var sleep_curtain: CanvasLayer
## 「体力见底」的强制休息正在进行（台词 → 黑幕过场）。期间吞掉全部输入，
## 也不再重复触发第二遍。SEA-ENERGY-R04。
var _exhausted_rest := false
## 黑幕里那句「啊，太累了…」停留多久再收幕（秒）。
const EXHAUSTED_LINE_SECONDS := 2.6
var _sleep_ui_layers: Array = []
var _sleep_calendar_visible := false
var _calendar_label: Label


const CozyUI = preload("res://src/ui/cozy_ui.gd")
func _cozy_node_added(node: Node) -> void:
	if node is Control and is_ancestor_of(node): CozyUI.apply_instance.call_deferred(node.get_instance_id())

func _apply_cozy_ui() -> void:
	CozyUI.apply_tree(self)

var start_screen: CanvasLayer
var avatar_profile = preload("res://src/avatar/avatar_profile.gd").new()
var avatar_session: Node
var arrival_flow: Node
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
	# Free ocean construction shares an unbounded sea with sailing. HOME_WATER
	# remains the pickup population area, not a build/sail/camera fence.
	navigation.allowed_area=Rect2()
	Zones.far_sea_query = func() -> bool: return GameState.far_sea_unlocked
	_setup_environment()
	_setup_lights()
	_setup_scene()
	_setup_sunroom()
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
	cam.target = player.global_position + Vector3.UP*BodyScale.CAMERA_FOCUS
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
	_setup_ladders()
	ensure_move_keys()
	_setup_calendar()
	_setup_sleep()
	_setup_room()
	_setup_building()
	_setup_npc_systems()
	_setup_workshop()
	_setup_save_registry()
	_setup_avatar()
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
			# 玩家上限是 38 m（SEA-CAMERA-R11）；调试参数显式要更远时临时抬高上限，
			# 否则 set_distance 会把请求静默夹回 38，截图看不出是被夹了。
			var spec := a.trim_prefix("--zoom=")
			if spec.is_valid_float():
				var z := float(spec)
				if z < cam.zoom_min:
					cam.zoom_min = maxf(6.0, z * 0.8)
				if z > cam.zoom_max:
					cam.zoom_max = z
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
		if a == "--test" and grade != null:
			# 调试：直接打开「测试」页（加资源/改时间/换天气），截图核对用。
			grade.set_open(true)
			grade.set_tab("test")
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


## 重置存档：把这一局退回开局，**旧进度改名归档后保留**。
##
## 三步，顺序不能换：
##   1. 归档旧档（改名，不删除）。失败就整件事取消 —— 不归档就重置等于烧桥。
##   2. 内存回到开局：用注册表在装配时抓下的 `defaults()` 走同一套 restore。
##      这里**不能**用「重载场景」代替：Economy / GameState 是 Autoload，
##      重载主场景它们不会重建，背包还是旧的 —— 那个做法只是看起来干净。
##   3. 立刻写一份新档。不写的话，玩家重置完直接退出，下次启动又读回旧进度，
##      观感就是「重置没生效」。
##
## 恢复走 `save_registry.restore()`，和读档同一条路：先校验全部模块再改任何
## 模块，中间事件被屏蔽，最后发一次 `restored` —— 所以 HUD、相机、昼夜、
## 海面浮标都按原来的接线自动跟上。
func reset_save(path := "") -> Dictionary:
	if dive != null and dive.active:
		hud.toast("潜水时不能重置存档，先上浮")
		return {"ok": false, "reason": "潜水时不能重置存档"}
	if save_registry.is_busy():
		hud.toast("正在结算或过场，稍等一下再重置")
		return {"ok": false, "reason": "正在结算或过场"}
	var target := path if path != "" else _save_path
	var archived: Dictionary = SaveGameLib.archive(target)
	if not archived.get("ok", false):
		hud.toast(str(archived.get("reason", "重置失败")))
		print("[save] reset %s aborted: %s" % [target, archived.get("reason", "")])
		return archived
	var fresh: Dictionary = save_registry.defaults()
	var res: Dictionary = save_registry.restore(fresh)
	if not res.get("ok", false):
		# 内存没改成，旧档也已经挪走了 —— 把归档放回去，别留一个「档没了」的现场。
		var restored: bool = _unarchive(target, archived)
		hud.toast("重置失败：%s%s" % [res.get("reason", ""), "" if restored else "（旧档在 %s）" % _archive_hint(archived)])
		print("[save] reset %s restore failed: %s" % [target, res.get("reason", "")])
		return res
	# 旧档已经归档，之前因为读档失败上的保护要撤掉，否则新档写不进去。
	_save_protected = false
	_autosave_on = true
	_autosave_left = AUTOSAVE_SECONDS
	var wrote: Dictionary = save_game(target, true)
	var where := _archive_hint(archived)
	# 也把水壶补满：开局状态本来就是满的，但 `_after_restore` 只在人在岸上时补，
	# 重置后可能还在船上 —— 不补的话第一天就带着一个空水壶开局。
	if Economy.farm != null:
		Economy.farm.refill()
	if wrote.get("ok", false):
		hud.toast("已重置存档 · 回到第一天早晨%s" % where, 4.0)
	else:
		hud.toast("已重置，但新存档写入失败：%s" % str(wrote.get("reason", "")), 5.0)
	print("[save] reset %s ok (archived %d file(s), new save %s)" % [
		target, (archived.get("files", []) as Array).size(), "ok" if wrote.get("ok", false) else wrote.get("reason", "")])
	return {"ok": wrote.get("ok", false), "reason": str(wrote.get("reason", "")), "archived": archived.get("files", [])}


## 归档文件的存放位置，给提示语用。取文件名而不是全路径：
## `user://` 的真实路径很长，一屏提示塞不下，写全了反而看不清。
func _archive_hint(archived: Dictionary) -> String:
	var files: Array = archived.get("files", [])
	if files.is_empty():
		return ""
	return " · 旧进度已备份为 %s" % String(files[0]).get_file()


## 把归档挪回原槽位。只在「归档成功、内存恢复失败」这一种情况下用。
func _unarchive(target: String, archived: Dictionary) -> bool:
	var files: Array = archived.get("files", [])
	var mark := String(archived.get("mark", ""))
	var ok := true
	for item in files:
		var from := String(item)
		var to := from.replace("_pre_reset-" + mark, "")
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) != OK:
			ok = false
	return ok


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
	_register_sea_structures(world_root.get_node_or_null("SeaStructures"))
	room = world_root.get_node_or_null("Interior") as Node3D
	_register_interior()
	if _zone_nodes.is_empty():
		push_error("World/Zones 下没有区块场景实例")
	_sync_zone_levels()


## 区块之外的结构物如果自己声明了 zone_id，就按「最小区块」登记。
##
## 为什么要破例：浮店原来只是景观 + 水面阻挡，玩家上不去也停不了船。
## 现在它是一个海上补给站 —— 甲板要走得上去、船要靠得进来，就需要
## 与区块同一套 WalkArea / LandingPoint / GroundSpace。与其在 main 里
## 另造一条并行的靠岸通道，不如让它满足区块那几条接口，登记进同一张表。
##
## 边界：仍然只有 `world_root/Zones` 是「有植物的生活区」；这里登记的结构物
## 不带 Plants / StaticBatch / 建造等级，`_sync_zone_levels` 对它们调
## `set_zone_level` 也只是空转。
func _register_sea_structures(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if not ("zone_id" in child) or str(child.zone_id).is_empty():
			continue
		if _zone_nodes.has(child.zone_id):
			push_error("Structure zone id collides with a zone: " + str(child.zone_id))
			continue
		if not (child.has_method("landing_points") and "walk_areas" in child):
			continue
		_zone_nodes[child.zone_id] = child
		Zones.bind_scene(child)


## 室内房间登记为区块（SEA-ROOM）。
##
## 为什么不放进 `World/Zones`：那里是「有植物、有建造等级、要水面阻挡」的户外生活区，
## 而房间是挂在太阳房上的室内空间（y≈120，不接触水面）。但它必须满足同一套区块接口
## （`zone_id` / `walk_areas` / `area_at` / `pick_walk`），否则「在屋里点地面走路」
## 与「房间位置存档校验」就得另开一条通道 —— 那正是要避免的第二套行走系统。
func _register_interior() -> void:
	if room == null:
		push_error("main.tscn 缺少 World/Interior 房间实例")
		return
	if not ("zone_id" in room) or not (room.has_method("landing_points") and "walk_areas" in room):
		push_error("World/Interior 缺 zone_id / walk_areas，房间无法作为区块登记")
		return
	var id := str(room.zone_id)
	if id.is_empty() or _zone_nodes.has(id):
		push_error("房间区块 id 为空或与既有区块冲突: " + id)
		return
	_zone_nodes[id] = room
	Zones.bind_scene(room)


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
	if _start_walk(area, point):
		reticle.show_at(point)
	# 点击了地面就消费输入；不通的地面不能继续被解释成水面航行。
	return true


func _current_landing() -> Node3D:
	if building_access!=null and building_access.is_dynamic(GameState.landing_id):
		return building_access.landing_node(GameState.landing_id)
	var zone: Node3D = _zone_nodes.get(GameState.current_zone)
	return zone.landing_point(GameState.landing_id) if zone != null else null

## 泊位数据的唯一出口。**返回的 `boatPark` 一定是合法水面** —— 本轮修的就是这条保证。
##
## BoatPark 是手摆的 Marker（静态泊位）或按边推导的点（自建平台），两者都可能落进
## 岸线的 0.9 m 缓冲里：zone1 的绞盘泊位实测 park=(-9.95, 18.21) 就在缓冲里，于是
## 「按 E 靠岸」走完整条链路后报「无法到达该泊位」，而船其实早就贴在那儿了。
## 这里把 park 挪到最近的开阔水（≤3.5 m）并缓存；挪不出去才原样返回，让上层如实报错。
const PARK_ESCAPE := 3.5
var _park_cache := {}

func _landing_data(zone_id: String,landing_id: String) -> Dictionary:
	var data: Dictionary
	if building_access!=null and building_access.is_dynamic(landing_id):
		data = building_access.landing_data(landing_id) if zone_id=="zone5" else {}
	else:
		data = Zones.landing(zone_id,landing_id)
	if data.is_empty() or not data.has("boatPark") or navigation == null:
		return data
	var raw := Vector2(float(data.boatPark[0]), float(data.boatPark[2]))
	var key := zone_id + "/" + landing_id
	var legal: Variant = _park_cache.get(key)
	# 自建平台会随着木板增删换边，缓存按原始 park 值失效。
	if legal == null or (legal as Vector2).distance_to(raw) > 0.01:
		var found: Variant = navigation.nearest_open_water(raw.x, raw.y, PARK_ESCAPE)
		legal = raw if found == null else found
		if _park_cache.size() > 64: _park_cache.clear()
		_park_cache[key] = legal
	if (legal as Vector2).distance_to(raw) < 0.01:
		return data
	var fixed := data.duplicate()
	fixed["boatPark"] = [legal.x, float(data.boatPark[1]), legal.y]
	return fixed


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


## 水面接触轮廓：区块内的地形靠岸线图（几何真的跨过水面才有截面），
## 而**漂浮在水平面上方**的结构（甲板底面高出水面几厘米）永远切不出截面，
## 于是整块东西一点白色波纹都没有，读起来像贴纸浮在图上。
##
## 这里把这类结构的占地并进运行时接触矩形（着色器里逐像素算距离，
## 不需要重烘岸线图），与玩家自建木板走同一条通路。
## 数据来源优先用结构自己的水面阻挡矩形（`BlockerSet` 从几何派生的真实轮廓），
## 没有阻挡时退回它的可行走矩形，再取总包围盒。
func _water_shapes(fishery_state: Variant = null) -> Array:
	if not _shore_shapes.is_empty():
		return _shore_shapes + (_fishery_visual.water_shapes(fishery_state) if _fishery_visual != null else [])
	_collect_water_shapes(get_node_or_null("World/Zones"))
	# 区块之外的海上结构物（World/SeaStructures）同样挡船：它们没有 ZoneScene，
	# 但有自己的 BlockerSet 与 rebuild_blockers，这里走同一个入口。
	_collect_water_shapes(get_node_or_null("World/SeaStructures"))
	var env: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/baked/shore_environment.json"))
	if env is Dictionary and env.has("shapes"):
		_shore_shapes.append_array(env.shapes)
	if _shore_shapes.is_empty():
		var legacy: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/baked/shore.json"))
		if legacy is Dictionary and legacy.has("shapes"):
			_shore_shapes = legacy.shapes
	return _shore_shapes + (_fishery_visual.water_shapes(fishery_state) if _fishery_visual != null else [])


## 把一棵子树里每个带 rebuild_blockers 的节点派生成的水面矩形并进 _shore_shapes。
func _collect_water_shapes(root: Node) -> void:
	if root == null:
		return
	for item in root.get_children():
		if not item.has_method("rebuild_blockers"):
			continue
		item.rebuild_blockers(WATER_LEVEL, 1.6)
		var rects: Array = item.water_block_rects
		for r in rects:
			_shore_shapes.append({"x": (r as Rect2).get_center().x,
				"z": (r as Rect2).get_center().y,
				"hx": (r as Rect2).size.x * 0.5, "hz": (r as Rect2).size.y * 0.5,
				"round": false})


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

func _physics_process(delta: float) -> void:
	if _title_active or sleep_cycle.busy or (dive != null and dive.switching) or actor_controller.actor == null: return
	_update_keyboard_move(delta)
	_update_walk(delta)


## ---- 键盘移动（SEA-MOVE-R20 / SEA-NAV-R15）---------------------------------
##
## 键位在代码里注册（同 `Interactor.ensure_input_map`）：project.godot 的
## InputEvent 序列化对版本敏感，旧工程/旧档不该因为缺动作就整个人不能走。
## WASD 与方向键指向同一组动作，两者都能用；不兼容「方向键移镜头」的旧行为。
const MOVE_KEYS := {
	"move_left":[KEY_A, KEY_LEFT],
	"move_right":[KEY_D, KEY_RIGHT],
	"move_forward":[KEY_W, KEY_UP],
	"move_back":[KEY_S, KEY_DOWN]}

func ensure_move_keys() -> void:
	for action in MOVE_KEYS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in MOVE_KEYS[action]:
			var exists := false
			for event in InputMap.action_get_events(action):
				if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
					exists = true
					break
			if exists:
				continue
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action, key)


## 屏幕相对方向：镜头朝向就是「上」。俯角再大也不影响，前向先投影到水平面。
func _camera_relative(axis: Vector2) -> Vector3:
	if axis.length_squared() < 0.000001 or cam == null:
		return Vector3.ZERO
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	return (right * axis.x + forward * -axis.y).normalized()


## 每物理帧把「按键」折成世界方向，分派给角色或船。
##
## 面板打开/过场/模态时整体不读键：方向键在背包页里是选格子，不是走路。
func _update_keyboard_move(delta: float) -> void:
	_boat_key_left = maxf(0.0, _boat_key_left - maxf(delta, 0.0))
	var axis := Vector2.ZERO
	# 建造/拆除模式里左右方向键是「换件/换层」，不驱动角色；那边仍用点击走位。
	var building_busy: bool = building_controller != null and building_controller.active
	if not input_blocked() and not building_busy:
		axis = Input.get_vector("move_left","move_right","move_forward","move_back")
	var world := _camera_relative(axis)
	var mode := actor_controller.mode()
	if mode == 0:
		if actor_controller.climbing():
			actor_controller.set_move_intent(Vector3.ZERO)
			actor_controller.set_sprint_held(false)
			return
		# Shift 只在岸上自由行走生效；小跑是同一套物理步进的轻微提速，
		# 面板/过场已在 input_blocked() 里统一挡住，不会穿透到世界。
		actor_controller.set_move_intent(world)
		# 先让 set_move_intent 进入 strolling，再写入 Shift；否则从站立
		# 起步的第一帧会因为状态还没切换而丢掉小跑意图。
		actor_controller.set_sprint_held(axis != Vector2.ZERO and Input.is_physical_key_pressed(KEY_SHIFT))
		return
	actor_controller.set_sprint_held(false)
	if boat == null or (dive != null and dive.active):
		return
	if mode == 1 or mode == 2:
		if axis == Vector2.ZERO:
			boat.release_drive()
			# 松手滑行停稳后回到「船上待机」：HUD 与交互都以 mode 为准，
			# 挂在 SAILING 会让船明明停了还显示在航行。
			if mode == 2 and not boat.driving() and not boat.starts_sailing():
				actor_controller.request_mode(GameState.Mode.ON_BOAT)
			return
		# 泊位里朝岸按方向键 = 想下船（SEA-MOVE-R24）。
		#
		# 这一段以前是空着的：靠好岸以后按 ↓，船头会顶着岸线往前挤 0.7 米，
		# 抛一句「前方靠岸过近」，同时船离开了泊位 —— 于是 E 也不认了，
		# 想上岸还得先把船划回来。玩家的原话是「靠岸后操作很不舒服，往下没法往下挪」。
		# 判据见 `_key_intent_is_toward_shore`：朝向陆地一侧，或者前方一步就撞岸。
		if not boat.driving() and _landing_is_docked() and _key_intent_is_toward_shore(world):
			boat.release_drive()
			_ashore_on_arrival = false
			if _step_ashore():
				_boat_key_left = BOAT_KEY_COOLDOWN
				hud.toast("上岸了")
			return
		if mode == 1:
			actor_controller.request_mode(GameState.Mode.SAILING)
		boat.set_drive(Vector2(world.x, world.z))

## 近距交互的**唯一仲裁**：图标画什么、点下去执行什么，都读这一个结果。
##
## 拆成两个函数是 2026-11-07 那类 bug 的温床（图标说「上岸」、点下去在采集）。
## 返回 {"kind": ..., "node": ...}；kind 只有五种：
##   boat_board —— 岸上船边，点击上船
##   boat_leave —— 船上泊位，点击靠妥并上岸
##   dock       —— 水面泊位热区，点击开过去靠岸并上岸
##   spot       —— 世界交互物（采集点 / 菜箱 / 出货箱 / 房门 …）
##   pick       —— 海面漂流物 / 鱼群（仅 `near` 时进入仲裁：图标 = 已进判定区）
##
## `pick` 的 `near` 门槛只管**图标**：够不着的时候不出「点它就捞」的图标，
## 否则等于告诉玩家「现在点能捞」却要开船过去。热区外按 E 仍然会划过去捞，
## 那是 `_press_boat_key()` 的赶路兜底，文案由 `_boat_shortcut_text()` 同步兜底。
func _near_action() -> Dictionary:
	if hover == null or hud == null or input_blocked():
		return {}
	if building_controller != null and building_controller.active:
		return {}
	# 交互焦点是上下船仲裁的对手方。它每 0.12 秒才重扫一次，而这里可能正好
	# 落在两次扫描之间（菜单刚关、过场刚结束）—— 那时 target 还是 null，
	# `_boat_key_action()` 会以为「旁边没有可操作的东西」而直接判上船。
	# 先同步要一次最新焦点，保证图标/按键和玩家眼睛看到的一致。
	if interactor != null and interactor.active and not is_instance_valid(interactor.target):
		interactor.refresh_now()
	# 上下船与泊位先排：它们和交互物是同一次仲裁（谁赢 E 谁出图标）。
	var boat_action := _boat_key_action()
	if boat_action != "":
		if boat_action == "leave":
			var landing := _current_landing()
			if landing != null:
				return {"kind": "boat_leave", "node": landing}
		elif is_instance_valid(boat):
			return {"kind": "boat_board", "node": boat}
	if interactor.active and is_instance_valid(interactor.target):
		return {"kind": "spot", "node": interactor.target}
	var pick := _sea_pick_candidate()
	if not pick.is_empty() and bool(pick.get("near", false)):
		var item: Dictionary = pick.item
		var root: Node3D = item.get("root")
		if is_instance_valid(root):
			return {"kind": "pick", "node": root, "pick": pick}
	var dock := _near_landing_key()
	if not dock.is_empty():
		var point: Node3D = _zone_nodes[str(dock.zone)].landing_point(str(dock.landing))
		if point != null:
			return {"kind": "dock", "node": point, "dock": dock}
	return {}


## 上一帧近距仲裁的结果，供码头标记让位使用（见 `_marker_suppressed`）。
##
## 不在这里保存会重复算一次 `_near_action()`：它带寻路缓存、还会顺手刷新
## 交互目标，每帧多调一次没有意义，也容易引入「谁先算」的不确定性。
var _near_kind := ""
var _near_landing_id := ""

## 只在玩家已接近、输入可用时出现原悬停图标，不显示教程或按键说明。
##
## 图标 = 「这里现在能操作」的唯一提示，所以**每一个可执行的入口都要出图标**：
## 岸上贴着船、船上开进泊位、站在采集点旁、海面上够得着漂流物。缺了哪一处，
## 玩家就只会读到「东西在那儿但我点不动」。
func _update_near_interaction(arbitrated: Variant = null) -> void:
	if hover == null:
		return
	var action: Dictionary = _near_action() if arbitrated == null else arbitrated
	_near_kind = str(action.get("kind", ""))
	_near_landing_id = str(action.get("dock", {}).get("landing", ""))
	if action.is_empty():
		hover.hide_near_focus()
		return
	var kind := str(action.get("kind", ""))
	var node: Node3D = action.get("node")
	match kind:
		"boat_board":
			# 图标贴在船上：点击即上船。
			hover.keyboard_focus = node
			hover.show_near_action(node.global_position + Vector3.UP * 1.05, "anchor")
		"boat_leave":
			# 图标贴在落脚的岸边：点击即靠妥并上岸。
			hover.keyboard_focus = node
			hover.show_near_action(node.stand_position() + Vector3.UP * 0.55, "anchor")
		"dock":
			# 图标贴在水面泊位锚点：点击即开过去靠岸并上岸。
			var dock: Dictionary = action.get("dock", {})
			var data: Dictionary = _landing_data(str(dock.get("zone", "")), str(dock.get("landing", "")))
			var at: Vector3 = node.stand_position()
			if not data.is_empty():
				at = Vector3(float(data.boatPark[0]), WATER_LEVEL + 0.35, float(data.boatPark[2]))
			hover.keyboard_focus = node
			hover.show_near_action(at, "anchor")
		"pick":
			hover.keyboard_focus = node
			hover.show_near_action(node.global_position + Vector3.UP * 0.5,
				"fish" if str(action.get("pick", {}).get("type", "")) == "fish" else "hand")
		"spot":
			hover.show_near_focus(node, interactor.progress())
		_:
			hover.hide_near_focus()

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
	# 区块之外的海上结构也要有吃水线（SEA-OCEAN-R23）。
	#
	# `World/SeaStructures` 里的东西没有 ZoneScene：船的水面阻挡早就单独收集了
	# （`_water_shapes()`），但岸线图只扫 zone 根节点 —— 于是「船知道这块东西
	# 存在，水却不知道」。新加进去的模型因此一点白色波纹都没有，在水面上像贴纸。
	#
	# 这里不能只把根节点塞进 `shore_roots`：漂浮结构是**整块浮在水平面上方**的
	# （甲板底面高出水面几厘米），竖直方向没有任何面跨过水面，几何切片切不出东西
	# （实测：塞进去之后切面反而从 9950 降到 2978）。所以改成把它的占地轮廓
	# 作为显式种子交给距线图，与几何截面走同一张图、同一套泡沫。
	var structures := get_node_or_null("World/SeaStructures")
	var outlines: Array = []
	if structures != null:
		for item in structures.get_children():
			outlines.append_array(_structure_outline(item))
		var extent := _subtree_xz_bounds(structures)
		if extent.has_area(): shore_region = shore_region.merge(extent)
	water_node.rebuild_shoreline(shore_roots,shore_region,outlines)


## 一个海上结构在水面处的占地轮廓（世界 XZ）。
##
## 优先用 `BlockerSet` 从几何派生的阶梯条带（真实外沿，随模型替换与旋转跟随）；
## 还没派生过就现算一次；结构没有可派生几何时退回它的可行走矩形（环廊贴着甲板边）。
func _structure_outline(item: Node) -> Array:
	var blocks: Array = item.get("water_block_rects") if "water_block_rects" in item else []
	if blocks.is_empty() and item.has_method("rebuild_blockers"):
		item.rebuild_blockers(WATER_LEVEL,1.6)
		blocks = item.get("water_block_rects") if "water_block_rects" in item else []
	var result: Array = []
	for rect: Rect2 in blocks: result.append(rect)
	if not result.is_empty(): return result
	var stack: Array = [item]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if "rects" in node and node.get("rects") is Array:
			var offset: Vector3 = (node as Node3D).global_position
			for rect: Rect2 in node.get("rects"):
				result.append(Rect2(Vector2(rect.position.x+offset.x,rect.position.y+offset.z),rect.size))
		stack.append_array(node.get_children())
	return result


## 一棵子树里所有可见网格的世界 XZ 包围盒。只用来定岸线取样范围。
func _subtree_xz_bounds(root: Node) -> Rect2:
	var result := Rect2()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and not (node as Node3D).is_visible_in_tree(): continue
		var box := AABB()
		var has := false
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			box = (node as Node3D).global_transform * (node as MeshInstance3D).get_aabb()
			has = true
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			box = (node as Node3D).global_transform * (node as MultiMeshInstance3D).get_aabb()
			has = true
		if has:
			var part := Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
			result = part if first else result.merge(part)
			first = false
		stack.append_array(node.get_children())
	return result


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
		# 手动划行撞住时，Boat 会保留方向盘，让玩家继续转头脱困；
		# 这里不能把状态切回 boat_idle，否则又会吃掉这次修复。
		if boat.driving():
			if hud != null: hud.toast("前方是岸")
			return
		_cancel_pending_pick()
		_ashore_on_arrival = false
		actor_controller.request_mode(GameState.Mode.ON_BOAT)
		player.set_rowing(false)
		if ribbon != null:
			ribbon.clear()
		if hud != null:
			# 自动航行撞阻挡才回到待机；手动驾驶不在这里结束。
			hud.toast("前方是岸" if not _near_landing_key().is_empty()
				else "前方靠岸过近，请重新选择航路"))
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
	# 海鸥只在 06:00–18:00 出现（SEA-AMBIENT-R05）。小时从唯一时钟读，
	# 鸟群自己不记时间；读档/睡觉/跨日都走同一条 `changed` 通道。
	var hour := float(world_clock.query().get("hour", 12.0))
	for node in find_children("*", "Node", true, false):
		if node.has_method("set_hour") and node.get_script() == GullFlockScript:
			node.set_hour(hour)
			var gullclock: Callable = func(snapshot: Dictionary, flock: Node) -> void:
				if is_instance_valid(flock): flock.set_hour(float(snapshot.get("hour", 12.0)))
			world_clock.changed.connect(gullclock.bind(node))
	world_clock.changed.connect(func(snapshot: Dictionary) -> void:
		bird_root.set_hour(float(snapshot.get("hour", 12.0))))
	bird_root.set_hour(hour)


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
	markers.suppress_query = _marker_suppressed
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
	var l: Dictionary = _landing_data(zone_id, landing_id)
	if l.is_empty():
		return fallback
	var park := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	# starts_sailing() 不在 Node3D 基类上：不显式写 bool，整条表达式会退化成
	# Variant，Godot 推不出类型直接报解析错误，整个 main.gd 加载不了。
	var sailing: bool = boat.starts_sailing()
	if sailing or boat.position.distance_to(park) > DOCK_SETTLE_TOLERANCE:
		return fallback
	# 抬到船舱上方，和 dockEdge 的 +0.55 观感一致，不被船体挡住。
	return boat.global_position + Vector3.UP * 1.35


## 码头锚点标记要不要给近距图标让位。
##
## 岸上船停在泊位时，标记会被 `_landing_icon_world` 挂到船上；新的上船图标也
## 贴在同一艘船上 —— 两个 teal 圆圈叠在一起，读起来像渲染重影。此时只留近距
## 图标（它带「现在按 E 就上船」的语境），标记让位。
##
## 反过来不行：标记是常驻路标，近距图标只在热区里出现，让标记消失会让远处
## 的玩家找不到船。所以只在这一档让位。
func _marker_suppressed(zone_id: String, landing_id: String) -> bool:
	if _near_kind != "boat_board":
		return false
	return zone_id == GameState.current_zone and landing_id == GameState.landing_id


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
	var l: Dictionary = _landing_data(GameState.current_zone, GameState.landing_id)
	if l.is_empty():
		return false
	var park := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	var sailing: bool = boat.starts_sailing()
	if sailing or boat.position.distance_to(park) > DOCK_SETTLE_TOLERANCE:
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
		player.position = boat.boarding_position()
	player.build()
	player.scale = Vector3(1.0, 1.0, 1.0)
	player.set_rowing(true)
	# 交互探测器跟着人走：它只认世界里的 Interactable，与相机/屏幕无关。
	interactor = InteractorScript.new()
	interactor.name = "Interactor"
	interactor.active = false
	player.add_child(interactor)


## 世界里的采集点：从 assets/data/gather_spots.json 生成，坐标是与区块同一套世界坐标。
func _setup_sunroom() -> void:
	var zone: Node = _zone_nodes.get("zone1")
	if zone == null:
		return
	sunroom_surface = zone.get_node_or_null("Models/太阳能木屋/太阳能木屋-海上区域") as Node3D
	if sunroom_surface == null:
		return
	# Runtime helpers live under the existing VegetationTurf child so the four
	# semantic surface modules remain the scene's only direct children.
	var runtime_parent: Node3D = sunroom_surface.get_node_or_null("前部倾斜太阳能房") as Node3D
	if runtime_parent == null:
		runtime_parent = sunroom_surface
	sunroom_view = _ensure_sunroom_runtime_node(runtime_parent, "SunroomView", "res://src/facilities/sunroom_view.gd")
	if sunroom_view != null and sunroom_view.has_method("configure"):
		sunroom_view.configure(sunroom_surface)
	var refresh := func() -> void: _apply_sunroom_state()
	# 端点和交互锚点由阳光房场景保存；Bootstrap 只负责注入状态服务与角色命令。
	# 这样用户调整太阳房实例/楼板时，不会留下一套脱离场景的隐形坐标。
	var repair_anchor := runtime_parent.get_node_or_null("SunroomRepairAnchor") as Node3D
	var bottom_anchor := runtime_parent.get_node_or_null("SunroomLadderBottomAnchor") as Node3D
	var top_anchor := runtime_parent.get_node_or_null("SunroomLadderTopAnchor") as Node3D
	var upper_anchor := runtime_parent.get_node_or_null("SunroomUpperRestoreAnchor") as Node3D
	var damage_anchor := runtime_parent.get_node_or_null("SunroomDamageAnchor") as Node3D
	if repair_anchor == null or bottom_anchor == null or top_anchor == null or upper_anchor == null or damage_anchor == null:
		push_error("solar_cabin_surface 缺少阳光房玩法锚点")
		return
	var repair: Node = _ensure_sunroom_runtime_node(runtime_parent, "SunroomRepair", "res://src/facilities/sunroom_repair_interactable.gd")
	if repair != null and repair.has_method("configure"):
		repair.position = repair_anchor.position
		repair.configure(Economy.sunroom, refresh)
	var upper: Node = _ensure_sunroom_runtime_node(runtime_parent, "SunroomUpperRestore", "res://src/facilities/sunroom_upper_interactable.gd")
	if upper != null and upper.has_method("configure"):
		upper.position = upper_anchor.position
		upper.configure(Economy.sunroom, refresh)
	var bottom: Node = _ensure_sunroom_runtime_node(runtime_parent, "SunroomLadderBottom", "res://src/facilities/sunroom_ladder_interactable.gd")
	var top: Node = _ensure_sunroom_runtime_node(runtime_parent, "SunroomLadderTop", "res://src/facilities/sunroom_ladder_interactable.gd")
	var damage: Node = _ensure_sunroom_runtime_node(runtime_parent, "SunroomDamage", "res://src/facilities/sunroom_damage_visual.gd")
	if damage != null:
		damage.position = damage_anchor.position
	var base: Vector3 = bottom_anchor.global_position
	var roof: Vector3 = top_anchor.global_position
	if bottom != null and bottom.has_method("configure"):
		bottom.position = bottom_anchor.position
		bottom.configure(Economy.sunroom, Callable(actor_controller, "climb_ladder"), "up", base, roof)
	if top != null and top.has_method("configure"):
		top.position = top_anchor.position
		top.configure(Economy.sunroom, Callable(actor_controller, "climb_ladder"), "down", base, roof)
	if not Economy.sunroom.changed.is_connected(_apply_sunroom_state):
		Economy.sunroom.changed.connect(_apply_sunroom_state)
	_apply_sunroom_state()

func _ensure_sunroom_runtime_node(parent: Node3D, node_name: String, script_path: String) -> Node3D:
	var existing: Node3D = parent.get_node_or_null(node_name) as Node3D
	if existing != null:
		return existing
	var node := Node3D.new()
	node.name = node_name
	node.set_script(load(script_path))
	parent.add_child(node)
	return node
	Economy.sunroom.changed.connect(_apply_sunroom_state)

func _apply_sunroom_state() -> void:
	if Economy.sunroom == null:
		return
	var day := int(world_clock.day) if world_clock != null else 1
	Economy.sunroom.set_calendar_day(day)
	if sunroom_view != null and sunroom_view.has_method("apply_stage"):
		sunroom_view.apply_stage(Economy.sunroom.stage, Economy.sunroom.season())
	var repair: Node = sunroom_surface.find_child("SunroomRepair", true, false) if sunroom_surface != null else null
	var upper: Node = sunroom_surface.find_child("SunroomUpperRestore", true, false) if sunroom_surface != null else null
	var bottom: Node = sunroom_surface.find_child("SunroomLadderBottom", true, false) if sunroom_surface != null else null
	var top: Node = sunroom_surface.find_child("SunroomLadderTop", true, false) if sunroom_surface != null else null
	for node in [repair, upper, bottom, top]:
		if node == null:
			continue
		if node.has_method("set_sunroom_stage"):
			node.set_sunroom_stage(Economy.sunroom.stage)
		if node == repair:
			node.visible = Economy.sunroom.stage == "ruined"
		elif node == upper:
			node.visible = Economy.sunroom.stage == "ladder_fixed"
		else:
			node.visible = Economy.sunroom.ladder_repaired()
	var damage: Node = sunroom_surface.find_child("SunroomDamage", true, false) if sunroom_surface != null else null
	if damage != null:
		damage.visible = Economy.sunroom.stage == "ruined"
	var lower: Variant = _zone_nodes.get("zone1")
	if lower != null:
		for area in lower.walk_areas:
			if str(area.area_id) == "sunroom_upper_deck":
				var was_active: bool = bool(area.active)
				area.active = Economy.sunroom.upper_restored()
				if area.active != was_active:
					lower.rebuild_ground()

func _setup_gather() -> void:
	gather = get_node_or_null("World/Gameplay/GatherField") as Node3D
	if gather == null:
		gather = GatherFieldScript.new()
		gather.name = "GatherField"
		add_child(gather)
	gather.construction = Economy.construction
	gather.energy_reason = Economy.energy.reason
	# 装配时按场景回算落点高度（SEA-GATHER-R06）：甲板被手工改过之后，
	# gather_spots.json 里的 y 会过期，靠这里自愈。
	gather.zone_query = func(zone_id: String) -> Variant: return _zone_nodes.get(zone_id)
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
	# FarmPlot emits only after a successful business command, including E.
	# One success event owns presentation; starting a hold must not fake a reward.
	if event in ["planted","watered","harvested"]: player.play_farm_action(event,payload)
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
	# 2026-11-06 重新打开。这条提示在「服务口袋」那次改版里被整体关掉了，
	# 理由是菜箱改成点击冒泡菜单、不需要底部条 —— 但采集点、出货箱、房门、
	# 订单板、绞盘都没有冒泡菜单，于是「站在东西前面该按什么」在画面上完全没有提示。
	# 玩家原话：「还有很多交互位置没有 E 键可以用的地方，导致没有鼠标就无法操作」。
	# 现在它只承担一件事：有焦点时显示 `E 动作 · 名称` + 按住进度。
	# 近距交互改为原悬停图标；底部文字操作说明不再显示。
	prompt.enabled = false
	interactor.target_changed.connect(prompt.focus_changed)
	prompt.action_requested.connect(func() -> void:
		if interactor.target != null: _approach(interactor.target))
	if interactor != null:
		interactor.blocked.connect(func(reason: String) -> void:
			_auto_target = null
			interactor.auto_hold = false
			hud.toast(reason)
			if prompt != null:
				prompt.flash_blocked(reason))
		# 自动接近的流程里，动作一旦成功就不要再按着 E（否则会连采同一个点）。
		interactor.completed.connect(func(_spot: Node3D, _reward: Dictionary) -> void:
			# 展开选择不是成功结算，不能提前播放“完成啦”。
			if str(_reward.get("event", "")) != "options": prompt.celebrate()
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
		trade_board.opened.connect(_open_fishery_construction)

	if trade_board != null: trade_board.order_model = null
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
	_bind_supply_counter()
	var fishery_zone: Node3D = _zone_nodes.get("zone1")
	_fishery_visual = fishery_zone.get_node("Models/WildFishery")
	_fishery_visual.configure(fishery_zone,fishery_zone.get_node("WalkAreas/Walk_zone1_salvage"),fishery_zone.get_node("Models/绞盘打捞台/salvage_station/绞盘打捞台-海上区域-01_001"),water_node)
	_fishery_visual.projection_changed.connect(_on_fishery_projection_changed)
	_fishery_schools = fishery_zone.get_node("FisherySchools")
	for school in _fishery_schools.get_children(): school.set_water(water_node)
	_fishery_harvest = fishery_zone.get_node("Objects/FisheryHarvest")
	_fishery_harvest.configure(Economy.fishery,_harvest_fishery)
	_fishery_marker = preload("res://src/ui/fishery_marker.gd").new()
	add_child(_fishery_marker)
	_fishery_marker.configure(cam,_fishery_harvest,func() -> Dictionary: return {"pending":Economy.fishery.pending},func() -> bool: return not input_blocked() and not dive.active and not cam.panning)
	_fishery_marker.harvest_requested.connect(_request_fishery_harvest)
	# Upgrade state projects the authored shore and net; no duplicate business owner.
	Economy.fishery.changed.connect(_on_fishery_changed)
	_on_fishery_changed()


## 家园补给站 → 渔场（SEA-AQUA-R04）。只转发一次命令，规则在 FisheryModel。
func _upgrade_fishery() -> Dictionary:
	return Economy.fishery.upgrade()

func _open_fishery_construction(_board: Node3D) -> void:
	if not Economy.fishery.unlocked:
		actor_controller.complete_interaction()
		hud.open_aqua_upgrade(_upgrade_fishery)

func _request_fishery_harvest() -> void:
	if input_blocked(): return
	var reason: String = Economy.fishery.harvest_reason()
	if reason == "": reason = _land_reach_reason(_fishery_harvest)
	if reason != "":
		hud.toast(reason)
		return
	_approach_command(_fishery_harvest,_harvest_fishery)

func _harvest_fishery() -> Dictionary:
	var result: Dictionary = Economy.fishery.harvest()
	if result.has("fish"):
		pickup_progress.receive({"fish":int(result.fish)})
		hud.toast(str(result.message))
	return result

## Upgrade/restore swaps only the authorized surface; the utility pole stays intact.
func _on_fishery_changed() -> void:
	var unlocked: bool = Economy.fishery.unlocked
	if trade_board != null:
		trade_board.visible = not unlocked
		trade_board.label = "渔场 · 待建"
		trade_board.verb = "建造渔场"
	if _fishery_visual != null: _fishery_visual.apply_upgrade(unlocked)
	if _fishery_schools != null: _fishery_schools.visible = unlocked
	if _fishery_harvest != null: _fishery_harvest.refresh()
	if _fishery_marker != null: _fishery_marker.refresh()

func _on_fishery_projection_changed() -> void:
	navigation.invalidate()
	Zones.bind_scene(_zone_nodes.zone1)
	_reach_cache.clear()
	if props != null:
		props.ocean.invalidate()
		props.sync_population(world_clock.query(),boat.position)


## 海上补给站：正面招牌下的交互点 → 打开补给页。
##
## 只做「把点击接到已有的商店页」这一件事：种子价格来自 Crop 定义、
## 土壤价格来自 material_shop，扣钱与库存检查走 Farm / Inventory 的公开端口。
## 这里不持有一份商品表，也不新增数值。
func _bind_supply_counter() -> void:
	var shop: Node = _zone_nodes.get("sea_supply")
	if shop == null:
		return
	if shop.has_method("configure_view_subject"):
		var ashore_query := func() -> bool: return actor_controller.mode() == 0
		shop.configure_view_subject(player, ashore_query, cam)
	var counter := shop.get_node_or_null("Objects/SupplyCounter")
	if counter != null and counter.has_signal("opened"):
		counter.opened.connect(_open_supply)


func _open_supply(_counter: Node3D) -> void:
	if shop_panel != null: shop_panel.open_shop("shop_general")
	else: hud.open_tab("shop")


func _open_orders(_board: Node3D) -> void:
	if Scope.minimal():
		shop_panel.open_shop("shop_general")
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
	hud.toast("已下钩")


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
	# 规划器可能把落点抬出岸线缓冲（落点本身压在缓冲里时）：以路径终点为准。
	# 否则 `boat.sail_to` 会把真正的 goal 补在路径末端，船朝一个开不进去的点冲，
	# 最后自己撞停在半路 —— 又一次「明明在这儿却靠不了岸」。
	var end: Vector2 = path[path.size() - 1]
	if Vector2(goal.x, goal.z).distance_to(end) > 0.01:
		goal = Vector3(end.x, WATER_LEVEL, end.y)
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
	hud.world_actions.opened.connect(hover.hide_near_focus)
	# 交互器在 Main 之后更新焦点，同帧刷新图标，避免菜单关闭时落后一帧。
	interactor.target_changed.connect(func(_spot): _update_near_interaction())
	interactor.progress_changed.connect(func(ratio: float):
		if ratio <= 0.0 and hover._near_progress != null: hover._near_progress.hide())
	hover.near_requested.connect(_activate_near_action)
	# 走不到的目标不给悬停图标、不改指针 —— 有图标就等于「这里能点」，
	# 玩家点了却弹不出东西，只会觉得界面坏了。判定与点击提示共用同一个函数。
	hover.reach_gate = _land_reach_reason


## 点近距图标：读 `_near_action()` 的同一份仲裁结果，绝不另判一次。
##
## 以前这里写的是 `if _boat_key_action() == "board": ... elif 交互物: ...`，
## 于是「船上·泊位」这一支（boat_action == "leave"）掉进了 else 分支，
## 点图标走的是海面打捞判定 —— 玩家在泊位点「上岸」图标，船却在捞东西。
func _activate_near_action() -> void:
	if hud != null and hud.world_actions != null and hud.world_actions.is_open():
		return
	var action := _near_action()
	if action.is_empty():
		return
	match str(action.get("kind", "")):
		"boat_board", "boat_leave":
			_toggle_boat_by_key()
		"dock":
			var dock: Dictionary = action.get("dock", {})
			_select_landing({"zone": str(dock.get("zone", "")), "landing": str(dock.get("landing", ""))})
		"pick":
			_press_sea_pick(action.get("pick", {}))
		"spot":
			_open_spot_bubbles(action.get("node"))


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
	# 面板的「测试」页（SEA-TOOL）不会自己去摸 Economy / 世界时间 / 天气 ——
	# 那几个状态各有所有者，测试工具只拿到一份端口。缺哪个，页面就把那一组禁用。
	grade.set_test_ports({
		"catalog": Callable(self, "_debug_catalog"),
		"count": func(id: String) -> int: return Economy.count(id),
		"give": func(amounts: Dictionary) -> void: Economy.give(amounts),
		"clock": func() -> Dictionary: return world_clock.query(),
		"set_time": Callable(self, "_debug_set_clock"),
		"weather": func() -> String: return weather_service.kind,
		"set_weather": func(kind: String) -> bool: return weather_service.set_weather(kind),
		"energy": func() -> Dictionary: return {"current": Economy.energy.current, "maximum": Economy.energy.maximum},
		"refill_energy": func() -> void: Economy.energy.refill(),
	})


## 测试页的可加物品清单。直接读物品表，不另立一份「测试专用资源列表」——
## 表里加了新物品，这一页下次打开就有了。
func _debug_catalog() -> Array:
	var rows := []
	for id in ItemDB.all_ids():
		var item: Dictionary = ItemDB.get_item(id)
		rows.append({"id": str(id), "label": str(item.get("label", id))})
	return rows


## 测试页的时间入口（SEA-TOOL-R03）。
##
## 只改 WorldClock 已经存在的两个公开字段，然后照常广播一次变化事件 ——
## 07:00 晨次结算、HUD 日历、昼夜与天气表现都由原来的订阅者接着处理。
## 这里**没有**第二条时间实现，也没有新增存档字段：存档照旧从 clock 取快照。
func _debug_set_clock(day: int, seconds: float) -> void:
	var next_day := maxi(1, day)
	var next_seconds := fposmod(seconds, 86400.0)
	var jumped: bool = next_day != int(world_clock.day)
	world_clock.day = next_day
	world_clock.seconds = next_seconds
	if jumped:
		world_clock.day_changed.emit(next_day)
	world_clock.changed.emit(world_clock.query())


func _setup_props() -> void:
	props = get_node_or_null("World/Gameplay/SeaProps") as Node3D
	if props == null:
		props = PropsScript.new()
		props.name = "SeaProps"
		add_child(props)
	props.water_surface = water_node
	props.water_point_clear = func(p: Vector2) -> bool: return navigation.is_open_water(p.x, p.y)
	props.zones = Zones
	props.give_resource = Economy.add_resource
	props.can_receive = Economy.inventory.can_add
	props.blocked.connect(func(reason: String): hud.toast(reason))
	if Scope.minimal():
		props.crate_count = 6
		props.planks_only = true
		props.school_count = 4
	props.ocean_enabled = true
	props.build()
	props.sync_population(world_clock.query(),boat.position)
	props.collected.connect(_on_crate_collected)
	props.fish_collected.connect(_on_fish_collected)


## 海上拾取的进度条与成功收获浮层：角色头顶，停稳后才打捞。
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


## 海面只装配稳定会话所有者；海底PackedScene按来源海域真正切换，不常驻几何。
func _setup_dive() -> void:
	dive = DiveSession.new()
	dive.name = "DiveSession"
	add_child(dive)
	dive.configure(self)
	dive.give_resource = Economy.add_resource
	dive.give_rewards = Economy.inventory.add_all
	dive.source_query = _dive_source_at
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
	# 地图上的「你」要真实世界坐标，不能拿区块中心糊弄：船开到两块之间时中心环会撒谎。
	hud.player_query = func() -> Dictionary:
		if player == null: return {}
		return {"zone":GameState.current_zone,"position":player.global_position}
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
	# 体力条（SEA-ENERGY）：右下角常驻，体力每次变动直接推给角标 HUD。
	Economy.energy.changed.connect(func(current: float, maximum: float) -> void:
		hud.corner.set_stamina(current, maximum))
	hud.corner.set_stamina(Economy.energy.current, Economy.energy.maximum)
	Economy.energy.tired.connect(func() -> void:
		hud.toast("有点累了 · 回家睡一觉会好起来", 3.0))
	Economy.energy.exhausted.connect(_on_energy_exhausted)


## 所有按钮和快捷键共享命令入口，取消不留下待执行动作。
func _cancel_action() -> void:
	if hud != null: hud.world_actions.close(true)
	actor_controller.cancel()
	_cancel_pending_pick()
	_ashore_on_arrival = false
	if dive.active: dive.cancel_navigation()
	if ribbon != null: ribbon.clear()
	hud.toast("已停止")

func _on_click_command(command: String) -> void:
	if _title_active or (sleep_cycle != null and sleep_cycle.busy): return
	if building_controller!=null and building_controller.active and command not in ["craft","save"]: building_controller.close()
	if not Scope.command_enabled(command): return
	if command != "cancel" and (salvage_panel.is_open() or order_panel.is_open()):
		hud.toast("请先关闭当前操作面板")
		return
	match command:
		"building_workshop":
			if workshop_host != null:
				var opened: Dictionary = workshop_host.open()
				if not opened.get("ok", false): hud.toast(str(opened.get("reason", "当前状态不允许打开楼房工坊")))
		"craft":
			cam_panel.set_open(false);grade.set_open(false);building_controller.open()
		"follow":
			cam.resume_follow()
			hud.toast("镜头跟随角色")
		"close":
			if hud.is_panel_open(): hud.toggle_panel()
		"shop":
			shop_panel.open_shop("shop_general")
		"bag", "notes", "plant", "build", "storage", "shipping":
			_auto_target = null
			interactor.auto_hold = false
			cam_panel.set_open(false)
			grade.set_open(false)
			hud.open_tab(command)
		"cancel":
			if salvage_panel.is_open(): salvage_panel.cancel()
			elif order_panel.is_open(): order_panel.set_open(false)
			else: _cancel_action()
		"room_exit":
			if room_service.inside:
				actor_controller.cancel()
				interactor.require_release()
				hover.hide_near_focus()
				room_controller.exit()
		"save": save_game()
		"load":
			_cancel_action()
			load_game()
		"reset":
			# 确认页由暂停菜单负责；走到这里已经是「确认过」的那一次点击。
			_cancel_action()
			var result := reset_save()
			if result.get("ok",false):
				_begin_title()
				start_screen.root_control.hide()
				_enter_game()
		"appearance":
			_begin_avatar_edit()
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
	if not _sail_to_landing(_landing_data(zone_id, "main"), zone_id, "main"):
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
	if hud.narrative_active():
		_world_press=false
		return
	if workshop_host != null and workshop_host.is_open():
		_world_press = false
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
	# 世界操作气泡打开时，键位全部归它（SEA-INTERACT-R17）。
	#
	# 菜箱、出货箱、渔场这类目标按 E 只弹出气泡菜单；菜单本身原来只能用鼠标点，
	# 于是「键盘玩家站在菜箱前，除了走开什么也做不了」。
	# 现在：数字 1…9 直接选对应项，E 选第一个可用项，ESC 关掉。
	# 这里必须**先于**上下船/打捞分支返回，否则按 E 会同时触发「气泡确认」和「上岸」。
	if hud.world_actions != null and hud.world_actions.is_open():
		if hud.world_actions.handle_key(event):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var bubble_key := (event as InputEventKey).physical_keycode
			if bubble_key == KEY_ESCAPE:
				hud.world_actions.close()
				get_viewport().set_input_as_handled()
				return
			if bubble_key == KEY_E:
				if not hud.world_actions.press_default():
					hud.toast("这一格现在做不了什么")
				get_viewport().set_input_as_handled()
				return
			var slot: int = int(hud.world_actions.index_for_key(bubble_key))
			if slot >= 0:
				hud.world_actions.activate(slot)
				get_viewport().set_input_as_handled()
				return
		return
	if event is InputEventKey and event.pressed and not event.echo and not input_blocked():
		var world_key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if world_key == KEY_X and room_service.inside:
			_on_click_command("room_exit")
			get_viewport().set_input_as_handled()
			return
		if world_key == KEY_K:
			building_controller.open_keyboard()
			get_viewport().set_input_as_handled()
			return
		if world_key == KEY_Q and actor_controller.mode() == 0:
			if interactor.cycle_target(-1 if event.shift_pressed else 1):
				if prompt != null: prompt._finish_left = 0.0
			else: hud.toast("附近没有可操作物件")
			get_viewport().set_input_as_handled()
			return
		if world_key == KEY_F:
			cam.restore_follow(player)
			hud.toast("镜头已回到角色")
			get_viewport().set_input_as_handled()
			return
	# E：上下船 / 海面打捞（SEA-INTERACT-R13 / R15）。有交互焦点时不抢 —— 那时 E 是采集。
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_E:
		if _press_boat_key():
			get_viewport().set_input_as_handled()
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
			# 在屋里：只认房间里的东西（家具/床/门）。海上的漂流物、登陆点、
			# 船、水面航行全部不参与 —— 屋里没有一片海，点了也不该有反应。
			if room_service.inside:
				if _try_walk(mb.position):
					return
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
			if actor_controller.mode()!=0 and building_access!=null:
				var built_landing: Dictionary=building_access.pick_landing(mb.position)
				if not built_landing.is_empty():
					_select_landing(built_landing);return
			# 先看点在不在甲板上（走），不在就当作「点水面划船」。
			if _try_walk(mb.position):
				return
			if _try_sail_to(mb.position):
				return


## 点登陆标记 / 键盘靠岸：在船与岸之间来回。
##
## 一个标记承担两个方向，用「角色现在在哪」决定，而不是再分两个按钮：
##   · 已经在岸上 → 走回泊位、上船（"坐在船上"）；
##   · 已经在船上且就在这个泊位 → 上岸；
##   · 船还没停到这个泊位（含别的区块）→ 开过去，**靠妥后自动上岸**。
## 第三种是本次改动的重点：以前开到就跑完了，玩家还得再点一次标记。
##
## **2026-11-09 补「已经在旁边」这一档**（主人：「我明明停在这里，标记都出来了，
## 按 E 却说无法到达」）。键盘划船不走航线网格，船可以贴到岸线 0.9 m 缓冲以内；
## 而旧实现只认「身份 + 1.6 m」才算靠妥，于是键盘划回来的船身份还是上一个泊位，
## 掉进规划分支、规划又因起点在缓冲里失败，弹出「无法到达该泊位」。
## 现在：船没在航行、就在 park 的 `DOCK_ADOPT_TOLERANCE` 内、且直线能滑到位 ——
## 认领这个泊位的身份并直着滑进去，**不寻路**，也就不会有这句谎话。
const DOCK_ADOPT_TOLERANCE := 3.0

func _select_landing(hit: Dictionary) -> void:
	var zone_id: String = hit.zone
	var landing_id: String = hit.landing
	var selected: Dictionary = _landing_data(zone_id,landing_id)
	if selected.is_empty(): return
	var park := Vector3(float(selected.boatPark[0]),WATER_LEVEL,float(selected.boatPark[2]))
	# 显式写 bool：boat 声明为 Node3D，starts_sailing() 不在基类上，
	# 这里一旦用 `:=`，整条表达式就是 Variant，Godot 推不出类型会直接报解析错误，
	# 而 main.gd 解析失败会让整个游戏加载不了。2026-10-28 改鲸的场景后重导入时踩到过。
	var sailing: bool = boat.starts_sailing()
	var reach := boat.position.distance_to(park)
	var docked: bool = zone_id == GameState.current_zone and landing_id == GameState.landing_id \
		and not sailing and reach < DOCK_SETTLE_TOLERANCE
	if docked:
		if GameState.mode == GameState.Mode.ASHORE:
			_ashore_on_arrival = false
			_depart(func() -> void: hud.toast("上船了"))
		else:
			_ashore_on_arrival = false
			_step_ashore()
		return
	if not Zones.is_unlocked(zone_id):
		hud.toast("远海街町需要先升级船只")
		return
	# 已经贴着这个泊位：认领身份 + 最后一小段直着滑进去，不走路径规划。
	if not sailing and reach <= DOCK_ADOPT_TOLERANCE and _park_glide_clear(park):
		GameState.landing_id = landing_id
		GameState.enter_zone(zone_id)
		_ashore_on_arrival = true
		var yaw := float(selected.get("boatYaw", boat.rotation.y))
		_depart(func() -> void:
			boat.sail_to(park, yaw, zone_id, landing_id, [])
			actor_controller.request_mode(GameState.Mode.SAILING)
			markers.set_highlight(zone_id))
		return
	if not _sail_to_landing(selected, zone_id, landing_id, true):
		return
	# 同上：目标水纹由 ribbon 负责，不再额外放一圈落点环。


## 「最后一小段能不能直着滑进泊位」——只看物理水面，不看航线网格。
##
## 起点可能就在缓冲里（船贴着码头停），所以先抬到最近的开阔水再判线段，
## 抬不出去（离岸超过 2.6 m）视为不能滑，交回正常规划。
func _park_glide_clear(park: Vector3) -> bool:
	if navigation == null: return false
	var from: Variant = navigation.nearest_open_water(boat.position.x, boat.position.z)
	if from == null: return false
	return navigation.segment_clear(from, Vector2(park.x, park.z))


## 靠泊后上岸的唯一入口：站在泊位上走过去，到位即 ashore_idle。
func _step_ashore() -> bool:
	var landing := _current_landing()
	if landing == null: return false
	if not _start_walk(landing.ground(), landing.stand_position()):
		hud.toast("这里上不了岸，请换个登陆点")
		return false
	if reticle != null: reticle.show_at(landing.stand_position())
	return true


## ---- 上下船热区（SEA-INTERACT-R13 / R25，2026-11-07）------------------------
##
## 与点击登陆标记是同一对动作，只是入口从「点图标」换成「走进热区按 E / 点图标」：
##   · 岸上·船边：船停在本泊位，人走进船旁 → 上船；
##   · 水面·泊位：船开进泊位附近的水面 → 靠岸并上岸；
##   · 船上·已靠妥：船已停稳在泊位 → 上岸。
##
## 朝向**不再是**上船的硬门槛。旧规则要求正对船 0.60，背对船哪怕只差一米也上不去，
## 玩家读成「船就在旁边却点不动」。现在它只用于**仲裁**：岸上同时够得着种植格
## 和上船口时，面朝谁就选谁（SEA-INTERACT-R24）。单人单目标时直接可选。
func _boat_key_action() -> String:
	if boat == null or (dive != null and dive.active):
		return ""
	if _title_active or (sleep_cycle != null and sleep_cycle.busy):
		return ""
	if room_controller != null and room_controller.busy:
		return ""
	if _boat_key_left > 0.0:
		return ""
	# 上下船过场进行中：此时 mode 已经先跳到船上，再按一次会被读成「上岸」。
	if actor_controller.machine.current == "boarding":
		return ""
	if not _landing_is_docked():
		return ""
	var mode := actor_controller.mode()
	if mode == 1 or mode == 2:
		return "leave"
	if mode != 0:
		return ""
	var landing := _current_landing()
	if landing == null or not is_instance_valid(actor_controller.actor):
		return ""
	if not _actor_in_boarding_zone(landing):
		return ""
	# 朝向只用于仲裁，不作为门槛：玩家正面对着种植格/出货箱时 E 归它，
	# 其余情况一律上船。差量在 FACING_TIE 以内视为同等正对，此时更近的一方赢
	# —— 也就是「站得离谁近，操作谁」，避免微微一晃就换目标。
	if interactor != null and interactor.active and is_instance_valid(interactor.target):
		var spot: Node3D = interactor.target
		if interactor.keyboard_target == spot: return ""
		var spot_pos: Vector3 = spot.focus_position() if spot.has_method("focus_position") else spot.global_position
		if _actor_facing_alignment(boat.global_position) < _actor_facing_alignment(spot_pos) + FACING_TIE:
			return ""
	return "board"


## 岸上船边热区：站在登陆点旁（去船舱的落点）或贴着船舷，都算「走进船只」。
##
## 为什么两个半径取或：各区块泊位到站立点的距离差别很大（实测 3.6–8.0 米），
## 只按站立点算，「顺着码头走到船边、离站立点 3 米」的玩家会进不了热区；
## 只按船算，则大泊位的站立点在 8 米外同样进不去。
func _actor_in_boarding_zone(landing: Node3D) -> bool:
	var here: Vector3 = actor_controller.actor.global_position
	var stand: Vector3 = landing.stand_position()
	if Vector2(here.x - stand.x, here.z - stand.z).length() <= BOAT_KEY_REACH:
		return true
	if boat == null:
		return false
	return Vector2(here.x - boat.global_position.x, here.z - boat.global_position.z).length() <= BOAT_HULL_REACH

func _actor_facing_alignment(point: Vector3) -> float:
	var body: Node3D = actor_controller.actor
	if not is_instance_valid(body): return -1.0
	var to := Vector3(point.x - body.global_position.x, 0.0, point.z - body.global_position.z)
	if to.length() < 0.00001: return 1.0
	var forward := body.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().dot(to.normalized())


## 泊位里按方向键：这个方向算「往岸上走」吗（SEA-MOVE-R24）。
##
## 两条判据取或：
##   1. 朝登陆点的站立点（±76° 锥内）—— 玩家心里的「往岸那边」；
##   2. 前方 1.4 米就撞岸 —— 兜住登陆点在别处的结构物泊位。
##
## 不只看碰撞：泊位到岸线常有 2–3 米水面，0.5 米的探针探不到，
## 于是「朝岸按」被当成划船，人被船带着飘走，E 也不认泊位了。
## 也不只看朝向：沿岸平划的意图必须仍然能划（锥外的方向照旧走驾驶）。
func _key_intent_is_toward_shore(dir: Vector3) -> bool:
	if boat == null or dir.length_squared() < 0.0001:
		return false
	var landing := _current_landing()
	if landing == null:
		return false
	var to_shore: Vector3 = landing.stand_position() - boat.position
	to_shore.y = 0.0
	if to_shore.length_squared() > 0.0001:
		var dot := Vector3(dir.x, 0.0, dir.z).normalized().dot(to_shore.normalized())
		if dot > 0.25:
			return true
	return boat.would_hit_shore(Vector2(dir.x, dir.z), 1.4)


func _toggle_boat_by_key() -> bool:
	match _boat_key_action():
		"board":
			_ashore_on_arrival = false
			var boarded := _depart(func() -> void: hud.toast("上船了"))
			if boarded:
				_boat_key_left = BOAT_KEY_COOLDOWN
			return boarded
		"leave":
			boat.stop_drive()
			_ashore_on_arrival = false
			var ok := _step_ashore()
			if ok:
				_boat_key_left = BOAT_KEY_COOLDOWN
				hud.toast("上岸了")
			return ok
	return false


## ---- 海面打捞的键盘入口（SEA-INTERACT-R15，2026-11-06）--------------------
##
## 漂流物和鱼群**不是** Interactable：它们要「开船靠过去 → 停稳 → 计时」，
## 所以一直只有鼠标点得到。键盘玩家在海上等于没有手 —— 这是用户原话
## 「比如海上的采集，无法靠近使用 E 键采集」。
##
## 这里只加一个只读查询 + 一个按键分派，动作仍走点击那条链路
## （`_handle_prop_click`）：航线规划、靠过去的停顿、体力、进度条、
## 结算都还是同一份，没有第二条打捞实现。
const SEA_PICK_FAR := 12.0

func _sea_pick_candidate() -> Dictionary:
	if props == null or boat == null:
		return {}
	if dive != null and dive.active:
		return {}
	var mode := actor_controller.mode()
	if mode != 1 and mode != 2:
		return {}
	# 正在赶路或正在捞：等这一轮结束，别用 E 打断自己。
	if boat.starts_sailing() or _pick_phase != PICK_PHASE_IDLE:
		return {}
	var best := {}
	var best_d := SEA_PICK_FAR
	for c in props.crates:
		var root: Node3D = c.get("root")
		if not is_instance_valid(root):
			continue
		var d := Vector2(root.position.x - boat.position.x, root.position.z - boat.position.z).length()
		if d < best_d:
			best_d = d
			best = {"type": "crate", "item": c, "dist": d,
				"near": d <= props.crate_reach(c) + 0.4}
	for s in props.schools:
		var root2: Node3D = s.get("root")
		if not is_instance_valid(root2):
			continue
		var d2 := Vector2(root2.position.x - boat.position.x, root2.position.z - boat.position.z).length()
		if d2 < best_d:
			best_d = d2
			best = {"type": "fish", "item": s, "dist": d2,
				"near": d2 <= props.FISH_PICKUP_RADIUS + 0.4}
	return best


## E 的总入口：读近距仲裁的同一份结果。
##
## 优先级由 `_near_action()` 一处拥有（贴到跟前的漂流物 → 上下船 → 泊位热区 →
## 划过去捞），提示文案、图标、按键分派全读它，三者不可能不一致。
func _press_boat_key() -> bool:
	if input_blocked():
		return false
	var action := _near_action()
	if action.is_empty():
		# 仲裁之外还有「不在热区、但想划过去捞」这一档：那是明确的赶路指令。
		# `_boat_shortcut_text()` 对此有同样的兜底，两边必须同时改。
		var c := _sea_pick_candidate()
		if not c.is_empty():
			return _press_sea_pick(c)
		return false
	match str(action.get("kind", "")):
		"boat_board", "boat_leave":
			return _toggle_boat_by_key()
		"dock":
			var dock: Dictionary = action.get("dock", {})
			_select_landing({"zone": str(dock.get("zone", "")), "landing": str(dock.get("landing", ""))})
			return true
		"pick":
			return _press_sea_pick(action.get("pick", {}))
		"spot":
			return false
	return false


## 键盘靠岸（SEA-INTERACT-R16 / R25，2026-11-07）。
##
## 原来「去哪个岛」只能点登陆标记：键盘玩家把船划到岛边就再也走不下去了。
## 这里按「船离哪个泊位最近」挑一个，走的是点击那条同一条链路
## （`_select_landing` → 航行 → 靠妥 → 上岸），不新增靠泊通道。
##
## **热区而不是方向锥**（2026-11-07）。旧实现要求船头朝泊位 0.20 以上，
## 于是「船已经开进泊位旁边，只是船尾对着码头」也点不了靠岸 —— 玩家原话是
## 「码头的上船区应该是在海面的，进入热区后点击即可靠岸上岸」。
## 现在只要船开进泊位周围这片水面、且真的能划过去，就出靠岸入口；
## 是否在热区由**位置**决定，与船头朝哪无关（航行到站本来就会摆正船头）。
## 保留「可航」这一条：距离近但被岸线/养殖平台隔开的泊位不算，否则会画一个
## 开不过去的入口。
const DOCK_KEY_REACH := 6.5
## 可航判定带缓存：热区查询每帧都跑，而路径规划不便宜。
var _dock_cache := {}
const DOCK_CACHE_TTL_MS := 400

func _near_landing_key() -> Dictionary:
	if boat == null or (dive != null and dive.active):
		return {}
	var mode := actor_controller.mode()
	if mode != 1 and mode != 2:
		return {}
	if boat.starts_sailing():
		return {}
	var best := {}
	var best_d := DOCK_KEY_REACH
	for zone_id in _zone_nodes.keys():
		if not Scope.zone_enabled(zone_id):
			continue
		var zone: Node = _zone_nodes[zone_id]
		if zone == null or not zone.has_method("landing_points"):
			continue
		for point in zone.landing_points():
			var lid := str(point.landing_id)
			var data: Dictionary = _landing_data(zone_id, lid)
			if not data.has("boatPark"):
				continue
			var park := Vector3(float(data.boatPark[0]), WATER_LEVEL, float(data.boatPark[2]))
			var d := Vector2(park.x - boat.position.x, park.z - boat.position.z).length()
			if d >= best_d:
				continue
			# 已经贴在这个泊位上：方向、航线都没有意义，只要直线滑得进去就一定允许。
			# 判据必须和 `_select_landing` 的「认领 + 滑入」那一档同源，
			# 否则会出现「提示写着靠岸、按下去报无法到达」。
			if d <= DOCK_ADOPT_TOLERANCE and _park_glide_clear(park):
				best_d = d
				best = {"zone": str(zone_id), "landing": lid, "dist": d}
				continue
			if not _dock_route_ok(park):
				continue
			best_d = d
			best = {"zone": str(zone_id), "landing": lid, "dist": d}
	return best


## 泊位能不能划过去。结果按「船位置 + 目标点」缓存 0.4 秒：
## 热区查询在近距图标、按键分派、提示文案三处都会跑，不缓存就是每帧三次寻路。
func _dock_route_ok(park: Vector3) -> bool:
	var key := Vector3i(roundi(boat.position.x * 4.0), roundi(park.x * 4.0), roundi(park.z * 4.0))
	var now := Time.get_ticks_msec()
	var hit: Variant = _dock_cache.get(key)
	if hit != null and now - int(hit.get("stamp", 0)) < DOCK_CACHE_TTL_MS:
		return bool(hit.get("ok", false))
	var ok := not plan_route_to(park.x, park.z).is_empty()
	if _dock_cache.size() > 64:
		_dock_cache.clear()
	_dock_cache[key] = {"ok": ok, "stamp": now}
	return ok


func _press_sea_pick(c: Dictionary) -> bool:
	_handle_prop_click({"type": str(c.get("type", "")), "item": c.get("item")})
	return true


## 船是否正停在这个泊位（与点击登陆标记、点船体同一判据）。
##
## 容差 1.6 米：旧值 1.0 太紧，自动靠泊在余速下常常停在 1.1–1.4 米，
## 玩家看到船明明贴着码头，E 却说「船不在泊位」——「上下船判定经常体验不好」
## 有相当一部分来自这里。船头朝向不参与判定，靠妥时本来就已摆正。
func _landing_is_docked() -> bool:
	if boat == null:
		return false
	var l: Dictionary = _landing_data(GameState.current_zone, GameState.landing_id)
	if l.is_empty():
		return false
	var park := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	var sailing: bool = boat.starts_sailing()
	return not sailing and boat.position.distance_to(park) < DOCK_SETTLE_TOLERANCE



## 提示条上的「现在按 E 会做什么」。
##
## 读 `_near_action()` 的同一份仲裁：提示、图标、按键分派三处共用一个结果，
## 不会再出现「写着上岸、按下去在打捞」。
##
## 有一档必须单独说清楚：**热区之外**的漂流物 / 鱼群。
## 那时不出图标（图标的意思是「你已进入判定区，点一下就动手」），
## 但 `_press_boat_key()` 仍保留「划过去捞」这条赶路指令 —— 键盘玩家
## 隔着几米没法出发就断手了。既然 E 会开船，提示就不能空着：
## 旧实现在 3 米处提示为空、按 E 船却直奔漂流物，正是「提示 ≠ 按键」。
## 这里补上与 `_press_boat_key()` 兜底同源的判断。
func _boat_shortcut_text(arbitrated: Variant = null) -> String:
	if hud == null or not is_instance_valid(hud) or input_blocked():
		return ""
	var action: Dictionary = _near_action() if arbitrated == null else arbitrated
	match str(action.get("kind", "")):
		"boat_board": return "上船"
		"boat_leave": return "上岸"
		"dock":
			var dock: Dictionary = action.get("dock", {})
			return "靠岸 · " + Zones.label(str(dock.get("zone", "")))
		"pick":
			return "捕鱼" if str(action.get("pick", {}).get("type", "")) == "fish" else "打捞"
		"spot":
			# 交互物的文案由 interactor / prompt 自己给，这里不抢。
			return ""
	# 空结果 = 不在任何热区。这一档 E 仍可能「划过去捞」，如实写明。
	var far := _sea_pick_candidate()
	if not far.is_empty():
		return "捕鱼" if str(far.get("type", "")) == "fish" else "打捞"
	return ""


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
		# 打捞不是靠泊：到站保留船头朝向，不在停稳后再拧一下（SEA-PICKUP-R15）。
		boat.sail_to(goal, boat.rotation.y, GameState.current_zone, GameState.landing_id, path, false)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		_begin_pick_sail({"type": "fish", "item": school})
	else:
		var crate: Dictionary = prop.item
		var target2: Vector3 = crate.base
		var goal2 := target2 + Vector3(props.crate_reach(crate) - 0.8, 0, 0)
		var path2 := plan_route_to(goal2.x, goal2.z)
		if path2.is_empty():
			goal2=target2
			path2=plan_route_to(goal2.x,goal2.z)
		if path2.is_empty():
			hud.toast("无法到达漂流物")
			return
		boat.sail_to(goal2, boat.rotation.y, GameState.current_zone, GameState.landing_id, path2, false)
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
		# 打捞也是一份体力活：结算前先问一句，够体力才收，收完再扣。
		# 扣在「成功那一条路」上，捞空了不会白掉体力。
		var tired: String = Economy.energy.reason("pickup")
		if tired != "":
			hud.toast(tired, 3.0)
			if pickup_progress != null: pickup_progress.clear()
			return
		if str(pick.get("type", "")) == "fish":
			got = props.collect_fish(pick.item)
		else:
			got = not props.collect_crate(pick.item).is_empty()
		if got: Economy.energy.spend("pickup")
	if pickup_progress != null:
		if got:
			pickup_progress.complete()
		else:
			pickup_progress.clear()


## 船停稳之后，目标是否真的在打捞范围内。
##
## 必须查这一下：船半路被岸线挡住也会「停」，那时候离目标还有几十米，
## 不校验就会在原地对着空气捞 1.2 秒，然后什么都没收到。
## 浮木按该束尺寸取范围，鱼群用 props 自己的捕捞半径。
func _pick_in_reach() -> bool:
	if props == null: return false
	var item: Dictionary = _pending_pick.get("item", {})
	var is_fish: bool = str(_pending_pick.get("type", "")) == "fish"
	if not (props.schools if is_fish else props.crates).has(item): return false
	var root = item.get("root")
	if not (root is Node3D) or not is_instance_valid(root): return false
	var d: float = Vector2(root.position.x - boat.position.x,
		root.position.z - boat.position.z).length()
	var reach: float = props.FISH_PICKUP_RADIUS \
		if str(_pending_pick.get("type", "")) == "fish" else props.crate_reach(item)
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
	if boat.starts_sailing() or not _pick_in_reach():
		_cancel_pending_pick()
		return
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
	if pickup_progress != null: pickup_progress.receive(reward)
	var parts: Array = []
	for k in reward.keys():
		parts.append("%s +%d" % [Economy.COLLECTIONS.get(k, {}).get("label", k), int(reward[k])])
	hud.toast("%s · %s" % [label, "  ".join(parts)])


func _on_fish_collected(_label: String) -> void:
	if pickup_progress != null: pickup_progress.receive({"fish":1})
	hud.toast("捞到 1 条鱼")


## 采集点进账：统一走背包，装不下的部分会被拦下并提示。
##
## 体力的拦截在 `GatherSpot.blocked_reason()` 里就已经发生（按住 E 直接提示），
## 这里只在真的收下之后扣费，采空/放不下都不会白掉体力。
func _on_gathered(kind: String, amount: int, label: String, _spot: Node3D) -> void:
	var added: Dictionary = Economy.give({kind: amount})
	var got := int(added.get(kind, 0))
	if got <= 0:
		hud.toast("背包装不下 %s" % label)
		return
	Economy.energy.spend("gather")
	var icon := ItemDB.icon(kind)
	hud.toast("%s  %s +%d" % [icon, label, got])


func _on_depth_changed(depth: float) -> void:
	hud.set_dive_depth(depth)


func _on_dive_air(ratio: float, lamp_on: bool, found: int, total: int) -> void:
	hud.set_dive_air(ratio, lamp_on, found, total)


func _on_dive_zone(name: String) -> void:
	hud.set_dive_zone(name)


func _on_dive_exited() -> void:
	# Session restored the same actor/boat scene and its original mode, not a new save.
	hud.set_diving(false)
	hud.toast("回到水面")

func _dive_source_at(boat_position: Vector3) -> String:
	# 家园海域：阳光房附近与「家园海底」共用一套世界坐标，下水点即入水点。
	var home := preload("res://src/diving/dive_map_catalog.gd").home_map()
	if not home.is_empty() and preload("res://src/diving/dive_map_catalog.gd").is_home_water(boat_position, _home_seabed_anchor()):
		return "home_seabed"
	if actor_controller != null and actor_controller.mode() == GameState.Mode.ASHORE:
		return GameState.current_zone
	# Nearest installed, enabled sea area wins. Anchors come from live scene landings,
	# never zones.json reference origins; moving a facility moves its catchment.
	var chosen := ""
	var nearest := INF
	for id in _zone_nodes:
		if not Scope.zone_enabled(str(id)): continue
		if preload("res://src/diving/dive_map_catalog.gd").get_map(str(id)).is_empty(): continue
		var zone = _zone_nodes[id]
		var points: Array = zone.landing_points()
		for point in points:
			var anchor: Vector3 = point.global_position
			var distance := Vector2(anchor.x-boat_position.x,anchor.z-boat_position.z).length_squared()
			if distance < nearest or (is_equal_approx(distance,nearest) and str(id) < chosen):
				nearest = distance
				chosen = str(id)
	return chosen


## 阳光房的真实海面位置由手摆场景决定，不写死在脚本里；挪动木屋会一起挪动入水归属。
func _home_seabed_anchor() -> Vector3:
	var zone = _zone_nodes.get("zone1")
	if zone == null: return Vector3.ZERO
	var cabin: Node3D = zone.find_child("太阳能木屋",true,false) as Node3D
	if cabin != null: return cabin.global_position
	return zone.global_position


## 调试入口（`--salvage`）：忽略距离，直接开面板。
func _try_salvage() -> void:
	if Scope.minimal(): return
	var now := Time.get_ticks_msec() / 1000.0
	if not Economy.can_salvage(now):
		hud.toast("绞盘还在收线 · %.0f 秒" % Economy.salvage_cooldown_left(now))
		return
	_open_salvage(salvage_winch)


func _on_dive() -> void:
	if _title_active or dive.switching: return
	if boat.starts_sailing():
		hud.toast("先靠岸或停船再潜水")
		return
	if dive.active:
		dive.surface()
		return
	if room_service != null and room_service.inside:
		hud.toast("请先离开房间再潜水")
		return
	if input_blocked(): return
	_cancel_action()
	if hud.is_panel_open(): hud.toggle_panel()
	cam_panel.set_open(false)
	grade.set_open(false)
	# The surface actor keeps its original mode and position while removed from tree.
	# The separate dive map owns its diver, camera, environment and HUD.
	# 世界对齐地图要用角色的真实落水点：岸上取人、船上取船。
	var entry := boat.position
	if actor_controller.mode() == GameState.Mode.ASHORE: entry = player.global_position
	var source: String = _dive_source_at(entry)
	dive.request_dive(entry, source)


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


## 体力归零：先念一句，再走黑幕过场。
##
## 顺序固定成「台词 → 收幕」，不是「收幕 → 台词」：玩家是在做某件事的半路上
## 突然动不了的，需要先被告知发生了什么，黑幕才有意义。台词期间输入被吞
## （`input_blocked()`），避免玩家在等过场时把角色又拖走。
func _on_energy_exhausted() -> void:
	if _title_active or _exhausted_rest or sleep_cycle.busy: return
	_exhausted_rest = true
	_cancel_action()
	hud.show_dialogue("我", "啊，太累了，今天需要休息了。")
	await get_tree().create_timer(EXHAUSTED_LINE_SECONDS).timeout
	if hud.dialogue != null and hud.dialogue.has_method("close_line"): hud.dialogue.close_line()
	if not sleep_cycle.busy:
		await sleep_cycle.request_forced()
	_exhausted_rest = false


func _on_upgrade_ship() -> void:
	if Scope.minimal(): return
	var r: Dictionary = Economy.upgrade_ship()
	if r.ok:
		hud.toast("小船升到 Lv.%d" % int(r.level))
	else:
		hud.toast(str(r.reason))


func _process(delta: float) -> void:
	if dive != null and dive.switching: return
	_t += delta
	# The public CPU wave clock remains continuous even with hidden rendering.
	if water_node != null: water_node.time = _t
	if weather_view != null: weather_view.advance_time(delta)
	if _title_active:
		if water_node.has_method("update_surface"): water_node.update_surface(_t,boat,cam.target)
		return
	sleep_cycle.advance(delta)
	if sleep_cycle.busy:
		if building_controller!=null and building_controller.active: building_controller.close()
		return
	# SleepCycle.advance owns this frame's single, bedtime-capped clock tick.
	var clock_snapshot: Dictionary = world_clock.query()
	var inside_room: bool = room_service != null and room_service.inside
	props.sync_population(clock_snapshot,boat.position)
	_tick_garden_greeting(delta)
	if building_controller!=null: building_controller.tick(delta)
	weather_service.tick(delta)
	if weather_view != null:
		var weather_snapshot: Dictionary = weather_service.query()
		weather_view.present(clock_snapshot,weather_snapshot,dive.active)
		# 连续时间仍驱动屋内日照；HUD 仅在显示文字改变时提交。
		if daylight_rig != null:
			daylight_rig.apply(clock_snapshot.hour)
		var calendar_text: String = clock_snapshot.text + " · " + weather_snapshot.label
		if _calendar_label.text != calendar_text: _calendar_label.text = calendar_text
		_calendar_label.visible = not dive.active
	if _autosave_on:
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			# 自动存档静默执行，不打断操作；F5 手动存档才有提示。
			save_game("", true)
	if not inside_room:
		if environment != null and environment.has_method("update_time"):
			environment.update_time(_t)
		for zone in _zone_nodes.values():
			if zone.has_method("update_time"):
				zone.update_time(_t)
	# 交互只在岸上、站定时开放：船上/航行中/潜水都不该出现采集提示。
	if interactor != null:
		interactor.active = (not dive.active) and (not _walking) \
			and GameState.mode == GameState.Mode.ASHORE and not input_blocked()
	# One read-only arbitration per presentation update; actual input paths still
	# re-query immediately and never consume a cross-frame target cache.
	var near_action := _near_action()
	if prompt != null:
		prompt.shortcut = _boat_shortcut_text(near_action)
		prompt.update_from(interactor)
	_update_pointer_ui()
	_update_near_interaction(near_action)
	_update_camera_feedback(delta)
	if water_node.has_method("update_surface") and not dive.active and not inside_room:
		water_node.update_surface(_t, boat, cam.target)
	# 拾取：推进当前这一轮（航行→打捞→结算都在里面）。
	_update_pickup_progress(delta)
	# 没有点击、船自己停在浮木旁边：也走同一套「停下才打捞」。
	# 顺序在推进之后：先让上一轮结算/收条，再考虑开新一轮。
	if props != null and not dive.active:
		_start_idle_pick()


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
	return _title_active or _exhausted_rest or (workshop_host != null and workshop_host.is_open()) or (dive != null and dive.switching) or actor_controller.climbing() or (sleep_cycle != null and sleep_cycle.busy) or (room_controller.busy if room_controller != null else false) or (hud != null and hud.is_modal()) or (salvage_panel != null and salvage_panel.is_open()) or (order_panel != null and order_panel.is_open()) or (cam_panel != null and cam_panel.is_open()) or (grade != null and grade.visible)

func _setup_actor_controller() -> void:
	player.rowing_pose_query = boat.rowing_pose
	actor_controller.mode_changed.connect(GameState.set_mode)
	actor_controller.configure(player,boat,self,interactor,{"landing":_current_landing,"zone":func(): return _zone_nodes.get(GameState.current_zone),"notify":func(text): hud.toast(text),"input_blocked":input_blocked})
	GameState.mode_changed.connect(actor_controller.reconcile_mode)
	cam.input_blocked = func(): return _title_active or _exhausted_rest or (dive!=null and dive.switching) or (sleep_cycle!=null and sleep_cycle.busy) or hud.camera_modal() or (salvage_panel!=null and salvage_panel.is_open()) or (order_panel!=null and order_panel.is_open()) or (cam_panel!=null and cam_panel.is_open()) or (grade!=null and grade.visible)
	player.rowing_query = boat.rowing_state
	boat.speed_multiplier = func() -> float: return 1.15 if Economy.ship_level>=3 else 1.0
	Economy.ship.upgraded.connect(func(_level): GameState.far_sea_unlocked=true)
	interactor.completed.connect(func(_spot,_reward): actor_controller.complete_interaction())
	interactor.blocked.connect(func(_reason): actor_controller.complete_interaction())
	interactor.reachable_query = func(spot: Node3D) -> bool: return _land_reach_reason(spot) == ""
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

## 街区里的既有直梯（目前只有霓虹花园左楼检修梯脚下那一架）。
##
## 为什么必须由 Bootstrap 注入：climb_ladder 是 ActorController 的方法，而
## ActorController 是主场景持有的 RefCounted、不在节点树上 —— 交互物顺着
## parent 找不到它。阳光房那架梯子同样是在这里 configure 的。
##
## 这里只补世界高度：两个交互点已经在场景里摆好（浮台上 / 第一级平台上），
## 缺的只是「从 1.12 爬到 4.83」这两个数。
const NEON_LADDER_BOTTOM := 1.12
const NEON_LADDER_TOP := 4.83

func _setup_ladders() -> void:
	var quarter: Node = _zone_nodes.get("neon_garden_quarter")
	if quarter == null:
		return
	var bottom: Node = quarter.get_node_or_null("Ladders/StairFootBottom")
	var top: Node = quarter.get_node_or_null("Ladders/StairFootTop")
	if bottom == null or top == null:
		return
	if not bottom.has_method("attach") or not top.has_method("attach"):
		return
	var climb := Callable(actor_controller, "climb_ladder")
	bottom.attach(climb, "up", NEON_LADDER_BOTTOM, NEON_LADDER_TOP, bottom)
	top.attach(climb, "down", NEON_LADDER_BOTTOM, NEON_LADDER_TOP, top)

func _setup_calendar() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/world_time.json"))
	world_clock.configure(config.get("clock",{}))
	world_clock.changed.connect(func(snapshot: Dictionary):
		props.sync_population(snapshot,boat.position)
		Economy.sunroom.set_calendar_day(int(snapshot.get("day", 1))))
	Economy.fishery.observe(world_clock.query())
	world_clock.changed.connect(Economy.fishery.observe)
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
	boundary.actor_query=func(): return {"mode":actor_controller.mode(),"zone":GameState.current_zone,"position":player.global_position,"state":actor_controller.state_id()}
	boundary.boat_query=func(): return boat.global_position
	boundary.obstacles_query=_construction_obstacles
	boundary.protected_query=_construction_protected
	boundary.farm_query=Economy.farm.state
	boundary.active_landing_query=func(): return GameState.landing_id if actor_controller.mode()==0 else ""
	building.configure({"eligibility":boundary.eligibility,"space_reason":boundary.space_reason,
		"layout_reason":_construction_layout_reason,"pay":Economy.inventory.pay,"refund":_construction_refund,
		"capacity_reason":_construction_capacity_reason,
		"energy_reason":Economy.energy.reason,"spend_energy":Economy.energy.spend})
	building_world.configure(building,_zone_nodes.zone5.walk_areas[0],farm_field,_bind_constructed_plot,func():
		navigation.invalidate()
		props.ocean.invalidate()
		_zone_nodes.zone5.rebuild_ground(_zone_nodes.zone5.walk_areas[0])
		water_node.set_runtime_contact_rects(building_world.contact_rects()))
	building_world.prop_action=func(action):
		if action=="storage": hud.open_tab("storage")
		elif action=="water": Economy.farm.refill();hud.toast("水壶已补满")
	building_access=preload("res://src/building/building_access.gd").new();add_child(building_access)
	building_access.configure(building,building_world,navigation,boat,markers,cam,_construction_actor_state,_select_landing,func(): return GameState.landing_id)
	building.changed.connect(func():
		if actor_controller.mode()!=0 and building_access.is_dynamic(GameState.landing_id) and building_access.landing_data(GameState.landing_id).is_empty():
			GameState.landing_id="main")
	cam.pan_bounds=Rect2()
	building.completed.connect(func(_id): props.apply_population_scope())
	building_controller=preload("res://src/building/building_controller.gd").new();add_child(building_controller)
	building_controller.configure(building,building_world,cam,hud,Economy.inventory.all,actor_controller.cancel,
		_construction_stand_point,_construction_walk,_construction_actor_state)
	# 拆除（锤子）钮在屋里收起：房间里既有建造也没有可拆的东西，
	# 一颗点不出任何结果的锤子只是噪声（2026-11-06 用户截图右上角那颗）。
	building_controller.demolition.launcher_visibility_query=func(): return not _title_active and not get_tree().paused and not _exhausted_rest and not room_service.inside and (sleep_cycle==null or not sleep_cycle.busy) and building_controller.active and actor_controller.mode()!=3
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
	if actor_controller.mode() in [1,2]: return building_access.boat_stand(center)
	if building_world.has_method("find_stand_point"):
		var request: Dictionary={}
		if building_controller!=null:
			request=building_controller.pending if not building_controller.pending.is_empty() else building_controller.preview
		return building_world.find_stand_point(player.global_position,center,2.8,request)
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
	if actor_controller.mode() in [1,2]:
		var path:=plan_route_to(point.x,point.z)
		if path.is_empty(): return false
		_cancel_pending_pick();_ashore_on_arrival=false
		boat.sail_to(point,boat.rotation.y,"","",path)
		actor_controller.request_mode(GameState.Mode.SAILING)
		if ribbon!=null: ribbon.show_route(boat.route,WATER_LEVEL)
		return true
	var zone: Node = _zone_nodes.get("zone5")
	if zone == null: return false
	var ground: Variant = zone.area_at(point,0.5)
	if ground == null: return false
	if hud != null: hud.world_actions.close(true)
	return actor_controller.start_walk(ground, point)

func _construction_actor_state() -> Dictionary:
	var afloat: bool=actor_controller.mode() in [1,2]
	return {"position":boat.global_position if afloat else player.global_position,
		"walking":boat.starts_sailing() if afloat else actor_controller.walking(),"mode":actor_controller.mode()}

func _construction_refund(cost: Dictionary) -> bool:
	return Economy.inventory.add_all(cost)

func _construction_layout_reason(before: Array,after: Array,request: Dictionary) -> String:
	var reason: String=building_boundary.layout_reason(before,after,request)
	if reason!="": return reason
	if actor_controller.mode()==0 and building_access!=null and building_access.is_dynamic(GameState.landing_id):
		if building_access.landing_data(GameState.landing_id,after).is_empty(): return "请保留当前上下船的位置"
	return ""

func _construction_capacity_reason(rows: Array) -> String:
	if save_registry==null or save_registry.is_busy(): return "正在结算或恢复，请稍后建造"
	var snapshot: Dictionary=SaveGameLib.encode(self)
	if snapshot.is_empty() or not snapshot.has("building"): return ""
	snapshot.building.instances=rows
	# Include the future Farm records of unfinished furnishings before charging.
	var states: Dictionary=snapshot.economy.farm.plots
	var live: Dictionary={}
	for row in rows:
		if preload("res://src/building/building_catalog.gd").role(str(row.kind))!="planter": continue
		var id: String="dynamic/"+str(row.id)
		live[id]=true
		if not states.has(id): states[id]={"crop":"pumpkin","remaining":3.0,"total":3.0,"water":1.0,"harvests":1000000000}
	for id in states.keys():
		if str(id).begins_with("dynamic/") and not live.has(id): states.erase(id)
	return "存档已达到安全容量，请先整理已有建造" if JSON.stringify(snapshot,"\t").to_utf8_buffer().size()>SaveGameLib.MAX_BYTES-65536 else ""

func _construction_obstacles() -> Array:
	var result: Array=[]
	var catalog = preload("res://src/building/building_catalog.gd")
	# 脚下这块固定浮台自身的水下底座不是「别人家的建筑」（SEA-BUILDING-R25）。
	#
	# 底座从水面线往下沉了十几米，它的水面阻挡矩形正好跟平台轮廓一样大；
	# 而木板网格 2.15×2.575 与平台 6.45×5.15 不同步，贴着平台接的新格子必然
	# 与底座矩形重叠 0.2 米左右 —— 结果就是四面都报「这里有既有建筑」，
	# 只剩原本已经拼好的那一侧能接，等于把扩建堵死。
	# 平台自己在建造判定里已经由「必须贴边」管住（`_platform_join_reason`），
	# 这里把与它重叠的阻挡全部放行；远处别的区块、别的建筑照旧拦。
	var base := Rect2(Vector2(catalog.ORIGIN.x,catalog.ORIGIN.z)+catalog.BASE.position,catalog.BASE.size)
	for shape in _water_shapes():
		if _shape_overlaps(shape,base): continue
		result.append(shape)
	for zone in _zone_nodes.values():
		if zone.zone_id=="zone5": continue
		for ground in zone.walk_areas:
			for rect: Rect2 in ground.rects:
				var point: Vector3=ground.to_global(Vector3(rect.position.x,0,rect.position.y))
				result.append(Rect2(Vector2(point.x,point.z),rect.size))
	return result


## 水面阻挡项（矩形或 {x,z,hx,hz,round} 形状）是否压到给定矩形。
static func _shape_overlaps(shape: Variant, area: Rect2) -> bool:
	if shape is Rect2:
		return (shape as Rect2).grow(-0.01).intersects(area.grow(-0.01))
	if shape is Dictionary:
		var data: Dictionary = shape
		var centre := Vector2(float(data.get("x",0)),float(data.get("z",0)))
		var hx := float(data.get("hx",0))
		var hz := float(data.get("hz",hx))
		if bool(data.get("round",false)):
			var nearest := Vector2(clampf(centre.x,area.position.x,area.end.x),clampf(centre.y,area.position.y,area.end.y))
			return nearest.distance_squared_to(centre) < hx*hx
		return Rect2(centre-Vector2(hx,hz),Vector2(hx,hz)*2).grow(-0.01).intersects(area.grow(-0.01))
	return false

func _construction_protected() -> Array:
	var result: Array=[]
	for zone in _zone_nodes.values():
		for landing in zone.landing_points():
			if str(landing.landing_id).begins_with("built:"): continue
			var data: Dictionary=landing.data()
			var park:=Vector2(data.boatPark[0],data.boatPark[2])
			var stand:=Vector2(data.landStand[0],data.landStand[2])
			result.append(Rect2(park-Vector2.ONE*1.3,Vector2.ONE*2.6))
			result.append(Rect2(stand,Vector2.ZERO).expand(park).grow(0.45))
	return result

func _restore_building(data: Dictionary) -> void:
	building_controller.close()
	building_world.reset_projection()
	building.from_dict(data)
	# Registry suppresses owner signals; the projection must exist before Farm restores.
	building_world.sync()

func _validate_building_world(snapshot: Dictionary) -> String:
	return validate_world_state(snapshot.game,snapshot.building.instances,bool(snapshot.economy.get("fishery",{}).get("unlocked",false)))

func _setup_npc_systems() -> void:
	# NPC 与商店仍各自持有业务，Main 只注入端口与转发公开事件。
	shop_service.configure(Economy.inventory)
	hud.shop_query = _legacy_shop_snapshot
	hud.shop_buy = _legacy_shop_buy
	npc_service.configure(_npc_world_query, Economy.inventory.exchange, Economy.inventory.remove, Economy.inventory.count)
	shop_panel = preload("res://src/shop/shop_panel.gd").new()
	shop_panel.name = "ShopPanel"
	add_child(shop_panel)
	shop_panel.configure(shop_service, Economy.inventory)
	shop_panel.opened.connect(_on_shop_panel_opened)
	shop_panel.closed.connect(_on_shop_panel_closed)
	npc_career_panel = preload("res://src/npc/npc_career_panel.gd").new()
	npc_career_panel.name = "NpcCareerPanel"
	add_child(npc_career_panel)
	npc_career_panel.configure(_npc_career_query, _npc_career_command)
	npc_career_panel.closed.connect(func(): _on_npc_modal_changed(false))
	npc_service.vendor_requested.connect(_on_npc_vendor_requested)
	assert(NpcCatalog.validate() == "", NpcCatalog.validate())
	npc_world_presenter = preload("res://src/npc/npc_world_presenter.gd").new()
	npc_world_presenter.name = "NpcWorldPresenter"
	npc_world_presenter.npc_interaction_requested.connect(_on_npc_interaction_requested)
	add_child(npc_world_presenter)
	_npc_previous_modal_query = hud.owned_modal_query
	_npc_previous_modal_close = hud.owned_modal_close
	_npc_previous_modal_input = hud.owned_modal_input
	_npc_previous_modal_camera_query = hud.owned_modal_camera_query
	hud.owned_modal_query = _npc_owned_modal
	hud.owned_modal_close = _npc_close_modal
	hud.owned_modal_input = _npc_modal_input
	hud.owned_modal_camera_query = _npc_owned_modal_camera_query
	npc_world_presenter.modal_changed.connect(_on_npc_modal_changed)
	npc_world_presenter.action_requested.connect(_on_npc_career_requested)
	var stations: Node3D = get_node_or_null("World/SeaStructures/rooftop_ranch/NpcStations") as Node3D
	var anchor_hub = preload("res://src/npc/npc_anchor_hub.gd").new()
	anchor_hub.name = "NpcAnchorHub"
	add_child(anchor_hub)
	anchor_hub.configure([stations,
		get_node_or_null("World/SeaStructures/floating_shop/Objects/NpcStations"),
		get_node_or_null("World/SeaStructures/neon_garden_quarter/NpcStations"),
		# 霓虹花园屋顶：船员站在派生屋顶面上，不能复用花园桥那一个站点。
		get_node_or_null("World/SeaStructures/neon_garden_quarter/RoofNpcStations")])
	npc_world_presenter.configure(npc_service, anchor_hub, _npc_world_query, _on_npc_interaction_requested)
	if hud.dialogue == null:
		hud.dialogue = preload("res://src/ui/character_dialogue.gd").new()
		hud.add_child(hud.dialogue)
	npc_world_presenter.panel.set_dialogue_view(hud.dialogue)
	world_clock.changed.connect(_on_npc_clock_changed)
	_setup_garden_greetings()

func _setup_workshop() -> void:
	workshop_host = WorkshopHostScript.new()
	workshop_host.name = "WorkshopHost"
	add_child(workshop_host)
	workshop_host.configure({
		"hud": hud,
		"parentNode": self,
		"can_open": _workshop_can_open,
		"before_open": _workshop_before_open,
		"after_close": _workshop_after_close})

func _workshop_can_open() -> String:
	if _title_active: return "标题或开场流程进行中"
	if sleep_cycle != null and sleep_cycle.busy: return "睡觉过场进行中"
	if dive != null and (dive.active or dive.switching): return "潜水或地图切换进行中"
	if avatar_session != null and avatar_session.active(): return "角色档案编辑进行中"
	if hud != null and hud.narrative_active(): return "对话或新手引导进行中"
	if arrival_flow != null and arrival_flow.phase != "idle": return "登岸流程进行中"
	if room_service != null and room_service.inside: return "室内不能打开楼房工坊"
	if save_registry != null and save_registry.is_busy(): return "正在结算或恢复，请稍后再试"
	if building != null and building.busy(): return "建筑状态正在处理"
	if _npc_owned_modal(): return "请先关闭当前操作面板"
	return ""

func _workshop_before_open() -> void:
	_world_press = false
	_dragged = false
	actor_controller.cancel()
	interactor.require_release()
	interactor.active = false
	if hud != null:
		hud.close_card()
	if cam_panel != null: cam_panel.set_open(false)
	if grade != null: grade.set_open(false)
	if hover != null: hover.clear()
	if hud != null and hud.menu != null and hud.menu.active: hud.menu.close_menu()

func _workshop_after_close() -> void:
	_world_press = false
	if hud != null:
		hud.set_external_modal(_npc_owned_modal() or hud.menu.external_open(), false)

func _legacy_shop_snapshot() -> Dictionary:
	var view: Dictionary = shop_service.shop_snapshot("shop_general")
	var catalog: Array = []
	for row in view.get("products", []):
		catalog.append({"id":row.item, "crop":row.id, "count":0, "price":row.price, "max_buy":row.max_buy})
	return {"catalog":catalog, "coins":view.get("coins", 0), "display_name":view.get("display_name", "综合商店"), "caption":"种子、土壤与日常补给"}

func _legacy_shop_buy(product_id: String, amount: int) -> Dictionary:
	var aliases := {"lettuce":"general_lettuce_seed", "tomato":"general_tomato_seed", "pumpkin":"general_pumpkin_seed", "soil":"general_soil"}
	var result: Dictionary = shop_service.buy("shop_general", str(aliases.get(product_id, product_id)), amount)
	if result.ok:
		result["event"] = "bought"
		result["message"] = "已购入 %s ×%d" % [result.label, amount]
	else: result["blocked"] = result.get("reason", "购买未完成")
	return result

func _on_npc_clock_changed(_snapshot: Dictionary) -> void:
	# High-frequency clock signals only publish context; NPC owns bounded schedule work.
	if npc_world_presenter != null: npc_world_presenter.notify_world(_npc_world_query())

func _npc_world_query() -> Dictionary:
	var snapshot: Dictionary = world_clock.query()
	snapshot["weather"] = weather_service.query().get("kind", "clear")
	return snapshot

func _npc_owned_modal() -> bool:
	return (npc_world_presenter != null and npc_world_presenter.is_modal()) or (shop_panel != null and shop_panel.is_open()) or (npc_career_panel != null and npc_career_panel.is_open()) or (_npc_previous_modal_query.is_valid() and _npc_previous_modal_query.call())

func _npc_close_modal() -> void:
	if shop_panel != null and shop_panel.is_open(): shop_panel.close()
	elif npc_career_panel != null and npc_career_panel.is_open(): npc_career_panel.close()
	elif npc_world_presenter != null and npc_world_presenter.is_modal(): npc_world_presenter.cancel_session()
	elif _npc_previous_modal_close.is_valid(): _npc_previous_modal_close.call()

func _npc_modal_input(event: InputEvent) -> bool:
	if shop_panel != null and shop_panel.is_open(): return shop_panel.handle_input(event)
	if npc_career_panel != null and npc_career_panel.is_open(): return npc_career_panel.handle_input(event)
	if npc_world_presenter != null and npc_world_presenter.is_modal(): return npc_world_presenter.handle_input(event)
	return _npc_previous_modal_input.is_valid() and _npc_previous_modal_input.call(event)

func _npc_owned_modal_camera_query() -> bool:
	return (workshop_host != null and workshop_host.is_open()) or (_npc_previous_modal_camera_query.is_valid() and _npc_previous_modal_camera_query.call())

func _on_npc_modal_changed(active: bool) -> void:
	hud.set_external_modal(active or _npc_owned_modal() or hud.menu.external_open(), false)
	_world_press = false
	if active:
		hud.close_card()
		actor_controller.cancel()
		interactor.require_release()
		interactor.active = false
		if hover != null: hover.clear()

func _set_hud_close_visible(on: bool) -> void:
	if hud == null: return
	var button: Variant = hud.command_buttons.get("close")
	if button is Button: button.visible = on

## 商店是全屏图标面板，自己带右下圆键；打开期间收起 HUD 那一枚，
## 避免同一角落并排两枚关闭键（SEA-UI-R47 只留一枚可见关闭入口）。
func _on_shop_panel_opened(_shop_id: String) -> void:
	_on_npc_modal_changed(true)
	_set_hud_close_visible(false)

func _on_shop_panel_closed(_shop_id: String) -> void:
	_on_npc_modal_changed(false)
	_set_hud_close_visible(true)

func _setup_garden_greetings() -> void:
	var file := FileAccess.open(GARDEN_GREETINGS, FileAccess.READ)
	if file == null:
		push_warning("菜园桥招呼台词表读取失败：" + GARDEN_GREETINGS)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_warning("菜园桥招呼台词表格式不对：" + GARDEN_GREETINGS)
		return
	for row in data.get("npcs", []):
		if row is Dictionary and str(row.get("npc_id", "")) == "npc_mu_he":
			for line in row.get("lines", []):
				if str(line).strip_edges() != "":
					_garden_lines.append(str(line))
	if _garden_lines.is_empty():
		return
	_garden_bubble = preload("res://src/ui/speech_bubble.gd").new()
	_garden_bubble.name = "GardenSpeechBubble"
	hud.add_child(_garden_bubble)
	_garden_bubble.hide()


## 玩家在楼下的船上靠近霓虹花园时，楼顶种菜的豆豆抬头喊一句。
##
## 距离只算水平 XZ：她站在 28 米高的菜园桥上，用三维距离判定会让
## 船正好从楼底下经过时反而「太远」。
func _tick_garden_greeting(delta: float) -> void:
	if _garden_bubble == null or _garden_lines.is_empty():
		return
	if _title_active:
		return
	# 任何模态（对话、商店、职业面板）期间都不喊，别和正在进行的谈话打架。
	if npc_world_presenter == null or npc_world_presenter.is_modal():
		if _garden_bubble.is_speaking():
			_garden_bubble.dismiss()
		return
	if int(world_clock.day) == _garden_spoken_day:
		return
	_garden_probe_cooldown -= delta
	if _garden_probe_cooldown > 0.0:
		return
	_garden_probe_cooldown = 0.2
	var body = npc_world_presenter.actor("npc_mu_he")
	if not is_instance_valid(body):
		return
	var traveler: Node3D = player if player != null else boat
	if not is_instance_valid(traveler):
		return
	var a: Vector3 = traveler.global_position
	var b: Vector3 = body.global_position
	if Vector2(a.x - b.x, a.z - b.z).length() > GARDEN_GREETING_RADIUS:
		return
	_garden_spoken_day = int(world_clock.day)
	var index := posmod(_garden_spoken_day - 1, _garden_lines.size())
	_garden_bubble.speak(str(_garden_lines[index]), body, cam, GARDEN_GREETING_HOLD)


func _on_npc_vendor_requested(npc_id: String, shop_id: String) -> void:
	var row: Dictionary = NpcCatalog.get_npc(npc_id)
	if row.get("shop_id", "") != shop_id: return
	npc_world_presenter.cancel_session()
	if npc_career_panel != null: npc_career_panel.close()
	var opened: Dictionary = shop_panel.open_shop(shop_id)
	if not opened.ok: hud.toast(opened.reason)

func _on_npc_career_requested(npc_id: String, action_id: String) -> void:
	var expected := {"npc_luo_yan":"ship", "npc_mu_he":"cultivation", "npc_ji_chen":"salvage", "npc_nan_zhi":"building", "npc_bai_shi":"archive"}
	if expected.get(npc_id, "") != action_id: return
	var result: Dictionary = npc_career_panel.open_service(npc_id, action_id)
	if result.ok: _on_npc_modal_changed(true)
	else: hud.toast(result.reason)

func _npc_career_query(action_id: String) -> Dictionary:
	var ids := {"ship":"npc_luo_yan", "cultivation":"npc_mu_he", "salvage":"npc_ji_chen", "building":"npc_nan_zhi", "archive":"npc_bai_shi"}
	var npc: Dictionary = NpcCatalog.get_npc(str(ids.get(action_id, "")))
	var result := {"ok": true, "display_name":npc.get("display_name", ""), "role":npc.get("role", "")}
	match action_id:
		"ship":
			result.merge({"ship_level":Economy.ship.ship_level, "cost":Economy.ship.ship_cost(), "can_execute":Economy.ship.can_upgrade_ship(), "reason":"船已满级" if Economy.ship.ship_level >= 3 else Economy.ship.construction_missing_text(Economy.ship.ship_cost())})
		"salvage":
			var now := SaveGameLib.now_seconds()
			var left: float = Economy.salvage.salvage_cooldown_left(now)
			result.merge({"cooldown_left":left, "can_execute":left <= 0.0, "description":"委托回声整理打捞物，复用现有打捞结算。", "reason":"绞盘正在收线" if left > 0.0 else ""})
		"cultivation":
			var crops: Array = []
			for id in Economy.farm.crop_definitions():
				var crop: Dictionary = Economy.farm.crop_def(str(id))
				crops.append({"display_name":crop.get("name",id), "growth_text":"%d个浇水日成熟" % crop.get("grow_days",3), "status_text":"收获 ×%d" % int(crop.get("yield",{}).values()[0])})
			result["crops"] = crops
		"archive":
			var events: Array = npc_service.list_events()
			for event in events: event["npc_id"] = str(event.npc_ids[0])
			result["events"] = events
	return result

func _npc_career_command(action_id: String, command: Dictionary) -> Dictionary:
	match str(command.get("id", "")):
		"upgrade_ship": return Economy.ship.upgrade_ship() if action_id == "ship" else {"ok":false,"reason":"职能不匹配"}
		"do_salvage":
			if action_id != "salvage": return {"ok":false,"reason":"职能不匹配"}
			var now := SaveGameLib.now_seconds()
			if not Economy.salvage.can_salvage(now): return {"ok":false,"reason":"打捞正在冷却"}
			if not Economy.inventory.can_add("wood",3) or not Economy.inventory.can_add("parts",2): return {"ok":false,"reason":"请留出打捞物空间"}
			var gain: Dictionary = Economy.salvage.do_salvage(now)
			return {"ok":not gain.is_empty(),"message":"打捞整理完成 · 木板 ×3 / 零件 ×2"}
		"shop_general":
			npc_career_panel.close()
			return shop_panel.open_shop("shop_general")
		"open_plant":
			npc_career_panel.close(); hud.open_tab("plant")
			return {"ok":true}
		"open_building":
			npc_career_panel.close(); _on_click_command("craft")
			return {"ok":true}
		"open_events", "replay_event":
			npc_career_panel.close()
			if str(command.id) == "replay_event":
				var event: Dictionary = NpcCatalog.get_event(str(command.get("event_id", "")))
				if event.is_empty(): return {"ok":false,"reason":"未知档案"}
				var opened: Dictionary = npc_world_presenter.open_npc(str(event.npc_ids[0]))
				if not opened.ok: return opened
				return npc_world_presenter.panel.session.command("event", {"id":str(event.id)})
			var opened: Dictionary = npc_world_presenter.open_npc("npc_bai_shi")
			if not opened.ok: return opened
			return npc_world_presenter.panel.session.command("events")
	return {"ok":false,"reason":"未知职业命令"}

func _on_npc_interaction_requested(npc_id: String = "") -> Dictionary:
	# 无参调用是弱引用 ports 的命名门禁；有参通知只清世界输入，不再重复启动 NPC 业务。
	if not npc_id.is_empty():
		actor_controller.cancel()
		_world_press = false
		var resident = npc_world_presenter.actor(npc_id)
		if is_instance_valid(resident):
			npc_world_presenter.face_player(npc_id, player.global_position)
			var offset: Vector3 = resident.global_position - player.global_position
			if Vector2(offset.x, offset.z).length_squared() > 0.0001:
				player.rotation.y = atan2(offset.x, offset.z)
	return {
		"enabled": not _title_active and not _exhausted_rest and not actor_controller.climbing()
			and not room_controller.busy and not dive.active and not building_controller.active
			and not hud.is_panel_open() and not hud.menu.active and not hud.menu.external_open()
			and not hud.world_actions.is_open() and not hud.corner.expanded
			and not shop_panel.is_open() and not npc_career_panel.is_open(),
		"paused": get_tree().paused,
		"sleeping": sleep_cycle.busy,
		"player_indoors": room_service.inside,
		"dialogue_active": hud.narrative_active()
	}

func _setup_save_registry() -> void:
	save_registry.busy_query = func(): return dive.active or dive.switching or Economy.daily.is_settling() or sleep_cycle.busy or building.busy() or actor_controller.climbing()
	var schemas: Dictionary = preload("res://src/save/save_schema.gd").schemas()
	save_registry.register("profile",avatar_profile.to_dict,avatar_profile.from_dict,schemas.profile,avatar_profile.to_dict(),avatar_profile.validate_snapshot,[avatar_profile])
	save_registry.snapshot_validator = _validate_building_world
	save_registry.register("building",building.to_dict,_restore_building,schemas.building,building.to_dict(),building.validate_snapshot,[building])
	var owners := {"economy":Economy,"gather":gather,"pickups":props,"dive":dive,"salvage":Economy.salvage,"time":world_clock,"weather":weather_service}
	for id in owners:
		var owner = owners[id]
		var sources: Array = owner.snapshot_event_sources() if owner.has_method("snapshot_event_sources") else [owner]
		save_registry.register(id,owner.to_dict,owner.from_dict,schemas[id],owner.to_dict(),Callable(),sources)
	save_registry.register("game",capture_world_state,restore_world_state,schemas.game,capture_world_state(),Callable(),[GameState])
	save_registry.register("room",room_service.to_dict,room_service.from_dict,schemas.room,room_service.to_dict(),room_service.validate_snapshot,[room_service])
	save_registry.register("npc",npc_service.to_dict,npc_service.from_dict,schemas.npc,npc_service.to_dict(),npc_service.validate_snapshot,[npc_service])
	save_registry.restored.connect(_after_restore)

func capture_world_state() -> Dictionary:
	# 在屋里存档：世界位置记成太阳房门口的落点。室内状态（床的摆放、在屋里）
	# 由 room 模块自己记，读档时先按门口恢复世界，再进屋里。
	if room_service.inside:
		var door_pose: Vector3 = room_controller.exit_position
		var parked := boat.position
		return {"zone":"zone1","landing":"main","mode":0,"far_sea":GameState.far_sea_unlocked,
			"boat":[parked.x,parked.y,parked.z,boat.rotation.y],
			"player":[door_pose.x,door_pose.y,door_pose.z]}
	var p := player.global_position
	var b := boat.position
	return {"zone":GameState.current_zone,"landing":GameState.landing_id,"mode":actor_controller.mode(),"far_sea":GameState.far_sea_unlocked,"boat":[b.x,b.y,b.z,boat.rotation.y],"player":[p.x,p.y,p.z] if actor_controller.mode()==0 else []}

func restore_world_state(data: Dictionary) -> void:
	data = data.duplicate(true)
	# Economy is already applied while owner signals are blocked. Build its
	# matching support before restoring the actor onto the upgraded shore.
	_on_fishery_changed()
	if Scope.minimal() and not Scope.zone_enabled(str(data.get("zone","zone1"))):
		data.merge({"zone":"zone1","landing":"main","mode":1,"boat":[],"player":[]},true)
	_cancel_pending_pick()
	_ashore_on_arrival = false
	actor_controller.cancel()
	GameState.far_sea_unlocked = bool(data.get("far_sea",false))
	var zone_id := str(data.get("zone","zone1"))
	if not _zone_nodes.has(zone_id): zone_id="zone1"
	GameState.landing_id = str(data.get("landing","main"))
	if building_access!=null and building_access.is_dynamic(GameState.landing_id) and building_access.landing_data(GameState.landing_id).is_empty():
		GameState.landing_id="main"
	var pose: Array = data.get("boat",[])
	if pose.size()==4: boat.place_at(Vector3(pose[0],pose[1],pose[2]),pose[3])
	else:
		var landing: Dictionary = Zones.landing(zone_id,"main")
		boat.place_at(Vector3(landing.boatPark[0],WATER_LEVEL,landing.boatPark[2]),landing.boatYaw)
	var saved_player: Array = data.get("player",[])
	if int(data.get("mode",1)) == GameState.Mode.ASHORE and saved_player.size()==3:
		var saved_point := Vector3(saved_player[0],saved_player[1],saved_player[2])
		var ground = _zone_nodes[zone_id].area_at(saved_point,0.5)
		if ground != null:
			var support: Vector3 = ground.surface_point(saved_point)
			data.player = [support.x,support.y,support.z]
		elif zone_id=="zone1" and _fishery_visual != null and Economy.fishery.unlocked and _fishery_visual.supports(saved_point,false):
			var recovered: Vector2 = _zone_nodes.zone1.get_node("WalkAreas/Walk_zone1_salvage").clamp_point(saved_point.x,saved_point.z)
			data.player = [recovered.x,1.33,recovered.y]
		elif zone_id=="zone5" and building_world.has_method("closest_walk_point"):
			var recovered: Vector3=building_world.closest_walk_point(Vector3(saved_player[0],saved_player[1],saved_player[2]))
			if recovered.is_finite(): data.player=[recovered.x,recovered.y,recovered.z]
	actor_controller.restore_pose(data)
	GameState.enter_zone(zone_id)

func _after_restore() -> void:
	player.apply_avatar(avatar_profile.query())
	props.sync_population(world_clock.query(),boat.position)
	if Scope.minimal(): Economy.daily.observe(world_clock.query())
	Economy.fishery.observe(world_clock.query())
	Economy.sunroom.set_calendar_day(int(world_clock.day))
	Economy.publish_restored()
	# NPC movement/visual refresh is intentionally deferred until the world has restored.
	if shop_panel != null: shop_panel.close()
	if npc_career_panel != null: npc_career_panel.close()
	if npc_world_presenter != null: npc_world_presenter.refresh_after_restore()
	_sync_zone_levels()
	cam.restore_follow(player)
	markers.set_highlight(GameState.current_zone)
	if room_service.inside:
		# 读档时已经在屋里的人：直接把世界收起来、把机位搬进房间，不再播第二次过场。
		room_controller.resync_inside()
	else:
		# 反向：在屋里读了一份「屋外存下的档」，`inside` 已经变回 false，
		# 但场景还停在进屋那一刻（世界全隐藏、背景全黑）。这里把它还原。
		room_controller.resync_outside()
	hud.refresh_after_restore()

func resume_after_dive_map() -> void:
	# Exit-tree cleanup for projections/editors is real, so restore only those ports
	# and projections; do not rerun Main._ready or load/reset any player snapshot.
	for zone in _zone_nodes.values():
		if zone.ground_space != null: zone.ground_space.configure(zone.walk_areas)
	avatar_session.save = func(): return save_game("",true)
	arrival_flow.place_at_dock = _place_new_traveler
	arrival_flow.release_title_camera = func(): title_camera.finish(cam)
	if npc_world_presenter != null:
		npc_world_presenter.sync_world(_npc_world_query())
	get_tree().call_group("dive_resume_listener","resume_after_map_switch")

func _exit_tree() -> void:
	if get_meta("dive_map_suspended",false): return
	if dive != null: dive.dispose()
	if npc_service != null: npc_service.dispose()
	actor_controller.ports.clear()
	actor_controller.after_walk = Callable()
	save_registry.clear()
	navigation.shape_query = Callable()

func validate_world_state(data: Dictionary, layout: Variant = null, fishery_state: Variant = null) -> String:
	var landing: String=str(data.get("landing","main"))
	if building_access!=null and building_access.is_dynamic(landing):
		if str(data.get("zone",""))!="zone5" or building_access.landing_data(landing,building.query() if layout==null else layout).is_empty():
			return "Saved constructed landing is invalid"
	var pos: Array = data.get("player",[])
	if int(data.get("mode",1))==0 and pos.size()==3:
		var zone_id := str(data.get("zone","zone1"))
		if not _zone_nodes.has(zone_id): return "Unknown saved zone"
		if zone_id=="zone5" and layout!=null:
			if not building_world.contains_saved(Vector3(pos[0],pos[1],pos[2]),layout): return "Saved player is outside constructed ground"
		else:
			var point := Vector3(pos[0],pos[1],pos[2])
			var area = _zone_nodes[zone_id].area_at(point,0.5)
			var fishery_owned: bool = zone_id=="zone1" and _fishery_visual != null and (_fishery_visual.ISLAND.has_point(Vector2(point.x,point.z)) or _fishery_visual.supports(point,false))
			if fishery_owned:
				var active: bool = Economy.fishery.unlocked if fishery_state==null else bool(fishery_state)
				if not _fishery_visual.supports(point,active) and not (active and _fishery_visual.supports(point,false)): return "Saved player is outside fishery ground"
			elif area==null: return "Saved player is outside walkable ground"
	var pose: Array = data.get("boat",[])
	var candidate_nav = preload("res://src/navigation/water_navigation.gd").new()
	candidate_nav.shape_query=func(): return _water_shapes(fishery_state)+building_world.water_shapes(building.query() if layout==null else layout)
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
	# 只关掉「本范围里没有入口」的两个场：建造牌（建造命令已禁用）与打捞绞盘。
	#
	# 采集点**不能**跟着一起藏。2026-11-06 之前的写法是
	#   for field in [gather, build_field, salvage_winch]: field.hide()
	#   for node in group("interactable"): if not visible: remove_from_group(...)
	# 结果 10 个采集点在默认范围里全部隐藏并永久离组 —— 键盘和鼠标都聚不到焦，
	# 「海边的贝壳/木料采不了」就是这个。而且离组是单向的，读档/回场景也救不回来。
	# 现在：采集点按所属区块启停，交给可见性判断；离组那一步整段删掉
	# （Interactor 与 HoverCard 本来就会跳过不可见节点）。
	for field in [build_field,salvage_winch]:
		field.hide()
		field.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_gather_scope()
	trade_board.order_model = null
	var supply_landing = _zone_nodes["zone1"].landing_point("salvage")
	trade_board.position = supply_landing.stand_position()+Vector3(-1.6,0,-1.2)
	trade_board.label = "渔场 · 待建"
	trade_board.verb = "建造渔场"
	# Camera remains locked; P is an available lighting/debug tool in this scope.
	cam_panel.process_mode = Node.PROCESS_MODE_DISABLED


## 采集点按所属区块启停（SEA-GATHER-R05）。
##
## 判据是「这个点所在的区块在当前范围里开着吗」，不是「整个场要不要藏」：
## 最小范围仍有 zone1 / zone2 / zone5，那三处的贝壳木料本来就是要采的。
## 未启用区块（zone3/zone4）的点随区块一起隐藏，避免站在启用区块里还能
## 看见隔壁关闭区块的采集物。
func _apply_gather_scope() -> void:
	if gather == null: return
	gather.visible = true
	gather.process_mode = Node.PROCESS_MODE_INHERIT
	for spot in gather.spots:
		if not is_instance_valid(spot): continue
		var zone_id := str(spot.get_meta("zone", ""))
		var on := zone_id == "" or not Scope.minimal() or Scope.zone_enabled(zone_id)
		spot.visible = on
		if on and not spot.is_in_group("interactable"):
			spot.add_to_group("interactable")

func _begin_title() -> void:
	# 从屋里回到标题（重置存档等）：先把房间那套视觉与世界显隐还回去。
	# 不还的话，标题界面的天空会一直是黑的，再进游戏也回不来。
	if room_service != null and room_controller != null:
		if bool(room_service.inside):
			room_controller.exit(true)
		else:
			room_controller.resync_outside()
	_suspend_for_avatar_or_title()
	title_camera.begin(cam)
	start_screen = preload("res://src/ui/start_screen.gd").new()
	start_screen.name = "StartScreen"
	add_child(start_screen)
	start_screen.start_requested.connect(_enter_game)

func _suspend_for_avatar_or_title() -> void:
	_title_active = true
	daylight_rig.apply(world_clock.query().hour)
	_zone_nodes.zone1.get_node("Objects/RoomDoor").hide()
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

func _enter_game() -> void:
	if not _title_active: return
	if avatar_session.active(): return
	if not _save_protected and not avatar_profile.query().completed:
		if is_instance_valid(start_screen): start_screen.process_mode=Node.PROCESS_MODE_DISABLED
		arrival_flow.begin(cam)
		return
	var transition := create_tween()
	transition.tween_method(func(value: float): title_camera.blend(cam,value),0.0,1.0,1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition.tween_callback(func():
		title_camera.finish(cam)
		_resume_after_avatar_or_title())

func _resume_after_avatar_or_title() -> void:
	for entry in _title_layers:
		if not is_instance_valid(entry.node): continue
		entry.node.visible = entry.visible
		entry.node.process_mode = entry.process_mode
	_title_layers.clear()
	props.visible = _title_props.visible
	props.process_mode = _title_props.process_mode
	_title_props.clear()
	_title_active = false
	_zone_nodes.zone1.get_node("Objects/RoomDoor").show()
	daylight_rig.apply(world_clock.query().hour)
	Economy.ticking = _title_economy_ticking
	if is_instance_valid(start_screen): start_screen.queue_free()
	start_screen = null

func _setup_avatar() -> void:
	avatar_profile.changed.connect(func(): player.apply_avatar(avatar_profile.query()))
	avatar_session=preload("res://src/avatar/avatar_session.gd").new()
	avatar_session.name="AvatarSession"
	avatar_session.profile=avatar_profile; avatar_session.player=player; avatar_session.camera=cam
	avatar_session.save=func(): return save_game("",true)
	add_child(avatar_session)
	avatar_session.finished.connect(func(saved: bool):
		_resume_after_avatar_or_title()
		if saved:
			var traveler_name: String = str(avatar_profile.query().name)
			if avatar_session.first_creation:
				_play_arrival_monologue(traveler_name)
			else:
				hud.toast("已保存你的新模样，%s。" % traveler_name, 4.0))
	arrival_flow=preload("res://src/onboarding/arrival_flow.gd").new()
	arrival_flow.name="ArrivalFlow"; arrival_flow.session=avatar_session
	arrival_flow.release_title_camera=func(): title_camera.finish(cam)
	arrival_flow.place_at_dock=_place_new_traveler
	add_child(arrival_flow)

func _place_new_traveler() -> void:
	var landing = _zone_nodes.zone1.landing_point("main")
	# Place traveler slightly further onto the open sunny courtyard deck (z=11.2)
	# while facing the solar cabin (-Z, yaw=PI), so the cabin veranda is right ahead.
	var pos := Vector3(3.15, landing.stand_position().y, 11.2)
	actor_controller.restore_pose({"mode":0,"player":[pos.x,pos.y,pos.z]})
	# Face the solar cabin (-Z) along the harbor deck rather than looking back at the boat.
	player.rotation=Vector3(0,PI,0)
	GameState.landing_id="main"; GameState.enter_zone("zone1")
	cam.restore_follow(player); cam.apply_pose()

func _play_arrival_monologue(traveler_name: String) -> void:
	hud.show_dialogue_sequence([
		{"speaker": traveler_name, "text": "旧城沉进水底之后，只有这座屋顶还留在海面上。木栈桥在晃，但阳光房的玻璃还是暖的。"},
		{"speaker": traveler_name, "text": "船就系在身后的桩子上，挎包里还留着三包生菜种子和八十枚旧瓶盖。"},
		{"speaker": traveler_name, "text": "先去屋前的培养箱把种子种下吧……从今天起，这里就是我的海上落脚处了。"}
	])

func _begin_avatar_edit() -> void:
	if avatar_session.active() or actor_controller.mode()==3: return
	_cancel_action()
	cam_panel.set_open(false); grade.set_open(false)
	if hud.is_panel_open(): hud.toggle_panel()
	_suspend_for_avatar_or_title()
	avatar_session.begin(false)


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
	# 居民点击直接接近交谈，不先弹物体操作气泡。
	if spot.has_signal("npc_requested"):
		_approach(spot)
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
	elif spot == _fishery_harvest or spot == trade_board:
		if spot == _fishery_harvest:
			options.append({"id":"harvest","icon":"fish","label":"收获鱼类","caption":"收获 ×%d" % Economy.fishery.pending,
				"blocked":Economy.fishery.harvest_reason(),"command":func(): _approach_command(spot,_harvest_fishery)})
		elif not Economy.fishery.unlocked:
			options.append({"id":"fishery","icon":"fish","label":"建造渔场","blocked":Economy.fishery.reason(),
				"command":func(): _approach_command(spot,func() -> Dictionary:
					hud.open_aqua_upgrade(_upgrade_fishery);return {"event":"fishery_opened"})})
	else:
		var icon := "hand"
		if spot.is_in_group("shipping_boxes"): icon="shipping"
		elif str(spot.id)=="room_bed": icon="sleep"
		elif str(spot.verb).contains("采"): icon="harvest"
		elif str(spot.verb).contains("挖"): icon="dig"
		var blocked := str(spot.blocked_reason()) if spot.has_method("blocked_reason") else ""
		options.append({"id":"interact","icon":icon,"label":str(spot.verb),"blocked":blocked,"command":func(): _approach(spot)})
	var title := str(spot.label)
	if spot.is_in_group("farm_plots"): title += " · " + Economy.farm.status_text(str(spot.plot_id))
	hud.open_world_actions(_bubble_anchor(spot),options,title,screen)

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
			var area: Variant = here.area_at(p,1.4)
			if area == null: continue
			on_here = true
			if not (area as Node3D).path_between(from, p).is_empty(): return ""
	if on_here: return "那里走不过去，中间没有连通的路"
	for zone_id in _zone_nodes:
		var node: Node = _zone_nodes[zone_id]
		if node == null or node == here: continue
		for p2: Vector3 in points:
			if node.area_at(p2,1.4) != null:
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
	hud.open_world_actions(_bubble_anchor(plot),options,"选择种子 · " + str(plot.plot_name),screen)
	hud.world_actions.back_action = func(): _open_spot_bubbles(plot,screen)

func _approach_command(spot: Node3D, command: Callable) -> void:
	if _approach(spot): interactor.queue_command(spot,command)

func _queue_plot_action(plot: Node3D, action: String, crop: String) -> void:
	_approach_command(plot,func() -> Dictionary:
		if not is_instance_valid(plot): return {"blocked":"种植格已不可用"}
		var result: Dictionary=plot.perform(action,crop)
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
		return result)

func _setup_shipping_box() -> void:
	var box = _zone_nodes.zone1.get_node("Objects/ShippingBox")
	box.opened.connect(func(): hud.open_tab("shipping"))


func _setup_sleep() -> void:
	sleep_curtain = preload("res://src/ui/sleep_curtain.gd").new()
	sleep_curtain.name = "SleepCurtain"
	add_child(sleep_curtain)
	sleep_curtain.focus_query = func(): return cam.unproject_position(player.global_position+Vector3.UP*BodyScale.CAMERA_FOCUS)
	sleep_cycle = preload("res://src/time/sleep_cycle.gd").new()
	sleep_cycle.name = "SleepCycle"
	add_child(sleep_cycle)
	sleep_cycle.clock = world_clock
	sleep_cycle.curtain = sleep_curtain
	if dive != null: dive.curtain = sleep_curtain
	sleep_cycle.prepare = _prepare_sleep
	sleep_cycle.return_home = _wake_at_home
	sleep_cycle.woke.connect(func(_snapshot):
		_restore_sleep_ui()
		hud.toast("早上好 · 作物已长一天 · 07:00 出货箱收货",4.0)
		if _autosave_on: save_game("",true))
	
## SEA-ROOM 接线：状态所有者、过场控制器、入口点、床铺睡觉、界面与存档。
func _setup_room() -> void:
	if room == null:
		return
	room_service.name = "RoomService"
	add_child(room_service)
	room.service = room_service
	room_controller.name = "RoomController"
	add_child(room_controller)
	room_controller.service = room_service
	room_controller.room = room
	room_controller.actor_controller = actor_controller
	room_controller.cam = cam
	room_controller.curtain = sleep_curtain
	room_controller.hud = hud
	room_controller.state = GameState
	room_controller.world_environment = world_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	room_controller.outdoor_nodes = _outdoor_nodes()
	# 出门后站回门口地毯边，面朝太阳房（-Z）。
	var door: Node3D = _zone_nodes.zone1.get_node("Objects/RoomDoor")
	room_controller.exit_position = door.global_position+Vector3(0,0,1.05)
	room_controller.exit_yaw = PI
	door.enter_requested.connect(func() -> void: room_controller.enter())
	room_service.changed.connect(room.apply_layout)
	room_service.changed.connect(func() -> void:
		if room.visible: room.apply_layout())
	room.get_node("Furnishings/Bed").sleep_requested.connect(_rest_for_day)
	room.set_camera(cam)
	room.set_active(false)
	room.apply_layout()


## 进屋要收起来的室外内容。
##
## 房间是**室内**：窗和玻璃前厅外面不该有海、有天、有任何东西。所以连海面
## 与船迹一起收，世界背景由 `room_controller` 切成纯黑（见
## `_apply_interior_environment`）。只留下 Lights（房间的日照与灯要它们）、
## WorldEnvironment 节点本身（背景改黑靠它）与风场。
func _outdoor_nodes() -> Array:
	var nodes: Array = []
	if world_root != null:
		var keep := ["Lights","WorldEnvironment","VegetationWind","Interior"]
		for child in world_root.get_children():
			if child.name in keep: continue
			if child is Node3D or child is CanvasLayer:
				nodes.append(child)
	for node in [boat, bird_root, dive]:
		if is_instance_valid(node): nodes.append(node)
	return nodes


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
	if dive.active: dive.abort_to_surface()
	actor_controller.begin_sleep()
	# Keep rain/world rendering alive; hide gameplay UI until the iris is fully open.
	_sleep_ui_layers.clear()
	for layer in find_children("*","CanvasLayer",true,false):
		if layer==sleep_curtain or layer.name=="WorldWeather": continue
		_sleep_ui_layers.append({"node":layer,"visible":layer.visible})
		layer.hide()
	_sleep_calendar_visible = _calendar_label.visible
	_calendar_label.hide()
	_zone_nodes.zone1.get_node("Objects/RoomDoor").hide()

func _restore_sleep_ui() -> void:
	for entry in _sleep_ui_layers:
		if is_instance_valid(entry.node): entry.node.visible=entry.visible
	_sleep_ui_layers.clear()
	_calendar_label.visible = _sleep_calendar_visible
	_zone_nodes.zone1.get_node("Objects/RoomDoor").show()

func _wake_at_home() -> void:
	# 在屋里床上睡的人，醒来还在屋里（床边站定）；在室外被到点/体力逼着睡的人，
	# 仍旧回太阳房入口。房间不是传送门 —— 睡觉地点决定醒来地点。
	if room_service.inside:
		room_controller.wake_in_room()
		markers.set_highlight("room")
	else:
		var door: Node3D = _zone_nodes.zone1.get_node("Objects/RoomDoor")
		var pos := door.global_position+Vector3(0,0,0.8)
		restore_world_state({"zone":"zone1","landing":"main","mode":0,"player":[pos.x,pos.y,pos.z],"far_sea":GameState.far_sea_unlocked})
		cam.restore_follow(player)
		cam.target = player.global_position+Vector3.UP*BodyScale.CAMERA_FOCUS
		cam.apply_pose()
		markers.set_highlight("zone1")
	daylight_rig.apply(world_clock.query().hour)
	_calendar_label.text = world_clock.query().text + " · " + weather_service.query().label
	# 体力在完全遮黑的这一段里结算：正常睡回满，被体力逼着睡则今天上限减半。
	Economy.energy.after_sleep(sleep_cycle.forced)
	# 换天即生长（SEA-FARM-R14）：作物在玩家看不见的黑幕里长一天，醒来就是新状态。
	# 以前挂在 07:00 的出货结算上，玩家 06:00 醒来看到的还是「昨天已浇、天数没动」，
	# 要多等一个游戏小时才翻页 —— 与牧场/星露谷那种「睡一觉就过一天」不符。
	# `advance_to_day` 以日历日为水位线，同一天只长一次，07:00 的结算再调是空操作。
	if Economy.farm != null: Economy.farm.advance_to_day(world_clock.day)
