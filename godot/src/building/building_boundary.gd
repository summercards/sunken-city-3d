extends RefCounted
## Runtime policy. World geometry and gameplay state arrive through queries.
const Catalog = preload("res://src/building/building_catalog.gd")
const Space = preload("res://src/building/building_space.gd")
var actor_query: Callable
var boat_query: Callable
var obstacles_query: Callable
var protected_query: Callable
var farm_query: Callable
var active_landing_query: Callable
var world: Node3D
var _cache_revision := -1
var _layout_cache: Dictionary={}
func eligibility() -> String:
	if not actor_query.is_valid(): return "建造未就绪"
	var context: Dictionary=actor_query.call()
	if str(context.get("state",""))=="sleeping" or int(context.get("mode",0))==3: return "现在不能施工"
	if int(context.get("mode",0))==0 and str(context.get("zone",""))!="zone5": return "请到海面平台或乘船施工"
	return ""
func space_reason(request: Dictionary) -> String:
	if Catalog.is_furnishing(str(request.kind)):
		if world!=null and Catalog.elevation(request)<0.5:
			for occupied: Rect2 in world.fixed_occupied_rects():
				if occupied.grow(-.01).intersects(Catalog.plot_rect(request)): return "这里已有原来的种植区，请选择旁边空木面"
		var context: Dictionary=actor_query.call()
		if int(context.get("mode",0))==0:
			var actor: Vector3=context.position
			if absf(actor.y-Catalog.ORIGIN.y-Catalog.elevation(request))<0.5 and Catalog.plot_rect(request).grow(Space.RADIUS).has_point(Vector2(actor.x-Catalog.ORIGIN.x,actor.z-Catalog.ORIGIN.z)):
				return "请先让出摆件的位置"
		return ""
	var rect:=Catalog.footprint_rect(request)
	rect.position+=Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
	if boat_query.is_valid():
		var boat: Vector3=boat_query.call()
		if rect.grow(0.9).has_point(Vector2(boat.x,boat.z)): return "请让船离开施工范围"
	if protected_query.is_valid():
		for protected: Rect2 in protected_query.call():
			if rect.intersects(protected): return "请保留泊位和上下船通道"
	if obstacles_query.is_valid():
		for obstacle in obstacles_query.call():
			if obstacle is Rect2:
				if rect.grow(-0.01).intersects(obstacle): return "这里有既有建筑，无法建造"
			elif obstacle is Dictionary:
				if _shape_intersects(rect,obstacle): return "这里有既有建筑，无法建造"
	return ""

static func _shape_intersects(rect: Rect2, shape: Dictionary) -> bool:
	var center:=Vector2(float(shape.get("x",0)),float(shape.get("z",0)))
	var hx:=float(shape.get("hx",0))
	if bool(shape.get("round",false)):
		var nearest:=Vector2(clampf(center.x,rect.position.x,rect.end.x),clampf(center.y,rect.position.y,rect.end.y))
		return nearest.distance_squared_to(center)<hx*hx
	var hz:=float(shape.get("hz",hx))
	return rect.grow(-0.01).intersects(Rect2(center-Vector2(hx,hz),Vector2(hx,hz)*2))

func layout_reason(before: Array, after: Array, request: Dictionary) -> String:
	if world==null: return "建造场地未就绪"
	if int(world.revision)!=_cache_revision:
		_cache_revision=int(world.revision);_layout_cache.clear()
	var context: Dictionary=actor_query.call()
	var at: Vector3=context.position
	var key:=str(request)+"/"+str(context.get("mode",0))+"/"+str(at.snapped(Vector3.ONE*0.05))
	if active_landing_query.is_valid(): key+="/"+str(active_landing_query.call())
	# Crop status is deliberately included: harvesting may change the remove
	# answer without any layout revision.
	if str(request.get("operation",""))=="remove" and farm_query.is_valid(): key+="/"+str(farm_query.call("dynamic/"+str(request.get("id",""))))
	if _layout_cache.has(key): return str(_layout_cache[key])
	var result:=_layout_reason_now(before,after,request,context)
	if _layout_cache.size()>128: _layout_cache.clear()
	_layout_cache[key]=result
	return result

func _layout_reason_now(before: Array, after: Array, request: Dictionary, context: Dictionary) -> String:
	var operation:=str(request.get("operation","begin"))
	var id:=str(request.get("id",""))
	if operation=="remove" and Catalog.is_furnishing(str(request.kind)) and farm_query.is_valid():
		var state: Variant=farm_query.call("dynamic/"+id)
		if state is Dictionary and str(state.get("crop",""))!="": return "先收获作物，再回收种植区"
	var at: Vector3=context.position
	var local:=Vector2(at.x-Catalog.ORIGIN.x,at.z-Catalog.ORIGIN.z)
	if operation=="remove" and Catalog.is_deck(str(request.kind)) and int(context.get("mode",0))==0:
		if Catalog.footprint_rect(request).grow(Space.RADIUS).has_point(local): return "请先离开这块木板，再回收"
		if active_landing_query.is_valid():
			var landing_id:=str(active_landing_query.call())
			if landing_id.begins_with("built:"+id+":"): return "这块木板是当前上下船位置，请先上船或换个泊位"
	if operation=="begin" and Catalog.is_deck(str(request.kind)): return ""
	if Catalog.is_kit(str(request.kind)):
		if operation=="remove" and preload("res://src/building/assembly_surfaces.gd").contains(at-Catalog.ORIGIN,[request]): return "请先离开楼梯或二层楼板"
		if operation=="remove" and Catalog.RECIPES[request.kind].get("profile","")=="stairs" and at.y>Catalog.ORIGIN.y+.5 and int(context.get("mode",0))==0: return "请先下楼，再回收楼梯"
		var old_ground: Array=world.walk_rects(before)
		var new_ground: Array=world.walk_rects(after)
		if Catalog.RECIPES[request.kind].get("profile","")!="stairs":
			var disconnected:=Space.connection_reason(before,after,old_ground,new_ground)
			if disconnected!="": return disconnected
		if int(context.get("mode",0))==0 and absf(at.y-Catalog.ORIGIN.y)<.5 and Space.nearest(old_ground,local,.01)!=Vector2.INF and Space.nearest(new_ground,local,.01)==Vector2.INF: return "这里会挡住角色，请先换个站位"
		return ""
	var old_walk: Array=world.walk_rects(before)
	var new_walk: Array=world.walk_rects(after)
	var reason:=Space.connection_reason(before,after,old_walk,new_walk)
	if reason!="": return reason
	if int(context.get("mode",0))==0:
		var was_safe:=Space.nearest(old_walk,local,0.01)!=Vector2.INF
		if was_safe and Space.nearest(new_walk,local,0.01)==Vector2.INF: return "这里会挡住角色，请先换个站位"
	var groups:=Space.components(new_walk)
	for row in after:
		if not Catalog.is_furnishing(str(row.kind)): continue
		var is_affected: bool=str(row.id)==id
		var old_row: Dictionary={}
		for previous in before:
			if previous.id==row.id: old_row=previous;break
		if not is_affected and (old_row.is_empty() or Space.operation_points(old_row,old_walk).is_empty()): continue
		var points:=Space.operation_points(row,new_walk)
		if points.is_empty(): return "种植区旁需要留出可站立的操作位置"
		if is_affected and int(context.get("mode",0))==0:
			var actor_groups:=Space.point_components(new_walk,groups,local)
			var reachable:=false
			for point in points:
				if not Space.intersect_ids(actor_groups,Space.point_components(new_walk,groups,point)).is_empty(): reachable=true;break
			if not reachable: return "这里走不到，请保留通向种植区的走道"
	return ""
