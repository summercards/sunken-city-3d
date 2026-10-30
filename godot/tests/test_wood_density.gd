extends SceneTree
const Population = preload("res://src/pickups/ocean_population.gd")
const Scope = preload("res://src/core/play_scope.gd")
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	print("[wood-density] ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func wood_count(data: Dictionary) -> int:
	var count := 0
	for item in data.values():
		if not item.fish: count += 1
	return count
func home_count(props: Node) -> int:
	var count := 0
	for item in props.crates:
		if Scope.HOME_WATER.has_point(Vector2(item.base.x,item.base.z)): count += 1
	return count
func run() -> void:
	# Count a fixed area against the original six-per-cell population. Exact
	# quotas across ten cells verify 30%, rather than accepting 2/6 everywhere.
	for cycle in [1,2,69]:
		var population := Population.new()
		population.cycle=cycle
		var before := 0
		var after := 0
		var fish_unchanged := true
		for x in range(40,50):
			var cell := Vector2i(x,50)
			var baseline: Dictionary=population._make_base_cell(cell,6,4,Callable())
			var reduced: Dictionary=population._make_cell(cell,6,4,Callable())
			before += wood_count(baseline)
			after += wood_count(reduced)
			for slot in baseline:
				if baseline[slot].fish: fish_unchanged = fish_unchanged and reduced.get(slot,{})==baseline[slot]
		check(before==60 and after==18,"day %d: offshore keeps exactly 18 of 60 bundles in equal open water" % cycle)
		check(fish_unchanged,"day %d: thinning wood retains original fish positions and counts" % cycle)
	var main: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.set_physics_process(false)
	main.props.set_process(false)
	main.boat.set_process(false)
	main.world_clock.paused=true
	var inventory=root.get_node("Economy").inventory
	root.get_node("Economy").set_process(false)
	check(home_count(main.props)==6,"sunroom home rectangle retains the original six bundles")
	var clear := true
	for item in main.props.crates:
		clear=clear and main.props._ocean_point_clear(Vector2(item.base.x,item.base.z),false)
	check(clear,"reduced and home bundles still clear buildings and platforms")
	var current: Dictionary=Save.encode(main)
	# Recreate an existing dense save with all six wood slots in each active
	# cell, and a collected home slot. Loading must apply density immediately,
	# while keeping that slot's remaining cooldown and the player's inventory.
	var dense: Dictionary=current.duplicate(true)
	dense.pickups.crates=[]
	var center: Vector2i=Population.cell_at(Vector2(main.boat.position.x,main.boat.position.z))
	var next_id: int=int(dense.pickups.next_id)
	for y in range(center.y-1,center.y+2):
		for x in range(center.x-1,center.x+2):
			var baseline: Dictionary=main.props.ocean._make_base_cell(Vector2i(x,y),6,4,main.props._ocean_point_clear)
			for slot in baseline:
				if baseline[slot].fish or slot=="0:0:wood:4": continue
				var p: Vector2=baseline[slot].point
				dense.pickups.crates.append({"id":next_id,"slot":slot,"kind":"planks","base":[p.x,1.12,p.y],"phase":0.0,"yaw":0.0})
				next_id+=1
	dense.pickups.next_id=next_id
	dense.pickups.ocean.missing["0:0:wood:4"]=float(dense.pickups.ocean.now)+8
	var bag_before: Dictionary=inventory.to_dict()
	var restored: Dictionary=Save.restore(main,dense)
	check(restored.ok,"existing dense save loads: "+str(restored.get("reason","")))
	check(main.props.crates.size()<dense.pickups.crates.size() and home_count(main.props)==5,"dense save immediately thins outside and retains five uncollected home bundles")
	check(main.props.ocean.missing["0:0:wood:4"]==dense.pickups.ocean.missing["0:0:wood:4"] and inventory.to_dict()==bag_before,"density adjustment preserves cooldown and inventory")
	var reduced: Dictionary=Save.encode(main)
	check(Save.write("user://wood-density.json",main).ok,"reduced population saves normally")
	var disk_restore: Dictionary=Save.restore(main,Save.read("user://wood-density.json").snapshot)
	check(disk_restore.ok and JSON.stringify(main.props.to_dict())==JSON.stringify(reduced.pickups),"reduced population and depletion roundtrip without rerolling: "+str(disk_restore.get("reason","")))
	main.world_clock.rest_to_morning()
	check(home_count(main.props)==6,"next 07:00 refresh keeps six at home")
	main.props.sync_population(main.world_clock.query(),Vector3(1400,1.12,1400))
	check(main.props.crates.size()>=16 and main.props.crates.size()<=17 and main.props.schools.size()==36,"next morning keeps offshore at 30 percent and fish unchanged")
	main.props.sync_population(main.world_clock.query(),main.boat.position)
	check(home_count(main.props)==6,"sailing away and back does not duplicate home bundles")
	print("[wood-density] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
