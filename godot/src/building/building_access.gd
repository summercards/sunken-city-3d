extends Node
## Boat construction and derived edge landings. Layout and actor state stay with
## their owners; every query is injected by the composition root.
const Catalog = preload("res://src/building/building_catalog.gd")
const Landing = preload("res://src/navigation/landing_point.gd")
const DIRECTIONS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
var service: RefCounted
var world: Node3D
var navigation: RefCounted
var boat: Node3D
var markers: CanvasLayer
var actor_query: Callable
var select_landing: Callable
var current_id: Callable
var camera: Camera3D
var _nodes: Dictionary={}
var _refresh_left:=0.0

func configure(model: RefCounted,projection: Node3D,nav: RefCounted,vessel: Node3D,icons: CanvasLayer,view: Camera3D,actor: Callable,selected: Callable,landing_id: Callable) -> void:
	service=model;world=projection;navigation=nav;boat=vessel;markers=icons;camera=view
	actor_query=actor;select_landing=selected;current_id=landing_id
	service.changed.connect(invalidate)

func invalidate() -> void:
	_refresh_left=0.0
	for node in _nodes.values():
		if is_instance_valid(node): node.queue_free()
	_nodes.clear()

func _process(delta: float) -> void:
	_refresh_left-=delta
	if _refresh_left>0.0 or markers==null: return
	_refresh_left=0.75
	refresh_markers()

static func is_dynamic(id: String) -> bool: return id.begins_with("built:")

func landing_data(id: String, rows: Variant = null, walk_override: Variant = null) -> Dictionary:
	if not is_dynamic(id): return {}
	var parts:=id.split(":")
	if parts.size()!=3 or not parts[2].is_valid_int(): return {}
	var side:=int(parts[2])
	if side<0 or side>=DIRECTIONS.size(): return {}
	var records: Array=service.query() if rows==null else rows
	var item: Dictionary={}
	var occupied: Dictionary={}
	for row in records:
		if row.kind!="deck": continue
		occupied[Vector2i(int(row.x),int(row.z))]=true
		if row.id==parts[1] and float(row.left)<=0.0: item=row
	if item.is_empty(): return {}
	var direction: Vector2i=DIRECTIONS[side]
	var neighbor:=Vector2i(int(item.x),int(item.z))+direction
	if occupied.has(neighbor) or Catalog.base_cell(neighbor.x,neighbor.y): return {}
	var rect: Rect2=Catalog.tile_rect(item.x,item.z)
	var center:=rect.get_center()
	var normal:=Vector2(direction)
	var half: float=rect.size.x*0.5 if side<2 else rect.size.y*0.5
	var edge:=center+normal*half
	var stand:=Vector2.INF
	var tangent:=Vector2(-normal.y,normal.x)
	# Live marker refresh can ask for dozens of edges. Its walking projection
	# is already available; only candidate-save/mutation validation recomputes.
	var walk: Array=world.walk_rects(records) if walk_override==null else walk_override
	# A side may be usable near either corner even when a planter occupies its
	# middle. Probe actual safe standing strips, never invent a floating anchor.
	for offset in [0.0,-0.4,0.4,-0.7,0.7]:
		for inset in [0.4,0.24,0.6,0.85]:
			var point: Vector2=edge+tangent*float(offset)-normal*float(inset)
			for piece: Rect2 in walk:
				if piece.has_point(point): stand=point;break
			if stand!=Vector2.INF: break
		if stand!=Vector2.INF: break
	if stand==Vector2.INF: return {}
	edge+=tangent*((stand-edge).dot(tangent))
	var park:=edge+normal*1.65
	var origin:=Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
	stand+=origin;park+=origin;edge+=origin
	return {"id":id,"name":"自建平台","ground_id":world.area.area_id,
		"landStand":[stand.x,Catalog.ORIGIN.y,stand.y],"boatPark":[park.x,1.12,park.y],
		"boatYaw":atan2(tangent.x,tangent.y),"dockEdge":[edge.x,Catalog.ORIGIN.y,edge.y]}

func landing_node(id: String) -> Node3D:
	if _nodes.has(id) and is_instance_valid(_nodes[id]): return _nodes[id]
	var data:=landing_data(id,null,world.area.rects)
	if data.is_empty(): return null
	var node:=Marker3D.new()
	node.set_script(Landing)
	node.landing_id=id;node.landing_label="自建平台"
	world.area.add_child(node)
	node.global_position=Vector3(data.landStand[0],data.landStand[1],data.landStand[2])
	var park:=Marker3D.new();park.name="BoatPark";node.add_child(park)
	park.global_position=Vector3(data.boatPark[0],data.boatPark[1],data.boatPark[2]);park.global_rotation.y=data.boatYaw
	var edge:=Marker3D.new();edge.name="DockEdge";node.add_child(edge)
	edge.global_position=Vector3(data.dockEdge[0],data.dockEdge[1],data.dockEdge[2])
	_nodes[id]=node
	return node

func refresh_markers() -> void:
	for i in range(markers.items.size()-1,-1,-1):
		if markers.items[i].get("dynamic_build",false): markers.items.remove_at(i)
	var candidates: Array=[]
	var rows: Array=service.query()
	var live_walk: Array=world.area.rects
	var near_decks: Array=[]
	for row in rows:
		if row.kind!="deck" or float(row.left)>0: continue
		var center: Vector3=world.position_for(row)
		row=row.duplicate();row.distance=Vector2(center.x-boat.position.x,center.z-boat.position.z).length_squared()
		near_decks.append(row)
	near_decks.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance)
	for index in mini(near_decks.size(),24):
		var row: Dictionary=near_decks[index]
		for side in 4:
			var id: String="built:%s:%d"%[row.id,side]
			var data:=landing_data(id,rows,live_walk)
			if data.is_empty(): continue
			var park:=Vector2(data.boatPark[0],data.boatPark[2])
			if not navigation.is_open_water(park.x,park.y): continue
			data.distance=park.distance_squared_to(Vector2(boat.position.x,boat.position.z))
			candidates.append(data)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance)
	var chosen: Array=[]
	var active: String=str(current_id.call())
	for data in candidates:
		if chosen.size()>=8 and data.id!=active: continue
		var p:=Vector3(data.dockEdge[0],data.dockEdge[1]+0.55,data.dockEdge[2])
		# Avoid placing several anchor icons on top of each other.
		var near:=false
		for prior: Vector3 in chosen:
			if prior.distance_to(p)<4.0: near=true;break
		if near and data.id!=active: continue
		chosen.append(p)
		markers.items.append({"zone":"zone5","landing":data.id,"name":"自建平台","world":p,
			"draw_world":p,"screen":Vector2.ZERO,"size":30.0,"near":0.0,"visible":false,"dynamic_build":true})

func pick_landing(screen: Vector2) -> Dictionary:
	var origin:=camera.project_ray_origin(screen)
	var dir:=camera.project_ray_normal(screen)
	if absf(dir.y)<0.00001: return {}
	var t: float=(Catalog.ORIGIN.y-origin.y)/dir.y
	if t<=0.0: return {}
	var point:=origin+dir*t
	var local:=Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)
	var rows: Array=service.query()
	var live_walk: Array=world.area.rects
	for row in rows:
		if row.kind!="deck" or row.left>0 or not Catalog.tile_rect(row.x,row.z).has_point(local): continue
		var choices: Array=[]
		for side in 4:
			var data:=landing_data("built:%s:%d"%[row.id,side],rows,live_walk)
			if data.is_empty(): continue
			var park:=Vector2(data.boatPark[0],data.boatPark[2])
			if navigation.is_open_water(park.x,park.y):
				data.distance=park.distance_squared_to(Vector2(boat.position.x,boat.position.z));choices.append(data)
		choices.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance)
		for data in choices:
			if not navigation.plan_route_to(Vector2(boat.position.x,boat.position.z),data.boatPark[0],data.boatPark[2]).is_empty():
				return {"zone":"zone5","landing":data.id}
	return {}

func boat_stand(center: Vector3) -> Vector3:
	var candidates: Array=[]
	var from:=Vector2(boat.position.x,boat.position.z)
	for side in 8:
		var normal:=Vector2.from_angle(float(side)*TAU/8.0)
		var point:=Vector2(center.x,center.z)+normal*3.1
		if not navigation.is_open_water(point.x,point.y): continue
		candidates.append({"point":point,"distance":point.distance_squared_to(from)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance)
	for candidate in candidates:
		var at: Vector2=candidate.point
		if not navigation.plan_route_to(from,at.x,at.y).is_empty(): return Vector3(at.x,1.12,at.y)
	return Vector3.INF
