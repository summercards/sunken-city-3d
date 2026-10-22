extends RefCounted
## 休闲界面的共享视觉语言。只处理表现，不修改操作和经济规则。
const INK := Color("#28434f")
const CREAM := Color("#fff7e7")
const MINT := Color("#92dfb1")
const SKY := Color("#95d9f4")
const CORAL := Color("#ffa083")
const GOLD := Color("#ffd472")
const LILAC := Color("#d2bdf2")

static func surface(color: Color, radius: int = 22) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = Color("#fffdf5")
	box.set_border_width_all(2)
	box.shadow_color = Color(0.19,0.32,0.36,0.16)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0,4)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func button_color(text: String) -> Color:
	if text.contains("农") or text.contains("养") or text.contains("种") or text.contains("补") or text.contains("收获"): return MINT
	if text.contains("建") or text.contains("买") or text.contains("出售"): return GOLD
	if text.contains("取消") or text.contains("退出") or text.contains("关闭"): return Color("#eee6d8")
	if text.contains("休息") or text.contains("滤镜"): return LILAC
	if text.contains("潜") or text.contains("游") or text.contains("浮") or text.contains("视角"): return SKY
	return CORAL

static func animate(control: Control, scale_to: float) -> void:
	var old: Variant = control.get_meta("cozy_tween") if control.has_meta("cozy_tween") else null
	if old is Tween and old.is_valid(): old.kill()
	control.pivot_offset = control.size*0.5
	var tween := control.create_tween()
	control.set_meta("cozy_tween",tween)
	tween.tween_property(control,"scale",Vector2.ONE*scale_to,0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

static func reveal(control: Control) -> void:
	if not control.is_visible_in_tree(): return
	control.scale = Vector2.ONE*0.97
	animate(control,1.0)

static func apply(control: Control) -> void:
	if not is_instance_valid(control) or control.is_queued_for_deletion(): return
	if control is Label:
		var previous: Color = control.get_theme_color("font_color")
		control.add_theme_color_override("font_color",Color(INK,previous.a))
		control.add_theme_font_size_override("font_size",maxi(13,control.get_theme_font_size("font_size")))
	elif control is Button:
		var color := button_color(control.text)
		control.add_theme_stylebox_override("normal",surface(color,18))
		control.add_theme_stylebox_override("hover",surface(color.lightened(0.12),18))
		var pressed := surface(color.darkened(0.04),18)
		pressed.shadow_size = 2
		pressed.shadow_offset = Vector2(0,1)
		control.add_theme_stylebox_override("pressed",pressed)
		control.add_theme_stylebox_override("disabled",surface(Color("#e4e7dd"),18))
		var focus := surface(Color.TRANSPARENT,18)
		focus.border_color = Color("#508775")
		focus.shadow_size = 0
		control.add_theme_stylebox_override("focus",focus)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			control.add_theme_color_override(key,INK)
		control.add_theme_color_override("font_disabled_color",Color("#7e8986"))
		control.add_theme_font_size_override("font_size",maxi(14,control.get_theme_font_size("font_size")))
		control.custom_minimum_size.y = maxf(38,control.custom_minimum_size.y)
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not control.has_meta("cozy_bound"):
			control.set_meta("cozy_bound",true)
			control.mouse_entered.connect(func() -> void: animate(control,1.025))
			control.mouse_exited.connect(func() -> void: animate(control,1.0))
			control.button_down.connect(func() -> void: animate(control,0.97))
			control.button_up.connect(func() -> void: animate(control,1.0))
	elif control is PanelContainer:
		control.add_theme_stylebox_override("panel",surface(CREAM))
		if not control.has_meta("cozy_bound"):
			control.set_meta("cozy_bound",true)
			control.visibility_changed.connect(func() -> void: reveal(control))
	elif control is ProgressBar:
		var bg := surface(Color("#e5e8d9"),9)
		bg.shadow_size = 0
		bg.set_border_width_all(0)
		bg.content_margin_top = 0
		bg.content_margin_bottom = 0
		control.add_theme_stylebox_override("background",bg)
		var fill: StyleBoxFlat = control.get_theme_stylebox("fill") as StyleBoxFlat
		if fill == null: fill = StyleBoxFlat.new()
		fill.bg_color = MINT
		fill.set_corner_radius_all(9)
		control.add_theme_stylebox_override("fill",fill)
		control.custom_minimum_size.y = maxf(16,control.custom_minimum_size.y)

static func apply_tree(root: Node) -> void:
	if root is Control: apply(root)
	for child in root.get_children(): apply_tree(child)


## 一次物品转移可能重建面板多次；延迟执行时旧控件可能已释放。
static func apply_instance(instance_id: int) -> void:
	var control := instance_from_id(instance_id)
	if is_instance_valid(control) and control is Control and not control.is_queued_for_deletion():
		apply(control)
