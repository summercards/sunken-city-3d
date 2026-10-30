extends RefCounted
## Pure geometry shared by placement, walking, approach and removal validation.
## Axis-aligned support cells are eroded only at exposed edges, never at seams.
const Catalog = preload("res://src/building/building_catalog.gd")
const RADIUS := 0.22
const EPS := 0.0005

static func subtract(a: Rect2, b: Rect2) -> Array:
	if not a.intersects(b): return [a]
	var top := maxf(a.position.y,b.position.y)
	var bottom := minf(a.end.y,b.end.y)
	var result: Array=[]
	if top-a.position.y>EPS: result.append(Rect2(a.position,Vector2(a.size.x,top-a.position.y)))
	if a.end.y-bottom>EPS: result.append(Rect2(Vector2(a.position.x,bottom),Vector2(a.size.x,a.end.y-bottom)))
	if bottom-top>EPS:
		if b.position.x-a.position.x>EPS: result.append(Rect2(Vector2(a.position.x,top),Vector2(b.position.x-a.position.x,bottom-top)))
		if a.end.x-b.end.x>EPS: result.append(Rect2(Vector2(b.end.x,top),Vector2(a.end.x-b.end.x,bottom-top)))
	return result

static func cut_all(rects: Array, cuts: Array) -> Array:
	var result: Array=[]
	for rect: Rect2 in rects:
		var pieces: Array=[rect]
		for cut: Rect2 in cuts:
			if not rect.intersects(cut): continue
			var next: Array=[]
			for piece: Rect2 in pieces: next.append_array(subtract(piece,cut))
			pieces=next
			if pieces.is_empty(): break
		result.append_array(pieces)
	return result

static func support_cells(rows: Array) -> Dictionary:
	var cells: Dictionary={}
	for x in 3:
		for z in 2: cells[Vector2i(x,z)]=true
	for row in rows:
		if Catalog.is_deck(str(row.kind)) and float(row.left)<=0.0: cells[Vector2i(int(row.x),int(row.z))]=true
	return cells

static func exterior_cuts(rows: Array, radius: float) -> Array:
	var tiles: Array=Catalog.deck_tiles(rows)
	for x in 3:
		for z in 2: tiles.append(Catalog.tile_rect(x,z))
	var cuts: Array=[]
	if radius<=0: return cuts
	for tile: Rect2 in Catalog.deck_tiles(rows):
		for side in 4:
			var vertical:=side<2
			var edge: float=(tile.position.x if side==0 else tile.end.x) if vertical else (tile.position.y if side==2 else tile.end.y)
			var spans: Array=[Vector2(tile.position.y-radius,tile.end.y+radius) if vertical else Vector2(tile.position.x-radius,tile.end.x+radius)]
			for other: Rect2 in tiles:
				if other==tile: continue
				var crosses: bool=(other.position.x<edge-EPS and other.end.x>=edge-EPS) if side==0 else ((other.end.x>edge+EPS and other.position.x<=edge+EPS) if side==1 else ((other.position.y<edge-EPS and other.end.y>=edge-EPS) if side==2 else (other.end.y>edge+EPS and other.position.y<=edge+EPS)))
				if not crosses: continue
				var lo: float=other.position.y if vertical else other.position.x
				var hi: float=other.end.y if vertical else other.end.x
				var next: Array=[]
				for span: Vector2 in spans:
					if lo>span.x: next.append(Vector2(span.x,minf(lo,span.y)))
					if hi<span.y: next.append(Vector2(maxf(hi,span.x),span.y))
				spans=next
			for span: Vector2 in spans:
				if span.y-span.x<=EPS: continue
				cuts.append(Rect2(Vector2(edge if side==0 else edge-radius,span.x),Vector2(radius,span.y-span.x)) if vertical else Rect2(Vector2(span.x,edge if side==2 else edge-radius),Vector2(span.y-span.x,radius)))
	return cuts

static func walk_rects(base: Array, rows: Array, fixed: Array=[], radius: float=RADIUS) -> Array:
	var support: Array=Catalog.deck_tiles(rows)
	# Authored base walk data stays stable. Dynamic support erodes only exposed
	# edges, preserving the entire shared seam of neighbouring boards.
	var dynamic: Array=cut_all(support,exterior_cuts(rows,radius))
	var result: Array=base.duplicate()
	result.append_array(dynamic)
	var cuts: Array=[]
	for rect: Rect2 in fixed: cuts.append(rect.grow(radius))
	for row in rows:
		if Catalog.is_furnishing(str(row.kind)) and Catalog.blocks_actor(str(row.kind)) and Catalog.elevation(row)<0.5:
			for blocker: Rect2 in preload("res://src/building/assembly_surfaces.gd").blockers(row): cuts.append(blocker.grow(radius))
		if row.left<=0 and Catalog.RECIPES[row.kind].get("profile","")=="stairs": cuts.append(Catalog.plot_rect(row))
	return cut_all(result,cuts)

static func contains(rect: Rect2, p: Vector2) -> bool:
	return p.x>=rect.position.x-EPS and p.x<=rect.end.x+EPS and p.y>=rect.position.y-EPS and p.y<=rect.end.y+EPS

static func nearest(rects: Array, point: Vector2, max_distance: float=INF) -> Vector2:
	var result := Vector2.INF
	var best := max_distance*max_distance
	for rect: Rect2 in rects:
		var inner := rect.grow(-0.002)
		if not inner.has_area(): inner=rect
		var p := Vector2(clampf(point.x,inner.position.x,inner.end.x),clampf(point.y,inner.position.y,inner.end.y))
		var distance := p.distance_squared_to(point)
		if distance<=best: result=p;best=distance
	return result

static func touching(a: Rect2, b: Rect2) -> bool:
	var x := minf(a.end.x,b.end.x)-maxf(a.position.x,b.position.x)
	var z := minf(a.end.y,b.end.y)-maxf(a.position.y,b.position.y)
	return (x>EPS and z>=-EPS) or (z>EPS and x>=-EPS)

static func _root(parent: Array, index: int) -> int:
	var at := index
	while parent[at]!=at: at=int(parent[at])
	while parent[index]!=index:
		var next := int(parent[index]);parent[index]=at;index=next
	return at

## Sparse buckets avoid allocating the ocean between distant islands.
static func components(rects: Array) -> Array:
	var parent: Array=[]
	var buckets: Dictionary={}
	const CELL := 3.0
	for i in rects.size(): parent.append(i)
	for i in rects.size():
		var rect: Rect2=rects[i]
		var visited: Dictionary={}
		for x in range(int(floor((rect.position.x-EPS)/CELL)),int(floor((rect.end.x+EPS)/CELL))+1):
			for z in range(int(floor((rect.position.y-EPS)/CELL)),int(floor((rect.end.y+EPS)/CELL))+1):
				var key := Vector2i(x,z)
				for other in buckets.get(key,[]):
					if visited.has(other): continue
					visited[other]=true
					if touching(rect,rects[other]): parent[_root(parent,i)]=_root(parent,int(other))
				if not buckets.has(key): buckets[key]=[]
				buckets[key].append(i)
	for i in parent.size(): parent[i]=_root(parent,i)
	return parent

static func point_components(rects: Array, groups: Array, p: Vector2) -> Array:
	var found: Array=[]
	for i in rects.size():
		if contains(rects[i],p) and not found.has(groups[i]): found.append(groups[i])
	return found

static func rect_components(rects: Array, groups: Array, target: Rect2) -> Array:
	var found: Array=[]
	for i in rects.size():
		var overlap: Rect2=rects[i].intersection(target)
		if overlap.size.x>EPS and overlap.size.y>EPS and not found.has(groups[i]): found.append(groups[i])
	return found

static func operation_points(row: Dictionary, walk: Array) -> Array[Vector2]:
	return operation_points_for(Catalog.plot_rect(row),walk,Catalog.blocks_actor(str(row.kind)))

## Authored initial beds share the same interaction geometry as built planters.
static func operation_points_for(rect: Rect2, walk: Array, blocks_actor: bool=true) -> Array[Vector2]:
	var center := rect.get_center()
	var result: Array[Vector2]=[]
	# A pass-through planter is a valid place to stand, not a hole in the deck.
	# Keep side anchors as alternatives, especially for edge-mounted plantings.
	if not blocks_actor:
		var on_soil := nearest(walk,center,0.05)
		if on_soil != Vector2.INF: result.append(on_soil)
	var offset := RADIUS+0.035
	for p: Vector2 in [Vector2(center.x,rect.position.y-offset),Vector2(center.x,rect.end.y+offset),Vector2(rect.position.x-offset,center.y),Vector2(rect.end.x+offset,center.y)]:
		var point := nearest(walk,p,0.35)
		if point==Vector2.INF: continue
		if point.distance_to(center)>maxf(rect.size.x,rect.size.y)*0.5+0.8: continue
		if not result.has(point): result.append(point)
	return result

static func intersect_ids(a: Array, b: Array) -> Array:
	var result: Array=[]
	for id in a:
		if b.has(id): result.append(id)
	return result

## Preserve preexisting connections, allowing legacy unsafe layouts to load
## and be repaired rather than making an unrelated existing flaw a new veto.
static func connection_reason(before_rows: Array, after_rows: Array, before: Array, after: Array) -> String:
	var before_groups := components(before)
	var after_groups := components(after)
	var old_groups: Dictionary={}
	var targets: Dictionary={"@base":Catalog.BASE}
	var removed: Dictionary={}
	for row in before_rows:
		if Catalog.is_deck(str(row.kind)) and float(row.left)<=0.0:
			targets[row.id]=Catalog.footprint_rect(row);removed[row.id]=true
	for row in after_rows:
		if Catalog.is_deck(str(row.kind)): removed.erase(row.id)
	for id in targets:
		if removed.has(id): continue
		var old_components := rect_components(before,before_groups,targets[id])
		var new_components := rect_components(after,after_groups,targets[id])
		if not old_components.is_empty() and new_components.is_empty(): return "这里会占满通路，请留出角色能通过的走道"
		for component in old_components:
			if not old_groups.has(component): old_groups[component]=new_components.duplicate()
			else: old_groups[component]=intersect_ids(old_groups[component],new_components)
	for group in old_groups.values():
		if group.is_empty(): return "这里会切断平台通路，请保留相连的走道"
	return ""
