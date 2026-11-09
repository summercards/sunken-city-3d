extends Camera3D
class_name OrbitCam
## 默认跟随角色；左键拖动越过阈值或触控板平移后手动接管。
## 参考网页版 dampingFactor=0.06，采用时间相关指数阻尼平滑目标。
## 松手后保持手动构图；顶部按钮恢复跟随。滚轮缩放、右键旋转保留。
const BodyScale = preload("res://src/avatar/avatar_dimensions.gd")

@export var target := Vector3(0.45, 1.75, -0.65)
@export var orbit_dir := Vector3(-0.5, 0.7, 0.5)
## 开局机位。区间收窄到 13.82–35.14 之后，原来的 54.25 已在界外，必须重取一个。
##
## 取新区间的 66%（13.82 + 0.66 × 21.32 = 27.9）：旧 54.25 正是 9–77.8 区间的 65.8%，
## 同一个「区间内位置」—— 开局既不钉在最远（2026-11-05 那版「一进游戏就是最远、
## 只能往近处看」已被推翻），也不钉在最近，两端都留出余量。
## 注意两种百分比不是一回事：27.9 m 在**显示刻度**上是 27.5%，在**可到区间**里是 66%。
@export var distance := 27.9
## 缩放下限/上限（**玩家能到的两头**，2026-11-09 按主人截图重新定档）。
##
## 主人给了两张图：最远 = 面板「视野 38%」，最近 = 「视野 7%」。这两张图都是
## 现在这版（区间 9–77.8 m）拍的，所以百分比的含义是
## `d = 9 + pct × (77.8 − 9)`，反解得：
##   最近 9 + 0.07 × 68.8 = 13.82 m
##   最远 9 + 0.38 × 68.8 = 35.14 m
## 区间收窄到这两个值：滚轮再转也不会穿出主人指定的取景。
## 抓图/探针工具若需要更宽取景，在自己脚本里临时抬高 zoom_max，不改玩家上限。
@export var zoom_min := 13.82
@export var zoom_max := 35.14
## 百分比刻度的参照区间：**故意不跟着 zoom_min/zoom_max 走**。
##
## 「视野 %」是主人用来指认机位的语言（38% / 7% 就是他说的那两个位置），
## 所以刻度必须保持稳定：换档只换能到的距离，不换百分比的含义。
@export var zoom_ref_min := 9.0
@export var zoom_ref_max := 77.8
@export var min_distance := 30.0
@export var max_distance := 35.14
@export var cam_fov := 31.0
@export var cam_near := 0.5
@export var cam_far := 600.0
## 平移范围（x 起点, z 起点, 宽, 高），防止把镜头拖到虚空里。
## 必须包住 SEA-NAV 的 150m 可航区（x/z 各 -75..75），再各留 2m，
## 否则船贴着航区边界时会「船在动、镜头被卡住」。
@export var pan_bounds := Rect2(-77.0, -77.0, 154.0, 154.0)
## 俯角范围（度）。低于 22° 会看到海平面切口，高于 78° 会变成纯正俯视看不出立体。
@export var pitch_min_deg := 22.0
@export var pitch_max_deg := 78.0

var dir := Vector3(-0.5, 0.7, 0.5).normalized()
## 当前是否在拖拽（供主场景区分「点击」和「拖镜头」）。
var panning := false
var rotating := false
var camera_machine = preload("res://src/core/state_machine.gd").new()
var input_blocked: Callable
var follow_enabled: bool:
	get: return camera_machine.current in ["", "follow"]
	set(value):
		if not camera_machine.states.is_empty(): camera_machine.change("follow" if value else "manual")
var follow_subject: Node3D
var _pan_pressed := false
var _pan_origin := Vector2.ZERO

## 平滑用的当前值：外部写 target/distance，相机自己追过去。
var _cur_target := Vector3.ZERO
var _cur_distance := 54.25
## 平移惯性（米/秒，世界 xz）。
var _velocity := Vector2.ZERO
## 固定机位（一次性摆放）：由主场景直接写 target/distance/dir，
## 关掉平移边界、高度夹取与鼠标/键盘接管。默认关，室外行为一字未改。
var pose_lock := false
## 「绕着一个东西转」的机位（SEA-ROOM 房间内）。
##
## 和 `pose_lock` 的区别只有一种：**允许鼠标右键拖动旋转、滚轮拉近拉远**，
## 但视点（target）钉死不动。房间只有 5×5 米，一旦允许平移，随手一拖镜头
## 就飘到房间外、只剩一片黑 —— 那是把人关进黑箱，不是「自由」。
##
## 所以这里的自由是「绕着房间转圈看」的自由：任意方位角（四面墙的剖切会跟着
## 换面）、受限的俯仰、受限的远近。默认关，室外行为一字未改。
var orbit_only := false
## `orbit_only` 下允许的俯仰（度）。比室外收窄：低于 26° 相机会贴到地板高度，
## 看见墙的背面；高于 72° 就成了平面图，房间的立体感全没了。
var orbit_pitch_min_deg := 26.0
var orbit_pitch_max_deg := 72.0
## `orbit_only` 下允许的距离（米）。太近会切进家具，太远整屋缩成一个点。
##
## 这两个是**入场时由房间按自身 scale 改写**的运行时值（见
## `RoomController._apply_room_camera`），下面两个常量是它们的出厂基准：
## 房间 1:1 时就是 8–24，房间放大 1.5 倍时变成 12–36。出门时还原成基准。
const ORBIT_ZOOM_MIN := 8.0
const ORBIT_ZOOM_MAX := 24.0
var orbit_zoom_min := ORBIT_ZOOM_MIN
var orbit_zoom_max := ORBIT_ZOOM_MAX
## 抓地平移的锚点（按住时鼠标下的地面点）。
var _grab_world := Vector3.ZERO
var _grab_valid := false
var _drag_last := Vector2.ZERO
var _drag_screen := Vector2.ZERO

const ROT_PER_PIXEL := 0.0062
const WHEEL_STEP := 0.86
const ZOOM_DAMP := 9.0
const TARGET_DAMP := 3.7125 # 网页每帧 0.06 在 60 FPS 下的等效阻尼
const INERTIA_DAMP := 3.4

## ---- 跟随手感（SEA-CAMERA-R14，2026-11-05）----------------------------------
##
## 两件事，各自解决一个具体的「不丝滑」：
##
## 1) **位移继承**：角色每走一步，`_cur_target` 先跟着平移同样的量，只剩「误差」
##    交给阻尼收敛。原实现是让整个 target 从后面追，人匀速走时视点永远落后
##    v·τ ≈ 2.3×0.27 = 0.62 米，一停还会「追上来」多滑一下。继承之后，
##    匀速段零滞后，阻尼只负责吃掉按键抖动与斜坡高度变化。
##
## 2) **前视**：按速度给一个前置量，镜头提前看到「要去的地方」。这是俯视相机
##    的进阶感来源 —— 没有前视，人永远在画面正中，走起来像贴纸在移动。
##    前置量 = clamp(速度) × LEAD_PER_SPEED，走路满速 2.3 × 0.52 = 1.2 米；
##    按 LEAD_TAU 缓入缓出，反向时自然回零，不会突然甩镜头。
##
## 前视只作用于「跟随」；手动接管（`manual`）、固定机位、房间环视都不加。
const LEAD_PER_SPEED := 0.52
const LEAD_MAX := 1.4
const LEAD_TAU := 0.32
## 主体速度估计的平滑时间常数：物理帧位置采样有 1–2 厘米的抖动，
## 不滤会把抖动放大成镜头晃动。
const SUBJECT_VEL_TAU := 0.12
## 超过这个单帧位移就当成传送，不参与速度估计（8 米/帧 ≈ 480 m/s）。
const TELEPORT_STEP := 8.0

var _subject_prev := Vector3.ZERO
var _subject_valid := false
var _subject_vel := Vector3.ZERO
var _lead := Vector3.ZERO


func resume_follow() -> void:
	follow_enabled = true
	_pan_pressed = false
	_end_drag()
	velocity_cancel()
	_forget_subject()

## 跟随目标变化（上下船、读档）时丢掉历史：不丢的话第一帧会把「上一个主体的
## 世界坐标 → 新主体」这段距离当成位移继承进视点，镜头会瞬移一次。
func _forget_subject() -> void:
	_subject_valid = false
	_subject_vel = Vector3.ZERO
	_lead = Vector3.ZERO

## 当前前视偏移（供跟随状态读取）。已缓动，不是原始速度。
func lead() -> Vector3: return _lead

func restore_follow(subject: Node3D) -> void:
	follow_subject = subject
	resume_follow()
	target = subject.global_position + Vector3.UP*BodyScale.CAMERA_FOCUS
	_apply()

func suspend_follow() -> void:
	follow_enabled = false

func _ready() -> void:
	camera_machine.configure(self,{"follow":preload("res://src/camera/states/follow.gd").new(),"manual":preload("res://src/camera/states/manual.gd").new()},{"follow":["manual"],"manual":["follow"]},"follow")
	_cur_target = target
	_cur_distance = clampf(distance, zoom_min, zoom_max)
	refresh()


## 从 export 值应用机位（编辑器保存的值 → 运行时姿态）。
func refresh() -> void:
	dir = orbit_dir.normalized() if orbit_dir.length() > 0.001 else Vector3(-0.5, 0.7, 0.5).normalized()
	_keep_pitch_valid()
	keep_aspect = Camera3D.KEEP_HEIGHT
	fov = cam_fov
	near = cam_near
	far = cam_far
	distance = clampf(distance, _zoom_low(), _zoom_high())
	_cur_distance = distance
	_cur_target = target
	_apply()


## 旧接口：用「相机位置 + 看向点」初始化（脚本建相机时用）。
func setup(cam_pos: Vector3, cam_target: Vector3) -> void:
	target = cam_target
	var offset := cam_pos - cam_target
	distance = offset.length()
	orbit_dir = offset.normalized()
	refresh()


func set_distance(d: float) -> void:
	distance = clampf(d, zoom_min, zoom_max)
	_cur_distance = distance
	_apply()


## 平滑飞到某个区块机位。
func focus_zone(zone: Dictionary) -> void:
	var c = zone.get("camera", null)
	if c == null:
		return
	target = Vector3(c[0], c[1], c[2])


## 立刻应用（截图/调试用；正常交互走 _process 的平滑）。
func _apply() -> void:
	_cur_target = target
	_cur_distance = clampf(distance, zoom_min, zoom_max)
	_update_pose()


func _update_pose() -> void:
	if _cur_distance < 0.2:
		_cur_distance = 0.2
	position = _cur_target + dir * _cur_distance
	if position.distance_to(_cur_target) > 0.01:
		look_at(_cur_target, Vector3.UP)


func _process(delta: float) -> void:
	_track_subject(delta)
	if current: camera_machine.tick(delta)

	# 室内是「绕房间转」而不是「跟人跑」：target 由房间给，任何夹取都只会
	# 把它从 12 米高的房间拖到海平面。
	if not pose_lock and not orbit_only:
		_clamp_target()
	# Following consumes the real character height, including future upper floors.
	# The original manual observation height remains unchanged.
	if not pose_lock and not orbit_only and not follow_enabled: target.y = clampf(target.y, 0.0, 10.0)

	var k := 1.0 - exp(-TARGET_DAMP * delta)
	_cur_target = _cur_target.lerp(target, k)
	var kd := 1.0 - exp(-ZOOM_DAMP * delta)
	_cur_distance = lerpf(_cur_distance, clampf(distance, _zoom_low(), _zoom_high()), kd)
	_update_pose()


## 跟随主体的位移继承 + 速度估计 + 前视缓动（SEA-CAMERA-R14）。
##
## 只在「跟随 + 室外」时生效：手动接管、固定机位、房间环视一律不加，
## 否则玩家自己拖好的构图会被角色的移动重新拽走。
func _track_subject(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	var tracking := follow_enabled and not pose_lock and not orbit_only and is_instance_valid(follow_subject)
	if not tracking:
		_subject_valid = false
		if dt > 0.0:
			_subject_vel = _subject_vel.lerp(Vector3.ZERO, 1.0 - exp(-dt / SUBJECT_VEL_TAU))
			_lead = _lead.lerp(Vector3.ZERO, 1.0 - exp(-dt / LEAD_TAU))
		return
	var now: Vector3 = follow_subject.global_position
	if _subject_valid and dt > 0.0001:
		var step := now - _subject_prev
		# 读档/上下船/调试传送：位移是「跳」不是「走」，别把它摊成速度。
		if step.length() > TELEPORT_STEP:
			_subject_vel = Vector3.ZERO
			_lead = Vector3.ZERO
		else:
			var raw := Vector3(step.x, 0.0, step.z) / dt
			_subject_vel = _subject_vel.lerp(raw, 1.0 - exp(-dt / SUBJECT_VEL_TAU))
		# 视点跟着主体走同样的位移；阻尼只收敛残余误差（不再有匀速段滞后）。
		_cur_target += step
	_subject_prev = now
	_subject_valid = true
	var want := Vector3(_subject_vel.x, 0.0, _subject_vel.z) * LEAD_PER_SPEED
	if want.length() > LEAD_MAX: want = want.normalized() * LEAD_MAX
	_lead = _lead.lerp(want, 1.0 - exp(-dt / LEAD_TAU))


## 键盘不再驱动镜头（SEA-CAMERA-R12，2026-11-05）。
##
## 以前 WASD / 方向键平移、Q/E 旋转，和「角色要用方向键走」直接冲突：
## 按住方向键时人和镜头一起动，E 又同时是交互键。现在键盘全部归角色与交互，
## 镜头只保留鼠标：左键拖拽平移、右键/中键旋转、滚轮与触控板捏合缩放。
## 需要键盘取景的抓图/探针工具自己调 `apply_pose()`，不依赖玩家键位。


func _unhandled_input(event: InputEvent) -> void:
	# 固定机位时镜头不接受任何接管（房间里就是要一个稳定构图）。
	if pose_lock:
		return
	# 面板打开时不抢镜头（面板自己要处理滚轮/拖动）。
	if _ui_blocked():
		_pan_pressed = false
		_end_drag()
		rotating = false
		return

	# 独立取景键，不占角色方向键与 E/Q；室内环视也沿同一约束。
	if event is InputEventKey and event.pressed:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
			_orbit(0.12 if code==KEY_BRACKETLEFT else -0.12,0.0)
		elif code in [KEY_MINUS,KEY_EQUAL]:
			set_distance(distance * (1.08 if code==KEY_MINUS else 1.0/1.08))
		else: return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				# 室内不接左键平移：这里左键留给「点地面走路 / 点家具」。
				if orbit_only:
					return
				if mb.pressed:
					_pan_pressed = true
					_pan_origin = mb.position
					_drag_last = mb.position
				else:
					_pan_pressed = false
					_end_drag()
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					rotating = true
					_drag_last = mb.position
				else:
					rotating = false
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(true, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(false, mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if rotating:
			_orbit(-mm.relative.x * ROT_PER_PIXEL, -mm.relative.y * ROT_PER_PIXEL * 0.7)
		elif orbit_only:
			# 室内没有平移，按住左键拖动也不该有任何镜头反应。
			return
		elif _pan_pressed:
			if not panning and mm.position.distance_to(_pan_origin)>=11.0:
				_begin_pan(_pan_origin)
			if panning: _drag_pan(mm.position)
	elif event is InputEventMagnifyGesture:
		# 触控板捏合：factor > 1 是放大（拉近）。
		var mg := event as InputEventMagnifyGesture
		_zoom_factor(1.0 / maxf(mg.factor, 0.01), mg.position)
	elif event is InputEventPanGesture and not orbit_only:
		# 触控板双指滑动：当地图平移用（比缩放更符合直觉，也解决「滚轮没反应」）。
		# 室内不接：target 钉死，滑动没有可平移的对象。
		suspend_follow()
		var pg := event as InputEventPanGesture
		target += _screen_delta_to_world(pg.delta)
		velocity_cancel()


## 面板打开时镜头不该动：HUD / 打捞面板 / 滤镜面板。
func _ui_blocked() -> bool:
	return not current or (input_blocked.is_valid() and bool(input_blocked.call()))

## ---- 平移 -------------------------------------------------------------------

func _begin_pan(screen: Vector2) -> void:
	# 室内的视点是钉死的：`_unhandled_input` 已经在入口挡住左键，这里再挡一次 ——
	# 以后若有人从别处调这个函数（工具、手柄、脚本），室内也不会被平移。
	if orbit_only:
		return
	suspend_follow()
	panning = true
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	_drag_last = screen
	_drag_screen = screen
	_velocity = Vector2.ZERO
	# 抓地锚点：按下时鼠标下的那块地（水面平面）。拿不到就退化成基向量平移。
	var hit := _ray_plane(screen)
	_grab_valid = hit != Vector3.INF
	_grab_world = hit if _grab_valid else Vector3.ZERO


func _drag_pan(screen: Vector2) -> void:
	pan_action.execute(self,screen)


func _end_drag() -> void:
	panning = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_grab_valid = false
	# 不额外抛掷；target 与 _cur_target 的余量继续平滑收敛。
	_velocity = Vector2.ZERO


func velocity_cancel() -> void:
	_velocity = Vector2.ZERO


## 屏幕像素位移 → 世界位移。取屏幕中心处的「米/像素」，不随视角变化而失准。
func _screen_delta_to_world(px: Vector2) -> Vector3:
	var center := get_viewport().get_visible_rect().size * 0.5
	var a := _ray_plane(center)
	var b := _ray_plane(center + px)
	if a == Vector3.INF or b == Vector3.INF:
		return Vector3.ZERO
	var d := a - b
	d.y = 0.0
	return d


## 光标位置投影到 y = target.y 的水平面。
func _ray_plane(screen: Vector2) -> Vector3:
	var origin := project_ray_origin(screen)
	var dir3 := project_ray_normal(screen)
	if absf(dir3.y) < 0.0001:
		return Vector3.INF
	var plane_y := _cur_target.y
	var t := (plane_y - origin.y) / dir3.y
	if t <= 0.0:
		return Vector3.INF
	return origin + dir3 * t


func _clamp_target() -> void:
	if not pan_bounds.has_area(): return
	target.x = clampf(target.x, pan_bounds.position.x, pan_bounds.end.x)
	target.z = clampf(target.z, pan_bounds.position.y, pan_bounds.end.y)


## ---- 缩放 -------------------------------------------------------------------

func _zoom_at(closer: bool, screen: Vector2) -> void:
	_zoom_factor(WHEEL_STEP if closer else 1.0 / WHEEL_STEP, screen)


## 朝光标缩放：缩放前后，指针下的那块地保持在同一个屏幕位置。
func _zoom_factor(factor: float, screen: Vector2) -> void:
	zoom_action.execute(self,factor,screen)


## ---- 旋转 -------------------------------------------------------------------

func _orbit(dyaw: float, dpitch: float) -> void:
	orbit_action.execute(self,dyaw,dpitch)


## 当前模式下的俯仰上下限（度）。室外 22–78°，室内 26–72°。
func pitch_low() -> float:
	return orbit_pitch_min_deg if orbit_only else pitch_min_deg


func pitch_high() -> float:
	return orbit_pitch_max_deg if orbit_only else pitch_max_deg


## 当前模式下的缩放上下限（米）。
func _zoom_low() -> float:
	return orbit_zoom_min if orbit_only else zoom_min


func _zoom_high() -> float:
	return orbit_zoom_max if orbit_only else zoom_max


func _keep_pitch_valid() -> void:
	var radius := Vector2(dir.x, dir.z).length()
	if radius < 0.0001:
		dir = Vector3(0.0, 0.7, 0.7).normalized()
		return
	var pitch := atan2(dir.y, radius)
	pitch = clampf(pitch, deg_to_rad(pitch_low()), deg_to_rad(pitch_high()))
	var yaw := atan2(dir.x, dir.z)
	dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	orbit_dir = dir


## 给 UI 显示当前缩放百分比（滚轮改变时 HUD 可以闪一下）。
##
## 分母用 `zoom_ref_*`（9–77.8），不是 `zoom_min/zoom_max`：
## 主人是拿这个百分比指认机位的（「最远到 38%」），刻度一动，同一句话就换个画面。
## 于是收窄可以到的区间之后，两头仍显示 7% 与 38%，而不是 0% 与 100%。
func zoom_ratio() -> float:
	return clampf((_cur_distance - zoom_ref_min) / maxf(zoom_ref_max - zoom_ref_min, 0.001), 0.0, 1.0)

var orbit_action = preload("res://src/camera/actions/orbit_action.gd").new()

var zoom_action = preload("res://src/camera/actions/zoom_action.gd").new()

var pan_action = preload("res://src/camera/actions/pan_action.gd").new()

## Public pose commands; underscored versions remain local/legacy test adapters.
func apply_pose() -> void: _apply()
func orbit(dyaw: float, dpitch: float) -> void: _orbit(dyaw,dpitch)
