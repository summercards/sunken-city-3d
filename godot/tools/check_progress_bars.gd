extends SceneTree
## 世界浮层进度条闸门：拾取条 / 建造条共用一份细条，且**只在拾取阶段出现**。
##
## 为什么需要它：这两件事都不会让任何脚本报错，只会"看起来不对"。
##   1. 早先拾取条从点击那一刻就挂在目标头上。船还在十几米外往回划，
##      浮木上方已经有一条 0% 的暗色轨道 —— 玩家读到的信息是"我明明还没开始捞"。
##      正确语义是：航行是航行，拾取是贴近目标开始打捞的那一小段。
##   2. `ProgressBar` 的最小高度由样式盒 content margin 决定（cozy_ui 留了
##      16/16/10/10），代码里写 12px 实际渲染约 20px。想画细条就必须绕开它。
##      这一条只有断言渲染尺寸才盯得住，改回 ProgressBar 不会有任何报错。
##
## 用法：
##   Godot --path godot --script res://tools/check_progress_bars.gd
## 退出码：0 = 全部合格，1 = 有不合格项。

const ThinBar = preload("res://src/ui/thin_progress_bar.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
const BuildingScript = preload("res://src/building/building_controller.gd")
const PickupScript = preload("res://src/pickups/pickup_progress.gd")

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func ok(value: bool, name: String) -> void:
	checks += 1
	print("[progress-bars] ", "PASS " if value else "FAIL ", name)
	if not value:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	_check_control()
	await _check_scene()
	print("[progress-bars] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


## --- 一、控件本身就是细的 ---------------------------------------------------

func _check_control() -> void:
	var build := ThinBar.new()
	build.configure(ThinBar.BUILD_WIDTH, ThinBar.BUILD_HEIGHT, ThinBar.BUILD_FILL, ThinBar.BUILD_TRACK)
	var pick := ThinBar.new()
	pick.configure(ThinBar.PICK_WIDTH, ThinBar.PICK_HEIGHT, ThinBar.PICK_FILL)

	ok(is_equal_approx(build.size.y, 8.0), "建造条实际高 8px（原实现约 20px）")
	ok(is_equal_approx(pick.size.y, 6.0), "拾取条实际高 6px")
	ok(pick.size.y < build.size.y, "拾取条比建造条更细")
	ok(pick.size.x < build.size.x, "拾取条比建造条更窄")
	ok(build.get_script() == pick.get_script(), "两条是同一个控件，不是各画各的")

	# ProgressBar 的 content margin 会把条撑粗；这个断言挡住"改回 ProgressBar"。
	ok(pick.get_class() != "ProgressBar" and build.get_class() != "ProgressBar",
		"不是 ProgressBar，不受 content margin 撑高")

	# cozy_ui 的 apply()/style_tree() 会把 ProgressBar 的最小高拉到 16/18。
	# 细条必须整棵跳过主题，否则任何一次界面刷新都会把它刷回粗条。
	ok(pick.has_meta("cozy_skip"), "拾取条带 cozy_skip 标记")
	ok(build.has_meta("cozy_skip"), "建造条带 cozy_skip 标记")
	Cozy.apply(pick)
	ok(is_equal_approx(pick.size.y, 6.0) and is_equal_approx(pick.custom_minimum_size.y, 6.0),
		"过一遍 cozy 主题后仍是 6px")

	# 圆角 = 半高：细条如果还带一圈描边或大圆角，会重新显粗。
	var corner := int(maxf(1.0, floorf(ThinBar.PICK_HEIGHT * 0.5)))
	ok(corner == 3, "拾取条圆角取半高（3px）")

	# 拾取条浮在**亮蓝水面**上：轨道必须是浅底。
	# 曾用过深青 (0.10,0.24,0.30)，半透明叠在水面上变成一条脏暗线，
	# 远看像水波纹而不是进度条 —— 只有亮度断言能挡住这种"改回去"。
	var track_lum: float = ThinBar.TRACK_COLOR.get_luminance()
	ok(track_lum > 0.7, "拾取轨道是浅底（亮度 %.2f > 0.7）" % track_lum)
	# 填充必须明显比轨道深，否则整条还是一片白、读不出走了多少。
	ok(ThinBar.PICK_FILL.get_luminance() < track_lum - 0.25,
		"填充与轨道有足够明度差（%.2f vs %.2f）"
			% [ThinBar.PICK_FILL.get_luminance(), track_lum])
	# 建造条保留原暖棕底 + 暖金填充，本轮只改粗细不改配色。
	ok(ThinBar.BUILD_TRACK == Color("#584c38") and ThinBar.BUILD_FILL == Color("#e9c16b"),
		"建造条配色未被改动（暖棕 + 暖金）")

	# 两个使用方必须 preload 同一份脚本 —— 否则以后有人复制一份改，粗细又会分家。
	var b_script: Script = BuildingScript
	var p_script: Script = PickupScript
	var b_consts: Dictionary = b_script.get_script_constant_map()
	var p_consts: Dictionary = p_script.get_script_constant_map()
	ok(b_consts.get("ThinBar") == ThinBar, "建造控制器引用共享细条")
	ok(p_consts.get("ThinBar") == ThinBar, "拾取进度引用共享细条")

	build.queue_free()
	pick.queue_free()


## --- 二、挂点是角色，不是目标 ----------------------------------------------
##
## 主人实测截图里"完全看不到进度条"：夜里航行，目标在画面外，
## 条挂在目标上就跟着一起消失了。所以挂点必须是角色。
## 这一段不测时机（时机在第三段），只测"条到底挂在谁头上"。

func _anchor(self_ref) -> Vector3:
	return self_ref.subject.global_position + Vector3.UP * PickupScript.ANCHOR_LIFT


## 把测试相机摆成"跟着角色"的机位（真实玩法里 cam 就是这么跟的）。
func _follow(cam: Camera3D, main) -> void:
	var at: Vector3 = main.player.global_position
	cam.global_position = at + Vector3(-6.0, 9.0, 12.0)
	cam.look_at(at, Vector3.UP)


func _check_anchor(main, cam: Camera3D) -> void:
	var prog = main.pickup_progress
	var bar = prog.bar

	var boat_at := Vector3(0.0, 1.12, 0.0)
	main.boat.place_at(boat_at, 0.0)
	# 用一个临时探针代表"目标"，**不动真实浮木** ——
	# 挪真浮木会污染后面的结算断言（结算要求船与浮木距离 ≤ 2.2 米）。
	var probe := Node3D.new()
	root.add_child(probe)

	# 一、目标在相机背后：正是主人截图里"看不到目标"的那种取景。
	probe.global_position = boat_at + Vector3(40.0, 0.0, 0.0)
	cam.global_position = boat_at + Vector3(10.0, 6.0, 0.0)
	cam.look_at(boat_at + Vector3(-10.0, 0.0, 0.0), Vector3.UP)
	prog.camera = cam

	var behind_point: Vector3 = probe.global_position + Vector3.UP * PickupScript.ANCHOR_LIFT
	ok(cam.is_position_behind(behind_point), "取景：目标确实在相机背后（主人截图的那种构图）")

	prog.begin()
	prog.set_ratio(0.5)
	prog.refresh()

	ok(bar.visible, "目标在画面外时条仍然可见（这就是主人看不到条的那一条）")

	# 二、条必须落在角色头顶正上方。
	var head: Vector3 = _anchor(prog)
	var head_screen: Vector2 = cam.unproject_position(head)
	var center_x: float = bar.position.x + bar.size.x * 0.5
	ok(absf(center_x - head_screen.x) < 2.0,
		"条水平居中对准角色（条心 %.1f / 角色 %.1f）" % [center_x, head_screen.x])
	ok(absf((bar.position.y + bar.size.y) - (head_screen.y - PickupScript.SCREEN_GAP)) < 2.0,
		"条底边压在角色头顶上方 %d px" % int(PickupScript.SCREEN_GAP))

	# 三、条不能落在目标那边。把探针挪到画面侧前方（投影才有意义，
	# 相机背后的点做投影比对会得到镜像位置，那种断言等于没断言）。
	probe.global_position = boat_at + Vector3(0.0, 0.0, 26.0)
	ok(not cam.is_position_behind(probe.global_position), "取景：探针在画面侧前方")
	prog.refresh()
	var probe_x: float = cam.unproject_position(probe.global_position).x
	ok(absf(center_x - probe_x) > 40.0,
		"条与目标投影点分开（差 %.0f px，不再挂在目标上）" % absf(center_x - probe_x))

	# 四、角色动了条跟着动；探针没动。
	var before := Vector2(bar.position)
	main.boat.place_at(boat_at + Vector3(0.0, 0.0, 4.0), 0.0)
	prog.refresh()
	ok(bar.position.distance_to(before) > 8.0, "角色移动后条跟着移动（%.1f px）" % bar.position.distance_to(before))

	prog.clear()
	probe.queue_free()
	# 把船摆回远处，交给第三段重新布景。
	main.boat.place_at(boat_at, 0.0)


## --- 三、场景里的拾取阶段 ----------------------------------------------------
##
## 关键回归（主人两次反馈，都在这段盯住）：
##   1. 点了浮木、船还在划的时候，条**一格都不许走** ——
##      这一段是赶路，人还没开始捞。
##   2. 船停稳、目标够得着，才算「开始打捞」：条从 0 出现、按时间走满、
##      走满才结算。推进到只剩 3 米仍在航行时，条也必须还没出现在。
## 相机每帧跟住角色，跟真实玩法一致（否则会混进"目标出画"的干扰）。

func _check_scene() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	await frames(2)

	var crates: Array = main.props.crates
	ok(crates.size() > 0, "有可拾取的漂流物")
	if crates.is_empty():
		return
	var crate: Dictionary = crates[0]
	var root3d: Node3D = crate.get("root")
	ok(root3d is Node3D, "漂流物带 root 节点")
	ok(main.pickup_progress.subject == main.player, "主场景把角色接成了挂点")

	# 测试相机：单独一台，跟着角色。
	var cam := Camera3D.new()
	root.add_child(cam)
	main.pickup_progress.camera = cam

	await _check_anchor(main, cam)

	var bar = main.pickup_progress.bar
	ok(main.PICK_GATHER_CRATE > 0.3 and main.PICK_GATHER_FISH > main.PICK_GATHER_CRATE,
		"打捞有实际时长（浮木 %.1f 秒 / 鱼群 %.1f 秒）"
			% [main.PICK_GATHER_CRATE, main.PICK_GATHER_FISH])

	# 把船摆到目标 30 米外，直接给一条直线航路（绕开岸线规划）。
	var goal: Vector3 = crate.base + Vector3(1.4, 0.0, 0.0)
	var far := Vector3(crate.base.x - 30.0, 1.12, crate.base.z)
	main.boat.place_at(far, 0.0)
	main.boat.sail_to(goal, 0.0, "", "manual",
		[Vector2(far.x, far.z), Vector2(goal.x, goal.z)])
	main._begin_pick_sail({"type": "crate", "item": crate})

	_follow(cam, main)
	main._update_pickup_progress(1.0 / 60.0)
	ok(not bar.visible, "点了之后立刻不显示条（船还在航行）")
	ok(main._pick_phase == main.PICK_PHASE_SAILING, "进入航行阶段，不是打捞阶段")

	# 一帧一帧把船推向目标，**始终保持航行状态**（不走 _steer：岸线阻挡会提前
	# 停船，那是航线的事，会把「什么时候才该开始捞」这条断言带歪）。
	# 关键回归：一路推到只剩 3 米，人还没停下，条都不许出现。
	var early := false
	for i in 6000:
		main.boat.position = main.boat.position.move_toward(goal, 0.10)
		_follow(cam, main)
		main._update_pickup_progress(1.0 / 60.0)
		if bar.visible:
			early = true
		if main.boat.remaining_distance() <= 3.0:
			break

	ok(main.boat.starts_sailing(), "船仍在航行（只剩 %.1f 米）" % main.boat.remaining_distance())
	ok(not early, "整段航行都没有进度：**船没停就不许走进度条**（主人这次报的就是这条）")
	ok(not bar.visible, "剩 3 米、人还没停下：条不出现")

	# 停稳：这一帧才算「开始打捞」，条从 0 出现。
	main.boat.place_at(goal, 0.0)
	ok(not main.boat.starts_sailing(), "船已停稳")
	main._update_pickup_progress(0.0)
	ok(main._pick_phase == main.PICK_PHASE_GATHERING, "停稳后进入打捞阶段")
	ok(bar.visible, "打捞开始时条才出现")
	ok(bar.ratio <= 0.01, "条从零起步（实测 %.2f）" % bar.ratio)

	# 打捞中：条按时间推进，不是按距离。
	for i in 36:
		main._update_pickup_progress(1.0 / 60.0)
	ok(absf(bar.ratio - 0.5) < 0.06, "打完 0.6 秒（总时长一半）条到约一半（实测 %.2f）" % bar.ratio)
	ok(not main._pending_pick.is_empty(), "打捞没走完之前不结算")

	for i in 40:
		main._update_pickup_progress(1.0 / 60.0)
	ok(main._pending_pick.is_empty() and main._pick_phase == main.PICK_PHASE_IDLE,
		"打捞走完才结算并清掉待拾取")
	ok(is_equal_approx(bar.ratio, 1.0), "结算时条刚好走满")
	ok(bar.visible, "走满后仍可见（停留一拍）")
	main.pickup_progress.tick(0.6)
	ok(not bar.visible, "停留结束后收条")

	# 半路被岸线挡住：船停了，但离目标还有 20 米 —— 不该原地对空气捞 1.2 秒。
	if main.props.crates.size() > 0:
		var crate3: Dictionary = main.props.crates[0]
		main.boat.place_at(Vector3(crate3.base.x - 20.0, 1.12, crate3.base.z), 0.0)
		main._begin_pick_sail({"type": "crate", "item": crate3})
		main._update_pickup_progress(0.0)
		ok(not bar.visible, "停稳但够不着：不打捞、也不显示条")
		ok(main._pending_pick.is_empty(), "够不着时直接作废待拾取")

	# 取消路径：中途取消必须立刻收条，不能留一条永远不走的条。
	if main.props.crates.size() > 0:
		var crate2: Dictionary = main.props.crates[0]
		main.boat.place_at(crate2.base + Vector3(1.4, 0.0, 0.0), 0.0)
		main._begin_pick_sail({"type": "crate", "item": crate2})
		_follow(cam, main)
		main._update_pickup_progress(0.0)
		ok(bar.visible, "停稳且够得着：条出现")
		main._cancel_pending_pick()
		ok(not bar.visible and main._pending_pick.is_empty(), "取消后立即收条并清空待拾取")

	cam.queue_free()
	main.queue_free()
