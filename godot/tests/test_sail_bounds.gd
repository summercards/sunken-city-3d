extends SceneTree
## R11 now covers free ocean, while explicit scenario bounds remain injectable.
const WaterNav=preload("res://src/navigation/water_navigation.gd")
const Scope=preload("res://src/core/play_scope.gd")
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",message)
func run() -> void:
	var main: Node=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.process_mode=Node.PROCESS_MODE_DISABLED
	check(not main.navigation.allowed_area.has_area(),"free ocean has no fixed area fence")
	check(Scope.HOME_WATER.size==Vector2(55,48),"pickup population scope stays independent")
	for p in [Vector2(75.5,0),Vector2(0,75.5),Vector2(500,500),Vector2(-500,500),Vector2(-500,-500),Vector2(500,-500)]:
		check(main.navigation.is_open_water(p.x,p.y),"unobstructed distant ocean allowed "+str(p))
	var path: Array=main.navigation.plan_route_to(Vector2(500,500),750,500)
	check(path.size()==2 and main.navigation.valid_route(path),"distant open route uses direct path")
	var isolated=WaterNav.new();isolated.shape_query=func(): return []
	isolated.allowed_area=Rect2(-75,-75,150,150)
	check(isolated.is_open_water(74.5,0) and not isolated.is_open_water(75.5,0),"explicit scenario area still enforces its own policy")
	isolated.allowed_area=Rect2()
	check(isolated.is_geometric_water(1000,-1000),"geometry itself is not clipped to old160m box")
	isolated.shape_query=func(): return [{"x":500.0,"z":500.0,"hx":2.0,"hz":2.0,"round":false}]
	isolated.invalidate()
	check(not isolated.is_open_water(500,500),"actual remote building still blocks sea")
	check(not isolated.segment_clear(Vector2(495,500),Vector2(505,500)),"analytic distant segment cannot cross building")
	main.cam.target=Vector3(500,1.48,-500);main.cam._clamp_target()
	check(main.cam.target==Vector3(500,1.48,-500),"camera is not held inside old154m frame")
	main.queue_free();await process_frame
	print("[sail-bounds] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)