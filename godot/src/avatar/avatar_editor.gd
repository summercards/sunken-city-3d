extends CanvasLayer
## UI owns a draft only. The session supplies commit, preview and cancel ports.
signal preview_requested(appearance: Dictionary)
signal save_requested(draft: Dictionary)
signal cancel_requested
signal rotate_requested(angle: float)
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Fonts = preload("res://src/ui/ui_font.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Profile = preload("res://src/avatar/avatar_profile.gd")
var draft: Dictionary
var first_creation := true
var step := 0
var group_id := "skin"
var saving := false
var root_control: Control
var canvas: Control
var paper: PanelContainer
var body: VBoxContainer
var name_input: LineEdit
var next_button: Button
var back_button: Button
var status: Label
var options_scroll: ScrollContainer
var buttons: Dictionary = {}
var _rotation := 0.0
var _font: Font

func _ready() -> void:
	layer=110
	set_meta("cozy_skip",true)
	_font=Fonts.embedded()
	root_control=Control.new(); root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(root_control)
	canvas=Control.new(); root_control.add_child(canvas)
	canvas.size=Vector2(1600,1000); canvas.mouse_filter=Control.MOUSE_FILTER_PASS
	var eyebrow:=_label("S E A  /  新 的 海 上 生 活",23,Cozy.CREAM)
	canvas.add_child(eyebrow); eyebrow.position=Vector2(92,54)
	var title:=_label("海风正好，\n故事从你开始。",38,Cozy.CREAM)
	canvas.add_child(title); title.position=Vector2(90,94)
	var portrait_hint:=_label("每一种模样，都有自己的光。",24,Cozy.CREAM)
	canvas.add_child(portrait_hint); portrait_hint.position=Vector2(100,824)
	var controls:=HBoxContainer.new(); controls.position=Vector2(150,880); controls.add_theme_constant_override("separation",12); canvas.add_child(controls)
	for row in [["rotate_left","向左转",-PI/6],["front","正面",0.0],["rotate_right","向右转",PI/6]]:
		var b:=_button(row[1],Vector2(125,54)); controls.add_child(b); buttons[row[0]]=b
		b.pressed.connect(func():
			_rotation=0.0 if row[0]=="front" else _rotation+float(row[2])
			rotate_requested.emit(_rotation))
	paper=PanelContainer.new(); paper.position=Vector2(820,76); paper.size=Vector2(690,848)
	var style:=Cozy.surface(Cozy.CREAM,38)
	style.content_margin_left=36; style.content_margin_right=36; style.content_margin_top=28; style.content_margin_bottom=28
	paper.add_theme_stylebox_override("panel",style); canvas.add_child(paper)
	body=VBoxContainer.new(); body.add_theme_constant_override("separation",12); paper.add_child(body)
	get_viewport().size_changed.connect(_layout); _layout(); render()

func _layout() -> void:
	var extent:=get_viewport().get_visible_rect().size
	var fit:=minf(extent.x/1600.0,extent.y/1000.0)
	canvas.scale=Vector2.ONE*fit; canvas.position=(extent-Vector2(1600,1000)*fit)*0.5

func _label(value: String, pixels:=24, color:=Cozy.INK) -> Label:
	var label:=Label.new(); label.text=value; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",_font); label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color); return label

func _button(value: String, dimensions:=Vector2(130,52), selected:=false, color:=Cozy.CREAM) -> Button:
	var button:=Button.new(); button.text=value; button.custom_minimum_size=dimensions
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",_font); button.add_theme_font_size_override("font_size",23)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(key,Cozy.INK)
	var normal:=Cozy.surface(Cozy.MINT if selected else color,20)
	if selected: normal.set_border_width_all(3); normal.border_color=Cozy.TEAL
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",Cozy.surface(Cozy.GOLD,20))
	button.add_theme_stylebox_override("pressed",Cozy.surface(Cozy.MINT,20))
	var focus:=Cozy.surface(Color.TRANSPARENT,20); focus.set_border_width_all(3); focus.border_color=Cozy.TEAL
	button.add_theme_stylebox_override("focus",focus)
	return button

func render() -> void:
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	for key in buttons.keys():
		if key not in ["rotate_left","front","rotate_right"]: buttons.erase(key)
	body.add_child(_label("0%d  /  03     %s" % [step+1,["你好，新朋友","找到喜欢的模样","收好这张旅人证"][step]],22,Cozy.TEAL))
	body.add_child(_label(["怎么称呼你？","这就是我","准备好出发了吗？"][step],39))
	var content:=VBoxContainer.new(); content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",16); body.add_child(content)
	if step==0: _name_page(content)
	elif step==1: _appearance_page(content)
	else: _confirm_page(content)
	status=_label("",21,Color("#b16653")); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size=Vector2(590,54); body.add_child(status)
	var footer:=HBoxContainer.new(); footer.add_theme_constant_override("separation",16); body.add_child(footer)
	back_button=_button("返回" if step>0 else ("慢慢想，不着急" if first_creation else "取消修改"),Vector2(240,58),false,Color("#eee9d5"))
	back_button.disabled=step==0 and first_creation; footer.add_child(back_button); buttons.back=back_button
	back_button.pressed.connect(back)
	next_button=_button("保存，开始生活" if step==2 else "下一步",Vector2(340,58),false,Cozy.GOLD)
	footer.add_child(next_button); buttons.next=next_button; next_button.pressed.connect(advance)
	if step==0:
		name_input.grab_focus(); _update_name_error()
	else: next_button.grab_focus()

func _name_page(content: VBoxContainer) -> void:
	content.add_child(_label("海风会记住这个名字，\n小岛上的朋友也会这样叫你。",25,Cozy.DIM))
	var spacer:=Control.new(); spacer.custom_minimum_size.y=36; content.add_child(spacer)
	name_input=LineEdit.new(); name_input.name="PlayerName"; name_input.text="" if first_creation and draft.name=="旅人" else draft.name
	name_input.keep_editing_on_text_submit=true
	name_input.placeholder_text="写下你的名字"; name_input.custom_minimum_size=Vector2(580,84)
	name_input.max_length=24; name_input.add_theme_font_override("font",_font); name_input.add_theme_font_size_override("font_size",36)
	name_input.add_theme_color_override("font_color",Cozy.INK); name_input.add_theme_color_override("caret_color",Cozy.TEAL)
	name_input.add_theme_stylebox_override("normal",Cozy.surface(Color("#eee9d5"),22)); name_input.add_theme_stylebox_override("focus",Cozy.surface(Color("#e3eedb"),22))
	content.add_child(name_input); buttons.name=name_input
	name_input.text_changed.connect(func(value): draft.name=value; _update_name_error())
	name_input.text_submitted.connect(func(_value): advance())
	content.add_child(_label("1–12 个字 · 中文、字母、数字都可以",22,Cozy.DIM))
	content.add_child(_label("以后也可以在「我的模样」里修改。",22,Cozy.DIM))

func _update_name_error() -> void:
	if status==null: return
	var error:=Profile.name_error(name_input.text)
	status.text="" if name_input.text.is_empty() else error
	next_button.disabled=error!=""

func _appearance_page(content: VBoxContainer) -> void:
	var tabs:=GridContainer.new(); tabs.columns=4; tabs.add_theme_constant_override("h_separation",8); tabs.add_theme_constant_override("v_separation",8); content.add_child(tabs)
	var selected: Dictionary
	for group in Catalog.data().groups:
		var b:=_button(group.label,Vector2(138,48),group.id==group_id,Color("#eee9d5")); tabs.add_child(b); buttons["group/"+group.id]=b
		b.pressed.connect(func(): group_id=group.id; render())
		if group.id==group_id: selected=group
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.custom_minimum_size.y=350; content.add_child(scroll)
	options_scroll=scroll
	var options:=VBoxContainer.new(); options.size_flags_horizontal=Control.SIZE_EXPAND_FILL; options.add_theme_constant_override("separation",14); scroll.add_child(options)
	for slot_id in selected.slots:
		var slot: Dictionary
		for row in Catalog.data().slots:
			if row.id==slot_id: slot=row
		options.add_child(_label(slot.label,23,Cozy.DIM))
		var grid:=GridContainer.new(); grid.columns=3; grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8); options.add_child(grid)
		for option in slot.options:
			var active: bool=Catalog.resolve(slot_id,str(draft.appearance[slot_id])).id==option.id
			var text: String=("✓ " if active else "")+option.label
			var b:=_button(text,Vector2(182,52),active,Color(option.color).lightened(0.38) if option.has("color") else Color("#eee9d5"))
			grid.add_child(b); buttons[slot_id+"/"+option.id]=b
			b.pressed.connect(func():
				draft.appearance[slot_id]=option.id; draft.design_refs.erase(slot_id)
				preview_requested.emit(draft.appearance.duplicate(true)); render())
	var random_button:=_button("随海风搭配一下",Vector2(580,48),false,Color("#eee9d5")); content.add_child(random_button); buttons.random=random_button
	random_button.pressed.connect(func():
		for slot in Catalog.data().slots: draft.appearance[slot.id]=slot.options.pick_random().id
		draft.design_refs.clear(); preview_requested.emit(draft.appearance.duplicate(true)); render())

func _confirm_page(content: VBoxContainer) -> void:
	content.add_child(_label("S E A   /   旅 人 证",23,Cozy.TEAL))
	content.add_child(_label(draft.name.strip_edges(),46))
	content.add_child(_label("从今天起，这片海有了你的故事。",24,Cozy.DIM))
	for group in Catalog.data().groups:
		var names:=PackedStringArray()
		for slot_id in group.slots: names.append(Catalog.resolve(slot_id,str(draft.appearance[slot_id])).label)
		content.add_child(_label(group.label+"  ·  "+" / ".join(names),22))

func advance() -> void:
	if saving: return
	if step==0: draft.name=name_input.text
	var error:=Profile.name_error(str(draft.name))
	if error!="": status.text=error; return
	draft.name=draft.name.strip_edges()
	if step<2: step+=1; render()
	else:
		saving=true; next_button.disabled=true; back_button.disabled=true
		status.text="正在收好你的旅人证……"; save_requested.emit(draft.duplicate(true))

func save_failed(reason: String) -> void:
	saving=false; next_button.disabled=false; back_button.disabled=false; status.text="没能保存："+reason+"。请重试。"

func back() -> void:
	if saving: return
	if step>0: step-=1; render()
	elif not first_creation: cancel_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE: back()
		get_viewport().set_input_as_handled()
