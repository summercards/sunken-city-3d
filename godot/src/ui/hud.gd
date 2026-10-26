extends CanvasLayer
class_name GameHUD
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
const BackpackGridLib = preload("res://src/inventory/backpack_grid.gd")
const Card = preload("res://src/ui/ac_card.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
const INK := Color("#3B3026")
const DIM := Color("#8A7A66")
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

func _ready() -> void:
	layer = 60
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
	var launch := HBoxContainer.new();launch.position = Vector2(32,30);launch.add_theme_constant_override("separation",10)
	_root.add_child(launch)
	var bag := _plain_button("▤  随身手册",true);launch.add_child(bag)
	bag.pressed.connect(func():
		if _panel_open: _toggle_panel()
		else: command_requested.emit("bag"))
	command_buttons.bag = bag
	_dive_btn = _plain_button("潜水",true);launch.add_child(_dive_btn)
	_dive_btn.pressed.connect(func(): dive_pressed.emit())
	for entry in [["follow","跟随"],["cancel","停止"]]:
		var button := _command_button(entry[1],entry[0],true);launch.add_child(button)
	_res_label = _label("",15,Color.WHITE);_res_label.position = Vector2(34,931);_root.add_child(_res_label)
	_dive_controls = HBoxContainer.new();_dive_controls.position = Vector2(32,88);_dive_controls.add_theme_constant_override("separation",8)
	_root.add_child(_dive_controls)
	for entry in [["rise","↑ 上游"],["descend","↓ 下游"],["lamp","头灯"]]: _dive_controls.add_child(_command_button(entry[1],entry[0],true))
	_dive_controls.hide()
	_hints = HBoxContainer.new();_hints.add_theme_constant_override("separation",12);_root.add_child(_hints)
	var close := _plain_button("Ⓑ  收起  Esc",true);close.pressed.connect(func():
		if _panel_open: _toggle_panel())
	command_buttons.close = close;_hints.add_child(close)
	var select := _plain_button("Ⓐ  选择  Enter",true);select.pressed.connect(_activate_selection);_hints.add_child(select);_hints.hide()
	_toast_box = PanelContainer.new();_toast_box.add_theme_stylebox_override("panel",_pill(true));_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box);_toast_box.hide();_toast = _label("",15,Color.WHITE);_toast_box.add_child(_toast)
	Economy.sites_changed.connect(_refresh_panel)
	Economy.resources_changed.connect(_refresh)
	_refresh();_layout()

func _label(text: String, pixels: int, color := INK) -> Label:
	var label := Label.new();label.text = text
	label.add_theme_font_override("font",_font);label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color);label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _pill(dark := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new();style.bg_color = Color(0.15,0.19,0.19,0.68) if dark else Cozy.CREAM
	style.set_corner_radius_all(22);style.content_margin_left = 16;style.content_margin_right = 16
	style.content_margin_top = 10;style.content_margin_bottom = 10
	return style

func _plain_button(text: String, dark := false) -> Button:
	var button := Button.new();button.text = text;button.custom_minimum_size.y = 40
	button.add_theme_font_override("font",_font);button.add_theme_font_size_override("font_size",14)
	for state in ["normal","hover","pressed","disabled"]: button.add_theme_stylebox_override(state,_pill(dark))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state,Color.WHITE if dark else INK)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

func _command_button(title: String, command: String, dark := false) -> Button:
	var button := _plain_button(title,dark)
	button.pressed.connect(func(): command_requested.emit(command))
	command_buttons[command] = button
	return button

func _layout() -> void:
	_layout_size = _root.size
	var fit := minf(1.0,minf((_root.size.y-120)/620,(_root.size.x-64)/420))
	_base_position = Vector2(maxf(32,_root.size.x*0.10),maxf(88,(_root.size.y-620*fit)/2))
	_panel.position = _base_position;_panel.scale = Vector2.ONE*fit
	_hints.position = Vector2(_root.size.x-370,_root.size.y-76)
	_res_label.position = Vector2(34,_root.size.y-63)
	_toast_box.position = Vector2(_root.size.x/2-160,_root.size.y-135)

func open_tab(tab: String) -> void:
	_tab = tab
	if not _panel_open: _toggle_panel()
	else: _refresh_panel()

func _toggle_panel() -> void:
	_panel_open = not _panel_open
	if _open_tween: _open_tween.kill()
	_panel.visible = _panel_open;_backdrop.visible = _panel_open;_hints.visible = _panel_open
	if not _panel_open: return
	_refresh_panel();_layout()
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
		_panel.show_grid(0)
		return
	for node in _tab_body.get_children():
		_tab_body.remove_child(node);node.queue_free()
	_build_rows.clear();_plant_rows.clear()
	match _tab:
		"plant": _panel.show_detail("种植日记");_refresh_plant()
		"build": _panel.show_detail("建造计划");_refresh_build()
		"storage": _panel.show_detail("背包与仓储");_refresh_storage()
		"map":
			_panel.show_detail("航海图")
			for entry in DESTINATIONS:
				var button := _plain_button(entry.name);_tab_body.add_child(button)
				button.pressed.connect(func(): _toggle_panel();destination_pressed.emit(entry.id))
		_:
			_panel.show_detail(ItemDBLib.label(_tab))
			var info := _label(str(ItemDBLib.get_item(_tab).get("desc","")),16)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;info.custom_minimum_size.x = 310;_tab_body.add_child(info)
			_tab_body.add_child(_label("持有 ×%d · 单价 %d 海贝" % [Economy.count(_tab),ItemDBLib.sell_price(_tab)],15))
			if ItemDBLib.get_item(_tab).get("category") == "produce":
				var sell := _plain_button("出售全部农产品")
				sell.disabled = Economy.count(_tab) == 0
				sell.pressed.connect(func(): _farm_action(Economy.farm.sell_produce));_tab_body.add_child(sell)
				var note := _label("会同时出售背包中的鱼、蔬菜、番茄和南瓜，
包含订单用料。",13,DIM);_tab_body.add_child(note)
			else: _tab_body.add_child(_label("可用于码头交易订单",14,DIM))
	_style_details(_tab_body)

func _style_details(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color",INK)
		node.add_theme_font_size_override("font_size",14)
	elif node is Button:
		node.add_theme_font_override("font",_font)
		node.add_theme_font_size_override("font_size",14)
		node.add_theme_stylebox_override("normal",_pill())
		for state in ["font_color","font_hover_color","font_pressed_color"]: node.add_theme_color_override(state,INK)
	elif node is PanelContainer:
		node.add_theme_stylebox_override("panel",_pill())
	for child in node.get_children(): _style_details(child)

func _activate(id: String) -> void:
	match id:
		"plant","build","save","load","camera","grade": command_requested.emit(id)
		"water": command_requested.emit("plant")
		"hook": toast("打捞钩已随身携带 · 前往绞盘打捞站使用")
		"lamp","dive":
			if _panel_open: _toggle_panel()
			dive_pressed.emit()
		_: open_tab(id)

func _activate_selection() -> void:
	if _panel.detail.visible: return
	for tile in _panel.tiles.values():
		if tile.selected and tile.is_visible_in_tree():
			tile.pressed.emit();return

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if _panel_open:
		if key in [KEY_ESCAPE,KEY_B,KEY_TAB]: _toggle_panel()
		elif key in [KEY_LEFT,KEY_RIGHT]: _panel.flip(1-_panel.page)
		elif key in [KEY_ENTER,KEY_SPACE]: _activate_selection()
		else: return
		get_viewport().set_input_as_handled()
	elif _diving and key in [KEY_B,KEY_TAB]:
		open_tab("bag");get_viewport().set_input_as_handled()

func toast(text: String, seconds := 2.4) -> void:
	_toast.text = text;_toast_left = maxf(seconds,3.2)
	_toast_box.visible = text != "";_toast_box.modulate.a = 1

func set_diving(on: bool) -> void:
	_diving = on;_dive_controls.visible = on;_dive_btn.text = "上浮" if on else "潜水"
	if not on: _dive_zone = "";_depth = -1;_air_ratio = -1
	_panel.update_context(_diving,_air_ratio,_depth)

func set_dive_air(ratio: float, lamp_on: bool, found: int, total: int) -> void:
	_air_ratio = clampf(ratio,0,1);_lamp_on = lamp_on;_found = found;_found_total = total
	_panel.update_context(_diving,_air_ratio,_depth)

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
	if not _diving: toast("缩放 %d%%" % roundi(ratio*100),1.2)

## Read-only presentation snapshot for diagnostics; never exposes mutable owner state.
func presentation_snapshot() -> Dictionary:
	return {"open":_panel_open,"page":_panel.page,"diving":_diving,"depth":_depth,"oxygen":_air_ratio,"clock":"—","tide":"—","turning":_panel.turning}

func _refresh() -> void:
	if _res_label == null: return
	_res_label.text = "海贝 %d  ·  背包 %d / %d" % [Economy.count("coins"),Economy.inventory.slots_used(),Economy.inventory.capacity()]
	for entry in _panel.harvest_specs:
		var id: String = entry[0]
		var count: int = Economy.count(id)
		_panel.tiles[id].set_amount(count,_initialized_counts)
		if _initialized_counts and count > int(_counts.get(id,0)): _panel.fly_in(id)
		_counts[id] = count
	_initialized_counts = true
	if _panel_open and _tab != "bag": _refresh_panel()

func _process(delta: float) -> void:
	if _root.size != _layout_size: _layout()
	if _toast_left > 0:
		_toast_left -= delta;_toast_box.modulate.a = clampf(_toast_left/0.9,0,1)
		if _toast_left <= 0: _toast_box.hide()
	_tick_build_rows();_tick_plant_rows()

func _refresh_storage() -> void:
	var grid := BackpackGridLib.new()
	_tab_body.add_child(grid)
	grid.setup(_font, Economy.inventory)

	# 货币单独一行：它不占格，但需要随时可见。
	var purse := _label("🪙 海贝 ×%d" % Economy.coins, 12, INK)
	_tab_body.add_child(purse)
	var tip := _label("点击物件即可前往采集；建设材料可以存入仓库。", 10, DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300, 0)
	_tab_body.add_child(tip)

	if Economy.facility_unlocked("warehouse"):
		var deposit := _row("材料仓库 %d/48 格 · 建设自动取料" % Economy.warehouse.slots_used(), "材料一键入库", true)
		deposit.button.pressed.connect(func() -> void: _farm_action(Economy.deposit_materials))
		_tab_body.add_child(deposit.box)
		for item in Economy.warehouse.all():
			var id := str(item)
			var row := _row("%s ×%d" % [ItemDBLib.label(id), Economy.warehouse.count(id)], "取回背包", true)
			row.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return Economy.withdraw_material(id)))
			_tab_body.add_child(row.box)
	else:
		var storage := _row("建造材料仓库，腾出背包空间", "前往建设", true)
		storage.button.pressed.connect(func() -> void: open_tab(TAB_BUILD))
		_tab_body.add_child(storage.box)


## 种植页：选作物 + 每块地的实时状态。
func _refresh_plant() -> void:
	_plant_rows.clear()
	if Economy.farm == null: return
	var farm = Economy.farm
	_tab_body.add_child(_label("第 %d 天 · 水壶 %d/%d · 海贝 %d" % [farm.day, farm.watering_can, farm.WATER_CAPACITY, Economy.coins], 12, INK))
	var rest := _row("浇水后的地格在休息时生长一天", "休息到明天", true)
	rest.button.pressed.connect(func() -> void: rest_requested.emit())
	_tab_body.add_child(rest.box)
	var refill := _row("岸上补给 · 免费淡水", "补满水壶", true)
	refill.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.refill()))
	_tab_body.add_child(refill.box)
	for crop_id in farm.crops:
		var crop: Dictionary = farm.crops[crop_id]
		var chosen := str(crop_id)
		var row := VBoxContainer.new()
		var select := Button.new()
		select.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		select.text = ("✓ " if farm.selected_crop == chosen else "") + str(crop.name) + " · 种子 %d" % Economy.count(str(crop.seed))
		select.add_theme_font_override("font", _font)
		select.add_theme_font_size_override("font_size", 12)
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.pressed.connect(func() -> void:
			farm.select_crop(chosen)
			_refresh_panel())
		row.add_child(select)
		var buy := Button.new()
		buy.add_theme_font_override("font", _font)
		buy.add_theme_font_size_override("font_size", 12)
		buy.text = "买 1 包 · %d 贝" % int(crop.seed_price)
		buy.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.buy_seed(chosen)))
		row.add_child(buy)
		_tab_body.add_child(row)
	var sell := _row("出售背包内全部农产品（订单用料也会卖出）", "出售农产品", true)
	sell.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.sell_produce()))
	_tab_body.add_child(sell.box)
	if Economy.count("seed") > 0:
		var exchange := _row("旧种子 ×%d" % Economy.count("seed"), "换生菜种子", true)
		exchange.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.exchange_seed()))
		_tab_body.add_child(exchange.box)
	_tab_body.add_child(_label("选择种子后点地格操作；每天浇一次，缺水只停长。", 10, INK))
	for spec_row in farm.specs:
		var id := str(spec_row.id)
		var line := _row(_plot_line(id), "前往操作", true)
		line.button.pressed.connect(func() -> void:
			_toggle_panel()
			plot_focus_requested.emit(id))
		_tab_body.add_child(line.box)
		_plant_rows[id] = {"info":line.label,"button":line.button}

func _farm_action(action: Callable) -> void:
	if GameState.mode != GameState.Mode.ASHORE:
		toast("请先上岸使用补给服务")
		return
	var result: Dictionary = action.call()
	toast(str(result.get("blocked",result.get("message","已完成"))))
	_refresh_panel()


## 种植页一行：菜箱名 + 状态（未解锁时说明前置）。
func _plot_line(id: String) -> String:
	var row: Dictionary = Economy.farm.spec(id)
	var name := str(row.get("name", id))
	var reason: String = Economy.farm._access_reason(id)
	if reason != "": return "%s · %s" % [name, reason]
	return "%s  %s" % [name, Economy.farm.status_text(id)]


func _site_name(id: String) -> String:
	var spec: Dictionary = Economy.SITES.get(id, {})
	return str(spec.get("name", id))


func _refresh_build() -> void:
	_build_rows.clear()
	var goal: Dictionary = Economy.goal_info()
	var heading := _label("小目标 · " + str(goal.name), 14)
	_tab_body.add_child(heading)
	var progress := _label(Economy.construction_progress(goal.cost), 12)
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress.custom_minimum_size.x = 310
	_tab_body.add_child(progress)
	_tab_body.add_child(_label("数量合计背包与仓库；建好后自动推荐下一目标。", 11))
	var source := _label("木料／缆绳：sea采集 · 零件／玻璃：横滨铁道\n海贝：农产品出售或码头交单；打捞也能补充木料与零件。", 11)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tab_body.add_child(source)
	for id in Economy.SITES.keys():
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

	for id in Economy.FACILITIES.keys():
		var f: Dictionary = Economy.FACILITIES[id]
		var built := Economy.facility_unlocked(id)
		var requirement: String = Economy.facility_requirement_text(id)
		var text := "%s  %s" % [f.name, "已建成" if built else Economy.construction_progress(f.cost)]
		if requirement != "": text += "\n" + requirement
		text += "\n" + str(f.description)
		var row2 := _row(text, "建造" if not built else "—", not built and Economy.can_build_facility(id))
		row2.button.pressed.connect(func(): facility_build_requested.emit(id))
		_tab_body.add_child(row2.box)
		_add_goal_button(str(id))

	var ship_text := "小船 Lv.%d · %s\n2 级开放远海与平台种植床；3 级航速提高 15%%" % [Economy.ship_level, Economy.construction_progress(Economy.ship_cost()) if Economy.ship_level < 3 else "满级"]
	var row3 := _row(ship_text, "升级", Economy.can_upgrade_ship())
	row3.button.pressed.connect(func(): ship_upgrade_requested.emit())
	_tab_body.add_child(row3.box)
	_add_goal_button("ship" if Economy.ship_level < 2 else "ship3")


## 建造页一行：等级 / 下一级费用 / 施工进度。
func _site_line(id: String) -> String:
	var spec: Dictionary = Economy.SITES[id]
	var level := Economy.site_level(id)
	if Economy.is_building(id):
		return "%s  Lv.%d → 施工中 %d%%（剩 %ds）" % [
			spec.name, level,
			int(Economy.site_work_progress(id) * 100.0),
			int(ceil(Economy.site_work_left(id)))]
	if Economy.site_maxed(id):
		return "%s  Lv.%d（满级）" % [spec.name, level]
	return "%s  Lv.%d → Lv.%d  %s" % [
		spec.name, level, level + 1, Economy.construction_progress(Economy.site_next_cost(id))]


func _cost_text(cost: Dictionary) -> String:
	return Economy.cost_text(cost)


func _row(text: String, action: String, enabled: bool) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",6)
	var info := _label(text,14,INK)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 310
	box.add_child(info)
	var button := _plain_button(action)
	button.disabled = not enabled
	box.add_child(button)
	return {"box":box,"button":button,"label":info}


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
			b.text = "查看" if Economy.is_building(id) else "前往"


func _add_goal_button(id: String) -> void:
	if Economy.goal_complete(id): return
	var button := Button.new()
	button.text = "正在追踪" if str(Economy.goal_info().id) == id else "设为小目标"
	button.disabled = str(Economy.goal_info().id) == id
	button.pressed.connect(func() -> void: Economy.track_goal(id))
	_tab_body.add_child(button)
