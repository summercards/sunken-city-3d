extends Node
## SEA-UI appearance adapter. Existing presenters retain their models, controls,
## signals and public actions. Only Control layout/style is changed here.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Icons = preload("res://src/ui/ac_icon.gd")
const Items = preload("res://src/inventory/item_db.gd")
var views := {}
var cards := {}
var order_icons: Array = []
var hud: CanvasLayer
var _pending := false
var world_hover: Node
var world_prompt: Node

func attach(owner_hud: CanvasLayer) -> void:
	hud=owner_hud
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_priority=100
	var scene:=hud.get_parent()
	for entry in [["camera","CameraPanel"],["grade","ColorGrade"],["orders","OrderPanel"],["salvage","SalvagePanel"]]:
		var view:=scene.get_node_or_null(entry[1])
		if view==null: continue
		views[entry[0]]=view
		view.layer=70
		view.set_meta("cozy_skip",true)
		var card: PanelContainer=view._panel if entry[0] in ["camera","grade"] else view._card
		cards[entry[0]]=card
		Cozy.style_tree(card,entry[0]=="grade")
		Cozy.paper(card,Cozy.LILAC if entry[0]=="grade" else Cozy.SKY)
		view.visibility_changed.connect(_opened.bind(entry[0]))
	if views.has("camera"):
		var body: VBoxContainer=cards.camera.get_child(0)
		body.add_theme_constant_override("separation",18)
		_title(body.get_child(0).get_child(0),"换个角度看海",26)
	if views.has("grade"):
		_title(views.grade._body.get_child(0).get_child(0),"风景调色室",24)
		for button in views.grade._tab_buttons.values(): button.pressed.connect(_restyle)
	if views.has("orders"): _letters()
	if views.has("salvage"):
		_title(views.salvage._title,"海底的小惊喜",28)
		cards.salvage.get_child(0).add_theme_constant_override("separation",18)
		views.salvage._tension.custom_minimum_size.y=32
	var prompt:=scene.get_node_or_null("InteractPrompt")
	world_prompt=prompt
	if prompt:
		prompt.set_meta("cozy_skip",true)
		prompt._panel.offset_left=-360;prompt._panel.offset_right=360
		prompt._panel.offset_top=-205;prompt._panel.offset_bottom=-95
		prompt._text.add_theme_font_size_override("font_size",28)
		prompt._text.add_theme_color_override("font_color",Cozy.INK)
		prompt._text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		prompt._text.custom_minimum_size.x=470
		Cozy.paper(prompt._panel,Cozy.GOLD,true)
	var hover:=scene.get_node_or_null("HoverCard")
	world_hover=hover
	if hover:
		Cozy.style_tree(hover._card)
		hover._card.add_theme_stylebox_override("panel",Cozy.surface(Cozy.CREAM,22))
	hud.bind_presenters(views)
	get_tree().node_added.connect(_added)
	_font_tree(scene)
	_restyle()

func _title(label: Label, text: String, pixels: int) -> void:
	label.text=text;label.add_theme_font_size_override("font_size",pixels)

func _letters() -> void:
	var view: Node=views.orders
	var box: VBoxContainer=cards.orders.get_child(0)
	_title(box.get_child(0).get_child(0),"码头来信",30)
	box.get_child(1).text="给邻居们准备一些小礼物吧。交付后，海贝会马上到账。"
	var letters:=HBoxContainer.new();letters.add_theme_constant_override("separation",18)
	box.add_child(letters);box.move_child(letters,2)
	for ref in view._rows:
		var panel: PanelContainer=ref.panel
		panel.reparent(letters)
		var style:=Cozy.surface(Color("#f3eedc"),24);style.shadow_size=0
		style.content_margin_left=22;style.content_margin_right=22
		style.content_margin_top=24;style.content_margin_bottom=24
		panel.add_theme_stylebox_override("panel",style)
		panel.custom_minimum_size=Vector2(278,360);panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var old: Node=panel.get_child(0)
		var row:=VBoxContainer.new();row.add_theme_constant_override("separation",16);panel.add_child(row)
		ref.who.reparent(row)
		var icon:=Icons.new();icon.font=view._font;icon.tint=Cozy.MINT
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon.focus_mode=Control.FOCUS_NONE
		icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;row.add_child(icon);order_icons.append(icon)
		for id in ["what","when","pay","button"]: ref[id].reparent(row)
		# Keep the original label alive: it remains a presenter's text output.
		ref.icon.reparent(row);ref.icon.hide()
		old.queue_free()
		for id in ["who","what","when","pay"]: ref[id].horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		ref.what.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;ref.what.custom_minimum_size.x=220
		ref.who.add_theme_font_size_override("font_size",19)
		ref.pay.add_theme_font_size_override("font_size",24)
		ref.button.focus_mode=Control.FOCUS_ALL
	view._reroll.focus_mode=Control.FOCUS_ALL

func _opened(id: String) -> void:
	if not views[id].visible: return
	_restyle()
	_place(id)
	Cozy.reveal(cards[id])
	var buttons: Array=cards[id].find_children("*","Button",true,false)
	for button in buttons:
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus.call_deferred();break

func _place(id: String) -> void:
	if id=="grade" and views.grade._water_scroll!=null:
		views.grade._water_scroll.custom_minimum_size.y=minf(360,hud.get_viewport().get_visible_rect().size.y-470)
	Cozy.place(cards[id],{"camera":480,"grade":700,"orders":980,"salvage":700}[id],id in ["camera","grade"])

func _process(_delta: float) -> void:
	# World annotations must not float over a paused/modal interface.
	var blocked: bool = hud.menu.active or hud._panel_open or hud.menu.external_open()
	# 只藏不恢复 = 背板永久消失。以前写成「有弹窗就 hide()」，却没有任何一处
	# 把它 show 回来，于是玩家开过一次背包后，交互提示就变成一行没有底的裸字。
	# 这里每帧按当前状态对齐，跟气泡自己的 `visible` 一起决定。
	if is_instance_valid(world_hover):
		world_hover._card.visible = not blocked
	if is_instance_valid(world_prompt):
		world_prompt._panel.visible = world_prompt.visible and not blocked
	for id in views:
		if views[id].visible: _place(id)
	if views.has("orders") and views.orders.visible:
		var view: Node=views.orders
		view._wallet.text=view._wallet.text.replace("🪙","海贝")
		for i in order_icons.size():
			var ref: Dictionary=view._rows[i]
			var slot: Dictionary=view.model.slots[i] if view.model and i<view.model.slots.size() else {}
			var item:=str(slot.get("item","clock"))
			order_icons[i].kind=item
			order_icons[i].caption="等待来信" if item=="clock" else Items.label(item)
			ref.pay.text=ref.pay.text.replace("🪙","报酬 / 海贝")

func _font_tree(node: Node) -> void:
	# 世界浮层字自带加粗字体（`Cozy.world_text`），这里不许刷回普通字体：
	# 一旦覆盖，字号还是大的，拉丁数字却掉回细笔画，一行字两种粗细。
	if node.has_meta("cozy_world_text"):
		return
	if node is Control:
		node.add_theme_font_override("font",hud._font)
		if node is RichTextLabel:
			for key in ["normal_font","bold_font","italics_font","bold_italics_font","mono_font"]: node.add_theme_font_override(key,hud._font)
	if node is Window:
		node.add_theme_font_override("title_font",hud._font)
	for child in node.get_children(true): _font_tree(child)

func _font_instance(instance_id: int) -> void:
	var node:=instance_from_id(instance_id)
	if is_instance_valid(node) and not node.is_queued_for_deletion(): _font_tree(node)

func _added(node: Node) -> void:
	if node is Control or node is Window: _font_instance.call_deferred(node.get_instance_id())
	if not views.has("grade") or not views.grade.is_ancestor_of(node): return
	if not _pending:
		_pending=true;_restyle.call_deferred()

func _restyle() -> void:
	_pending=false
	if not views.has("grade"): return
	Cozy.style_tree(cards.grade,true)
	_style_popups(views.grade)
	_place("grade")

func _popup_theme() -> Theme:
	var theme:=Theme.new();theme.default_font=hud._font;theme.default_font_size=22
	for type in ["PopupMenu","PopupPanel","AcceptDialog","PanelContainer"]:
		theme.set_stylebox("panel",type,Cozy.surface(Cozy.CREAM,24))
	for type in ["Label","Button","LineEdit","PopupMenu","CheckButton"]:
		theme.set_color("font_color",type,Cozy.INK)
		theme.set_color("font_hover_color",type,Cozy.INK)
		theme.set_color("font_pressed_color",type,Cozy.INK)
		theme.set_color("font_focus_color",type,Cozy.INK)
		theme.set_color("font_disabled_color",type,Cozy.DIM)
	for state in ["normal","hover","pressed","disabled"]:
		var style:=Cozy.surface(Cozy.GOLD if state in ["hover","pressed"] else Cozy.MINT,18)
		style.shadow_size=0
		theme.set_stylebox(state,"Button",style)
		theme.set_stylebox(state,"LineEdit",Cozy.surface(Color("#eee9d8"),14))
	theme.set_stylebox("hover","PopupMenu",Cozy.surface(Cozy.GOLD,14))
	var frame:=Cozy.surface(Cozy.CREAM,24)
	frame.expand_margin_top=38
	theme.set_stylebox("embedded_border","Window",frame)
	theme.set_color("title_color","Window",Cozy.INK)
	theme.set_color("title_outline_modulate","Window",Color.TRANSPARENT)
	theme.set_constant("title_height","Window",38)
	theme.set_font_size("title_font_size","Window",24)
	theme.set_font("title_font","Window",hud._font)
	return theme

func _fit_popup(window: Window) -> void:
	if not window.visible: return
	var viewport:=hud.get_viewport().get_visible_rect().size
	window.position=Vector2i(clampf(window.position.x,24,maxf(24,viewport.x-window.size.x-24)),clampf(window.position.y,60,maxf(60,viewport.y-window.size.y-24)))

func _style_popups(node: Node) -> void:
	if node is Window:
		node.theme=_popup_theme()
		if node is PopupMenu:
			node.add_theme_font_size_override("font_size",20)
		if not node.has_meta("island_popup"):
			node.set_meta("island_popup",true)
			node.visibility_changed.connect(func(): _fit_popup.call_deferred(node))
		if node is AcceptDialog:
			node.min_size=Vector2i(480,180)
			Cozy.style_tree(node)
			Cozy.style_tree(node.get_ok_button())
			if node is ConfirmationDialog:
				Cozy.style_tree(node.get_cancel_button())
				node.get_cancel_button().grab_focus.call_deferred()
		_fit_popup.call_deferred(node)
	if node is LineEdit:
		node.add_theme_font_size_override("font_size",22)
		node.add_theme_color_override("font_color",Cozy.INK)
	for child in node.get_children(true): _style_popups(child)
