extends CanvasLayer
## 鼠标悬停铭牌：把网页版那张 hover card 搬到世界坐标上。
##
## 网页版的做法是「DOM 卡片 + 工程投影」，好处是鼠标一移上去就知道
## 「这是什么、几级、点了会发生什么」。Godot 版之前只有走近才出提示条，
## 远处的目标完全靠猜。这里补上三件事：
##
##   1. 悬停到可交互物 / 上岸桩 / 漂流物 / 鱼群时，在它上方浮出名字与动作；
##   2. 鼠标指针变成手型（可点的地方一眼能看出来）；
##   3. 悬停的目标同时亮一下焦点环（如果能亮），点击即执行。
##
## 判定全部按**屏幕投影**做，不做物理射线：建筑没有碰撞体，
## 而真正需要悬停的东西（采集点 / 施工牌 / 菜箱 / 锚标 / 漂流物）本来就有世界坐标，
## 投影 + 距离阈值更便宜，也不会被水面挡住。

const PropsScript = preload("res://scripts/sea_props.gd")

const HOVER_RADIUS := 30.0
const CARD_BG := Color(0.030, 0.098, 0.165, 0.90)
const C_BORDER := Color(0.42, 0.88, 0.82, 0.36)
const C_TITLE := Color(0.92, 0.99, 1.0, 1.0)
const C_SUB := Color(0.66, 0.82, 0.88, 1.0)
const C_WARN := Color(1.0, 0.80, 0.45, 1.0)
const C_GOOD := Color(0.55, 0.96, 0.82, 1.0)

var camera: Camera3D
var markers: CanvasLayer
var props: Node3D
## 为 false 时（面板打开 / 潜水 / 航行中）不显示，也不改指针。
var enabled := true
## 当前所在区块，用来区分上岸桩是「前往」还是「已经在这里」。
var current_zone := "zone1"

var target: Dictionary = {}

var _card: PanelContainer
var _title: Label
var _sub: Label
var _font: SystemFont
var _canvas: Control
var _shown := false
var _hover_world := Vector3.ZERO


func _ready() -> void:
	layer = 12

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Heiti SC", "Microsoft YaHei", "Helvetica Neue"])

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", _panel_style())
	_canvas.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)

	_title = _label(13, C_TITLE)
	box.add_child(_title)
	_sub = _label(11, C_SUB)
	box.add_child(_sub)

	_card.visible = false


## 每帧由 main 驱动。`screen` 是鼠标在视口里的位置。
func update_hover(screen: Vector2) -> void:
	if not enabled or camera == null or not is_instance_valid(camera):
		_clear_cursor()
		return
	var hit := _pick(screen)
	target = hit
	if hit.is_empty():
		_clear_cursor()
		_hide()
		return
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	_show(hit, screen)


func clear() -> void:
	target = {}
	_clear_cursor()
	_hide()


## 悬停命中：屏幕距离最近者优先，`priority` 作为同距离下的加权。
func _pick(screen: Vector2) -> Dictionary:
	var best := {}
	var best_score := INF
	var vp_h := get_viewport().get_visible_rect().size.y

	# 1) 世界里的可交互物（采集点 / 施工牌 / 菜箱 / 绞盘）
	for raw in get_tree().get_nodes_in_group("interactable"):
		var spot: Node3D = raw
		if spot == null or not is_instance_valid(spot) or not spot.is_visible_in_tree():
			continue
		var anchor: Vector3 = spot.global_position + Vector3.UP * 0.75
		if camera.is_position_behind(anchor):
			continue
		var sp: Vector2 = camera.unproject_position(anchor)
		var dist: float = sp.distance_to(screen)
		if dist > HOVER_RADIUS:
			continue
		var blocked := ""
		if spot.has_method("blocked_reason"):
			blocked = str(spot.blocked_reason())
		var score := dist - float(spot.priority) * 2.2
		if score < best_score:
			best_score = score
			best = {
				"type": "spot", "node": spot, "screen": sp, "world": anchor,
				"title": spot.focus_text(),
				"sub": ("按 E" if float(spot.hold_time) <= 0.01 else "按住 E") if blocked == "" else blocked,
				"warn": blocked != "",
			}

	# 2) 上岸桩（图标本身就在屏幕空间）
	if markers != null and markers.has_method("pick"):
		var mh: Dictionary = markers.pick(screen)
		if not mh.is_empty():
			var dist2: float = (mh.get("screen", screen) as Vector2).distance_to(screen)
			if dist2 - 3.0 < best_score:
				best_score = dist2 - 3.0
				var here: bool = str(mh.zone) == current_zone
				best = {
					"type": "landing", "hit": mh, "screen": mh.get("screen", screen),
					"world": Vector3.ZERO,
					"title": str(mh.get("name", "上岸点")),
					"sub": "已经在这里" if here else "点击前往",
					"warn": false,
				}

	# 3) 海面漂流物 / 鱼群
	if props != null and props.has_method("pick"):
		var ph: Dictionary = props.pick(screen, camera)
		if not ph.is_empty():
			var dist3: float = (ph.get("screen", screen) as Vector2).distance_to(screen)
			if dist3 < best_score:
				best_score = dist3
				if ph.type == "fish":
					best = {"type": "prop", "hit": ph, "screen": ph.screen, "world": Vector3.ZERO,
						"title": "海面鱼群", "sub": "点击驶近", "warn": false}
				else:
					var spec: Dictionary = PropsScript.CRATE_KINDS.get(ph.item.kind, PropsScript.CRATE_KINDS.crate)
					var bits := PackedStringArray()
					for k in spec.reward.keys():
						bits.append("%d %s" % [int(spec.reward[k]), _item_label(str(k))])
					best = {"type": "prop", "hit": ph, "screen": ph.screen, "world": Vector3.ZERO,
						"title": str(spec.label), "sub": "点击划过去拾取 · " + "  ".join(bits),
						"warn": false}
	return best


func _show(hit: Dictionary, screen: Vector2) -> void:
	_title.text = str(hit.title)
	_sub.text = str(hit.sub)
	_sub.add_theme_color_override("font_color", C_WARN if bool(hit.warn) else C_GOOD)
	_card.visible = true
	_shown = true

	# 先让容器算出尺寸，再摆位置（否则第一次会摆在左上角闪一下）。
	_card.reset_size()
	var sz := _card.size
	var anchor: Vector2 = hit.screen
	if hit.type != "spot" and hit.type != "prop":
		anchor = screen
	var pos := Vector2(anchor.x - sz.x * 0.5, anchor.y - sz.y - 16.0)
	var vp := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))
	_card.position = pos


func _hide() -> void:
	if _shown:
		_card.visible = false
		_shown = false


func _clear_cursor() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _item_label(id: String) -> String:
	return ItemDB.label(id)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CARD_BG
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 11
	s.content_margin_right = 11
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_color = Color(0.0, 0.05, 0.10, 0.32)
	s.shadow_size = 6
	return s
