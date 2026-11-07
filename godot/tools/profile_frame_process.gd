extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for mode in ["normal", "process_disabled", "normal_again"]:
		main.process_mode = Node.PROCESS_MODE_DISABLED if mode == "process_disabled" else Node.PROCESS_MODE_INHERIT
		for i in 20: await process_frame
		var frames: Array = []
		var stamp := Time.get_ticks_usec()
		for i in 60:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now-stamp)/1000.0)
			stamp = now
		frames.sort()
		var sum := 0.0
		for t in frames: sum += t
		print("[frame-process] ", JSON.stringify({"mode":mode,"fps":60000.0/sum,"p50_ms":frames[30],"p95_ms":frames[57],"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}))
	print("[frame-process] complete")
	quit()
