extends VBoxContainer
class_name BackpackGrid
## 背包页：按物品表渲染格子，只显示「有货」的物品 + 空位占位。
##
## 数据全部来自 Inventory，这里不保存任何状态 —— 重新渲染就能跟上任何变化。

const ItemDBLib = preload("res://scripts/core/item_db.gd")
const COLUMNS := 3
const SLOT_H := 46

var _font: Font
var _grid: GridContainer
var _head: Label
var _inv: RefCounted


func setup(font: Font, inventory: RefCounted) -> void:
	_font = font
	_inv = inventory
	add_theme_constant_override("separation", 7)
	_head = Label.new()
	_head.add_theme_font_override("font", font)
	_head.add_theme_font_size_override("font_size", 11)
	_head.add_theme_color_override("font_color", Color(0.78, 0.93, 0.95, 0.9))
	add_child(_head)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 5)
	_grid.add_theme_constant_override("v_separation", 5)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)
	refresh()


func refresh() -> void:
	if _grid == null or _inv == null:
		return
	for c in _grid.get_children():
		c.queue_free()

	var used: int = _inv.slots_used()
	var cap: int = _inv.capacity()
	_head.text = "背包  %d / %d 格" % [used, cap]
	_head.add_theme_color_override("font_color",
		Color(1.0, 0.78, 0.5) if used >= cap else Color(0.78, 0.93, 0.95, 0.9))

	# 有货的排前面，按物品表顺序；货币不进格子（它不占格）。
	var owned: Array = []
	for id in ItemDBLib.all_ids():
		if ItemDBLib.is_currency(id):
			continue
		if _inv.count(id) > 0:
			owned.append(id)
	for id in owned:
		_grid.add_child(_cell(id, _inv.count(id)))

	# 剩余空位：画成暗格，让容量是「看得见」的。
	var free_slots := maxi(cap - used, 0)
	for i in mini(free_slots, 6):
		_grid.add_child(_empty_cell())
	if free_slots > 6:
		var more := Label.new()
		more.text = "+%d" % (free_slots - 6)
		more.add_theme_font_override("font", _font)
		more.add_theme_font_size_override("font_size", 10)
		more.add_theme_color_override("font_color", Color(0.72, 0.86, 0.9, 0.6))
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.custom_minimum_size = Vector2(0, SLOT_H)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_grid.add_child(more)


func _cell(id: String, count: int) -> Control:
	var accent: Color = ItemDBLib.color(id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(96, SLOT_H)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _cell_style(accent))
	panel.tooltip_text = "%s\n%s" % [ItemDBLib.label(id), str(ItemDBLib.get_item(id).get("desc", ""))]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	panel.add_child(row)

	var icon := Label.new()
	icon.text = ItemDBLib.icon(id)
	icon.add_theme_font_override("font", _font)
	icon.add_theme_font_size_override("font_size", 17)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var name_label := Label.new()
	name_label.text = ItemDBLib.label(id)
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.99, 1.0, 0.95))
	col.add_child(name_label)

	var amount := Label.new()
	amount.text = "×%d" % count
	amount.add_theme_font_override("font", _font)
	amount.add_theme_font_size_override("font_size", 11)
	amount.add_theme_color_override("font_color", accent)
	col.add_child(amount)
	return panel


func _empty_cell() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(96, SLOT_H)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.16, 0.24, 0.35)
	s.border_color = Color(0.4, 0.7, 0.75, 0.12)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", s)
	return panel


func _cell_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.22, accent.g * 0.30, accent.b * 0.34, 0.72)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.30)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
