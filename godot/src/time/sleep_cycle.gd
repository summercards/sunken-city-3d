extends Node
## Session flow only; the clock owns time, injected commands own actor/UI changes.
signal woke(snapshot: Dictionary)
const Schedule = preload("res://src/time/day_schedule.gd")
var clock: RefCounted
var curtain: CanvasLayer
var prepare: Callable
var return_home: Callable
var busy := false

func advance(delta: float) -> void:
	if busy or clock.paused or not is_finite(delta) or delta < 0.0: return
	var hour: float = clock.query().hour
	if hour >= Schedule.SLEEP_HOUR or hour < Schedule.WAKE_HOUR:
		request(true)
		return
	# Cap at bedtime before publishing time: a long frame cannot skip into another day.
	var remaining: float = (Schedule.SLEEP_HOUR-hour)*clock.day_length/24.0
	clock.tick(minf(delta,remaining))
	if float(clock.query().hour) >= Schedule.SLEEP_HOUR-0.000001: request(true)

func request(automatic := false) -> void:
	if busy: return
	busy = true
	var was_paused: bool = clock.paused
	clock.paused = true
	prepare.call()
	await curtain.cover("夜深了，回家休息" if automatic else "晚安，明天见")
	clock.wake_to_morning()
	return_home.call()
	await curtain.uncover("第 %d 天 · 早上 06:00" % int(clock.query().day))
	clock.paused = was_paused
	busy = false
	woke.emit(clock.query())

func is_busy() -> bool: return busy
