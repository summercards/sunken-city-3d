extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main._autosave_on=false
	var economy=root.get_node("Economy")
	economy.set_process(false)
	check(economy.coins==98765,"default startup restores prior process")
	check(main.world_clock.day==17 and main.weather_service.kind=="rain","clock and weather persisted")
	var storage=preload("res://src/save/save_game.gd")
	var good: Dictionary=storage.encode(main)
	var invalid: Dictionary=good.duplicate(true)
	invalid.economy.erase("ship_level")
	check(not storage.restore(main,invalid).ok and economy.coins==98765,"truncated v2 cannot reset missing module")
	invalid=good.duplicate(true);invalid.economy.farm={}
	check(not storage.restore(main,invalid).ok and economy.coins==98765,"truncated farm cannot clear crops")
	var malformed: Array=[]
	var malformed_labels: Array=[]
	for key in ["pickups","dive"]:
		var record: Dictionary=good.duplicate(true)
		record[key]={}
		malformed.append(record);malformed_labels.append("empty "+key)
	var record: Dictionary=good.duplicate(true)
	record.version=99
	malformed.append(record);malformed_labels.append("future snapshot bypassing decode")
	record=good.duplicate(true)
	record.economy.farm.plots["home_plot"]={"crop":"lettuce"}
	malformed.append(record);malformed_labels.append("truncated crop row")
	record=good.duplicate(true)
	record.economy.orders.slots=[{"order":"missing-id","left":0.0}]
	malformed.append(record);malformed_labels.append("truncated order")
	record=good.duplicate(true)
	record.economy.orders.slots=[{"refill":1.0,"order":"mixed"}]
	malformed.append(record);malformed_labels.append("mixed order states")
	record=good.duplicate(true)
	record.pickups.crates.append(record.pickups.crates[0].duplicate(true))
	malformed.append(record);malformed_labels.append("duplicate pickup ID")
	record=good.duplicate(true)
	record.pickups.rng="9999999999999999999999999999999999999"
	malformed.append(record);malformed_labels.append("overflow random stream")
	for index in malformed.size():
		check(not storage.restore(main,malformed[index]).ok and economy.coins==98765 and main.props.to_dict()==good.pickups,"reject without mutation: "+malformed_labels[index])
	invalid=good.duplicate(true)
	invalid.economy.inventory.counts.coins=-1
	check(not storage.restore(main,invalid).ok and economy.coins==98765,"bad snapshot cannot mutate any state")
	invalid=good.duplicate(true);invalid.game.boat=[999,1,999,0]
	check(not storage.restore(main,invalid).ok and economy.coins==98765,"unsafe world position rejected before economy apply")
	var path: String="user://backup_test.json"
	check(storage.write(path,main).ok,"first generation write")
	economy.coins=12345
	check(storage.write(path,main).ok,"second generation write")
	var f=FileAccess.open(path,FileAccess.WRITE);f.store_string("{broken");f.close()
	var recovered: Dictionary=storage.read(path)
	check(recovered.get("recovered",false) and recovered.snapshot.economy.inventory.counts.coins==98765,"corrupt primary recovers previous valid generation")
	f=FileAccess.open(path,FileAccess.WRITE);f.store_string('{"version":999}');f.close()
	check(storage.read(path).get("future",false) and not storage.write(path,main).ok,"future primary does not fallback or overwrite")
	var backup_only: String="user://future_backup_only.json"
	f=FileAccess.open(backup_only+".bak",FileAccess.WRITE);f.store_string('{"version":999}');f.close()
	check(storage.read(backup_only).get("future",false) and not storage.write(backup_only,main).ok and not FileAccess.file_exists(backup_only),"future backup protected when primary missing")
	check(storage.restore(main,good).ok,"validated restoration")
	var observed_days: Array=[]
	var observe: Callable=func():observed_days.append(main.world_clock.day)
	economy.resources_changed.connect(observe)
	economy.coins=7
	main.world_clock.day=1
	observed_days.clear()
	main.world_clock.set_block_signals(true)
	check(storage.restore(main,good).ok and not observed_days.is_empty() and observed_days.all(func(day):return day==17),"restore publishes economy only after every feature is complete")
	check(main.world_clock.is_blocking_signals(),"restore preserves pre-existing signal block")
	main.world_clock.set_block_signals(false)
	economy.resources_changed.disconnect(observe)
	var cargo: Dictionary=main.props.crates[0]
	main.props.collect_crate(cargo)
	var cargo_state: Dictionary=main.props.to_dict()
	var rewards: Dictionary=economy.inventory.to_dict()
	check(main.props.collect_crate(cargo).is_empty() and economy.inventory.to_dict()==rewards,"stale pickup cannot reward twice")
	main.props.from_dict(cargo_state)
	check(main.props.to_dict()==cargo_state,"pickup entities and pending relative timers round trip")
	check(storage.restore(main,good).ok,"pickup restore resets previous timers")
	main.actor_controller.cancel()
	check(main.actor_controller.state_id()=="boat_idle","cancel stable on boat")
	main.dive.dive(main.boat.position,"test")
	check(main.dive.phase=="enter","dive enter state")
	main.dive.phase_machine.tick(main.dive.ENTER_TIME)
	check(main.dive.phase=="swim","enter to swim")
	main.dive.surface()
	check(main.dive.phase=="exit","surface enters exit")
	main.dive.phase_machine.tick(main.dive.ENTER_TIME)
	check(main.dive.phase=="surface" and not main.dive.active,"exit restores surface")
	main._debug_teleport("zone1")
	main.interactor.set_process(false)
	var plot: Node3D=main.farm_field.find("home_plot")
	economy.farm.states["home_plot"]=economy.farm._empty_state()
	economy.farm.select_crop("lettuce")
	var seeds: int=economy.count("lettuce_seed")
	check(main.actor_controller.approach(plot),"approach command accepted")
	for i in 1200:
		main.actor_controller.tick(1.0/60.0)
		if not main.actor_controller.walking(): break
	check(main.actor_controller.state_id()=="interacting","walking transitions to interacting")
	main.hud.set_external_modal(true)
	main.actor_controller.tick(0.0)
	check(not main.interactor.auto_hold,"modal blocks automatic hold")
	main.hud.set_external_modal(false)
	main.actor_controller.tick(0.0)
	check(main.interactor.auto_hold,"unblocked target begins hold")
	main.interactor.active=true
	main.interactor.update(5.0,true)
	check(economy.count("lettuce_seed")==seeds-1 and main.actor_controller.state_id()=="ashore_idle","interaction finishes once")
	main.actor_controller.tick(1.0)
	check(not main.interactor.auto_hold,"completion releases automatic input")
	var invoked: Array=[]
	main.actor_controller.start_walk(main._current_landing().ground(),main._current_landing().stand_position())
	main.actor_controller.after_walk=func():invoked.append(true)
	main.actor_controller.cancel()
	main.actor_controller.tick(100.0)
	check(invoked.is_empty() and main.actor_controller.walk_path.is_empty(),"cancel removes old route and callback")
	check(storage.restore(main,good).ok,"restore clears active control state")
	main.weather_service.set_weather("rain")
	main.world_clock.seconds=0.0
	main._process(0.0)
	check(main.weather_view.rain==1.0 and main.weather_view.daylight==0.0,"weather presentation consumes queries")
	check(economy.farm.day==int(good.economy.farm.day),"world clock does not grow crops implicitly")
	main.queue_free()
	await process_frame
	print("[framework-integration] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
