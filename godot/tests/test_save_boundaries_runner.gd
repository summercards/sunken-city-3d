extends SceneTree

var checks := 0
var failures := 0

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.set_physics_process(false)
	main.world_clock.paused = true
	var economy: Node = root.get_node("Economy")
	economy.set_process(false)
	await process_frame
	await process_frame
	var before := checks
	preload("res://tests/test_save_boundaries.gd").run(main, Callable(self, "_check"))
	# The helper owns only the assertions; this wrapper owns the runner marker.
	print("[save-boundaries] %d checks, %d failures" % [checks - before, failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
