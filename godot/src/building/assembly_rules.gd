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
	if profile(row) in ["wall","window","door","beam"]:
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
## Every socket owner at a required point counts. A post corner and the end of a
## wall are the same point, so taking only the first match let build order decide
## whether a floor found the bearing its `support` names — validation then failed
## a layout that had been accepted moments earlier.
static func bearing_ids(row: Dictionary, rows: Array) -> Array[String]:
	var ids: Array[String]=[]
	var own:=str(row.get("exclude_id",row.get("id","")))
	var shape:=Catalog.footprint_rect(row).grow(0.26)
	var target:=Catalog.elevation(row)
	if profile(row)=="beam": target+=float(Catalog.RECIPES[row.kind].height)
	for other in rows:
		if str(other.id)==own or other.left>0: continue
		if not Catalog.same_level(Catalog.elevation(other)+float(Catalog.RECIPES[other.kind].get("height",0.3)),target): continue
		for socket in sockets(other):
			if shape.has_point(socket):
				ids.append(str(other.id));break
	return ids
## All placement consumers use the same height-aware support lookup. A stair's
## high edge is a connection, never a pretend rectangular floor under a prop.
static func support_ids(row: Dictionary,rows: Array) -> Array[String]:
	var ids: Array[String]=[]
	var kind:=str(row.get("kind",""))
	if not Catalog.RECIPES.has(kind): return ids
	var own:=str(row.get("exclude_id",row.get("id","")))
	var height:=Catalog.elevation(row)
	var shape:=Catalog.footprint_rect(row)
	if Catalog.is_platform(kind):
		if Catalog.same_level(height,0.0) and Catalog.contact_length(shape,Catalog.BASE)>=Catalog.JOIN_MIN: ids.append("@base")
		for other in rows:
			if str(other.id)==own or float(other.left)>0.0: continue
			if Catalog.is_platform(str(other.kind)) and Catalog.same_level(Catalog.elevation(other),height) and Catalog.contact_length(shape,Catalog.footprint_rect(other))>=Catalog.JOIN_MIN: ids.append(str(other.id))
			elif profile(other)=="stairs" and Catalog.same_level(Catalog.elevation(other)+Catalog.LAYER_HEIGHT,height) and Catalog.stairs_top_contact(shape,other)>=Catalog.JOIN_MIN: ids.append(str(other.id))
		return ids
	if Catalog.same_level(height,0.0) and Catalog.BASE.grow(.11).intersects(shape): ids.append("@base")
	for other in Catalog.platform_rows_at_level(rows,height):
		if str(other.id)!=own and Catalog.footprint_rect(other).grow(.11).intersects(shape): ids.append(str(other.id))
	if str(Catalog.RECIPES[kind].get("placement",""))=="top":
		for id in bearing_ids(row,rows):
			if not ids.has(id): ids.append(id)
	return ids
## Pure geometry: overlap, floor, bearings. Whether a new platform may start
## where it stands is a build-eligibility question and lives in BuildingService.
static func reason(row: Dictionary, rows: Array,strict_clearance: bool=true) -> String:
	var kind:=str(row.get("kind",""))
	if not Catalog.RECIPES.has(kind): return "未知组件"
	for key in ["px","pz","py"]:
		var v: Variant=row.get(key,0.0)
		if not (v is float or v is int) or not is_finite(float(v)): return "组件坐标格式错误"
	var shape:=Catalog.footprint_rect(row)
	if not shape.position.is_finite() or not shape.size.is_finite(): return "组件坐标超出数值精度"
	var own:=str(row.get("exclude_id",row.get("id","")))
	var p:=profile(row)
	var h:=Catalog.elevation(row)
	var definition: Dictionary=Catalog.RECIPES[kind]
	if Catalog.is_platform(kind):
		if not Catalog.valid_level(h): return "平台需要放在有效的楼层平面"
		var named:=str(row.get("support",""))
		if named!="" and not rows.any(func(other): return str(other.id)==named and str(other.id)!=own and float(other.left)<=0): return "原承载构件已经不存在"
		if Catalog.same_level(h,0.0) and shape.grow(-0.001).intersects(Catalog.BASE): return "不能覆盖原有平台"
		for other in rows:
			if str(other.id)!=own and Catalog.is_platform(str(other.kind)) and Catalog.same_level(Catalog.elevation(other),h) and Catalog.footprint_rect(other).grow(-0.001).intersects(shape): return "同一楼层的平台不能重叠"
		return ""
	var support: Dictionary={}
	if str(row.get("support",""))=="@base": support=Catalog.fixed_support()
	for other in rows:
		if str(other.id)==str(row.get("support","")): support=other;break
	if support.is_empty() or support.left>0 or str(support.id)==own: return "需要已完工的承载组件"
	var top:=str(definition.get("placement",""))=="top"
	var bearing_support:=top and bearing_ids(row,rows).has(str(support.id))
	if not bearing_support:
		if not Catalog.valid_level(h): return "请选择已有平台或楼梯顶部的楼层平面"
		var tiles:=Catalog.platform_tiles_at_level(rows,h)
		if not ((str(support.id)=="@base" and Catalog.same_level(h,0.0)) or (Catalog.is_platform(str(support.kind)) and Catalog.same_level(Catalog.elevation(support),h))): return "支撑楼层不匹配"
		var supporting_rect: Rect2=Catalog.BASE if str(support.id)=="@base" else Catalog.footprint_rect(support)
		if not supporting_rect.grow(.11).intersects(shape): return "请选择组件脚下的实际支撑"
		# Structural joints may meet exactly at the outside edge; decorations stay inside.
		var inset:=0.0 if definition.get("group","")=="structure" else 0.04
		var test_shape:=shape.grow(inset)
		if p in ["wall","window","door","railing","post"]: test_shape=shape.grow(-minf(shape.size.x,shape.size.y)*0.49)
		if definition.get("group","")=="structure":
			for i in tiles.size(): tiles[i]=tiles[i].grow(.01)
		if not Catalog.covered(test_shape,tiles): return "组件需要完整落在当前楼层承载面内"
	for other in rows:
		if str(other.id)==own or Catalog.is_deck(str(other.kind)): continue
		var other_h:=Catalog.elevation(other)
		var other_height: float=Catalog.RECIPES[other.kind].get("height",0.3)
		if h>=other_h+other_height-0.015 or other_h>=h+float(definition.get("height",0.3))-0.015: continue
		var structural_joint: bool=definition.get("group","")=="structure" and Catalog.RECIPES[other.kind].get("group","")=="structure"
		var clearance: float=-0.008 if structural_joint or not strict_clearance else 0.0195
		if not shape.grow(clearance).intersects(Catalog.footprint_rect(other)): continue
		if structural_joint:
			if kind==other.kind and center(row).distance_to(center(other))<0.02 and int(row.turn)==int(other.turn): return "挂点已有相同构件"
			# Ends/corners are real join sockets, not mutually exclusive furniture slots.
			if p in ["wall","window","door","post","beam","railing"] and profile(other) in ["wall","window","door","post","beam","railing"] and joint_overlap(row,other): continue
		return "同一高度的实体不能重叠"
	return ""
