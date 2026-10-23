extends CanvasLayer
class_name GameHUD
## 顶部 HUD / 目的地按钮 / 提示条，视觉对齐网页版 ui.css。

signal destination_pressed(zone_id: String)
signal dive_pressed
signal build_pressed
## 建造页的「前往」：走到建造牌并执行一次交付。
signal site_focus_requested(id: String)
## 种植页的「前往」：走到指定地格并执行一次操作。
signal plot_focus_requested(id: String)
signal command_requested(command: String)
signal rest_requested
signal facility_build_requested(id: String)
signal ship_upgrade_requested

const UiFontLib = preload("res://src/ui/ui_font.gd")
const ItemDBLib = preload("res://src/inventory/item_db.gd")

const DESTINATIONS := [
	{"id": "zone1", "icon": "🏡", "name": "sea"},
	{"id": "zone2", "icon": "🚃", "name": "横滨铁道"},
	{"id": "zone3", "icon": "🌱", "name": "圆弧农场"},
	{"id": "zone5", "icon": "🪷", "name": "浅水养殖"},
	{"id": "zone4", "icon": "🌊", "name": "远海街町"},
]

var _res_label: Label
var _toast: Label
## 提示条的药丸底：淡出改这个节点的 modulate（改 Label 的会和底色脱节）。
var _toast_box: PanelContainer
var _toast_left := 0.0
var _font: Font
var _root: Control
const SURFACE_HINT := "点目标去做事 · 拖动看风景"
const DIVE_HINT := "点水域游过去 · 点宝箱搜索 · 按钮调整深度 · 右键环视 · 上浮返回"

var _dive_label: Label
var _dive_zone := ""
## 左下的潜水仪表：氧气条 + 头灯 / 已发现宝箱。
var _dive_meter: PanelContainer
var _air_bar: ProgressBar
var _air_value: Label
var _dive_meta: Label
var _air_ratio := 1.0
var _lamp_on := true
var _found := 0
var _found_total := 0
## 低氧闪烁的相位。
var _dive_pulse := 0.0
var _hint_label: Label
## 缩放提示的剩余时间：滚轮/捏合时临时把缩放百分比显示在底部提示条里。
var _hint_left := 0.0
var _dive_btn: Button
var _diving := false
var _dive_controls: HBoxContainer
var command_buttons := {}
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _panel_open := false
var _tab_body: VBoxContainer
## 建造页每一行的实时引用：施工进度每帧都在变，重建整页会把按钮焦点也一起丢掉。
var _build_rows := {}
## 种植页每一行的实时引用（生长进度每帧都在变）。
var _plant_rows := {}
var _tab := "bag"
const TAB_BAG := "bag"
const TAB_BUILD := "build"
const TAB_PLANT := "plant"
const BackpackGridLib = preload("res://src/inventory/backpack_grid.gd")


func _ready() -> void:
	layer = 10
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"]))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_brand()
	_build_resources()
	_build_destinations()
	_build_hints()
	_build_toast()
	_build_panel()
	_build_dive_meter()
	Economy.sites_changed.connect(func(): _refresh_panel())
	Economy.resources_changed.connect(_refresh)
	_refresh()


func _panel_style(bg := Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.68),
		border := Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.38),
		radius := 13) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(4.0 / 255.0, 22.0 / 255.0, 58.0 / 255.0, 0.34)
	s.shadow_size = 10
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _btn_style(bg: Color, border: Color, radius := 9) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_brand() -> void:
	var brand := PanelContainer.new()
	brand.add_theme_stylebox_override("panel", _panel_style())
	brand.position = Vector2(14, 14)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(brand)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(hb)

	var dot := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color("#48f0c8")
	ds.set_corner_radius_all(5)
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(dot)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	vb.add_child(_label("sea", 13, Color("#ffffff")))
	vb.add_child(_label("一片小小水域，一段慢慢的生活", 10, Color(205.0 / 255.0, 238.0 / 255.0, 1.0, 0.85)))


func _build_resources() -> void:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _panel_style())
	pill.anchor_left = 1.0
	pill.anchor_right = 1.0
	pill.offset_left = -430
	pill.offset_right = -14
	pill.offset_top = 14
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pill)

	_res_label = _label("", 12)
	_res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(_res_label)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-880,64)
	_root.add_child(bar)
	for entry in [["follow","跟随中"],["bag","背包"],["plant","种植"],["build","建造"],["cancel","取消"],["save","保存"],["load","读档"],["camera","视角"],["grade","滤镜"]]:
		var button := _command_button(str(entry[1]),str(entry[0]))
		bar.add_child(button)
	_dive_controls = HBoxContainer.new()
	_dive_controls.position = Vector2(18,104)
	_root.add_child(_dive_controls)
	for entry in [["rise","上游 3 米"],["descend","下游 3 米"],["lamp","头灯开关"]]:
		_dive_controls.add_child(_command_button(str(entry[1]),str(entry[0])))
	_dive_controls.visible = false

func _command_button(title: String, command: String) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(70,34)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",_font)
	button.add_theme_font_size_override("font_size",13)
	button.add_theme_stylebox_override("normal",_btn_style(Color("#163c58"),Color("#558b99")))
	button.pressed.connect(func() -> void: command_requested.emit(command))
	command_buttons[command] = button
	return button

func open_tab(tab: String) -> void:
	_tab = tab
	if not _panel_open: _toggle_panel()
	else: _refresh_panel()


func _build_destinations() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -340
	bar.offset_right = 340
	bar.offset_top = -78
	bar.offset_bottom = -28
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(bar)

	for d in DESTINATIONS:
		var b := Button.new()
		b.add_theme_font_override("font",_font)
		b.text = str(d.icon) + " " + str(d.name)
		b.tooltip_text = d.name
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(110, 48)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_stylebox_override("normal", _btn_style(Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.68), Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.38), 23))
		b.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.82), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.7), 23))
		b.add_theme_stylebox_override("pressed", _btn_style(Color(40.0 / 255.0, 200.0 / 255.0, 180.0 / 255.0, 0.75), Color("#9affef"), 23))
		var zid: String = d.id
		b.pressed.connect(func(): destination_pressed.emit(zid))
		bar.add_child(b)


func _build_hints() -> void:
	var hint := PanelContainer.new()
	hint.add_theme_stylebox_override("panel", _panel_style(Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.65), Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.30), 11))
	hint.position = Vector2(14, 0)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -56
	hint.offset_bottom = -14
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint)
	_hint_label = _label("点一点，慢慢逛 · 拖动看风景", 13, Color(230.0 / 255.0, 247.0 / 255.0, 1.0, 0.92))
	hint.add_child(_hint_label)

	_dive_label = _label("区块名 · 深度 0.0 m", 11, Color(0.9, 0.99, 1.0, 0.0))
	_dive_label.anchor_left = 0.5
	_dive_label.anchor_right = 0.5
	_dive_label.anchor_top = 0.5
	_dive_label.anchor_bottom = 0.5
	_dive_label.offset_left = -140
	_dive_label.offset_right = 140
	_dive_label.offset_top = -220
	_dive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_dive_label)

	var dive := Button.new()
	_dive_btn = dive
	dive.text = "潜水"
	dive.add_theme_font_override("font", _font)
	dive.add_theme_font_size_override("font_size", 13)
	dive.add_theme_color_override("font_color", Color("#e9f8ff"))
	dive.add_theme_stylebox_override("normal", _panel_style(Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.75), Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.45), 12))
	dive.add_theme_stylebox_override("hover", _panel_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.9), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.8), 12))
	dive.anchor_left = 1.0
	dive.anchor_right = 1.0
	dive.anchor_top = 1.0
	dive.anchor_bottom = 1.0
	dive.offset_left = -96
	dive.offset_right = -14
	dive.offset_top = -56
	dive.offset_bottom = -14
	dive.pressed.connect(func(): dive_pressed.emit())
	_root.add_child(dive)


func _build_dive_meter() -> void:
	_dive_meter = PanelContainer.new()
	_dive_meter.name = "DiveMeter"
	_dive_meter.add_theme_stylebox_override("panel", _panel_style(
		Color(6.0 / 255.0, 26.0 / 255.0, 58.0 / 255.0, 0.74),
		Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.34), 12))
	_dive_meter.anchor_left = 0.0
	_dive_meter.anchor_right = 0.0
	_dive_meter.anchor_top = 1.0
	_dive_meter.anchor_bottom = 1.0
	_dive_meter.offset_left = 14
	_dive_meter.offset_right = 216
	# 高度按内容给：标题行 ~16 + 进度条 7 + 说明行 ~14 + 间距 6 + 内边距 16 ≈ 60。
	# 原先给 92，面板底下会空一大块。
	_dive_meter.offset_top = -136
	_dive_meter.offset_bottom = -72
	_dive_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 只在潜水时出现。字体色不透明，靠 visible 开关而不是 alpha。
	_dive_meter.visible = false
	_root.add_child(_dive_meter)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_dive_meter.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var caption := _label("氧气", 11, Color(0.86, 0.98, 1.0, 1.0))
	head.add_child(caption)
	_air_value = _label("100%", 11, Color(0.86, 0.98, 1.0, 1.0))
	_air_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_air_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_air_value)

	_air_bar = ProgressBar.new()
	_air_bar.min_value = 0.0
	_air_bar.max_value = 1.0
	_air_bar.value = 1.0
	_air_bar.show_percentage = false
	_air_bar.custom_minimum_size = Vector2(0, 7)
	_air_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(3.0 / 255.0, 18.0 / 255.0, 40.0 / 255.0, 0.85)
	track.set_corner_radius_all(4)
	_air_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = air_color(1.0)
	fill.set_corner_radius_all(4)
	_air_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_air_bar)

	_dive_meta = _label("头灯 开 (F)   ·   宝箱 0/5", 10, Color(0.84, 0.97, 1.0, 0.88))
	box.add_child(_dive_meta)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style(Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.9), Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.45), 14))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -530
	_panel.offset_right = -14
	_panel.offset_top = 122
	_panel.visible = false
	_root.add_child(_panel)

	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_panel_box)

	var close := _command_button("关闭", "close")
	_panel_box.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	_panel_box.add_child(tabs)
	for spec in [["背包", TAB_BAG], ["建造", TAB_BUILD], ["种植", TAB_PLANT]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", Color("#e9f8ff"))
		b.add_theme_stylebox_override("normal", _btn_style(Color(18.0 / 255.0, 52.0 / 255.0, 86.0 / 255.0, 0.5), Color(120.0 / 255.0, 200.0 / 255.0, 210.0 / 255.0, 0.18)))
		b.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.85), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.7)))
		b.custom_minimum_size = Vector2(58, 24)
		var tab_id := str(spec[1])
		b.pressed.connect(func() -> void:
			_tab = tab_id
			_refresh_panel())
		tabs.add_child(b)

	_tab_body = VBoxContainer.new()
	_tab_body.add_theme_constant_override("separation", 7)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_box.add_child(scroll)
	_tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tab_body)


func _toggle_panel() -> void:
	_panel_open = not _panel_open
	_panel.visible = _panel_open
	if _panel_open:
		_refresh_panel()


func _refresh_panel() -> void:
	if _tab_body == null:
		return
	for c in _tab_body.get_children():
		_tab_body.remove_child(c)
		c.queue_free()
	_tab_body.get_parent().scroll_vertical = 0
	if _tab == TAB_BAG:
		_refresh_bag()
	elif _tab == TAB_PLANT:
		_refresh_plant()
	else:
		_refresh_build()


func _refresh_bag() -> void:
	var grid := BackpackGridLib.new()
	_tab_body.add_child(grid)
	grid.setup(_font, Economy.inventory)

	# 货币单独一行：它不占格，但需要随时可见。
	var purse := _label("🪙 海贝 ×%d" % Economy.coins, 12, Color(0.96, 0.90, 0.66, 1.0))
	_tab_body.add_child(purse)
	var tip := _label("点击物件即可前往采集；建设材料可以存入仓库。", 10, Color(0.72, 0.86, 0.90, 0.75))
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
	_tab_body.add_child(_label("第 %d 天 · 水壶 %d/%d · 海贝 %d" % [farm.day, farm.watering_can, farm.WATER_CAPACITY, Economy.coins], 12, Color("#d6f1df")))
	var rest := _row("浇水后的地格在休息时生长一天", "休息到明天", true)
	rest.button.pressed.connect(func() -> void: rest_requested.emit())
	_tab_body.add_child(rest.box)
	var refill := _row("岸上补给 · 免费淡水", "补满水壶", true)
	refill.button.pressed.connect(func() -> void: _farm_action(func() -> Dictionary: return farm.refill()))
	_tab_body.add_child(refill.box)
	for crop_id in farm.crops:
		var crop: Dictionary = farm.crops[crop_id]
		var chosen := str(crop_id)
		var row := HBoxContainer.new()
		var select := Button.new()
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
	_tab_body.add_child(_label("选择种子后点地格操作；每天浇一次，缺水只停长。", 10, Color("#d6f1df")))
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
	progress.custom_minimum_size.x = 440
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
		10, Color(0.72, 0.86, 0.90, 0.75))
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
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var l := _label(text, 11, Color(0.92, 0.98, 1.0, 0.95))
	l.custom_minimum_size = Vector2(285, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	var b := Button.new()
	b.text = action
	b.disabled = not enabled
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color("#e9f8ff"))
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.85, 0.9, 0.45))
	b.add_theme_stylebox_override("normal", _btn_style(Color(22.0 / 255.0, 62.0 / 255.0, 120.0 / 255.0, 0.72), Color(132.0 / 255.0, 226.0 / 255.0, 236.0 / 255.0, 0.34)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.9), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.8)))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(20.0 / 255.0, 36.0 / 255.0, 62.0 / 255.0, 0.5), Color(120.0 / 255.0, 160.0 / 255.0, 180.0 / 255.0, 0.2)))
	box.add_child(b)
	return {"box": box, "button": b, "label": l}


func _build_toast() -> void:
	# 提示条压在场景上：单独的白字在浅色甲板上根本看不清，
	# 所以包一层深色药丸底，位置也从 72% 抬到底部提示条上方。
	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel",
		_panel_style(Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.72),
			Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.30), 12))
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.anchor_top = 1.0
	_toast_box.anchor_bottom = 1.0
	_toast_box.offset_top = -140
	_toast_box.offset_bottom = -102
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	_toast_box.visible = false
	_root.add_child(_toast_box)

	# 字体色 alpha 必须是 1：淡出交给 modulate 做。
	# 这里原来写的是 alpha=0，toast() 只改 modulate.a，
	# 结果所有提示（采集/建造/航行/存档）在画面上从来没出现过。
	_toast = _label("", 14, Color(0.96, 1.0, 0.99, 1.0))
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_box.add_child(_toast)


func toast(text: String, seconds := 2.4) -> void:
	_toast.text = text
	_toast_left = maxf(seconds,3.2)
	if _toast_box != null:
		_toast_box.modulate.a = 1.0
		# 有内容才占位：空字符串时药丸底色会变成一小块深色斑。
		_toast_box.visible = text != ""
		load("res://src/ui/cozy_ui.gd").reveal(_toast_box)


func set_diving(on: bool) -> void:
	_diving = on
	_dive_controls.visible = on
	for command in ["follow","bag","plant","build","camera","grade","save","load"]:
		command_buttons[command].disabled = on
	if on and _panel_open: _toggle_panel()
	# 深度标签的字体颜色 alpha 是 0，只改 modulate 是看不见的，必须改字体色本身。
	_dive_label.add_theme_color_override("font_color", Color(0.90, 0.99, 1.0, 1.0 if on else 0.0))
	if _hint_label != null:
		_hint_label.text = DIVE_HINT if on else SURFACE_HINT
	if not on:
		_dive_zone = ""
	_dive_btn.text = "上浮" if on else "潜水"
	if not on:
		_dive_label.text = ""
	if _dive_meter != null:
		_dive_meter.visible = on


## 潜水仪表：氧气条随余量变色，低于告警线时整条闪烁提醒。
func set_dive_air(ratio: float, lamp_on: bool, found: int, total: int) -> void:
	_air_ratio = clampf(ratio, 0.0, 1.0)
	_lamp_on = lamp_on
	_found = found
	_found_total = total
	if _air_bar == null:
		return
	_air_bar.value = _air_ratio
	var fill := StyleBoxFlat.new()
	fill.bg_color = air_color(_air_ratio)
	fill.set_corner_radius_all(4)
	_air_bar.add_theme_stylebox_override("fill", fill)
	_air_value.text = "%d%%" % int(round(_air_ratio * 100.0))
	_air_value.add_theme_color_override("font_color", air_color(_air_ratio))
	_dive_meta.text = "头灯 %s (F)   ·   宝箱 %d/%d" % [
		"开" if _lamp_on else "关", _found, _found_total]


static func air_color(ratio: float) -> Color:
	if ratio <= 0.15:
		return Color(1.0, 0.42, 0.38, 0.95)
	if ratio <= 0.35:
		return Color(1.0, 0.78, 0.35, 0.95)
	return Color(0.46, 0.95, 0.86, 0.95)


func set_dive_zone(name: String) -> void:
	_dive_zone = name
	if _diving and _dive_zone != "":
		_dive_label.text = "%s · 深度 %.1f m" % [_dive_zone, GameState.dive_depth]


func set_dive_depth(depth: float) -> void:
	GameState.dive_depth = depth
	if not _diving:
		return
	var where := _dive_zone if _dive_zone != "" else Zones.label(GameState.current_zone)
	_dive_label.text = "%s · 深度 %.1f m" % [where, depth]


## 缩放时的即时反馈（滚轮/捏合都会调）。用底部提示条，不额外占屏幕。
func note_zoom(ratio: float) -> void:
	if _hint_label == null or _diving:
		return
	_hint_label.text = "缩放 %d%%   ·   %s" % [int(round(ratio * 100.0)), SURFACE_HINT]
	_hint_left = 1.2


func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0 and _hint_label != null and not _diving:
			_hint_label.text = SURFACE_HINT
	if _toast_left > 0.0:
		_toast_left -= delta
		var a := clampf(_toast_left / 0.9, 0.0, 1.0)
		# 淡出要作用在药丸底上，只改 Label 会留下一个空的深色块。
		_toast_box.modulate.a = a
		if _toast_left <= 0.0:
			_toast_box.visible = false
	_tick_build_rows()
	_tick_plant_rows()
	_tick_dive_meter(delta)


## 氧气见底时整块仪表呼吸式闪烁：画面很花的海底，静态变色不够醒目。
func _tick_dive_meter(delta: float) -> void:
	if _dive_meter == null or not _dive_meter.visible:
		return
	_dive_pulse += delta
	if _air_ratio > 0.15:
		_dive_meter.modulate.a = 1.0
		return
	_dive_meter.modulate.a = 0.62 + 0.38 * (0.5 + 0.5 * sin(_dive_pulse * 2.5))


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


func _refresh() -> void:
	if _res_label == null:
		return
	if _panel_open:
		_refresh_panel()
	# 顶部只放「货币 + 手里最多的 4 样」，其余靠背包面板。
	# 图标与名称来自物品表，加新物品不用改这里。
	var parts: Array = []
	parts.append("%s %d" % [ItemDBLib.icon("coins"), Economy.coins])
	var owned: Array = []
	for id in ItemDBLib.all_ids():
		if ItemDBLib.is_currency(id):
			continue
		if Economy.count(id) > 0:
			owned.append(id)
	owned.sort_custom(func(a: String, b: String) -> bool:
		return Economy.count(a) > Economy.count(b))
	for id in owned.slice(0, 4):
		parts.append("%s %d" % [ItemDBLib.icon(id), Economy.count(id)])
	if owned.size() > 4:
		parts.append("+%d" % (owned.size() - 4))
	parts.append("⛵ %d" % Economy.ship_level)
	var line1 := "      ".join(parts.slice(0, 3))
	var line2 := "      ".join(parts.slice(3)) if parts.size() > 3 else ""
	_res_label.text = line1 if line2 == "" else line1 + "\n" + line2


func _add_goal_button(id: String) -> void:
	if Economy.goal_complete(id): return
	var button := Button.new()
	button.text = "正在追踪" if str(Economy.goal_info().id) == id else "设为小目标"
	button.disabled = str(Economy.goal_info().id) == id
	button.pressed.connect(func() -> void: Economy.track_goal(id))
	_tab_body.add_child(button)
