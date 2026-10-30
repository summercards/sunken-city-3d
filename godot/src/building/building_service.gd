extends RefCounted
## Sole layout owner. All scene, route, inventory and crop policies are injected.
const Assembly = preload("res://src/building/assembly_rules.gd")
const Catalog = preload("res://src/building/building_catalog.gd")
signal changed
signal completed(id: String)
var _rows: Array = []
var _next_id := 1
var _ports: Dictionary = {}
var _committing := false
var _by_id: Dictionary = {}
var _deck_cells: Dictionary = {}
var _finished_tiles: Array = []

func configure(ports: Dictionary) -> void:
	for key in ["eligibility","space_reason","pay"]:
		assert(ports.has(key) and ports[key].is_valid())
	_ports=ports.duplicate()
func catalog() -> Dictionary: return Catalog.RECIPES.duplicate(true)
func query() -> Array: return _rows.duplicate(true)
func busy() -> bool: return _committing
func context_reason() -> String:
	return _ports.eligibility.call() if _ports.has("eligibility") else "建造未就绪"
func row(id: String) -> Dictionary:
	return (_by_id.get(id,{}) as Dictionary).duplicate(true)

func _index(item: Dictionary) -> void:
	_by_id[item.id]=item
	if item.kind!="deck" and Catalog.is_deck(str(item.kind)) and float(item.left)<=0: _finished_tiles.append(Catalog.footprint_rect(item))
	if item.kind=="deck":
		_deck_cells[Vector2i(int(item.x),int(item.z))]=item
		if float(item.left)<=0.0: _finished_tiles.append(Catalog.tile_rect(int(item.x),int(item.z)))
func _reindex() -> void:
	_by_id.clear();_deck_cells.clear();_finished_tiles.clear()
	for item in _rows: _index(item)

## A sparse frontier, with no fixed scan rectangle and no gameplay size cap.
## Independent foundations are selected directly on the sea; this list only
## supplies useful adjacent suggestions for existing platforms.
func candidates() -> Array:
	var cells: Dictionary={}
	for x in 3:
		for z in 2: cells[Vector2i(x,z)]=true
	for cell: Vector2i in _deck_cells:
		if float(_deck_cells[cell].left)<=0.0: cells[cell]=true
	var frontier: Dictionary={}
	for cell: Vector2i in cells:
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i=cell+direction
			if not Catalog.allowed_cell(next.x,next.y) or _deck_cells.has(next): continue
			frontier[next]=true
	var keys: Array=frontier.keys()
	keys.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.x<b.x or (a.x==b.x and a.y<b.y))
	var result: Array=[]
	for cell: Vector2i in keys:
		result.append({"kind":"deck","x":cell.x,"z":cell.y,"px":0.0,"pz":0.0,"turn":0,"support":""})
	return result

func geometry_reason(request: Dictionary) -> String:
	var kind := str(request.get("kind",""))
	if not Catalog.RECIPES.has(kind): return "未知配方"
	for key in (["x","z"] if kind=="deck" else ["px","pz"]):
		var value: Variant=request.get(key)
		if not (value is int or value is float) or not is_finite(float(value)): return "位置格式无效"
		if kind=="deck" and float(value)!=floor(float(value)): return "木板必须对齐拼接网格"
		# Vector2i keys must never silently wrap an extreme untrusted integer.
		if kind=="deck" and (float(value)<-2147483648.0 or float(value)>2147483647.0): return "位置超出数值精度"
	var rotation: Variant=request.get("turn",0)
	if not (rotation is int or rotation is float) or not is_finite(float(rotation)) or rotation!=floor(rotation) or rotation<0 or rotation>3:
		return "朝向无效"
	if Catalog.is_kit(kind): return Assembly.reason(request,query())
	if kind=="deck":
		for other in _rows:
			if Catalog.is_deck(str(other.kind)) and other.kind!="deck" and Catalog.footprint_rect(other).grow(-0.001).intersects(Catalog.tile_rect(int(request.x),int(request.z))): return "这里已有浮台"
		var x:=int(request.x)
		var z:=int(request.z)
		if Catalog.base_cell(x,z): return "这里是原有平台"
		if _deck_cells.has(Vector2i(x,z)): return "这里已有木板或正在施工"
		return ""
	var support: Dictionary=Catalog.fixed_support() if str(request.get("support",""))=="@base" else _by_id.get(str(request.get("support","")),{})
	if support.is_empty() or (str(support.id)!="@base" and not Catalog.is_deck(str(support.kind))) or support.left>0: return "请放在已完成的新木板上"
	var rect := Catalog.plot_rect(request)
	if not (Catalog.BASE if str(support.id)=="@base" else Catalog.footprint_rect(support)).intersects(rect): return "请选择脚下的支撑木板"
	if not Catalog.covered(rect.grow(Catalog.PLANTER_MARGIN),Catalog.support_tiles(_rows)): return "种植区超出了木板边缘"
	var excluded := str(request.get("exclude_id",""))
	for item in _rows:
		if item.id==excluded or Catalog.is_deck(str(item.kind)): continue
		if Catalog.elevation(item)>0.5: continue
		if Catalog.plot_rect(item).grow(0.02).intersects(rect): return "摆件不能重叠"
	return ""

func _record(request: Dictionary, id: String, seconds: float) -> Dictionary:
	# Only consume fields that geometry validated for this placement kind.
	# A furnishing request's unused x/z (or a deck's px/pz/support) must never
	# reach numeric conversions or turn into an unsaveable committed record.
	if Catalog.is_kit(str(request.kind)):
		return {"id":id,"kind":str(request.kind),"x":0,"z":0,"px":float(request.px),"pz":float(request.pz),"py":float(request.get("py",0)),"turn":int(request.get("turn",0)),"support":str(request.get("support","")),"left":seconds}
	if str(request.kind)=="deck":
		return {"id":id,"kind":"deck","x":int(request.x),"z":int(request.z),
			"px":0.0,"pz":0.0,"turn":0,"support":"","left":seconds}
	return {"id":id,"kind":str(request.kind),"x":0,"z":0,
		"px":float(request.px),"pz":float(request.pz),"turn":int(request.get("turn",0)),
		"support":str(request.support),"left":seconds}

func _proposed(request: Dictionary, operation: String, id: String) -> Array:
	var result: Array=[]
	for item in _rows:
		if item.id!=id: result.append(item.duplicate(true))
	if operation!="remove":
		result.append(_record(request,id,0.0 if operation=="move" else float(Catalog.RECIPES[request.kind].seconds)))
	return result

func _layout_reason(request: Dictionary, operation: String, id: String) -> String:
	var context: Dictionary=request.duplicate(true)
	context.operation=operation
	context.id=id
	var proposed:=_proposed(request,operation,id)
	if _layout_bytes(proposed,_next_id+1)>Catalog.MAX_LAYOUT_BYTES:
		return "建造布局已接近存档容量，请先回收不需要的物件"
	if _ports.has("capacity_reason") and _ports.capacity_reason.is_valid():
		var capacity_error: String=_ports.capacity_reason.call(proposed)
		if capacity_error!="": return capacity_error
	if not _ports.has("layout_reason") or not _ports.layout_reason.is_valid(): return ""
	return _ports.layout_reason.call(query(),proposed,context)

static func _layout_bytes(rows: Array, sequence: int) -> int:
	# Include the module nesting used by SaveGame's tab-indented serialization.
	return JSON.stringify({"building":{"version":1,"next_id":sequence,"instances":rows}},"\t").to_utf8_buffer().size()

func can_place(request: Dictionary) -> String:
	var reason := context_reason()
	if reason!="": return reason
	reason=geometry_reason(request)
	if reason!="": return reason
	reason=_ports.space_reason.call(request)
	if reason!="": return reason
	var excluded := str(request.get("exclude_id",""))
	if excluded!="": return _layout_reason(request,"move",excluded)
	return _layout_reason(request,"begin","built_%d"%_next_id)

## Cheap unselected frontier hint. The selected preview and every command must
## still use can_place/can_move, including capacity and full layout contracts.
func preview_reason(request: Dictionary, full_layout: bool=false) -> String:
	if full_layout: return can_place(request)
	var reason:=context_reason()
	if reason!="": return reason
	reason=geometry_reason(request)
	return reason if reason!="" else str(_ports.space_reason.call(request))

## Near an outer edge, snap back inside the whole wooden surface. The precision
## mode supplies its own position; exact old save coordinates are never rounded.
func snap_planter(request: Dictionary) -> Dictionary:
	if not Catalog.is_furnishing(str(request.get("kind",""))) or not request.has("px") or not request.has("pz"): return request.duplicate()
	for key in ["px","pz"]:
		var value: Variant=request[key]
		if not (value is float or value is int) or not is_finite(float(value)): return request.duplicate()
	var rotation: Variant=request.get("turn",0)
	if not (rotation is float or rotation is int) or not is_finite(float(rotation)) or rotation!=floor(rotation) or rotation<0 or rotation>3:
		return request.duplicate()
	if Catalog.covered(Catalog.plot_rect(request).grow(Catalog.PLANTER_MARGIN),_finished_tiles): return request.duplicate()
	var base:=Vector2(float(request.px),float(request.pz))
	var best: Dictionary={}
	var best_distance:=INF
	var raw_step: Variant=request.get("snap_step",0.1)
	var step: float=clampf(float(raw_step),0.01,0.1) if (raw_step is int or raw_step is float) and is_finite(float(raw_step)) else 0.1
	var steps:=int(floor(0.4/step))
	for i in range(-steps,steps+1):
		for j in range(-steps,steps+1):
			var candidate: Dictionary=request.duplicate()
			candidate.px=snappedf(base.x+float(i)*step,step)
			candidate.pz=snappedf(base.y+float(j)*step,step)
			var distance:=base.distance_squared_to(Vector2(candidate.px,candidate.pz))
			if distance>0.16001 or distance>=best_distance: continue
			if geometry_reason(candidate)!="": continue
			best_distance=distance;best=candidate
	return best if not best.is_empty() else request.duplicate()

func begin(request: Dictionary) -> Dictionary:
	if _committing: return {"ok":false,"reason":"正在提交建造"}
	if str(request.get("exclude_id",""))!="": return {"ok":false,"reason":"搬移请使用搬移命令"}
	if not Catalog.enabled(str(request.get("kind",""))): return {"ok":false,"reason":"该配方已停用"}
	var reason := can_place(request)
	if reason!="": return {"ok":false,"reason":reason}
	var recipe: Dictionary=Catalog.RECIPES[request.kind]
	_committing=true
	if not _ports.pay.call(recipe.cost.duplicate(true)):
		_committing=false
		return {"ok":false,"reason":"材料不足，请拾取浮木或到商店买土壤"}
	var item := _record(request,"built_%d"%_next_id,float(recipe.seconds))
	_next_id+=1
	_rows.append(item);_index(item)
	_committing=false
	changed.emit()
	return {"ok":true,"id":item.id}

func can_move(id: String, request: Dictionary) -> String:
	var item: Dictionary=_by_id.get(id,{})
	if item.is_empty(): return "摆件已经不存在"
	if item.left>0.0: return "施工完成后才能搬移"
	if not bool(Catalog.RECIPES[item.kind].get("movable",false)): return "木板请拆除后重新拼接"
	if str(request.get("kind",item.kind))!=item.kind: return "不能改变摆件种类"
	var candidate:=item.duplicate(true)
	candidate.merge(request,true)
	candidate.exclude_id=id
	return can_place(candidate)

func move(id: String, request: Dictionary) -> Dictionary:
	if _committing: return {"ok":false,"reason":"正在提交建造"}
	var reason:=can_move(id,request)
	if reason!="": return {"ok":false,"reason":reason}
	_committing=true
	var target: Dictionary=_by_id[id]
	var candidate:=target.duplicate(true)
	candidate.merge(request,true)
	var updated:=_record(candidate,id,0.0)
	target.clear();target.merge(updated)
	_reindex()
	_committing=false
	changed.emit()
	return {"ok":true,"id":id}

func can_remove(id: String) -> String:
	var reason:=context_reason()
	if reason!="": return reason
	var item: Dictionary=_by_id.get(id,{})
	if item.is_empty(): return "摆件已经不存在"
	if item.left>0.0: return "施工完成后才能回收"
	if not bool(Catalog.RECIPES[item.kind].get("removable",false)): return "这个物件不能回收"
	if Catalog.is_deck(str(item.kind)):
		var rect:=Catalog.footprint_rect(item)
		for other in _rows:
			if Catalog.is_deck(str(other.kind)): continue
			if other.support==id or Catalog.plot_rect(other).grow(Catalog.PLANTER_MARGIN).intersects(rect):
				return "先搬走木板上的摆件，再回收木板"
	var remaining: Array=[]
	for other in _rows:
		if other.id!=id: remaining.append(other)
	for other in remaining:
		if Catalog.is_kit(str(other.kind)) and Assembly.reason(other,remaining)!="": return "先拆除依附在此构件上的结构或摆件"
	var request: Dictionary=item.duplicate(true)
	request.operation="remove"
	return _layout_reason(request,"remove",id)

func remove(id: String) -> Dictionary:
	if _committing: return {"ok":false,"reason":"正在提交建造"}
	var reason:=can_remove(id)
	if reason!="": return {"ok":false,"reason":reason}
	if not _ports.has("refund") or not _ports.refund.is_valid(): return {"ok":false,"reason":"回收材料服务未就绪"}
	var item: Dictionary=_by_id[id]
	var cost: Dictionary=Catalog.RECIPES[item.kind].cost.duplicate(true)
	_committing=true
	if not _ports.refund.call(cost):
		_committing=false
		return {"ok":false,"reason":"背包空间不足，请先整理再回收"}
	_rows.erase(item);_reindex()
	_committing=false
	changed.emit()
	return {"ok":true,"id":id,"refund":cost}

func tick(delta: float) -> void:
	var done: Array[String]=[]
	for item in _rows:
		if item.left<=0: continue
		item.left=maxf(0,float(item.left)-maxf(0,delta))
		if item.left==0: done.append(item.id)
	if not done.is_empty():
		_reindex()
		changed.emit()
		for id in done: completed.emit(id)
func to_dict() -> Dictionary: return {"version":1,"next_id":_next_id,"instances":query()}
func from_dict(data: Dictionary) -> bool:
	if validate_snapshot(data)!="": return false
	_rows=data.instances.duplicate(true);_next_id=int(data.next_id)
	_reindex();changed.emit()
	return true
static func empty_snapshot() -> Dictionary: return {"version":1,"next_id":1,"instances":[]}

static func validate_snapshot(data: Dictionary) -> String:
	if data.get("version")!=1 or not data.get("instances") is Array: return "Invalid building snapshot"
	var sequence: Variant=data.get("next_id")
	if not (sequence is float or sequence is int) or not is_finite(float(sequence)) or sequence<1 or sequence!=floor(sequence):
		return "Invalid building sequence"
	if _layout_bytes(data.instances,int(sequence))>Catalog.MAX_LAYOUT_BYTES: return "Building layout exceeds save byte budget"
	var validator=load("res://src/building/building_service.gd").new()
	var ids: Dictionary={}
	var furnishings: Array=[]
	# Validate scalar contracts first. All supports are indexed before any
	# furnishing is checked: a moved box can use a deck built later than itself.
	for raw in data.instances:
		if not raw is Dictionary: return "Invalid building record"
		if raw.has("exclude_id") or raw.has("operation") or raw.has("snap_step"):
			return "Transient building command cannot be saved as layout"
		for key in ["id","kind","support"]:
			if not raw.get(key) is String: return "Missing building string: "+key
		for key in ["x","z","px","pz","turn","left"]:
			var value: Variant=raw.get(key)
			if not (value is float or value is int) or not is_finite(float(value)): return "Invalid building number: "+key
		for key in ["x","z","turn"]:
			if raw[key]!=floor(raw[key]): return "Fractional building grid"
		if raw.turn<0 or raw.turn>3 or raw.left<0: return "Invalid building rotation/timer"
		if not Catalog.RECIPES.has(raw.kind) or raw.left>Catalog.RECIPES[raw.kind].seconds: return "Invalid building recipe/timer"
		var suffix: String=raw.id.trim_prefix("built_")
		if not suffix.is_valid_int() or raw.id!="built_%d"%int(suffix) or int(suffix)<1 or int(suffix)>=sequence or ids.has(raw.id):
			return "Invalid building identity"
		ids[raw.id]=true
		if raw.kind=="deck" or (Catalog.is_kit(str(raw.kind)) and Catalog.is_deck(str(raw.kind))):
			if validator.geometry_reason(raw)!="" or raw.support!="": return "Invalid building deck or overlap"
			validator._rows.append(raw.duplicate(true))
			validator._index(validator._rows[-1])
		else: furnishings.append(raw)
	var pending: Array=furnishings.duplicate()
	while not pending.is_empty():
		var progressed:=false
		for raw in pending.duplicate():
			if validator.geometry_reason(raw)!="": continue
			validator._rows.append(raw.duplicate(true));validator._index(validator._rows[-1])
			pending.erase(raw);progressed=true
		if not progressed: return "Invalid building support or overlap"
	return ""
