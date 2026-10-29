extends SceneTree
## Rule-level regressions for open-ocean construction and stable DIY mutations.
const Service = preload("res://src/building/building_service.gd")
const Catalog = preload("res://src/building/building_catalog.gd")
const Schema = preload("res://src/save/save_schema.gd")
const Contract = preload("res://src/core/record_contract.gd")
var checks := 0
var failures := 0
var paid := 0
var refunded := 0
var refund_allowed := true
var layout_blocked := false
var callback_seen := {}
var reentry_service: RefCounted
var reentry_blocked := false

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func configured() -> RefCounted:
	var service:=Service.new()
	service.configure({"eligibility":func(): return "", "space_reason":func(_r): return "",
		"pay":func(_cost): paid+=1;return true,
		"refund":func(_cost):
			if not refund_allowed: return false
			refunded+=1;return true,
		"layout_reason":func(before:Array,after:Array,request:Dictionary):
			callback_seen={"before":before.size(),"after":after.size(),"operation":request.operation,"id":request.id}
			return "occupied crop" if layout_blocked else ""})
	return service
func deck(x:int,z:int) -> Dictionary: return {"kind":"deck","x":x,"z":z}
func furnish(id:String,x:float,z:float,kind:="planter_small") -> Dictionary:
	return {"kind":kind,"px":x,"pz":z,"support":id,"turn":0}
func make_deck(service:RefCounted,x:int,z:int) -> Dictionary:
	var result:Dictionary=service.begin(deck(x,z))
	check(result.ok,"deck accepted at %d,%d"%[x,z])
	service.tick(3.0)
	return service.row(result.get("id",""))
func run() -> void:
	var service:=configured()
	check(Catalog.allowed_cell(-100,100) and Catalog.allowed_cell(100,-100),"no ring or west-side prohibition")
	check(not Catalog.allowed_cell(0,0),"original platform cannot be overwritten")
	var far:=make_deck(service,40,-40)
	check(not far.is_empty(),"disconnected foundation accepted by geometry; policy owns eligibility")
	var frontier:Dictionary={}
	for candidate in service.candidates(): frontier[Vector2i(candidate.x,candidate.z)]=true
	check(frontier.has(Vector2i(41,-40)) and frontier.has(Vector2i(40,-41)),"sparse frontier follows remote foundation")
	var count_before:int=paid
	check(not service.begin(deck(40,-40)).ok and paid==count_before,"duplicate foundation never pays again")
	check(not service.begin({"kind":"deck","x":INF,"z":0}).ok,"nonfinite grid rejected")
	check(not service.begin({"kind":"deck","x":0.1,"z":5}).ok,"fractional grid rejected")
	for i in 70: make_deck(service,100+i,100)
	var snapshot:Dictionary=service.to_dict()
	check(snapshot.instances.size()>54 and Service.validate_snapshot(snapshot)=="","more than 54 instances round-trip")
	check(Contract.check(snapshot,Schema.schemas().building)=="","wire schema uses the same unlimited count contract")
	var fresh:=configured()
	check(fresh.from_dict(snapshot) and fresh.query().size()==service.query().size(),"large layout restores")
	var copy:Array=service.query();copy.clear()
	check(not service.query().is_empty(),"query cannot mutate owner")

	var a:=make_deck(service,0,5)
	var center_a:Vector2=Catalog.tile_rect(0,5).get_center()
	var built:Dictionary=service.begin(furnish(a.id,center_a.x,center_a.y))
	check(built.ok,"compact planter uses metadata footprint")
	check(not service.can_move(built.id,furnish(a.id,center_a.x,center_a.y)).is_empty(),"unfinished furnishing cannot move")
	check(not service.can_remove(built.id).is_empty(),"unfinished furnishing cannot remove")
	service.tick(3.0)
	var b:=make_deck(service,1,5)
	var center_b:Vector2=Catalog.tile_rect(1,5).get_center()
	var before_id:String=built.id
	var move_request:=furnish(b.id,center_b.x+0.01,center_b.y+0.02)
	move_request.exclude_id=built.id
	move_request.turn=1
	count_before=paid
	check(service.can_move(built.id,move_request)=="","self excluded from relocation overlap")
	check(service.move(built.id,move_request).ok,"move to newer support commits")
	check(service.row(built.id).id==before_id and service.row(built.id).support==b.id and service.row(built.id).turn==1,"move preserves identity and changes support/rotation")
	check(paid==count_before,"move has no material payment")
	check(callback_seen.operation=="move" and callback_seen.before==callback_seen.after,"layout preview receives whole before and after worlds")
	check(Service.validate_snapshot(service.to_dict())=="","moved item supported by later-created deck restores")
	var reversed:Dictionary=service.to_dict()
	reversed.instances.reverse()
	check(Service.validate_snapshot(reversed)=="","snapshot validation independent of creation order")
	check(not service.can_remove(b.id).is_empty(),"cannot remove current support")
	check(service.can_remove(a.id)=="","old support becomes removable")
	check(service.remove(a.id).ok and refunded==1,"empty deck refunds once")
	check(not service.remove(a.id).ok and refunded==1,"double remove does not refund twice")

	var blocked_snapshot:Dictionary=service.to_dict()
	layout_blocked=true
	check(not service.move(built.id,furnish(b.id,center_b.x,center_b.y)).ok,"policy can reject relocation")
	check(not service.remove(built.id).ok,"policy protects living crop")
	check(service.to_dict()==blocked_snapshot,"rejected mutation leaves whole layout unchanged")
	layout_blocked=false;refund_allowed=false
	check(not service.remove(built.id).ok and service.to_dict()==blocked_snapshot,"full bag leaves object and state unchanged")
	refund_allowed=true
	check(service.remove(built.id).ok and refunded==2,"empty planter reclaim is atomic")
	check(service.remove(b.id).ok and refunded==3,"support reclaims after furnishing removal")
	check(Service.validate_snapshot(service.to_dict())=="","holes in instance ids after removal remain valid")

	var edge_service:=configured()
	var support:=make_deck(edge_service,7,7)
	var center:Vector2=Catalog.tile_rect(7,7).get_center()
	var tiny:Dictionary=edge_service.begin(furnish(support.id,center.x,center.y))
	edge_service.tick(3.0)
	var edge_req:=furnish(support.id,center.x+0.68,center.y)
	edge_req.exclude_id=tiny.id
	var snapped:Dictionary=edge_service.snap_planter(edge_req)
	check(edge_service.can_move(tiny.id,snapped)=="","snap honours moved id and compact footprint")
	var bad:Dictionary=service.to_dict();bad.instances.append(bad.instances[0].duplicate(true))
	check(Service.validate_snapshot(bad)!="","duplicate id rejected in large layout")
	bad=service.to_dict();bad.instances[0].x=4294967296
	check(Service.validate_snapshot(bad)!="","extreme coordinates cannot wrap occupancy keys")
	bad=service.to_dict();bad.instances[0].exclude_id=bad.instances[0].id
	check(Service.validate_snapshot(bad)!="","transient self-exclusion cannot enter saved layouts")
	var capacity:=Service.new()
	capacity.configure({"eligibility":func():return "","space_reason":func(_r):return "","pay":func(_cost):paid+=1;return true,
		"capacity_reason":func(_after:Array):return "snapshot storage full"})
	count_before=paid
	check(not capacity.begin(deck(90,90)).ok and paid==count_before and capacity.query().is_empty(),"aggregate byte admission rejects before payment")
	bad=service.to_dict();bad.instances[0].unrecognized_payload="x".repeat(Catalog.MAX_LAYOUT_BYTES+1)
	check(Service.validate_snapshot(bad)!="","technical byte budget matches snapshot validation")
	reentry_service=Service.new()
	reentry_service.configure({"eligibility":func():return "","space_reason":func(_r):return "","pay":func(_c):return true,
		"refund":func(_c):
			reentry_blocked=not reentry_service.begin(deck(91,91)).ok and reentry_service.busy()
			return true})
	var reclaim:=make_deck(reentry_service,90,90)
	check(reentry_service.remove(reclaim.id).ok and reentry_blocked and reentry_service.query().is_empty(),"refund callbacks cannot reenter layout commits")
	reentry_service=null
	var ignored:=configured()
	var poisoned_deck:=deck(92,92)
	poisoned_deck.px=[];poisoned_deck.pz=INF;poisoned_deck.support="not-a-support"
	var clean_deck:Dictionary=ignored.begin(poisoned_deck)
	check(clean_deck.ok and Service.validate_snapshot(ignored.to_dict())=="","unused deck request fields cannot poison committed snapshot")
	ignored.tick(3.0)
	var at:Vector2=Catalog.tile_rect(92,92).get_center()
	var poisoned_box:=furnish(clean_deck.id,at.x,at.y)
	poisoned_box.x=[];poisoned_box.z=INF
	var clean_box:Dictionary=ignored.begin(poisoned_box)
	check(clean_box.ok and Service.validate_snapshot(ignored.to_dict())=="","unused furnishing request fields cannot trigger conversion errors")
	ignored.tick(3.0)
	check(ignored.move(clean_box.id,poisoned_box).ok and Service.validate_snapshot(ignored.to_dict())=="","relocation canonicalizes unused fields too")
	check(ignored.move(clean_box.id,{"turn":2}).ok and ignored.row(clean_box.id).turn==2 and ignored.row(clean_box.id).support==clean_deck.id,"partial move infers recipe and keeps stable position/support")
	var invalid_pose:=furnish(clean_deck.id,at.x,at.y)
	invalid_pose.px=[]
	check(not ignored.can_move(clean_box.id,invalid_pose).is_empty(),"malformed move position returns a rule error")
	check(ignored.snap_planter(invalid_pose)==invalid_pose,"malformed snap query does not convert invalid values")
	print("[building-open-rules] %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
