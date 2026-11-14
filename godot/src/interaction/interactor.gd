extends Node3D
class_name Interactor
## 玩家身上的交互探测器。
##
## 每 0.12 秒扫一次附近的 Interactable，按「面朝向 → 优先级 → 距离」挑一个焦点。
##
## **触发式交互（2026-11-07）**：走近 → 进判定区 → 出现图标 → 点一下就走完。
## 不再要求玩家按住读条 —— 一次按下 = 执行一次，`hold_time` 从「要按多久」
## 变成「动作本身的时长」，由探测器自动推进，按键松不松结果一样。
##
## 朝向不是硬门槛：站在目标旁边背对着它也能操作（用户原话：「直接走近，
## 进入判定区，出现图标，点击即可触发」）。朝向只决定**多目标同在判定区时**
## 谁赢 —— 例如岸边同时够得着种植格和上船口，面朝谁就选谁；
## 差量在误差带内时更近的一方赢。
##
## 这里刻意不做「屏幕点击」：海底/海面/以后的所有可交互物共用同一套规则，
## 换相机、换场景都不用改判定。

signal action_started(spot: Node3D)
signal target_changed(spot: Node3D)
signal progress_changed(ratio: float)
signal completed(spot: Node3D, reward: Dictionary)
signal blocked(reason: String)

## 世界坐标的探测半径（米）。
@export var radius := 2.8
## 扫描间隔，避免每帧遍历整张表。
@export var scan_interval := 0.12
## 走动超过这个距离就取消当前动作。
@export var move_tolerance := 0.35

var active := false
## Optional actor-space query. The interactor never owns navigation or rules.
var reachable_query: Callable
## 点击目标后由 main 打开：小人走到位就自动按住，不用玩家再按 E。
var auto_hold := false
## 点击选择的地格优先，避免相邻六格被最近距离抢走。
var preferred_target: Node3D
## One selected command, consumed at the normal hold completion boundary.
var command_target: Node3D
var selected_command: Callable
var target: Node3D = null
var hold := 0.0
var last_blocked := ""
## 动作正在执行：由一次按下发起，之后自动走完，和按键是否松开无关。
var acting := false
var action_target: Node3D
var _action_generation := 0

var _scan_left := 0.0
var _anchor := Vector3.ZERO
var _blocked_cooldown := 0.0
## 这一次按下已经用掉了，要先松开才允许下一次。
## 触发式交互靠它防连发：按住 E 不会连续种两格、也不会连穿两级菜单。
var _wait_release := false
## 本轮按住已经触发过一次动作（松开时清）。自动接近的命令不占用它。
var _acted_once := false
var keyboard_target: Node3D
## 对齐度分档带宽：差量不超过它的两个目标视为「同等正对」，
## 这时才比优先级和距离。0.08 ≈ 5° 的朝向差。
const FACING_TIE := 0.08
## 脚下近中心豁免半径（米）：站在目标正上方时方向向量没有意义，视为完全正对。
const CENTER_REACH := 0.35

func facing_alignment(point: Vector3) -> float:
	var offset := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if offset.length() <= CENTER_REACH + 0.00001: return 1.0
	var forward := global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().dot(offset.normalized())

func _scan_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node is Node3D or not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		if not node.can_interact(): continue
		if reachable_query.is_valid() and not bool(reachable_query.call(node)): continue
		var focus: Vector3 = node.focus_position()
		var offset: Vector3 = focus - global_position
		if absf(offset.y) > 2.5: continue
		offset.y = 0.0
		var distance := offset.length()
		if distance <= minf(radius, float(node.effective_focus_radius())) + 0.9:
			result.append({"node": node, "focus": focus, "distance": distance})
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		return str((a["node"] as Node3D).get_path()) < str((b["node"] as Node3D).get_path()))
	return result


func candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for entry: Dictionary in _scan_candidates():
		result.append(entry["node"] as Node3D)
	return result

## 手动往返的旧名：现在等于「这一按已经用掉，松开前不再触发」。
func require_release() -> void:
	_cancel_current_action()
	_wait_release = true

func cycle_target(direction := 1) -> bool:
	if not active: return false
	var scanned := _scan_candidates()
	if scanned.is_empty(): return false
	var nearby: Array[Node3D] = []
	for entry: Dictionary in scanned:
		nearby.append(entry["node"] as Node3D)
	var index := nearby.find(target)
	keyboard_target = nearby[posmod(index + direction, nearby.size())]
	_refresh_target_from_scan(scanned)
	return true


static func ensure_input_map() -> void:
	# 输入映射放在代码里注册：project.godot 的 InputEvent 序列化对版本敏感，
	# 而且这样旧存档/旧工程也能直接用。
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event("interact", key)
	if not InputMap.has_action("cancel_action"):
		InputMap.add_action("cancel_action")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("cancel_action", esc)


func _ready() -> void:
	ensure_input_map()
	set_process(true)


func _process(delta: float) -> void:
	update(delta, active and (Input.is_action_pressed("interact") or auto_hold))


## 供测试直接驱动的一帧。
##
## `holding` = 玩家正按着交互键（或自动接近到位）。触发式交互只看「按下的那一下」：
## 一次按下发起一次动作，之后自动走完；连续按住不会触发第二次。
func update(delta: float, holding: bool) -> void:
	var physical_hold := Input.is_action_pressed("interact")
	if not holding:
		# 松开 = 这一轮结束：允许下一次触发。
		_acted_once = false
		if not physical_hold: _wait_release = false
	if not active:
		if physical_hold: _wait_release = true
		if target != null:
			_release()
		if acting: _cancel_current_action()
		_acted_once = false
		return

	var generation := _action_generation
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		_refresh_target()
	if generation != _action_generation:
		return
	if acting and (not is_instance_valid(action_target) or action_target != target \
			or not action_target.is_visible_in_tree() or not action_target.can_interact()):
		_cancel_current_action()
		blocked.emit("操作目标已不可用")
		_acted_once = true
		return

	if not is_instance_valid(target):
		if hold != 0.0 or acting:
			hold = 0.0
			acting = false
			progress_changed.emit(0.0)
		return

	# 动作执行中：自动推进，和按键松不松无关。这一段必须在去重闸门**之前**，
	# 否则一按下去动作就被闸门冻在半路。
	if acting:
		_tick_action(delta)
		return

	if not holding:
		return
	# 一次按住只触发一次：按住 E 不会连开两级菜单、也不会连收两格。
	# `_acted_once` 是本轮已经用掉；`_wait_release` 是上层显式要求的「等松手」。
	#
	# `_wait_release` 只挡**手动**按住。它会在“菜单开着、E 还按着”时被置位，
	# 而菜单确认后执行的是一条 `auto_hold` 命令 —— 若连同 auto_hold 一起挡，
	# 这次按住就永远等不到松开，命令一辈子不执行（2026-11-07 键盘播种卡死）。
	if _acted_once:
		return
	if _wait_release and not auto_hold:
		return
	_begin_action()


## 发起一次动作：锁住目标与落点，然后自动推进到完成。
##
## 手动那一按立刻记「已用掉」——不用等动作走完才记，否则一个 1 秒的动作
## 在完成的瞬间刚好又收到一帧 holding，就会马上发起第二次。
func _begin_action() -> void:
	_anchor = global_position
	last_blocked = ""
	_action_generation += 1
	action_target = target
	acting = true
	hold = 0.0
	if not auto_hold: _acted_once = true
	action_started.emit(action_target)


func _tick_action(delta: float) -> void:
	# 走动打断：脚下挪了位置就重来。
	if global_position.distance_to(_anchor) > move_tolerance:
		hold = 0.0
		progress_changed.emit(0.0)
		if auto_hold:
			# 自动接近中（点了目标让小人自己走过去）：这时候人还在走，
			# 「进度归零」是正确的，「被打断」不是 —— 后者会让上层
			# `blocked` 回调把 `auto_hold` 关掉，于是走到位也不再有进度。
			#
			# 2026-11-06 就是这么坏的：房间放大 1.5 倍后，从门口到床边的路变长，
			# 交互器在还有 1.8 米时就锁定了床并开始 hold，人继续走触发打断，
			# 上层清掉 auto_hold —— 点床边再也不会睡，且没有任何报错。
			#
			# 重设锚点而不是结束：人停稳后从那一刻重新计时，
			# 既不会「边走边采」，也不会把一次正常的接近判成失败。
			_anchor = global_position
			return
		_cancel_current_action()
		blocked.emit("走动打断了操作")
		return

	if _blocked_cooldown > 0.0:
		_blocked_cooldown -= delta

	# 瞬发动作（hold_time 为 0 或很小）当帧完成；有耗时的动作按真实时长推进。
	var need := maxf(action_target.hold_time, 0.0)
	hold += delta
	if hold < need:
		progress_changed.emit(clampf(hold / need, 0.0, 1.0))
		return
	_finish_action(action_target, _action_generation)


func _finish_action(acted_target: Node3D, generation: int) -> void:
	if generation != _action_generation or not acting or not is_instance_valid(acted_target) \
			or acted_target != action_target or acted_target != target:
		return
	hold = 0.0
	acting = false
	action_target = null
	# 无论结果如何，这一轮都用掉了：返回空字典的动作（例如只发事件的房门、
	# 只开面板的绞盘）不能让自动接近每帧重放一次。
	_acted_once = true
	# 自动接近的按住在这一次动作后必须放开。上层的 `completed` 回调只在
	# 有产出时才清理 auto_hold，而返回空字典的动作什么都不发 —— 不在这里清，
	# 角色会永远停在 interacting，自动按住一直挂着。
	auto_hold = false
	var command := selected_command if acted_target == command_target else Callable()
	selected_command = Callable()
	command_target = null
	progress_changed.emit(0.0)
	if generation != _action_generation or not is_instance_valid(acted_target) or acted_target != target \
			or not acted_target.is_visible_in_tree() or not acted_target.can_interact(): return
	var reward: Dictionary
	if command.is_valid(): reward = command.call()
	else: reward = acted_target.interact(self)
	if reward.has("blocked"):
		last_blocked = str(reward.blocked)
		_blocked_cooldown = 0.6
		blocked.emit(last_blocked)
		return
	if not reward.is_empty():
		completed.emit(acted_target, reward)
	# 执行后立刻重选：采空的点不该继续占着焦点。
	_refresh_target()


## 立刻重选一次焦点，不等 0.12 秒的扫描间隔。
##
## 给「一帧之内就要拿到最终答案」的仲裁用。最典型的是菜单刚关、上下船过场刚结束时：
## 那一下 `target` 还是 null，若直接判「旁边没有交互物」，站在菜箱前正对着它
## 也会被读成「想上船」——图标贴在船上，玩家按 E 上了船而不是种菜。
func refresh_now() -> void:
	if not active:
		return
	_scan_left = scan_interval
	_refresh_target()


## 选焦点：**面朝向优先**，同档再看优先级与距离。
##
## 单目标在判定区里直接选中，不看朝向 —— 站在菜箱旁背对着它也能操作。
## 只有多个目标同时够得着时才比朝向（SEA-INTERACT-R24）：岸边同时有种植格和
## 上船口时，面朝谁就选谁；朝向差在 FACING_TIE 以内视为「同等正对」，
## 这时更近/优先级更高的一方赢，避免玩家左右微微一晃就换目标。
func _refresh_target() -> void:
	_refresh_target_from_scan(_scan_candidates())


func _refresh_target_from_scan(scanned: Array[Dictionary]) -> void:
	var best: Node3D = null
	var best_align := -INF
	var best_score := INF
	var nearby: Array[Node3D] = []
	for entry: Dictionary in scanned:
		nearby.append(entry["node"] as Node3D)
	if is_instance_valid(keyboard_target) and not nearby.has(keyboard_target):
		keyboard_target = null
	for entry: Dictionary in scanned:
		var spot: Node3D = entry["node"] as Node3D
		var focus: Vector3 = entry["focus"]
		var dist: float = float(entry["distance"])
		if spot == null or not is_instance_valid(spot):
			continue
		# 显式选择（Q 键盘切目标、点击落下）压过一切自然排序。
		var align := facing_alignment(focus)
		if (is_instance_valid(keyboard_target) and spot == keyboard_target) \
				or (is_instance_valid(preferred_target) and spot == preferred_target):
			align = INF
		# 距离与优先级只在「同等正对」时起作用。
		var score := dist - float(spot.priority) * 0.25
		if align > best_align + FACING_TIE:
			best_align = align
			best_score = score
			best = spot
		elif align > best_align - FACING_TIE and score < best_score:
			best_score = score
			best = spot
	if best == target:
		return
	_release()
	target = best
	hold = 0.0
	if target != null:
		target.focus_enter()
	target_changed.emit(target)


func _cancel_current_action() -> void:
	_action_generation += 1
	acting = false
	action_target = null
	hold = 0.0
	selected_command = Callable()
	command_target = null
	auto_hold = false
	preferred_target = null
	_acted_once = true
	progress_changed.emit(0.0)


func _release() -> void:
	if acting:
		_cancel_current_action()
		blocked.emit("操作目标已改变")
		_acted_once = true
	elif is_instance_valid(target) and target == command_target:
		_cancel_current_action()
	if target != null and is_instance_valid(target) and target.focused:
		target.focus_exit()
	target = null
	hold = 0.0


func progress() -> float:
	if target == null:
		return 0.0
	return clampf(hold / maxf(target.hold_time, 0.01), 0.0, 1.0)


## 测试：绕过扫描直接锁定一个目标。
func debug_focus(spot: Node3D) -> void:
	_release()
	target = spot
	if target != null:
		target.focus_enter()
	target_changed.emit(target)

func cancel() -> void:
	_cancel_current_action()
	selected_command=Callable();command_target=null
	auto_hold=false
	preferred_target=null
	keyboard_target=null
	acting=false
	# 取消是「这一轮结束了」，不是「可以立刻再来一次」。
	#
	# 这里曾经把闸门整个打开（清 `_acted_once`、清 `_wait_release`），结果按着 E
	# 打开气泡菜单时：菜单自己会 `actor_controller.cancel()` → 交互器被取消 →
	# 闸门全开 → 下一帧又发起一次动作、又发一次 options、又取消自己 —— 一个
	# 按住的 E 能把菜单连开两遍（harvest-receive 抓到 completed ==
	# ["options","options","harvested"]）。
	# 正确语义：这一轮结束了。手还按着就必须等松开 —— 但**不能**把整个闸门关死，
	# 否则下一次新按下（手已经松开）也会被挡住。
	_acted_once=false
	_wait_release=Input.is_action_pressed("interact")
	_release()

## 排队一条明确命令（气泡菜单选完种子之类）：走到位就执行，无需再按一次。
##
## **必须清 `_acted_once`**。它是「这次按下已经用掉了」的闸门，只在
## `holding == false` 时复位；而命令式交互的 holding 来自 `auto_hold`，
## 从点下菜单到执行全程为真 —— 不复位的话第二条命令永远进不了
## `_begin_action`，角色停在 `interacting`、`auto_hold` 一直挂着、
## 菜单里选好的动作一次都不执行（2026-11-07：键盘播种全线卡死，
## 只剩一句「背包里没有种子」）。
func queue_command(spot: Node3D, command: Callable) -> void:
	if acting: _cancel_current_action()
	command_target=spot;selected_command=command
	_acted_once=false
	_wait_release=false
