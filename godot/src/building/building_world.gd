extends Node3D
## Layout projection: render, walk surfaces, farm registration. Owns no saved state.
const Catalog = preload("res://src/building/building_catalog.gd")
const Space = preload("res://src/building/building_space.gd")
const Deck = preload("res://scenes/buildables/wood_deck.tscn")
const Plot = preload("res://scenes/props/farm_cell.tscn")
var service: RefCounted
var area: Node3D
var field: Node3D
var bind_plot: Callable
var geometry_changed: Callable
var _base_rects: Array=[]
var _nodes := {}
var _completed := {}
var _fixed_footprints: Array=[]
var revision := 0
var prop_action: Callable
var _assembly_walk: Node3D

func configure(model: RefCounted, ground: Node3D, farm_field: Node3D, bind: Callable, invalidate: Callable) -> void:
	service=model;area=ground;field=farm_field;bind_plot=bind;geometry_changed=invalidate
	# These rectangles describe valid actor CENTERS, with body clearance already
	# applied to the union and its obstacles. A WalkArea-level inset would erode
	# each thin strip/seam a second time and make compact gardens unreachable.
	if "body_radius" in area: area.body_radius=0.0
	_base_rects=area.rects.duplicate()
	_fixed_footprints.clear()
	# Fixed planting beds are pass-through by default. Only explicitly solid
	# component metadata reserves a footprint; crops never supply collision.
	for plot in field.plots:
		if str(plot.zone_id)!="zone5" or str(plot.plot_id).begins_with("dynamic/"): continue
		if not bool(plot.get_meta("blocks_actor",false)): continue
		_fixed_footprints.append(_fixed_plot_rect(plot))
	service.changed.connect(sync)
	sync()
func _fixed_plot_rect(plot: Node3D) -> Rect2:
	var center: Vector3=plot.global_position-Catalog.ORIGIN
	var extent:=Vector2(1.30*absf(plot.global_basis.get_scale().x),0.90*absf(plot.global_basis.get_scale().z))
	if absf(sin(plot.global_rotation.y))>0.5: extent=Vector2(extent.y,extent.x)
	return Rect2(Vector2(center.x,center.z)-extent/2,extent)
func fixed_occupied_rects() -> Array:
	var result: Array=[]
	for plot: Node3D in field.plots:
		if str(plot.zone_id)=="zone5" and not str(plot.plot_id).begins_with("dynamic/"): result.append(_fixed_plot_rect(plot))
	return result
func node_for(id: String) -> Node3D: return _nodes.get(id)
func position_for(row: Dictionary) -> Vector3:
	var p: Vector2=Catalog.tile_rect(row.x,row.z).get_center() if row.kind=="deck" else Vector2(row.px,row.pz)
	return Catalog.ORIGIN+Vector3(p.x,Catalog.elevation(row),p.y)
func sync() -> void:
	revision+=1
	var rows: Array=service.query()
	var live := {}
	for item in rows: live[item.id]=true
	for id in _nodes.keys():
		if not live.has(id): _remove(id)
	for item in rows:
		var done: bool=item.left<=0
		if _nodes.has(item.id) and _completed[item.id]!=done: _remove(item.id)
		if _nodes.has(item.id):
			# Moving a furnishing changes only its pose. Unregistering/recreating
			# a FarmPlot here would erase its crop, water and growth state.
			var existing: Node3D=_nodes[item.id]
			existing.position=position_for(item)
			existing.rotation.y=int(item.turn)*PI/2
			continue
		var node: Node3D
		if item.kind=="deck":
			node=Deck.instantiate();node.ghost=not done
		elif Catalog.is_kit(str(item.kind)):
			node=load(Catalog.RECIPES[item.kind].prefab).instantiate()
			node.ghost=not done;node.instance_id=str(item.id)
			node.rotation.y=int(item.turn)*PI/2
			if prop_action.is_valid(): node.action_requested.connect(func(action): prop_action.call(action))
		elif done and Catalog.role(str(item.kind))=="planter":
			node=Plot.instantiate();node.plot_id="dynamic/"+item.id;node.zone_id="zone5";node.plot_name="培养土种植格"
			var footprint: Vector2=Catalog.RECIPES[item.kind].footprint
			node.scale=Vector3(footprint.x/1.30,0.65,footprint.y/0.90);node.rotation.y=int(item.turn)*PI/2
			node.farm_model=field.farm_model
		else:
			node=ghost_planter(str(item.kind))
			node.rotation.y=int(item.turn)*PI/2
		node.name=item.id;node.position=position_for(item)
		add_child(node);_nodes[item.id]=node;_completed[item.id]=done
		node.set_meta("building_instance_id",str(item.id))
		if Catalog.role(str(item.kind))=="planter" and done:
			field.register_node(node)
			bind_plot.call(node)
	area.rects=walk_rects(rows)
	area.polygons.clear()
	_sync_assembly(rows)
	# Every placement can change another plot's usable operation side. Refresh
	# all anchors after projecting the complete candidate walking surface.
	for item in rows:
		if Catalog.is_furnishing(str(item.kind)) and float(item.left)<=0.0 and _nodes.has(item.id):
			_nodes[item.id].set_meta("approach_points",approach_points(item))
	for plot: Node3D in field.plots:
		if str(plot.zone_id)!="zone5" or str(plot.plot_id).begins_with("dynamic/"): continue
		plot.set_meta("approach_points",_world_operation_points(_fixed_plot_rect(plot),bool(plot.get_meta("blocks_actor",false))))
	geometry_changed.call()
func _sync_assembly(rows: Array) -> void:
	var zone: Node3D=area.get_parent().get_parent()
	if _assembly_walk==null:
		_assembly_walk=preload("res://src/navigation/walk_area.gd").new()
		_assembly_walk.name="AssemblyWalk";_assembly_walk.area_id="zone5_assembly";_assembly_walk.zone_id="zone5"
		_assembly_walk.body_radius=0.0;_assembly_walk.surface_y=Catalog.ORIGIN.y+2.8
		area.get_parent().add_child(_assembly_walk);_assembly_walk.global_position=Catalog.ORIGIN
		zone.walk_areas.append(_assembly_walk)
		zone.ground_space.configure(zone.walk_areas)
	_assembly_walk.surface_triangles=preload("res://src/building/assembly_surfaces.gd").faces(rows)
	area.open_surface_junctions.clear()
	for row in rows:
		if row.left<=0 and Catalog.RECIPES[row.kind].get("profile","")=="stairs":
			var rect:=Catalog.footprint_rect(row);rect.position+=Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
			area.open_surface_junctions.append(rect)

func _remove(id: String) -> void:
	var node: Node3D=_nodes[id]
	if "plot_id" in node: field.unregister_node(node)
	remove_child(node);node.queue_free();_nodes.erase(id);_completed.erase(id)
func reset_projection() -> void:
	for id in _nodes.keys(): _remove(id)
func walk_rects(rows: Array) -> Array:
	return Space.walk_rects(_base_rects,rows,_fixed_footprints)
## Splits `a` around `b`, producing non-overlapping strips that avoid polygon holes.
static func _subtract(a: Rect2, b: Rect2) -> Array:
	return Space.subtract(a,b)
func approach_points(item: Dictionary) -> Array[Vector3]:
	if Catalog.elevation(item)>.5 and _assembly_walk!=null:
		var result: Array[Vector3]=[]
		var at:=position_for(item)
		for offset: Vector3 in [Vector3(0,0,.7),Vector3(0,0,-.7),Vector3(.7,0,0),Vector3(-.7,0,0)]:
			var point: Vector3=_assembly_walk.surface_point(at+offset)
			if point.is_finite() and absf(point.y-at.y)<.3: result.append(point)
		return result
	return _world_operation_points(Catalog.plot_rect(item),Catalog.blocks_actor(str(item.kind)))
func _world_operation_points(rect: Rect2, blocks_actor: bool) -> Array[Vector3]:
	var walk: Array=area.rects
	var result: Array[Vector3]=[]
	for at: Vector2 in Space.operation_points_for(rect,walk,blocks_actor):
		result.append(Catalog.ORIGIN+Vector3(at.x,0,at.y))
	return result
## Free placement can push the four probes off the deck edge; pull each one back
## onto the nearest walkable strip so a built planter stays usable.
static func _nearest_walk(rects: Array, p: Vector2) -> Vector2:
	return Space.nearest(rects,p)

func closest_walk_point(point: Vector3, max_distance: float=INF) -> Vector3:
	var local:=Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)
	var nearest:=Space.nearest(area.rects,local,max_distance)
	return Vector3.INF if nearest==Vector2.INF else Catalog.ORIGIN+Vector3(nearest.x,0,nearest.y)

func find_stand_point(actor: Vector3, center: Vector3, max_distance: float=2.8, request: Dictionary={}) -> Vector3:
	if actor.y>Catalog.ORIGIN.y+0.5 and _assembly_walk!=null:
		for offset: Vector3 in [Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
			var candidate: Vector3=_assembly_walk.surface_point(center+offset)
			if candidate.is_finite() and not _assembly_walk.path_between(actor,candidate).is_empty(): return candidate
	var walk: Array=area.rects
	var groups:=Space.components(walk)
	var local:=Vector2(actor.x-Catalog.ORIGIN.x,actor.z-Catalog.ORIGIN.z)
	var target:=Vector2(center.x-Catalog.ORIGIN.x,center.z-Catalog.ORIGIN.z)
	var actor_groups:=Space.point_components(walk,groups,local)
	if actor_groups.is_empty(): return Vector3.INF
	var best:=Vector2.INF
	var score:=INF
	var future_box:=Rect2(target-Catalog.PLOT_EXTENT/2,Catalog.PLOT_EXTENT).grow(Space.RADIUS)
	if not request.is_empty() and Catalog.is_furnishing(str(request.get("kind",""))): future_box=Catalog.plot_rect(request).grow(Space.RADIUS)
	var probes: Array[Vector2]=[target]
	var direction:=local-target
	if direction.length_squared()<0.001: direction=Vector2.UP
	direction=direction.normalized()
	for radius in [1.0,1.25,1.5,1.9,2.4]:
		probes.append(target+direction*radius)
		for d: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]: probes.append(target+d*radius)
	for i in walk.size():
		if not actor_groups.has(groups[i]): continue
		for probe in probes:
			var point:=Space.nearest([walk[i]],probe,max_distance)
			if point==Vector2.INF: continue
			var distance:=point.distance_to(target)
			if distance<0.95 or distance>max_distance: continue
			if future_box.has_point(point): continue
			var rank:=local.distance_to(point)+distance*0.15
			if rank<score: best=point;score=rank
	if best==Vector2.INF: return Vector3.INF
	return Catalog.ORIGIN+Vector3(best.x,0,best.y)
func water_shapes(saved: Variant = null) -> Array:
	var rows: Array=service.query() if saved==null else saved
	var result: Array=[]
	for item in rows:
		if not Catalog.is_deck(str(item.kind)): continue
		# Reserve water as soon as work starts, so a boat cannot enter during construction.
		var rect:=Catalog.footprint_rect(item)
		var p:=rect.get_center()+Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
		result.append({"x":p.x,"z":p.y,"hx":rect.size.x/2,"hz":rect.size.y/2,"round":false})
	return result
func contact_rects() -> Array:
	var result: Array=[]
	for item in service.query():
		if not Catalog.is_deck(str(item.kind)) or item.left>0: continue
		var rect:=Catalog.footprint_rect(item)
		var center:=rect.get_center()+Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
		result.append(Vector4(center.x,center.y,rect.size.x/2,rect.size.y/2))
	return result
func contains_saved(point: Vector3, rows: Array) -> bool:
	if preload("res://src/building/assembly_surfaces.gd").contains(point-Catalog.ORIGIN,rows): return true
	if absf(point.y-Catalog.ORIGIN.y)>0.5: return false
	var p:=Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)
	# Old saves may contain positions in former narrow paths. They remain valid
	# candidate data; the restore adapter may pull the actor to current safe ground.
	var legacy: Array=_base_rects.duplicate()
	legacy.append_array(Catalog.deck_tiles(rows))
	var cuts: Array=[]
	for row in rows:
		if Catalog.is_furnishing(str(row.kind)) and Catalog.blocks_actor(str(row.kind)) and Catalog.elevation(row)<0.5:
			cuts.append(Catalog.plot_rect(row).grow(0.05))
	for rect in Space.cut_all(legacy,cuts):
		if preload("res://src/navigation/ground_path.gd").contains([Catalog.polygon(rect)],p): return true
	return false
static func ghost_planter(kind: String="planter") -> Node3D:
	var node:=Node3D.new()
	var footprint: Vector2=Catalog.RECIPES.get(kind,Catalog.RECIPES.planter).footprint
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(footprint.x,0.22,footprint.y)
	mesh.mesh=box;mesh.position.y=0.11
	var mat:=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority=10
	mat.albedo_color=Color(0.55,0.95,0.78,0.48);mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override=mat;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(mesh)
	return node
