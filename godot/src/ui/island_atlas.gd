extends Control
var zones: Node
var game_state: Node
## 世界坐标查询，返回 {"zone": String, "position": Vector3}。为空时退回区块中心。
var player_query: Callable
## Read-only drawn map from registered footprints. It never invents unlocks or routes.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const HOME_ZONE := "zone1"
const YOU := Color("#d98f63")
const YOU_DARK := Color("#b06b41")
const HOME_EDGE := Color("#e0b768")
var font: Font
var bounds := Rect2(-100,-110,210,210)
var footprints := {}
var _tick := 0.0

func _ready() -> void:
	custom_minimum_size=Vector2(560,235)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for zone in zones.list:
		if zones.zone_enabled_query.is_valid() and not zones.zone_enabled_query.call(str(zone.id)): continue
		footprints[zone.id]=zones.footprint(zone.id)
	if footprints.size()<=2: bounds=Rect2(-18,-12,55,48)
	resized.connect(queue_redraw)
	set_process(true)

func _process(delta: float) -> void:
	# 地图打开时船可能还在走：定时重取真实坐标，别把旧位置画成「你现在在这」。
	if not is_visible_in_tree() or not player_query.is_valid(): return
	_tick += delta
	if _tick < 0.25: return
	_tick = 0.0
	queue_redraw()

func project(point: Vector2) -> Vector2:
	return Vector2(28,22)+(point-bounds.position)/bounds.size*(size-Vector2(56,44))

func _draw() -> void:
	var base := Cozy.surface(Color("#b8d9cf"),26);base.shadow_size=0
	draw_style_box(base,Rect2(Vector2.ZERO,size))
	for y in range(20,int(size.y),26):
		for x in range(20,int(size.x),40):
			draw_arc(Vector2(x,y),7,0.2,PI-0.2,10,Color(1,1,0.65,0.20),1,true)
	var spot := _you_spot()
	var here := _berth_of(spot) if spot.available else ""
	for id in footprints:
		var rect: Rect2=footprints[id]
		if not rect.has_area(): continue
		var p := project(rect.get_center())
		var unlocked: bool=zones.is_unlocked(id)
		var home: bool = id == HOME_ZONE
		var extent := _extent(id,rect)
		var land := Cozy.surface(Cozy.CREAM if unlocked else Color("#a3bdb2"),14);land.shadow_size=0
		if home and unlocked:
			land.border_color = HOME_EDGE
			land.set_border_width_all(2)
		elif id == here:
			# 站在这里：徽标自己套一圈橙环，比在中心盖一个点更清楚 —— 房子还看得见。
			land.border_color = YOU
			land.set_border_width_all(2)
		draw_style_box(land,Rect2(p-extent/2,extent))
		if home:
			_draw_home(p,unlocked)
			if font: draw_string(font,p+Vector2(-70,32),"太阳房 · 家园",HORIZONTAL_ALIGNMENT_CENTER,140,15,Cozy.INK)
		else:
			draw_circle(p,7,Cozy.TEAL if unlocked else Cozy.DIM)
			if font: draw_string(font,p+Vector2(12,-10),zones.label(id),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Cozy.INK)
	if spot.available:
		_draw_you(spot,here)

func _extent(id: String, rect: Rect2) -> Vector2:
	var e := Vector2(maxf(38,rect.size.x*1.5),maxf(22,rect.size.y*0.65))
	if id == HOME_ZONE: e = Vector2(maxf(58,e.x),maxf(44,e.y))
	return e

func _draw_home(p: Vector2, unlocked: bool) -> void:
	var roof := HOME_EDGE if unlocked else Cozy.DIM
	var body := Cozy.CREAM if unlocked else Color("#dcd7c7")
	draw_colored_polygon(PackedVector2Array([p+Vector2(-17,-3),p+Vector2(0,-20),p+Vector2(17,-3)]),roof)
	draw_rect(Rect2(p+Vector2(-13,-3),Vector2(26,18)),body)
	draw_rect(Rect2(p+Vector2(-13,-3),Vector2(26,18)),Cozy.INK,false,1.6)
	draw_rect(Rect2(p+Vector2(-4,5),Vector2(8,10)),Cozy.INK)

## 「你自己」按真实世界坐标投影。
## 停泊时把橙点别在该区块徽标的外侧角上：中心是房子和名字，点压上去就成了糊掉的一块。
## 取不到坐标（无角色/未进世界）时退回当前区块中心，不编造位置。
func _draw_you(spot: Dictionary, here: String) -> void:
	var p: Vector2 = spot.pos
	if here != "":
		var rect: Rect2 = footprints[here]
		var center := project(rect.get_center())
		var extent := _extent(here,rect)
		# 挂在牌子外侧左上角：像别针别在牌子边上，不压房子、不压名字。
		p = center+Vector2(-extent.x/2-3,-extent.y/2-3)
	draw_circle(p,10,Color("#fffdf5"))
	draw_circle(p,6.5,YOU)
	if font == null or here != "": return
	var text := "你在这里"
	var tw: float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	var box := Rect2(p+Vector2(-tw/2-10,-52),Vector2(tw+20,28))
	box.position.x = clampf(box.position.x,6,size.x-6-box.size.x)
	box.position.y = clampf(box.position.y,6,size.y-6-box.size.y)
	draw_style_box(Cozy.surface(Cozy.CREAM,12),box)
	draw_string(font,box.position+Vector2(10,20),text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,YOU_DARK)

## 这一点是否已经落在某处泊位徽标上（该徽标自己会亮橙环，不再另加标签）。
func _berth_of(spot: Dictionary) -> String:
	if not spot.available: return ""
	var p: Vector2 = spot.pos
	var best := ""
	var best_d := 30.0
	for id in footprints:
		var rect: Rect2 = footprints[id]
		if not rect.has_area(): continue
		var d := p.distance_to(project(rect.get_center()))
		if d < best_d:
			best_d = d
			best = id
	return best

func _you_spot() -> Dictionary:
	if player_query.is_valid():
		var data: Variant = player_query.call()
		if data is Dictionary and data.has("position"):
			var v: Vector3 = data["position"]
			var raw := project(Vector2(v.x,v.z))
			return {"available":true,"pos":Vector2(clampf(raw.x,18,size.x-18),clampf(raw.y,18,size.y-18))}
	if game_state != null and footprints.has(str(game_state.current_zone)):
		var rect: Rect2 = footprints[str(game_state.current_zone)]
		if rect.has_area(): return {"available":true,"pos":project(rect.get_center())}
	return {"available":false,"pos":Vector2.ZERO}
