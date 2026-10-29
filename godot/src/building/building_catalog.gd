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
## Placement and rendering both consume these roles. Adding a new furnishing
## means adding a recipe and its projection, not another layout state owner.
const RECIPES := {
	"deck":{"name":"拼接木板", "cost":{"wood":6}, "seconds":3.0,
		"description":"接出平台，或乘船在空旷海面开始新平台。", "category":"structure",
		"placement":"ocean_grid", "support":"water", "footprint":TILE, "visual":"deck",
		"role":"deck", "rotatable":false, "movable":false, "removable":true},
	"planter":{"name":"培养土种植区", "cost":{"wood":3,"soil":2}, "seconds":4.0,
		"description":"在整片木面自由摆放，可搬移、旋转与回收。", "category":"furnishing",
		"placement":"deck_surface", "support":"finished_deck", "footprint":PLOT_EXTENT,
		"visual":"planter", "role":"planter", "blocks_actor":false, "rotatable":true, "movable":true, "removable":true},
	"planter_small":{"name":"小型培养土", "cost":{"wood":2,"soil":1}, "seconds":3.0,
		"description":"占地更小，适合单板花园和窄平台。", "category":"furnishing",
		"placement":"deck_surface", "support":"finished_deck", "footprint":Vector2(0.9,1.0),
		"visual":"planter", "role":"planter", "blocks_actor":false, "rotatable":true, "movable":true, "removable":true}
}
static func is_furnishing(kind: String) -> bool:
	return RECIPES.has(kind) and RECIPES[kind].category=="furnishing"
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
		if item.kind!="deck" or float(item.left)>0: continue
		result.append(tile_rect(int(item.x),int(item.z)))
	return result
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
