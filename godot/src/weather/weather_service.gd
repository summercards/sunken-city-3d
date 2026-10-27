extends RefCounted
signal changed(snapshot: Dictionary)
const KINDS := ["clear","cloudy","rain"]
const LABELS := {"clear":"晴","cloudy":"多云","rain":"雨"}
var kind := "clear"
var remaining := 240.0
var seed_value := 3701
var duration := 240.0
var paused := false

func configure(config: Dictionary) -> void:
	duration = maxf(10.0,float(config.get("duration_seconds",240)))
	seed_value = int(config.get("seed",3701))
	remaining = duration

func tick(delta: float) -> void:
	if paused or not is_finite(delta) or delta <= 0.0: return
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
func to_dict() -> Dictionary: return {"kind":kind,"remaining":remaining,"seed":seed_value,"duration":duration}
func from_dict(data: Dictionary) -> void:
	kind = str(data.get("kind","clear"))
	remaining = float(data.get("remaining",240))
	seed_value = int(data.get("seed",3701))
	duration = float(data.get("duration",240))
	changed.emit(query())
