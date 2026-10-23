extends CanvasLayer
## 码头订单板面板：三张单子 + 「换一批」。
##
## 规则与数值全在 `src/orders/orders.gd` / `assets/data/orders.json`，
## 这里只做三件事：把单子画清楚、交付按钮按得动、数字实时刷新。
##
## 交互约定：打开时只吃 ESC（关）与鼠标点击；键盘 E / 空格留给主场景以外的东西。

signal fulfill_requested(uid: String)
signal reroll_requested
signal closed

const UiFontLib = preload("res://src/ui/ui_font.gd")
const ItemDB = preload("res://src/inventory/item_db.gd")

const C_PANEL := Color(0.030, 0.098, 0.165, 0.94)
const C_BORDER := Color(0.42, 0.88, 0.82, 0.40)
const C_TITLE := Color("#354c57")
const C_TEXT := Color("#52676b")
const C_DIM := Color("#62777a")
const C_GOOD := Color("#32785d")
const C_WARN := Color("#95602f")
const C_COIN := Color("#8b642c")

var model = null
var open := false

var _card: PanelContainer
var _font: Font
var _rows: Array = []
var _empty_label: Label
var _wallet: Label
var _reroll: Button
var _status: Label
var _status_left := 0.0


func _ready() -> void:
	layer = 62
	_font = UiFontLib.make(PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC",
		"Microsoft YaHei", "Helvetica Neue"]))
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_card = PanelContainer.new()
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -280
	_card.offset_right = 280
	_card.offset_top = -430
	_card.offset_bottom = -108
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)

	# 标题行：名字 + 钱包 + 换一批
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var title := _label("码头订单板", 15, C_TITLE)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_wallet = _label("", 11, C_COIN)
	head.add_child(_wallet)
	_reroll = Button.new()
	_reroll.text = "换一批"
	_reroll.focus_mode = Control.FOCUS_NONE
	_reroll.add_theme_font_override("font", _font)
	_reroll.add_theme_font_size_override("font_size", 11)
	_reroll.pressed.connect(func() -> void: reroll_requested.emit())
	head.add_child(_reroll)
	var close := Button.new()
	close.text = "关闭"
	close.add_theme_font_override("font",_font)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)

	var sub := _label("点击订单板前往打开 · 交付会立刻扣货、报酬当场入账", 10, C_DIM)
	box.add_child(sub)

	# 三张单子
	for i in 3:
		_rows.append(_make_row(box))

	_empty_label = _label("板子空了 · 正在等下一批船", 12, C_DIM)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_empty_label)

	_status = _label("", 11, C_WARN)
	box.add_child(_status)

	var foot := _label("ESC 关闭", 10, C_DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(foot)

	visible = false


func _make_row(parent: Node) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.05, 0.14, 0.21, 0.85), Color(0.30, 0.62, 0.66, 0.28), 9))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	panel.add_child(row)

	var icon := _label("", 18, C_TITLE)
	icon.custom_minimum_size = Vector2(24, 0)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(icon)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 1)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var who := _label("", 11, C_TEXT)
	mid.add_child(who)
	var what := _label("", 12, C_TITLE)
	mid.add_child(what)
	var when := _label("", 10, C_DIM)
	mid.add_child(when)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	row.add_child(right)
	var pay := _label("", 12, C_COIN)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(pay)
	var btn := Button.new()
	btn.text = "交付"
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(62, 0)
	right.add_child(btn)
	return {"panel": panel, "icon": icon, "who": who, "what": what, "when": when,
		"pay": pay, "button": btn, "uid": ""}


func _process(delta: float) -> void:
	if _status_left > 0.0:
		_status_left -= delta
		if _status_left <= 0.0:
			_status.text = ""
	if not open or model == null:
		return
	_refresh_dynamic()


# ---------------------------------------------------------------- 开关

func set_open(on: bool) -> void:
	open = on
	visible = on
	if on:
		refresh()
		get_tree().paused = false
	else:
		_status.text = ""
		_status_left = 0.0
		closed.emit()


func is_open() -> bool:
	return open


## 面板开着时吃掉 ESC（关面板）与鼠标事件，别让点击穿透到世界去走路。
func _input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			set_open(false)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		# 面板外的点击：不穿透。点面板内由控件自己处理。
		var mb := event as InputEventMouseButton
		if mb.pressed and not _card.get_global_rect().has_point(mb.position):
			get_viewport().set_input_as_handled()


func note(text: String, seconds := 2.4) -> void:
	_status.text = text
	_status_left = seconds


# ---------------------------------------------------------------- 刷新

func refresh() -> void:
	if model == null:
		return
	_wallet.text = "🪙 %d" % Economy.count("coins")
	var cost: int = model.reroll_cost()
	_reroll.text = "免费换一批"
	_reroll.disabled = Economy.count("coins") < cost
	var live := 0
	for i in _rows.size():
		var ref: Dictionary = _rows[i]
		var slot: Dictionary = model.slots[i] if i < model.slots.size() else {}
		if slot.is_empty() or slot.has("refill"):
			ref.panel.visible = true
			ref.uid = ""
			ref.icon.text = "⏳"
			ref.who.text = "码头卸货中"
			var wait: float = float(slot.get("refill", 0.0)) if slot.has("refill") else 0.0
			ref.what.text = "下一张单子 · %d 秒" % int(ceil(wait))
			ref.when.text = ""
			ref.pay.text = ""
			ref.button.visible = false
			continue
		live += 1
		_refresh_row(ref, slot, true)
	_empty_label.visible = live == 0
	_card.size = Vector2.ZERO  # 让容器按内容重算高度
	_card.reset_size()


func _refresh_dynamic() -> void:
	_wallet.text = "🪙 %d" % Economy.count("coins")
	_reroll.disabled = Economy.count("coins") < model.reroll_cost()
	var live := 0
	for i in _rows.size():
		var ref: Dictionary = _rows[i]
		var slot: Dictionary = model.slots[i] if i < model.slots.size() else {}
		if slot.is_empty() or slot.has("refill"):
			if ref.uid != "":
				ref.uid = ""
			var wait: float = float(slot.get("refill", 0.0)) if slot.has("refill") else 0.0
			ref.what.text = "下一张单子 · %d 秒" % int(ceil(wait))
			continue
		live += 1
		_refresh_row(ref, slot, false)
	_reroll.disabled = Economy.count("coins") < model.reroll_cost()


func _refresh_row(ref: Dictionary, slot: Dictionary, full: bool) -> void:
	var uid := str(slot.get("uid", ""))
	var changed: bool = uid != ref.uid
	ref.uid = uid
	var item := str(slot.get("item", ""))
	var need := int(slot.get("amount", 0))
	var have := Economy.count(item)
	var info := ItemDB.get_item(item)
	if full or changed:
		ref.icon.text = str(info.get("icon", "•"))
		ref.who.text = str(slot.get("customer", "码头客人"))
		var bonus: Dictionary = slot.get("bonus", {})
		var extra := ""
		for k in bonus.keys():
			extra += "  +%s×%d" % [ItemDB.label(str(k)), int(bonus[k])]
		ref.what.text = "%s ×%d%s" % [ItemDB.label(item), need, extra]
		ref.pay.text = "🪙 %d" % int(slot.get("pay", 0))
		ref.panel.visible = true
		ref.button.visible = true
		if ref.button.pressed.is_connected(_on_row_pressed) == false:
			ref.button.pressed.connect(_on_row_pressed.bind(ref))
	ref.when.text = "长期有效 · 背包 %d/%d" % [have, need]
	ref.when.add_theme_color_override("font_color", C_DIM)
	var reason: String = model.blocked_reason(slot)
	ref.button.disabled = reason != ""
	ref.button.tooltip_text = reason
	ref.button.text = "交付" if reason == "" else ("缺货" if have < need else "整理背包")


func _on_row_pressed(ref: Dictionary) -> void:
	if ref.uid != "":
		fulfill_requested.emit(str(ref.uid))


# ---------------------------------------------------------------- 小工具

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style(bg := C_PANEL, border := C_BORDER, radius := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(4.0 / 255.0, 22.0 / 255.0, 58.0 / 255.0, 0.34)
	s.shadow_size = 10
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
