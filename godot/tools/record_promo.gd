extends SceneTree
## promo 录制时间轴（30 FPS，60 秒 / 1800 帧）。
##
## 用法：
##   godot --path . --resolution 1920x1200 --fixed-fps 30 \
##         --write-movie <out.avi> --script res://tools/_record_promo.gd -- --nosave
##
## 分镜：
##   0.0– 5.8s  标题（SEA + 开始游戏）推近 → 悬停 → 点击开始 → 镜头交接
##   5.8–11.0s  家园：全景收近，看角色、码头、小船
##  11.0–17.3s  点菜箱 → 角色走过去 → 播种完成
##  17.3–21.0s  种植日记面板
##  21.0–26.5s  走回船 → 上船 → 起航
##  26.5–33.3s  驶向浅水养殖台（航线与尾迹）
##  33.3–38.3s  靠泊 → 上岸
##  38.3–46.7s  养殖台近景 → 拉远全景
##  46.7–55.3s  缓慢环绕（鸟、鲸、鱼群）
##  55.3–59.3s  淡出
const TOTAL := 1800

var main: Node
var cam: Camera3D
var fade: ColorRect
var f := 0

func _init() -> void:
	call_deferred("run")

# ── 基础 ──────────────────────────────────────────────────────────────
## 等一帧。用 frame_pre_draw 而不是 process_frame：界面收敛必须发生在
## 节点 _process 之后、渲染之前，否则会被同一帧的 update_from 覆盖回去。
func w(n: int = 1) -> void:
	for i in n:
		await RenderingServer.frame_pre_draw
		_quiet_ui()
		f += 1

## 宣传片专用的界面收敛（只影响本次录制会话）：
##   · 「视野 x%」是一次性调试浮标，逐帧调机位会把它刷成一整条常驻提示；
##   · 底部「操作」大卡片在角色站定于可交互物旁时常驻，会盖住构图。
func _quiet_ui() -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.hud != null:
		main.hud._zoom_left = 0.0
		main.hud._zoom.visible = false
	if main.cam != null:
		main._zoom_seen = main.cam.distance
	if main.prompt != null and main.prompt._panel != null:
		main.prompt._panel.visible = false

func till(target: int) -> void:
	while f < target:
		await w(1)

func wait_until(cond: Callable, limit: int) -> void:
	var start := f
	while not cond.call() and f - start < limit:
		await w(1)

func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

# ── 相机 ──────────────────────────────────────────────────────────────
func cam_move(pos: Vector3, dist: float, frames: int) -> void:
	var p0: Vector3 = cam.target
	var d0: float = cam.distance
	for i in frames:
		var k := smooth(float(i + 1) / float(frames))
		cam.target = p0.lerp(pos, k)
		cam.distance = lerpf(d0, dist, k)
		await w(1)

func cam_zoom(dist: float, frames: int) -> void:
	var d0: float = cam.distance
	for i in frames:
		cam.distance = lerpf(d0, dist, smooth(float(i + 1) / float(frames)))
		await w(1)

func cam_orbit(dyaw: float, dpitch: float, frames: int) -> void:
	for i in frames:
		cam.orbit(dyaw, dpitch)
		await w(1)

func title_dolly(push: float, frames: int) -> void:
	var t0: Transform3D = cam.global_transform
	var forward := -t0.basis.z
	for i in frames:
		var k := smooth(float(i + 1) / float(frames))
		cam.global_transform = Transform3D(t0.basis, t0.origin + forward * push * k)
		await w(1)

# ── 输入 ──────────────────────────────────────────────────────────────
func mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	root.push_input(ev, true)

func hover(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)

func setup_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	main.add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.09, 0.13, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

# ── 主流程 ────────────────────────────────────────────────────────────
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	cam = main.cam
	var gs = root.get_node("GameState")
	var eco = root.get_node("Economy")
	setup_fade()
	# 划船按 1.7 倍推进，只影响本次会话，真实游玩数值不动。
	main.boat.speed_multiplier = func() -> float: return 1.7
	# 底部「操作提示」大卡片：站定在可交互物旁会整段常驻，宣传片里会挡住构图。
	main.prompt._panel.hide()
	await w(2)
	print("[rec] boot title=", main._title_active, " f=", f)

	for i in 24:
		fade.color.a = 1.0 - float(i + 1) / 24.0
		await w(1)

	# A 标题
	await till(24)
	await title_dolly(4.0, 76)
	await till(96)
	var btn: Button = main.start_screen.start_button
	var bpos: Vector2 = btn.get_global_rect().get_center()
	hover(bpos)
	await till(112)
	mouse(bpos, true)
	await w(2)
	mouse(bpos, false)
	await wait_until(func(): return not main._title_active, 160)
	print("[rec] entered game f=", f)

	# B 家园：全景 → 收近
	await till(178)
	await cam_zoom(40.0, 66)
	print("[rec] home wide f=", f)
	await cam_zoom(28.0, 76)
	print("[rec] home close f=", f)

	# C 点菜箱 → 走过去 → 播种
	await till(352)
	var cell: Node3D = main.farm_field.find("home_plot:1")
	var cpos: Vector2 = cam.unproject_position(cell.global_position + Vector3.UP * 0.18)
	hover(cpos)
	await w(8)
	mouse(cpos, true)
	await w(2)
	mouse(cpos, false)
	print("[rec] click plot f=", f)
	await wait_until(func(): return not main._walking and main._auto_target == null, 560)
	print("[rec] planted f=", f, " crop=", eco.farm.crop_of("home_plot:1"))

	# D 种植日记
	await till(545)
	main.hud.open_tab("plant")
	await till(632)
	main.hud.toggle_panel()
	await w(8)
	print("[rec] panel closed f=", f)

	# E 上船 → 出航
	await till(650)
	main._select_landing({"zone": "zone5", "landing": "main"})
	await wait_until(func(): return gs.mode == 2, 420)
	print("[rec] sailing f=", f)
	await cam_zoom(48.0, 60)
	await wait_until(func(): return not main.boat.starts_sailing(), 800)
	print("[rec] docked f=", f, " zone=", gs.current_zone)

	# F 上岸
	await w(16)
	main._select_landing({"zone": "zone5", "landing": "main"})
	await wait_until(func(): return gs.mode == 0, 360)
	print("[rec] ashore f=", f, " player=", main.player.global_position)

	# G 养殖台近景
	await till(1010)
	cam.suspend_follow()
	await cam_move(Vector3(21.6, 1.45, 16.1), 17.0, 66)
	print("[rec] platform f=", f)

	# H 拉远全景
	await till(1150)
	await cam_move(Vector3(11.0, 1.8, 9.5), 66.0, 140)
	print("[rec] wide f=", f, " dist=", cam.distance)

	# I 缓慢环绕
	await till(1300)
	await cam_orbit(-0.0016, 0.0, 170)
	await cam_zoom(72.0, 90)
	await cam_orbit(-0.0012, -0.0005, 110)
	print("[rec] orbit f=", f, " dist=", cam.distance)

	# J 淡出
	await till(1676)
	for i in 118:
		fade.color.a = float(i + 1) / 118.0
		await w(1)
	await till(TOTAL)
	print("[rec] done total=", f)
	quit()
