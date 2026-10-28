extends Control
## Compact text-only status and a dismissible icon launcher. Commands stay with HUD/Main.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Art = preload("res://src/ui/illustrated_icons.gd")
const Scope = preload("res://src/core/play_scope.gd")
signal requested(command: String)
var font: Font
var status: PanelContainer
var clock_label: Label
var balance: Label
var capacity: Label
var actions: HBoxContainer
var toolbar: Control
var menu_button: Button
var popup: PanelContainer
var buttons := {}
var expanded := false

func _ready() -> void:
	set_meta("cozy_skip",true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	status=PanelContainer.new();status.name="DailyStatus";add_child(status)
	var paper:=StyleBoxEmpty.new()
	status.add_theme_stylebox_override("panel",paper)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",8);status.add_child(body)
	clock_label=_label("1月1日 07:00 · 晴",26,Color.WHITE);body.add_child(clock_label)
	var wallet:=HBoxContainer.new();wallet.add_theme_constant_override("separation",12);body.add_child(wallet)
	balance=_label("瓶盖 80",28,Color.WHITE);wallet.add_child(balance)
	var bag:=HBoxContainer.new();bag.add_theme_constant_override("separation",12);body.add_child(bag)
	capacity=_label("背包 1 / 24",28,Color.WHITE);bag.add_child(capacity)
	actions=HBoxContainer.new();actions.name="CameraFollow";add_child(actions)
	var follow:=_launcher("follow","锁定角色视角");actions.add_child(follow);buttons.follow=follow
	follow.pressed.connect(func(): requested.emit("follow"))
	toolbar=Control.new();toolbar.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(toolbar)
	menu_button=_launcher("menu","菜单");menu_button.position=Vector2(92,0)
	toolbar.add_child(menu_button);menu_button.pressed.connect(func(): set_expanded(not expanded))
	popup=PanelContainer.new();popup.position=Vector2(0,88);popup.size.x=164;toolbar.add_child(popup)
	popup.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",20);grid.add_theme_constant_override("v_separation",16);popup.add_child(grid)
	var entries: Array=[["bag","背包 B"],["notes","笔记"],["shop","商店"],["storage","仓库"],["shipping","出货箱"],["map","航海图"],["system","设置 Esc"],["craft","建造手册"]]
	if not Scope.minimal(): entries.append_array([["dive","潜水"],["build","建造"]])
	for entry in entries:
		var button:=_launcher(entry[0],entry[1]);grid.add_child(button)
		buttons[entry[0]]=button
		button.pressed.connect(func(): set_expanded(false);requested.emit(entry[0]))
	popup.hide()

func _label(text: String, pixels: int, ink: Color) -> Label:
	var label:=Label.new();label.text=text;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",Cozy.world_font());label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",ink)
	label.add_theme_color_override("font_shadow_color",Color(0.07,0.17,0.20,0.55))
	label.add_theme_constant_override("shadow_offset_x",1);label.add_theme_constant_override("shadow_offset_y",2)
	label.add_theme_constant_override("shadow_outline_size",0);label.add_theme_constant_override("outline_size",0)
	label.set_meta("cozy_world_text",true)
	return label

func _icon(kind: String, extent: int, action:=false) -> TextureRect:
	var icon:=TextureRect.new();icon.texture=Art.texture(kind,action)
	icon.custom_minimum_size=Vector2(extent,extent);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if action: icon.modulate=Cozy.TEAL
	return icon

func _button(text: String, pixels: int) -> Button:
	var button:=Button.new();button.text=text;button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font",Cozy.world_font());button.add_theme_font_size_override("font_size",pixels)
	button.set_meta("cozy_world_text",true)
	button.add_theme_constant_override("outline_size",0)
	for state in ["normal","hover","pressed","focus"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state,Cozy.CREAM)
	return button

func _launcher(kind: String, hint: String) -> Button:
	var button:=preload("res://src/ui/launcher_icon.gd").new();button.kind=kind;button.tooltip_text=hint
	return button

func place(extent: Vector2) -> void:
	var fit:=minf(1.0,minf(extent.x/1600.0,extent.y/1000.0))
	status.scale=Vector2.ONE*fit;status.size=Vector2(284,0)
	status.position=Vector2(24,extent.y-status.size.y*fit-24)
	actions.scale=Vector2.ONE*fit
	actions.position=extent-Vector2(72*fit+28,72*fit+28)
	toolbar.scale=Vector2.ONE*fit;toolbar.position=Vector2(extent.x-164*fit-28,28)

func set_follow_locked(on: bool) -> void:
	buttons.follow.selected=on
	buttons.follow.tooltip_text="视角已锁定角色 · 拖动可自由观察" if on else "锁定角色视角"

func set_expanded(on: bool) -> void:
	expanded=on;popup.visible=on;menu_button.selected=on
	if on: buttons.bag.grab_focus()

func _input(event: InputEvent) -> void:
	if not expanded or not toolbar.is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		set_expanded(false);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if not popup.get_global_rect().has_point(event.position) and not menu_button.get_global_rect().has_point(event.position):
			set_expanded(false);get_viewport().set_input_as_handled()
