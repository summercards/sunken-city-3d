extends Node3D
## Layout projection: render, walk surfaces, farm registration. Owns no saved state.
const Catalog = preload("res://src/building/building_catalog.gd")
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

func configure(model: RefCounted, ground: Node3D, farm_field: Node3D, bind: Callable, invalidate: Callable) -> void:
	service=model;area=ground;field=farm_field;bind_plot=bind;geometry_changed=invalidate
	_base_rects=area.rects.duplicate()
	service.changed.connect(sync)
	sync()
func node_for(id: String) -> Node3D: return _nodes.get(id)
func position_for(row: Dictionary) -> Vector3:
	var p: Vector2=Catalog.tile_rect(row.x,row.z).get_center() if row.kind=="deck" else Vector2(row.px,row.pz)
	return Catalog.ORIGIN+Vector3(p.x,0,p.y)
func sync() -> void:
	var rows: Array=service.query()
	var live := {}
	for item in rows: live[item.id]=true
	for id in _nodes.keys():
		if not live.has(id): _remove(id)
	for item in rows:
		var done: bool=item.left<=0
		if _nodes.has(item.id) and _completed[item.id]!=done: _remove(item.id)
		if _nodes.has(item.id): continue
		var node: Node3D
		if item.kind=="deck":
			node=Deck.instantiate();node.ghost=not done
		elif done:
			node=Plot.instantiate();node.plot_id="dynamic/"+item.id;node.zone_id="zone5";node.plot_name="培养土种植格"
			node.scale=Vector3(1.38,0.65,1.75);node.rotation.y=int(item.turn)*PI/2
			node.farm_model=field.farm_model
		else:
			node=ghost_planter()
			node.rotation.y=int(item.turn)*PI/2
		node.name=item.id;node.position=position_for(item)
		add_child(node);_nodes[item.id]=node;_completed[item.id]=done
		if item.kind=="planter" and done:
			field.register_node(node)
			node.set_meta("approach_points",approach_points(item))
			bind_plot.call(node)
	area.rects=walk_rects(rows)
	area.polygons.clear()
	geometry_changed.call()
func _remove(id: String) -> void:
	var node: Node3D=_nodes[id]
	if "plot_id" in node: field.unregister_node(node)
	remove_child(node);node.queue_free();_nodes.erase(id);_completed.erase(id)
func reset_projection() -> void:
	for id in _nodes.keys(): _remove(id)
func walk_rects(rows: Array) -> Array:
	var result: Array=_base_rects.duplicate()
	for item in rows:
		if item.kind!="deck" or item.left>0: continue
		var rect:=Catalog.tile_rect(item.x,item.z)
		var cut:=Rect2()
		for other in rows:
			if other.kind=="planter" and other.support==item.id: cut=Catalog.plot_rect(other).grow(0.06)
		if not cut.has_area(): result.append(rect);continue
		# Four non-overlapping strips avoid polygon holes being treated as walkable union.
		for strip in [Rect2(rect.position,Vector2(rect.size.x,cut.position.y-rect.position.y)),
			Rect2(Vector2(rect.position.x,cut.end.y),Vector2(rect.size.x,rect.end.y-cut.end.y)),
			Rect2(Vector2(rect.position.x,cut.position.y),Vector2(cut.position.x-rect.position.x,cut.size.y)),
			Rect2(Vector2(cut.end.x,cut.position.y),Vector2(rect.end.x-cut.end.x,cut.size.y))]:
			if strip.size.x>0.01 and strip.size.y>0.01: result.append(strip)
	return result
func approach_points(item: Dictionary) -> Array[Vector3]:
	var rect:=Catalog.plot_rect(item)
	var center:=rect.get_center()
	var result: Array[Vector3]=[]
	for p in [Vector2(center.x,rect.position.y-0.25),Vector2(center.x,rect.end.y+0.25),Vector2(rect.position.x-0.25,center.y),Vector2(rect.end.x+0.25,center.y)]:
		result.append(Catalog.ORIGIN+Vector3(p.x,0,p.y))
	return result
func water_shapes(saved: Variant = null) -> Array:
	var rows: Array=service.query() if saved==null else saved
	var result: Array=[]
	for item in rows:
		if item.kind!="deck": continue
		# Reserve water as soon as work starts, so a boat cannot enter during construction.
		var rect:=Catalog.tile_rect(item.x,item.z)
		var p:=rect.get_center()+Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
		result.append({"x":p.x,"z":p.y,"hx":rect.size.x/2,"hz":rect.size.y/2,"round":false})
	return result
func contact_rects() -> Array:
	var result: Array=[]
	for item in service.query():
		if item.kind!="deck" or item.left>0: continue
		var rect:=Catalog.tile_rect(item.x,item.z)
		var center:=rect.get_center()+Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
		result.append(Vector4(center.x,center.y,rect.size.x/2,rect.size.y/2))
	return result
func contains_saved(point: Vector3, rows: Array) -> bool:
	if absf(point.y-Catalog.ORIGIN.y)>0.5: return false
	var p:=Vector2(point.x-Catalog.ORIGIN.x,point.z-Catalog.ORIGIN.z)
	for rect in walk_rects(rows):
		if preload("res://src/navigation/ground_path.gd").contains([Catalog.polygon(rect)],p): return true
	return false
static func ghost_planter() -> Node3D:
	var node:=Node3D.new()
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(1.794,0.22,1.575)
	mesh.mesh=box;mesh.position.y=0.11
	var mat:=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority=10
	mat.albedo_color=Color(0.55,0.95,0.78,0.48);mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override=mat;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(mesh)
	return node
