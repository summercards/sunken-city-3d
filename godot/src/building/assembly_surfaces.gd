extends RefCounted
## Shared candidate/live geometry for stairs, upper floors, save validation and blockers.
const Catalog=preload("res://src/building/building_catalog.gd")
const Rules=preload("res://src/building/assembly_rules.gd")
static func blockers(row: Dictionary) -> Array:
	if Rules.profile(row)!="door": return [Catalog.footprint_rect(row)]
	var result: Array=[]
	for x in [-0.79,0.79]:
		var center:=Rules.turn_point(Vector2(x,0),row)
		var size:=Vector2(.42,.16) if int(row.turn)%2==0 else Vector2(.16,.42)
		result.append(Rect2(center-size/2,size))
	return result
static func surface_rows(rows: Array) -> Array:
	var result: Array=[]
	for row in rows:
		if row.left<=0 and Rules.profile(row) in ["stairs","floor"]: result.append(row)
	return result
static func height_at(point: Vector2, row: Dictionary) -> float:
	var local: Vector2=(point-Rules.center(row)).rotated(float(row.turn)*PI/2)
	var extent: Vector2=Catalog.RECIPES[row.kind].footprint
	if absf(local.x)>extent.x/2+0.001 or absf(local.y)>extent.y/2+0.001: return NAN
	return (2.0-local.y)*.7 if Rules.profile(row)=="stairs" else Catalog.elevation(row)
static func faces(rows: Array) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for row in surface_rows(rows):
		var box:=Catalog.footprint_rect(row)
		var rects: Array=[box]
		if Rules.profile(row)=="floor":
			for other in rows:
				if other.id==row.id or absf(Catalog.elevation(other)-2.8)>.1 or not Catalog.blocks_actor(other.kind): continue
				for cut: Rect2 in blockers(other):
					var pieces: Array=[]
					for rect: Rect2 in rects: pieces.append_array(load("res://src/building/building_space.gd").subtract(rect,cut.grow(.22)))
					rects=pieces
		for rect: Rect2 in rects:
			var xs: Array=[rect.position.x,rect.end.x]
			var zs: Array=[rect.position.y,rect.end.y]
			for other in surface_rows(rows):
				var edge:=Catalog.footprint_rect(other)
				for x in [edge.position.x,edge.end.x]:
					if x>rect.position.x+.001 and x<rect.end.x-.001 and not xs.has(x): xs.append(x)
				for z in [edge.position.y,edge.end.y]:
					if z>rect.position.y+.001 and z<rect.end.y-.001 and not zs.has(z): zs.append(z)
			xs.sort();zs.sort()
			for x in xs.size()-1:
				for z in zs.size()-1:
					var corners:=Catalog.polygon(Rect2(Vector2(xs[x],zs[z]),Vector2(xs[x+1]-xs[x],zs[z+1]-zs[z])))
					for i in [0,2,1,0,3,2]:
						var at: Vector2=corners[i]
						result.append(Vector3(at.x,height_at(at,row),at.y))
	return result
static func contains(point: Vector3, rows: Array) -> bool:
	for row in surface_rows(rows):
		var height:=height_at(Vector2(point.x,point.z),row)
		if is_finite(height) and absf(point.y-height)<0.35: return true
	return false
