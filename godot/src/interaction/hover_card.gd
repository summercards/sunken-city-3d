extends CanvasLayer
## 屏幕投影只负责命中与小操作图标；动态操作气泡由HUD拥有。
## 不显示物体名、状态文案或原先的悬停说明卡。

const PropsScript = preload("res://src/pickups/sea_props.gd")

const HOVER_RADIUS := 30.0
var camera: Camera3D
var markers: CanvasLayer
var props: Node3D
## 为 false 时（面板打开 / 潜水 / 航行中）不显示，也不改指针。
var enabled := true
## 当前所在区块，用来区分上岸桩是「前往」还是「已经在这里」。
var current_zone := "zone1"

var target: Dictionary = {}

var _card: PanelContainer
var _canvas: Control
var _shown := false


func _ready() -> void:
	set_meta("cozy_skip",true)
	layer = 12
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(38,38)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("#438f83");style.set_corner_radius_all(19)
	style.border_color=Color("#fff9e7");style.set_border_width_all(2)
	style.content_margin_left=8;style.content_margin_right=8
	style.content_margin_top=8;style.content_margin_bottom=8
	_card.add_theme_stylebox_override("panel",style)
	_canvas.add_child(_card)
	var icon := TextureRect.new()
	icon.texture=preload("res://src/ui/illustrated_icons.gd").texture("hand",true)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_card.add_child(icon)
	_card.hide()


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
	if str(hit.get("type",""))=="landing":
		_hide()
		return
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
		var anchor: Vector3 = spot.global_position + Vector3.UP * (0.18 if spot.is_in_group("farm_plots") else 0.75)
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
				"sub": "点击前往并操作" if blocked == "" else blocked,
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
