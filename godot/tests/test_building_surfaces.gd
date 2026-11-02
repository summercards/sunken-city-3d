extends SceneTree
## Actual-world regression for stair-led platforms, free surfaces and demolition.
const Catalog=preload("res://src/building/building_catalog.gd")
const Service=preload("res://src/building/building_service.gd")
const Assembly=preload("res://src/building/assembly_rules.gd")
const Surfaces=preload("res://src/building/assembly_surfaces.gd")
const Save=preload("res://src/save/save_game.gd")
var checks:=0
var failures:=0
var main: Node
var econ: Node
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	print("[surface-check] ",label," ",ok)
	if not ok: failures+=1;printerr("FAIL ",label)
func pure() -> void:
	var s:=Service.new()
	s.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":func(_c): return true,"refund":func(_c): return true})
	var raft: Dictionary=s.begin({"kind":"raft_4x4","px":100.0,"pz":102.0,"origin":"boat"});s.tick(30)
	check(raft.ok,"base raft builds")
	var stair: Dictionary=s.begin({"kind":"stairs","px":100.0,"pz":102.0,"py":0.0,"support":raft.id});s.tick(30)
	check(stair.ok,"stairs build on free platform")
	for kind in ["deck","raft_4x4","raft_2x4","upper_floor"]:
		var candidate:=Catalog.snap_foundation(kind,Vector2(100,99.8),0,s.query(),false,2.8)
		check(Catalog.stairs_top_contact(Catalog.footprint_rect(candidate),s.row(stair.id))>=.6,"stairs top snaps "+kind)
		check(s.can_place(candidate)=="","stairs top accepts "+kind+": "+s.can_place(candidate))
	var floor: Dictionary=s.begin({"kind":"upper_floor","px":100.0,"pz":99.0,"py":2.8});s.tick(30)
	check(floor.ok,"first upper floor requires no posts")
	check(s.begin({"kind":"upper_floor","px":102.0,"pz":99.0,"py":2.8}).ok,"upper floor extends by same-plane seam");s.tick(30)
	for kind in ["wall","railing","post","planter_small","oil_lamp"]:
		var at:=Vector2(100,99)
		var row: Dictionary={"kind":kind,"px":at.x,"pz":at.y,"py":2.8,"turn":0,"support":floor.id}
		check(s.can_place(row)=="","upper surface accepts "+kind+": "+s.can_place(row))
	var planted: Dictionary=s.begin({"kind":"planter_small","px":100.0,"pz":99.0,"py":2.8,"support":floor.id});s.tick(30)
	check(planted.ok and Catalog.elevation(s.row(planted.id))==2.8,"planter height is authoritative")
	var data: Dictionary=s.to_dict();data.instances.reverse()
	check(Service.validate_snapshot(data)=="","reversed upper platform/planter save validates")
	var restored:=Service.new();restored.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":func(_c): return true})
	check(restored.from_dict(JSON.parse_string(JSON.stringify(data))),"JSON restore retains upper platform and planter")
	check(not s.begin({"kind":"deck","positioned":true,"px":500.0,"pz":500.0,"py":2.8,"origin":"boat"}).ok,"boat cannot create unsupported high platform")
	var mix:=Service.new();mix.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":func(_c): return true})
	var base: Dictionary=mix.begin({"kind":"raft_4x4","px":100.0,"pz":100.0,"origin":"boat"});mix.tick(30)
	var lamp: Dictionary=mix.begin({"kind":"oil_lamp","px":100.2,"pz":100.0,"support":base.id});mix.tick(30)
	check(mix.begin({"kind":"planter","px":99.0,"pz":100.0,"support":base.id}).ok,"legacy planter can mix with lamp at safe spacing");mix.tick(30)
	check(not mix.move(lamp.id,{"px":100.1,"pz":100.0}).ok,"unsaveable 1.3cm mixed gap refused before moving")
	check(Service.validate_snapshot(mix.to_dict())=="","refused mixed move leaves save valid")
	var higher:=Service.new();higher.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":func(_c): return true})
	var low: Dictionary=higher.begin({"kind":"raft_4x4","px":120.0,"pz":120.0,"origin":"boat"});higher.tick(30)
	check(higher.begin({"kind":"stairs","px":120.0,"pz":120.0,"py":0.0,"support":low.id}).ok,"first height stair builds");higher.tick(30)
	var high: Dictionary=higher.begin({"kind":"raft_4x4","px":120.0,"pz":116.0,"py":2.8});higher.tick(30)
	check(high.ok,"same raft recipe carries upper height")
	check(higher.begin({"kind":"stairs","px":120.0,"pz":116.0,"py":2.8,"support":high.id}).ok,"new staircase may start on upper platform");higher.tick(30)
	check(higher.begin({"kind":"upper_floor","px":120.0,"pz":113.0,"py":5.6}).ok,"next stair top derives its actual 5.6m plane")
	check(Service.validate_snapshot(higher.to_dict())=="","multi-height stairs and work in progress save")
	for direction in 4:
		var rotated:=Service.new();rotated.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":func(_c): return true})
		var deck: Dictionary=rotated.begin({"kind":"raft_4x4","px":300.0,"pz":300.0,"origin":"boat"});rotated.tick(30)
		var step: Dictionary=rotated.begin({"kind":"stairs","px":300.0,"pz":300.0,"py":0.0,"turn":direction,"support":deck.id});rotated.tick(30)
		var edge:=Catalog.stairs_top_edge(rotated.row(step.id))
		var cursor: Vector2=(edge[0]+edge[1])/2+Vector2(0,-.8).rotated(-direction*PI/2)
		var board:=Catalog.snap_foundation("deck",cursor,1,rotated.query(),false,2.8)
		check(rotated.begin(board).ok,"rotated stair top accepts rotated board direction "+str(direction))

func build(kind: String,x: float,z: float,h: float=0.0) -> String:
	econ.energy.refill()
	var request: Dictionary={"kind":kind,"px":x,"pz":z,"py":h,"turn":0,"origin":"boat","support":""}
	if kind=="deck": request.positioned=true
	var supports:=Assembly.support_ids(request,main.building.query())
	if not Catalog.is_platform(kind) and not supports.is_empty(): request.support=supports[0]
	var made: Dictionary=main.building.begin(request)
	check(made.ok,"world builds "+kind+" @ "+str(Vector3(x,h,z))+": "+str(made.get("reason","")))
	main.building.tick(30)
	return str(made.get("id",""))
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true);await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		root.push_input(event,true);await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	if not main.building_controller.active: main.building_controller.tick(0)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/building-surface-"+name+".png")
func run() -> void:
	pure()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.cam.set_process(false);main.cam.follow_enabled=false;main.boat.set_process(false);main.interactor.set_process(false)
	econ=root.get_node("Economy");econ.set_process(false)
	econ.inventory.set_count("wood",700);econ.inventory.set_count("soil",30)
	await process_frame
	main._debug_teleport("zone5");root.get_node("GameState").enter_zone("zone5")
	var base:=build("raft_4x4",100,102)
	var stair:=build("stairs",100,102)
	if base=="" or stair=="": main.queue_free();quit(1);return
	var actor_at:=Catalog.ORIGIN+Vector3(100,0,103.8)
	main.actor_controller.restore_pose({"mode":0,"player":[actor_at.x,actor_at.y,actor_at.z]})
	for i in 3: await physics_frame
	main.cam.global_position=Catalog.ORIGIN+Vector3(109,17,115);main.cam.look_at(Catalog.ORIGIN+Vector3(100,2.8,100));main.cam.fov=38
	var editor: Node=main.building_controller
	editor.open();editor.select_recipe("deck");editor.manual_level=false
	var aim:=Catalog.ORIGIN+Vector3(100,2.8,99.9)
	editor.update_preview(main.cam.unproject_position(aim))
	check(absf(Catalog.elevation(editor.preview)-2.8)<.001,"mouse automatically recognizes stair top")
	check(main.building.can_place(editor.preview)=="","mouse first board is legal without posts")
	var before_count: int=main.building.query().size()
	await click(main.cam.unproject_position(aim))
	for i in 2400:
		main.actor_controller.tick(1.0/60);editor.tick(1.0/60)
		if i>2 and editor.pending.is_empty(): break
	check(main.building.query().size()==before_count+1,"real click approaches stair top then starts first board: "+main.hud._toast.text)
	main.building.tick(30);editor.close()
	# A clean 4x4 upper surface and an edge-connected chain exercise actual navigation.
	main._restore_building(Service.empty_snapshot())
	main.actor_controller.restore_pose({"mode":1})
	base=build("raft_4x4",100,102);build("raft_4x4",100,106);stair=build("stairs",100,102)
	var a:=build("raft_4x4",100,98,2.8)
	var b:=build("upper_floor",103,98,2.8)
	var c:=build("upper_floor",105,98,2.8)
	var crate:=build("storage_crate",103,97.5,2.8)
	var zone: Node=main._zone_nodes.zone5
	var start:=Catalog.ORIGIN+Vector3(105,2.8,98.7)
	var goal:=Catalog.ORIGIN+Vector3(100,2.8,98.7)
	check(not zone.ground_space.route(start,goal).is_empty(),"upper furniture preserves navigation across matching cut seams")
	main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]})
	check(main.building.can_remove(b)!="","cannot demolish the upper bridge trapping actor")
	check(main.building.can_remove(stair)!="","cannot remove only return stair while upstairs")
	var foot:=Catalog.ORIGIN+Vector3(100,0,104.6)
	main.actor_controller.restore_pose({"mode":0,"player":[foot.x,foot.y,foot.z]})
	for i in 3: await physics_frame
	var assembly: Node=main.building_world._assembly_walk
	check(main.actor_controller.start_walk(assembly,goal),"real actor accepts ground-to-upper route")
	for i in 2200:
		main.actor_controller.tick(1.0/60)
		if not main.actor_controller.walking(): break
	check(main.player.global_position.distance_to(goal)<.2,"real capsule climbs stairs and reaches upper platform: "+str(main.player.global_position))
	var planter:=build("planter_small",99.1,96.8,2.8)
	var wall:=build("wall",100,96,2.8)
	var rail:=build("railing",101.8,98,2.8)
	var lamp:=build("oil_lamp",99.2,98.4,2.8)
	check(planter!="" and wall!="" and rail!="" and lamp!="","upper platform carries plants, wall, railing and lamp")
	check(main.farm_field.find("dynamic/"+planter)!=null,"upper planter registers with real Farm")
	if planter!="":
		econ.inventory.set_count("lettuce_seed",2);econ.energy.refill()
		var plot: Node=main.farm_field.find("dynamic/"+planter)
		check(plot.perform("plant","lettuce").get("event")=="planted","upper planter runs real planting command")
		var crop_before: Dictionary=econ.farm.state("dynamic/"+planter)
		check(main.building.can_remove(planter)!="","upper crop must be harvested before demolition")
		check(main.building.move(planter,{"px":100.6,"pz":97.0}).ok,"upper crop can move freely on same platform")
		check(econ.farm.state("dynamic/"+planter)==crop_before and Catalog.elevation(main.building.row(planter))==2.8,"upper move preserves crop, ID and height")
	var saved: Dictionary=Save.write("user://surface-test.json",main)
	check(saved.ok,"whole upper world writes through production save: "+str(saved.reason))
	if saved.ok:
		var disk: Dictionary=Save.read("user://surface-test.json")
		check(disk.ok and Save.restore(main,disk.snapshot).ok,"production JSON disk read restores all heights")
	check(main.player.global_position.y>Catalog.ORIGIN.y+2,"restored actor remains upstairs")
	main.cam.global_position=Catalog.ORIGIN+Vector3(110,17,114);main.cam.look_at(Catalog.ORIGIN+Vector3(102,2,100))
	await shot("two-floors")
	# Free, non-metre structural positioning and moving preview.
	editor.open();editor.select_recipe("post");editor.build_level=1;editor.manual_level=true;editor.snap_assist=false
	var free_request: Dictionary=editor._furnishing_request(Vector2(100.3,97.3))
	check(is_equal_approx(float(free_request.px),100.3) and is_equal_approx(float(free_request.pz),97.3),"frame placement keeps free 0.1m coordinates")
	editor.recipe="planter_small"
	var unassisted: Dictionary=editor._furnishing_request(Vector2(98.2,98))
	check(is_equal_approx(float(unassisted.px),98.2),"G off leaves planter edge position under player control")
	editor.snap_assist=true
	var assisted: Dictionary=editor._furnishing_request(Vector2(98.2,98))
	check(float(assisted.px)>float(unassisted.px) and main.building.geometry_reason(assisted)=="","G on may assist planter back inside the surface")
	editor.snap_assist=false
	editor.select_recipe("move");editor.moving_id=lamp;editor.build_level=1;editor.manual_level=true
	editor.update_preview(main.cam.unproject_position(Catalog.ORIGIN+Vector3(100.4,2.8,98.4)))
	check(editor.focus_ghost!=null and editor.focus_ghost.visible,"moving upper lamp has visible destination ghost")
	var zoom_before: float=main.cam.distance
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.position=Vector2(600,400)
	main.cam._unhandled_input(wheel)
	check(main.cam.distance<zoom_before,"placement mode permits actual camera wheel input")
	await shot("move-ghost")
	editor.close()
	# Full safe confirmation flow on a standalone prop, with real mouse buttons.
	main.actor_controller.restore_pose({"mode":0,"player":[goal.x,goal.y,goal.z]})
	editor.open_demolition();await process_frame
	check(editor.recipe=="remove" and editor.demolition.active,"dedicated button path opens hammer tool")
	var lamp_at: Vector3=main.building_world.position_for(main.building.row(lamp))+Vector3.UP*.3
	editor.update_preview(main.cam.unproject_position(lamp_at))
	check(editor.hovered_id==lamp and editor.selection_outline.visible,"hover highlights visible built lamp")
	var hover_event:=InputEventMouseMotion.new();hover_event.position=main.cam.unproject_position(lamp_at);root.push_input(hover_event,true);await process_frame
	# Capture a deterministic controller hover frame; synthetic push_input does
	# not warp the operating system pointer returned by get_mouse_position().
	editor.demolition.set_process(false);editor.update_preview(hover_event.position)
	editor.demolition.cursor.position=hover_event.position-Vector2(10,10);editor.demolition.cursor.show()
	editor.demolition.target_tip.position=hover_event.position+Vector2(32,30);editor.demolition.target_tip.show()
	await shot("hammer-highlight")
	editor.demolition.set_process(true)
	await click(main.cam.unproject_position(lamp_at))
	check(editor.demolition.confirmation_open() and not main.building.row(lamp).is_empty(),"click opens confirmation without demolishing")
	zoom_before=main.cam.distance;main.cam._unhandled_input(wheel)
	check(main.cam.distance==zoom_before,"confirmation locks camera input")
	await shot("demolition-confirm")
	await click(editor.demolition.no_button.get_global_transform_with_canvas()*(editor.demolition.no_button.size/2))
	check(not editor.demolition.confirmation_open() and not main.building.row(lamp).is_empty(),"No keeps object and returns to hammer mode")
	editor.update_preview(main.cam.unproject_position(lamp_at));await click(main.cam.unproject_position(lamp_at))
	var wood_before: int=econ.count("wood")
	await click(editor.demolition.yes_button.get_global_transform_with_canvas()*(editor.demolition.yes_button.size/2))
	for i in 1800:
		main.actor_controller.tick(1.0/60);editor.tick(1.0/60)
		if i>2 and editor.pending.is_empty(): break
	check(main.building.row(lamp).is_empty(),"Yes approaches and demolishes exactly selected object: "+main.hud._toast.text)
	check(econ.count("wood")==wood_before+2,"confirmed demolition refunds exactly once")
	editor.close()
	main.actor_controller.restore_pose({"mode":1})
	build("raft_4x4",130,130);build("door_frame",130,130)
	var pot:=build("flower_pot",130,128.8)
	main.cam.global_position=Catalog.ORIGIN+Vector3(130,1.7,133)
	var pot_body:=Catalog.ORIGIN+Vector3(130,.35,128.8);main.cam.look_at(pot_body)
	editor.open_demolition()
	check(editor.build_level==0,"returning to boat resets construction to water plane")
	editor.build_level=1;editor.manual_level=true
	editor.update_preview(main.cam.unproject_position(pot_body))
	check(editor.hovered_id==pot,"visible pot can be selected through actual door aperture: target="+str(editor.preview)+" expected="+pot)
	editor.close();main.queue_free();await process_frame
	print("[building-surfaces] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
