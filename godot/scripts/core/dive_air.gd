extends RefCounted
class_name DiveAir
## 潜水的代价：氧气。纯状态机，不碰节点，可在 headless 里按固定步长推。
##
## 旧版潜水没有成本 —— 想潜多久潜多久，宝箱列成一张清单挨个点。
## 现在氧气同时被三件事消耗，玩家每次下潜都要做取舍：
##
##   1. **深度**：越深耗得越快（水压）。浅水几乎没有压力，深沟只能快进快出。
##   2. **动作**：游动比悬浮贵，冲刺（Shift）再乘一档 —— 赶路还是省气，得选。
##   3. **头灯**：开着才能照见远处的宝箱，但每秒额外烧气。
##      于是「看得见」和「待得久」互相挤压，这正是探索该有的张力。
##
## 回到水面（y 高于 SURFACE_Y）会快速换气，几秒就满。
## 氧气归零不会直接扣资源，而是**强制上浮**并留一段「需要缓一缓」的冷却，
## 让失败有代价但不必惩罚过重。

const MAX := 100.0
## 高于这个深度算「在水面」，可以换气（单位：米，正数 = 水面以下多深）。
const SURFACE_DEPTH := 5.0
## 静止悬浮、浅水时的每秒消耗。
const BASE_RATE := 0.85
## 每下潜 1 米额外增加的消耗比例。75m 处约 1.7 倍。
const DEPTH_RATE := 0.009
const MOVE_FACTOR := 1.35
const SPRINT_FACTOR := 1.9
## 头灯每秒的额外消耗。
const LAMP_COST := 0.30
## 水面每秒回复的量（约 3 秒回满）。
const REFILL_RATE := 34.0
const WARN_LOW := 0.35
const WARN_CRIT := 0.15

var air := MAX
var lamp := true
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
	recover = 0.0


func ratio() -> float:
	return clampf(air / MAX, 0.0, 1.0)


## 当前状态下的每秒消耗（用于 UI 显示「还能待多久」）。
func drain_rate(depth: float, moving: bool, sprint: bool) -> float:
	var rate := BASE_RATE * (1.0 + maxf(depth, 0.0) * DEPTH_RATE)
	if moving:
		rate *= SPRINT_FACTOR if sprint else MOVE_FACTOR
	if lamp:
		rate += LAMP_COST
	return rate


## 按当前状态还能在水下待几秒。
func seconds_left(depth: float, moving: bool, sprint: bool) -> float:
	var rate := drain_rate(depth, moving, sprint)
	if rate <= 0.001:
		return 999.0
	return air / rate


## 推进一帧。depth 是当前深度（米，正数）。返回本帧发生的事件：
## "" 无 / "low" 余气告警 / "crit" 严重告警 / "empty" 耗尽。
func update(delta: float, depth: float, moving: bool, sprint: bool) -> String:
	if recover > 0.0:
		recover = maxf(0.0, recover - delta)
	if depth <= SURFACE_DEPTH:
		# 水面换气：快速回满，并清掉告警状态。
		air = minf(MAX, air + REFILL_RATE * delta)
		if air >= MAX - 0.01:
			low_warned = false
			crit_warned = false
			emptied = false
		return ""
	if emptied:
		return ""
	air = maxf(0.0, air - drain_rate(depth, moving, sprint) * delta)
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
