extends RefCounted
## Runtime eligibility policy. Replace eligibility for future offshore construction.
const Catalog = preload("res://src/building/building_catalog.gd")
var actor_query: Callable
var boat_query: Callable
var obstacles_query: Callable
var world: Node3D
func eligibility() -> String:
	var context: Dictionary=actor_query.call()
	if context.mode!=0 or context.zone!="zone5": return "初阶建造需要先登上六格种植平台"
	return ""
func space_reason(request: Dictionary) -> String:
	if request.kind=="planter":
		var actor: Vector3=actor_query.call().position
		if Catalog.plot_rect(request).grow(0.18).has_point(Vector2(actor.x-Catalog.ORIGIN.x,actor.z-Catalog.ORIGIN.z)):
			return "请先让出种植区的位置"
		return ""
	var rect:=Catalog.tile_rect(request.x,request.z)
	rect.position+=Vector2(Catalog.ORIGIN.x,Catalog.ORIGIN.z)
	var boat: Vector3=boat_query.call()
	if rect.grow(2.5).has_point(Vector2(boat.x,boat.z)): return "请让船离开施工范围"
	for obstacle: Rect2 in obstacles_query.call():
		if rect.grow(-0.08).intersects(obstacle): return "这里有既有建筑，无法拼接"
	return ""
