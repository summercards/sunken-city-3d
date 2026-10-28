extends RefCounted
const Schedule = preload("res://src/time/day_schedule.gd")
signal changed(snapshot: Dictionary)
signal day_changed(day: int)
var day := 1
var seconds := Schedule.MORNING_SECONDS
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
	# After midnight, the next morning belongs to the current calendar day.
	if seconds >= Schedule.MORNING_SECONDS: day += 1
	seconds = Schedule.MORNING_SECONDS
	day_changed.emit(day)
	changed.emit(query())

func wake_to_morning() -> void:
	# Midnight-to-dawn saves wake on the same calendar day; all other sleep advances one day.
	var wake_seconds := Schedule.WAKE_HOUR*3600.0
	if seconds >= wake_seconds: day += 1
	seconds = wake_seconds
	day_changed.emit(day)
	changed.emit(query())

func query() -> Dictionary:
	var hour := seconds / 3600.0
	return {"day":day,"hour":hour,"text":"第%d天 %02d:%02d" % [day,int(hour),int(seconds/60.0)%60],"daylight":clampf(sin((hour-6.0)/12.0*PI),0.0,1.0)}

func to_dict() -> Dictionary: return {"day":day,"seconds":seconds,"day_length":day_length}
func from_dict(data: Dictionary) -> void:
	day = int(data.get("day",1))
	seconds = float(data.get("seconds",Schedule.MORNING_SECONDS))
	day_length = float(data.get("day_length",1200.0))
	changed.emit(query())
