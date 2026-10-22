extends Camera3D
class_name OrbitCam
## 默认跟随角色；左键拖动越过阈值或触控板平移后手动接管。
## 参考网页版 dampingFactor=0.06，采用时间相关指数阻尼平滑目标。
## 松手后保持手动构图；顶部按钮恢复跟随。滚轮缩放、右键旋转保留。

@export var target := Vector3(0.45, 1.75, -0.65)
@export var orbit_dir := Vector3(-0.5, 0.7, 0.5)
@export var distance := 54.25
## 缩放下限/上限。不再复用 min_distance / max_distance（那两个是旧接口的相容字段）。
@export var zoom_min := 9.0
@export var zoom_max := 190.0
@export var min_distance := 30.0
@export var max_distance := 120.0
@export var cam_fov := 31.0
@export var cam_near := 0.5
@export var cam_far := 600.0
## 平移范围（x 起点, z 起点, 宽, 高），防止把镜头拖到虚空里。
@export var pan_bounds := Rect2(-72.0, -82.0, 156.0, 156.0)
## 俯角范围（度）。低于 22° 会看到海平面切口，高于 78° 会变成纯正俯视看不出立体。
@export var pitch_min_deg := 22.0
@export var pitch_max_deg := 78.0

var dir := Vector3(-0.5, 0.7, 0.5).normalized()
## 当前是否在拖拽（供主场景区分「点击」和「拖镜头」）。
var panning := false
var rotating := false
var follow_enabled := true
var follow_subject: Node3D
var _pan_pressed := false
var _pan_origin := Vector2.ZERO

## 平滑用的当前值：外部写 target/distance，相机自己追过去。
var _cur_target := Vector3.ZERO
var _cur_distance := 60.0
## 平移惯性（米/秒，世界 xz）。
var _velocity := Vector2.ZERO
## 键盘平移速度（米/秒，再乘距离系数）。
var _key_pan_speed := 26.0
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


func resume_follow() -> void:
	follow_enabled = true
	_pan_pressed = false
	_end_drag()
	velocity_cancel()

func suspend_follow() -> void:
	follow_enabled = false

func _ready() -> void:
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
	distance = clampf(distance, zoom_min, zoom_max)
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
	if not _ui_blocked(): _keyboard(delta)
	if follow_enabled and is_instance_valid(follow_subject) and current:
		target = follow_subject.global_position + Vector3.UP*0.7

	# 兼容外部速度输入；日常拖动通过 target 剩余位移缓动。
	if not follow_enabled and not panning and _velocity.length() > 0.01:
		target += Vector3(_velocity.x, 0.0, _velocity.y) * delta
		_velocity *= exp(-INERTIA_DAMP * delta)
		if _velocity.length() < 0.02:
			_velocity = Vector2.ZERO

	_clamp_target()
	target.y = clampf(target.y, 0.0, 10.0)

	var k := 1.0 - exp(-TARGET_DAMP * delta)
	_cur_target = _cur_target.lerp(target, k)
	var kd := 1.0 - exp(-ZOOM_DAMP * delta)
	_cur_distance = lerpf(_cur_distance, clampf(distance, zoom_min, zoom_max), kd)
	_update_pose()


## 键盘平移/旋转。用 physical key 而不是 action，省掉 InputMap 注册。
func _keyboard(delta: float) -> void:
	var vx := 0.0
	var vz := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		vx -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		vx += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		vz -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		vz += 1.0
	var rot := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		rot += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		rot -= 1.0
	if rot != 0.0:
		_orbit(-rot * 1.5 * delta, 0.0)
	if vx == 0.0 and vz == 0.0:
		return
	suspend_follow()
	var boost := 2.4 if (Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_CTRL)) else 1.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	# 键盘速度随高度缩放：拉近时慢，拉远时快，观感一致。
	var speed := _key_pan_speed * boost * clampf(_cur_distance / 90.0, 0.35, 1.8)
	target += (right * vx + fwd * -vz) * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	# 面板打开时不抢镜头（面板自己要处理滚轮/拖动）。
	if _ui_blocked():
		_pan_pressed = false
		_end_drag()
		rotating = false
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
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
		elif _pan_pressed:
			if not panning and mm.position.distance_to(_pan_origin)>=11.0:
				_begin_pan(_pan_origin)
			if panning: _drag_pan(mm.position)
	elif event is InputEventMagnifyGesture:
		# 触控板捏合：factor > 1 是放大（拉近）。
		var mg := event as InputEventMagnifyGesture
		_zoom_factor(1.0 / maxf(mg.factor, 0.01), mg.position)
	elif event is InputEventPanGesture:
		# 触控板双指滑动：当地图平移用（比缩放更符合直觉，也解决「滚轮没反应」）。
		suspend_follow()
		var pg := event as InputEventPanGesture
		target += _screen_delta_to_world(pg.delta)
		velocity_cancel()


## 面板打开时镜头不该动：HUD / 打捞面板 / 滤镜面板。
func _ui_blocked() -> bool:
	var host := get_parent()
	if host == null:
		return false
	var hud = host.get("hud")
	if hud != null and hud.get("_panel_open") == true:
		return true
	var sp = host.get("salvage_panel")
	if sp != null and sp.has_method("is_open") and sp.is_open():
		return true
	for key in ["order_panel","cam_panel"]:
		var panel = host.get(key)
		if panel != null and panel.is_open(): return true
	var grade = host.get("grade")
	if grade != null and grade.visible: return true
	return false


## ---- 平移 -------------------------------------------------------------------

func _begin_pan(screen: Vector2) -> void:
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
	# 每次输入只累计像素增量；由指数阻尼消化余量，与网页 OrbitControls 一致。
	target += _screen_delta_to_world(screen-_drag_last)
	_drag_last = screen
	_clamp_target()


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
	target.x = clampf(target.x, pan_bounds.position.x, pan_bounds.end.x)
	target.z = clampf(target.z, pan_bounds.position.y, pan_bounds.end.y)


## ---- 缩放 -------------------------------------------------------------------

func _zoom_at(closer: bool, screen: Vector2) -> void:
	_zoom_factor(WHEEL_STEP if closer else 1.0 / WHEEL_STEP, screen)


## 朝光标缩放：缩放前后，指针下的那块地保持在同一个屏幕位置。
func _zoom_factor(factor: float, screen: Vector2) -> void:
	if follow_enabled:
		distance = clampf(distance*factor,zoom_min,zoom_max)
		return
	var before := _ray_plane(screen)
	var want := clampf(distance * factor, zoom_min, zoom_max)
	if is_equal_approx(want, distance):
		return
	distance = want
	# 算「缩放后」指针落在哪：临时按新距离摆一次算完立刻还原，
	# 这样距离本身仍然由 _process 平滑过去（不然滚轮会「啪」地跳一档）。
	var old_dist := _cur_distance
	_cur_distance = clampf(distance, zoom_min, zoom_max)
	_update_pose()
	var after := _ray_plane(screen)
	_cur_distance = old_dist
	_update_pose()
	if before != Vector3.INF and after != Vector3.INF:
		var shift := before - after
		shift.y = 0.0
		# 目标修正也平滑收敛，避免缩放时瞬间侧跳。
		target += shift
		_clamp_target()
		_update_pose()


## ---- 旋转 -------------------------------------------------------------------

func _orbit(dyaw: float, dpitch: float) -> void:
	var radius := Vector2(dir.x, dir.z).length()
	var pitch := atan2(dir.y, maxf(radius, 0.0001))
	var yaw := atan2(dir.x, dir.z)
	yaw += dyaw
	pitch = clampf(pitch + dpitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	orbit_dir = dir
	_update_pose()


func _keep_pitch_valid() -> void:
	var radius := Vector2(dir.x, dir.z).length()
	if radius < 0.0001:
		dir = Vector3(0.0, 0.7, 0.7).normalized()
		return
	var pitch := atan2(dir.y, radius)
	pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	var yaw := atan2(dir.x, dir.z)
	dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	orbit_dir = dir


## 给 UI 显示当前缩放百分比（滚轮改变时 HUD 可以闪一下）。
func zoom_ratio() -> float:
	return clampf((_cur_distance - zoom_min) / maxf(zoom_max - zoom_min, 0.001), 0.0, 1.0)
