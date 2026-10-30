extends SceneTree
## Pure placement/transaction regressions: no Main, rendering or singletons.
const Catalog=preload("res://src/building/building_catalog.gd")
const Assembly=preload("res://src/building/assembly_rules.gd")
const Service=preload("res://src/building/building_service.gd")
const Space=preload("res://src/building/building_space.gd")
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func row(kind: String,id: int,x: float,z: float,support: String="",height: float=0.0,turn: int=0) -> Dictionary:
	return {"id":"built_%d"%id,"kind":kind,"x":0,"z":0,"px":x,"pz":z,"py":height,"support":support,"turn":turn,"left":0.0}
func base() -> Dictionary: return row("raft_4x4",1,100,100)
func supports(points: Array) -> Array:
	var rows: Array=[base()]
	for point: Vector2 in points: rows.append(row("post",rows.size()+1,point.x,point.y,"built_1"))
	return rows
func model() -> RefCounted:
	var service:=Service.new()
	service.configure({"eligibility":func(): return "","space_reason":func(_request): return "","pay":func(_cost): return true,"refund":func(_cost): return true})
	return service
func run() -> void:
	# Every catalog role has an intentional supported positive fixture; scene
	# loading is covered separately by building-kit, not repeated here.
	var seen:=0
	for kind: String in Catalog.RECIPES:
		if not Catalog.is_kit(kind): continue
		seen+=1
		var definition: Dictionary=Catalog.RECIPES[kind]
		var fixture: Array=[base()]
		var candidate:=row(kind,100,100,100,"built_1")
		if definition.profile=="foundation":
			candidate=row(kind,100,110,100)
		elif definition.profile=="beam":
			fixture=supports([Vector2(99,100),Vector2(101,100)])
			candidate.support="built_2";candidate.py=2.6
		elif definition.profile=="floor":
			fixture=supports([Vector2(99,99),Vector2(99,101),Vector2(101,99),Vector2(101,101)])
			candidate.support="built_2";candidate.py=2.8
		elif definition.profile=="roof":
			fixture=supports([Vector2(98,98),Vector2(98,102),Vector2(102,98),Vector2(102,102)] if kind=="roof_flat" else [Vector2(99,98),Vector2(99,102),Vector2(101,98),Vector2(101,102)])
			candidate.support="built_2";candidate.py=2.8
		var reason: String=Assembly.reason(candidate,fixture)
		check(reason=="","supported content "+kind+": "+reason)
		if definition.profile!="foundation":
			var missing: Dictionary=candidate.duplicate();missing.support="gone"
			check(Assembly.reason(missing,fixture)!="","missing support rejected "+kind)
	check(seen>=22,"all twelve structures and ten decorations covered")
	# A wall corner is allowed, broad intersections and parallel stacking are not.
	var wall:=row("wall",2,100,100,"built_1")
	var wall_fixture: Array=[base(),wall]
	check(Assembly.reason(row("window_wall",3,100,100,"built_1"),wall_fixture)!="","window wall cannot replace occupied solid wall")
	check(Assembly.reason(row("door_frame",3,100.5,100,"built_1"),wall_fixture)!="","half-overlapped doorway rejected")
	check(Assembly.reason(row("wall",3,100,100,"built_1",0,1),wall_fixture)!="","midspan crossed walls rejected")
	check(Assembly.reason(row("wall",3,101,101,"built_1",0,1),wall_fixture)=="","perpendicular endpoint corner remains legal")
	var floor_fixture:=supports([Vector2(99,99),Vector2(99,101),Vector2(101,99),Vector2(101,101)])
	var floor_row:=row("upper_floor",6,100,100,"built_2",2.8)
	floor_fixture.append(floor_row)
	check(Assembly.reason(row("upper_floor",7,100,100,"built_2",2.8),floor_fixture)!="","duplicate upper floor denied")
	check(Assembly.reason(row("oil_lamp",7,100,100,"built_6",2.8),floor_fixture)=="","upper floor supports a real furnishing")
	var incomplete: Array=floor_fixture.duplicate(true);incomplete.remove_at(4);incomplete.remove_at(incomplete.size()-1)
	check(Assembly.reason(floor_row,incomplete)!="","three columns cannot support four floor corners")
	var rotated_beam_fixture:=supports([Vector2(100,99),Vector2(100,101)])
	check(Assembly.reason(row("beam",4,100,100,"built_2",2.6,1),rotated_beam_fixture)=="","rotated beam uses rotated end sockets")
	check(Assembly.reason(row("beam",4,100,100,"built_2",0,1),rotated_beam_fixture)!="","beam cannot float at ground socket height")
	# Keep complete support chains, independent of creation or save record order.
	var service:=model()
	var snapshot: Dictionary={"version":1,"next_id":7,"instances":floor_fixture}
	check(service.from_dict(snapshot),"supported structural fixture restores")
	check(service.can_remove("built_2")!="","support column cannot be removed under floor")
	var lamp_request:=row("oil_lamp",7,100,100,"built_6",2.8);lamp_request.erase("id")
	var placed: Dictionary=service.begin(lamp_request)
	check(placed.get("ok",false),"furnishing construction accepted upstairs")
	service.tick(30)
	check(service.can_remove("built_6")!="","floor cannot be removed under furnishing")
	check(service.remove(str(placed.get("id",""))).get("ok",false),"remove top furnishing first")
	check(service.remove("built_6").get("ok",false),"floor removable after dependents cleared")
	check(service.can_remove("built_2")=="","column released after top component removal")
	var reversed: Dictionary=snapshot.duplicate(true);reversed.instances.reverse()
	check(Service.validate_snapshot(reversed)=="","save reconstruction resolves support graph without record order")
	var active_before: bool=Catalog.RECIPES.oil_lamp.active
	Catalog.RECIPES.oil_lamp.active=false
	check(service.begin(lamp_request).get("ok",true)==false,"retired recipe refuses new construction")
	var historical: Dictionary=snapshot.duplicate(true);historical.instances.append(row("oil_lamp",7,100,100,"built_6",2.8));historical.next_id=8
	check(Service.validate_snapshot(historical)=="","retired content retains historical save compatibility")
	Catalog.RECIPES.oil_lamp.active=active_before
	# Old boards and the new 4 m foundation share an actual geometric seam,
	# not a common cell size. Both bearing and actor centres cross that seam.
	var legacy: Dictionary={"id":"built_1","kind":"deck","x":10,"z":10,"px":0.0,"pz":0.0,"turn":0,"support":"","left":0.0}
	var legacy_rect:=Catalog.footprint_rect(legacy)
	var seam:=legacy_rect.end.x
	var adjacent:=row("raft_4x4",2,seam+2,legacy_rect.get_center().y)
	var mixed: Array=[legacy,adjacent]
	check(Assembly.reason(adjacent,[legacy])=="","4x4 foundation exactly adjoins legacy board")
	var overlapping:=adjacent.duplicate();overlapping.px-=0.2
	check(Assembly.reason(overlapping,[legacy])!="","foundation crossing the legacy footprint rejected")
	var cross:=row("oil_lamp",3,seam,legacy_rect.get_center().y,"built_1")
	check(Assembly.reason(cross,mixed)=="","kit furnishing can straddle old/new foundation seam")
	var pure:=model();check(pure.from_dict({"version":1,"next_id":3,"instances":mixed}),"mixed foundation save restores")
	cross.erase("id")
	check(pure.can_place(cross)=="","service accepts straddling content on old board primary support")
	var planter:=cross.duplicate();planter.kind="planter_small"
	check(pure.can_place(planter)=="","legacy planting uses the same mixed foundation union")
	var walk: Array=Space.walk_rects([],mixed)
	var walk_groups: Array=Space.components(walk)
	var a:=Vector2(seam-0.3,legacy_rect.get_center().y)
	var b:=Vector2(seam+0.3,legacy_rect.get_center().y)
	check(not Space.intersect_ids(Space.point_components(walk,walk_groups,a),Space.point_components(walk,walk_groups,b)).is_empty(),"actor-width path stays connected across exact old/new seam")
	var gap:=adjacent.duplicate();gap.px+=0.1
	var gapped: Array=Space.walk_rects([],[legacy,gap]);var gap_groups: Array=Space.components(gapped)
	check(Space.intersect_ids(Space.point_components(gapped,gap_groups,a),Space.point_components(gapped,gap_groups,b+Vector2(.1,0))).is_empty(),"water gap is not silently bridged")
	var bad:=row("oil_lamp",100,100,100,"built_1");bad.py=NAN
	check(Assembly.reason(bad,[base()])!="","nonfinite height rejected")
	check(pure.geometry_reason({"kind":"unknown_component","px":1,"pz":1,"turn":0})!="","unknown content does not become generic furnishing")
	# A post corner and a wall end are the same socket point. Taking only the
	# first owner made a legal floor depend on which of the two was built first,
	# so a layout could be accepted and then fail its own save validation.
	var bearing_deck:=row("raft_4x4",200,20,20)
	var bearing_posts: Array=[row("post",201,19,19,"built_200"),row("post",202,21,19,"built_200"),
		row("post",203,19,21,"built_200"),row("post",204,21,21,"built_200")]
	var bearing_floor:=row("upper_floor",205,20,20,"built_201",2.8)
	# This wall's two end sockets land exactly on the floor's north corners.
	var corner_wall:=row("wall",206,20,19,"built_200")
	check(Assembly.reason(bearing_floor,[bearing_deck]+bearing_posts+[corner_wall])=="",
		"floor finds its bearing post when the wall comes after")
	check(Assembly.reason(bearing_floor,[bearing_deck,corner_wall]+bearing_posts)=="",
		"floor still finds its bearing post when the wall came first")
	check(Assembly.bearing_ids(bearing_floor,[bearing_deck,corner_wall]+bearing_posts).has(str(bearing_floor.support)),
		"every socket owner counts at a shared corner, not just the first match")
	print("[kit-safety] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
