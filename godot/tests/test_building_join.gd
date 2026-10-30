extends SceneTree
## SEA-BUILDING: platforms are one class. Legacy boards and both rafts join
## edge to edge, the seam is walkable, and a platform cannot be created with
## nothing to extend. Frames still need a real support socket.
const Service = preload("res://src/building/building_service.gd")
const Catalog = preload("res://src/building/building_catalog.gd")
const Space = preload("res://src/building/building_space.gd")
## Authorised walk surface of the fixed aqua platform, as authored in zone5.
const FIXED_WALK := Rect2(-3.200, -2.800, 6.500, 5.500)
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func model() -> RefCounted:
	var service:=Service.new()
	service.configure({"eligibility":func(): return "", "space_reason":func(_r): return "",
		"pay":func(_c): return true, "refund":func(_c): return true,
		"layout_reason":func(_b:Array,_a:Array,_r:Dictionary): return ""})
	return service
func platform(kind: String,x: float,z: float,turn: int=0,origin: String="shore") -> Dictionary:
	return {"kind":kind,"px":x,"pz":z,"py":0.0,"turn":turn,"support":"","origin":origin}
func deck_cell(x: int,z: int,origin: String="shore") -> Dictionary:
	return {"kind":"deck","x":x,"z":z,"origin":origin}
func rect_of(request: Dictionary) -> Rect2: return Catalog.footprint_rect(request)
func walkable(service: RefCounted,a: Vector2,b: Vector2) -> bool:
	var walk: Array=Space.walk_rects([FIXED_WALK],service.query(),[])
	var groups: Array=Space.components(walk)
	var from: Array=Space.point_components(walk,groups,a)
	for group in from:
		if Space.point_components(walk,groups,b).has(group): return true
	return false

func run() -> void:
	# 1. Content has exactly two behavioural classes.
	check(Catalog.is_platform("deck") and Catalog.is_platform("raft_4x4") and Catalog.is_platform("raft_2x4"),
		"legacy board and both rafts are one platform class")
	check(Catalog.is_frame("wall") and Catalog.is_frame("post") and Catalog.is_frame("roof_flat"),
		"walls, posts and roofs are frames")
	check(not Catalog.is_platform("wall") and not Catalog.is_frame("oil_lamp"),
		"a wall is not a platform and a lamp is not a frame")
	check(Catalog.category("raft_4x4")==Catalog.CATEGORY_PLATFORM,"raft reports the platform category")

	# 2. On foot nothing can be created without a seam to extend.
	var shore:=model()
	check(shore.preview_reason(platform("raft_4x4",900.0,900.0))!="","a raft cannot start on empty water on foot")
	check(shore.preview_reason(deck_cell(60,60))!="","a board cannot start on empty water on foot")
	var boat:=platform("raft_4x4",900.0,900.0,0,"boat")
	check(shore.preview_reason(boat)=="","the boat may start a platform in open water")

	# 3. Snapping always produces a real seam against the fixed platform.
	var north:=Vector2(0.0,-2.575)
	for offset: float in [0.3,0.8,1.5,2.5,3.5]:
		var snapped: Dictionary=Catalog.snap_foundation("raft_4x4",Vector2(0.0,north.y-offset),0,shore.query(),false)
		var shape: Rect2=rect_of(snapped)
		check(Catalog.platform_contact(shape,shore.query())>=Catalog.JOIN_MIN,
			"4x4 snapped %.1fm out still shares a real seam"%offset)
		check(not shape.grow(-0.002).intersects(Catalog.BASE),"4x4 never covers the fixed platform")
		check(shore.preview_reason(snapped)=="","snapped 4x4 is buildable at %.1fm"%offset)

	# 4. Both rafts and the legacy board chain together into one walkable deck.
	var first: Dictionary=shore.begin(platform("raft_4x4",-1.225,-4.575))
	check(first.ok,"raft joins the fixed platform: "+str(first.get("reason","")))
	shore.tick(6.0)
	var first_rect: Rect2=rect_of(shore.row(first.get("id","")))
	check(is_equal_approx(first_rect.end.y,-2.575),"the raft edge sits exactly on the platform edge")

	var second: Dictionary=shore.begin(platform("raft_2x4",first_rect.end.x+1.0,first_rect.get_center().y))
	check(second.ok,"a 2x4 raft joins the 4x4 raft: "+str(second.get("reason","")))
	shore.tick(5.0)
	var third: Dictionary=shore.begin(deck_cell(3,0))
	check(third.ok,"a legacy board still joins the fixed platform: "+str(third.get("reason","")))
	shore.tick(3.0)

	check(walkable(shore,Vector2(0.0,-1.0),Vector2(-1.0,-4.0)),"the platform and the 4x4 raft are one walkable surface")
	check(walkable(shore,Vector2(0.0,-1.0),Vector2(first_rect.end.x+1.0,first_rect.get_center().y)),
		"a body can walk from the platform across the raft onto the 2x4")
	check(walkable(shore,Vector2(0.0,-1.0),Catalog.tile_rect(3,0).get_center()),
		"the legacy board seam is walkable too")

	# 5. A raft that only touches at a corner is not joined.
	var corner: Dictionary=platform("raft_4x4",first_rect.position.x-2.0,first_rect.position.y-2.0)
	var corner_rect: Rect2=rect_of(corner)
	check(Catalog.platform_contact(corner_rect,shore.query())<Catalog.JOIN_MIN,
		"two rafts meeting at one corner share no seam")
	check(shore.preview_reason(corner)!="","a corner-touching raft is refused on foot")

	# 6. Frames still need a support; the platform class did not loosen that.
	check(shore.preview_reason({"kind":"wall","px":0.0,"pz":-4.0,"py":0.0,"turn":0,"support":first.get("id","")})=="",
		"a wall stands on the finished raft")
	check(shore.preview_reason({"kind":"wall","px":900.0,"pz":902.0,"py":0.0,"turn":0,"support":""})!="",
		"a wall cannot float on open water")

	# 7. Old saves that already contain a lone raft still load; the rule only
	#    governs new work.
	var legacy_snapshot: Dictionary={"version":1,"next_id":3,"instances":[
		{"id":"built_1","kind":"raft_4x4","x":0,"z":0,"px":900.0,"pz":900.0,"py":0.0,"turn":0,"support":"","left":0.0},
		{"id":"built_2","kind":"oil_lamp","x":0,"z":0,"px":900.0,"pz":900.0,"py":0.0,"turn":0,"support":"built_1","left":0.0}]}
	check(Service.validate_snapshot(legacy_snapshot)=="","a layout saved with a lone raft still validates")
	var restored:=model()
	check(restored.from_dict(legacy_snapshot) and restored.query().size()==2,"a lone-raft save still restores")
	check(restored.can_place(platform("raft_4x4",904.0,900.0))=="","the restored lone raft can be extended again")

	# 8. Removing the last joined neighbour is still refused; the platform rule
	#    never deletes what a player built.
	check(restored.can_remove("built_1")!="","a raft carrying a lamp cannot be reclaimed")

	print("[building-join] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
