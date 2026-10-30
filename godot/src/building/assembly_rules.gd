extends RefCounted
## Pure content policy. Stable IDs, support sockets and 3D separation; no scene reads.
const Catalog=preload("res://src/building/building_catalog.gd")
static func profile(row: Dictionary) -> String: return str(Catalog.RECIPES.get(str(row.get("kind","")),{}).get("profile",""))
static func center(row: Dictionary) -> Vector2: return Catalog.footprint_rect(row).get_center()
static func turn_point(p: Vector2, row: Dictionary) -> Vector2:
	return center(row)+p.rotated(-float(row.get("turn",0))*PI/2)
static func sockets(row: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	if profile(row)=="post": result.append(center(row))
	if profile(row) in ["wall","window","door"]:
		result.append(turn_point(Vector2(-1,0),row));result.append(turn_point(Vector2(1,0),row))
	return result
static func required_sockets(row: Dictionary) -> Array[Vector2]:
	var extent: Vector2=Catalog.RECIPES[row.kind].footprint
	var result: Array[Vector2]=[]
	if profile(row)=="beam":
		result.append(turn_point(Vector2(-1,0),row));result.append(turn_point(Vector2(1,0),row))
	else:
		for x in [-extent.x/2,extent.x/2]:
			for z in [-extent.y/2,extent.y/2]: result.append(turn_point(Vector2(x,z),row))
	return result
static func joint_points(row: Dictionary) -> Array[Vector2]:
	if profile(row)=="post": return [center(row)]
	return [turn_point(Vector2(-1,0),row),turn_point(Vector2(1,0),row)]
static func joint_overlap(a: Dictionary,b: Dictionary) -> bool:
	var overlap:=Catalog.footprint_rect(a).intersection(Catalog.footprint_rect(b))
	if overlap.size.x>.32 or overlap.size.y>.32: return false
	for point in joint_points(a):
		for other in joint_points(b):
			if point.distance_to(other)<=.23: return true
	return false
static func bearing_ids(row: Dictionary, rows: Array) -> Array[String]:
	var ids: Array[String]=[]
	for point in required_sockets(row):
		var found:=""
		for other in rows:
			if str(other.id)==str(row.get("id",row.get("exclude_id",""))) or other.left>0: continue
			for socket in sockets(other):
				if socket.distance_to(point)<0.26: found=str(other.id);break
			if found!="": break
		if found=="": return []
		if not ids.has(found): ids.append(found)
	return ids
static func reason(row: Dictionary, rows: Array) -> String:
	var kind:=str(row.get("kind",""))
	if not Catalog.is_kit(kind): return "未知组件"
	for key in ["px","pz","py"]:
		var v: Variant=row.get(key,0.0)
		if not (v is float or v is int) or not is_finite(float(v)): return "组件坐标格式错误"
	var shape:=Catalog.footprint_rect(row)
	var own:=str(row.get("id",row.get("exclude_id","")))
	var p:=profile(row)
	var h:=Catalog.elevation(row)
	var definition: Dictionary=Catalog.RECIPES[kind]
	if p=="foundation":
		if absf(h)>0.001: return "浮台必须位于水面基础层"
		if shape.grow(-0.001).intersects(Catalog.BASE): return "不能覆盖原有平台"
		for other in rows:
			if str(other.id)!=own and Catalog.is_deck(str(other.kind)) and Catalog.footprint_rect(other).grow(-0.001).intersects(shape): return "浮台不能重叠"
		return ""
	var support: Dictionary={}
	if str(row.get("support",""))=="@base": support=Catalog.fixed_support()
	for other in rows:
		if str(other.id)==str(row.get("support","")): support=other;break
	if support.is_empty() or support.left>0 or str(support.id)==own: return "需要已完工的承载组件"
	if str(definition.placement)=="top":
		var expected:=2.6 if p=="beam" else 2.8
		if absf(h-expected)>0.001: return "顶部组件需要吸附到2.8米层高挂点"
		var bearings:=bearing_ids(row,rows)
		if bearings.is_empty() or not bearings.has(str(support.id)): return "顶部挂点缺少完整的立柱或墙体支撑"
	else:
		if absf(h)>0.001 and absf(h-2.8)>0.001: return "请选择地面或二层楼板"
		if h>0.1 and (p in ["wall","window","door","post","stairs","railing"]): return "首批结构件安装在基础层"
		var tiles: Array=[Catalog.BASE] if h<.1 else []
		for other in rows:
			if other.left>0: continue
			if h<0.1 and Catalog.is_deck(str(other.kind)): tiles.append(Catalog.footprint_rect(other))
			elif h>0.1 and profile(other)=="floor": tiles.append(Catalog.footprint_rect(other))
		if not ((h<0.1 and (str(support.id)=="@base" or Catalog.is_deck(str(support.kind)))) or (h>0.1 and profile(support)=="floor")): return "支撑楼层不匹配"
		var supporting_rect: Rect2=Catalog.BASE if str(support.id)=="@base" else Catalog.footprint_rect(support)
		if not supporting_rect.grow(.11).intersects(shape): return "请选择组件脚下的实际支撑"
		# Structural joints may meet exactly at the outside edge; decorations stay inside.
		var inset:=0.0 if definition.group=="structure" else 0.04
		var test_shape:=shape.grow(inset)
		if p in ["wall","window","door","railing","post"]: test_shape=shape.grow(-minf(shape.size.x,shape.size.y)*0.49)
		if definition.group=="structure":
			for i in tiles.size(): tiles[i]=tiles[i].grow(.01)
		if not Catalog.covered(test_shape,tiles): return "组件需要完整落在当前楼层承载面内"
	for other in rows:
		if str(other.id)==own or Catalog.is_deck(str(other.kind)): continue
		var other_h:=Catalog.elevation(other)
		if profile(other)=="floor" and h>=other_h-0.015 and definition.group=="decoration": continue
		var other_height: float=Catalog.RECIPES[other.kind].get("height",0.3)
		if h>=other_h+other_height-0.015 or other_h>=h+float(definition.height)-0.015: continue
		if not shape.grow(-0.008).intersects(Catalog.footprint_rect(other)): continue
		if definition.group=="structure" and Catalog.RECIPES[other.kind].get("group","")=="structure":
			if kind==other.kind and center(row).distance_to(center(other))<0.02 and int(row.turn)==int(other.turn): return "挂点已有相同构件"
			# Ends/corners are real join sockets, not mutually exclusive furniture slots.
			if p in ["wall","window","door","post","beam","railing"] and profile(other) in ["wall","window","door","post","beam","railing"] and joint_overlap(row,other): continue
		return "同一高度的实体不能重叠"
	return ""
