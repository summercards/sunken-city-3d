extends SceneTree
const Service = preload("res://src/building/building_service.gd")
var checks:=0
var failures:=0
var balance: Dictionary={"wood":30,"soil":6}
var allowed:=true
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func pay(cost: Dictionary) -> bool:
	for id in cost:
		if balance.get(id,0)<cost[id]: return false
	for id in cost: balance[id]-=cost[id]
	return true
func _init() -> void: call_deferred("run")
func run() -> void:
	check(root.get_node_or_null("Economy")==null,"rules run without Autoload")
	var service=Service.new()
	service.configure({"eligibility":func(): return "" if allowed else "land required","space_reason":func(_r): return "","pay":pay})
	var candidate: Dictionary=service.candidates()[0]
	allowed=false
	check(not service.begin(candidate).ok and balance.wood==30,"offshore denied without payment")
	allowed=true
	var result: Dictionary=service.begin(candidate)
	check(result.ok and balance.wood==24,"one deck payment")
	check(not service.begin(candidate).ok and balance.wood==24,"repeat rejected")
	check(not service.begin({"kind":"deck","x":40,"z":40}).ok,"remote cell rejected")
	service.tick(1)
	var snapshot: Dictionary=service.to_dict()
	check(is_equal_approx(snapshot.instances[0].left,2),"relative progress")
	check(Service.validate_snapshot(snapshot)=="","valid work snapshot")
	service.from_dict(snapshot);service.tick(2)
	check(service.row(result.id).left==0 and balance.wood==24,"restore finishes without payment")
	var deck: Dictionary=service.row(result.id)
	var p: Vector2=preload("res://src/building/building_catalog.gd").tile_rect(deck.x,deck.z).get_center()
	var planter: Dictionary={"kind":"planter","support":deck.id,"px":p.x,"pz":p.y,"turn":0}
	check(service.begin(planter).ok and balance.wood==21 and balance.soil==4,"planter payment")
	check(not service.begin(planter).ok,"occupied support denied")
	service.tick(4)
	check(Service.validate_snapshot(service.to_dict())=="","completed layouts validate")
	var copy: Array=service.query();copy.clear()
	check(service.query().size()==2,"queries isolated")
	var bad: Dictionary=service.to_dict();bad.instances[1].support="missing"
	check(Service.validate_snapshot(bad)!="","missing support rejected")
	bad=service.to_dict();bad.instances[0].left=8
	check(Service.validate_snapshot(bad)!="","timer overflow rejected")
	bad=service.to_dict();bad.instances[1].id=bad.instances[0].id
	check(Service.validate_snapshot(bad)!="","duplicate ID rejected")
	bad=service.to_dict();bad.instances[1].px=900
	check(Service.validate_snapshot(bad)!="","unsupported planter rejected")
	bad=service.to_dict();bad.instances[1].turn=0.5
	check(Service.validate_snapshot(bad)!="","fractional rotation rejected")
	bad=service.to_dict();bad.next_id=1
	check(Service.validate_snapshot(bad)!="","bad sequence rejected")
	balance.wood=0
	check(not service.begin(service.candidates()[0]).ok and service.query().size()==2,"no funds no instance")
	# Replace only eligibility: future offshore capability has a real injection point.
	allowed=false
	service.configure({"eligibility":func(): return "","space_reason":func(_r): return "","pay":pay})
	check(service.context_reason()=="","future policy can be replaced")
	print("[building] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
