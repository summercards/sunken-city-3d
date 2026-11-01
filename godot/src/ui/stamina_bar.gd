extends Control
## 右下角体力条。手绘奶油胶囊 + 薄荷/琥珀/珊瑚三段配色，与 HUD 同一套色板。
##
## 为什么自绘而不是用 ProgressBar：`cozy_ui.surface()` 的内容边距会把
## ProgressBar 撑到 20px 以上，细条根本画不出来（见 `thin_progress_bar.gd` 的注释）。
## 这里的高度就是 `bar_height`，不受任何主题最小尺寸影响。
##
## 位置由 `corner_hud.place()` 给，不自己找锚点：跟随按钮在同一角，
## 体力条压在它上方 12px，任何分辨率下相对关系不变。

const Cozy = preload("res://src/ui/cozy_ui.gd")

const WIDTH := 184.0
const HEIGHT := 44.0
const BAR_HEIGHT := 13.0
const TRACK := Color(1.0, 0.976, 0.909, 0.55)
const FULL := Color("#5baa96")
const TIRED := Color("#e0a15c")
const EMPTY := Color("#c96f5c")

var current := 100.0
var maximum := 100.0
var _label: Label
var _track_box := StyleBoxFlat.new()
var _fill_box := StyleBoxFlat.new()


func _init() -> void:
	set_meta("cozy_skip", true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	_label = Label.new()
	_label.set_meta("cozy_skip", true)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.position = Vector2(0, 0)
	_label.size = Vector2(WIDTH, 26)
	_label.add_theme_font_override("font", Cozy.world_font())
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Cozy.CREAM)
	_label.add_theme_color_override("font_shadow_color", Color(0.07, 0.17, 0.20, 0.55))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_constant_override("outline_size", 0)
	add_child(_label)
	_apply_boxes()
	_sync_label()


func set_values(value: float, cap: float) -> void:
	current = maxf(0.0, value)
	maximum = maxf(cap, 1.0)
	_sync_label()
	queue_redraw()


func ratio() -> float:
	return clampf(current / maxf(maximum, 0.001), 0.0, 1.0)


func _fill_color() -> Color:
	if current <= 0.0:
		return EMPTY
	return TIRED if ratio() <= 0.25 else FULL


func _sync_label() -> void:
	if _label == null:
		return
	_label.text = "体力 %d / %d" % [int(round(current)), int(round(maximum))]


func _apply_boxes() -> void:
	var r := int(maxf(1.0, floorf(BAR_HEIGHT * 0.5)))
	_track_box.bg_color = TRACK
	_track_box.set_corner_radius_all(r)
	_track_box.anti_aliasing = true
	_fill_box.set_corner_radius_all(r)
	_fill_box.anti_aliasing = true


func _draw() -> void:
	var w := WIDTH
	var h := BAR_HEIGHT
	var top := HEIGHT - h
	_fill_box.bg_color = _fill_color()
	draw_style_box(_track_box, Rect2(Vector2(0, top), Vector2(w, h)))
	var filled := w * ratio()
	if filled > 0.0:
		draw_style_box(_fill_box, Rect2(Vector2(0, top), Vector2(minf(filled, w), h)))
