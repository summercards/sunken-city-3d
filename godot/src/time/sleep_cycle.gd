extends Node
## Session flow only; the clock owns time, injected commands own actor/UI changes.
signal woke(snapshot: Dictionary)
const Schedule = preload("res://src/time/day_schedule.gd")
var clock: RefCounted
var curtain: CanvasLayer
var prepare: Callable
var return_home: Callable
var busy := false
## 这一次是被体力逼着睡的（2026-11-01 SEA-ENERGY）。醒来时 Main 据此把
## 今天的体力上限减半；正常入睡（23:00 自动或门口点击）保持 false。
var forced := false

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

func request(automatic := false, from_exhaustion := false) -> void:
	if busy: return
	busy = true
	forced = from_exhaustion
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

## 体力耗尽：同一套黑幕过场，只是标记这一次是「撑不住了」。
## 台词由调用方（Main）先念，黑幕里的文案仍走自动入睡那一句。
func request_forced() -> void:
	await request(true, true)

func is_busy() -> bool: return busy
