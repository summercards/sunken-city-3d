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
var _nav_grid: Dictionary = {}
## 岸线形状缓存（判断「点的是水面还是陆地」）。
var _shore_shapes: Array = []
var _safe_nav: Dictionary = {}
## 手动航行的航线刷新节流。
var _ribbon_left := 0.0
## 上一帧的相机距离（判断是否在缩放）。
var _zoom_seen := 0.0
## 点击某个可交互物后自动走过去的目标；到位后自动按住 E。
var _auto_target: Node3D = null
## 截图/回归用：把鼠标「钉」在某个屏幕位置（真实鼠标在 headless 截图里永远在 0,0）。
var _debug_mouse := ""
var _surface_lights: Array = []

var _zone_nodes: Dictionary = {}
var _walk_target := Vector3.ZERO
var _walk_area: Node3D = null
var _walking := false
var _walk_path: Array[Vector3] = []
var _after_walk := Callable()
const WALK_SPEED := 2.3

var _t := 0.0
var _ripples := PackedVector4Array()
var _press_pos := Vector2.ZERO
var _world_press := false
var _dragged := false
var _pending_pick := {}
## 存档：当前槽位路径、自动存档倒计时、是否允许自动存档（截图/自检时关掉）。
var _save_path := SaveGameLib.SLOT_PATH
var _autosave_left := AUTOSAVE_SECONDS
var _autosave_on := true


const CozyUI = preload("res://src/ui/cozy_ui.gd")
func _cozy_node_added(node: Node) -> void:
	if node is Control and is_ancestor_of(node): CozyUI.apply_instance.call_deferred(node.get_instance_id())

func _apply_cozy_ui() -> void:
	CozyUI.apply_tree(self)

func _ready() -> void:
	# 水面是接近纯色的大渐变，8 位输出会出现一圈圈可见色阶（网页版有轻微噪声盖住）。
	# 开启去色带比往 shader 里掺噪点干净，也不会让静态截图变脏。
	get_viewport().use_debanding = true
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
	cam._apply()
	_setup_props()
	_setup_dive()
	_setup_hud()
	_setup_prompt()
	_setup_grade()
	_setup_salvage()
	_setup_trade()
	_setup_hover()
	_setup_ribbon()
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
	for a in args:
		if a == "--load":
			load_game()
		elif a.begins_with("--load="):
			load_game(a.trim_prefix("--load="))
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
			hud._toggle_panel()
		if a.begins_with("--tab="):
			if not hud._panel_open:
				hud._toggle_panel()
			hud._tab = a.trim_prefix("--tab=")
			hud._refresh_panel()
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
			cam._apply()
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
				cam._orbit(float(rot[0]), float(rot[1]))
				cam._apply()
		if a.begins_with("--look="):
			# 调试：把镜头对准世界坐标（截图核对采集点/建筑细节用）。
			var look := a.trim_prefix("--look=").split(",")
			if look.size() == 3:
				cam.target = Vector3(float(look[0]), float(look[1]), float(look[2]))
				cam._apply()
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
				for row in Economy.farm.specs:
					var pid := str(row.get("id", ""))
					Economy.farm.plant(pid, Economy.farm.selected_crop)
					var total: float = Economy.farm.grow_days(Economy.farm.selected_crop)
					if a == "--farm=ready":
						Economy.farm.state(pid).remaining = 0.0
					else:
						Economy.farm.state(pid).remaining = total * 0.45
					Economy.farm.state(pid).water = 0.0 if a == "--farm=mid" else 1.0
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
				GameState.set_mode(GameState.Mode.ASHORE)
				_walking = false


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
	_autosave_left = AUTOSAVE_SECONDS
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
	_pending_pick.clear()
	interactor.auto_hold = false
	if _start_walk(area, Vector3(point.x, area.surface_y, point.z)):
		reticle.show_at(Vector3(point.x,area.surface_y,point.z))
	# 点击了地面就消费输入；不通的地面不能继续被解释成水面航行。
	return true


func _current_landing() -> Node3D:
	var zone: Node3D = _zone_nodes.get(GameState.current_zone)
	return zone.landing_point(GameState.landing_id) if zone != null else null


func _start_walk(area: Node3D, target: Vector3) -> bool:
	if boat.starts_sailing():
		return false
	var start := player.global_position
	var landing := _current_landing()
	var ashore := GameState.mode == GameState.Mode.ASHORE
	if not ashore:
		if landing == null or landing.ground() != area:
			hud.toast("请先停靠这块地面的泊位")
			return false
		var park: Vector3 = landing.get_node("BoatPark").global_position
		if Vector2(boat.position.x - park.x, boat.position.z - park.z).length() > 1.0:
			hud.toast("请先靠泊再上岸")
			return false
		start = landing.stand_position()
	elif not area.contains_world(start.x, start.z) or absf(start.y - area.surface_y) > 0.4:
		hud.toast("这里与脚下地面不连通，请换泊位上岸")
		return false
	var path: Array[Vector3] = area.path_between(start, target)
	if path.is_empty():
		hud.toast("地面不连通，无法直接走过去")
		return false
	if not ashore:
		_disembark_near(area, start)
	_after_walk = Callable()
	_walk_area = area
	_walk_target = target
	_walk_path = path
	_walk_path.pop_front()
	_walking = not _walk_path.is_empty()
	GameState.set_mode(GameState.Mode.ASHORE)
	player.set_rowing(false)
	player.set_walking(_walking)
	return true


## 离岸必须先沿同一块地面走回上岸点；到位后才上船并执行航行。
func _depart(action: Callable) -> bool:
	if GameState.mode != GameState.Mode.ASHORE:
		action.call()
		return true
	var landing := _current_landing()
	if landing == null or not _start_walk(landing.ground(), landing.stand_position()):
		return false
	_auto_target = null
	_after_walk = func() -> void:
		_board_player()
		action.call()
	return true



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
	_pending_pick.clear()
	return _depart(func() -> void:
		GameState.set_mode(GameState.Mode.SAILING)
		boat.sail_to_point(p, path)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		if reticle != null:
			reticle.show_at(p, true)
		hud.toast("划向那里"))



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
	if x < -68.0 or x > 76.0 or z < -78.0 or z > 58.0:
		return false
	if _shore_shapes.is_empty():
		var data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/baked/shore.json"))
		if data is Dictionary and data.has("shapes"):
			_shore_shapes = data.shapes
	for s in _shore_shapes:
		var cx := float(s.get("x", 0.0))
		var cz := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0)) + 0.9
		if bool(s.get("round", false)):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= hx * hx:
				return false
		else:
			var hz := float(s.get("hz", hx)) + 0.9
			if absf(x - cx) <= hx and absf(z - cz) <= hz:
				return false
	return true


## 下船：把小人从船锚挂到世界上，落在离目标最近的可站立点
func _disembark_near(area: Node3D, _target: Vector3) -> void:
	var landing := _current_landing()
	if landing == null or landing.ground() != area:
		return
	if player.get_parent() != self:
		player.reparent(self, true)
	player.global_position = landing.stand_position()
	hud.toast("走上 " + Zones.label(GameState.current_zone))


## 回到船上
func _board_player() -> void:
	if player.get_parent() == boat:
		return
	player.reparent(boat, true)
	player.position = Vector3(0, 0.62, -0.30)
	player.rotation = Vector3.ZERO
	player.set_walking(false)
	player.set_rowing(true)
	_walking = false
	_walk_path.clear()
	_after_walk = Callable()
	GameState.set_mode(GameState.Mode.ON_BOAT)
	hud.toast("回到船上")


func _update_walk(delta: float) -> void:
	if not _walking:
		return
	var budget := WALK_SPEED * delta
	while not _walk_path.is_empty() and budget > 0.0:
		var next: Vector3 = _walk_path[0]
		var offset := next - player.global_position
		var distance := offset.length()
		var step := minf(distance, budget)
		if distance > 0.0001:
			player.global_position += offset / distance * step
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-offset.z, offset.x), 1.0 - exp(-12.0 * delta))
		budget -= step
		if distance <= step + 0.0001:
			_walk_path.pop_front()
		else:
			break
	if _walk_path.is_empty():
		_walking = false
		player.set_walking(false)
		var callback := _after_walk
		_after_walk = Callable()
		if callback.is_valid():
			callback.call()


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
	# 只有「每帧/每次启动都不同」的参数在这里写；静态外观交给资源文件。
	water_mat.set_shader_parameter("u_time", 0.0)
	water_mat.set_shader_parameter("water_level", WATER_LEVEL)
	# 深度纹理的 NDC 约定随渲染后端不同，Web(gl_compatibility) 必须换算。
	water_mat.set_shader_parameter("u_reverse_z", RenderFlagsLib.reverse_z())
	# 水面是纯自发光材质，兼容后端对 EMISSION 的解码比 Forward+ 暗一档多。
	water_mat.set_shader_parameter("emission_gain", RenderFlagsLib.water_emission_gain())
	_set_shore_uniforms()
	if water_node.has_method("update_surface"):
		water_node.wake = get_node_or_null("World/BoatWake")

	_ripples.resize(8)
	for i in 8:
		_ripples[i] = Vector4(0, 0, -100, 0)
	water_mat.set_shader_parameter("u_ripples", _ripples)
	water_mat.set_shader_parameter("u_ripple_count", 0)


func _set_shore_uniforms() -> void:
	# Slice actual visible scene geometry at sea level; no hand-authored shore boxes.
	var shore_region: Rect2 = get_node("Camera").pan_bounds.grow(24.0)
	water_node.rebuild_shoreline([get_node("World/Environment"), get_node("World/Zones")], shore_region)


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
	boat.navigation_blocked.connect(func() -> void:
		_pending_pick.clear()
		GameState.set_mode(GameState.Mode.ON_BOAT)
		player.set_rowing(false)
		if ribbon != null:
			ribbon.clear()
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
	markers.build(cam)
	markers.set_highlight(GameState.current_zone)


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
	farm_field.build()
	farm_field.acted.connect(_on_farm_acted)
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
	prompt.action_requested.connect(func() -> void:
		if interactor.target != null: _approach(interactor.target))
	if interactor != null:
		interactor.action_started.connect(func(spot: Node3D) -> void:
			if spot.is_in_group("farm_plots"): player.play_farm_action(spot.verb))
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

	order_panel = get_node_or_null("OrderPanel")
	if order_panel == null:
		order_panel = OrderPanelScript.new()
		order_panel.name = "OrderPanel"
		add_child(order_panel)
	order_panel.model = Economy.orders
	order_panel.fulfill_requested.connect(_on_order_fulfill)
	order_panel.reroll_requested.connect(_on_order_reroll)
	if Economy.orders != null:
		Economy.orders.fulfilled.connect(_on_order_fulfilled)
		Economy.orders.changed.connect(func() -> void:
			if order_panel != null and order_panel.is_open():
				order_panel.refresh())


func _open_orders(_board: Node3D) -> void:
	if order_panel == null or order_panel.is_open():
		return
	order_panel.set_open(true)
	_auto_target = null
	if interactor != null:
		interactor.auto_hold = false


func _on_order_fulfill(uid: String) -> void:
	if Economy.orders == null:
		return
	var res: Dictionary = Economy.orders.fulfill(uid)
	if not res.get("ok", false):
		order_panel.note(str(res.get("reason", "交付失败")))
		return
	order_panel.refresh()


func _on_order_reroll() -> void:
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


## ---- 航线预览 / 水面寻路 -----------------------------------------------------

func _setup_ribbon() -> void:
	ribbon = get_node_or_null("RouteRibbon")
	if ribbon == null:
		ribbon = RouteRibbonScript.new()
		ribbon.name = "RouteRibbon"
		add_child(ribbon)


## 岸线栅格按需建一次：25 个形状 ≈ 268×265 格，一次十几毫秒，不值得每帧算。
##
## 用 `SailNavLib.create_nav_grid()`（src/core，网页版 sail-nav.js 的移植）建矩形障碍，
## 再手工把圆形轮廓（圆弧农场塔、一座圆岛）补进 blocked —— 那个接口只吃 Rect2，
## 用外接正方形会把旁边 3m 的水道也堵死。
func nav_grid() -> Dictionary:
	if not _nav_grid.is_empty():
		return _nav_grid
	var text := FileAccess.get_file_as_string("res://assets/baked/shore.json")
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not data.has("shapes"):
		push_warning("shore.json 读不到，暂停航行")
		_nav_grid = {}
		return _nav_grid
	var shapes: Array = data.shapes
	var rects: Array = []
	var rounds: Array = []
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for s in shapes:
		var x := float(s.get("x", 0.0))
		var z := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0))
		var hz := float(s.get("hz", hx))
		if bool(s.get("round", false)):
			rounds.append(Vector3(x, z, hx))
			min_p = Vector2(minf(min_p.x, x - hx), minf(min_p.y, z - hx))
			max_p = Vector2(maxf(max_p.x, x + hx), maxf(max_p.y, z + hx))
		else:
			rects.append(Rect2(x - hx, z - hz, hx * 2.0, hz * 2.0))
			min_p = Vector2(minf(min_p.x, x - hx), minf(min_p.y, z - hz))
			max_p = Vector2(maxf(max_p.x, x + hx), maxf(max_p.y, z + hz))
	# 四周各留 14m：泊位常常就在岸边，网格边缘不能正好卡在泊位上。
	min_p -= Vector2(14.0, 14.0)
	max_p += Vector2(14.0, 14.0)
	var bounds := Rect2(min_p, max_p - min_p)
	var clearance := 2.3
	var grid: Dictionary = SailNavLib.create_nav_grid(rects, bounds, 0.5, clearance)

	# 圆形轮廓补进去：按格子中心到圆心的距离判定。
	var blocked: PackedByteArray = grid.blocked
	var cols: int = grid.cols
	var rows: int = grid.rows
	var cell: float = grid.cell
	var origin: Vector2 = bounds.position
	for c in rounds:
		var pad: float = float(c.z) + clearance
		var i0 := maxi(0, int(floor((c.x - pad - origin.x) / cell)))
		var i1 := mini(cols - 1, int(floor((c.x + pad - origin.x) / cell)))
		var j0 := maxi(0, int(floor((c.y - pad - origin.y) / cell)))
		var j1 := mini(rows - 1, int(floor((c.y + pad - origin.y) / cell)))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var px := origin.x + (float(i) + 0.5) * cell
				var pz := origin.y + (float(j) + 0.5) * cell
				if Vector2(px - c.x, pz - c.y).length() <= pad:
					blocked[j * cols + i] = 1
	grid.blocked = blocked
	_nav_grid = grid
	return _nav_grid


## 巡航沿用原岸线网格；首尾或窄水道不能通过时，用精确水域网格重规划。
## 失败明确返回空路径，禁止穿岸直线兜底。
func plan_route_to(x: float, z: float) -> Array:
	var from := Vector2(boat.position.x, boat.position.z)
	var goal := Vector2(x, z)
	if not _is_open_water(from.x, from.y) or not _is_open_water(x, z):
		return []
	var grid := nav_grid()
	if grid.is_empty():
		return []
	var path: Variant = SailNavLib.plan_route(grid, from, goal)
	if _valid_water_route(path):
		return path
	if _safe_nav.is_empty():
		_safe_nav = SailNavLib.create_nav_grid([], Rect2(-68, -78, 144, 136), 0.5, 0.9)
		var blocked: PackedByteArray = _safe_nav.blocked
		for j in _safe_nav.rows:
			for i in _safe_nav.cols:
				var p := SailNavLib.cell_center(_safe_nav, i, j)
				blocked[j * int(_safe_nav.cols) + i] = 0 if _is_open_water(p.x, p.y) else 1
		_safe_nav.blocked = blocked
	path = SailNavLib.plan_route(_safe_nav, from, goal)
	return path if _valid_water_route(path) else []

func _valid_water_route(path: Variant) -> bool:
	if path == null or path.size() < 2:
		return false
	for i in range(1, path.size()):
		if not _water_segment_clear(path[i - 1], path[i]):
			return false
	return true

func _water_segment_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / 0.1)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / steps)
		if not _is_open_water(p.x, p.y):
			return false
	return true


## 出航统一入口：规划 → 交给船 → 铺航线预览。
func _sail_to_landing(l: Dictionary, zone_id: String, landing_id: String) -> bool:
	if l.is_empty():
		return false
	var goal := Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2]))
	var path := plan_route_to(goal.x, goal.z)
	if path.is_empty():
		hud.toast("无法到达该泊位")
		return false
	_pending_pick.clear()
	return _depart(func() -> void:
		boat.sail_to(goal, float(l.boatYaw), zone_id, landing_id, path)
		GameState.set_mode(GameState.Mode.SAILING)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		markers.set_highlight(zone_id))


## ---- 悬停铭牌 / 落点环 -------------------------------------------------------

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


## 悬停与自动交互每帧更新：面板打开 / 潜水时整体关掉，避免抢指针。
func _update_pointer_ui() -> void:
	if hover == null:
		return
	var panel_open: bool = (hud != null and hud._panel_open) \
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

	if interactor != null:
		interactor.preferred_target = _auto_target
	if _auto_target == null:
		return
	if not is_instance_valid(_auto_target) or not _auto_target.is_visible_in_tree():
		_auto_target = null
		if interactor != null:
			interactor.auto_hold = false
		return
	var d: float = player.global_position.distance_to(_auto_target.global_position)
	interactor.auto_hold = (not panel_open) and (not _walking) and d <= 2.2


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
		if hud.command_buttons.has("follow"):
			hud.command_buttons.follow.text = "跟随中" if cam.follow_enabled else "回到角色"
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
	if node == null or dive.active:
		return false
	if node.has_method("blocked_reason"):
		var reason: String = node.blocked_reason()
		if reason != "":
			hud.toast(reason)
			return false
	var zone: Node3D = _zone_nodes.get(GameState.current_zone, null)
	if zone == null:
		return false
	var area: Variant = zone.area_containing(node.global_position.x, node.global_position.z)
	if area == null:
		return false
	# 站到目标靠玩家这一侧，别站进物件里；1.35m 约等于采集半径内、又不重叠。
	var from := Vector3(player.global_position.x - node.global_position.x, 0.0,
		player.global_position.z - node.global_position.z)
	if from.length() < 0.01:
		from = Vector3(0.0, 0.0, 1.0)
	var dir := from.normalized()
	var stand: Vector2 = area.clamp_point(
		node.global_position.x + dir.x * 1.35, node.global_position.z + dir.z * 1.35)
	if not _start_walk(area, Vector3(stand.x, area.surface_y, stand.y)):
		return false
	_pending_pick.clear()
	_auto_target = node
	interactor.preferred_target = node
	hud.toast("前往 · " + node.label)
	if reticle != null:
		reticle.show_at(_walk_target)
	return true


## 点在悬停目标上：按类型分派（可交互物走过去 / 上岸桩开船 / 漂流物划过去）。
func _activate_hover(hit: Dictionary) -> bool:
	match str(hit.get("type", "")):
		"spot":
			_approach(hit.node)
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
	props.build()
	props.collected.connect(_on_crate_collected)
	props.fish_collected.connect(_on_fish_collected)


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
		add_child(hud)
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
	_auto_target = null
	_pending_pick.clear()
	_walking = false
	_walk_path.clear()
	_after_walk = Callable()
	player.set_walking(false)
	interactor.auto_hold = false
	interactor.preferred_target = null
	interactor._release()
	if dive.active:
		dive.cancel_navigation()
	elif boat.starts_sailing():
		boat.place_at(boat.position,boat.rotation.y)
		GameState.set_mode(GameState.Mode.ON_BOAT)
		player.set_rowing(false)
	if ribbon != null: ribbon.clear()
	hud.toast("已停止，可点击新的目标")

func _on_click_command(command: String) -> void:
	if command != "cancel" and (salvage_panel.is_open() or order_panel.is_open()):
		hud.toast("请先关闭当前操作面板")
		return
	match command:
		"follow":
			cam.resume_follow()
			hud.toast("镜头跟随角色")
		"close":
			if hud._panel_open: hud._toggle_panel()
		"bag", "plant", "build":
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
			if hud._panel_open: hud._toggle_panel()
			grade.set_open(false)
			cam_panel.set_open(not cam_panel.is_open())
		"grade":
			if hud._panel_open: hud._toggle_panel()
			cam_panel.set_open(false)
			grade.set_open(not grade.visible)
		"rise": dive.swim_to(dive.diver_pos + Vector3.UP*3.0)
		"descend": dive.swim_to(dive.diver_pos + Vector3.DOWN*3.0)
		"lamp": dive._toggle_lamp()


func _on_destination(zone_id: String) -> void:
	if dive.active:
		hud.toast("请先上浮再选择航行目的地")
		return
	if not Zones.is_unlocked(zone_id):
		hud.toast("远海街町需要先升级船只")
		return
	if not _sail_to_landing(Zones.landing(zone_id, "main"), zone_id, "main"):
		return
	hud.toast("启航 · " + Zones.label(zone_id))


func _on_boat_arrived(zone_id: String, landing_id: String) -> void:
	if ribbon != null:
		ribbon.clear()
	# 手动点水面划过来的：没有区块可切，停在原地继续等指令。
	if zone_id == "":
		player.set_rowing(false)
		GameState.set_mode(GameState.Mode.ON_BOAT)
		hud.toast("已停船")
		return
	GameState.landing_id = landing_id
	GameState.enter_zone(zone_id)
	GameState.set_mode(GameState.Mode.ON_BOAT)
	hud.toast("抵达 · " + Zones.label(zone_id))
	markers.set_highlight(zone_id)
	player.set_rowing(false)


## 按下必须发生在世界里；拖出去再拖回来也仍是拖动。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_world_press = false
		_dragged = false
	elif event is InputEventMouseMotion and _world_press:
		_dragged = _dragged or _press_pos.distance_to(event.position) >= 11.0

func _unhandled_input(event: InputEvent) -> void:
	# 潜水时输入归海底世界（游动 / 环视 / 宝箱），海面这边一律不响应。
	if dive != null and dive.active:
		return
	# 打捞面板打开时，E / 空格 / ESC 都归它。
	if salvage_panel != null and salvage_panel.is_open():
		return
	# 订单面板同理：它自己按 ESC 关，别的键点击都不该穿透到世界里。
	if order_panel != null and order_panel.is_open():
		return
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
			hud._toggle_panel()
			get_viewport().set_input_as_handled()
			return
		# ESC：先关面板，再取消「自动走过去」，与网页版 closeActionMenus 的层级一致。
		if key == KEY_ESCAPE:
			if hud._panel_open: hud._toggle_panel()
			else: _cancel_action()
			get_viewport().set_input_as_handled()
			return
	if hud._panel_open or cam_panel.is_open() or grade.visible:
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
			var prop: Dictionary = props.pick(mb.position, cam)
			if not prop.is_empty():
				_handle_prop_click(prop)
				return
			var hit: Dictionary = markers.pick(mb.position)
			if not hit.is_empty():
				_select_landing(hit)
				return
			# 先看点在不在甲板上（走），不在就当作「点水面划船」。
			if _try_walk(mb.position):
				return
			if _try_sail_to(mb.position):
				return


func _select_landing(hit: Dictionary) -> void:
	var zone_id: String = hit.zone
	var landing_id: String = hit.landing
	var selected: Dictionary = Zones.landing(zone_id,landing_id)
	if selected.is_empty(): return
	var park := Vector3(float(selected.boatPark[0]),WATER_LEVEL,float(selected.boatPark[2]))
	if zone_id == GameState.current_zone and landing_id == GameState.landing_id and not boat.starts_sailing() and boat.position.distance_to(park)<1.0:
		if GameState.mode == GameState.Mode.ASHORE:
			_depart(func() -> void: pass)
		else:
			var landing := _current_landing()
			if landing != null:
				_start_walk(landing.ground(), landing.stand_position())
		return
	if not Zones.is_unlocked(zone_id):
		hud.toast("远海街町需要先升级船只")
		return
	var l := Zones.landing(zone_id, landing_id)
	if not _sail_to_landing(l, zone_id, landing_id):
		return
	if reticle != null:
		reticle.show_at(Vector3(float(l.boatPark[0]), WATER_LEVEL, float(l.boatPark[2])), true)
	hud.toast("启航 · " + Zones.label(zone_id) + " · " + str(hit.name))


func _handle_prop_click(prop: Dictionary) -> void:
	if GameState.mode == GameState.Mode.ASHORE:
		_depart(func() -> void: _handle_prop_click(prop))
		return
	if prop.type == "fish":
		var school: Dictionary = prop.item
		var target: Vector3 = school.base
		var goal := target + Vector3(2.1, 0, 0)
		var path := plan_route_to(goal.x, goal.z)
		if path.is_empty():
			hud.toast("无法到达鱼群")
			return
		boat.sail_to(goal, boat.rotation.y, GameState.current_zone, GameState.landing_id, path)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		_pending_pick = {"type": "fish", "item": school}
		hud.toast("驶向鱼群")
	else:
		var crate: Dictionary = prop.item
		var target2: Vector3 = crate.base
		var goal2 := target2 + Vector3(1.4, 0, 0)
		var path2 := plan_route_to(goal2.x, goal2.z)
		if path2.is_empty():
			hud.toast("无法到达漂流物")
			return
		boat.sail_to(goal2, boat.rotation.y, GameState.current_zone, GameState.landing_id, path2)
		if ribbon != null:
			ribbon.show_route(boat.route, WATER_LEVEL)
		_pending_pick = {"type": "crate", "item": crate}
		hud.toast("驶向" + str(PropsScript.CRATE_KINDS.get(crate.kind, {}).get("label", "漂流物资")))
	GameState.set_mode(GameState.Mode.SAILING)


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
	hud.set_diving(false)
	hud.toast("回到水面")


## 调试入口（`--salvage`）：忽略距离，直接开面板。
func _try_salvage() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not Economy.can_salvage(now):
		hud.toast("绞盘还在收线 · %.0f 秒" % Economy.salvage_cooldown_left(now))
		return
	_open_salvage(salvage_winch)


func _on_dive() -> void:
	if boat.starts_sailing():
		hud.toast("先靠岸或停船再潜水")
		return
	if dive.active:
		dive.surface()
		hud.set_diving(false)
		hud.toast("上浮")
		return
	_cancel_action()
	if hud._panel_open: hud._toggle_panel()
	cam_panel.set_open(false)
	grade.set_open(false)
	dive.dive(boat.position, Zones.label(GameState.current_zone))
	# 氧气还没恢复时 dive() 会拒绝并自己发提示，别把 HUD 切成潜水模式。
	if not dive.active:
		return
	player.set_diving(true)
	hud.set_diving(true)
	hud.toast("下潜 · %s" % Zones.label(GameState.current_zone))


## 建造页直接进入前往和自动交付流程。
func _on_focus_site(id: String) -> void:
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
	if dive.active or boat.starts_sailing() or _walking or GameState.mode != GameState.Mode.ASHORE:
		hud.toast("请在岸上站定后休息")
		return
	_auto_target = null
	interactor.auto_hold = false
	var result: Dictionary = Economy.farm.advance_day()
	hud.toast("第 %d 天 · %d 格生长，%d 格成熟" % [result.day,result.grew,result.ready])
	if hud._panel_open: hud._refresh_panel()
	if _autosave_on: save_game("",true)



func _on_upgrade_ship() -> void:
	var r: Dictionary = Economy.upgrade_ship()
	if r.ok:
		hud.toast("小船升到 Lv.%d" % int(r.level))
	else:
		hud.toast(str(r.reason))


func _process(delta: float) -> void:
	_t += delta
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
			and GameState.mode == GameState.Mode.ASHORE and not hud._panel_open \
			and not salvage_panel.is_open() and not order_panel.is_open()
	if prompt != null:
		prompt.update_from(interactor)
	_update_pointer_ui()
	_update_camera_feedback(delta)
	water_mat.set_shader_parameter("u_time", _t)
	if water_node.has_method("update_surface") and not dive.active:
		water_node.update_surface(_t, boat, cam.target)
	if props != null and not dive.active:
		var stopped: bool = not boat.starts_sailing()
		if not _pending_pick.is_empty() and stopped:
			var pending: Dictionary = _pending_pick
			_pending_pick = {}
			if pending.type == "fish":
				props.collect_fish(pending.item)
			else:
				props.collect_crate(pending.item)
		elif stopped:
			var got: Dictionary = props.try_pickup(boat.position, true)
			if not got.is_empty():
				hud.toast("%s · %s" % [got.label, "  ".join(_reward_parts(got.reward))])
	if boat != null:
		water_mat.set_shader_parameter("u_boat", boat.wake_uniform())


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
	GameState.set_mode(GameState.Mode.ON_BOAT)
	cam.focus_zone(Zones.get_zone(zone_id))
	cam.target = Vector3(l.boatPark[0], l.boatPark[1], l.boatPark[2])
	cam._apply()
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
		" env_is_uw=", world_env.environment == dive._uw_env if dive != null else "n/a",
		" fov=", get_viewport().get_camera_3d().fov if get_viewport().get_camera_3d() else -1)
	if dive != null and dive.active:
		print("[capture] uw phase=", dive.phase,
			" diver=", dive.diver_pos,
			" cam=", dive.camera.global_position,
			" dir=", -dive.camera.global_transform.basis.z)
	if hud != null:
		# 提示条是唯一会「用完就消失」的 UI，截图回归时先确认它真的画得出来。
		print("[capture] toast=%s rect=%s alpha=%.2f" % [
			"\"" + hud._toast.text + "\"" if hud._toast != null else "none",
			str(hud._toast_box.get_global_rect()) if hud._toast_box != null else "-",
			hud._toast_box.modulate.a if hud._toast_box != null else -1.0])
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
