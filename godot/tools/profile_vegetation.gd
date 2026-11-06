extends "res://tools/capture_vegetation.gd"
var patches: Array = []
var modules: Array = []
var replaced: Array = []
func percentile(values: Array, p: float) -> float:
	var ordered := values.duplicate(); ordered.sort()
	return ordered[mini(ordered.size()-1, int(ordered.size()*p))]
func run() -> void:
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	# 性能档使用 42/95 m 机位；玩家上限是 77.8 m（SEA-CAMERA-R11），不抬高会被静默夹回。
	main.cam.zoom_max = 160.0
	main._autosave_on = false; main.set_process(false)
	for i in 12: await process_frame
	patches = main.find_children("VegetationTurf", "Node3D", true, false)
	for node in main.find_children("*", "Node3D", true, false):
		if node.has_meta("vegetation_replaced"): replaced.append(node)
	solar_surface = find_solar_surface()
	var roof: Node3D = main._zone_nodes["rooftop_ranch"]
	var wind = get_first_node_in_group("vegetation_wind_owner")
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var results := []
	for view in ["solar", "rooftop"]:
		main.cam.suspend_follow()
		main.cam.target = solar_surface.to_global(Vector3(6,5.07,3)) if view == "solar" else roof.to_global(Vector3(0,60.42,0))
		var facility: Node3D = solar_surface if view == "solar" else roof
		main.cam.dir = (facility.global_basis * Vector3(-.2,.8,1)).normalized(); main.cam.distance = 42 if view == "solar" else 95; main.cam.cam_fov = 35; main.cam.apply_pose()
		for mode in ["baseline", "new_static", "new_wind"]:
			var enabled: bool = mode != "baseline"
			for node in replaced: node.visible = not enabled
			for patch in patches:
				patch.visible = enabled; patch.quality = 2 if mode == "high_density" else 1
				patch.update_quality(main.cam)
			wind.set_wind(1.1 if mode == "new_wind" else 0.0, Vector2(.86,.5))
			for i in 80: await process_frame
			var gpu := []; var cpu := []; var frame := []; var script_cost := []; var rebuild_cost := []; var draws := []
			var stamp := Time.get_ticks_usec()
			for i in 180:
				await process_frame
				var now := Time.get_ticks_usec(); frame.append(float(now-stamp)/1000.0); stamp = now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport)); cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				# Worst-case update (all chunks together), separately from render CPU timing.
				var start := Time.get_ticks_usec()
				if enabled:
					for patch in patches: patch.update_quality(main.cam)
					wind.sample_at(wind.elapsed)
				script_cost.append(float(Time.get_ticks_usec()-start)/1000.0)
				start = Time.get_ticks_usec()
				if enabled:
					for patch in patches: patch.update_quality(main.cam, true)
				rebuild_cost.append(float(Time.get_ticks_usec()-start)/1000.0)
			results.append({"view":view,"mode":mode,"gpu_ms_p50":percentile(gpu,.5),"gpu_ms_p95":percentile(gpu,.95),"render_cpu_ms_p95":percentile(cpu,.95),"frame_ms_p95":percentile(frame,.95),"vegetation_update_cpu_ms_p95":percentile(script_cost,.95),"all_chunks_lod_cpu_ms_p95":percentile(rebuild_cost,.95),"draw_calls_p50":percentile(draws,.5),"samples":180})
			print("[vegetation-perf] ", results[-1])
	var device := RenderingServer.get_rendering_device()
	var report := {"gpu":device.get_device_name() if device != null else "unavailable","cpu":OS.get_processor_name(),"resolution":str(root.size),"renderer":RenderingServer.get_current_rendering_method(),"gpu_scope":"root viewport only; includes its render passes, not other applications","results":results}
	FileAccess.open("res://outputs/vegetation_performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("[vegetation-performance] complete")
	quit(0)
