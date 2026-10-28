extends RefCounted
## Sole layout owner. Ports are supplied by composition, never obtained from globals.
const Catalog = preload("res://src/building/building_catalog.gd")
signal changed
signal completed(id: String)
var _rows: Array = []
var _next_id := 1
var _ports: Dictionary = {}
var _committing := false

func configure(ports: Dictionary) -> void:
	for key in ["eligibility","space_reason","pay"]: assert(ports.has(key) and ports[key].is_valid())
	_ports=ports.duplicate()
func catalog() -> Dictionary: return Catalog.RECIPES.duplicate(true)
func query() -> Array: return _rows.duplicate(true)
func busy() -> bool: return _committing
func context_reason() -> String: return _ports.eligibility.call() if _ports.has("eligibility") else "建造未就绪"
func row(id: String) -> Dictionary:
	for item in _rows:
		if item.id==id: return item.duplicate(true)
	return {}
func candidates() -> Array:
	var cells := {}
	for x in 3:
		for z in 2: cells[Vector2i(x,z)]=true
	for item in _rows:
		if item.kind=="deck" and item.left<=0: cells[Vector2i(item.x,item.z)]=true
	var result: Array=[]
	for x in range(0,5):
		for z in range(-2,4):
			if not Catalog.allowed_cell(x,z): continue
			var occupied := false
			for item in _rows:
				if item.kind=="deck" and item.x==x and item.z==z: occupied=true
			if occupied: continue
			for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if cells.has(Vector2i(x,z)+d):
					result.append({"kind":"deck","x":x,"z":z,"px":0.0,"pz":0.0,"turn":0,"support":""})
					break
	return result
func geometry_reason(request: Dictionary) -> String:
	var kind := str(request.get("kind",""))
	if not Catalog.RECIPES.has(kind): return "未知配方"
	for key in (["x","z"] if kind=="deck" else ["px","pz"]):
		var value: Variant=request.get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return "位置格式无效"
		if kind=="deck" and float(value)!=floor(float(value)): return "木板必须对齐拼接网格"
	var rotation: Variant=request.get("turn",0)
	if not (rotation is int or rotation is float) or not is_finite(float(rotation)) or rotation!=floor(rotation) or rotation<0 or rotation>3: return "朝向无效"
	if kind=="deck":
		for c in candidates():
			if c.x==request.get("x") and c.z==request.get("z"): return ""
		return "只能沿现有平台边缘拼接，且不能重叠"
	var support := row(str(request.get("support","")))
	if support.is_empty() or support.kind!="deck" or support.left>0: return "请放在已完成的新木板上"
	if not request.has("px") or not request.has("pz"): return "请选择位置"
	var rect := Catalog.plot_rect(request)
	if not Catalog.tile_rect(support.x,support.z).grow(-0.12).encloses(rect): return "种植区需要完整放在木板内"
	for item in _rows:
		if item.kind=="planter" and item.support==support.id: return "这块木板已经有种植区"
	return ""
func can_place(request: Dictionary) -> String:
	var reason := context_reason()
	if reason!="": return reason
	reason=geometry_reason(request)
	if reason!="": return reason
	return _ports.space_reason.call(request)
func begin(request: Dictionary) -> Dictionary:
	if _committing: return {"ok":false,"reason":"正在提交建造"}
	var reason := can_place(request)
	if reason!="": return {"ok":false,"reason":reason}
	var recipe: Dictionary=Catalog.RECIPES[request.kind]
	_committing=true
	if not _ports.pay.call(recipe.cost.duplicate(true)):
		_committing=false
		return {"ok":false,"reason":"材料不足，请拾取浮木或到商店买土壤"}
	var item := {"id":"built_%d"%_next_id,"kind":str(request.kind),"x":int(request.get("x",0)),"z":int(request.get("z",0)),
		"px":float(request.get("px",0)),"pz":float(request.get("pz",0)),"turn":int(request.get("turn",0))%4,
		"support":str(request.get("support","")),"left":float(recipe.seconds)}
	_next_id+=1
	_rows.append(item)
	_committing=false
	changed.emit()
	return {"ok":true,"id":item.id}
func tick(delta: float) -> void:
	var done: Array[String]=[]
	for item in _rows:
		if item.left<=0: continue
		item.left=maxf(0,float(item.left)-maxf(0,delta))
		if item.left==0: done.append(item.id)
	if not done.is_empty():
		changed.emit()
		for id in done: completed.emit(id)
func to_dict() -> Dictionary: return {"version":1,"next_id":_next_id,"instances":query()}
func from_dict(data: Dictionary) -> bool:
	if validate_snapshot(data)!="": return false
	_rows=data.instances.duplicate(true);_next_id=int(data.next_id)
	changed.emit()
	return true
static func empty_snapshot() -> Dictionary: return {"version":1,"next_id":1,"instances":[]}
static func validate_snapshot(data: Dictionary) -> String:
	if data.get("version")!=1 or not data.get("instances") is Array: return "Invalid building snapshot"
	if not data.get("next_id") is float and not data.get("next_id") is int: return "Invalid building sequence"
	if data.next_id<1 or data.next_id!=floor(data.next_id) or data.instances.size()>54: return "Invalid building sequence or count"
	var validator=load("res://src/building/building_service.gd").new()
	var ids := {}
	# Order is creation order: every child must refer to an earlier completed support.
	for raw in data.instances:
		if not raw is Dictionary: return "Invalid building record"
		for key in ["id","kind","support"]:
			if not raw.get(key) is String: return "Missing building string: "+key
		for key in ["x","z","px","pz","turn","left"]:
			var v: Variant=raw.get(key)
			if not (v is float or v is int) or not is_finite(float(v)): return "Invalid building number: "+key
		for key in ["x","z","turn"]:
			if raw[key]!=floor(raw[key]): return "Fractional building grid"
		if raw.turn<0 or raw.turn>3 or raw.left<0: return "Invalid building rotation/timer"
		if not Catalog.RECIPES.has(raw.kind) or raw.left>Catalog.RECIPES[raw.kind].seconds: return "Invalid building recipe/timer"
		var suffix: String=raw.id.trim_prefix("built_")
		if not suffix.is_valid_int() or raw.id!="built_%d"%int(suffix) or int(suffix)<1 or int(suffix)>=data.next_id or ids.has(raw.id): return "Invalid building identity"
		if validator.geometry_reason(raw)!="": return "Invalid building support or overlap"
		ids[raw.id]=true
		validator._rows.append(raw.duplicate(true))
	return ""
