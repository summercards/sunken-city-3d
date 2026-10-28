extends SceneTree
var checks := 0
var failures := 0
class TestState extends "res://src/core/state.gd":
	var id := ""
	var successor := ""
	func enter(_payload: Dictionary) -> void:
		context.events.append("enter:"+id)
		if successor!="": machine.change(successor)
	func exit() -> void: context.events.append("exit:"+id)
class Owner extends RefCounted:
	var events: Array = []
class StorageHost extends Node:
	var save_registry
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	check(not root.has_node("Economy"),"no autoload")
	var owner := Owner.new()
	var machine = preload("res://src/core/state_machine.gd").new()
	var a := TestState.new(); a.id="a"
	var b := TestState.new(); b.id="b";b.successor="c"
	var c := TestState.new(); c.id="c"
	machine.configure(owner,{"a":a,"b":b,"c":c},{"a":["b"],"b":["c"],"c":["a"]},"a")
	check(not machine.change("c") and machine.current=="a","illegal edge rejected")
	check(machine.change("b") and machine.current=="c","entry transition is queued")
	check(owner.events==["enter:a","exit:a","enter:b","exit:b","enter:c"],"exit before enter, exactly once")
	var weak: WeakRef = weakref(owner);owner=null
	check(weak.get_ref()==null,"machine does not retain owner")
	var clock = preload("res://src/time/world_clock.gd").new()
	clock.tick(1200.0)
	check(clock.day==2 and is_equal_approx(clock.seconds,25200.0),"day rollover")
	clock.paused=true;clock.tick(1200.0)
	check(clock.day==2,"paused clock")
	clock.paused=false;clock.rest_to_morning()
	check(clock.day==3 and clock.seconds==25200.0,"rest next morning")
	clock.tick(-1);clock.tick(NAN)
	check(clock.day==3,"invalid time ignored")
	var weather = preload("res://src/weather/weather_service.gd").new()
	var other = preload("res://src/weather/weather_service.gd").new()
	weather.tick(1000.0)
	for i in 100: other.tick(10.0)
	check(weather.to_dict()==other.to_dict(),"weather independent of tick partition")
	var snap: Dictionary = weather.to_dict();other.from_dict(snap)
	weather.tick(500.0);other.tick(500.0)
	check(weather.to_dict()==other.to_dict(),"weather RNG resumes after restore")
	check(not weather.set_weather("storm") and weather.set_weather("rain"),"weather commands validate kind")
	var inv = preload("res://src/inventory/inventory.gd").new(24)
	inv.set_count("rope",5);inv.set_count("coins",100);inv.set_count("wood",20);inv.set_count("parts",20)
	var payments := {"construction_pay":inv.pay,"construction_has":inv.has_all,"construction_missing_text":func(_cost):return "missing"}
	var construction = preload("res://src/construction/construction_service.gd").new();construction.configure(payments)
	check(construction.begin_site_upgrade("home_cabin").ok,"construction without world/UI")
	var after: int = inv.count("coins")
	check(not construction.begin_site_upgrade("home_cabin").ok and inv.count("coins")==after,"duplicate start not charged")
	construction.tick_sites(18.0)
	check(construction.site_level("home_cabin")==2,"construction timer completes")
	construction.from_dict({})
	check(construction.site_level("home_cabin")==1 and construction.site_work.is_empty(),"construction full reset")
	var ship = preload("res://src/ship/ship_service.gd").new();ship.configure(payments)
	check(ship.upgrade_ship().ok and ship.ship_level==2,"ship command uses payment port")
	var facility = preload("res://src/facilities/facility_service.gd").new()
	payments.site_level=construction.site_level;facility.configure(payments)
	check(facility.build_facility("warehouse").ok,"facility command")
	facility.from_dict(facility.to_dict())
	check(facility.facility_unlocked("warehouse"),"warehouse unlock survives restore")
	var nav = preload("res://src/navigation/water_navigation.gd").new()
	nav.shape_query = func():return [{"x":0.0,"z":0.0,"hx":3.0,"hz":3.0,"round":false}]
	check(not nav.is_open_water(0,0) and not nav.is_open_water(500,0),"solid and world boundary rejected")
	check(not nav.segment_clear(Vector2(-10,0),Vector2(10,0)),"crossing segment rejected")
	var route: Array=nav.plan_route_to(Vector2(-10,0),10,0)
	check(route.size()>2 and nav.valid_route(route),"route goes around solid")
	var registry = preload("res://src/save/snapshot_registry.gd").new()
	var applied := []
	registry.register("a",func():return {"v":1},func(d):applied.append(d),{"fields":{"v":{"type":"integer","min":0}},"required":["v"]},{"v":0})
	registry.register("b",func():return {"v":2},func(d):applied.append(d),{"fields":{"v":{"type":"integer","min":0}},"required":["v"]},{"v":0})
	check(not registry.restore({"a":{"v":4},"b":{"v":-1}}).ok and applied.is_empty(),"validate all before any apply")
	check(registry.restore(registry.capture()).ok and applied.size()==2,"registry round trip")
	var storage = preload("res://src/save/save_game.gd")
	check(not storage.decode("{}").ok,"empty JSON rejected")
	check(not storage.decode('{"version":1,"economy":{"inventory":{"capacity":-2,"counts":{}}}}').ok,"negative capacity rejected")
	check(not storage.decode('{"version":1,"economy":{"inventory":{"capacity":24,"counts":{"wood":"bad"}}}}').ok,"invalid nested count rejected")
	check(storage.decode('{"inventory":{"capacity":24,"counts":{"wood":5}}}').ok,"v0 migration")
	check(storage.decode('{"version":99}').get("future",false),"future version protected")
	var host := StorageHost.new()
	host.save_registry=preload("res://src/save/snapshot_registry.gd").new()
	var attempts: Array=[]
	host.save_registry.register("probe",func():return {},func(_data):attempts.append(storage.write("user://during_restore.json",host)),{"type":"object"},{})
	check(host.save_registry.restore({"probe":{}}).ok and not attempts[0].ok and not FileAccess.file_exists("user://during_restore.json"),"reentrant save cannot persist a partial restore")
	host.save_registry.clear()
	host.free()
	registry.clear()
	for service in [construction,facility,ship]: service.ports.clear()
	print("[framework-modules] %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
