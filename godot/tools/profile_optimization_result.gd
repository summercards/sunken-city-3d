extends SceneTree
## Paired before/after entry. Identical probe, optional runner source-overlay only.
var main
var rows: Array = []
var report := {"rows":[],"images":[],"fixed_simulation_dt":1.0/60.0,"renderer_scope":"1600x1000 Forward+ real viewport; VSync off; not a release/device signoff"}
func _init() -> void: call_deferred("run")
func wait_frames(count: int) -> void:
	for i in count: await process_frame
func percentile(values: Array, q: float) -> float:
	values.sort()
	return float(values[mini(values.size()-1,maxi(0,ceili(values.size()*q)-1))])
func write_report() -> void:
	var file := FileAccess.open("res://outputs/optimization-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
func measure(label: String) -> void:
	await wait_frames(60)
	var frames: Array=[]
	var gpu: Array=[]
	var draws: Array=[]
	var primitives: Array=[]
	var stamp := Time.get_ticks_usec()
	var sum := 0.0
	for i in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now-stamp)/1000.0
		frames.append(ms);sum+=ms;stamp=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var row := {"label":label,"frames":300,"fps":300000.0/sum,"frame_p50_ms":percentile(frames.duplicate(),0.5),"frame_p95_ms":percentile(frames.duplicate(),0.95),"frame_p99_ms":percentile(frames.duplicate(),0.99),"gpu_p50_ms":percentile(gpu.duplicate(),0.5),"draws_p50":percentile(draws,0.5),"primitives_p50":percentile(primitives,0.5),"raw_frame_ms":frames,"raw_gpu_ms":gpu}
	rows.append(row);report.rows=rows;write_report()
	print("[optimization-result] ",JSON.stringify(row.merged({"raw_frame_ms":[],"raw_gpu_ms":[]})))
func freeze(node: Node) -> void:
	node.set_process(false);node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func image(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://outputs/optimization-"+label+".png"
	root.get_texture().get_image().save_png(path)
	report.images.append(path);write_report()
func run() -> void:
	root.size=Vector2i(1600,1000);root.content_scale_size=Vector2i(1600,1000)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var started := Time.get_ticks_usec()
	var scene := load("res://scenes/main.tscn")
	report.load_ms=float(Time.get_ticks_usec()-started)/1000.0
	main=scene.instantiate()
	started=Time.get_ticks_usec()
	root.add_child(main);current_scene=main
	report.ready_ms=float(Time.get_ticks_usec()-started)/1000.0
	main._autosave_on=false;main.world_clock.paused=true
	main._title_active=false
	if main.start_screen!=null: main.start_screen.hide()
	await wait_frames(60)
	main.cam.set_process(false);main.cam.suspend_follow()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	report.engine=Engine.get_version_info().string
	report.adapter=RenderingServer.get_video_adapter_name()
	report.camera={"size":[root.size.x,root.size.y],"position":[main.cam.position.x,main.cam.position.y,main.cam.position.z],"fov":main.cam.fov}
	for trial in 3:
		await measure("surface_"+str(trial))
		main.room_controller.enter(true)
		await measure("room_"+str(trial))
		main.room_controller.exit(true)
		await wait_frames(15)
	# End-state snapshots use the same absolute wave/vegetation phases.
	freeze(main)
	main._t=10.0
	main.water_node.update_surface(10.0,main.boat,main.cam.target)
	RenderingServer.global_shader_parameter_set("vegetation_time",10.0)
	main.hud.hide()
	if main.weather_view!=null: main.weather_view.hide()
	await wait_frames(4)
	await image("surface")
	main.room_controller.enter(true)
	freeze(main)
	await wait_frames(4)
	await image("room")
	main.room_controller.exit(true)
	# Rebuild the exact same production shoreline twice at the same frozen pose.
	if main.water_node.shoreline.get("cache_enabled") != null:
		main._set_shore_uniforms()
		var first_metrics: Dictionary=main.water_node.shoreline.metrics.duplicate()
		var first_data: PackedByteArray=main.water_node.shoreline.texture.get_image().get_data()
		main._set_shore_uniforms()
		var second_metrics: Dictionary=main.water_node.shoreline.metrics.duplicate()
		var second_data: PackedByteArray=main.water_node.shoreline.texture.get_image().get_data()
		report.full_resolution_cache={"first":first_metrics,"second":second_metrics,"raw_bytes_equal":first_data==second_data,"bytes":second_data.size(),"resolution":1536}
		if first_data!=second_data or not second_metrics.cache_hit:
			printerr("FAIL [optimization-result] full resolution warm cache equivalence")
			write_report();quit(1);return
	report.engine_static_bytes=OS.get_static_memory_usage()
	report.engine_video_bytes=Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	write_report()
	print("[optimization-result] complete")
	quit(0)
