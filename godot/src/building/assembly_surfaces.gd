extends RefCounted
## Shared candidate/live geometry for stairs, upper floors, save validation and blockers.
const Catalog=preload("res://src/building/building_catalog.gd")
const Rules=preload("res://src/building/assembly_rules.gd")
const Space=preload("res://src/building/building_space.gd")
static func blockers(row: Dictionary) -> Array:
	return Space.blocker_rects(row)
static func surface_rows(rows: Array) -> Array:
	return rows.filter(func(row): return float(row.left)<=0.0 and (Catalog.is_platform(str(row.kind)) or Rules.profile(row)=="stairs"))
static func height_at(point: Vector2,row: Dictionary) -> float:
	var local: Vector2=(point-Rules.center(row)).rotated(float(row.turn)*PI/2)
	var extent: Vector2=Catalog.RECIPES[row.kind].footprint
	if absf(local.x)>extent.x/2+.001 or absf(local.y)>extent.y/2+.001: return NAN
	return Catalog.elevation(row)+(extent.y/2-local.y)*Catalog.stair_rise(row)/extent.y if Rules.profile(row)=="stairs" else Catalog.elevation(row)

static func level_rects(rows: Array,height: float,radius: float=.22,base: Array=[]) -> Array:
	var tiles:=Catalog.platform_tiles_at_level(rows,height,false)
	if Catalog.same_level(height,0.0): tiles.append_array(base)
	var cuts: Array=[]
	# Erode only exposed edges; shared platform and stair seams stay open.
	var neighbours:=tiles.duplicate()
	for row in rows:
		if row.left>0 or Rules.profile(row)!="stairs": continue
		var edge: Array[Vector2]=[]
		if Catalog.same_level(Catalog.elevation(row),height): edge=Catalog.stairs_low_edge(row)
		elif Catalog.same_level(Catalog.elevation(row)+Catalog.stair_rise(row),height): edge=Catalog.stairs_top_edge(row)
		if not edge.is_empty():
			var middle: Vector2=(edge[0]+edge[1])/2
			var direction: Vector2=(Rules.center(row)-middle).normalized()*.001
			neighbours.append(Rect2(Vector2(minf(edge[0].x,edge[1].x),minf(edge[0].y,edge[1].y))+Vector2(minf(direction.x,0),minf(direction.y,0)),Vector2(absf(edge[0].x-edge[1].x),absf(edge[0].y-edge[1].y))+direction.abs()))
	if radius>0:
		for tile: Rect2 in tiles:
			for side in 4:
				var vertical:=side<2
				var edge: float=(tile.position.x if side==0 else tile.end.x) if vertical else (tile.position.y if side==2 else tile.end.y)
				var spans: Array=[Vector2(tile.position.y,tile.end.y) if vertical else Vector2(tile.position.x,tile.end.x)]
				for other: Rect2 in neighbours:
					if other==tile: continue
					var crosses: bool=(other.position.x<edge-Space.EPS and other.end.x>=edge-Space.EPS) if side==0 else ((other.end.x>edge+Space.EPS and other.position.x<=edge+Space.EPS) if side==1 else ((other.position.y<edge-Space.EPS and other.end.y>=edge-Space.EPS) if side==2 else (other.end.y>edge+Space.EPS and other.position.y<=edge+Space.EPS)))
					if not crosses: continue
					var lo: float=other.position.y if vertical else other.position.x
					var hi: float=other.end.y if vertical else other.end.x
					var next: Array=[]
					for span: Vector2 in spans:
						if lo>span.x: next.append(Vector2(span.x,minf(lo,span.y)))
						if hi<span.y: next.append(Vector2(maxf(hi,span.x),span.y))
					spans=next
				for span: Vector2 in spans:
					if span.y-span.x<=Space.EPS: continue
					cuts.append(Rect2(Vector2(edge if side==0 else edge-radius,span.x-radius),Vector2(radius,span.y-span.x+radius*2)) if vertical else Rect2(Vector2(span.x-radius,edge if side==2 else edge-radius),Vector2(span.y-span.x+radius*2,radius)))
	for row in rows:
		if not Catalog.same_level(Catalog.elevation(row),height): continue
		if Rules.profile(row)=="stairs" and row.left<=0: cuts.append(Catalog.footprint_rect(row));continue
		if not Catalog.is_furnishing(str(row.kind)) or not Catalog.blocks_actor(str(row.kind)): continue
		for cut: Rect2 in blockers(row): cuts.append(cut.grow(radius))
	return Space.cut_all(tiles,cuts)

static func records(rows: Array,radius: float=.22,base: Array=[]) -> Array:
	var result: Array=[]
	for height in Catalog.placement_levels(rows):
		for rect: Rect2 in level_rects(rows,height,radius,base): result.append({"rect":rect,"height":height,"slope":{}})
	for row in rows:
		if row.left>0 or Rules.profile(row)!="stairs": continue
		var extent: Vector2=Catalog.RECIPES[row.kind].footprint
		var left:=radius;var right:=radius
		for other in rows:
			if other.left>0 or str(other.id)==str(row.id) or not Catalog.stairs_parallel(row,other): continue
			var offset: Vector2=(Rules.center(other)-Rules.center(row)).rotated(float(row.turn)*PI/2)
			if offset.x<0: left=0.0
			else: right=0.0
		var local_center:=Vector2((left-right)/2,0).rotated(-float(row.turn)*PI/2)
		var size:=Vector2(extent.x-left-right,extent.y)
		if int(row.turn)%2==1: size=Vector2(size.y,size.x)
		var rect:=Rect2(Rules.center(row)+local_center-size/2,size)
		result.append({"rect":rect,"height":Catalog.elevation(row),"slope":row})
	return result

static func record_height(record: Dictionary,point: Vector2) -> float:
	return float(record.height) if record.slope.is_empty() else height_at(point,record.slope)

static func faces(rows: Array,radius: float=.22) -> PackedVector3Array:
	var result:=PackedVector3Array()
	var records_all:=records(rows,radius)
	# Share furniture cut vertices with neighbouring tiles to prevent T seams.
	var xs: Array=[];var zs: Array=[]
	for record in records_all:
		var raw: Rect2=record.rect
		var low: Vector2=raw.position.snapped(Vector2.ONE*.0001)
		var high: Vector2=raw.end.snapped(Vector2.ONE*.0001)
		record.rect=Rect2(low,high-low)
		for x in [record.rect.position.x,record.rect.end.x]:
			if not xs.has(x): xs.append(x)
		for z in [record.rect.position.y,record.rect.end.y]:
			if not zs.has(z): zs.append(z)
	xs.sort();zs.sort()
	for record in records_all:
		if record.slope.is_empty() and Catalog.same_level(record.height,0.0): continue
		var rect: Rect2=record.rect
		var cuts_x: Array=xs.filter(func(x): return x>=rect.position.x-.00001 and x<=rect.end.x+.00001)
		var cuts_z: Array=zs.filter(func(z): return z>=rect.position.y-.00001 and z<=rect.end.y+.00001)
		for x in cuts_x.size()-1:
			for z in cuts_z.size()-1:
				if cuts_x[x+1]-cuts_x[x]<.00009 or cuts_z[z+1]-cuts_z[z]<.00009: continue
				var corners:=Catalog.polygon(Rect2(Vector2(cuts_x[x],cuts_z[z]),Vector2(cuts_x[x+1]-cuts_x[x],cuts_z[z+1]-cuts_z[z])))
				for i in [0,2,1,0,3,2]:
					var at: Vector2=corners[i];result.append(Vector3(at.x,record_height(record,at),at.y))
	return result

static func contains(point: Vector3,rows: Array) -> bool:
	for record in records(rows):
		var at:=Vector2(point.x,point.z)
		if Space.contains(record.rect,at) and absf(point.y-record_height(record,at))<.35: return true
	return false

static func connected(a: Dictionary,b: Dictionary) -> bool:
	if not Space.touching(a.rect,b.rect): return false
	var low:=Vector2(maxf(a.rect.position.x,b.rect.position.x),maxf(a.rect.position.y,b.rect.position.y))
	var high:=Vector2(minf(a.rect.end.x,b.rect.end.x),minf(a.rect.end.y,b.rect.end.y))
	# 整条共享边都须同高，不能只因反向坡面在中点交叉就连通。
	for point: Vector2 in [low,(low+high)/2,high]:
		if absf(record_height(a,point)-record_height(b,point))>=.04: return false
	return true

static func groups(parts: Array) -> Array:
	var parent: Array=[]
	for i in parts.size(): parent.append(i)
	for i in parts.size():
		for j in i:
			if connected(parts[i],parts[j]): parent[Space._root(parent,i)]=Space._root(parent,j)
	for i in parent.size(): parent[i]=Space._root(parent,i)
	return parent

static func point_groups(parts: Array,components: Array,point: Vector3) -> Array:
	var result: Array=[];var at:=Vector2(point.x,point.z)
	for i in parts.size():
		if Space.contains(parts[i].rect,at) and absf(point.y-record_height(parts[i],at))<.35 and not result.has(components[i]): result.append(components[i])
	return result

static func _group_has_slope(parts: Array,groups: Array,group: int) -> bool:
	for i in parts.size():
		if int(groups[i])==group and not parts[i].slope.is_empty(): return true
	return false

static func _ground_groups(parts: Array,groups: Array) -> Array:
	var result: Array=[]
	for i in parts.size():
		if parts[i].slope.is_empty() and Catalog.same_level(float(parts[i].height),0.0) and not result.has(groups[i]): result.append(groups[i])
	return result
static func _has_ground_return(parts: Array,groups: Array,actor: Vector3) -> bool:
	var actor_groups:=point_groups(parts,groups,actor)
	var ground_groups:=_ground_groups(parts,groups)
	for group in actor_groups:
		if ground_groups.has(group): return true
	return false
static func safety_reason(before: Array,after: Array,actor: Vector3,ashore: bool,base: Array) -> String:
	var old_parts:=records(before,.22,base);var new_parts:=records(after,.22,base)
	var old_groups:=groups(old_parts);var new_groups:=groups(new_parts)
	var constraints: Dictionary={}
	# 固定平台也是返程锚点；不能只比较自建上层彼此仍然相连。
	for tile: Rect2 in base:
		var old_ids: Array=[];var new_ids: Array=[]
		for pair in [[old_parts,old_groups,old_ids],[new_parts,new_groups,new_ids]]:
			for i in pair[0].size():
				var record: Dictionary=pair[0][i]
				if not record.slope.is_empty() or not Catalog.same_level(record.height,0.0): continue
				var overlap: Rect2=record.rect.intersection(tile)
				if overlap.size.x>Space.EPS and overlap.size.y>Space.EPS and not pair[2].has(pair[1][i]): pair[2].append(pair[1][i])
		for group in old_ids:
			if not constraints.has(group): constraints[group]=new_ids.duplicate()
			else: constraints[group]=Space.intersect_ids(constraints[group],new_ids)
	for row in before:
		if row.left>0 or not Catalog.is_platform(str(row.kind)): continue
		if not after.any(func(other): return other.id==row.id): continue
		var old_ids: Array=[];var new_ids: Array=[]
		for pair in [[old_parts,old_groups,old_ids],[new_parts,new_groups,new_ids]]:
			for i in pair[0].size():
				var record: Dictionary=pair[0][i]
				if not record.slope.is_empty() or not Catalog.same_level(record.height,Catalog.elevation(row)): continue
				var overlap: Rect2=record.rect.intersection(Catalog.footprint_rect(row))
				if overlap.size.x>Space.EPS and overlap.size.y>Space.EPS and not pair[2].has(pair[1][i]): pair[2].append(pair[1][i])
		if not old_ids.is_empty() and new_ids.is_empty(): return "这里会占满平台通路，请留出可通过的走道"
		for group in old_ids:
			if not constraints.has(group): constraints[group]=new_ids.duplicate()
			else: constraints[group]=Space.intersect_ids(constraints[group],new_ids)
	if ashore:
		var old_actor:=point_groups(old_parts,old_groups,actor)
		var new_actor:=point_groups(new_parts,new_groups,actor)
		if not old_actor.is_empty() and new_actor.is_empty(): return "这里会移除角色的落脚点，请先换个站位"
		# 当前角色仍站在上层平台时，保留其矩形落脚点不够：还必须保留
		# 一条真实楼梯/斜面连接到任意完工0层平台。独立海台也是合法返程锚，
		# 不要求它与 Catalog.BASE 相交；因此这个检查不依赖固定底座夹具。
		if _has_ground_return(old_parts,old_groups,actor) and not _has_ground_return(new_parts,new_groups,actor): return "这里会切断返回楼梯或平台的通路"
		for group in old_actor:
			if constraints.has(group) and Space.intersect_ids(constraints[group],new_actor).is_empty(): return "这里会切断返回楼梯或平台的通路"
	for result in constraints.values():
		if result.is_empty(): return "这里会切断楼层通路，请保留通向楼梯和平台的走道"
	return ""
