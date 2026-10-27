class_name GameHUD
extends CanvasLayer
const EconomyDependency = preload("res://src/economy/economy.gd")
var economy: EconomyDependency
var zones: Node
var game_state: Node
## SEA-UI: one physical card; gameplay mutations only through existing commands.
signal destination_pressed(zone_id: String)
signal dive_pressed
signal build_pressed
signal site_focus_requested(id: String)
signal plot_focus_requested(id: String)
signal command_requested(command: String)
signal rest_requested
signal facility_build_requested(id: String)
signal ship_upgrade_requested
const UiFontLib = preload("res://src/ui/ui_font.gd")
const ItemDBLib = preload("res://src/inventory/item_db.gd")
const Card = preload("res://src/ui/ac_card.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
const INK := Cozy.INK
const DIM := Cozy.DIM
const OXYGEN_FEEDBACK_ENABLED := true
const TAB_BAG := "bag"
const TAB_BUILD := "build"
const TAB_PLANT := "plant"
const DESTINATIONS := [
	{"id":"zone1","name":"sea · 家园"},{"id":"zone2","name":"横滨铁道"},
	{"id":"zone3","name":"圆弧农场"},{"id":"zone5","name":"浅水养殖"},{"id":"zone4","name":"远海街町"}]
var _font: Font
var _root: Control
var _panel: Control
var _tab_body: VBoxContainer
var _panel_open := false
var _tab := "bag"
var _build_rows := {}
var _plant_rows := {}
var command_buttons := {}
var _diving := false
var _dive_zone := ""
var _depth := -1.0
var _air_ratio := -1.0
var _lamp_on := false
var _found := 0
var _found_total := 0
var _dive_btn: Button
var _dive_controls: HBoxContainer
var _dive_status: Label
var _toast: Label
var _toast_box: PanelContainer
var _toast_left := 0.0
var _res_label: Label
var _hints: HBoxContainer
var _backdrop: ColorRect
var _open_tween: Tween
var _base_position := Vector2(160,190)
var _counts := {}
var _initialized_counts := false
var _layout_size := Vector2.ZERO
var menu: CanvasLayer
var presenter_sources: Dictionary = {}
var _external_modal := false
## 外部面板打开时是否铺压暗遮罩。调色 / 取景面板会把它关掉，见 `set_external_modal`。
var _external_dim := true
var _launch: HBoxContainer
var _world_actions: HBoxContainer
var _history: Array[String] = []
var _toast_elapsed := 0.0
var _zoom: Label
var _zoom_left := 0.0
var _toast_tag: Label

func _ready() -> void:
	layer = 60
	# Canvas antialiasing only: leave the project and 3D renderer unchanged.
	get_viewport().msaa_2d = Viewport.MSAA_4X
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB","PingFang SC","Microsoft YaHei"]))
	_root = Control.new();_root.set_meta("cozy_skip",true)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT);_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_backdrop = ColorRect.new();_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D screen_texture : hint_screen_texture, filter_linear; uniform float strength = 0.0; void fragment(){ vec3 c=texture(screen_texture,SCREEN_UV).rgb; float gray=dot(c,vec3(0.299,0.587,0.114)); COLOR=vec4(mix(c,vec3(gray),0.18*strength)*(1.0-0.12*strength),1.0); }"
	var mat := ShaderMaterial.new();mat.shader = shader;_backdrop.material = mat
	_root.add_child(_backdrop);_backdrop.hide()
	_panel = Card.new();_panel.font = _font;_panel.feedback_enabled = OXYGEN_FEEDBACK_ENABLED
	_root.add_child(_panel);_panel.hide();_tab_body = _panel.body
	_panel.activated.connect(_activate)
	_panel.page_changed.connect(func(_page): _tab = "bag")
	for id in ["plant","build","save","load","camera","grade"]: command_buttons[id] = _panel.tiles[id]
	var launch := HBoxContainer.new();_launch=launch;launch.position = Vector2(40,32);launch.add_theme_constant_override("separation",12)
	_root.add_child(launch)
	var bag := _plain_button("▤  手册 B",true);bag.tooltip_text="随身手册 · B";launch.add_child(bag)
	bag.pressed.connect(func():
		if _panel_open: _toggle_panel()
		else: command_requested.emit("bag"))
	command_buttons.bag = bag
	var system := _plain_button("☰  Esc",true);system.tooltip_text="暂停与设置 · Esc";launch.add_child(system)
	system.pressed.connect(func(): menu.show_menu())
	command_buttons.system = system
	_dive_btn = _plain_button("潜水",true);launch.add_child(_dive_btn)
	_dive_btn.pressed.connect(func(): dive_pressed.emit())
	_world_actions=HBoxContainer.new();_world_actions.add_theme_constant_override("separation",10);_root.add_child(_world_actions)
	for entry in [["follow","回到角色"],["cancel","停止行动"]]:
		var button := _command_button(entry[1],entry[0],true);_world_actions.add_child(button)
	_res_label = _label("",15,Color.WHITE);_root.add_child(_res_label)
	# 世界浮层字：大号、圆润、不勾边。旧的 22px + 1~2px 硬阴影正是截图里
	# 「字很细、边缘发沟」的来源，见 Cozy.world_text 的两条规则。
	Cozy.world_text(_res_label,Cozy.WORLD_TEXT_RESOURCES,Color.WHITE)
	_dive_controls = HBoxContainer.new();_dive_controls.position = Vector2(32,88);_dive_controls.add_theme_constant_override("separation",8)
	_root.add_child(_dive_controls)
	for entry in [["rise","↑ 上游"],["descend","↓ 下游"],["lamp","头灯"]]: _dive_controls.add_child(_command_button(entry[1],entry[0],true))
	_dive_status = _label("",14,Color.WHITE)
	_root.add_child(_dive_status);_dive_status.hide()
	Cozy.world_text(_dive_status,Cozy.WORLD_TEXT_DIVE,Color.WHITE)
	_dive_controls.hide()
	_hints = HBoxContainer.new();_hints.add_theme_constant_override("separation",12);_root.add_child(_hints)
	var close := _plain_button("Ⓑ  返回   Esc",true);close.pressed.connect(func():
		if menu: menu.back()
		else: back())
	command_buttons.close = close;_hints.add_child(close)
	var select := _plain_button("Ⓐ  选择  Enter",true);select.pressed.connect(_activate_selection);_hints.add_child(select);_hints.hide()
	_toast_box = PanelContainer.new();_toast_box.add_theme_stylebox_override("panel",_pill(true));_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box);_toast_box.hide();_toast = _label("",30,INK);_toast_box.add_child(_toast)
	_toast.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_toast.custom_minimum_size.x=600
	_toast_box.custom_minimum_size.x=680
	Cozy.paper(_toast_box,Cozy.GOLD,true)
	_toast_box.custom_minimum_size.y=130
	_toast.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_toast_tag=_label("  海上的消息  ",22,Cozy.CREAM)
	_toast_tag.add_theme_stylebox_override("normal",Cozy.surface(Cozy.INK,18))
	_toast_tag.rotation=-0.035;_root.add_child(_toast_tag);_toast_tag.hide()
	_zoom=_label("",16,Cozy.CREAM)
	_zoom.add_theme_stylebox_override("normal",_pill(true));_root.add_child(_zoom);_zoom.hide()
	Cozy.world_text(_zoom,Cozy.WORLD_TEXT_ZOOM,Cozy.CREAM)
	menu = preload("res://src/ui/island_menu.gd").new();add_child(menu)
	menu.command_requested.connect(func(command): command_requested.emit(command))
	menu.oxygen_feedback_changed.connect(func(on): _panel.feedback_enabled=on)
	if economy != null: bind_models()
	_layout()
	_panel.update_context(false,-1,-1)
	_attach_presenters.call_deferred()

func _label(text: String, pixels: int, color := INK) -> Label:
	var label := Label.new();label.text = text
	label.add_theme_font_override("font",_font);label.add_theme_font_size_override("font_size",maxi(22,pixels))
	label.add_theme_color_override("font_color",color);label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _pill(dark := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new();style.bg_color = Color(0.15,0.19,0.19,0.68) if dark else Cozy.CREAM
	style.set_corner_radius_all(22);style.content_margin_left = 16;style.content_margin_right = 16
	style.content_margin_top = 10;style.content_margin_bottom = 10
	return style

func _plain_button(text: String, dark := false) -> Button:
	var button := Button.new();button.text=text
	button.add_theme_font_override("font",_font)
	Cozy.style_tree(button)
	if dark:
		for state in ["normal","hover","pressed"]:
			var style := Cozy.surface(Cozy.CREAM if state == "normal" else Cozy.GOLD,24)
			style.shadow_size=0
			button.add_theme_stylebox_override(state,style)
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state,Cozy.INK)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	return button

func _command_button(title: String, command: String, dark := false) -> Button:
	var button := _plain_button(title,dark)
	button.pressed.connect(func(): command_requested.emit(command))
	command_buttons[command] = button
	return button

func _layout() -> void:
	_layout_size = _root.size
	_world_actions.position=Vector2(40,_root.size.y-78)
	var extent: Vector2 = _panel.size
	var fit := minf(1.0,minf((_root.size.y-160)/extent.y,(_root.size.x-100)/extent.x))
	_base_position = Vector2((_root.size.x-extent.x)/2 if _panel.detail.visible else maxf(48,_root.size.x*0.13),(_root.size.y-extent.y)/2)
	_panel.position = _base_position;_panel.scale=Vector2.ONE*fit
	_hints.position=Vector2(_root.size.x-_hints.get_combined_minimum_size().x-40,_root.size.y-78)
	# 资源行放大了 2 倍，位置必须跟着字高走，否则会压到底部的「跟随/停止行动」。
	# 行高按 1.35em 估（圆体中文字面 + 上下留白），底边压在动作条上方 12px。
	var res_h: float = _res_label.get_theme_font_size("font_size")*1.35
	_res_label.position=Vector2(40,maxf(24,_root.size.y-90-res_h))
	# 潜水状态在潜水按钮排（y=88，高 52）下面一行。
	var dive_h: float = _dive_status.get_theme_font_size("font_size")*1.35
	_dive_status.position=Vector2(34,140+maxf(12,dive_h*0.2))
	_toast_box.size=Vector2(680,0)
	_layout_notice()
	_zoom.position=Vector2((_root.size.x-_zoom.get_combined_minimum_size().x)/2,_root.size.y-80)

func _layout_notice() -> void:
	_toast_box.position=Vector2((_root.size.x-680)/2,42 if _panel_open or _external_modal else _root.size.y-225)
	# 「海上的消息」这枚标签是骑在纸左上角上的（上半出纸、下半压纸）。
	# 纸比 `_toast_box` 外扩了 `Cozy.PAPER_OUTSET`，标签得跟着往外挪同样的量，
	# 否则它会整个漂到纸外面去 —— 纸放大了，骑边的装饰也得跟着纸走。
	_toast_tag.position=_toast_box.position+Vector2(24,-22)-Vector2(Cozy.PAPER_OUTSET,Cozy.PAPER_OUTSET)

func _attach_presenters() -> void:
	var adapter := preload("res://src/ui/island_presenters.gd").new()
	add_child(adapter);adapter.attach(self,presenter_sources)

func bind_presenters(views: Dictionary) -> void:
	menu.bind(self,views)

## `dim` 为 false 时仍然算「有面板挡着」（提示气泡、底部按钮照旧收起），
## 但不铺那层压暗 + 去色的屏幕遮罩。
##
## 单独一个开关是必须的：调色面板和取景面板的全部意义就是让人看清画面本身，
## 任何盖在 3D 上的半透明层都会改它下面每一个像素的色相与亮度 —— 在那上面
## 调出来的数值，一关面板就不成立。
func set_external_modal(on: bool, dim := true) -> void:
	if _external_modal == on and _external_dim == dim: return
	_external_modal=on
	_external_dim=dim
	_sync_backdrop()
	_hints.visible=on or _panel_open
	_launch.visible=not on and not _panel_open
	_world_actions.visible=not on and not _panel_open


## 遮罩的唯一开关点。`_toggle_panel` 也要走这里，否则两条路径各自改一次
## `visible`，谁最后写谁生效，P 面板关掉后代币卡片的遮罩会跟着消失。
func _sync_backdrop() -> void:
	var dim_external := _external_modal and _external_dim
	_backdrop.visible = dim_external or _panel_open
	if _backdrop.material != null:
		_backdrop.material.set_shader_parameter("strength", 1.0 if _backdrop.visible else 0.0)

func close_card() -> void:
	if _panel_open: _toggle_panel()

func back() -> void:
	if not _panel_open: return
	if not _history.is_empty():
		_tab=_history.pop_back();_refresh_panel();_layout()
	elif _panel.detail.visible:
		_tab="bag";_panel.show_grid(1);_layout()
	else: close_card()

func open_tab(tab: String) -> void:
	if _panel_open and tab != _tab and tab != "bag": _history.append(_tab)
	if tab == "bag": _history.clear();_panel.show_grid(0)
	_tab=tab
	if not _panel_open: _toggle_panel()
	else: _refresh_panel();_layout()

func _toggle_panel() -> void:
	_panel_open = not _panel_open
	if _open_tween: _open_tween.kill()
	_panel.visible = _panel_open
	_sync_backdrop()
	_hints.visible = _panel_open or _external_modal
	_launch.visible=not _panel_open and not _external_modal
	_world_actions.visible=_launch.visible
	if not _panel_open:
		_history.clear()
		return
	_refresh_panel();_layout()
	_panel.flush_arrivals()
	if not _backdrop.visible:
		return
	if not Cozy.motion_enabled:
		_backdrop.material.set_shader_parameter("strength",1.0)
		return
	var target_scale := _panel.scale
	_panel.position.y += 64;_panel.scale = target_scale*0.92
	_backdrop.material.set_shader_parameter("strength",0.0)
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_panel,"position",_base_position,0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_panel,"scale",target_scale,0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_method(func(value): _backdrop.material.set_shader_parameter("strength",value),0.0,1.0,0.22)

func _refresh_panel() -> void:
	if _tab_body == null: return
	if _tab == "bag":
		if _panel.detail.visible: _panel.show_grid(_panel.page)
		return
	for node in _tab_body.get_children():
		_tab_body.remove_child(node);node.queue_free()
	_build_rows.clear();_plant_rows.clear()
	_tab_body.add_theme_constant_override("separation",6 if _tab == "storage" else 12)
	match _tab:
		"plant": _panel.show_detail("种植日记");_refresh_plant()
		"build": _panel.show_detail("建造计划");_refresh_build()
		"storage": _panel.show_detail("背包与仓储");_refresh_storage()
		"map":
			_panel.show_detail("海风带你去哪里？")
			var atlas := preload("res://src/ui/island_atlas.gd").new();atlas.font=_font;atlas.zones=zones;atlas.game_state=game_state;_tab_body.add_child(atlas)
			_tab_body.add_child(_label("圆环是你的位置 · 选择一处泊位，准备出发。",16,DIM))
			for entry in DESTINATIONS:
				var unlocked: bool=zones.is_unlocked(entry.id)
				var button := _plain_button(entry.name + ("   ·   已在这里" if entry.id == game_state.current_zone else "   →") if unlocked else entry.name+"   ·   需要升级小船")
				button.disabled=not unlocked or _diving;_tab_body.add_child(button)
				button.pressed.connect(func(): _toggle_panel();destination_pressed.emit(entry.id))
		_:
			_panel.show_detail(ItemDBLib.label(_tab))
			var art := _item_tile(_tab,economy.count(_tab));art.mouse_filter=Control.MOUSE_FILTER_IGNORE;art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;_tab_body.add_child(art)
			var info := _label(str(ItemDBLib.get_item(_tab).get("desc","")),16)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;info.custom_minimum_size.x = 560;_tab_body.add_child(info)
			_tab_body.add_child(_label("持有 ×%d · 单价 %d 海贝" % [economy.count(_tab),ItemDBLib.sell_price(_tab)],15))
			if _crop_sale_ids().has(_tab):
				var sell := _plain_button("出售全部农产品")
				sell.disabled = economy.count(_tab) == 0
				sell.pressed.connect(func(): _farm_action(economy.farm.sell_produce));_tab_body.add_child(sell)
				var note := _label("会同时出售背包中的蔬菜、番茄和南瓜，
包含订单用料。",13,DIM);_tab_body.add_child(note)
			else:
				var trade := _plain_button("前往码头交易")
				trade.pressed.connect(func(): _toggle_panel();destination_pressed.emit("zone1"))
				_tab_body.add_child(trade)
				_tab_body.add_child(_label("在码头订单中交付，换取海贝。",14,DIM))
	_style_details(_tab_body)
	_layout()

func _crop_sale_ids() -> Array:
	var ids: Array = []
	if economy.farm != null:
		for crop in economy.farm.crop_definitions().values():
			for id in crop.get("yield",{}):
				if not ids.has(id): ids.append(id)
	return ids

func _style_details(node: Node) -> void:
	Cozy.style_tree(node)

func _activate(id: String) -> void:
	match id:
		"load": menu.show_menu("load")
		"plant","build","save","camera","grade": command_requested.emit(id)
		"water": command_requested.emit("plant")
		"hook": toast("打捞钩已随身携带 · 前往绞盘打捞站使用")
		"lamp","dive":
			if _panel_open: _toggle_panel()
			dive_pressed.emit()
		_: open_tab(id)

func _activate_selection() -> void:
	if _external_modal:
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is Button and focus.is_visible_in_tree() and not focus.disabled and not _hints.is_ancestor_of(focus):
			focus.pressed.emit()
		return
	if _panel.detail.visible or _panel.turning: return
	for tile in _panel.tiles.values():
		if tile.selected and tile.is_visible_in_tree():
			tile.pressed.emit();return

func _input(event: InputEvent) -> void:
	if menu and menu.active: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if _panel_open:
		if key == KEY_ESCAPE: return
		if key in [KEY_B,KEY_TAB]: _toggle_panel()
		elif key in [KEY_LEFT,KEY_RIGHT] and not _panel.detail.visible: _panel.flip(1-_panel.page)
		elif key == KEY_UP and not _panel.detail.visible: _panel.move_selection(-1)
		elif key == KEY_DOWN and not _panel.detail.visible: _panel.move_selection(1)
		elif key in [KEY_ENTER,KEY_SPACE] and not _panel.detail.visible: _activate_selection()
		elif key in [KEY_C,KEY_P]:
			command_requested.emit("camera" if key == KEY_C else "grade")
		elif key in [KEY_F5,KEY_F9]:
			if key == KEY_F5: command_requested.emit("save")
			else: menu.show_menu("load")
		else: return
		get_viewport().set_input_as_handled()
	elif key in [KEY_B,KEY_TAB]:
		command_requested.emit("bag");get_viewport().set_input_as_handled()

func toast(text: String, seconds := 2.4) -> void:
	if menu and menu.active:
		menu.note(text)
		return
	_toast.text = text;_toast_left = maxf(seconds,3.2 + text.length()/55.0);_toast_elapsed=0
	_toast.visible_characters=0 if Cozy.motion_enabled else -1
	_toast_box.reset_size();_layout_notice()
	_toast_box.visible = text != "";_toast_box.modulate.a = 1

func set_diving(on: bool) -> void:
	_diving = on;_dive_controls.visible = on;_dive_status.visible = on;_dive_btn.text = "上浮" if on else "潜水"
	if not on: _dive_zone = "";_depth = -1;_air_ratio = -1
	_panel.update_context(_diving,_air_ratio,_depth)

func set_dive_air(ratio: float, lamp_on: bool, found: int, total: int) -> void:
	_air_ratio = clampf(ratio,0,1);_lamp_on = lamp_on;_found = found;_found_total = total
	_panel.update_context(_diving,_air_ratio,_depth)
	_dive_status.text = "氧气 %d%% · 水深 %s · 头灯%s · 发现 %d/%d" % [roundi(_air_ratio*100),"%.0fm" % _depth if _depth >= 0 else "—","开" if lamp_on else "关",found,total]
	_dive_status.add_theme_color_override("font_color",air_color(_air_ratio) if _air_ratio <= 0.30 else Color.WHITE)

static func air_color(ratio: float) -> Color:
	if ratio <= 0.15: return Color("#D4573F")
	if ratio <= 0.30: return Color("#E08B4A")
	return Color("#4E9FC4")

func set_dive_zone(name: String) -> void:
	_dive_zone = name

func set_dive_depth(depth: float) -> void:
	_depth = depth
	_panel.update_context(_diving,_air_ratio,_depth)

func note_zoom(ratio: float) -> void:
	if not _diving:
		_zoom.text="  视野 %d%%  " % roundi(ratio*100)
		_zoom_left=1.2

## Read-only presentation snapshot for diagnostics; never exposes mutable owner state.
func presentation_snapshot() -> Dictionary:
	return {"open":_panel_open,"page":_panel.page,"diving":_diving,"depth":_depth,"oxygen":_air_ratio,"clock":"—","tide":"—","turning":_panel.turning}

func _refresh() -> void:
	if _res_label == null: return
	_res_label.text = "海贝 %d  ·  背包 %d / %d" % [economy.count("coins"),economy.inventory.slots_used(),economy.inventory.capacity()]
	for entry in _panel.harvest_specs:
		var id: String = entry[0]
		var count: int = economy.count(id)
		_panel.tiles[id].set_amount(count,_initialized_counts)
		if _initialized_counts and count > int(_counts.get(id,0)): _panel.fly_in(id)
		_counts[id] = count
	_initialized_counts = true
	if _panel_open and _tab != "bag": _refresh_panel()

func _process(delta: float) -> void:
	if _root.size != _layout_size: _layout()
	if _toast_left > 0:
		_toast_elapsed += delta
		_toast.visible_characters = int(_toast_elapsed*55) if Cozy.motion_enabled else -1
		_toast_left -= delta;_toast_box.modulate.a = clampf(_toast_left/0.9,0,1)
		if _toast_left <= 0: _toast_box.hide()
	_toast_tag.visible=_toast_box.visible and not menu.active
	_toast_tag.modulate=_toast_box.modulate
	_zoom_left=maxf(0,_zoom_left-delta)
	_zoom.visible=_zoom_left>0 and not _panel_open and not _external_modal and not menu.active
	_tick_build_rows();_tick_plant_rows()

func _item_tile(id: String, count: int) -> Button:
	var tile := preload("res://src/ui/ac_icon.gd").new()
	tile.font=_font;tile.kind=id;tile.caption=ItemDBLib.label(id)
	tile.tint=ItemDBLib.color(id).lerp(Cozy.CREAM,0.38)
	tile.amount=count;tile.shown_amount=count
	return tile

func _refresh_storage() -> void:
	_tab_body.add_child(_label("口袋里的宝贝   ·   %d / %d 格" % [economy.inventory.slots_used(),economy.inventory.capacity()],21))
	var selected_name := _label("选择一件随身物品",22,Cozy.CREAM)
	selected_name.set_meta("island_label",true)
	selected_name.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	var tag_style:=Cozy.surface(Cozy.TEAL,22);tag_style.content_margin_top=5;tag_style.content_margin_bottom=5
	selected_name.add_theme_stylebox_override("normal",tag_style)
	_tab_body.add_child(selected_name)
	var grid := GridContainer.new();grid.name="PocketSlots";grid.columns=8
	grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10)
	_tab_body.add_child(grid)
	for id in ItemDBLib.all_ids():
		if ItemDBLib.is_currency(id) or economy.count(id) <= 0: continue
		var remaining: int=economy.count(id)
		while remaining > 0:
			var count_in_slot:=mini(remaining,ItemDBLib.stack_limit(id))
			var item := _item_tile(id,count_in_slot);item.pocket=true;grid.add_child(item)
			item.tooltip_text=ItemDBLib.label(id)
			item.mouse_entered.connect(func(): selected_name.text=ItemDBLib.label(id))
			item.focus_entered.connect(func(): selected_name.text=ItemDBLib.label(id))
			item.pressed.connect(func(): open_tab(id))
			remaining-=count_in_slot
	for slot in maxi(0,economy.inventory.capacity()-grid.get_child_count()):
		var empty:=preload("res://src/ui/ac_icon.gd").new()
		empty.pocket=true;empty.empty_slot=true;empty.disabled=true;empty.focus_mode=Control.FOCUS_NONE
		empty.mouse_filter=Control.MOUSE_FILTER_IGNORE;grid.add_child(empty)

	# 货币单独一行：它不占格，但需要随时可见。
	var purse := _label("海贝  %d" % economy.coins, 12, INK)
	_tab_body.add_child(purse)
	var tip := _label("点击物件查看用途；建设材料可以存入仓库。", 10, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300, 0)
	_tab_body.add_child(tip)

	if economy.facility_unlocked("warehouse"):
		var deposit := _row("材料仓库 %d/48 格 · 建设自动取料" % economy.warehouse.slots_used(), "材料一键入库", true)
		deposit.button.pressed.connect(func() -> void: _farm_action(economy.deposit_materials))
		_tab_body.add_child(deposit.box)
		for item in economy.warehouse.all():
			var id := str(item)
			var row := _row("%s ×%d" % [ItemDBLib.label(id), economy.warehouse.count(id)], "取回背包", true)
			row.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return economy.withdraw_material(id)))
			_tab_body.add_child(row.box)
	else:
		var storage := _row("建造材料仓库，腾出背包空间", "前往建设", true)
		storage.button.pressed.connect(func() -> void: open_tab(TAB_BUILD))
		_tab_body.add_child(storage.box)


## 种植页：选作物 + 每块地的实时状态。
func _refresh_plant() -> void:
	_plant_rows.clear()
	if economy.farm == null: return
	var farm = economy.farm
	_tab_body.add_child(_label("第 %d 天 · 水壶 %d/%d · 海贝 %d" % [farm.day, farm.watering_can, farm.WATER_CAPACITY, economy.coins], 12, INK))
	var rest := _row("浇水后的地格在休息时生长一天", "休息到明天", true)
	rest.button.pressed.connect(func() -> void: rest_requested.emit())
	_tab_body.add_child(rest.box)
	var refill := _row("岸上补给 · 免费淡水", "补满水壶", true)
	refill.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.refill()))
	_tab_body.add_child(refill.box)
	var crops := HBoxContainer.new();crops.add_theme_constant_override("separation",16);_tab_body.add_child(crops)
	for crop_id in farm.crop_definitions():
		var crop: Dictionary=farm.crop_def(crop_id)
		var chosen := str(crop_id)
		var panel := PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var style := Cozy.surface(Color("#edf0d9"),24);style.shadow_size=0
		panel.add_theme_stylebox_override("panel",style);crops.add_child(panel)
		var row := VBoxContainer.new();row.add_theme_constant_override("separation",12);panel.add_child(row)
		var yield_id: String=str(crop.get("yield",{}).keys()[0])
		var select := _item_tile(yield_id,0);select.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		select.caption=str(crop.name);select.selected=farm.selected_crop==chosen
		select.pressed.connect(func(): farm.select_crop(chosen);_refresh_panel())
		row.add_child(select)
		var days := _label("%d 个浇水日" % int(crop.get("grow_days",0)),16);days.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;row.add_child(days)
		var seeds := _label("种子 ×%d" % economy.count(str(crop.seed)),15,DIM);seeds.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;row.add_child(seeds)
		var buy := _plain_button("购买 · %d贝" % int(crop.seed_price))
		buy.tooltip_text="购买"+str(crop.name)+"种子"
		buy.pressed.connect(func(): _farm_action(func() -> Dictionary: return farm.buy_seed(chosen)))
		row.add_child(buy)
	var sell := _row("出售背包内全部农产品（订单用料也会卖出）", "出售农产品", true)
	sell.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.sell_produce()))
	_tab_body.add_child(sell.box)
	if economy.count("seed") > 0:
		var exchange := _row("旧种子 ×%d" % economy.count("seed"), "换生菜种子", true)
		exchange.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.exchange_seed()))
		_tab_body.add_child(exchange.box)
	_tab_body.add_child(_label("选择种子后点地格操作；每天浇一次，缺水只停长。", 10, INK))
	for spec_row in farm.plot_specs():
		var id := str(spec_row.id)
		var line := _row(_plot_line(id), "前往操作", true)
		line.button.pressed.connect(func() -> void:
			_toggle_panel()
			plot_focus_requested.emit(id))
		_tab_body.add_child(line.box)
		_plant_rows[id] = {"info":line.label,"button":line.button}

func _farm_action(action: Callable) -> void:
	if game_state.mode != game_state.Mode.ASHORE:
		toast("请先上岸使用补给服务")
		return
	var result: Dictionary = action.call()
	toast(str(result.get("blocked",result.get("message","已完成"))))
	_refresh_panel()


## 种植页一行：菜箱名 + 状态（未解锁时说明前置）。
func _plot_line(id: String) -> String:
	var row: Dictionary = economy.farm.spec(id)
	var name := str(row.get("name", id))
	var reason: String = economy.farm.access_reason(id)
	if reason != "": return "%s · %s" % [name, reason]
	return "%s  %s" % [name, economy.farm.status_text(id)]


func _site_name(id: String) -> String:
	var spec: Dictionary = economy.SITES.get(id, {})
	return str(spec.get("name", id))


func _refresh_build() -> void:
	_build_rows.clear()
	var goal: Dictionary = economy.goal_info()
	var heading := _label("小目标 · " + str(goal.name), 14)
	_tab_body.add_child(heading)
	var progress := _label(economy.construction_progress(goal.cost), 12)
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress.custom_minimum_size.x = 560
	_tab_body.add_child(progress)
	_tab_body.add_child(_label("数量合计背包与仓库；建好后自动推荐下一目标。", 11))
	var source := _label("木料／缆绳：sea采集 · 零件／玻璃：横滨铁道\n海贝：农产品出售或码头交单；打捞也能补充木料与零件。", 11)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tab_body.add_child(source)
	for id in economy.SITES.keys():
		var row := _row(_site_line(id), "前往", true)
		row.button.pressed.connect(func():
			_toggle_panel()
			site_focus_requested.emit(id))
		_tab_body.add_child(row.box)
		_build_rows[id] = {"info": row.label, "button": row.button}
		_add_goal_button(str(id))
	var tip := _label("点击建造牌即可前往交付；走开也不会停工。",
		10, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300, 0)
	_tab_body.add_child(tip)

	for id in economy.FACILITIES.keys():
		var f: Dictionary = economy.FACILITIES[id]
		var built := economy.facility_unlocked(id)
		var requirement: String = economy.facility_requirement_text(id)
		var text := "%s  %s" % [f.name, "已建成" if built else economy.construction_progress(f.cost)]
		if requirement != "": text += "\n" + requirement
		text += "\n" + str(f.description)
		var row2 := _row(text, "建造" if not built else "—", not built and economy.can_build_facility(id))
		row2.button.pressed.connect(func(): facility_build_requested.emit(id))
		_tab_body.add_child(row2.box)
		_add_goal_button(str(id))

	var ship_text := "小船 Lv.%d · %s\n2 级开放远海与平台种植床；3 级航速提高 15%%" % [economy.ship_level, economy.construction_progress(economy.ship_cost()) if economy.ship_level < 3 else "满级"]
	var row3 := _row(ship_text, "升级", economy.can_upgrade_ship())
	row3.button.pressed.connect(func(): ship_upgrade_requested.emit())
	_tab_body.add_child(row3.box)
	_add_goal_button("ship" if economy.ship_level < 2 else "ship3")


## 建造页一行：等级 / 下一级费用 / 施工进度。
func _site_line(id: String) -> String:
	var spec: Dictionary = economy.SITES[id]
	var level := economy.site_level(id)
	if economy.is_building(id):
		return "%s  Lv.%d → 施工中 %d%%（剩 %ds）" % [
			spec.name, level,
			int(economy.site_work_progress(id) * 100.0),
			int(ceil(economy.site_work_left(id)))]
	if economy.site_maxed(id):
		return "%s  Lv.%d（满级）" % [spec.name, level]
	return "%s  Lv.%d → Lv.%d  %s" % [
		spec.name, level, level + 1, economy.construction_progress(economy.site_next_cost(id))]


func _cost_text(cost: Dictionary) -> String:
	return economy.cost_text(cost)


func _row(text: String, action: String, enabled: bool) -> Dictionary:
	var panel := PanelContainer.new()
	var style := Cozy.surface(Color("#f1ecd9"),22);style.shadow_size=0
	style.content_margin_left=20;style.content_margin_right=20;style.content_margin_top=16;style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	var box := HBoxContainer.new();box.add_theme_constant_override("separation",18);panel.add_child(box)
	var info := _label(text,17,INK);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x=330;info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_child(info)
	var button := _plain_button(action);button.custom_minimum_size.x=156;button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	button.disabled=not enabled;box.add_child(button)
	return {"box":panel,"button":button,"label":info}


## 种植页：只改文案，不重建（重建会丢按钮焦点、作物选择也会跳）。
func _tick_plant_rows() -> void:
	if not _panel_open or _tab != TAB_PLANT or _plant_rows.is_empty():
		return
	for id in _plant_rows.keys():
		var ref: Dictionary = _plant_rows[id]
		var text := _plot_line(str(id))
		if ref.info.text != text:
			ref.info.text = text


## 只有建造页打开时才刷新文案；不做整页重建，按钮焦点不会丢。
func _tick_build_rows() -> void:
	if not _panel_open or _tab != TAB_BUILD or _build_rows.is_empty():
		return
	for id in _build_rows.keys():
		var ref: Dictionary = _build_rows[id]
		var text := _site_line(id)
		if ref.info.text != text:
			ref.info.text = text
			var b: Button = ref.button
			b.text = "查看" if economy.is_building(id) else "前往"


func _add_goal_button(id: String) -> void:
	if economy.goal_complete(id): return
	var button := Button.new()
	button.text = "正在追踪" if str(economy.goal_info().id) == id else "设为小目标"
	button.disabled = str(economy.goal_info().id) == id
	button.pressed.connect(func() -> void: economy.track_goal(id))
	_tab_body.add_child(button)

func is_modal() -> bool:
	return _panel_open or _external_modal or (menu != null and menu.visible and get_tree().paused)

func refresh_after_restore() -> void:
	refresh_view()

func bind_models() -> void:
	if not economy.sites_changed.is_connected(_refresh_panel): economy.sites_changed.connect(_refresh_panel)
	if not economy.resources_changed.is_connected(_refresh): economy.resources_changed.connect(_refresh)
	_refresh()

## Public command/query boundary for scene composition and input routing.
func is_panel_open() -> bool: return _panel_open
func toggle_panel() -> void: _toggle_panel()
func refresh_view() -> void:
	_refresh()
	if _panel_open: _refresh_panel()
func toast_snapshot() -> Dictionary:
	return {"text":_toast.text if _toast != null else "none",
		"rect":_toast_box.get_global_rect() if _toast_box != null else Rect2(),
		"alpha":_toast_box.modulate.a if _toast_box != null else 0.0}
