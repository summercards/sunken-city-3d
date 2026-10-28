extends RefCounted
const Schedule = preload("res://src/time/day_schedule.gd")
## Display calendar only: day 1 is January 1; a 365-day cycle needs no new save fields.
const MONTH_LENGTHS := [31,28,31,30,31,30,31,31,30,31,30,31]
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
	var date:=calendar_date(day)
	return {"day":day,"month":date.month,"day_of_month":date.day_of_month,"hour":hour,
		"text":"%d月%d日 %02d:%02d" % [date.month,date.day_of_month,int(hour),int(seconds/60.0)%60],
		"daylight":clampf(sin((hour-6.0)/12.0*PI),0.0,1.0)}

static func calendar_date(elapsed_day: int) -> Dictionary:
	var remaining: int=(maxi(1,elapsed_day)-1)%365
	for index in MONTH_LENGTHS.size():
		if remaining<int(MONTH_LENGTHS[index]): return {"month":index+1,"day_of_month":remaining+1}
		remaining-=int(MONTH_LENGTHS[index])
	return {"month":1,"day_of_month":1}

func to_dict() -> Dictionary: return {"day":day,"seconds":seconds,"day_length":day_length}
func from_dict(data: Dictionary) -> void:
	day = int(data.get("day",1))
	seconds = float(data.get("seconds",Schedule.MORNING_SECONDS))
	day_length = float(data.get("day_length",1200.0))
	changed.emit(query())
