extends Control
## Presentation only: the controller owns selection, approach and safe removal.
const Catalog = preload("res://src/building/building_catalog.gd")
const ItemDB = preload("res://src/inventory/item_db.gd")
const FONT = preload("res://src/ui/fonts/LXGW975YuanSC-700W.ttf")
signal requested
signal confirmed(id: String)
signal cancelled

class HammerGlyph extends Control:
	var tint := Color("#76543d")
	func _draw() -> void:
		var fit := minf(size.x,size.y)/44.0
		draw_set_transform((size-Vector2.ONE*44.0*fit)/2,0.0,Vector2.ONE*fit)
		# Wooden shaft and the broad iron head remain legible at cursor size.
		draw_line(Vector2(11,35),Vector2(28,16),Color("#6b4b35"),9.0,true)
		draw_line(Vector2(11,34),Vector2(27,16),Color("#d4a362"),5.0,true)
		draw_colored_polygon(PackedVector2Array([Vector2(17,12),Vector2(25,4),Vector2(39,16),Vector2(35,24),Vector2(30,25)]),tint)
		draw_line(Vector2(18,12),Vector2(25,6),Color("#f4e6c6"),2.0,true)
		draw_set_transform(Vector2.ZERO)

class HammerButton extends Button:
	var selected := false:
		set(value): selected=value;queue_redraw()
	func _init() -> void:
		set_meta("cozy_skip",true)
		custom_minimum_size=Vector2(72,72)
	func _ready() -> void:
		size=custom_minimum_size;mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		for state in ["normal","hover","pressed","disabled","focus"]:
			add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var glyph:=HammerGlyph.new();glyph.position=Vector2(14,12);glyph.size=Vector2(44,44)
		glyph.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(glyph)
		mouse_entered.connect(queue_redraw);mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw);focus_exited.connect(queue_redraw)
	func _draw() -> void:
		var fill:=Color("#e9c47c") if selected or is_hovered() else Color("#fff6dc")
		draw_circle(Vector2(36,40),32,Color(0.20,0.15,0.09,0.22))
		draw_circle(Vector2(36,36),32,fill)
		draw_arc(Vector2(36,36),32,0,TAU,48,Color("#775d3c"),2.5,true)
		if selected or has_focus(): draw_arc(Vector2(36,36),35,0,TAU,48,Color("#4e9f8f"),2.0,true)

var launcher: Button
var cursor: Control
var target_tip: PanelContainer
var target_label: Label
var blocker: ColorRect
var confirmation: Panel
var question: Label
var details: Label
var yes_button: Button
var no_button: Button
var active := false
var target: Dictionary = {}
var target_reason := ""
var _pending_id := ""
var _focus_before: Control
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _cursor_hidden := false
var launcher_visibility_query: Callable

func _init() -> void:
	set_meta("cozy_skip",true)
	process_mode=Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	launcher=HammerButton.new();launcher.name="DemolitionButton";launcher.tooltip_text="拆除 · 选择物件并确认后返还材料"
	add_child(launcher);launcher.pressed.connect(func(): requested.emit())
	cursor=HammerGlyph.new();cursor.name="HammerCursor";cursor.size=Vector2(44,44)
	cursor.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(cursor);cursor.hide()
	target_tip=PanelContainer.new();target_tip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var tooltip_style:=_paper(Color("#fff6dc"));tooltip_style.content_margin_left=14;tooltip_style.content_margin_right=14
	tooltip_style.content_margin_top=9;tooltip_style.content_margin_bottom=9
	target_tip.add_theme_stylebox_override("panel",tooltip_style);add_child(target_tip)
	target_label=_label("",18);target_tip.add_child(target_label);target_tip.hide()
	blocker=ColorRect.new();blocker.color=Color(0.12,0.16,0.12,0.28)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(blocker);blocker.hide()
	confirmation=Panel.new();confirmation.name="DemolitionConfirmation";confirmation.size=Vector2(520,300)
	confirmation.add_theme_stylebox_override("panel",_paper(Color("#f7eed7")));blocker.add_child(confirmation)
	question=_label("确认拆除？",28);question.position=Vector2(28,23);confirmation.add_child(question)
	details=_label("",21);details.position=Vector2(28,76);details.size=Vector2(464,130)
	details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;confirmation.add_child(details)
	no_button=_button("否 · 保留",Vector2(28,230),Color("#e2eee1"))
	yes_button=_button("是 · 拆除",Vector2(270,230),Color("#f3ccaf"))
	confirmation.add_child(no_button);confirmation.add_child(yes_button)
	no_button.pressed.connect(dismiss);yes_button.pressed.connect(_accept)
	_layout()

func _paper(fill: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=fill;style.border_color=Color("#b09a74")
	style.set_border_width_all(2);style.set_corner_radius_all(18)
	style.shadow_color=Color(0.16,0.12,0.08,0.20);style.shadow_size=8;style.shadow_offset=Vector2(0,4)
	return style

func _label(value: String, pixels: int) -> Label:
	var label:=Label.new();label.text=value;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",FONT);label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",Color("#765d3c"));return label

func _button(value: String, at: Vector2, fill: Color) -> Button:
	var button:=Button.new();button.text=value;button.position=at;button.size=Vector2(222,46)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;button.set_meta("cozy_skip",true)
	button.add_theme_font_override("font",FONT);button.add_theme_font_size_override("font_size",22)
	for state in ["normal","hover","pressed","focus"]:
		var style:=_paper(fill if state=="normal" else fill.lightened(0.08))
		style.shadow_size=0
		if state=="focus": style.border_color=Color("#489f8d");style.set_border_width_all(3)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state,Color("#765d3c"))
	return button

func _layout() -> void:
	if launcher==null: return
	var extent:=get_viewport().get_visible_rect().size
	var fit:=minf(1.0,minf(extent.x/1600.0,extent.y/1000.0))
	launcher.scale=Vector2.ONE*fit
	# CornerHUD's menu occupies the right column; its left slot was unused.
	launcher.position=Vector2(extent.x-164*fit-28,28)
	var dialog_fit:=minf(1.0,minf((extent.x-32)/520.0,(extent.y-32)/300.0))
	confirmation.scale=Vector2.ONE*dialog_fit
	confirmation.position=(extent-confirmation.size*dialog_fit)/2

func set_launcher_visible(on: bool) -> void:
	if launcher!=null: launcher.visible=on

func set_active(on: bool) -> void:
	if active==on: return
	active=on
	if launcher!=null: launcher.selected=on
	if on: _previous_mouse_mode=Input.mouse_mode
	else:
		dismiss();target={};target_reason="";_restore_cursor()
		if cursor!=null: cursor.hide()
		if target_tip!=null: target_tip.hide()

func set_target(row: Dictionary, reason: String) -> void:
	if confirmation_open(): return
	target=row.duplicate(true);target_reason=reason
	if target_label==null: return
	var name:=str(Catalog.RECIPES.get(str(row.get("kind","")),{}).get("name",""))
	target_label.text=(name+"\n" if name!="" else "")+(reason if reason!="" else "点击选择后确认拆除" if name!="" else "点击自建物件 · Esc 退出")
	target_label.add_theme_color_override("font_color",Color("#a4533f") if reason!="" else Color("#527b60"))
	if cursor!=null:
		cursor.tint=Color("#a95543") if reason!="" else Color("#527b60");cursor.queue_redraw()

func ask(row: Dictionary, refund: Dictionary) -> bool:
	if not active or confirmation_open() or str(row.get("id",""))=="": return false
	if str(target.get("id",""))==str(row.id) and target_reason!="": return false
	_pending_id=str(row.id)
	var name:=str(Catalog.RECIPES.get(str(row.get("kind","")),{}).get("name","自建物件"))
	var parts: Array[String]=[]
	for id in refund: parts.append("%s ×%d"%[ItemDB.label(str(id)),int(refund[id])])
	details.text="%s\n全额返还：%s\n角色会先走近，安全检查通过后拆除。"%[name,"、".join(parts) if not parts.is_empty() else "无材料"]
	_focus_before=get_viewport().gui_get_focus_owner()
	blocker.show();cursor.hide();target_tip.hide();_restore_cursor()
	no_button.grab_focus()
	return true

func confirmation_open() -> bool:
	return _pending_id!=""

func dismiss() -> bool:
	var was_open:=confirmation_open();_pending_id=""
	if blocker!=null: blocker.hide()
	if was_open and is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree(): _focus_before.grab_focus()
	elif was_open:
		var focused:=get_viewport().gui_get_focus_owner()
		if focused!=null and confirmation.is_ancestor_of(focused): focused.release_focus()
	_focus_before=null
	return was_open

func _accept() -> void:
	if not active or not confirmation_open(): return
	var id:=_pending_id
	dismiss() # Clear before emitting: a second click cannot confirm the old ID.
	confirmed.emit(id)

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int=event.physical_keycode if event.physical_keycode else event.keycode
		if code==KEY_ESCAPE:
			if not dismiss(): cancelled.emit()
			return true
		if confirmation_open():
			if code in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:
				if yes_button.has_focus(): yes_button.pressed.emit()
				else: no_button.pressed.emit()
			elif code in [KEY_LEFT,KEY_RIGHT,KEY_TAB]:
				if no_button.has_focus(): yes_button.grab_focus()
				else: no_button.grab_focus()
			return true
	return confirmation_open()

func is_ui_point(screen: Vector2) -> bool:
	return confirmation_open() or (launcher!=null and launcher.visible and launcher.get_global_rect().has_point(screen))

func _restore_cursor() -> void:
	if _cursor_hidden:
		if Input.mouse_mode==Input.MOUSE_MODE_HIDDEN: Input.mouse_mode=_previous_mouse_mode
		_cursor_hidden=false

func _process(_delta: float) -> void:
	_layout()
	if launcher_visibility_query.is_valid(): set_launcher_visible(bool(launcher_visibility_query.call()))
	if not active or confirmation_open() or get_tree().paused:
		cursor.hide();target_tip.hide();_restore_cursor();return
	var pointer:=get_viewport().get_mouse_position()
	var hovered:=get_viewport().gui_get_hovered_control()
	var over_ui:=hovered!=null and hovered.mouse_filter!=Control.MOUSE_FILTER_IGNORE
	var show_cursor:=get_viewport().get_visible_rect().has_point(pointer) and not over_ui
	cursor.visible=show_cursor;target_tip.visible=show_cursor
	if not show_cursor: _restore_cursor();return
	if not _cursor_hidden:
		Input.mouse_mode=Input.MOUSE_MODE_HIDDEN;_cursor_hidden=true
	cursor.position=pointer-Vector2(10,10)
	target_tip.reset_size()
	var extent:=get_viewport().get_visible_rect().size
	target_tip.position=Vector2(clampf(pointer.x+32,8,maxf(8,extent.x-target_tip.size.x-8)),clampf(pointer.y+30,8,maxf(8,extent.y-target_tip.size.y-8)))

func _exit_tree() -> void:
	_restore_cursor()
