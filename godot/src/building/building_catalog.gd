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
## Placement and rendering both consume these roles. Adding a new furnishing
## means adding a recipe and its projection, not another layout state owner.
const LEGACY_RECIPES := {
	"deck":{"name":"拼接木板", "cost":{"wood":6}, "seconds":3.0,
		"description":"接出平台，或乘船在空旷海面开始新平台。", "category":CATEGORY_PLATFORM,
		"placement":"ocean_grid", "support":"water", "footprint":TILE, "visual":"deck",
		"role":"deck", "rotatable":false, "movable":false, "removable":true},
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
static func _load_recipes() -> Dictionary:
	var result: Dictionary=LEGACY_RECIPES.duplicate(true)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/building_kit.json"))
	assert(data is Dictionary and data.get("schema")==1,"Invalid building content catalog")
	for raw: Dictionary in data.modules:
		assert(not result.has(raw.id),"Duplicate recipe ID")
		var definition: Dictionary=raw.duplicate(true)
		definition.footprint=Vector2(raw.footprint[0],raw.footprint[1])
		definition.kit=true;definition.visual="kit"
		# A raft is a platform, not a frame: it carries bodies and joins other
		# platforms edge-to-edge, exactly like the legacy 2.15x2.575 board.
		# Walls, posts, beams and roofs are frames; furniture is decoration.
		if raw.profile=="foundation":
			definition.category=CATEGORY_PLATFORM
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
static func enabled(kind: String) -> bool: return bool(RECIPES.get(kind,{}).get("active",true))
static func position_rect(row: Dictionary) -> Rect2: return footprint_rect(row)
static func elevation(row: Dictionary) -> float: return float(row.get("py",0.0))
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
	return tile_rect(int(row.x),int(row.z)) if str(row.kind)=="deck" else plot_rect(row)
static func cell_at(point: Vector2) -> Vector2i:
	var cell := (point-BASE.position)/TILE
	return Vector2i(int(floor(cell.x)),int(floor(cell.y)))
static func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
## Footprint of every finished deck, as one continuous wooden surface.
static func deck_tiles(rows: Array) -> Array:
	var result: Array=[]
	for item in rows:
		if not is_deck(str(item.kind)) or float(item.left)>0: continue
		result.append(footprint_rect(item))
	return result
static func support_tiles(rows: Array) -> Array:
	var result:=deck_tiles(rows)
	result.append(BASE)
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
static func platform_contact(rect: Rect2, rows: Array) -> float:
	var best:=0.0
	for tile: Rect2 in support_tiles(rows):
		best=maxf(best,contact_length(rect,tile))
	return best
static func overlaps_any(rect: Rect2, surfaces: Array) -> bool:
	for tile: Rect2 in surfaces:
		var overlap: Rect2=rect.grow(-0.002).intersection(tile)
		if overlap.size.x>0.001 and overlap.size.y>0.001: return true
	return false
## Platforms only join edge to edge. Each candidate is generated by laying one
## raft edge flush against an existing platform edge, then sliding it along that
## edge until one of its own edges lines up with a neighbour's corner. Free
## integer-metre positions are only for a raft that joins nothing, which the
## boat unlocks; on foot a platform must touch the surface it extends.
static func snap_foundation(kind: String,point: Vector2,turn: int,rows: Array,free_water: bool=false) -> Dictionary:
	var extent:=platform_extent(kind,turn)
	var free: Dictionary={"kind":kind,"px":snappedf(point.x,2.0),"pz":snappedf(point.y,2.0),
		"py":0.0,"x":0,"z":0,"support":"","turn":turn}
	var surfaces:=support_tiles(rows)
	if free_water:
		var lone:=Rect2(Vector2(free.px,free.pz)-extent/2,extent)
		var clear:=not overlaps_any(lone,surfaces)
		for tile: Rect2 in surfaces:
			if tile.grow(0.6).intersects(lone): clear=false;break
		if clear: return free
	var best: Dictionary={}
	var best_score:=INF
	for tile: Rect2 in surfaces:
		for side in 4:
			var vertical:=side<2
			var edge: float=(tile.position.x if side==0 else tile.end.x) if vertical else (tile.position.y if side==2 else tile.end.y)
			var span: float=extent.y if vertical else extent.x
			var seen: Dictionary={}
			for other: Rect2 in surfaces:
				for raw: float in [(other.position.y if vertical else other.position.x)+span/2,
						(other.end.y if vertical else other.end.x)-span/2]:
					var key:=int(round(raw*100.0))
					if seen.has(key): continue
					seen[key]=true
					var request: Dictionary=free.duplicate()
					if vertical:
						request.px=edge-(extent.x/2) if side==0 else edge+(extent.x/2)
						request.pz=raw
					else:
						request.px=raw
						request.pz=edge-(extent.y/2) if side==2 else edge+(extent.y/2)
					var rect:=Rect2(Vector2(request.px,request.pz)-extent/2,extent)
					if platform_contact(rect,rows)<JOIN_MIN: continue
					if overlaps_any(rect,surfaces): continue
					var score:=rect_distance(rect,point)
					if score<best_score-0.0005:
						best_score=score;best=request
	if not best.is_empty(): return best
	return free
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
