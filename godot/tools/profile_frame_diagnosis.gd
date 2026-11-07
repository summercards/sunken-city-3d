extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	var env: Environment = main.get_node("World/WorldEnvironment").environment
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var result := []
	for mode in ["glow_on", "glow_off", "glow_on_again"]:
		env.glow_enabled = mode != "glow_off"
		for i in 60: await process_frame
		var frames: Array = []
		var gpu: Array = []
		var process: Array = []
		var draws: Array = []
		var stamp := Time.get_ticks_usec()
		for i in 180:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now-stamp)/1000.0)
			stamp = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
			process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		frames.sort(); gpu.sort(); process.sort(); draws.sort()
		var sum := 0.0
		for t in frames: sum += t
		var row = {"mode":mode,"fps":180000.0/sum,"frame_ms_p50":frames[90],"frame_ms_p95":frames[171],"gpu_ms_p50":gpu[90],"gpu_ms_p95":gpu[171],"process_ms_p95":process[171],"draws_p50":draws[90]}
		result.append(row)
		print("[frame-diagnosis] ", JSON.stringify(row))
	print("[frame-diagnosis] complete")
	quit()
