extends SceneTree
const Catalog = preload("res://src/building/building_catalog.gd")
const Space = preload("res://src/building/building_space.gd")
const Boundary = preload("res://src/building/building_boundary.gd")
const Ground = preload("res://src/navigation/ground_path.gd")
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func deck(id: String,x: int,z: int) -> Dictionary:
	return {"id":id,"kind":"deck","x":x,"z":z,"left":0.0}
func plot(id: String,kind: String,px: float,pz: float) -> Dictionary:
	return {"id":id,"kind":kind,"px":px,"pz":pz,"turn":0,"left":0.0}
func polygons(rects: Array) -> Array:
	var result: Array=[]
	for rect: Rect2 in rects: result.append(Catalog.polygon(rect))
	return result
func run() -> void:
	var rows: Array=[deck("east",3,0),deck("east2",4,0)]
	var walk:=Space.walk_rects([Catalog.BASE],rows)
	var seam:=Vector2(Catalog.tile_rect(3,0).end.x,-1.2875)
	check(not Space.point_components(walk,Space.components(walk),seam).is_empty(),"tile seam is not eroded")
	check(not Ground.route(polygons(walk),Vector2(0,0),Vector2(6.45,-1.2875)).is_empty(),"cross-seam body-width route")
	var independent: Array=[deck("far",900,-700)]
	var remote:=Space.walk_rects([Catalog.BASE],independent)
	check(remote.size()<20,"sparse remote island does not allocate intervening ocean")
	check(Ground.route(polygons(remote),Vector2(0,0),Catalog.tile_rect(900,-700).get_center()).is_empty(),"separate island is not connected over water")
	var small:=rows.duplicate(true)
	small.append(plot("small","planter_small",4.3,-1.3))
	var small_walk:=Space.walk_rects([Catalog.BASE],small)
	check(Space.connection_reason(rows,small,walk,small_walk)=="","compact planter keeps existing route")
	check(not Space.operation_points(small[-1],small_walk).is_empty(),"compact planter has real standing anchors")
	var branch: Array=[]
	for z in 4: branch.append(deck("branch%d"%z,3,z))
	var old_walk:=Space.walk_rects([Catalog.BASE],branch)
	var narrow:=branch.duplicate(true)
	narrow.append(plot("a","planter",4.2,3.9));narrow.append(plot("b","planter",4.4,5.5))
	var new_walk:=Space.walk_rects([Catalog.BASE],narrow)
	check(Space.connection_reason(branch,narrow,old_walk,new_walk)=="","pass-through planters do not disconnect a supported platform")
	check(not Ground.route(polygons(new_walk),Vector2(0,0),Vector2(4.3,7.3)).is_empty(),"actor can cross planting beds rather than squeeze between their edges")
	check(Ground.contains(polygons(small_walk),Vector2(4.3,-1.3)),"small planter centre is walkable")
	check(not Catalog.blocks_actor("planter") and not Catalog.blocks_actor("planter_small"),"both planting recipes explicitly allow actor passage")
	var explicit_solid:=Space.walk_rects([Rect2(0,0,4,4)],[],[Rect2(1,1,1,1)])
	check(not Ground.contains(polygons(explicit_solid),Vector2(1.5,1.5)),"explicit solid footprint still blocks walking")
	var bridge_removed:=branch.duplicate(true);bridge_removed.remove_at(1)
	check(not Space.connection_reason(branch,bridge_removed,old_walk,Space.walk_rects([Catalog.BASE],bridge_removed)).is_empty(),"bridge removal cannot disconnect a platform")
	check(Boundary._shape_intersects(Rect2(0,0,2,2),{"x":2.5,"z":1,"hx":1,"round":true}),"round obstacle overlaps edge")
	check(not Boundary._shape_intersects(Rect2(0,0,1,1),{"x":2.5,"z":2.5,"hx":1,"round":true}),"round obstacle avoids AABB false positive")
	check(Boundary._shape_intersects(Rect2(-1,-1,2,2),{"x":0,"z":0,"hx":0.2,"hz":0.2}),"rectangle obstacle blocks footprint")
	var policy:=Boundary.new()
	policy.actor_query=func(): return {"mode":1,"zone":"zone1","state":"boat_idle","position":Vector3.ZERO}
	policy.boat_query=func(): return Vector3(100,1.12,100)
	policy.obstacles_query=func(): return []
	policy.protected_query=func(): return []
	check(policy.eligibility()=="","boat can build offshore")
	check(policy.space_reason({"kind":"deck","x":-10,"z":-10})=="","negative west and north ocean is not globally banned")
	var protected: Rect2=Catalog.tile_rect(-10,-10)
	protected.position+=Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
	policy.protected_query=func(): return [protected]
	check(not policy.space_reason({"kind":"deck","x":-10,"z":-10}).is_empty(),"actual dock reservation blocks matching footprint")
	print("[building-space] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
