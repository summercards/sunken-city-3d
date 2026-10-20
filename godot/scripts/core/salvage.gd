extends RefCounted
class_name SalvageModel
## 绞盘打捞的规则层（纯状态机，不碰节点，可在 headless 里按固定步长推）。
##
## 旧版是一次点击 + 40 秒冷却：点完就等，等完再点，中间没有任何操作。
## 现在分三段，每段都要玩家做一个判断：
##
##   1. 下钩（DROP）   钩子匀速下沉，按 E 停住。越深产出越好，但 75% 之后张力涨得更快。
##   2. 收线（REEL）   按住 E 收线（张力上升），松手放线（张力下降）。
##                     张力停在绿区才有进度；顶到红区超过 0.55 秒断线，这一趟作废。
##   3. 结算（DONE）   产出 = 深度 × 准度，深海还额外带玻璃/珍珠。
##
## 关键取舍：**深度不是越高越好**。满深度多一份货，但收线窗口更窄，
## 玩家第一次会冲着到底去，第二次就会开始挑「七八成」这个甜点。

enum Phase { IDLE, DROP, REEL, DONE, FAILED }

## 钩子从水面沉到最深处要多久。
const DROP_SECONDS := 2.6
## 张力在绿区时，收满一次线要多久。
const REEL_SECONDS := 5.4
## 张力绿区上下限。
const SWEET_MIN := 0.42
const SWEET_MAX := 0.78
## 张力到达这里开始计「断线倒计时」。
const SNAP_TENSION := 0.96
const SNAP_GRACE := 0.55
## 深度超过这条线，载荷变重（张力涨得更快）。
const HEAVY_DEPTH := 0.75

var phase: int = Phase.IDLE
## 钩子深度 0..1。
var depth := 0.0
## 当前张力 0..1。
var tension := 0.0
## 收线进度 0..1。
var progress := 0.0
## 本次一共收了多少秒（算准度用）。
var reel_seconds := 0.0
## 张力落在绿区里的累计秒数。
var sweet_seconds := 0.0
## 张力顶格的累计秒数。
var over_seconds := 0.0
## 钩子放得太浅（低于 SHALLOW_DEPTH）时的标记，结算给提示。
var shallow := false
var reason := ""

const SHALLOW_DEPTH := 0.18


func start() -> void:
	phase = Phase.DROP
	depth = 0.0
	tension = 0.18
	progress = 0.0
	reel_seconds = 0.0
	sweet_seconds = 0.0
	over_seconds = 0.0
	shallow = false
	reason = ""


## 按 E / 空格：下钩阶段是「停住」，收线阶段是「用力」。
func press() -> void:
	if phase == Phase.DROP:
		phase = Phase.REEL
		shallow = depth < SHALLOW_DEPTH
		tension = maxf(tension, 0.30)


func update(delta: float, holding: bool) -> void:
	if phase == Phase.DROP:
		depth = minf(1.0, depth + delta / DROP_SECONDS)
		return
	if phase != Phase.REEL:
		return

	reel_seconds += delta
	# 负重：越深张力涨得越快；松手时回落速度固定，于是深水更难稳。
	var load := 1.0 + maxf(0.0, depth - HEAVY_DEPTH) * 2.6
	var rate := (0.78 * load) if holding else -0.86
	tension = clampf(tension + rate * delta, 0.0, 1.0)

	var in_sweet := tension >= SWEET_MIN and tension <= SWEET_MAX
	if in_sweet:
		sweet_seconds += delta
		if holding:
			progress = minf(1.0, progress + delta / REEL_SECONDS)
	if tension >= SNAP_TENSION:
		over_seconds += delta
	else:
		over_seconds = maxf(0.0, over_seconds - delta * 0.9)

	if over_seconds >= SNAP_GRACE:
		phase = Phase.FAILED
		reason = "张力过大，缆绳绷断了"
		return
	if progress >= 1.0:
		phase = Phase.DONE


func is_active() -> bool:
	return phase == Phase.DROP or phase == Phase.REEL


func is_finished() -> bool:
	return phase == Phase.DONE or phase == Phase.FAILED


## 绿区时间占收线时间的比例：0..1。
func accuracy() -> float:
	if reel_seconds <= 0.001:
		return 0.0
	return clampf(sweet_seconds / reel_seconds, 0.0, 1.0)


## 张力相对绿区的偏移（-1 太低 / 0 刚好 / +1 太高），给 UI 上色用。
func tension_offset() -> float:
	if tension < SWEET_MIN:
		return -clampf((SWEET_MIN - tension) / SWEET_MIN, 0.0, 1.0)
	if tension > SWEET_MAX:
		return clampf((tension - SWEET_MAX) / maxf(0.001, 1.0 - SWEET_MAX), 0.0, 1.0)
	return 0.0


## 结算产出。只有 DONE 才有东西；FAILED 返回空字典。
func haul() -> Dictionary:
	if phase != Phase.DONE:
		return {}
	var q := accuracy()
	var out := {}
	out["wood"] = 2 + int(round(depth * 2.4)) + (1 if q >= 0.72 else 0)
	out["parts"] = 1 + int(round(depth * 1.6)) + (1 if q >= 0.9 and depth >= 0.6 else 0)
	if depth >= 0.72 and q >= 0.5:
		out["glass"] = 1
	if depth >= 0.9 and q >= 0.8:
		out["pearl"] = 1
	if shallow:
		out.erase("glass")
		out.erase("pearl")
	return out


## 一行总结，UI 与自检共用。
func summary() -> String:
	match phase:
		Phase.IDLE:
			return "待下钩"
		Phase.DROP:
			return "下钩 %.0f%%" % (depth * 100.0)
		Phase.REEL:
			return "收线 %.0f%% · 准度 %.0f%%" % [progress * 100.0, accuracy() * 100.0]
		Phase.DONE:
			return "收线完成 · 深度 %.0f%% · 准度 %.0f%%" % [depth * 100.0, accuracy() * 100.0]
		_:
			return reason if reason != "" else "断线"
