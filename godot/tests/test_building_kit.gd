extends SceneTree
const Catalog=preload("res://src/building/building_catalog.gd")
const SHIFT:=Vector2(180,160)
var checks:=0
var failures:=0
var main
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func build(kind: String,x: float,z: float,support: String="",height: float=0.0) -> String:
	var result: Dictionary=main.building.begin({"kind":kind,"px":x+SHIFT.x,"pz":z+SHIFT.y,"py":height,"support":support,"turn":0})
	check(result.get("ok",false),"build "+kind+": "+str(result.get("reason","")))
	if not result.get("ok",false): return ""
	main.building.tick(30);return str(result.id)
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.cam.set_process(false)
	var econ=root.get_node("Economy");econ.set_process(false);econ.inventory.set_count("wood",2000)
	var structures:=0;var decorations:=0
	for kind: String in Catalog.RECIPES:
		if not Catalog.is_kit(kind): continue
		if Catalog.RECIPES[kind].group=="structure": structures+=1
		else: decorations+=1
		var pack=load(Catalog.RECIPES[kind].prefab);check(pack is PackedScene,"standalone prefab "+kind)
		var node=pack.instantiate();root.add_child(node)
		check(not node.find_children("*","MeshInstance3D",true,false).is_empty(),"visual geometry "+kind)
		if Catalog.RECIPES[kind].profile=="lamp": check(node.get_node_or_null("WarmLamp")!=null,"real lamp "+kind)
		node.queue_free()
	check(structures>=10 and decorations==10,"twelve structures and ten props")
	main.building_controller.recipe="oil_lamp";main.building_controller.build_level=0
	var fixed_request: Dictionary=main.building_controller._furnishing_request(Vector2(0,0))
	check(fixed_request.support=="@base" and main.building.geometry_reason(fixed_request)=="","original fixed deck accepts new component")
	check(main.building.can_place({"kind":"oil_lamp","px":-2.15,"pz":-1.28,"py":0,"support":"@base","turn":0})!="","original planted cells remain occupied")
	var legacy: Dictionary={"id":"built_900","kind":"deck","x":8,"z":8,"px":0.0,"pz":0.0,"turn":0,"support":"","left":0.0}
	var tile:=Catalog.footprint_rect(legacy)
	var near_edge:=Vector2(tile.end.x+2+.5,tile.get_center().y+.7)
	var snapped: Dictionary=Catalog.snap_foundation("raft_4x4",near_edge,0,[legacy])
	check(is_equal_approx(Catalog.footprint_rect(snapped).position.x,tile.end.x),"4x4 cursor snaps to exact old deck edge")
	check(main.building.geometry_reason({"kind":"oil_lamp","px":tile.get_center().x,"pz":tile.get_center().y,"py":0,"support":"missing","turn":0})!="","missing old-deck support still refused")
	main.building_controller.recipe=""
	var old_result: Dictionary=main.building.begin({"kind":"deck","x":3,"z":0})
	check(old_result.get("ok",false),"legacy board still builds in the real home world")
	main.building.tick(30)
	if old_result.get("ok",false):
		main.building_controller.recipe="wall"
		main.building_controller._rows_cache=main.building.query()
		var old_wall: Dictionary=main.building_controller._furnishing_request(Vector2(4.3,-1.2875))
		check(is_equal_approx(old_wall.pz,-1.2875) and old_wall.support==old_result.id and main.building.geometry_reason(old_wall)=="","structure preview uses legacy board module origin")
		main.building_controller.recipe=""
		var on_old: Dictionary=main.building.begin({"kind":"oil_lamp","px":4.3,"pz":-1.28,"py":0,"support":old_result.id,"turn":0})
		check(on_old.get("ok",false),"old constructed board really accepts a new lamp")
		main.building.tick(30)
		var actual_snap: Dictionary=Catalog.snap_foundation("raft_4x4",Vector2(7.6,-.8),0,main.building.query())
		var next_result: Dictionary=main.building.begin(actual_snap)
		check(next_result.get("ok",false),"snapped 4x4 builds flush beside the old board")
		main.building.tick(30)
		check(not main.building_world.area.path_between(Catalog.ORIGIN+Vector3(2,0,0),main.building_world.position_for(actual_snap)).is_empty(),"real home old/new seam is walkable")
	var base:=build("raft_4x4",20,0)
	var second_base:=build("raft_4x4",20,4)
	check(main.building.can_place({"kind":"raft_4x4","px":20+SHIFT.x,"pz":SHIFT.y,"py":0,"turn":0})!="","duplicate foundation denied")
	check(main.building.can_place({"kind":"roof_flat","px":20+SHIFT.x,"pz":SHIFT.y,"py":2.8,"support":base,"turn":0})!="","unsupported roof denied")
	if base=="": main.queue_free();await process_frame;quit(1);return
	var posts: Array[String]=[]
	for point: Vector2 in [Vector2(18,-2),Vector2(20,-2),Vector2(18,0),Vector2(20,0)]: posts.append(build("post",point.x,point.y,base))
	var floor_id:=build("upper_floor",19,-1,posts[0],2.8)
	var stairs:=build("stairs",19,2,base)
	check(main.building.can_remove(posts[0])!="","cannot remove floor support")
	var lamp:=build("oil_lamp",19,-1,floor_id,2.8)
	check(main.building_world.node_for(lamp)!=null and main.building_world.node_for(lamp).global_position.y>4.0,"lamp stands on upper floor")
	var saved: Dictionary=main.building.to_dict()
	check(main.building.validate_snapshot(saved)=="","save validates stacked layout")
	var reverse: Dictionary=saved.duplicate(true);reverse.instances.reverse()
	check(main.building.validate_snapshot(reverse)=="","support validation independent of record order")
	var zone=main._zone_nodes.zone5
	var from:=Catalog.ORIGIN+Vector3(19+SHIFT.x,0,5+SHIFT.y)
	var to:=Catalog.ORIGIN+Vector3(19+SHIFT.x,2.8,-1+SHIFT.y)
	check(main.building_world.contains_saved(to,main.building.query()),"upper floor saved pose")
	var route: Array=main.building_world._assembly_walk.path_between(from,to)
	check(not route.is_empty(),"real navigation connects stairs to upper floor")
	root.get_node("GameState").enter_zone("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[from.x,from.y,from.z]})
	for i in 3: await physics_frame
	check(main.actor_controller.start_walk(main.building_world._assembly_walk,to),"actor accepts upper-floor route")
	for i in 1500:
		main.actor_controller.tick(1.0/60)
		if not main.actor_controller.walking(): break
	print("[kit-climb] route=",route," at=",main.player.global_position," goal=",to," state=",main.actor_controller.state_id())
	check(main.player.global_position.distance_to(to)<.15,"real capsule climbs stairs to upstairs")
	var root_save=preload("res://src/save/save_game.gd")
	var snapshot: Dictionary=root_save.encode(main)
	check(root_save.restore(main,snapshot).get("ok",false),"whole game restores actor on upper floor with supported kit")
	check(main.player.global_position.distance_to(to)<.2,"upper actor pose stays upstairs after restore")
	check("让出" in main.building_boundary.space_reason({"kind":"stool","px":19+SHIFT.x,"pz":-1+SHIFT.y,"py":2.8,"turn":0}),"upper-floor furnishing cannot occupy the actor")
	check(main.building.can_remove(stairs)!="","upstairs actor cannot remove their stairs")
	var storage:=build("storage_crate",21,4.8,second_base)
	if storage!="":
		main.building_world.node_for(storage).interact(main.player)
		check(main.hud._tab=="storage","storage prop opens shared warehouse")
		main.hud.close_card()
	var barrel:=build("water_barrel",21,3,second_base)
	if barrel!="":
		econ.farm.watering_can=1;main.building_world.node_for(barrel).interact(main.player)
		check(econ.farm.watering_can==12,"water barrel invokes farm refill port")
	Catalog.RECIPES.oil_lamp.active=false
	check(main.building.validate_snapshot(main.building.to_dict())=="","retired recipe still restores existing objects")
	check(not main.building.begin({"kind":"oil_lamp","px":199,"pz":159,"py":2.8,"support":floor_id,"turn":0}).ok,"retired content cannot be newly built")
	Catalog.RECIPES.oil_lamp.active=true
	# Finish every catalog entry through the real service/world adapter, including
	# a supported roof and a doorway whose centre must stay physically passable.
	var house:=build("raft_4x4",40,0)
	var porch:=build("raft_2x4",43,0)
	build("wall",39,-2,house);build("window_wall",41,-2,house)
	build("door_frame",40,0,house);build("railing",43,2,porch)
	for point: Vector2 in [Vector2(38,-2),Vector2(42,-2),Vector2(38,2),Vector2(42,2)]: build("post",point.x,point.y,house)
	var flat:=build("roof_flat",40,0,main.building.query()[-1].id,2.8)
	check(flat!="","four posts support the full 4m roof")
	var ground: Array=main.building_world.area.rects
	var space=preload("res://src/building/building_space.gd")
	check(space.nearest(ground,SHIFT+Vector2(40,0),.01)!=Vector2.INF,"doorway centre remains walkable after world projection")
	check(space.nearest(ground,SHIFT+Vector2(39,-2),.01)==Vector2.INF,"solid wall centre blocks the actor")
	var roof_base:=build("raft_4x4",50,0)
	var roof_post:=""
	for point: Vector2 in [Vector2(49,-2),Vector2(51,-2),Vector2(49,2),Vector2(51,2)]: roof_post=build("post",point.x,point.y,roof_base)
	build("beam",50,2,roof_post,2.6);build("roof_slope",50,0,roof_post,2.8)
	var garden_a:=build("raft_4x4",60,0)
	var garden_b:=build("raft_4x4",64,0)
	var prop_index:=0
	for kind: String in Catalog.RECIPES:
		if not Catalog.is_kit(kind) or Catalog.RECIPES[kind].group!="decoration": continue
		var x:=58.8+(prop_index%5)*1.4
		var z:=-1.0+floori(prop_index/5.0)*2.0
		build(kind,x,z,garden_a if x<62 else garden_b)
		prop_index+=1
	var built_kinds: Dictionary={}
	for row in main.building.query():
		if Catalog.is_kit(row.kind) and row.left<=0: built_kinds[row.kind]=true
	check(built_kinds.size()==22,"all 22 entries finish in the real game world")
	check(main.building.validate_snapshot(main.building.to_dict())=="","full 22-component world retains a valid save")
	main.building_controller.open();check(main.building_controller.book.recipe_buttons.has("roof_flat"),"book discovers content")
	if DisplayServer.get_name()!="headless":
		main.water_node.show();main.cam.suspend_follow();main.cam.pan_bounds=Rect2(-500,-500,1000,1000);main.cam.target=Catalog.ORIGIN+Vector3(20+SHIFT.x,1.5,1+SHIFT.y);main.cam.distance=25;main.cam.refresh()
		for i in 10: main._process(0);await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/kit-book.png")
		main.building_controller.close()
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/kit-assembly.png")
	main.queue_free();await process_frame
	print("[building-kit] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
