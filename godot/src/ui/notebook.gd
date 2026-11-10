extends Control
## Category index, six cards per page and a readable detail leaf.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Art = preload("res://src/ui/illustrated_icons.gd")
const CATEGORIES := [["overview","总目录"],["plant","种植"],["goods","物产"],["life","生活"]]
const PAGE_SIZE := 6
signal requested(command: String)
signal close_requested
var font: Font
var query: Callable
var category := "overview"
var page := 0
var selected := ""
var entries: Array=[]
var categories := {}
var cards: Array[Button]=[]
var grid: GridContainer
var detail_title: Label
var detail_tag: Label
var detail_body: Label
var detail_facts: Label
var detail_icon: TextureRect
var action_button: Button
var page_label: Label
var previous: Button
var next: Button
var index_label: Label
var _action := ""
var _focus_area := "cards"
var _selected_index := 0
var _display_signature := ""
var _has_display_signature := false
## PERF-AUTH: counts actual rebuilds without changing the public refresh contract.
var _refresh_count := 0

func _ready() -> void:
	set_meta("cozy_skip",true)
	size=Vector2(1080,748);pivot_offset=size/2
	mouse_filter=Control.MOUSE_FILTER_STOP
	var paper:=Panel.new();paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=Cozy.surface(Cozy.CREAM,32);style.shadow_size=16;style.shadow_color=Color(0.12,0.23,0.22,0.14)
	paper.add_theme_stylebox_override("panel",style);add_child(paper)
	_add_label("S E A  /  日 子 慢 慢 记",Vector2(36,22),18,Cozy.TEAL)
	_add_label("海岛笔记",Vector2(36,48),36)
	_add_label("看看今天，也记住每一份小收获。",Vector2(242,61),21,Cozy.DIM)
	var close:=_button("×",26);close.position=Vector2(1000,30);close.size=Vector2(44,44)
	add_child(close);close.pressed.connect(func(): close_requested.emit())
	var index:=HBoxContainer.new();index.position=Vector2(36,112);index.size=Vector2(1008,66)
	index.add_theme_constant_override("separation",12);add_child(index)
	for entry in CATEGORIES:
		var button:=_button(entry[1],24);button.custom_minimum_size=Vector2(243,62)
		index.add_child(button);categories[entry[0]]=button
		button.pressed.connect(func(): show_category(entry[0]))
		button.focus_entered.connect(func(): _focus_area="categories")
	index_label=_add_label("",Vector2(40,193),20,Cozy.DIM)
	grid=GridContainer.new();grid.columns=3;grid.position=Vector2(36,232)
	grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",14);add_child(grid)
	for i in PAGE_SIZE:
		var button:=_button("",22);button.custom_minimum_size=Vector2(198,195)
		grid.add_child(button);cards.append(button)
		button.pressed.connect(func(): select_card(i))
		button.focus_entered.connect(func():
			_focus_area="cards";_selected_index=i
			var actual:=page*PAGE_SIZE+i
			if actual<entries.size(): selected=entries[actual].id;_show_detail(entries[actual]);_sync_detail_focus())
	var leaf:=Panel.new();leaf.position=Vector2(690,232);leaf.size=Vector2(354,404)
	leaf.mouse_filter=Control.MOUSE_FILTER_IGNORE
	leaf.add_theme_stylebox_override("panel",Cozy.surface(Color("#f0ecd8"),22));add_child(leaf)
	detail_tag=_add_label("",Vector2(714,248),18,Cozy.TEAL)
	detail_title=_add_label("",Vector2(714,279),28)
	detail_title.size=Vector2(250,44);detail_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_icon=_icon("vegetable");detail_icon.position=Vector2(974,272);detail_icon.size=Vector2(48,48);add_child(detail_icon)
	detail_body=_add_label("",Vector2(714,333),21)
	detail_body.size=Vector2(306,172);detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail_facts=_add_label("",Vector2(714,518),20,Cozy.DIM)
	detail_facts.size=Vector2(306,110);detail_facts.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	action_button=_button("",22);action_button.position=Vector2(690,651);action_button.size=Vector2(354,54);add_child(action_button)
	action_button.pressed.connect(func():
		if _action.begins_with("category:"): show_category(_action.trim_prefix("category:"))
		else: requested.emit(_action))
	previous=_button("‹  上一页",21);previous.position=Vector2(36,660);previous.size=Vector2(144,48);add_child(previous)
	next=_button("下一页  ›",21);next.position=Vector2(510,660);next.size=Vector2(144,48);add_child(next)
	page_label=_add_label("",Vector2(198,667),22);page_label.size.x=294;page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	previous.pressed.connect(func(): turn_page(-1));next.pressed.connect(func(): turn_page(1))
	previous.focus_entered.connect(func(): _focus_area="pager")
	next.focus_entered.connect(func(): _focus_area="pager")
	close.focus_entered.connect(func(): _focus_area="close")

func _add_label(text: String, at: Vector2, pixels: int, color:=Cozy.INK) -> Label:
	var label:=Label.new();label.text=text;label.position=at;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color);add_child(label);return label

func _button(text: String, pixels: int) -> Button:
	var button:=Button.new();button.text=text;button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",font);button.add_theme_font_size_override("font_size",pixels)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=Cozy.surface(Color("#f0ecd8") if state in ["normal","disabled"] else Cozy.GOLD,18)
		if state=="focus": style.bg_color=Color.TRANSPARENT;style.border_color=Cozy.INK;style.set_border_width_all(3)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]: button.add_theme_color_override(state,Cozy.INK)
	return button

func _icon(kind: String) -> TextureRect:
	var icon:=TextureRect.new();icon.texture=Art.texture(kind)
	if icon.texture==null:
		icon.texture=Art.texture(kind,true);icon.modulate=Cozy.TEAL
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return icon

func show_category(id: String) -> void:
	category=id;page=0;selected="";_focus_area="cards";_selected_index=0;refresh();_focus_first()

func page_count() -> int: return maxi(1,ceili(entries.size()/float(PAGE_SIZE)))

func refresh() -> void:
	if not query.is_valid(): return
	var data: Dictionary=query.call()
	var next_entries: Array=data.get(category,[])
	var next_page := clampi(page,0,maxi(0,ceili(next_entries.size()/float(PAGE_SIZE))-1))
	var next_selected := selected
	var selected_index := next_page*PAGE_SIZE
	for i in range(next_page*PAGE_SIZE,mini(next_entries.size(),(next_page+1)*PAGE_SIZE)):
		if str(next_entries[i].id)==next_selected:
			selected_index=i
			break
	if not next_entries.is_empty():
		next_selected=str(next_entries[selected_index].id)
	var signature := _signature(data,next_page,next_selected)
	if _has_display_signature and signature == _display_signature:
		return
	_display_signature=signature
	_has_display_signature=true
	_refresh_count+=1
	entries=next_entries
	page=next_page
	selected=next_selected
	for id in categories:
		categories[id].add_theme_stylebox_override("normal",Cozy.surface(Cozy.GOLD if id==category else Color("#eee9d5"),18))
		categories[id].add_theme_color_override("font_color",Cozy.INK if id==category else Cozy.DIM)
	selected_index=page*PAGE_SIZE
	for i in range(page*PAGE_SIZE,mini(entries.size(),(page+1)*PAGE_SIZE)):
		if entries[i].id==selected: selected_index=i
	for i in PAGE_SIZE:
		var tile: Button=cards[i]
		for child in tile.get_children(): tile.remove_child(child);child.queue_free()
		var index:=page*PAGE_SIZE+i
		tile.visible=index<entries.size()
		if not tile.visible: continue
		var row: Dictionary=entries[index]
		tile.set_meta("entry_id",row.id)
		var style:=Cozy.surface(Color("#e9edce") if row.id==selected else Color("#f3efdb"),16)
		style.border_color=Color("#b3c792") if row.id==selected else Color("#e6dfc7");style.set_border_width_all(2)
		tile.add_theme_stylebox_override("normal",style)
		var icon:=_icon(row.icon);icon.position=Vector2(56,16);icon.size=Vector2(86,86);tile.add_child(icon)
		var title:=_add_label(row.title,Vector2(8,113),23);title.reparent(tile);title.position=Vector2(8,113)
		title.size=Vector2(182,34);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var subtitle:=_add_label(row.subtitle,Vector2(8,153),18,Cozy.DIM);subtitle.reparent(tile);subtitle.position=Vector2(8,153)
		subtitle.size=Vector2(182,28);subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;subtitle.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	page_label.text="%02d   /   %02d" % [page+1,page_count()]
	previous.disabled=page==0;next.disabled=page>=page_count()-1
	index_label.text="%s  ·  共 %d 条记录" % [str(categories[category].text),entries.size()]
	if not entries.is_empty():
		_selected_index=selected_index-page*PAGE_SIZE
		_show_detail(entries[selected_index]);_sync_detail_focus()
	var focused:=get_viewport().gui_get_focus_owner()
	if is_visible_in_tree() and (focused==null or not is_ancestor_of(focused) or not focused.is_visible_in_tree()):
		_focus_first()

func _signature(data: Dictionary, display_page: int, display_selected: String) -> String:
	var parts: Array[String] = [category,str(display_page),display_selected]
	for id in CATEGORIES:
		var rows: Array=data.get(id[0],[])
		parts.append(id[0]+":"+str(rows.size()))
		for row in rows: parts.append(JSON.stringify(row))
	return "|".join(parts)

func _show_detail(row: Dictionary) -> void:
	detail_tag.text=row.tag;detail_title.text=row.title;detail_body.text=row.body
	detail_facts.text="\n".join(PackedStringArray(row.facts))
	detail_icon.texture=Art.texture(row.icon);detail_icon.modulate=Color.WHITE
	if detail_icon.texture==null: detail_icon.texture=Art.texture(row.icon,true);detail_icon.modulate=Cozy.TEAL
	_action=row.action;action_button.text=row.button;action_button.visible=_action!=""
	action_button.disabled=bool(row.get("disabled",false))
	if row.get("reason","")!="": detail_facts.text+="\n"+str(row.reason)

func select_card(index: int) -> void:
	var actual:=page*PAGE_SIZE+index
	if actual>=entries.size(): return
	selected=entries[actual].id;_selected_index=index;_focus_area="cards";refresh()

func _sync_detail_focus() -> void:
	for i in cards.size():
		var index:=page*PAGE_SIZE+i
		var style:=Cozy.surface(Color("#e9edce") if index<entries.size() and entries[index].id==selected else Color("#f3efdb"),16)
		style.border_color=Cozy.TEAL;style.set_border_width_all(3 if index<entries.size() and entries[index].id==selected else 0)
		cards[i].add_theme_stylebox_override("normal",style)

func _focus_first() -> void:
	if not entries.is_empty():
		var index:=clampi(_selected_index,0,mini(PAGE_SIZE,entries.size()-page*PAGE_SIZE)-1)
		cards[index].grab_focus.call_deferred()
	else:
		categories[category].grab_focus.call_deferred()

func back() -> bool:
	if get_viewport().gui_get_focus_owner()==action_button:
		_focus_first();return true
	return false

func activate_focused() -> void:
	var focused:=get_viewport().gui_get_focus_owner()
	if focused in cards:
		if action_button.visible and not action_button.disabled: action_button.grab_focus();_focus_area="detail"
	elif focused is Button and is_ancestor_of(focused) and focused.is_visible_in_tree() and not focused.disabled:
		focused.pressed.emit()

func move_selection(step: int) -> void:
	var focused:=get_viewport().gui_get_focus_owner()
	if focused in categories.values():
		if abs(step)>1: _focus_first();return
		var index:=categories.values().find(focused)
		categories.values()[posmod(index+step,CATEGORIES.size())].grab_focus();return
	if focused==action_button or focused==previous or focused==next:
		_focus_first();return
	if entries.is_empty(): categories[category].grab_focus();return
	var count:=mini(PAGE_SIZE,entries.size()-page*PAGE_SIZE)
	var target:=_selected_index+step
	if step==-3 and target<0: categories[category].grab_focus();return
	if step==1 and (_selected_index%3==2 or target>=count) and action_button.visible and not action_button.disabled:
		action_button.grab_focus();_focus_area="detail";return
	if target<0 or target>=count:
		if step>0 and not next.disabled: next.grab_focus()
		elif step<0 and not previous.disabled: previous.grab_focus()
		return
	cards[target].grab_focus()

func turn_page(direction: int) -> void:
	var target:=clampi(page+direction,0,page_count()-1)
	if target==page: return
	page=target;selected="";_selected_index=0;_focus_area="cards";refresh();_focus_first()
