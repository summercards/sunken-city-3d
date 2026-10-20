extends CanvasLayer
class_name GameHUD
## 顶部 HUD / 目的地按钮 / 提示条，视觉对齐网页版 ui.css。

signal destination_pressed(zone_id: String)
signal dive_pressed
signal build_pressed
## 建造页的「前往」：把镜头挪到该建造点，真正施工要在世界里按 E。
signal site_focus_requested(id: String)
## 种植页的「前往」：把镜头挪到菜箱。
signal plot_focus_requested(id: String)
signal facility_build_requested(id: String)
signal ship_upgrade_requested

const ItemDBLib = preload("res://scripts/core/item_db.gd")

const DESTINATIONS := [
	{"id": "zone1", "icon": "🏡", "name": "晴空水巷"},
	{"id": "zone2", "icon": "🚃", "name": "横滨铁道"},
	{"id": "zone3", "icon": "🌱", "name": "圆弧农场"},
	{"id": "zone5", "icon": "🪷", "name": "浅水养殖"},
	{"id": "zone4", "icon": "🌊", "name": "远海街町"},
]

var _res_label: Label
var _toast: Label
var _toast_left := 0.0
var _font: SystemFont
var _root: Control
const SURFACE_HINT := "左键拖动 平移   ·   右键拖动 旋转   ·   滚轮 缩放   ·   点水面开船   ·   C 相机 · P 滤镜"
const DIVE_HINT := "WASD 游动   ·   E 上浮   ·   Q 下潜   ·   右键拖拽环视   ·   滚轮拉远   ·   点宝箱游过去"

var _dive_label: Label
var _dive_zone := ""
var _hint_label: Label
## 缩放提示的剩余时间：滚轮/捏合时临时把缩放百分比显示在底部提示条里。
var _hint_left := 0.0
var _dive_btn: Button
var _diving := false
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
const BackpackGridLib = preload("res://scripts/ui/backpack_grid.gd")


func _ready() -> void:
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"])
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
	vb.add_child(_label("晴空水巷", 13, Color("#ffffff")))
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

	var build := Button.new()
	build.text = "物资 / 建造"
	build.add_theme_font_override("font", _font)
	build.add_theme_font_size_override("font_size", 11)
	build.add_theme_color_override("font_color", Color("#e9f8ff"))
	build.add_theme_stylebox_override("normal", _btn_style(Color(22.0 / 255.0, 62.0 / 255.0, 120.0 / 255.0, 0.58), Color(132.0 / 255.0, 226.0 / 255.0, 236.0 / 255.0, 0.28)))
	build.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 114.0 / 255.0, 192.0 / 255.0, 0.82), Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.7)))
	build.anchor_left = 1.0
	build.anchor_right = 1.0
	build.offset_left = -134
	build.offset_right = -14
	build.offset_top = 64
	build.offset_bottom = 92
	build.pressed.connect(_toggle_panel)
	_root.add_child(build)


func _build_destinations() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -145
	bar.offset_right = 145
	bar.offset_top = -78
	bar.offset_bottom = -28
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(bar)

	for d in DESTINATIONS:
		var b := Button.new()
		b.text = d.icon
		b.tooltip_text = d.name
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(46, 46)
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
	_hint_label = _label(SURFACE_HINT, 11, Color(230.0 / 255.0, 247.0 / 255.0, 1.0, 0.92))
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


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style(Color(8.0 / 255.0, 28.0 / 255.0, 64.0 / 255.0, 0.9), Color(118.0 / 255.0, 235.0 / 255.0, 220.0 / 255.0, 0.45), 14))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -392
	_panel.offset_right = -14
	_panel.offset_top = 104
	_panel.visible = false
	_root.add_child(_panel)

	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_panel_box)

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
	_panel_box.add_child(_tab_body)


func _toggle_panel() -> void:
	_panel_open = not _panel_open
	_panel.visible = _panel_open
	if _panel_open:
		_refresh_panel()


func _refresh_panel() -> void:
	if _tab_body == null:
		return
	for c in _tab_body.get_children():
		c.queue_free()
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
	var tip := _label("采集按 E 长按；背包装满后产出会被丢弃。", 10, Color(0.72, 0.86, 0.90, 0.75))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300, 0)
	_tab_body.add_child(tip)


## 种植页：选作物 + 每块地的实时状态。
func _refresh_plant() -> void:
	_plant_rows.clear()
	if Economy.farm == null:
		_tab_body.add_child(_label("种植系统未就绪", 11, Color(1, 0.8, 0.6)))
		return

	var head := _label("播种用哪种作物", 10, Color(0.72, 0.86, 0.90, 0.8))
	_tab_body.add_child(head)

	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 4)
	_tab_body.add_child(picker)
	for crop_id in Economy.farm.crops.keys():
		var crop: Dictionary = Economy.farm.crops[crop_id]
		var b := Button.new()
		b.text = "%s %s" % [str(crop.get("icon", "•")), str(crop.get("name", crop_id))]
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", Color("#e9f8ff"))
		var on := str(crop_id) == str(Economy.farm.selected_crop)
		var bg := Color(44.0 / 255.0, 132.0 / 255.0, 110.0 / 255.0, 0.85) if on \
			else Color(18.0 / 255.0, 52.0 / 255.0, 86.0 / 255.0, 0.55)
		var edge := Color(124.0 / 255.0, 248.0 / 255.0, 228.0 / 255.0, 0.75) if on \
			else Color(120.0 / 255.0, 200.0 / 255.0, 210.0 / 255.0, 0.2)
		b.add_theme_stylebox_override("normal", _btn_style(bg, edge))
		b.add_theme_stylebox_override("hover", _btn_style(Color(44.0 / 255.0, 140.0 / 255.0, 160.0 / 255.0, 0.9), edge))
		b.custom_minimum_size = Vector2(0, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chosen := str(crop_id)
		b.pressed.connect(func() -> void:
			Economy.farm.selected_crop = chosen
			_refresh_plant())
		picker.add_child(b)

	for row in Economy.farm.specs:
		if not (row is Dictionary):
			continue
		var id := str(row.get("id", ""))
		var line := _row(_plot_line(id), "前往", true)
		line.button.pressed.connect(func(): plot_focus_requested.emit(id))
		_tab_body.add_child(line.box)
		_plant_rows[id] = {"info": line.label, "button": line.button}

	var tip := _label("到菜箱旁按住 E 播种／浇水／收获；缺水只是停长，不会枯死。",
		10, Color(0.72, 0.86, 0.90, 0.75))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300, 0)
	_tab_body.add_child(tip)


## 种植页一行：菜箱名 + 状态（未解锁时说明前置）。
func _plot_line(id: String) -> String:
	var row: Dictionary = Economy.farm.spec(id)
	var name := str(row.get("name", id))
	var need := str(row.get("requires_site", ""))
	var level := int(row.get("requires_level", 0))
	if need != "" and Economy.site_level(need) < level:
		return "%s  未解锁（%s Lv.%d）" % [name, _site_name(need), level]
	return "%s  %s" % [name, Economy.farm.status_text(id)]


func _site_name(id: String) -> String:
	var spec: Dictionary = Economy.SITES.get(id, {})
	return str(spec.get("name", id))


func _refresh_build() -> void:
	_build_rows.clear()
	for id in Economy.SITES.keys():
		var row := _row(_site_line(id), "前往", true)
		row.button.pressed.connect(func(): site_focus_requested.emit(id))
		_tab_body.add_child(row.box)
		_build_rows[id] = {"info": row.label, "button": row.button}
	var tip := _label("施工要在世界里的建造牌旁按 E 交付材料；走开也不会停工。",
		10, Color(0.72, 0.86, 0.90, 0.75))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(300, 0)
	_tab_body.add_child(tip)

	for id in Economy.FACILITIES.keys():
		var f: Dictionary = Economy.FACILITIES[id]
		var built := Economy.facility_unlocked(id)
		var text := "%s  %s" % [f.name, "已建成" if built else Economy.cost_text(f.cost)]
		var row2 := _row(text, "建造" if not built else "—", not built and Economy.can_build_facility(id))
		row2.button.pressed.connect(func(): facility_build_requested.emit(id))
		_tab_body.add_child(row2.box)

	var ship_text := "小船  Lv.%d  %s" % [Economy.ship_level, Economy.cost_text(Economy.SHIP_RECIPE)]
	var row3 := _row(ship_text, "升级", Economy.can_upgrade_ship())
	row3.button.pressed.connect(func(): ship_upgrade_requested.emit())
	_tab_body.add_child(row3.box)


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
		spec.name, level, level + 1, Economy.cost_text(Economy.site_next_cost(id))]


func _cost_text(cost: Dictionary) -> String:
	return Economy.cost_text(cost)


func _row(text: String, action: String, enabled: bool) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var l := _label(text, 11, Color(0.92, 0.98, 1.0, 0.95))
	l.custom_minimum_size = Vector2(246, 0)
	l.clip_text = true
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
	_toast = _label("", 14, Color(0.96, 1.0, 0.99, 0.0))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.72
	_toast.anchor_bottom = 0.72
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_toast)


func toast(text: String, seconds := 2.4) -> void:
	_toast.text = text
	_toast_left = seconds
	_toast.modulate.a = 1.0


func set_diving(on: bool) -> void:
	_diving = on
	# 深度标签的字体颜色 alpha 是 0，只改 modulate 是看不见的，必须改字体色本身。
	_dive_label.add_theme_color_override("font_color", Color(0.90, 0.99, 1.0, 1.0 if on else 0.0))
	if _hint_label != null:
		_hint_label.text = DIVE_HINT if on else SURFACE_HINT
	if not on:
		_dive_zone = ""
	_dive_btn.text = "上浮" if on else "潜水"
	if not on:
		_dive_label.text = ""


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
		if _toast_left < 0.6:
			_toast.modulate.a = clamp(_toast_left / 0.6, 0.0, 1.0)
	_tick_build_rows()
	_tick_plant_rows()


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
