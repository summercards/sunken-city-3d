extends SceneTree
## Height-aware adapters in the real main scene. Fixtures exist only in memory.
const Save = preload("res://src/save/save_game.gd")
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false; main.set_process(false); main.set_physics_process(false)
	for i in 3: await physics_frame; await process_frame
	var zone: Node3D = main._zone_nodes.zone1
	var upper = preload("res://src/navigation/walk_area.gd").new()
	upper.area_id="test_upper"; upper.zone_id="zone1"
	upper.surface_y=12.0; upper.rects=[Rect2(1.0,7.0,3.0,3.0)]
	zone.get_node("WalkAreas").add_child(upper)
	zone.walk_areas.append(upper)
	zone.ground_space.configure(zone.walk_areas)
	for i in 3: await physics_frame; await process_frame
	var state: Node=root.get_node("GameState")
	state.enter_zone("zone1"); state.landing_id="main"
	main.actor_controller.restore_pose({"mode":0,"player":[2.0,12.0,8.0]})
	check(zone.area_at(Vector3(2,12,8))==upper,"world query selects upper floor at overlapping XZ")
	check(zone.area_at(Vector3(2,1.38,8))!=upper,"world query retains original lower floor")
	var encoded: Dictionary=Save.encode(main)
	var written: Dictionary=Save.write("user://character-upper.json",main)
	check(written.ok,"upper floor pose writes through real save registry: "+str(written.reason))
	main.actor_controller.restore_pose({"mode":0,"player":[2.0,1.38,8.0]})
	var restored: Dictionary=Save.restore(main,encoded)
	check(restored.ok and absf(main.player.global_position.y-12.0)<0.001,"restore preserves saved upper floor instead of first XZ match")
	var economy_before: String=JSON.stringify(root.get_node("Economy").to_dict())
	var bad: Dictionary=encoded.duplicate(true); bad.game.player[1]=6.0
	var rejected: Dictionary=Save.restore(main,bad)
	check(not rejected.ok and absf(main.player.global_position.y-12.0)<0.001,"unsupported height rejects without changing live pose")
	check(JSON.stringify(root.get_node("Economy").to_dict())==economy_before,"bad pose cannot partially apply economy")
	main.cam.restore_follow(main.player); main.cam._process(1.0/60)
	check(absf(main.cam.target.y-12.7)<0.001,"follow camera consumes upper floor height above old 10m clamp")
	main.cam.suspend_follow(); main.cam.target.y=12.7; main.cam._process(1.0/60)
	check(is_equal_approx(main.cam.target.y,10.0),"manual camera preserves original observation clamp")
	# The lower player's E scan cannot acquire a spot directly above it upstairs.
	main.actor_controller.restore_pose({"mode":0,"player":[2.0,1.38,8.0]})
	var spot = preload("res://src/interaction/interactable.gd").new()
	spot.id="upper_fixture";spot.focus_anchor="node"
	main.add_child(spot);spot.global_position=Vector3(2,12,8)
	check(main._compute_reach_reason(spot)!="","unconnected upper interaction is unreachable")
	check(not main.interactor.reachable_query.call(spot),"injected E query refuses interaction through another floor")
	main.queue_free();await process_frame
	print("[character-space-save] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
