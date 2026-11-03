extends CanvasLayer
## Draft-only UI. Profile commits and rendered previews belong to the session.
signal preview_requested(appearance: Dictionary) # Compatibility for existing appearance-only consumers.
signal draft_preview_requested(draft: Dictionary)
signal save_requested(draft: Dictionary)
signal cancel_requested
signal rotate_requested(angle: float)
signal focus_requested(mode: String)
signal expression_requested(mode: String)
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Fonts = preload("res://src/ui/ui_font.gd")
const Catalog = preload("res://src/avatar/avatar_catalog.gd")
const Profile = preload("res://src/avatar/avatar_profile.gd")
const HISTORY_LIMIT := 40
var draft: Dictionary
var first_creation := true
var step := 0
var group_id := "body"
var subsection_id := ""
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
var morph_sliders: Dictionary = {}
var _rotation := 0.0
var _focus_mode := ""
var _font: Font
var _original_draft: Dictionary
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _scroll_positions: Dictionary = {}
var _rendered_scroll_key := ""
var _option_buttons: Dictionary = {}
var _option_headings: Dictionary = {}
var _morph_values: Dictionary = {}
var _swatches: Dictionary = {}
var _syncing := false
var _drag_id := ""
var _drag_saved := false
var _comparing := false

func _ready() -> void:
	layer=110; set_meta("cozy_skip",true); _font=Fonts.embedded()
	_ensure_draft(); _original_draft=draft.duplicate(true)
	root_control=Control.new(); root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(root_control)
	canvas=Control.new(); root_control.add_child(canvas)
	canvas.size=Vector2(1600,1000); canvas.mouse_filter=Control.MOUSE_FILTER_PASS
	var eyebrow:=_label("S E A  /  新 的 海 上 生 活" if first_creation else "S E A  /  我 的 模 样",23,Cozy.CREAM)
	canvas.add_child(eyebrow); eyebrow.position=Vector2(92,54)
	var title:=_label("海风正好，\n故事从你开始。" if first_creation else "今天，\n想换一种模样。",38,Cozy.CREAM)
	canvas.add_child(title); title.position=Vector2(90,94)
	var hint:=_label("每一种模样，都有自己的光。",24,Cozy.CREAM)
	canvas.add_child(hint); hint.position=Vector2(100,824)
	var controls:=HBoxContainer.new(); controls.position=Vector2(150,880); controls.add_theme_constant_override("separation",12); canvas.add_child(controls)
	for row in [["rotate_left","向左转",-PI/6],["front","正面",0.0],["rotate_right","向右转",PI/6]]:
		var b:=_button(row[1],Vector2(125,50)); controls.add_child(b); buttons[row[0]]=b
		b.pressed.connect(func():
			_rotation=0.0 if row[0]=="front" else _rotation+float(row[2])
			rotate_requested.emit(_rotation))
	var views:=HBoxContainer.new(); views.position=Vector2(210,940); views.add_theme_constant_override("separation",12); canvas.add_child(views)
	for mode in ["body","face"]:
		var b:=_button("看全身" if mode=="body" else "看脸部",Vector2(130,42)); views.add_child(b); buttons["view/"+mode]=b
		b.pressed.connect(func(): _set_focus_mode(mode))
	paper=PanelContainer.new(); paper.position=Vector2(820,60); paper.size=Vector2(690,880)
	var style:=Cozy.surface(Cozy.CREAM,38)
	style.content_margin_left=32; style.content_margin_right=32; style.content_margin_top=24; style.content_margin_bottom=24
	paper.add_theme_stylebox_override("panel",style); canvas.add_child(paper)
	body=VBoxContainer.new(); body.add_theme_constant_override("separation",10); paper.add_child(body)
	get_viewport().size_changed.connect(_layout); _layout(); render()

func _ensure_draft() -> void:
	if not draft.has("appearance"): draft.appearance={}
	for id in Catalog.defaults():
		if not draft.appearance.has(id): draft.appearance[id]=Catalog.defaults()[id]
	if not draft.has("morphs"): draft.morphs={}
	for id in Catalog.morph_defaults():
		if not draft.morphs.has(id): draft.morphs[id]=Catalog.morph_defaults()[id]
	if not draft.has("design_refs"): draft.design_refs={}
	if not draft.has("name"): draft.name="旅人"

func _layout() -> void:
	var extent:=get_viewport().get_visible_rect().size
	var fit:=minf(extent.x/1600.0,extent.y/1000.0)
	canvas.scale=Vector2.ONE*fit; canvas.position=(extent-Vector2(1600,1000)*fit)*0.5

func _label(value: String, pixels:=24, color:=Cozy.INK) -> Label:
	var label:=Label.new(); label.text=value; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",_font); label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color); return label

func _button(value: String, dimensions:=Vector2(130,52), selected:=false, color:=Color("#eee9d5")) -> Button:
	var button:=Button.new(); button.text=value; button.custom_minimum_size=dimensions
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",_font); button.add_theme_font_size_override("font_size",23)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(key,Cozy.INK)
	button.add_theme_color_override("font_disabled_color",Color("#a3a292"))
	_style_selection(button,selected,color)
	button.add_theme_stylebox_override("hover",Cozy.surface(Cozy.GOLD,18))
	button.add_theme_stylebox_override("pressed",Cozy.surface(Cozy.MINT,18))
	button.add_theme_stylebox_override("disabled",Cozy.surface(Color("#eeebdd"),18))
	var focus:=Cozy.surface(Color.TRANSPARENT,18); focus.set_border_width_all(3); focus.border_color=Cozy.TEAL
	button.add_theme_stylebox_override("focus",focus)
	return button

func _style_selection(button: Button, selected: bool, color:=Color("#eee9d5")) -> void:
	var normal:=Cozy.surface(Cozy.MINT if selected else color,18)
	if selected: normal.set_border_width_all(3); normal.border_color=Cozy.TEAL
	button.add_theme_stylebox_override("normal",normal)

func _swatch(value: String) -> Texture2D:
	if _swatches.has(value): return _swatches[value]
	var img:=Image.create(28,28,false,Image.FORMAT_RGBA8); var color:=Color(value)
	for y in range(28):
		for x in range(28):
			var alpha:=clampf(13.0-Vector2(x-13.5,y-13.5).length(),0.0,1.0)
			img.set_pixel(x,y,Color(color,alpha))
	var texture:=ImageTexture.create_from_image(img); _swatches[value]=texture; return texture

func _remember_scroll() -> void:
	if is_instance_valid(options_scroll) and not _rendered_scroll_key.is_empty(): _scroll_positions[_rendered_scroll_key]=options_scroll.scroll_vertical

func render() -> void:
	_remember_scroll(); preview_original(false)
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	options_scroll=null; _option_buttons.clear(); _option_headings.clear(); morph_sliders.clear(); _morph_values.clear()
	for key in buttons.keys():
		if key not in ["rotate_left","front","rotate_right","view/body","view/face"]: buttons.erase(key)
	body.add_child(_label("0%d  /  03     %s" % [step+1,["你好，新朋友","找到喜欢的模样","收好这张旅人证"][step]],22,Cozy.TEAL))
	body.add_child(_label(["怎么称呼你？","这就是我","准备好出发了吗？"][step],37))
	var content:=VBoxContainer.new(); content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10); body.add_child(content)
	if step==0: _name_page(content)
	elif step==1: _appearance_page(content)
	else: _confirm_page(content)
	status=_label("",20,Color("#b16653")); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size=Vector2(590,34); body.add_child(status)
	var footer:=HBoxContainer.new(); footer.add_theme_constant_override("separation",16); body.add_child(footer)
	back_button=_button("返回" if step>0 else ("慢慢想，不着急" if first_creation else "取消修改"),Vector2(238,56),false,Color("#eee9d5"))
	back_button.disabled=step==0 and first_creation; footer.add_child(back_button); buttons.back=back_button
	back_button.pressed.connect(back)
	next_button=_button(("保存，开始生活" if first_creation else "保存我的模样") if step==2 else "下一步",Vector2(350,56),false,Cozy.GOLD)
	footer.add_child(next_button); buttons.next=next_button; next_button.pressed.connect(advance)
	if step==0: name_input.grab_focus(); _update_name_error()
	else: next_button.grab_focus()
	_set_focus_mode("face" if step==1 and (group_id not in ["body","top","bottom","shoes"] or (group_id=="body" and subsection_id=="head")) else "body")
	_update_history_buttons()

func _name_page(content: VBoxContainer) -> void:
	content.add_child(_label("海风会记住这个名字，\n小岛上的朋友也会这样叫你。",25,Cozy.DIM))
	var spacer:=Control.new(); spacer.custom_minimum_size.y=36; content.add_child(spacer)
	name_input=LineEdit.new(); name_input.name="PlayerName"; name_input.text="" if first_creation and draft.name=="旅人" else draft.name
	name_input.keep_editing_on_text_submit=true
	name_input.placeholder_text="写下你的名字"; name_input.custom_minimum_size=Vector2(580,84)
	name_input.max_length=12; name_input.add_theme_font_override("font",_font); name_input.add_theme_font_size_override("font_size",36)
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

func _sections(id: String) -> Array:
	match id:
		"body": return [{"id":"shape","label":"身形与四肢","slots":["body_type"],"morphs":["body_build","arm_girth","leg_length"]},{"id":"head","label":"头部比例","morphs":["head_size","head_width"]}]
		"hair": return [{"id":"styles","label":"发型","slots":["hair_style","fringe","hair_accessory"]},{"id":"colors","label":"发色","slots":["hair_color"]},{"id":"diy","label":"DIY 发型","morphs":["hair_length","hair_volume","hair_sweep"]}]
		"eyes": return [{"id":"styles","label":"眼睛与眉毛","slots":["eyes","brows"]},{"id":"colors","label":"瞳色","slots":["eye_color"]},{"id":"spacing","label":"眼睛间距","morphs":["eye_spacing"]}]
		"face": return [{"id":"features","label":"鼻子与嘴巴","slots":["nose","mouth"]},{"id":"blush","label":"红晕","slots":["blush"]},{"id":"beard","label":"胡子","slots":["beard","beard_color"]}]
	return []

func show_group(id: String, subsection: String="") -> void:
	_remember_scroll(); group_id=id; subsection_id=subsection
	if is_inside_tree(): render()

func _appearance_page(content: VBoxContainer) -> void:
	var tabs:=GridContainer.new(); tabs.columns=3; tabs.add_theme_constant_override("h_separation",8); tabs.add_theme_constant_override("v_separation",8); content.add_child(tabs)
	var selected: Dictionary
	for group in Catalog.data().groups:
		var b:=_button(group.label,Vector2(194,42),group.id==group_id); tabs.add_child(b); buttons["group/"+group.id]=b
		b.pressed.connect(func(): show_group(group.id))
		if group.id==group_id: selected=group
	var slots: Array=selected.get("slots",[]).duplicate()
	var morph_ids: Array=[]
	for definition in Catalog.morph_definitions():
		if definition.group==group_id: morph_ids.append(definition.id)
	var sections:=_sections(group_id)
	if not sections.is_empty():
		var valid_section:=false
		for section in sections:
			if section.id==subsection_id: valid_section=true
		if not valid_section: subsection_id=sections[0].id
		var sub_tabs:=HBoxContainer.new(); sub_tabs.add_theme_constant_override("separation",8); content.add_child(sub_tabs)
		for section in sections:
			var b:=_button(section.label,Vector2(194,40),section.id==subsection_id); b.add_theme_font_size_override("font_size",21); sub_tabs.add_child(b); buttons["sub/"+section.id]=b
			b.pressed.connect(func(): show_group(group_id,section.id))
			if section.id==subsection_id: slots=section.get("slots",[]); morph_ids=section.get("morphs",[])
	var toolbar:=HBoxContainer.new(); toolbar.add_theme_constant_override("separation",8); content.add_child(toolbar)
	for item in [["undo","撤销",108],["redo","重做",108],["group_reset","重置这一类",166],["compare","按住看原样",176]]:
		var b:=_button(item[1],Vector2(item[2],40)); b.add_theme_font_size_override("font_size",20); toolbar.add_child(b); buttons[item[0]]=b
	buttons.undo.pressed.connect(undo); buttons.redo.pressed.connect(redo); buttons.group_reset.pressed.connect(reset_group)
	buttons.undo.tooltip_text="撤销上一次调整 · Ctrl+Z"
	buttons.redo.tooltip_text="恢复刚撤销的调整 · Ctrl+Shift+Z / Ctrl+Y"
	buttons.group_reset.tooltip_text="将当前整类恢复默认；其他类别保留。可以撤销。"
	buttons.compare.tooltip_text="按住预览打开界面时的模样，松开回到当前搭配。"
	buttons.compare.button_down.connect(func(): preview_original(true))
	buttons.compare.button_up.connect(func(): preview_original(false))
	buttons.compare.mouse_exited.connect(func(): preview_original(false))
	if group_id in ["eyes","face"]:
		var expressions:=HBoxContainer.new(); expressions.add_theme_constant_override("separation",8); content.add_child(expressions)
		for entry in [["neutral","平静"],["happy","开心"],["focused","专注"],["surprised","惊讶"],["concerned","担心"]]:
			var b:=_button(entry[1],Vector2(112,36)); b.add_theme_font_size_override("font_size",19)
			b.tooltip_text="试试表情 · 不改变搭配"; expressions.add_child(b); buttons["expression/"+entry[0]]=b
			b.pressed.connect(func(): expression_requested.emit(entry[0]))
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.custom_minimum_size.y=200; content.add_child(scroll); options_scroll=scroll
	var options:=VBoxContainer.new(); options.size_flags_horizontal=Control.SIZE_EXPAND_FILL; options.add_theme_constant_override("separation",10 if slots.is_empty() else 14); scroll.add_child(options)
	for id in morph_ids: _morph_control(options,id)
	for id in slots: _option_section(options,id)
	_rendered_scroll_key=group_id+"/"+subsection_id
	var restore:=int(_scroll_positions.get(_rendered_scroll_key,0))
	scroll.set_deferred("scroll_vertical",restore)
	var random_row:=HBoxContainer.new(); random_row.add_theme_constant_override("separation",12); content.add_child(random_row)
	var random_group:=_button("这一类，随海风搭配",Vector2(304,44)); random_group.add_theme_font_size_override("font_size",21); random_row.add_child(random_group); buttons.random_group=random_group
	random_group.pressed.connect(randomize_group)
	var random_all:=_button("全部搭配一下",Vector2(304,44)); random_all.add_theme_font_size_override("font_size",21); random_row.add_child(random_all); buttons.random=random_all
	random_all.pressed.connect(randomize_all)

func _option_section(options: VBoxContainer, id: String) -> void:
	var slot: Dictionary={}
	for row in Catalog.data().slots:
		if row.id==id: slot=row; break
	if slot.is_empty(): return
	var current:=Catalog.resolve(id,str(draft.appearance.get(id,"")))
	var heading:=_label(slot.label+"  ·  "+str(current.get("label","")),22,Cozy.DIM)
	options.add_child(heading); _option_headings[id]=heading
	var grid:=GridContainer.new(); grid.columns=3; grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8); options.add_child(grid)
	_option_buttons[id]={}
	for option in slot.options:
		var active: bool=current.id==option.id
		var b:=_button(option.label,Vector2(186,50),active); b.add_theme_font_size_override("font_size",22)
		if option.has("color"):
			b.icon=_swatch(option.color); b.add_theme_constant_override("h_separation",10)
		b.tooltip_text=slot.label+"："+option.label+("（已选择）" if active else "")
		grid.add_child(b); buttons[id+"/"+option.id]=b; _option_buttons[id][option.id]=b
		b.pressed.connect(func(): select_option(id,option.id))

func _morph_control(options: VBoxContainer, id: String) -> void:
	var definition: Dictionary={}
	for row in Catalog.morph_definitions():
		if row.id==id: definition=row; break
	if definition.is_empty(): return
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",8); options.add_child(box)
	var heading:=HBoxContainer.new(); box.add_child(heading)
	var title:=_label(definition.label,23); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(title)
	var range_hint:=_label(str(definition.get("low_label","少一些"))+"  —  "+str(definition.get("high_label","多一些")),18,Cozy.DIM)
	heading.add_child(range_hint)
	var value_label:=_label("%d%%" % roundi(float(draft.morphs[id])*100),22,Cozy.TEAL); value_label.custom_minimum_size.x=62; value_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; heading.add_child(value_label); _morph_values[id]=value_label
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",16); box.add_child(row)
	var slider:=HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=0.01; slider.value=float(draft.morphs[id]); slider.custom_minimum_size=Vector2(390,44); slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; slider.scrollable=false
	slider.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; slider.tooltip_text=definition.label+"；方向键微调，默认 50%"
	var rail:=Cozy.surface(Color("#dddac7"),5); rail.content_margin_top=4; rail.content_margin_bottom=4
	slider.add_theme_stylebox_override("slider",rail); slider.add_theme_stylebox_override("grabber_area",Cozy.surface(Cozy.TEAL,5)); slider.add_theme_stylebox_override("grabber_area_highlight",Cozy.surface(Cozy.TEAL,5))
	slider.add_theme_icon_override("grabber",_swatch(Cozy.TEAL.to_html())); slider.add_theme_icon_override("grabber_highlight",_swatch(Cozy.GOLD.to_html())); row.add_child(slider)
	morph_sliders[id]=slider; buttons["morph/"+id]=slider
	slider.drag_started.connect(func():
		if _drag_id!=id: _drag_id=id; _drag_saved=false)
	slider.drag_ended.connect(func(_value_changed): _drag_id=""; _drag_saved=false)
	slider.value_changed.connect(func(value):
		if not _syncing: set_morph(id,value))
	var reset:=_button("默认",Vector2(76,40)); reset.add_theme_font_size_override("font_size",20); row.add_child(reset); buttons["morph_reset/"+id]=reset
	reset.pressed.connect(func(): set_morph(id,float(definition.get("default",0.5))))

func _editing_state(source: Dictionary) -> Dictionary:
	return {"appearance":source.appearance.duplicate(true),"morphs":source.morphs.duplicate(true),"design_refs":source.design_refs.duplicate(true)}

func _record_change() -> void:
	preview_original(false)
	_undo.append(_editing_state(draft)); _redo.clear()
	if _undo.size()>HISTORY_LIMIT: _undo.pop_front()

func select_option(id: String, option_id: String) -> void:
	if saving or draft.appearance.get(id,"")==option_id: return
	_record_change(); draft.appearance[id]=option_id; draft.design_refs.erase(id); _changed()

func set_morph(id: String, value: float) -> void:
	if saving or not Catalog.morph_defaults().has(id) or not is_finite(value): return
	value=snappedf(clampf(value,0.0,1.0),0.01)
	if is_equal_approx(float(draft.morphs.get(id,0.5)),value): return
	if _drag_id!=id or not _drag_saved: _record_change(); _drag_saved=true
	draft.morphs[id]=value; _changed()

func reset_group() -> void:
	if saving: return
	var next:=_editing_state(draft)
	for group in Catalog.data().groups:
		if group.id==group_id:
			for id in group.slots: next.appearance[id]=Catalog.defaults()[id]; next.design_refs.erase(id)
	for definition in Catalog.morph_definitions():
		if definition.group==group_id: next.morphs[definition.id]=definition.get("default",0.5)
	_apply_transaction(next)

func randomize_group() -> void:
	if saving: return
	var next:=_editing_state(draft)
	for group in Catalog.data().groups:
		if group.id==group_id:
			for id in group.slots: next.appearance[id]=Catalog.options(id).pick_random().id; next.design_refs.erase(id)
	for definition in Catalog.morph_definitions():
		if definition.group==group_id: next.morphs[definition.id]=snappedf(randf(),0.01)
	_apply_transaction(next)

func randomize_all() -> void:
	if saving: return
	var next:=_editing_state(draft)
	for slot in Catalog.data().slots: next.appearance[slot.id]=slot.options.pick_random().id; next.design_refs.erase(slot.id)
	for id in Catalog.morph_defaults(): next.morphs[id]=snappedf(randf(),0.01)
	_apply_transaction(next)

func _apply_transaction(next: Dictionary) -> void:
	if next==_editing_state(draft): return
	_record_change(); _restore_editing_state(next); _changed()

func undo() -> void:
	if saving or _undo.is_empty(): return
	preview_original(false); _redo.append(_editing_state(draft)); _restore_editing_state(_undo.pop_back()); _changed()
	if is_instance_valid(status): status.text="已撤销上一次调整。"

func redo() -> void:
	if saving or _redo.is_empty(): return
	preview_original(false); _undo.append(_editing_state(draft)); _restore_editing_state(_redo.pop_back()); _changed()
	if is_instance_valid(status): status.text="已恢复刚撤销的调整。"

func _restore_editing_state(state: Dictionary) -> void:
	for id in ["appearance","morphs","design_refs"]: draft[id]=state[id].duplicate(true)

func _changed() -> void:
	_syncing=true
	for id in morph_sliders:
		morph_sliders[id].value=float(draft.morphs[id]); _morph_values[id].text="%d%%" % roundi(float(draft.morphs[id])*100)
	_syncing=false
	for id in _option_buttons:
		var selected:=Catalog.resolve(id,str(draft.appearance.get(id,"")))
		var title: String=""
		for slot in Catalog.data().slots:
			if slot.id==id: title=slot.label; break
		_option_headings[id].text=title+"  ·  "+str(selected.get("label",""))
		for option_id in _option_buttons[id]:
			var b: Button=_option_buttons[id][option_id]; var active: bool=selected.id==option_id
			_style_selection(b,active); b.tooltip_text=title+"："+b.text+("（已选择）" if active else "")
	_update_history_buttons()
	if is_instance_valid(status): status.text="已在左侧预览；可以继续调整，或下一步确认。"; status.add_theme_color_override("font_color",Cozy.TEAL)
	_emit_preview(draft)

func _update_history_buttons() -> void:
	if buttons.has("undo"): buttons.undo.disabled=_undo.is_empty() or saving
	if buttons.has("redo"): buttons.redo.disabled=_redo.is_empty() or saving
	if buttons.has("compare"): buttons.compare.disabled=_editing_state(draft)==_editing_state(_original_draft) or saving

func _emit_preview(value: Dictionary) -> void:
	draft_preview_requested.emit(value.duplicate(true)); preview_requested.emit(value.appearance.duplicate(true))

func preview_original(active: bool) -> void:
	if _comparing==active: return
	_comparing=active; _emit_preview(_original_draft if active else draft)

func _set_focus_mode(mode: String) -> void:
	for id in ["body","face"]:
		if buttons.has("view/"+id): _style_selection(buttons["view/"+id],id==mode)
	if _focus_mode==mode: return
	_focus_mode=mode; focus_requested.emit(mode)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		preview_original(false); _drag_id=""; _drag_saved=false

func _input(event: InputEvent) -> void:
	# Capture the baseline before Range changes on a track click. A complete drag
	# is one history transaction regardless of how many live previews it emits.
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT: return
	if not event.pressed:
		_drag_id=""; _drag_saved=false
		if _comparing: preview_original(false)
	elif step==1 and not saving:
		for id in morph_sliders:
			var slider: HSlider=morph_sliders[id]
			if slider.get_global_rect().has_point(event.position):
				_drag_id=id; _drag_saved=false; break

func _confirm_page(content: VBoxContainer) -> void:
	content.add_child(_label("S E A   /   旅 人 证",23,Cozy.TEAL))
	content.add_child(_label(draft.name.strip_edges(),46))
	content.add_child(_label("从今天起，这片海有了你的故事。",24,Cozy.DIM))
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.custom_minimum_size.y=320; content.add_child(scroll)
	var summary:=VBoxContainer.new(); summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL; summary.add_theme_constant_override("separation",14); scroll.add_child(summary)
	for group in Catalog.data().groups:
		var names:=PackedStringArray()
		for id in group.slots: names.append(Catalog.resolve(id,str(draft.appearance.get(id,""))).label)
		for definition in Catalog.morph_definitions():
			if definition.group==group.id: names.append("%s %d%%" % [definition.label,roundi(float(draft.morphs[definition.id])*100)])
		var line:=_label(group.label+"  ·  "+" / ".join(names),22); line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; line.custom_minimum_size.x=575; summary.add_child(line)

func advance() -> void:
	if saving: return
	preview_original(false)
	if step==0: draft.name=name_input.text
	var error:=Profile.name_error(str(draft.name))
	if error!="": status.text=error; return
	draft.name=draft.name.strip_edges()
	if step<2: step+=1; render()
	else:
		saving=true; next_button.disabled=true; back_button.disabled=true; _update_history_buttons()
		status.text="正在收好你的旅人证……"; save_requested.emit(draft.duplicate(true))

func save_failed(reason: String) -> void:
	saving=false; next_button.disabled=false; back_button.disabled=false; _update_history_buttons()
	status.add_theme_color_override("font_color",Color("#b16653")); status.text="没能保存："+reason+"。请重试。"

func back() -> void:
	if saving: return
	preview_original(false)
	if step>0: step-=1; render()
	elif not first_creation: cancel_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE: back()
		elif step==1 and event.ctrl_pressed:
			if event.keycode==KEY_Z:
				if event.shift_pressed: redo()
				else: undo()
			elif event.keycode==KEY_Y: redo()
		get_viewport().set_input_as_handled()
