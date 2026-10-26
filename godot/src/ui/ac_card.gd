extends Control
## One physical shell, two clipped pages. No gameplay state is owned here.
const Icon = preload("res://src/ui/ac_icon.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
const INK := Color("#3B3026")
const DIM := Color("#8A7A66")
const BLUE := Color("#4E9FC4")
const CREAM := Color("#F7F1E3")
signal activated(id: String)
signal page_changed(index: int)
var font: Font
var underwater := false
var oxygen := -1.0
var depth := -1.0
var feedback_enabled := true
var page := 0
var turning := false
var title: Label
var subtitle: Label
var status: Label
var footer: Label
var clip: Control
var pages: Array[Control] = []
var tiles := {}
var dots: Array[Button] = []
var motion: Control
var detail: ScrollContainer
var body: VBoxContainer
var phase := 0.0
var status_clock := "—"
var status_tide := "—"
var turn_tween: Tween
var tool_specs := [["water","水壶",Cozy.SKY],["hook","打捞钩",Cozy.GOLD],["lamp","潜水镜",Cozy.LILAC]]
var harvest_specs := [["fish","鲜鱼",Cozy.SKY],["vegetable","蔬菜",Cozy.MINT],["tomato","番茄",Cozy.CORAL],["pumpkin","南瓜",Cozy.GOLD],["shell","贝壳",Color("#ead3c1")],["pearl","珍珠",Cozy.LILAC]]
var app_specs := [["plant","种植",Cozy.MINT],["build","建造",Cozy.GOLD],["storage","仓储",Color("#ead3c1")],["map","航海图",Cozy.MINT],["dive","去潜水",Cozy.SKY],["save","保存",Cozy.CORAL],["load","读档",Cozy.LILAC],["camera","视角",Cozy.SKY],["grade","滤镜",Cozy.GOLD]]

func _ready() -> void:
	set_meta("cozy_skip",true)
	size = Vector2(420,620)
	pivot_offset = size/2
	mouse_filter = Control.MOUSE_FILTER_STOP
	motion = Control.new()
	motion.size = size
	motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(motion)
	motion.draw.connect(_draw_shell)
	status = label("",13,Vector2(36,20),Vector2(348,32),DIM)
	title = label("渔具箱",29,Vector2(44,77),Vector2(332,43),INK)
	subtitle = label("已装备工具  /  不可出售",12,Vector2(48,137),Vector2(324,22),DIM)
	clip = Control.new()
	clip.position = Vector2(27,169)
	clip.size = Vector2(366,369)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motion.add_child(clip)
	for p in 2:
		var sheet := Control.new()
		sheet.size = Vector2(366,369)
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(sheet)
		pages.append(sheet)
		var specs: Array = tool_specs + harvest_specs if p == 0 else app_specs
		for i in 9:
			var entry: Array = specs[i]
			var tile := Icon.new()
			tile.kind = entry[0]; tile.caption = entry[1]; tile.tint = entry[2];tile.font = font
			tile.locked = p == 0 and i < 3
			tile.position = Vector2(21+(i%3)*114,7+(i/3)*114)
			tile.pressed.connect(func(): select_tile(tile); activated.emit(str(entry[0])))
			sheet.add_child(tile)
			tiles[str(entry[0])] = tile
		pages[p].visible = p == 0
	footer = label("今日收成 · 选中查看",13,Vector2(44,529),Vector2(332,28),DIM)
	for p in 2:
		var dot := Button.new()
		dot.position = Vector2(183+p*29,574); dot.size = Vector2(24,24)
		dot.tooltip_text = "渔具箱" if p == 0 else "生活手册"
		for state in ["normal","hover","pressed","focus"]: dot.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		dot.pressed.connect(func(): flip(p))
		motion.add_child(dot);dots.append(dot)
	detail = ScrollContainer.new()
	detail.position = Vector2(36,137);detail.size = Vector2(348,407)
	detail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	motion.add_child(detail)
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	detail.add_child(body);detail.hide()
	select_tile(tiles.water)

func label(text: String, pixels: int, pos: Vector2, extent: Vector2, color: Color) -> Label:
	var node := Label.new();node.text = text;node.position = pos;node.size = extent
	node.add_theme_font_override("font",font);node.add_theme_font_size_override("font_size",pixels)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motion.add_child(node)
	return node

func select_tile(tile: Button) -> void:
	for t in tiles.values(): t.selected = t == tile
	footer.text = tile.caption + (" · 随身工具，不可出售" if tile.locked else " · 选择查看")

func flip(target: int) -> void:
	if turning: return
	if detail.visible:
		show_grid(target)
		return
	if target == page: return
	turning = true
	var old := pages[page]
	var next := pages[target]
	next.position.x = 366
	next.show()
	turn_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	turn_tween.tween_property(old,"position:x",-366.0,0.18)
	turn_tween.tween_property(next,"position:x",0.0,0.18)
	page = target
	_update_heading()
	turn_tween.chain().tween_callback(func():
		old.hide();old.position.x = 0;turning = false;page_changed.emit(page))

func show_grid(target := 0) -> void:
	if turn_tween: turn_tween.kill()
	turning = false
	page = target
	detail.hide();clip.show();subtitle.show()
	for i in 2:
		pages[i].position.x = 0;pages[i].visible = i == page
	_update_heading()

func show_detail(heading: String) -> void:
	if turn_tween: turn_tween.kill()
	turning = false
	clip.hide();subtitle.hide();detail.show();detail.scroll_vertical = 0
	title.text = heading;footer.text = "点下方圆点返回"

func _update_heading() -> void:
	title.text = ("潜水日志" if underwater else "渔具箱") if page == 0 else "生活手册"
	subtitle.text = "已装备工具  /  不可出售" if page == 0 else "海上的小事，慢慢来"
	footer.text = "今日收成 · 选中查看" if page == 0 else "选择一项，开始今天的生活"

func update_context(is_underwater: bool, air: float, meters: float) -> void:
	if underwater != is_underwater:
		underwater = is_underwater
		if not detail.visible: _update_heading()
	oxygen = air;depth = meters
	status.text = "时间 %s   潮汐 %s   水深 %s   氧气 %s" % [status_clock,status_tide,"%.0fm" % meters if meters >= 0 and underwater else "—","%d%%" % roundi(air*100) if air >= 0 and underwater else "—"]

func fly_in(id: String) -> void:
	if not tiles.has(id) or not visible or page != 0 or detail.visible: return
	var target: Control = tiles[id]
	var mote := Icon.new();mote.font = font;mote.kind = id;mote.tint = target.tint
	mote.mouse_filter = Control.MOUSE_FILTER_IGNORE;mote.scale = Vector2.ONE*0.38
	mote.position = Vector2(160,350);pages[0].add_child(mote)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mote,"position",target.position+Vector2(28,25),0.48)
	tween.tween_property(mote,"rotation",-0.15,0.48)
	tween.chain().tween_callback(func(): mote.queue_free();target.highlight())

func _process(delta: float) -> void:
	phase += delta
	motion.position.x = 2*sin(TAU*10*phase) if feedback_enabled and underwater and oxygen >= 0 and oxygen <= 0.15 else 0.0
	motion.queue_redraw()

func _draw_shell() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM;style.set_corner_radius_all(40)
	style.shadow_color = Color(0,0,0,0.18);style.shadow_size = 40;style.shadow_offset = Vector2(0,12)
	style.border_color = Color("#ddd3bf") if not underwater else Color("#95b8ba")
	style.set_border_width_all(2)
	if feedback_enabled and underwater and oxygen >= 0 and oxygen <= 0.30:
		style.border_color = Color("#D4573F") if oxygen <= 0.15 else Color("#E08B4A")
		style.set_border_width_all(3)
	motion.draw_style_box(style,Rect2(Vector2.ZERO,size))
	# Wood joinery at sea; stitched spine and binding loops underwater.
	var seam := Color("#b59a78") if not underwater else Color("#729ca6")
	motion.draw_line(Vector2(36,63),Vector2(384,63),Color(seam,0.3),1,true)
	for y in [112,508]:
		if underwater:
			for d in 3: motion.draw_arc(Vector2(9,y+d*9),7,-PI/2,PI/2,10,seam,2,true)
		else:
			motion.draw_circle(Vector2(19,y),2.5,Color(seam,0.65))
	for p in 2:
		var center := Vector2(195+p*29,586)
		if page == p: motion.draw_arc(center,7,0,TAU,24,BLUE,2.5,true)
		else: motion.draw_circle(center,4,Color("#c9c4b5"))
