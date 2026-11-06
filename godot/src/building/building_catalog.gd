extends RefCounted
## Recipe and geometry constants; no mutable gameplay state.
const ORIGIN := Vector3(22, 1.48, 16)
const TILE := Vector2(2.15, 2.575)
const BASE := Rect2(-3.225, -2.575, 6.45, 5.15)
## Footprint of one planter. Free placement only needs the whole footprint on deck.
const PLOT_EXTENT := Vector2(1.794,1.575)
## Distance a planter must stay inside the deck outline. Small on purpose:
## the deck is the boundary, not one tile, so crossing a seam is legal.
const PLANTER_MARGIN := 0.04
## Storage protection, not a plot-count or map-size progression rule. Reserve
## the other half of the 8 MiB save envelope for crops and the other owners.
const MAX_LAYOUT_BYTES := 4 * 1024 * 1024
## Two content classes only. Platforms carry bodies and join each other
## edge-to-edge; frames stand on a platform and need a real support socket.
## Decorations are the frames' loose furniture and follow the same support rule.
const CATEGORY_PLATFORM := "platform"
const CATEGORY_STRUCTURE := "structure"
const CATEGORY_DECORATION := "decoration"
## A seam a body must be able to cross. Wider than the 0.44 m actor, so a
## rounded corner or a 0.2 m post beside it never closes the join.
const JOIN_MIN := 0.6
const LAYER_HEIGHT := 5.086335
const LEGACY_LAYER_HEIGHT := 2.8
const STAIR_SNAP_DISTANCE := 0.35
const SEAM_EPS := 0.0005
const LEVEL_EPS := 0.002
## Placement and rendering both consume these roles. Adding a new furnishing
## means adding a recipe and its projection, not another layout state owner.
const LEGACY_RECIPES := {
	"deck":{"name":"拼接木板", "cost":{"wood":6}, "seconds":3.0,
		"description":"接出平台，或乘船在空旷海面开始新平台。", "category":CATEGORY_PLATFORM,
		"placement":"ocean_grid", "support":"water", "footprint":TILE, "visual":"deck",
		"role":"deck", "rotatable":true, "movable":false, "removable":true},
	"planter":{"name":"培养土种植区", "cost":{"wood":3,"soil":2}, "seconds":4.0,
		"description":"在整片木面自由摆放，可搬移、旋转与回收。", "category":CATEGORY_DECORATION,
		"placement":"deck_surface", "support":"finished_deck", "footprint":PLOT_EXTENT,
		"visual":"planter", "role":"planter", "blocks_actor":false, "rotatable":true, "movable":true, "removable":true},
	"planter_small":{"name":"小型培养土", "cost":{"wood":2,"soil":1}, "seconds":3.0,
		"description":"占地更小，适合单板花园和窄平台。", "category":CATEGORY_DECORATION,
		"placement":"deck_surface", "support":"finished_deck", "footprint":Vector2(0.9,1.0),
		"visual":"planter", "role":"planter", "blocks_actor":false, "rotatable":true, "movable":true, "removable":true}
}
static var RECIPES: Dictionary = _load_recipes()
## Content baseline taken at load time. `RECIPES` is a shared mutable Dictionary
## (GDScript has no read-only container), so anything holding a reference could
## rewrite costs or footprints for every consumer at once: the card price, the
## amount charged, and the world projection all read the same object. The
## signature covers the definition fields only; `active` is a runtime switch and
## is deliberately excluded so pinning content off does not read as corruption.
static var _baseline: Dictionary = _signature(RECIPES)
static func _signature(recipes: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for kind: String in recipes:
		var entry: Dictionary=(recipes[kind] as Dictionary).duplicate(true)
		# Placement and support are derived at load time, so they stay in the
		# signature: a wrong derivation is exactly the drift worth catching.
		entry.erase("active")
		result[kind]=JSON.stringify(_canonical(entry))
	return result
## Integer and float spellings of the same number are the same content. Without
## this, re-entering a cost as 2 after reading 2.0 would report phantom drift.
static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var mapped: Dictionary={}
		for key in value: mapped[key]=_canonical(value[key])
		return mapped
	if value is Array:
		var listed: Array=[]
		for item in value: listed.append(_canonical(item))
		return listed
	if value is int: return float(value)
	return value
## Returns "" while the catalog still matches the file it was loaded from, or a
## human-readable list of what changed. Gateways call this so a stray write to
## the shared table fails loudly instead of silently repricing the game.
static func verify_content() -> String:
	var now: Dictionary=_signature(RECIPES)
	var drift: Array[String]=[]
	for kind: String in _baseline:
		if not now.has(kind): drift.append(kind+" 被移除"); continue
		if str(now[kind])!=str(_baseline[kind]): drift.append(kind+" 定义被改写")
	for kind: String in now:
		if not _baseline.has(kind): drift.append(kind+" 被新增")
	if drift.is_empty(): return ""
	return "建造目录与源文件不一致："+", ".join(drift)
static func _load_recipes() -> Dictionary:
	var result: Dictionary=LEGACY_RECIPES.duplicate(true)
	result.planter.height=0.35;result.planter_small.height=0.35
	# 旧结构仅退出菜单，兼容 API begin(旧 ID) 与旧存档仍保留原定义。
	result.deck.menu_visible=false
	for path in ["res://assets/data/building_kit.json","res://assets/data/building_kit_5m.json"]:
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(data is Dictionary and data.get("schema")==1,"建造目录格式错误")
		for raw: Dictionary in data.modules:
			assert(not result.has(raw.id),"建造配方 ID 重复")
			var definition: Dictionary=raw.duplicate(true)
			definition.footprint=Vector2(raw.footprint[0],raw.footprint[1])
			definition.kit=true;definition.visual="kit"
			definition.menu_visible=path.ends_with("building_kit_5m.json") or str(raw.category)=="decoration"
			if raw.profile in ["foundation","floor"]:
				definition.category=CATEGORY_PLATFORM
				definition.role="deck"
				definition.support="water"
				definition.placement="platform_edge"
			elif str(raw.category)=="decoration":
				definition.category=CATEGORY_DECORATION
				definition.support="finished_deck"
			else:
				definition.category=CATEGORY_STRUCTURE
				definition.support="finished_deck"
			definition.group=raw.category
			definition.rotatable=true
			result[raw.id]=definition
	return result
static func is_kit(kind: String) -> bool: return bool(RECIPES.get(kind,{}).get("kit",false))
static func is_platform(kind: String) -> bool:
	return RECIPES.has(kind) and str(RECIPES[kind].get("category",""))==CATEGORY_PLATFORM and role(kind)=="deck"
## Kept as the historical name: every platform is a walkable deck surface.
static func is_deck(kind: String) -> bool: return is_platform(kind)
static func is_frame(kind: String) -> bool:
	return RECIPES.has(kind) and str(RECIPES[kind].get("category",""))==CATEGORY_STRUCTURE
static func category(kind: String) -> String:
	return str(RECIPES.get(kind,{}).get("category",""))
static func enabled(kind: String) -> bool:
	return RECIPES.has(kind) and bool(RECIPES[kind].get("active",true)) and bool(RECIPES[kind].get("menu_visible",true))
static func api_enabled(kind: String) -> bool:
	return RECIPES.has(kind) and bool(RECIPES[kind].get("active",true))
static func position_rect(row: Dictionary) -> Rect2: return footprint_rect(row)
static func elevation(row: Dictionary) -> float: return float(row.get("py",0.0))
static func same_level(a: float,b: float) -> bool: return absf(a-b)<=LEVEL_EPS
static func valid_level(height: float) -> bool:
	# 高度的几何范围与实际承载分离；混合楼梯可以派生非整层高度。
	return is_finite(height) and height>=-LEVEL_EPS and height<=100000.0
static func stair_rise(row: Dictionary) -> float:
	var definition: Dictionary=RECIPES.get(str(row.get("kind","")),{})
	return float(definition.get("height",LEGACY_LAYER_HEIGHT))
static func component_height(row: Dictionary) -> float:
	return stair_rise(row) if str(RECIPES.get(str(row.get("kind","")),{}).get("profile",""))=="stairs" else float(RECIPES.get(str(row.get("kind","")),{}).get("height",0.3))
static func is_furnishing(kind: String) -> bool:
	# Anything mounted on a finished platform: frames and loose furniture.
	return RECIPES.has(kind) and not is_platform(kind)
static func role(kind: String) -> String:
	return str(RECIPES.get(kind,{}).get("role",""))
static func blocks_actor(kind: String) -> bool:
	return bool(RECIPES.get(kind,{}).get("blocks_actor",true))
static func tile_rect(x: int, z: int) -> Rect2:
	return Rect2(BASE.position + Vector2(x,z)*TILE,TILE)
static func base_cell(x: int, z: int) -> bool: return x>=0 and x<3 and z>=0 and z<2
static func allowed_cell(x: int, z: int) -> bool:
	# There is no construction envelope. Buildings, docks and live boats are
	# checked by the injected world policy, rather than banning an entire side.
	return not base_cell(x,z)
static func plot_rect(row: Dictionary) -> Rect2:
	var kind := str(row.get("kind","planter"))
	var extent: Vector2 = RECIPES.get(kind,RECIPES.planter).get("footprint",PLOT_EXTENT)
	if int(row.get("turn",0))%2==1: extent=Vector2(extent.y,extent.x)
	return Rect2(Vector2(row.px,row.pz)-extent/2,extent)
static func footprint_rect(row: Dictionary) -> Rect2:
	return tile_rect(int(row.x),int(row.z)) if grid_deck(row) else plot_rect(row)
## Historical boards keep their exact integer grid. Edge-joined boards carry
## an explicit position, so extending an old off-grid raft never moves the raft.
static func grid_deck(row: Dictionary) -> bool:
	return str(row.get("kind",""))=="deck" and not bool(row.get("positioned",false)) and same_level(elevation(row),0.0)
static func cell_at(point: Vector2) -> Vector2i:
	var cell := (point-BASE.position)/TILE
	return Vector2i(int(floor(cell.x)),int(floor(cell.y)))
static func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
## Footprint of every finished deck, as one continuous wooden surface.
static func deck_tiles(rows: Array) -> Array:
	return platform_tiles_at_level(rows,0.0,false)
static func support_tiles(rows: Array) -> Array:
	return platform_tiles_at_level(rows,0.0)
static func platform_rows_at_level(rows: Array,height: float,finished_only: bool=true) -> Array:
	var result: Array=[]
	for item in rows:
		if is_platform(str(item.kind)) and same_level(elevation(item),height) and (not finished_only or float(item.left)<=0.0): result.append(item)
	return result
static func platform_tiles_at_level(rows: Array,height: float,include_base: bool=true,finished_only: bool=true) -> Array:
	var result: Array=[]
	for item in platform_rows_at_level(rows,height,finished_only): result.append(footprint_rect(item))
	if include_base and same_level(height,0.0): result.append(BASE)
	return result
static func placement_levels(rows: Array) -> Array[float]:
	var result: Array[float]=[0.0]
	for item in rows:
		if float(item.left)>0.0: continue
		var height:=elevation(item)
		if str(RECIPES[item.kind].get("profile",""))=="stairs": height+=stair_rise(item)
		elif not is_platform(str(item.kind)): continue
		var exists:=false
		for known in result:
			if same_level(known,height): exists=true;break
		if not exists: result.append(height)
	result.sort()
	return result
static func stairs_top_edge(row: Dictionary) -> Array[Vector2]:
	var extent: Vector2=RECIPES[row.kind].footprint
	var at:=footprint_rect(row).get_center()
	var angle: float=-float(row.get("turn",0))*PI/2
	return [at+Vector2(-extent.x/2,-extent.y/2).rotated(angle),at+Vector2(extent.x/2,-extent.y/2).rotated(angle)]
static func stairs_top_contact(rect: Rect2,row: Dictionary) -> float:
	if str(RECIPES[row.kind].get("profile",""))!="stairs" or float(row.left)>0.0: return 0.0
	var edge:=stairs_top_edge(row)
	var middle: Vector2=(edge[0]+edge[1])/2
	var outward:=Vector2(0,-1).rotated(-float(row.get("turn",0))*PI/2)
	if (rect.get_center()-middle).dot(outward)<=0.0: return 0.0
	if absf(edge[0].x-edge[1].x)<0.01:
		if minf(absf(rect.position.x-middle.x),absf(rect.end.x-middle.x))>SEAM_EPS: return 0.0
		return maxf(0.0,minf(rect.end.y,maxf(edge[0].y,edge[1].y))-maxf(rect.position.y,minf(edge[0].y,edge[1].y)))
	if minf(absf(rect.position.y-middle.y),absf(rect.end.y-middle.y))>SEAM_EPS: return 0.0
	return maxf(0.0,minf(rect.end.x,maxf(edge[0].x,edge[1].x))-maxf(rect.position.x,minf(edge[0].x,edge[1].x)))
static func stairs_low_edge(row: Dictionary) -> Array[Vector2]:
	var extent: Vector2=RECIPES[row.kind].footprint
	var at:=footprint_rect(row).get_center()
	var angle: float=-float(row.get("turn",0))*PI/2
	return [at+Vector2(-extent.x/2,extent.y/2).rotated(angle),at+Vector2(extent.x/2,extent.y/2).rotated(angle)]
static func stairs_parallel(a: Dictionary,b: Dictionary) -> bool:
	if str(RECIPES[a.kind].get("profile",""))!="stairs" or str(RECIPES[b.kind].get("profile",""))!="stairs": return false
	if int(a.get("turn",0))!=int(b.get("turn",0)) or not same_level(elevation(a),elevation(b)) or not same_level(stair_rise(a),stair_rise(b)): return false
	var ea: Vector2=RECIPES[a.kind].footprint
	var eb: Vector2=RECIPES[b.kind].footprint
	var offset: Vector2=(footprint_rect(b).get_center()-footprint_rect(a).get_center()).rotated(float(a.get("turn",0))*PI/2)
	return absf(ea.y-eb.y)<=SEAM_EPS and absf(offset.y)<=SEAM_EPS and absf(absf(offset.x)-(ea.x+eb.x)/2)<=SEAM_EPS
static func stair_support_ids(row: Dictionary,rows: Array) -> Array[String]:
	var ids: Array[String]=[]
	var spans: Array[Vector2]=[]
	var edge:=stairs_low_edge(row)
	var vertical:=absf(edge[0].x-edge[1].x)<SEAM_EPS
	var low: float=minf(edge[0].y,edge[1].y) if vertical else minf(edge[0].x,edge[1].x)
	var high: float=maxf(edge[0].y,edge[1].y) if vertical else maxf(edge[0].x,edge[1].x)
	var fixed: float=edge[0].x if vertical else edge[0].y
	var own:=str(row.get("exclude_id",row.get("id","")))
	var candidates:=rows.duplicate()
	if same_level(elevation(row),0.0): candidates.append(fixed_support())
	for other in candidates:
		if str(other.id)==own or float(other.left)>0.0: continue
		var lo:=low;var hi:=high
		if str(other.id)=="@base" or (is_platform(str(other.kind)) and same_level(elevation(other),elevation(row))):
			var rect: Rect2=BASE if str(other.id)=="@base" else footprint_rect(other)
			if fixed<(rect.position.x if vertical else rect.position.y)-SEAM_EPS or fixed>(rect.end.x if vertical else rect.end.y)+SEAM_EPS: continue
			lo=maxf(lo,rect.position.y if vertical else rect.position.x)
			hi=minf(hi,rect.end.y if vertical else rect.end.x)
		elif str(RECIPES.get(str(other.kind),{}).get("profile",""))=="stairs" and same_level(elevation(other)+stair_rise(other),elevation(row)):
			var top:=stairs_top_edge(other)
			if (absf(top[0].x-top[1].x)<SEAM_EPS)!=vertical: continue
			if absf((top[0].x if vertical else top[0].y)-fixed)>SEAM_EPS: continue
			var outward:=Vector2(0,-1).rotated(-float(other.get("turn",0))*PI/2)
			if (footprint_rect(row).get_center()-(top[0]+top[1])/2).dot(outward)<=SEAM_EPS: continue
			lo=maxf(lo,minf(top[0].y,top[1].y) if vertical else minf(top[0].x,top[1].x))
			hi=minf(hi,maxf(top[0].y,top[1].y) if vertical else maxf(top[0].x,top[1].x))
		else: continue
		if hi-lo>SEAM_EPS: spans.append(Vector2(lo,hi));ids.append(str(other.id))
	spans.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x<b.x)
	var length:=0.0;var start: float=-INF;var reach: float=-INF
	for span in spans:
		if span.x>reach+SEAM_EPS: start=span.x
		reach=maxf(reach,span.y);length=maxf(length,reach-start)
	ids.sort()
	if length>=JOIN_MIN-SEAM_EPS: return ids
	ids.clear()
	return ids
static func snap_stairs(request: Dictionary,rows: Array,edge_assist: bool=true) -> Dictionary:
	var result:=request.duplicate(true)
	var rules=load("res://src/building/assembly_rules.gd")
	var supports: Array=rules.support_ids(result,rows)
	result.support="" if supports.is_empty() else supports[0]
	if not edge_assist: return result
	var cursor:=Vector2(float(request.px),float(request.pz))
	var extent:=platform_extent(str(request.kind),int(request.get("turn",0)))
	var guides: Array=[]
	for other in rows:
		if float(other.left)>0.0: continue
		if is_platform(str(other.kind)) and same_level(elevation(other),elevation(request)): guides.append({"rect":footprint_rect(other),"stair":{}})
		elif str(RECIPES[other.kind].get("profile",""))=="stairs":
			if same_level(elevation(other),elevation(request)) or same_level(elevation(other)+stair_rise(other),elevation(request)): guides.append({"rect":footprint_rect(other),"stair":other})
	if same_level(elevation(request),0.0): guides.append({"rect":BASE,"stair":{}})
	guides.sort_custom(func(a,b): return not a.stair.is_empty() and b.stair.is_empty())
	var best_distance:=STAIR_SNAP_DISTANCE*STAIR_SNAP_DISTANCE
	var stair_match:=false
	for entry in guides:
		if stair_match and entry.stair.is_empty(): continue
		var guide: Rect2=entry.rect
		if not entry.stair.is_empty() and (stairs_parallel(result,entry.stair) or supports.has(str(entry.stair.id))) and rules.reason(result,rows)=="": return result
		var xs: Array=[cursor.x,guide.position.x-extent.x/2,guide.end.x+extent.x/2,guide.position.x+extent.x/2,guide.end.x-extent.x/2,guide.get_center().x]
		var zs: Array=[cursor.y,guide.position.y-extent.y/2,guide.end.y+extent.y/2,guide.position.y+extent.y/2,guide.end.y-extent.y/2,guide.get_center().y]
		for x: float in xs:
			for z: float in zs:
				var distance:=cursor.distance_squared_to(Vector2(x,z))
				if distance<0.000000001 or distance>=best_distance: continue
				var candidate:=request.duplicate(true);candidate.px=x;candidate.pz=z
				var ids: Array=rules.support_ids(candidate,rows)
				if ids.is_empty(): continue
				candidate.support=ids[0]
				if not entry.stair.is_empty() and not stairs_parallel(candidate,entry.stair) and not ids.has(str(entry.stair.id)): continue
				if rules.reason(candidate,rows)!="": continue
				best_distance=distance;result=candidate
				if not entry.stair.is_empty(): stair_match=true
	return result
static func fixed_support() -> Dictionary:
	return {"id":"@base","kind":"fixed_base","left":0.0}

## Footprint of a platform after rotation. Turn swaps the two edge lengths.
static func platform_extent(kind: String, turn: int) -> Vector2:
	var extent: Vector2=RECIPES.get(kind,RECIPES.deck).get("footprint",TILE)
	return Vector2(extent.y,extent.x) if int(turn)%2==1 else extent
static func rect_distance(rect: Rect2, point: Vector2) -> float:
	var dx:=maxf(maxf(rect.position.x-point.x,point.x-rect.end.x),0.0)
	var dz:=maxf(maxf(rect.position.y-point.y,point.y-rect.end.y),0.0)
	return Vector2(dx,dz).length()
## Length of the edge two rectangles share. A corner touch is not a seam.
static func contact_length(a: Rect2, b: Rect2) -> float:
	var x:=minf(a.end.x,b.end.x)-maxf(a.position.x,b.position.x)
	var z:=minf(a.end.y,b.end.y)-maxf(a.position.y,b.position.y)
	if absf(z)<=0.02 and x>0.02: return x
	if absf(x)<=0.02 and z>0.02: return z
	return 0.0
## Longest seam with the finished platform union, the fixed base included.
static func platform_contact(rect: Rect2, rows: Array,height: float=0.0,include_stairs: bool=true) -> float:
	var result:=contact_against(rect,platform_tiles_at_level(rows,height))
	if include_stairs:
		for row in rows:
			if str(RECIPES[row.kind].get("profile",""))=="stairs" and same_level(elevation(row)+stair_rise(row),height): result=maxf(result,stairs_top_contact(rect,row))
	return result
## Same measurement against an already materialised tile list. Support tiles are
## rebuilt on every call, so the snap solver passes its own list instead of
## rebuilding the union once per candidate.
static func contact_against(rect: Rect2, surfaces: Array) -> float:
	var best:=0.0
	for tile: Rect2 in surfaces:
		best=maxf(best,contact_length(rect,tile))
	return best

## Spatial index over the finished platform union. Snapping used to re-scan the
## whole union for every candidate, which is why preview cost grew with the cube
## of the platform count (45 boards: 163 ms per cursor move). The index is built
## once per snap and makes neighbour lookups local.
##
## Edge lists are kept split by role on purpose: `starts` holds rectangle
## minimums and `ends` holds maximums, because a flush neighbour is found by
## `start + extent/2` or `end - extent/2` — mixing the two would quietly add
## solutions the original solver never produced.
const INDEX_CELL := 4.0
static func build_index(surfaces: Array) -> Dictionary:
	var starts_x: Dictionary={};var ends_x: Dictionary={}
	var starts_z: Dictionary={};var ends_z: Dictionary={}
	var buckets: Dictionary={}
	for tile: Rect2 in surfaces:
		starts_x[tile.position.x]=true;ends_x[tile.end.x]=true
		starts_z[tile.position.y]=true;ends_z[tile.end.y]=true
		for bx in range(int(floor(tile.position.x/INDEX_CELL)),int(floor(tile.end.x/INDEX_CELL))+1):
			for bz in range(int(floor(tile.position.y/INDEX_CELL)),int(floor(tile.end.y/INDEX_CELL))+1):
				var key:=Vector2i(bx,bz)
				if not buckets.has(key): buckets[key]=[]
				buckets[key].append(tile)
	var index: Dictionary={"tiles":surfaces,"buckets":buckets}
	for pair in [["starts_x",starts_x],["ends_x",ends_x],["starts_z",starts_z],["ends_z",ends_z]]:
		var sorted: Array=pair[1].keys()
		sorted.sort()
		index[pair[0]]=sorted
	return index
## Tiles that could possibly touch `rect`, from the buckets it covers. Used for
## overlap and seam tests so a candidate only inspects its own neighbourhood.
static func neighbours(index: Dictionary, rect: Rect2) -> Array:
	var buckets: Dictionary=index.buckets
	var seen: Dictionary={}
	var out: Array=[]
	for bx in range(int(floor(rect.position.x/INDEX_CELL)),int(floor(rect.end.x/INDEX_CELL))+1):
		for bz in range(int(floor(rect.position.y/INDEX_CELL)),int(floor(rect.end.y/INDEX_CELL))+1):
			for tile: Rect2 in buckets.get(Vector2i(bx,bz),[]):
				if seen.has(tile): continue
				seen[tile]=true;out.append(tile)
	return out
static func overlaps_any(rect: Rect2, surfaces: Array) -> bool:
	for tile: Rect2 in surfaces:
		var overlap: Rect2=rect.grow(-0.002).intersection(tile)
		if overlap.size.x>0.001 and overlap.size.y>0.001: return true
	return false
static func snap_deck(point: Vector2, rows: Array, free_water: bool=false,height: float=0.0,snap_step: float=0.1,edge_assist: bool=true,turn: int=0) -> Dictionary:
	if not same_level(height,0.0) or not edge_assist or turn!=0: return snap_foundation("deck",point,turn,rows,free_water,height,snap_step,edge_assist)
	var cell:=cell_at(point)
	var grid: Dictionary={"kind":"deck","x":cell.x,"z":cell.y,"px":0.0,"pz":0.0,"turn":0,"support":""}
	var surfaces:=support_tiles(rows)
	var rect:=footprint_rect(grid)
	# Keep the original cursor/grid behaviour wherever it can actually join.
	if not overlaps_any(rect,surfaces) and (free_water or contact_against(rect,surfaces)>=JOIN_MIN): return grid
	var near:=INF
	for tile: Rect2 in surfaces: near=minf(near,rect_distance(tile,point))
	# A distant shore click keeps its red ocean-grid preview instead of moving
	# the cursor's target all the way back to the nearest island.
	if near>maxf(TILE.x,TILE.y)*1.5: return grid
	return snap_foundation("deck",point,0,rows,free_water,height,snap_step,edge_assist)
## Platforms only join edge to edge. Each candidate is generated by laying one
## raft edge flush against an existing platform edge, then sliding it along that
## edge until one of its own edges lines up with a neighbour's corner. Free
## integer-metre positions are only for a raft that joins nothing, which the
## boat unlocks; on foot a platform must touch the surface it extends.
static func snap_foundation(kind: String,point: Vector2,turn: int,rows: Array,free_water: bool=false,height: float=0.0,snap_step: float=0.1,edge_assist: bool=true) -> Dictionary:
	var extent:=platform_extent(kind,turn)
	var step:=clampf(snap_step,0.01,0.1)
	var free: Dictionary={"kind":kind,"px":snappedf(point.x,step),"pz":snappedf(point.y,step),
		"py":height,"x":0,"z":0,"support":"","turn":turn}
	if kind=="deck": free.positioned=true
	if not edge_assist: return free
	var surfaces:=platform_tiles_at_level(rows,height)
	var stairs: Array=[]
	# Degenerate rectangles contribute only the stair's high edge as a snap
	# guide. They never add support area or cover a hole in a platform.
	for row in rows:
		if str(RECIPES[row.kind].get("profile",""))!="stairs" or float(row.left)>0 or not same_level(elevation(row)+stair_rise(row),height): continue
		stairs.append(row)
		var edge:=stairs_top_edge(row)
		surfaces.append(Rect2(Vector2(minf(edge[0].x,edge[1].x),minf(edge[0].y,edge[1].y)),Vector2(absf(edge[0].x-edge[1].x),absf(edge[0].y-edge[1].y))))
	if free_water and same_level(height,0.0):
		var lone:=Rect2(Vector2(free.px,free.pz)-extent/2,extent)
		var clear:=not overlaps_any(lone,surfaces)
		for tile: Rect2 in surfaces:
			if tile.grow(0.6).intersects(lone): clear=false;break
		if clear: return free
	var best: Dictionary={}
	var best_score:=INF
	var index:=build_index(surfaces)
	# One ordered copy of every tile corner: [start, end, start, end, …] in the
	# same order the old inner loop produced them. Reusing this keeps tie-breaks
	# identical — several positions can be equally near the cursor, and the first
	# one wins, so a sorted set would silently pick a different board placement.
	var corner_x: Array=[]
	var corner_z: Array=[]
	for tile: Rect2 in surfaces:
		corner_x.append(tile.position.x);corner_x.append(tile.end.x)
		corner_z.append(tile.position.y);corner_z.append(tile.end.y)
	# The slid positions depend only on the corner list and the candidate span,
	# never on which edge is being attached, so the two orientations are resolved
	# once instead of once per edge per tile.
	var raws_vertical: Array=unique_slide_positions(corner_z,extent.y/2)
	var raws_horizontal: Array=unique_slide_positions(corner_x,extent.x/2)
	var half:=extent/2
	for tile: Rect2 in surfaces:
		for side in 4:
			var vertical:=side<2
			var edge: float=(tile.position.x if side==0 else tile.end.x) if vertical else (tile.position.y if side==2 else tile.end.y)
			var fixed: float=(edge-half.x) if side==0 else ((edge+half.x) if side==1 else ((edge-half.y) if side==2 else (edge+half.y)))
			for raw: float in (raws_vertical if vertical else raws_horizontal):
				var center: Vector2=(Vector2(fixed,raw) if vertical else Vector2(raw,fixed))
				var rect:=Rect2(center-half,extent)
				# Distance is cheaper than the seam/overlap tests and is the value
				# the result is ranked by, so a candidate that cannot win is dropped
				# before touching the spatial index.
				var near: float=rect_distance(rect,point)
				if near>=best_score-0.0005: continue
				var local: Array=neighbours(index,rect)
				var contact:=contact_against(rect,local)
				if contact<JOIN_MIN:
					for stair in stairs: contact=maxf(contact,stairs_top_contact(rect,stair))
				if contact<JOIN_MIN: continue
				if overlaps_any(rect,local): continue
				best_score=near
				best={"kind":kind,"px":center.x,"pz":center.y,"py":height,"x":0,"z":0,"support":"","turn":turn}
				if kind=="deck": best.positioned=true
	if not best.is_empty(): return best
	return free
## Flush positions along one axis: a candidate edge lands on `corner + span/2`
## for a start corner and `corner - span/2` for an end corner. Duplicates are
## dropped in first-seen order so the cheapest equally-near candidate is still
## the one that wins.
static func unique_slide_positions(corners: Array, half_span: float) -> Array:
	var seen: Dictionary={}
	var out: Array=[]
	for i in corners.size():
		var raw: float=float(corners[i])+((half_span) if i%2==0 else (-half_span))
		var key:=int(round(raw*100.0))
		if seen.has(key): continue
		seen[key]=true
		out.append(raw)
	return out
## True when `rect` lies entirely inside the union of `tiles`.
## Sweeps every vertical slice between tile edges, so a seam between two
## neighbouring decks counts as covered and a gap never does.
static func covered(rect: Rect2, tiles: Array) -> bool:
	if rect.size.x<=0.0 or rect.size.y<=0.0: return false
	var edges: Dictionary={rect.position.x:true,rect.end.x:true}
	var relevant: Array=[]
	for tile: Rect2 in tiles:
		if not tile.intersects(rect): continue
		relevant.append(tile)
		if tile.position.x>rect.position.x and tile.position.x<rect.end.x: edges[tile.position.x]=true
		if tile.end.x>rect.position.x and tile.end.x<rect.end.x: edges[tile.end.x]=true
	if relevant.is_empty(): return false
	# Many tiles share an X edge. Deduplicate it before sweeping; otherwise a
	# large platform repeats the same slice once per distant row of tiles.
	var xs: Array=edges.keys()
	xs.sort()
	for i in xs.size()-1:
		var left: float=xs[i]
		var right: float=xs[i+1]
		if right-left<0.0005: continue
		var sample: float=(left+right)*0.5
		var spans: Array=[]
		for tile: Rect2 in relevant:
			if sample>=tile.position.x and sample<=tile.end.x: spans.append(Vector2(tile.position.y,tile.end.y))
		spans.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x<b.x)
		var reach: float=rect.position.y
		for span: Vector2 in spans:
			if span.x>reach+0.0005: break
			reach=maxf(reach,span.y)
		if reach<rect.end.y-0.0005: return false
	return true
