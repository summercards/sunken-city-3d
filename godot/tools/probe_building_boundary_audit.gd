extends SceneTree
## Regression for the historical boundary audit. The old log remains archived;
## this probe now requires the open-ocean, safe-route and save-capacity fixes.
const Catalog = preload("res://src/building/building_catalog.gd")
const Service = preload("res://src/building/building_service.gd")
var checks := 0
var failures := 0
var findings := {}
var main: Node

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func deck(x:int,z:int) -> Dictionary: return {"kind":"deck","x":x,"z":z}
func support_at(service: RefCounted,x:int,z:int) -> String:
	for row in service.query():
		if row.kind=="deck" and row.x==x and row.z==z: return row.id
	return ""
func planter(support:String,px:float,pz:float,kind:="planter") -> Dictionary:
	return {"kind":kind,"support":support,"px":px,"pz":pz,"turn":0}

func audit_capacity() -> void:
	var service:=Service.new()
	service.configure({"eligibility":func():return "","space_reason":func(_r):return "","pay":func(_c):return true})
	# The same 24+36 layout that first failed at instance 55 in the old audit.
	for x in 5:
		for z in range(-2,4):
			if Catalog.base_cell(x,z): continue
			check(service.begin(deck(x,z)).ok,"old envelope deck accepted")
			service.tick(3.0)
	var accepted:=0
	for band in 3:
		for x in (2 if band==2 else 5):
			for z in 3:
				var px:float=snappedf((4.2 if band==2 else -2.2)+x*1.9,0.1)
				var pz:float=snappedf((-1.5 if band==2 else (-6.7 if band==0 else 3.6))+z*1.6,0.1)
				var cell:=Catalog.cell_at(Vector2(px,pz))
				var result:Dictionary=service.begin(planter(support_at(service,cell.x,cell.y),px,pz))
				if result.ok: accepted+=1
				service.tick(4.0)
	findings.capacity={"decks":24,"accepted_planters":accepted,"total_instances":service.query().size(),
		"snapshot_rejection":Service.validate_snapshot(service.to_dict()),"layout_byte_budget":Catalog.MAX_LAYOUT_BYTES}
	check(accepted==36 and service.query().size()==60,"historical 60-instance fixture still geometrically representable")
	check(Service.validate_snapshot(service.to_dict())=="","60-instance layout is now saveable")
	check(not service.candidates().is_empty(),"full old envelope still has outward frontier")
	check(service.geometry_reason(deck(100,-100))=="","independent remote foundation has no ring limit")

func audit_access() -> void:
	main.building.from_dict(Service.empty_snapshot())
	main.actor_controller.restore_pose({"mode":0,"player":[21.0,1.48,16.0]})
	root.get_node("GameState").enter_zone("zone5")
	for z in 4:
		check(main.building.begin(deck(3,z)).ok,"branch deck accepted")
		main.building.tick(3.0)
	var ground:Node=main._zone_nodes.zone5.walk_areas[0]
	var goal:=Catalog.ORIGIN+Vector3(4.3,0.0,7.3)
	check(not ground.path_between(main.player.global_position,goal).is_empty(),"unfurnished branch tip reachable")
	var branch:Dictionary=main.building.to_dict()
	var cases:Array=[
		[planter(support_at(main.building,3,2),4.2,3.9),planter(support_at(main.building,3,3),4.4,5.5)],
		[planter(support_at(main.building,3,2),4.162,3.8625),planter(support_at(main.building,3,3),4.438,5.4625)]]
	var rejected:Array=[]
	for pair:Array in cases:
		main.building.from_dict(branch)
		var reasons:Array=[]
		var any_rejected:=false
		for request:Dictionary in pair:
			var before:int=root.get_node("Economy").count("wood")
			var result:Dictionary=main.building.begin(request)
			reasons.append(str(result.get("reason","")))
			if not result.ok:
				any_rejected=true
				check(root.get_node("Economy").count("wood")==before,"unsafe placement rejected before payment")
			main.building.tick(4.0)
		check(not any_rejected,"pass-through planting beds no longer falsely close the supported branch")
		check(not ground.path_between(main.player.global_position,goal).is_empty(),"accepted mutations preserve branch connection")
		rejected.append(reasons)
	findings.access={"historical_fixture_rejection_reasons":rejected,"body_radius":preload("res://src/building/building_space.gd").RADIUS}
	main.building.from_dict(branch)
	var center:=Catalog.tile_rect(3,2).get_center()
	var small:Dictionary=main.building.begin(planter(support_at(main.building,3,2),center.x,center.y,"planter_small"))
	check(small.ok,"compact planter provides single-board DIY with real clearance")
	main.building.tick(3.0)
	check(not ground.path_between(main.player.global_position,goal).is_empty(),"compact planter allows passage across its supported board")

func screenshot_fixture() -> void:
	main.building.from_dict(Service.empty_snapshot())
	# Start from the safe east branch. Historical cells near the fixed island
	# and its dock are now subject to actual building/water obstruction policy.
	for cell in [Vector2i(3,0),Vector2i(3,1),Vector2i(3,2),Vector2i(4,2),Vector2i(3,3)]:
		var result:Dictionary=main.building.begin(deck(cell.x,cell.y))
		check(result.ok,"screenshot stage deck %s: %s"%[cell,str(result.get("reason",""))])
		main.building.tick(3.0)
	main.actor_controller.restore_pose({"mode":0,"player":[26.3,1.48,17.2875]})
	root.get_node("GameState").enter_zone("zone5")
	var controller:Node=main.building_controller
	controller.open();controller.select_recipe("deck")
	var outside:=deck(3,4)
	var target:Vector3=main.building_world.position_for(outside)
	controller.update_preview(main.cam.unproject_position(target))
	findings.boundary={"unrestricted_signed_grid":true,"beyond_old_south_limit_reason":main.building.can_place(outside),
		"preview":controller.preview.duplicate(true),"hint":controller.hint.text,"candidate_count":main.building.candidates().size()}
	check(Catalog.allowed_cell(3,4) and Catalog.allowed_cell(-3,4),"both old south and west limits removed")
	check(not controller.preview.is_empty() and int(controller.preview.x)==3 and int(controller.preview.z)==4,"cursor beyond old limit has a real selectable preview")
	check(main.building.can_place(outside)=="","old outside row passes complete placement policy")
	if DisplayServer.get_name()!="headless":
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/building-boundary-audit.png")
	controller.close()

func run() -> void:
	audit_capacity()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false)
	main.cam.set_process(false);main.cam.follow_enabled=false
	main.interactor.set_process(false);main.boat.set_process(false)
	root.get_node("Economy").set_process(false)
	await process_frame
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[21.0,1.48,16.0]})
	root.get_node("GameState").enter_zone("zone5")
	root.get_node("Economy").inventory.set_count("wood",300)
	root.get_node("Economy").inventory.set_count("soil",100)
	main.cam.global_position=Vector3(18,24,38)
	main.cam.look_at(Vector3(20,1.4,16));main.cam.fov=40
	audit_access()
	await screenshot_fixture()
	var output:=FileAccess.open("res://outputs/building-boundary-audit.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(findings,"  "));output.close()
	print("[audit-findings] ",JSON.stringify(findings))
	main.queue_free();await process_frame
	print("[building-boundary-audit] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
