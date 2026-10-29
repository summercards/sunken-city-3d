extends SceneTree
## SEA-MOVE presentation extension: clips never commit business operations.
var checks := 0
var failures := 0
var events: Array[String] = []

class FutureClip extends RefCounted:
	var samples := 0
	func sample(actor, _delta: float) -> void:
		samples += 1
		actor.body_pivot.rotation.z = 0.2

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	var clock = preload("res://src/player/animation/action_playback.gd").new()
	check(clock.start("", 1.0).is_empty() and clock.start("x", NAN).is_empty(), "bad action clock input rejected")
	var first: Dictionary = clock.start("inspect", 0.5)
	clock.advance(0.2)
	var snapshot: Dictionary = clock.capture()
	snapshot.elapsed = 999.0
	check(is_equal_approx(clock.progress(), 0.4), "query is a copy")
	clock.advance(-1.0); clock.advance(NAN)
	check(is_equal_approx(clock.remaining(), 0.3), "bad delta cannot advance action")
	check(clock.advance(0.3).token == first.token and not clock.active(), "exact duration completes once")
	check(clock.advance(0.3).is_empty() and clock.cancel().is_empty(), "completion cannot repeat")
	var second: Dictionary = clock.start("inspect", 0.5)
	check(second.token > first.token, "repeated requests have distinct tokens")
	var third: Dictionary = clock.start("collect", 1.0)
	check(third.replaced.token == second.token and clock.capture().id == "collect", "replacement captures old action")
	clock.cancel()

	var actor = preload("res://src/player/character.gd").new()
	actor.set_process(false)
	root.add_child(actor)
	actor.build()
	actor.action_started.connect(func(id: String, token: int): events.append("start:%s:%d" % [id,token]))
	actor.action_finished.connect(func(id: String, token: int): events.append("finish:%s:%d" % [id,token]))
	actor.action_cancelled.connect(func(id: String, token: int, reason: String): events.append("cancel:%s:%d:%s" % [id,token,reason]))
	var origin: Vector3 = actor.global_position
	actor._process(0.0)
	check(actor.animation_state() == "idle", "idle remains initial clip")
	var harvest: int = actor.play_action("harvesting")
	check(harvest > 0 and actor.animation_state() == "harvesting", "public harvest presentation command")
	actor._process(0.55)
	check(is_equal_approx(actor.body_pivot.rotation.x, 0.38), "harvest original midpoint pose")
	check(is_equal_approx(actor.action_progress(), 0.5), "normalized action progress")
	check(actor.play_action("unknown") == 0 and actor.action_playback().token == harvest, "unknown clip leaves current action intact")
	actor._process(0.55)
	check(events.count("finish:harvesting:%d" % harvest) == 1 and actor.action_playback().is_empty(), "finite action finishes once")
	actor._process(0.0)
	check(actor.animation_state() == "idle", "completed clip returns to locomotion")
	check(actor.global_position == origin, "sampling never moves gameplay root")

	for row in [["播种","planting",0.3],["浇水","watering",0.22],["收获","harvesting",0.38]]:
		actor.play_farm_action(row[0])
		actor._process(0.55)
		check(actor.animation_state() == row[1] and is_equal_approx(actor.body_pivot.rotation.x, float(row[2])), "legacy farm clip pose " + str(row[1]))
		actor.cancel_action("test")

	var interrupted: int = actor.play_action("watering")
	var replacement: int = actor.play_action("planting")
	check(replacement > interrupted and events.count("cancel:watering:%d:replaced" % interrupted) == 1, "replacement cancels previous token once")
	actor.set_walking(true)
	actor._process(0.0)
	check(actor.animation_state() == "walking" and actor.action_playback().is_empty(), "walking takes over transient action")
	check(events.count("cancel:planting:%d:walking" % replacement) == 1, "walking cancellation is observable")
	actor.set_walking(false)
	actor.set_rowing(true); actor._process(0.0)
	check(actor.animation_state() == "rowing", "rowing remains existing clip")
	actor.set_rowing(false)
	actor.set_diving(true); actor._process(0.0)
	check(actor.animation_state() == "swimming" and actor.gear.visible and actor.mask.visible, "swim clip and equipment preserved")
	actor.set_diving(false); actor._process(0.0)
	check(actor.animation_state() == "idle" and not actor.gear.visible and not actor.mask.visible, "restore clears swim presentation")

	var future := FutureClip.new()
	check(actor.register_action("inspect", future, 0.4), "new interaction clip uses registration port")
	check(not actor.register_action("idle", future, 0.4) and not actor.register_action("broken", null, 0.4), "existing and invalid clips cannot overwrite catalog")
	check(not actor.register_action("bad-time", future, -1.0), "bad clip duration rejected")
	var inspect: int = actor.play_action("inspect")
	actor._process(0.2)
	check(future.samples == 1 and is_equal_approx(actor.body_pivot.rotation.z, 0.2), "registered clip samples through same presentation path")
	var query: Dictionary = actor.action_playback()
	query.id = "corrupted"
	check(actor.action_playback().id == "inspect", "presentation query cannot change active clip")
	actor.cancel_action("sleep")
	check(events.count("cancel:inspect:%d:sleep" % inspect) == 1 and not actor.cancel_action("sleep"), "sleep cancellation is idempotent")
	actor._process(0.8)
	check(events.count("finish:inspect:%d" % inspect) == 0, "cancelled clip cannot later finish")
	check(actor.global_position == origin, "custom clip leaves actor position unchanged")

	actor.queue_free()
	await process_frame
	print("[actor-presentation] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
