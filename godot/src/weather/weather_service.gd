extends RefCounted
## 天气规则。两种模式：
##   · `fixed`：当前版本使用。天气钉死在 `fixed_kind`（默认晴），不会自己变。
##   · `cycle`：保留的轮换模式。按 `duration` 用确定性随机流换天气。
##
## 改成固定不是把随机逻辑删掉：`seed` 推进、离线冻结、tick 分段一致这几条
## 跨进程契约仍归本服务所有，将来要恢复轮换只改 `weather.json` 的 `mode`。
##
## 存档 `version` 从 2 起。1 及更早没有版本字段，那时天气是随机轮的，
## 存档里的 kind 很可能正好是雨 —— 固定模式下读档必须落到 `fixed_kind`，
## 否则玩家读一次旧档又会变回下雨。
signal changed(snapshot: Dictionary)
const KINDS := ["clear","cloudy","rain"]
const LABELS := {"clear":"晴","cloudy":"多云","rain":"雨"}
const SNAPSHOT_VERSION := 2
var kind := "clear"
var remaining := 240.0
var seed_value := 3701
var duration := 240.0
var fixed := false
var fixed_kind := "clear"
var paused := false

func configure(config: Dictionary) -> void:
	duration = maxf(10.0,float(config.get("duration_seconds",240)))
	seed_value = int(config.get("seed",3701))
	remaining = duration
	fixed = str(config.get("mode","fixed")) == "fixed"
	var wanted := str(config.get("fixed_kind","clear"))
	fixed_kind = wanted if wanted in KINDS else "clear"
	if fixed: kind = fixed_kind

func tick(delta: float) -> void:
	if paused or not is_finite(delta) or delta <= 0.0: return
	# 固定天气不消耗周期：remaining 保持，`changed` 只在显式命令时发。
	if fixed: return
	remaining -= delta
	while remaining <= 0.0:
		seed_value = (seed_value * 48271) % 2147483647
		kind = KINDS[seed_value % KINDS.size()]
		remaining += duration
		changed.emit(query())

func set_weather(next: String) -> bool:
	if not next in KINDS: return false
	kind = next
	remaining = duration
	changed.emit(query())
	return true

func query() -> Dictionary:
	return {"kind":kind,"label":LABELS[kind],"rain":1.0 if kind=="rain" else 0.0,"cloud":0.0 if kind=="clear" else 1.0,"remaining":remaining}
func to_dict() -> Dictionary: return {"version":SNAPSHOT_VERSION,"kind":kind,"remaining":remaining,"seed":seed_value,"duration":duration}
func from_dict(data: Dictionary) -> void:
	# 旧档没有 version：那份 kind 来自随机轮换，固定模式下不沿用。
	if fixed and int(data.get("version",1)) < SNAPSHOT_VERSION:
		kind = fixed_kind
	else:
		var saved := str(data.get("kind","clear"))
		kind = saved if saved in KINDS else "clear"
	remaining = float(data.get("remaining",240))
	seed_value = int(data.get("seed",3701))
	duration = float(data.get("duration",240))
	changed.emit(query())
