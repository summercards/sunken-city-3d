extends RefCounted
signal changed(snapshot: Dictionary)
signal day_changed(day: int)
var day := 1
var seconds := 28800.0
var day_length := 1200.0
var paused := false

func configure(config: Dictionary) -> void:
	day_length = maxf(60.0, float(config.get("day_length_seconds", 1200)))

func tick(delta: float) -> void:
	if paused or not is_finite(delta) or delta <= 0.0: return
	var total := seconds + delta * 86400.0 / day_length
	var days := int(floor(total / 86400.0))
	seconds = fmod(total, 86400.0)
	if days > 0:
		day += days
		day_changed.emit(day)
	changed.emit(query())

func rest_to_morning() -> void:
	day += 1
	seconds = 28800.0
	day_changed.emit(day)
	changed.emit(query())

func query() -> Dictionary:
	var hour := seconds / 3600.0
	return {"day":day,"hour":hour,"text":"第%d天 %02d:%02d" % [day,int(hour),int(seconds/60.0)%60],"daylight":clampf(sin((hour-6.0)/12.0*PI),0.0,1.0)}

func to_dict() -> Dictionary: return {"day":day,"seconds":seconds,"day_length":day_length}
func from_dict(data: Dictionary) -> void:
	day = int(data.get("day",1))
	seconds = float(data.get("seconds",28800.0))
	day_length = float(data.get("day_length",1200.0))
	changed.emit(query())
