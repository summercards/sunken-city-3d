extends RefCounted
## Recipe and geometry constants; no mutable gameplay state.
const ORIGIN := Vector3(22, 1.48, 16)
const TILE := Vector2(2.15, 2.575)
const BASE := Rect2(-3.225, -2.575, 6.45, 5.15)
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
	var extent := Vector2(1.794,1.575)
	if int(row.get("turn",0))%2==1: extent=Vector2(extent.y,extent.x)
	return Rect2(Vector2(row.px,row.pz)-extent/2,extent)
static func polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
