extends RefCounted
## 休闲界面的共享视觉语言。只处理表现，不修改操作和经济规则。
const INK := Color("#625744")
const DIM := Color("#9a8e76")
const TEAL := Color("#5baa96")
static var motion_enabled := true
const CREAM := Color("#fff9e8")
const MINT := Color("#b3dca7")
const SKY := Color("#acd5de")
const CORAL := Color("#edb39d")
const GOLD := Color("#f7d879")
const LILAC := Color("#cfbfdc")

static func surface(color: Color, radius: int = 22) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.corner_detail = 16
	box.anti_aliasing = true
	box.anti_aliasing_size = 1.5
	box.border_color = Color("#fffdf5")
	box.set_border_width_all(0)
	box.shadow_color = Color(0.19,0.32,0.36,0.16)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0,6)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func button_color(_text: String) -> Color:
	# Neutral choice pills; color belongs to app icons and selected actions.
	return Color("#eee9d5")

static func animate(control: Control, scale_to: float) -> void:
	if not motion_enabled:
		control.scale = Vector2.ONE
		return
	var old: Variant = control.get_meta("cozy_tween") if control.has_meta("cozy_tween") else null
	if old is Tween and old.is_valid(): old.kill()
	control.pivot_offset = control.size*0.5
	var tween := control.create_tween()
	control.set_meta("cozy_tween",tween)
	tween.tween_property(control,"scale",Vector2.ONE*scale_to,0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

static func reveal(control: Control) -> void:
	if not control.is_visible_in_tree(): return
	control.scale = Vector2.ONE*0.94
	animate(control,1.0)

static func apply(control: Control) -> void:
	if not is_instance_valid(control) or control.is_queued_for_deletion(): return
	# 祖先带 cozy_skip 就整棵子树不碰。
	# 只看自己有没有标记是不够的：面板的子控件是运行时一个个 add_child 的，
	# 每个都会单独走一次 node_added → apply，那时标记只打在面板根上。
	var n: Node = control
	while n != null:
		if n.has_meta("cozy_skip"): return
		n = n.get_parent()
	if control is Label:
		var previous: Color = control.get_theme_color("font_color")
		control.add_theme_color_override("font_color",Color(INK,previous.a))
		control.add_theme_font_size_override("font_size",maxi(22,control.get_theme_font_size("font_size")))
	elif control is Button:
		var color := button_color(control.text)
		control.add_theme_stylebox_override("normal",surface(color,24))
		control.add_theme_stylebox_override("hover",surface(GOLD,24))
		var pressed := surface(GOLD.darkened(0.04),24)
		pressed.shadow_size = 2
		pressed.shadow_offset = Vector2(0,1)
		control.add_theme_stylebox_override("pressed",pressed)
		control.add_theme_stylebox_override("disabled",surface(Color("#e9e5d5"),24))
		var focus := surface(Color.TRANSPARENT,24)
		focus.border_color = TEAL
		focus.set_border_width_all(2)
		focus.shadow_size = 0
		control.add_theme_stylebox_override("focus",focus)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			control.add_theme_color_override(key,INK)
		control.add_theme_color_override("font_disabled_color",Color("#7e8986"))
		control.add_theme_font_size_override("font_size",maxi(22,control.get_theme_font_size("font_size")))
		control.custom_minimum_size.y = maxf(44,control.custom_minimum_size.y)
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not control.has_meta("cozy_bound"):
			control.set_meta("cozy_bound",true)
			control.mouse_entered.connect(func() -> void: animate(control,1.035))
			control.mouse_exited.connect(func() -> void: animate(control,1.0))
			control.button_down.connect(func() -> void: animate(control,0.97))
			control.button_up.connect(func() -> void: animate(control,1.0))
	elif control is PanelContainer:
		if control.has_meta("island_paper"): return
		control.add_theme_stylebox_override("panel",surface(CREAM,30))
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
	# 标记打在祖先上就整棵子树跳过：面板里挂的对话框、下拉弹层也一起豁免。
	if root is Control:
		if root.has_meta("cozy_skip"): return
		apply(root)
	for child in root.get_children(): apply_tree(child)


## 一次物品转移可能重建面板多次；延迟执行时旧控件可能已释放。
static func apply_instance(instance_id: int) -> void:
	var control := instance_from_id(instance_id)
	if is_instance_valid(control) and control is Control and not control.is_queued_for_deletion():
		apply(control)


## Decorate a presenter-owned outer container without moving business controls.
static func paper(panel: PanelContainer, accent := TEAL, dialogue := false) -> void:
	if panel.has_meta("island_paper"): return
	panel.set_meta("island_paper",true)
	panel.set_meta("cozy_bound",true)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 32
	empty.content_margin_right = 32
	empty.content_margin_top = 30
	empty.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel",empty)
	var drawing := preload("res://src/ui/island_paper.gd").new()
	drawing.accent = accent;drawing.dialogue = dialogue;drawing.stitched = false
	# Top-level decorative sibling follows the panel so PanelContainer won't lay it out.
	panel.get_parent().add_child(drawing)
	panel.get_parent().move_child(drawing,panel.get_index())
	drawing.set_meta("paper_owner",panel)
	var sync := func():
		if is_instance_valid(panel):
			drawing.position = panel.position;drawing.size = panel.size
			drawing.scale = panel.scale;drawing.pivot_offset = panel.pivot_offset
			drawing.visible = panel.visible;drawing.modulate = panel.modulate
	panel.resized.connect(sync)
	panel.item_rect_changed.connect(sync)
	panel.visibility_changed.connect(sync)
	panel.tree_exiting.connect(func(): drawing.queue_free())
	# Called once after anchors have settled.
	sync.call_deferred()

static func place(panel: Control, width: float, right := false) -> void:
	var vp := panel.get_viewport_rect().size
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size.x = minf(width,vp.x-80)
	panel.size = Vector2(minf(width,vp.x-80),panel.get_combined_minimum_size().y)
	panel.position = Vector2(vp.x-panel.size.x-48 if right else (vp.x-panel.size.x)/2,maxf(88,(vp.y-panel.size.y)/2))

static func style_tree(root: Node, compact := false) -> void:
	if root.has_meta("island_icon") or root.has_meta("island_label"): return
	if root is Control:
		root.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded())
	# Explicit styling also works under cozy_skip developer tools.
	if root is Label:
		root.add_theme_color_override("font_color",INK)
		root.add_theme_font_size_override("font_size",maxi(18 if compact else 22,root.get_theme_font_size("font_size")))
	elif root is Button:
		root.focus_mode=Control.FOCUS_ALL
		var color := button_color(root.text)
		for state in ["normal","hover","pressed","disabled"]:
			var c := GOLD if state in ["hover","pressed"] else color
			if state == "disabled": c = Color("#e9e5d5")
			var style := surface(c,22);style.shadow_size = 0
			root.add_theme_stylebox_override(state,style)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: root.add_theme_color_override(key,INK)
		root.add_theme_color_override("font_disabled_color",DIM)
		root.add_theme_font_size_override("font_size",18 if compact else 24)
		root.custom_minimum_size.y = maxf(root.custom_minimum_size.y,44 if compact else 52)
		var focus := surface(Color.TRANSPARENT,22);focus.border_color = TEAL;focus.set_border_width_all(2);focus.shadow_size = 0
		root.add_theme_stylebox_override("focus",focus)
		if not root.has_meta("island_bound"):
			root.set_meta("island_bound",true)
			root.mouse_entered.connect(func(): animate(root,1.025))
			root.mouse_exited.connect(func(): animate(root,1.0))
			root.button_down.connect(func(): animate(root,0.98))
			root.button_up.connect(func(): animate(root,1.0))
	elif root is HSlider:
		root.custom_minimum_size.y = 28
		var track := surface(Color("#e7e1cd"),8);track.shadow_size = 0
		track.content_margin_top = 4;track.content_margin_bottom = 4
		root.add_theme_stylebox_override("slider",track)
		var fill := surface(TEAL,8);fill.shadow_size = 0
		root.add_theme_stylebox_override("grabber_area",fill)
	elif root is LineEdit:
		root.add_theme_stylebox_override("normal",surface(CREAM,16))
		root.add_theme_color_override("font_color",INK)
	elif root is ProgressBar:
		var bg := surface(Color("#e7e1cd"),10);bg.shadow_size=0
		root.add_theme_stylebox_override("background",bg)
		var fill := surface(TEAL,10);fill.shadow_size=0
		root.add_theme_stylebox_override("fill",fill)
		root.custom_minimum_size.y = 18
	for child in root.get_children(): style_tree(child,compact)
