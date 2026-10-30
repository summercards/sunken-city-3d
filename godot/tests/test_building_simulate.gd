extends SceneTree
## SEA-BUILDING player simulation. Assembles all twelve frame templates in the
## real scene through BuildingController/BuildingWorld, walks the result with the
## real capsule, drops all ten props on freshly finished platforms, then saves,
## restores and probes for bugs.
##
## Deliberately not a rule unit test: it exercises projection, navigation, farm
## binding and the whole-game save path.
const Catalog = preload("res://src/building/building_catalog.gd")
const Space = preload("res://src/building/building_space.gd")
const Surfaces = preload("res://src/building/assembly_surfaces.gd")
const SaveGame = preload("res://src/save/save_game.gd")
## Test plots live far from the home deck inside the same local build space.
const SHIFT := Vector2(180, 160)
var checks := 0
var failures := 0
var main
var econ
var frames: Array[String] = ["raft_4x4","raft_2x4","wall","window_wall","door_frame","post",
	"beam","railing","stairs","upper_floor","roof_slope","roof_flat"]
var props: Array[String] = ["oil_lamp","lamp_post","windmill","flower_pot","storage_crate",
	"water_barrel","flag","table","stool","wind_chime"]
## Hand-checked legal spots on the two garden rafts, kept 4 cm inside the union.
const PROP_SPOTS := {
	"oil_lamp": Vector2(59.0,-1), "lamp_post": Vector2(60.0,-1), "windmill": Vector2(61.2,-1),
	"flower_pot": Vector2(62.2,-1), "storage_crate": Vector2(63.4,-1),
	"water_barrel": Vector2(59.0,1), "flag": Vector2(60.0,1), "table": Vector2(61.3,1),
	"stool": Vector2(62.6,1), "wind_chime": Vector2(63.6,1)}

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func note(piece: String, what: String, value) -> void:
	print("[sim] %-13s %-12s %s"%[piece,what,str(value)])

func build(kind: String,x: float,z: float,support: String="",height: float=0.0) -> String:
	var before: int=econ.count("wood")
	var result: Dictionary=main.building.begin({"kind":kind,"px":x+SHIFT.x,"pz":z+SHIFT.y,
		"py":height,"support":support,"turn":0,"origin":"boat"})
	var spent: int=before-econ.count("wood")
	var cost:=int(Catalog.RECIPES[kind].cost.get("wood",0))
	check(result.get("ok",false),"build %s @(%s,%s): %s"%[kind,str(x),str(z),str(result.get("reason",""))])
	check(spent==(cost if result.get("ok",false) else 0),
		"wood charged once for %s (spent %d, cost %d)"%[kind,spent,cost])
	if not result.get("ok",false): return ""
	main.building.tick(30)
	return str(result.id)

func blocked(local: Vector2) -> bool:
	return Space.nearest(main.building_world.area.rects,local+SHIFT,0.02)==Vector2.INF
func passable(local: Vector2) -> bool: return not blocked(local)
func row_near(kind: String,local: Vector2) -> Dictionary:
	for row in main.building.query():
		if row.kind==kind and Vector2(row.px,row.pz).distance_to(local+SHIFT)<0.4: return row
	return {}

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.cam.set_process(false);main.cam.follow_enabled=false
	econ=root.get_node("Economy")
	econ.set_process(false);econ.inventory.set_count("wood",500);econ.inventory.set_count("soil",40)
	main._debug_teleport("zone5")
	root.get_node("GameState").enter_zone("zone5")
	for i in 4: await process_frame

	# ------------------------------------------------------------- platforms
	var a:=build("raft_4x4",20,0)        # 18..22, -2..2  house
	var b:=build("raft_4x4",20,4)        # 18..22,  2..6  stairs
	var porch:=build("raft_2x4",23,0)    # 22..24, -2..2  railing
	var beam_deck:=build("raft_2x4",25,0)# 24..26, -2..2  beam
	var roof_e:=build("raft_4x4",50,0)   # flat roof
	var roof_f:=build("raft_4x4",30,0)   # slope roof
	var garden_a:=build("raft_4x4",60,0)
	var garden_b:=build("raft_4x4",64,0)
	if a=="" or b=="" or garden_a=="" or garden_b=="":
		printerr("platform chain failed; aborting");main.queue_free();quit(1);return
	note("platforms","built","8 rafts chained and placed")

	# -------------------------------------------------------- frame assembly
	var p_nw:=build("post",18,-2,a)
	var p_ne:=build("post",20,-2,a)
	var p_sw:=build("post",18,0,a)
	var p_se:=build("post",20,0,a)
	var floor_id:=build("upper_floor",19,-1,p_nw,2.8)
	var stairs:=build("stairs",19,2,b)
	var wall:=build("wall",19,-2,a)
	var window_id:=build("window_wall",21,-2,a)
	var door:=build("door_frame",21,2,a)
	var railing:=build("railing",23,2,porch)
	var beam_post_a:=build("post",24,0,beam_deck)
	var beam_post_b:=build("post",26,0,beam_deck)
	var beam:=build("beam",25,0,beam_post_a,2.6)
	var flat_posts: Array[String]=[]
	for point: Vector2 in [Vector2(48,-2),Vector2(52,-2),Vector2(48,2),Vector2(52,2)]:
		flat_posts.append(build("post",point.x,point.y,roof_e))
	var flat:=build("roof_flat",50,0,flat_posts[0],2.8)
	var slope_posts: Array[String]=[]
	for point: Vector2 in [Vector2(29,-2),Vector2(31,-2),Vector2(29,2),Vector2(31,2)]:
		slope_posts.append(build("post",point.x,point.y,roof_f))
	var slope:=build("roof_slope",30,0,slope_posts[0],2.8)

	var built_kinds: Dictionary={}
	for row in main.building.query():
		if row.left<=0: built_kinds[str(row.kind)]=true
	var missing: Array[String]=[]
	for kind in frames:
		if not built_kinds.has(kind): missing.append(kind)
	check(missing.is_empty(),"all twelve frame templates assemble: missing "+str(missing))

	# ---------------------------------------------------- frame passability
	check(blocked(Vector2(19,-2)),"solid wall blocks the actor")
	check(blocked(Vector2(21,-2)),"window wall blocks the actor")
	check(blocked(Vector2(18,-2)),"post blocks the actor")
	check(blocked(Vector2(23,2)),"railing blocks the actor")
	check(passable(Vector2(21,2)),"door frame leaves a real opening")
	check(passable(Vector2(20,-1)),"the house floor stays walkable")
	check(passable(Vector2(25,0)),"beam (blocks_actor=false) leaves the deck walkable")
	check(passable(Vector2(20.6,3)),"the deck beside the stairs stays walkable")

	# Roofs must never become a walking surface (SEA-BUILDING-R20).
	var surface_kinds: Array[String]=[]
	for row in Surfaces.surface_rows(main.building.query()): surface_kinds.append(str(row.kind))
	check(not surface_kinds.has("roof_flat"),"the flat roof is not a walking surface")
	check(not surface_kinds.has("roof_slope"),"the sloped roof is not a walking surface")
	check(surface_kinds.has("stairs") and surface_kinds.has("upper_floor"),
		"only stairs and upper floor add surfaces")
	check(not Surfaces.contains(Catalog.ORIGIN+Vector3(50+SHIFT.x,2.8,0+SHIFT.y),main.building.query()),
		"the actor cannot stand on the flat roof")
	check(not Surfaces.contains(Catalog.ORIGIN+Vector3(30+SHIFT.x,2.8,0+SHIFT.y),main.building.query()),
		"the actor cannot stand on the sloped roof")
	check(not Surfaces.contains(Catalog.ORIGIN+Vector3(30+SHIFT.x,3.2,0+SHIFT.y),main.building.query()),
		"the sloped cone is not walkable either")

	# -------------------------------------------- real capsule: deck traversal
	root.get_node("GameState").enter_zone("zone5")
	var start:=Catalog.ORIGIN+Vector3(23+SHIFT.x,0.0,-1+SHIFT.y)
	main.actor_controller.restore_pose({"mode":0,"player":[start.x,start.y,start.z]})
	for i in 4: await physics_frame
	var far_end:=Catalog.ORIGIN+Vector3(20+SHIFT.x,0.0,5+SHIFT.y)
	check(main.actor_controller.start_walk(main.building_world.area,far_end),"actor accepts a deck route")
	for i in 3000:
		main.actor_controller.tick(1.0/60)
		if not main.actor_controller.walking(): break
	note("deck","traverse",'%.2f m from target'%main.player.global_position.distance_to(far_end))
	check(main.player.global_position.distance_to(far_end)<0.25,
		"capsule walks porch -> raft -> chained raft across both seams")

	# ------------------------------------------------ real capsule: climb stairs
	var foot:=Catalog.ORIGIN+Vector3(19+SHIFT.x,0.0,5+SHIFT.y)
	var upstairs:=Catalog.ORIGIN+Vector3(19+SHIFT.x,2.8,-1+SHIFT.y)
	main.actor_controller.restore_pose({"mode":0,"player":[foot.x,foot.y,foot.z]})
	for i in 4: await physics_frame
	var assembly=main.building_world._assembly_walk
	check(assembly!=null and not assembly.path_between(foot,upstairs).is_empty(),
		"navigation links the stairs to the upper floor")
	check(main.actor_controller.start_walk(assembly,upstairs),"actor accepts the climb route")
	for i in 2000:
		main.actor_controller.tick(1.0/60)
		if not main.actor_controller.walking(): break
	note("stairs","climb",'%.2f m from target'%main.player.global_position.distance_to(upstairs))
	check(main.player.global_position.distance_to(upstairs)<0.15,"capsule really climbs onto the second floor")

	# ------------------------------------------------------------------ save
	var before_rows: Array=main.building.query()
	var before_count:=before_rows.size()
	for row in before_rows:
		check(not row.has("origin"),"transient origin never reaches a row")
	var snapshot: Dictionary=SaveGame.encode(main)
	check(not snapshot.is_empty(),"whole game encodes")
	check(main.building.validate_snapshot(main.building.to_dict())=="","live layout validates")
	var reversed: Dictionary=main.building.to_dict();reversed.instances.reverse()
	check(main.building.validate_snapshot(reversed)=="","validation ignores record order")
	var restore: Dictionary=SaveGame.restore(main,snapshot)
	check(restore.get("ok",false),"whole game restores: %s"%str(restore.get("reason","")))
	var after_rows: Array=main.building.query()
	check(after_rows.size()==before_count,"restore keeps every instance (%d -> %d)"%[before_count,after_rows.size()])
	var mismatch:=""
	for i in mini(before_rows.size(),after_rows.size()):
		for key in ["id","kind","px","pz","py","turn","support","left"]:
			if str(before_rows[i].get(key))!=str(after_rows[i].get(key)):
				mismatch="%s.%s [%s] != [%s]"%[str(before_rows[i].id),key,
					str(before_rows[i].get(key)),str(after_rows[i].get(key))]
				break
		if mismatch!="": break
	check(mismatch=="","restore is field-identical: "+mismatch)
	check(main.player.global_position.y>Catalog.ORIGIN.y+2.0,"actor comes back on the second floor")
	check(main.building.validate_snapshot(main.building.to_dict())=="","re-saved layout still valid")
	note("save","restore","%d instances, actor y=%.2f"%[after_rows.size(),main.player.global_position.y])

	# ------------------------------------------------------------ decorations
	var placed: Array[String]=[]
	for kind in props:
		var spot: Vector2=PROP_SPOTS[kind]
		var support:=garden_a if spot.x<62.0 else garden_b
		var id:=build(kind,spot.x,spot.y,support)
		if id!="": placed.append(kind)
		var node: Node3D=main.building_world.node_for(id) if id!="" else null
		check(node!=null,"prop %s is projected into the world"%kind)
		if node!=null:
			var want:=Vector2(spot.x+SHIFT.x+Catalog.ORIGIN.x,spot.y+SHIFT.y+Catalog.ORIGIN.z)
			var got:=Vector2(node.global_position.x,node.global_position.z)
			check(got.distance_to(want)<0.02,"prop %s stands where the player aimed"%kind)
	check(placed.size()==10,"all ten props stand on freshly finished decks (%d/10)"%placed.size())

	for kind in props:
		var spot: Vector2=PROP_SPOTS[kind]
		var expected:=Catalog.blocks_actor(kind)
		check(blocked(spot)==expected,"prop %s blocking matches blocks_actor=%s"%[kind,str(expected)])

	# An upper-floor prop must not punch a hole in the ground deck.
	var upper_lamp:=build("oil_lamp",19.6,-1,floor_id,2.8)
	check(upper_lamp!="","a prop can be placed on the second floor")
	check(main.building_world.node_for(upper_lamp).global_position.y>4.0,"the upper prop is lifted to 2.8 m")
	check(passable(Vector2(19.6,-1)),"an upper prop does not cut the ground walk surface")

	# Behaviour ports must still fire on the new content.
	var storage_row:=row_near("storage_crate",PROP_SPOTS["storage_crate"])
	if not storage_row.is_empty():
		main.building_world.node_for(storage_row.id).interact(main.player)
		check(main.hud._tab=="storage","storage crate opens the shared warehouse")
		main.hud.close_card()
	var barrel_row:=row_near("water_barrel",PROP_SPOTS["water_barrel"])
	if not barrel_row.is_empty():
		econ.farm.watering_can=1
		main.building_world.node_for(barrel_row.id).interact(main.player)
		check(econ.farm.watering_can==12,"water barrel refills the can through the farm port")
	for kind in ["oil_lamp","lamp_post"]:
		var row:=row_near(kind,PROP_SPOTS[kind])
		if not row.is_empty():
			var node: Node3D=main.building_world.node_for(row.id)
			check(node.get_node_or_null("WarmLamp")!=null,"%s carries a real lamp"%kind)

	# -------------------------------------------------------------- mouse path
	var rejects: Array[String]=[]
	for probe in [{"kind":"wall","at":Vector2(21,3)},{"kind":"post","at":Vector2(21,0)},
			{"kind":"door_frame","at":Vector2(21,0)},{"kind":"railing","at":Vector2(23,-2)}]:
		main.building_controller.recipe=str(probe.kind)
		main.building_controller.build_level=0
		main.building_controller._rows_cache=main.building.query()
		var request: Dictionary=main.building_controller._furnishing_request(probe.at+SHIFT)
		main.building_controller.recipe=""
		var reason: String=main.building.can_place(request)
		if reason!="": rejects.append("%s: %s"%[probe.kind,reason])
	check(rejects.is_empty(),"mouse preview can place frames: "+str(rejects))

	# ------------------------------------------------------------- bug probes
	var wood_before: int=econ.count("wood")
	check(not main.building.begin({"kind":"raft_4x4","px":20+SHIFT.x,"pz":0+SHIFT.y,"py":0.0,
		"turn":0,"support":"","origin":"boat"}).ok and econ.count("wood")==wood_before,
		"a refused build charges nothing")
	check(main.building.can_remove(a)!="","a platform carrying a house cannot be reclaimed")
	check(main.building.can_remove(floor_id)!="","an occupied upper floor cannot be reclaimed")
	check(main.building.can_remove(p_nw)!="","a post bearing a floor cannot be reclaimed")
	if not upper_lamp.is_empty() and main.building.can_remove(upper_lamp)=="":
		var pre: int=econ.count("wood")
		var cost:=int(Catalog.RECIPES.oil_lamp.cost.get("wood",0))
		check(main.building.remove(upper_lamp).ok,"a free prop reclaims cleanly")
		check(econ.count("wood")==pre+cost,"reclaim refunds the full cost")
	else:
		check(false,"free upper prop was expected to be reclaimable")
	check(main.building.validate_snapshot(main.building.to_dict())=="","layout stays valid after reclaim")
	check(not main.building.begin({"kind":"upper_floor","px":19+SHIFT.x,"pz":2+SHIFT.y,"py":2.8,
		"turn":0,"support":""}).ok,"an upper floor without bearings is refused")
	check(not main.building.begin({"kind":"oil_lamp","px":19.6+SHIFT.x,"pz":-1+SHIFT.y,"py":2.8,
		"turn":0,"support":""}).ok,"a second-floor prop without a floor is refused")

	# ------------------------------------------------------------- matrices
	print("[sim] ---- frames ----")
	for kind in frames:
		print("[sim] frame %-12s assembled=%s" % [kind,"yes" if built_kinds.has(kind) else "NO"])
	print("[sim] ---- props ----")
	for kind in props:
		print("[sim] prop  %-12s placed=%s blocks=%s" % [kind,
			"yes" if placed.has(kind) else "NO",str(Catalog.blocks_actor(kind))])
	# A renderer-aware capture proves the assembled frames actually read as a
	# house; headless runs skip it because there is no frame to draw.
	if DisplayServer.get_name()!="headless":
		main.water_node.show()
		main.cam.suspend_follow();main.cam.pan_bounds=Rect2(-500,-500,1000,1000)
		for shot in [{"name":"kit-simulate-house","at":Vector3(20,1.5,2),"dist":26.0},
				{"name":"kit-simulate-props","at":Vector3(62,1.5,0),"dist":22.0}]:
			main.cam.target=Catalog.ORIGIN+Vector3(shot.at.x+SHIFT.x,shot.at.y,shot.at.z+SHIFT.y)
			main.cam.distance=float(shot.dist);main.cam.refresh()
			for i in 12: main._process(0);await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/%s.png"%shot.name)
	main.queue_free();await process_frame
	print("[building-simulate] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
