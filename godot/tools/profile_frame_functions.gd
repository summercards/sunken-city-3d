extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on = false
	for i in 20: await process_frame
	main.set_process(false)
	for i in 5: await process_frame
	var calls := {
		"population": func(): main.props.sync_population(main.world_clock.query(),main.boat.position),
		"shader_time": func(): main._active_water_mat().set_shader_parameter("u_time",1.0),
		"shader_boat": func(): main._active_water_mat().set_shader_parameter("u_boat",main.boat.wake_uniform()),
		"input_blocked": func(): main.input_blocked(),
		"sleep": func(): main.sleep_cycle.advance(1.0/60.0),
		"clock": func(): main.world_clock.tick(1.0/60.0),
		"npc_sync": func(): main.npc_world_presenter.sync_world(main._npc_world_query()),
		"daylight": func(): main.daylight_rig.apply(main.world_clock.query().hour),
		"building": func(): main.building_controller.tick(1.0/60.0),
		"prompt": func(): main.prompt.update_from(main.interactor),
		"boat_shortcut": func(): main._boat_shortcut_text(),
		"camera_feedback": func(): main._update_camera_feedback(1.0/60.0),
		"pickup_progress": func(): main._update_pickup_progress(1.0/60.0),
		"weather": func(): main.weather_view.present(main.world_clock.query(),main.weather_service.query(),main.dive.active),
		"zones": func():
			for zone in main._zone_nodes.values():
				if zone.has_method("update_time"): zone.update_time(1.0),
		"pointer": func(): main._update_pointer_ui(),
		"near_interaction": func(): main._update_near_interaction(),
		"water": func(): main.water_node.update_surface(1.0,main.boat,main.cam.target),
		"idle_pick": func(): main._start_idle_pick(),
		"main_process": func(): main._process(1.0/60.0),
	}
	for name in calls:
		var samples: Array = []
		for i in 5:
			var start := Time.get_ticks_usec()
			calls[name].call()
			samples.append(float(Time.get_ticks_usec()-start)/1000.0)
		samples.sort()
		print("[frame-functions] ",name," median_ms=",samples[2]," samples=",samples)
	print("[frame-functions] complete")
	quit()
