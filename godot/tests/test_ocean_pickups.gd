extends SceneTree
const Population = preload("res://src/pickups/ocean_population.gd")
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
var main: Node
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	print("[ocean-pickups] ","PASS " if value else "FAIL ",label)
	if not value: failures += 1

func sync(day: int, hour: float, point := Vector3(400,1.12,400)) -> void:
	main.boat.place_at(point,0)
	main.world_clock.from_dict({"day":day,"seconds":hour*3600,"day_length":1200})
	main.props.sync_population(main.world_clock.query(),point)

func has_slot(slot: String, fish := false) -> bool:
	for item in (main.props.schools if fish else main.props.crates):
		if item.slot == slot: return true
	return false

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	main.world_clock.paused = true
	var economy = root.get_node("Economy")
	economy.set_process(false)
	var props = main.props
	check(props.ocean_enabled and not props.spawn_area.has_area(),"formal world no longer confines resources to HOME_WATER")
	for point in [Vector3(400,1.12,400),Vector3(-400,1.12,400),Vector3(-400,1.12,-400),Vector3(400,1.12,-400),Vector3(1400,1.12,1400)]:
		sync(1,7,point)
		check(props.crates.size()>=16 and props.crates.size()<=17 and props.schools.size()==36,"30 percent offshore wood and unchanged fish populate distant water at "+str(point))
		var spread := {}
		var clear := true
		for item in props.crates+props.schools:
			var p := Vector2(item.base.x,item.base.z)
			spread[Population.cell_at(p)] = true
			clear = clear and main.navigation.is_open_water(p.x,p.y)
		check(spread.size()==9 and clear,"resources occupy all nine cells and clear the actual navigation geometry")
		await process_frame

	sync(1,7)
	var crate: Dictionary = props.crates[0]
	var wood_slot: String = crate.slot
	var before: int = economy.count("wood")
	check(not props.collect_crate(crate).is_empty() and economy.count("wood")==before+3,"wood commits once and emits reward")
	check(props.collect_crate(crate).is_empty() and economy.count("wood")==before+3,"stale crate cannot pay twice")
	var due: float = props.ocean.missing[wood_slot]
	check(due>=13 and due<=17,"wood waits 6-10 GAME hours, not wall seconds")
	props._process(90)
	check(not has_slot(wood_slot),"90 real animation seconds do not bypass the world clock")
	var school: Dictionary = props.schools[0]
	var fish_slot: String = school.slot
	check(props.collect_fish(school),"fish collection succeeds")
	check(not props.collect_fish(school),"stale fish cannot pay twice")
	var second: Dictionary = props.crates[0]
	props.collect_crate(second)
	check(not is_equal_approx(due,float(props.ocean.missing[second.slot])),"bundles draw independent random replenishment times")

	sync(1,8,Vector3(-400,1.12,-400))
	sync(1,8)
	check(not has_slot(wood_slot) and not has_slot(fish_slot,true),"leaving and revisiting a cell preserves depletion")
	sync(1,due-0.001)
	check(not has_slot(wood_slot),"wood absent immediately before its deadline")
	sync(1,due+0.001)
	check(has_slot(wood_slot) and not has_slot(fish_slot,true),"wood returns at deadline, fish remains depleted")
	sync(2,6.999)
	check(not has_slot(fish_slot,true),"midnight and 06:00 wake do not add a second fish refresh")
	sync(2,7)
	check(has_slot(fish_slot,true) and props.crates.size()>=16 and props.crates.size()<=17 and props.schools.size()==36,"07:00 renews reduced wood population and fish once")
	var positions: Array = props.to_dict().schools
	sync(2,7)
	check(props.to_dict().schools==positions,"reobserving the same morning does not reroll resources")

	# Save at a distant location: live nodes plus unloaded depletion must roundtrip.
	main.boat.place_at(Vector3(1400,1.12,1400),0)
	sync(2,8,main.boat.position)
	crate=props.crates[0]; school=props.schools[0]
	wood_slot=crate.slot; fish_slot=school.slot
	props.collect_crate(crate); props.collect_fish(school)
	var captured: Dictionary = Save.encode(main)
	check(Save.write("user://ocean-pickups.json",main).ok,"distant population and game-hour deadlines write to disk")
	var loaded: Dictionary = Save.read("user://ocean-pickups.json")
	check(loaded.ok and Save.restore(main,loaded.snapshot).ok,"disk restore validates and applies the new optional pickup state")
	check(JSON.stringify(props.ocean.to_dict())==JSON.stringify(captured.pickups.ocean),"restore keeps exact deadlines and daily watermark")
	check(not has_slot(wood_slot) and not has_slot(fish_slot,true),"restore does not regenerate collected targets")
	var damaged: Dictionary = captured.duplicate(true)
	damaged.pickups.ocean.missing[wood_slot] = -1
	var state_before: Dictionary = props.to_dict()
	check(not Save.restore(main,damaged).ok and props.to_dict()==state_before,"negative cooldown rejects transaction without mutation")
	damaged=captured.duplicate(true)
	damaged.pickups.ocean.missing["bad-slot"] = props.ocean.now+7
	check(not Save.restore(main,damaged).ok,"malformed slot rejects before restoration")
	damaged=captured.duplicate(true)
	damaged.pickups.ocean.cycle = int(captured.time.day)+1
	check(not Save.restore(main,damaged).ok,"future daily watermark rejects")
	damaged=captured.duplicate(true)
	damaged.pickups.pending=[3.0]
	check(not Save.restore(main,damaged).ok,"mixed legacy seconds and calendar cooldowns reject")
	# A legacy save has seconds-based missing counts. Explicitly migrate rather
	# than turning a missing bundle/fish into a free immediate replacement.
	var legacy: Dictionary = captured.duplicate(true)
	legacy.pickups.erase("ocean")
	legacy.pickups.crates = legacy.pickups.crates.slice(0,5)
	legacy.pickups.schools = legacy.pickups.schools.slice(0,3)
	for item in legacy.pickups.crates+legacy.pickups.schools: item.erase("slot")
	var landing: Dictionary = root.get_node("Zones").landing("zone1","main")
	legacy.game.boat = [landing.boatPark[0],landing.boatPark[1],landing.boatPark[2],landing.boatYaw]
	var migrated: Dictionary = Save.restore(main,legacy)
	check(migrated.ok,"legacy save without ocean fields migrates: "+str(migrated.get("reason","")))
	check(props.ocean.missing.has("0:0:wood:5") and props.ocean.missing.has("0:0:fish:3"),"legacy collected slots remain depleted with new schedule")
	Save.restore(main,captured)
	economy.inventory.from_dict({"capacity":1,"counts":{"wood":999}})
	var count_before: int = props.schools.size()
	var missing_before: Dictionary = props.ocean.missing.duplicate(true)
	main.pickup_progress.clear()
	check(not props.collect_fish(props.schools[0]) and props.schools.size()==count_before and props.ocean.missing==missing_before,"full bag preserves target and refresh state")
	check(main.pickup_progress.rewards.is_empty(),"failed receipt produces no floating reward")
	Save.restore(main,captured)
	main.pickup_progress.clear()
	props.collect_fish(props.schools[0])
	check(main.pickup_progress.rewards.size()==1,"successful receipt creates exactly one item effect")
	main.pickup_progress.tick(0.2)
	var row: Control = main.pickup_progress.rewards[0].node
	var at := row.position.y
	main.pickup_progress.tick(0.6)
	check(row.position.y<at and row.modulate.a<1,"reward rises and fades above the progress anchor")
	main.pickup_progress.complete()
	main.pickup_progress.tick(0.51)
	check(not main.pickup_progress.bar.visible and main.pickup_progress.rewards.size()==1,"reward outlasts progress bar hold")
	main.pickup_progress.tick(1)
	check(main.pickup_progress.rewards.is_empty(),"completed effect cleans itself up")
	main.pickup_progress.receive({"wood":3})
	main._cancel_pending_pick()
	check(main.pickup_progress.rewards.is_empty(),"cancel clears old item effects")
	# The morning's replacement must also cancel a live gathering target.
	sync(3,6.9)
	crate=props.crates[0]
	main.boat.place_at(crate.base+Vector3(1.2,0,0),0)
	main._begin_pick_sail({"type":"crate","item":crate})
	main._update_pickup_progress(0)
	check(main._pick_phase==main.PICK_PHASE_GATHERING,"stationary nearby target enters gathering")
	main.world_clock.from_dict({"day":3,"seconds":7*3600,"day_length":1200})
	main._update_pickup_progress(0.1)
	check(main._pick_phase==main.PICK_PHASE_IDLE and not main.pickup_progress.bar.visible,"daily replacement cancels gathering of retired target")
	# SEA-PICKUP-R15：打捞巡航到站**不拧正船头**。
	# 出发朝向 0（正北）、目标在正东 → 航行中船头必然转到 ≈ -90°。
	# 到站后若还被出发朝向拉回去，这里会读到角度继续变化（主人看到的"自动转向一下"）。
	main.boat.place_at(Vector3(400,0,400),0.0)
	main.boat.set_process(true)
	main.boat.sail_to(Vector3(404,0,400),0.0,"","pickup",[],false)
	var guard := 0
	while main.boat.starts_sailing() and guard < 900:
		await process_frame
		guard += 1
	check(not main.boat.starts_sailing(),"打捞巡航能走到站")
	var arrive_yaw: float = main.boat.rotation.y
	for i in 40:
		await process_frame
	check(absf(angle_difference(arrive_yaw,0.0)) > 0.5,"到站朝向是航行方向，不是出发朝向")
	check(absf(angle_difference(arrive_yaw,main.boat.rotation.y)) < 0.01,"停稳后船头不再自己转")
	check(is_zero_approx(main.boat._dock_left),"打捞到站不排队拧正船头")
	# 反向对照：靠泊仍然要拧正，否则这条修复会把泊位朝向一起废掉。
	main.boat.place_at(Vector3(400,0,400),0.0)
	main.boat.sail_to(Vector3(404,0,400),0.0,"","dock",[],true)
	guard = 0
	while main.boat.starts_sailing() and guard < 900:
		await process_frame
		guard += 1
	check(not main.boat.starts_sailing() and absf(main.boat._dock_left) > 0.5,"靠泊仍保留拧正量")
	main.boat.set_process(false)
	print("[ocean-pickups] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
