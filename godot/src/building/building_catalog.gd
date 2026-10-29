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
const RECIPES := {
	"deck":{"name":"拼接木板", "cost":{"wood":6}, "seconds":3.0, "description":"沿平台边缘接出新的落脚处。"},
	"planter":{"name":"培养土种植区", "cost":{"wood":3,"soil":2}, "seconds":4.0, "description":"一格木框培养土，让新平台长出蔬菜。"}
}
static func tile_rect(x: int, z: int) -> Rect2:
	return Rect2(BASE.position + Vector2(x,z)*TILE,TILE)
static func base_cell(x: int, z: int) -> bool: return x>=0 and x<3 and z>=0 and z<2
static func allowed_cell(x: int, z: int) -> bool:
	# West edge is the existing dock. Keep the entire approach channel open.
	return x>=0 and x<=4 and z>=-2 and z<=3 and not base_cell(x,z)
static func plot_rect(row: Dictionary) -> Rect2:
	var extent := PLOT_EXTENT
	if int(row.get("turn",0))%2==1: extent=Vector2(extent.y,extent.x)
	return Rect2(Vector2(row.px,row.pz)-extent/2,extent)
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
	var xs: Array=[rect.position.x,rect.end.x]
	for tile: Rect2 in tiles:
		if tile.position.x>rect.position.x and tile.position.x<rect.end.x: xs.append(tile.position.x)
		if tile.end.x>rect.position.x and tile.end.x<rect.end.x: xs.append(tile.end.x)
	xs.sort()
	for i in xs.size()-1:
		var left: float=xs[i]
		var right: float=xs[i+1]
		if right-left<0.0005: continue
		var sample: float=(left+right)*0.5
		var spans: Array=[]
		for tile: Rect2 in tiles:
			if sample>=tile.position.x and sample<=tile.end.x: spans.append(Vector2(tile.position.y,tile.end.y))
		spans.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x<b.x)
		var reach: float=rect.position.y
		for span: Vector2 in spans:
			if span.x>reach+0.0005: break
			reach=maxf(reach,span.y)
		if reach<rect.end.y-0.0005: return false
	return true
