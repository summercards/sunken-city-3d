extends SceneTree
## Read-only diagnostics in the unified runner's isolated copy. Never edits production assets.
var main
var results: Array = []
var report := {"purpose":"performance audit, not optimization acceptance", "rows":[], "images":[], "diagnostic_effect_removals":true, "save_access":"isolated runner user dir; autosave disabled"}
var start_usec := 0
var base_vsync := 0
var original_modes: Array = []
var saved_preview_mode := 0

func _init() -> void:
	call_deferred("run")

func settle(count: int = 30) -> void:
	for i in count: await process_frame

func p(values: Array, q: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size()-1, int(ceil(q*sorted.size()))-1)]) if not sorted.is_empty() else 0.0

func monitor_state() -> Dictionary:
	return {"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"engine_static_bytes":OS.get_static_memory_usage(),
		"engine_video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"engine_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"engine_buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"physics_active":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)}

func camera_state() -> Dictionary:
	var camera := root.get_camera_3d()
	if camera == null: return {}
	return {"position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],
		"rotation":[camera.rotation.x,camera.rotation.y,camera.rotation.z], "fov":camera.fov,
		"size":[root.size.x,root.size.y]}

func sample(label: String, count: int = 120) -> void:
	await settle(30)
	var frame: Array = []
	var gpu: Array = []
	var render_cpu: Array = []
	var draws: Array = []
	var primitives: Array = []
	var process_ms: Array = []
	var physics_ms: Array = []
	var sub_gpu: Array = []
	var stamp := Time.get_ticks_usec()
	var viewport := root.get_viewport_rid()
	for i in count:
		await process_frame
		var now := Time.get_ticks_usec()
		frame.append(float(now-stamp)/1000.0)
		stamp = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		if main.workshop_host != null:
			sub_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(main.workshop_host.panel.preview.viewport.get_viewport_rid()))
	var total := 0.0
	for value in frame: total += float(value)
	var row := {"label":label,"frames":count,"fps":1000.0*count/total,
		"frame_p50_ms":p(frame,0.50),"frame_p95_ms":p(frame,0.95),"frame_p99_ms":p(frame,0.99),
		"gpu_p50_ms":p(gpu,0.50),"gpu_p95_ms":p(gpu,0.95),"render_cpu_p50_ms":p(render_cpu,0.50),
		"engine_process_raw_untrusted":p(process_ms,0.50),"engine_physics_raw_untrusted":p(physics_ms,0.50),
		"monitor_warning":"Performance TIME counters rejected for attribution: stale/inconsistent during fixed-fps coroutine sampling", 
		"preview_update_mode":main.workshop_host.panel.preview.viewport.render_target_update_mode,
		"draws_p50":p(draws,0.50),"primitives_p50":p(primitives,0.50),
		"workshop_gpu_p50_ms":p(sub_gpu,0.50),"memory":monitor_state(),"camera":camera_state(),
		"raw_frame_ms":frame,"raw_gpu_ms":gpu}
	results.append(row)
	print("[performance-audit] ",JSON.stringify(row.duplicate().merged({"raw_frame_ms":[],"raw_gpu_ms":[]})))
	report.rows = results
	save_report()

func save_report() -> void:
	var file := FileAccess.open("res://outputs/performance-audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://outputs/perf-"+label+".png"
	var image := root.get_texture().get_image()
	image.save_png(path)
	report.images.append(path)
	save_report()

func capture_modes(node: Node) -> void:
	original_modes.append([node,node.is_processing(),node.is_physics_processing()])
	for child in node.get_children(): capture_modes(child)

func freeze_modes(frozen: bool) -> void:
	for row in original_modes:
		if is_instance_valid(row[0]):
			row[0].set_process(false if frozen else row[1])
			row[0].set_physics_process(false if frozen else row[2])

func subtree_counts(node: Node) -> Dictionary:
	var out := {"nodes":1,"process":int(node.is_processing()),"physics":int(node.is_physics_processing()),"meshes":int(node is MeshInstance3D),"multimeshes":int(node is MultiMeshInstance3D)}
	for child in node.get_children():
		var sub := subtree_counts(child)
		for key in out: out[key] += sub[key]
	return out

func microbench() -> void:
	var queries := {
		"clock_query":func(): return main.world_clock.query(),
		"pointer":func(): main._update_pointer_ui(),
		"near_interaction":func(): main._update_near_interaction(),
		"water":func(): main.water_node.update_surface(main._t,main.boat,main.cam.target),
		"daylight":func(): main.daylight_rig.apply(main.world_clock.query().hour),
		"npc_unchanged_sync":func(): main.npc_world_presenter.sync_world(main._npc_world_query()),
		"save_encode_no_write":func(): return load("res://src/save/save_game.gd").encode(main),
		"capacity_current":func(): return main._construction_capacity_reason(main.building.query())}
	report.micro = {}
	for key in queries:
		var values: Array = []
		for i in 30:
			var t0 := Time.get_ticks_usec()
			queries[key].call()
			values.append(float(Time.get_ticks_usec()-t0)/1000.0)
		report.micro[key] = {"calls":30,"p50_ms":p(values,0.5),"p95_ms":p(values,0.95),"max_ms":p(values,1.0),"samples_ms":values}
	report.micro_note = "Sequential direct calls, cached/unchanged state, not whole-frame or active construction/navigation performance; save encode never writes."
	save_report()
	print("[performance-audit] micro ",JSON.stringify(report.micro))

func run() -> void:
	start_usec = Time.get_ticks_usec()
	root.size = Vector2i(1600,1000)
	root.content_scale_size = Vector2i(1600,1000)
	report.engine = Engine.get_version_info()
	report.pid = OS.get_process_id()
	report.system = {"processor":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"adapter":RenderingServer.get_video_adapter_name(),"rendering_method":RenderingServer.get_current_rendering_method()}
	report.memory_before_main = monitor_state()
	var t := Time.get_ticks_usec()
	var packed = load("res://scenes/main.tscn")
	report.main_resource_load_ms = float(Time.get_ticks_usec()-t)/1000.0
	t = Time.get_ticks_usec()
	main = packed.instantiate()
	report.main_instantiate_ms = float(Time.get_ticks_usec()-t)/1000.0
	t = Time.get_ticks_usec()
	root.add_child(main)
	current_scene = main
	report.main_ready_ms = float(Time.get_ticks_usec()-t)/1000.0
	main._autosave_on = false
	main.world_clock.paused = true
	if main.start_screen != null: main.start_screen.hide()
	main._title_active = false
	base_vsync = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	report.original_vsync = base_vsync
	report.actual_vsync = DisplayServer.window_get_vsync_mode()
	report.simulation_fixed_fps = 60
	report.frame_clock = "Time.get_ticks_usec actual elapsed; fixed simulation dt is not performance evidence"
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var preview: SubViewport = main.workshop_host.panel.preview.viewport
	RenderingServer.viewport_set_measure_render_time(preview.get_viewport_rid(),true)
	report.workshop = {"panel_visible":main.workshop_host.panel.visible,"preview_size":[preview.size.x,preview.size.y],"update_mode":preview.render_target_update_mode}
	report.main_counts = subtree_counts(main)
	await settle(60)
	if OS.get_environment("SEA_PERF_MICRO_ONLY") == "1":
		await microbench()
		print("[performance-audit] complete")
		quit(0)
		return
	saved_preview_mode = preview.render_target_update_mode
	report.workshop_settled_update_mode = saved_preview_mode
	main.cam.set_process(false)
	main.cam.suspend_follow()
	await sample("surface_baseline_a",240)
	await shot("surface-baseline")
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await sample("hidden_workshop_disabled")
	preview.render_target_update_mode = saved_preview_mode
	await sample("surface_baseline_b")
	var water := main.water_node as Node3D
	water.hide()
	await sample("diagnostic_water_hidden")
	water.show()
	var city := main.get_node("World/SunkenCity") as Node3D
	city.hide()
	await sample("diagnostic_surface_city_hidden")
	await shot("diagnostic-surface-city-hidden")
	city.show()
	var sun: DirectionalLight3D = main.get_node("World/Lights/Sun")
	var had_shadow := sun.shadow_enabled
	sun.shadow_enabled = false
	await sample("diagnostic_sun_shadow_off")
	sun.shadow_enabled = had_shadow
	await sample("surface_baseline_c")
	# Exact no-effect check with all process callbacks frozen. Shader TIME can still animate.
	capture_modes(main)
	freeze_modes(true)
	await settle(4)
	await shot("viewport-on-frozen")
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await settle(4)
	await shot("viewport-off-frozen")
	preview.render_target_update_mode = saved_preview_mode
	freeze_modes(false)
	report.workshop_before_open_mode = preview.render_target_update_mode
	main.workshop_host.panel.open()
	await settle(10)
	report.workshop_open_mode = preview.render_target_update_mode
	main.workshop_host.panel.close_now()
	await settle(10)
	report.workshop_after_close_mode = preview.render_target_update_mode
	saved_preview_mode = preview.render_target_update_mode
	main.room_controller.enter(true)
	await settle(30)
	report.room_counts = {}
	for node in main._outdoor_nodes():
		report.room_counts[str(node.name)] = subtree_counts(node).merged({"visible":node.visible,"process_mode":node.process_mode})
	await sample("room_baseline",240)
	await shot("room-baseline")
	var outdoor_modes: Array = []
	for node in main._outdoor_nodes():
		outdoor_modes.append([node,node.process_mode])
		node.process_mode = Node.PROCESS_MODE_DISABLED
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await sample("diagnostic_room_outdoor_process_disabled",240)
	for row in outdoor_modes: row[0].process_mode = row[1]
	preview.render_target_update_mode = saved_preview_mode
	await sample("room_restored",240)
	main.room_controller.exit(true)
	await settle(20)
	# Actual DiveSession retains Main and detaches it before runtime, unlike a standalone map.
	t = Time.get_ticks_usec()
	var accepted: bool = main.dive.dive(Vector3(7.0,1.12,5.0),"home_seabed")
	report.dive_accepted = accepted
	report.dive_sync_load_ready_ms = float(Time.get_ticks_usec()-t)/1000.0
	if accepted:
		for i in 240:
			await physics_frame
			if main.dive.runtime.phase == "swim": break
		var runtime = main.dive.runtime
		report.dive_phase = runtime.phase
		report.dive_counts = subtree_counts(runtime)
		report.surface_retained_out_of_tree = not main.is_inside_tree()
		# Lock a representative depth while preserving normal runtime effects/physics.
		runtime.dive_set_position(Vector3(7.0,float(runtime.water_level)-20.0,5.0))
		await sample("underwater_20m_baseline")
		await shot("underwater-20m")
		var beams: Node3D = runtime.get_node_or_null("Atmosphere/LightShafts") as Node3D
		if beams != null:
			beams.hide()
			await sample("diagnostic_underwater_beams_hidden")
			beams.show()
		await sample("underwater_20m_restored")
		for depth_m in [41.0,80.0]:
			runtime.dive_set_position(Vector3(7.0,float(runtime.water_level)-depth_m,5.0))
			await sample("underwater_"+str(int(depth_m))+"m")
			await shot("underwater-"+str(int(depth_m))+"m")
		report.memory_underwater = monitor_state()
		# Return through owning session; no rebuilding Main and no production save.
		main.dive._commit_return(true,false)
		await settle(60)
		report.memory_after_return = monitor_state()
		report.main_identity_restored = main.is_inside_tree()
	report.total_wall_ms = float(Time.get_ticks_usec()-start_usec)/1000.0
	save_report()
	print("[performance-audit] complete")
	quit(0)
