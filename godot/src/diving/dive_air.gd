extends RefCounted
class_name DiveAir
## 潜水的代价：氧气。纯状态机，不碰节点，可在 headless 里按固定步长推。
##
## 旧版潜水没有成本 —— 想潜多久潜多久，宝箱列成一张清单挨个点。
## 现在氧气由深度和实际运动负荷共同消耗：悬停、巡航、冲刺形成清晰取舍，头灯不再因可读性被迫关闭。
## 工具动作只有内容事务显式标记时才增加极小成本，不按按键意图或镜头状态误扣。
## 正式潜水不在水下换气，返回海面后才恢复，避免贴近水面无限续航。
## 氧气归零不会直接扣资源，而是**强制上浮**并留一段「需要缓一缓」的冷却，
## 让失败有代价但不必惩罚过重。

const MAX := 100.0
## 高于这个深度算「在水面」，可以换气（单位：米，正数 = 水面以下多深）。
## 具体地图必须把它覆盖到角色胶囊真实可达的浅层上限；不使用不可达的5m/0.5m假换气带。
const SURFACE_DEPTH := 6.0
var surface_depth := SURFACE_DEPTH
## 首轮3–5分钟体验候选A：保留100点UI语义，用深度和实际运动负荷调平路线。
const BASE_RATE := 1.0 / 3.0
const DEPTH_RATE := 0.15
const DEPTH_REFERENCE := 120.0
const MOVE_FACTOR := 1.08
const SPRINT_FACTOR := 1.35
## 工具动作只在未来由内容事务显式传入；头灯是照明，不额外烧气。
const TOOL_COST := 0.02
## 水面每秒回复的量（约 3 秒回满）。
const REFILL_RATE := 34.0
const WARN_LOW := 0.35
const WARN_CRIT := 0.15

var air := MAX
var lamp := true
## 水下首版不换气；离开 runtime 后由 Session/海面状态恢复为 true。
var surface_refill_enabled := true
## 已经报过一次「余气不多」，避免每帧刷提示。
var low_warned := false
var crit_warned := false
## 这一次下潜是否已经耗尽过氧气（强制上浮后复位）。
var emptied := false
## 上浮后的恢复冷却（秒）。大于 0 时不允许再次下潜。
var recover := 0.0

const RECOVER_SECONDS := 6.0


func reset() -> void:
	air = MAX
	lamp = true
	low_warned = false
	crit_warned = false
	emptied = false
	surface_refill_enabled = true
	recover = 0.0


func ratio() -> float:
	return clampf(air / MAX, 0.0, 1.0)


## 当前状态下的每秒消耗（用于 UI 显示「还能待多久」）。
## tool_active 只由潜水内容事务在实际工具动作期间传入，避免按键意图或头灯状态误耗气。
func drain_rate(depth: float, moving: bool, sprint: bool, tool_active := false) -> float:
	var normalized_depth := clampf(maxf(depth, 0.0) / DEPTH_REFERENCE, 0.0, 1.0)
	var movement_factor := SPRINT_FACTOR if (sprint and moving) else (MOVE_FACTOR if moving else 1.0)
	var rate := BASE_RATE * (1.0 + normalized_depth * DEPTH_RATE) * movement_factor
	if tool_active:
		rate += TOOL_COST
	return rate


## 按当前状态还能在水下待几秒。
func seconds_left(depth: float, moving: bool, sprint: bool, tool_active := false) -> float:
	var rate := drain_rate(depth, moving, sprint, tool_active)
	if rate <= 0.001:
		return 999.0
	return air / rate


## 推进一帧。depth 是当前深度（米，正数）。返回本帧发生的事件：
## "" 无 / "low" 余气告警 / "crit" 严重告警 / "empty" 耗尽。
func update(delta: float, depth: float, moving: bool, sprint: bool, tool_active := false) -> String:
	if recover > 0.0:
		recover = maxf(0.0, recover - delta)
	if depth <= surface_depth and surface_refill_enabled:
		# 非潜水兼容预览的海面恢复使用换气带；正式潜水由Controller关闭续气。
		air = minf(MAX, air + REFILL_RATE * delta)
		if air >= MAX - 0.01:
			low_warned = false
			crit_warned = false
			emptied = false
		return ""
	if emptied:
		return ""
	air = maxf(0.0, air - drain_rate(depth, moving, sprint, tool_active) * delta)
	var r := ratio()
	if air <= 0.0:
		emptied = true
		recover = RECOVER_SECONDS
		return "empty"
	if r <= WARN_CRIT and not crit_warned:
		crit_warned = true
		low_warned = true
		return "crit"
	if r <= WARN_LOW and not low_warned:
		low_warned = true
		return "low"
	return ""


## 水面补给（读档 / 重新下潜时用）。
func refill() -> void:
	air = MAX
	low_warned = false
	crit_warned = false
	emptied = false


func can_dive() -> bool:
	return recover <= 0.0


func summary() -> String:
	var pct := int(round(ratio() * 100.0))
	if recover > 0.0:
		return "需要换气 · %.1f s" % recover
	if emptied:
		return "氧气耗尽"
	return "氧气 %d%%%s" % [pct, " · 头灯开" if lamp else ""]
