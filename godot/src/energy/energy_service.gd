extends Node
class_name EnergyModel
## 体力与疲劳。参考《星露谷物语》：每个行为扣一点体力，见底就撑不住。
##
## 单一写入者：只有本节点改体力；扣费由行为方在**真正结算成功的那一条路径**上
## 通过 `spend()` 发起，拒绝时返回原因字符串，行为方据此不结算。
##
## 两个阈值（2026-11-01 需求）：
##   · 低于 25% —— 疲劳提醒（只提一次，回满后重置）；
##   · 归零 —— 强制休息：主场景播一句「啊，太累了，今天需要休息了」，
##              然后走同一套黑幕过场，第二天体力上限减半。
##
## 上限减半只挂一天：第二天照常睡觉即回满。惩罚用 `pending_half` 记录，
## 不能直接改 `base_max`，否则读档两次会把一半再减一次。

signal changed(current: float, maximum: float)
signal tired
signal exhausted

## 满体力。取 100 而不是星露谷的 270：本作一天行为量少，
## 100 配下面的个位数开销刚好是「一天做二十来件事」。
const BASE_MAX := 100.0
## 疲劳提醒阈值（比例）。见底之前先给一句提示，别让人直接从满格掉进强制睡觉。
const TIRED_RATIO := 0.25
## 每个行为的体力开销。键与行为方传入的 action id 一致。
const COSTS := {
	"plant": 2.0,     # 播种
	"water": 1.0,     # 浇水
	"harvest": 1.0,   # 收获
	"build": 4.0,     # 新建一件（木板/种植区/框架）
	"remove": 3.0,    # 拆回
	"move": 3.0,      # 搬移
	"gather": 3.0,    # 岸边采集
	"pickup": 3.0,    # 海上打捞浮木/鱼群
}

var base_max := BASE_MAX
var maximum := BASE_MAX
var current := BASE_MAX
## 上一次强制休息留下的惩罚：下一次醒来上限减半。
var pending_half := false
var _tired_sent := false
## 每次恢复、回满或扣费都作废旧疲劳等待；不进入存档格式。
var generation := 0

func _ready() -> void:
	current = maximum

## 行为开销；未知行为返回 0，不凭空扣费。
func cost_of(action: String) -> float:
	return float(COSTS.get(action, 0.0))

func ratio() -> float:
	return clampf(current / maxf(maximum, 0.001), 0.0, 1.0)

func is_empty() -> bool:
	return current <= 0.0

## 能不能做这件事？空串表示能。只在**体力已经完全见底**时拒绝；
## 剩 1 点仍允许做，扣到 0 再触发疲劳流程 —— 否则会出现「差 1 点什么都做不了」。
func reason(action: String) -> String:
	if is_empty(): return "太累了，先回去睡觉"
	if cost_of(action) <= 0.0: return ""
	return ""

## 扣费。返回 "" 表示已扣，否则是拒绝原因。
func spend(action: String) -> String:
	var cost := cost_of(action)
	if cost <= 0.0:
		return ""
	var blocked := reason(action)
	if blocked != "": return blocked
	generation += 1
	current = maxf(0.0, current - cost)
	changed.emit(current, maximum)
	_check_thresholds()
	return ""

## 睡觉回满。`forced` = 昨晚是被体力逼着睡的，今天上限减半。
func after_sleep(forced: bool) -> void:
	generation += 1
	if forced: pending_half = true
	maximum = base_max * (0.5 if pending_half else 1.0)
	pending_half = false
	current = maximum
	_tired_sent = false
	changed.emit(current, maximum)

## 立刻回满（调试/自检用；正常流程走 after_sleep）。
func refill() -> void:
	generation += 1
	current = maximum
	_tired_sent = false
	changed.emit(current, maximum)

func _check_thresholds() -> void:
	if not _tired_sent and current > 0.0 and ratio() <= TIRED_RATIO:
		_tired_sent = true
		tired.emit()
	if current <= 0.0:
		exhausted.emit()

func to_dict() -> Dictionary:
	return {"version": 1, "current": current, "maximum": maximum, "pending_half": pending_half}

func from_dict(data: Dictionary) -> void:
	generation += 1
	base_max = BASE_MAX
	maximum = clampf(float(data.get("maximum", BASE_MAX)), 1.0, BASE_MAX)
	current = clampf(float(data.get("current", maximum)), 0.0, maximum)
	pending_half = bool(data.get("pending_half", false))
	_tired_sent = current > 0.0 and ratio() <= TIRED_RATIO
	changed.emit(current, maximum)
