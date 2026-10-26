extends CanvasLayer
## Single modal coordinator. Commands are injected by the HUD; owns UI preferences only.
const Cozy = preload("res://src/ui/cozy_ui.gd")
const Fonts = preload("res://src/ui/ui_font.gd")
const PREFS := "user://island_ui.cfg"
signal command_requested(command: String)
signal oxygen_feedback_changed(enabled: bool)
var hud: CanvasLayer
var presenters := {}
var active := false
var page := "pause"
var history: Array[String] = []
var feedback_enabled := true
var _root: Control
var _shade: ColorRect
var _paper: PanelContainer
var _body: VBoxContainer
var _title: Label
var _subtitle: Label
var _hint: Label
var _font: Font
var _previous_pause := false
var _focus: Control
var _changing := false
var buttons := {}

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("cozy_skip",true)
	_font = Fonts.make(PackedStringArray(["PingFang SC","Hiragino Sans GB"]))
	_root = Control.new();_root.set_anchors_preset(Control.PRESET_FULL_RECT);_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_shade = ColorRect.new();_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.13,0.22,0.20,0.30);_root.add_child(_shade)
	_paper = PanelContainer.new();_root.add_child(_paper)
	var outer := VBoxContainer.new();outer.add_theme_constant_override("separation",20);_paper.add_child(outer)
	var tag := label("S E A   /   海 上 慢 生 活",14,Cozy.TEAL);outer.add_child(tag)
	_title = label("歇一会儿吧",32);outer.add_child(_title)
	_subtitle = label("风景会等你，慢慢来。",17,Cozy.DIM);outer.add_child(_subtitle)
	_body = VBoxContainer.new();_body.add_theme_constant_override("separation",12);outer.add_child(_body)
	_hint = label("Esc 返回   ·   Enter 选择",15,Cozy.DIM);outer.add_child(_hint)
	Cozy.paper(_paper,Cozy.TEAL,false)
	var margins: StyleBox=_paper.get_theme_stylebox("panel")
	margins.content_margin_left=52;margins.content_margin_right=52
	margins.content_margin_top=44;margins.content_margin_bottom=44
	get_viewport().size_changed.connect(_place)
	_load_preferences()
	visible = false

func label(text: String, pixels := 18, color := Cozy.INK) -> Label:
	var node := Label.new();node.text=text
	node.add_theme_font_override("font",_font);node.add_theme_font_size_override("font_size",maxi(22,pixels))
	node.add_theme_color_override("font_color",color)
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.custom_minimum_size.x=440
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return node

func bind(owner_hud: CanvasLayer, views: Dictionary) -> void:
	hud = owner_hud;presenters = views
	for id in presenters:
		presenters[id].visibility_changed.connect(_external_changed.bind(id))
	oxygen_feedback_changed.emit(feedback_enabled)

func _external_changed(id: String) -> void:
	if _changing or not presenters[id].visible: return
	_changing = true
	if active: close_menu()
	if hud._panel_open: hud.close_card()
	for other in presenters:
		if other != id and presenters[other].visible: _close_presenter(other)
	_changing = false
	_sync_backdrop()

func _close_presenter(id: String) -> void:
	var node: Node = presenters[id]
	if id == "salvage": node.cancel()
	else: node.set_open(false)

func external_open() -> bool:
	for node in presenters.values():
		if node.visible: return true
	return false

func _sync_backdrop() -> void:
	# Under all independent panels, above world annotations. The HUD owns this screen layer.
	if hud: hud.set_external_modal(external_open())

func _process(_delta: float) -> void:
	_sync_backdrop()

func show_menu(target := "pause") -> void:
	if not active:
		_focus = get_viewport().gui_get_focus_owner()
		_previous_pause = get_tree().paused
		get_tree().paused = true
		active = true;visible = true;history.clear()
		if hud: hud._toast_box.hide();hud._launch.hide();hud._world_actions.hide()
		if hud and hud._panel_open: hud._panel.hide();hud._hints.hide();hud._backdrop.hide()
		page = target
		_render()
		Cozy.reveal(_paper)
	else:
		history.append(page);page = target;_render()

func note(text: String) -> void:
	_subtitle.text=text

func close_menu() -> void:
	if not active: return
	active = false;visible = false
	get_tree().paused = _previous_pause
	history.clear()
	if hud:
		hud._launch.visible=not hud._panel_open and not external_open()
		hud._world_actions.visible=hud._launch.visible
	if hud and hud._panel_open: hud._panel.show();hud._hints.show();hud._backdrop.show()
	if is_instance_valid(_focus) and _focus.is_visible_in_tree(): _focus.grab_focus()

func _close_popup(node: Node) -> bool:
	var children:=node.get_children(true)
	children.reverse()
	for child in children:
		if _close_popup(child): return true
	if node is Window and node.visible:
		node.hide();return true
	return false

func back() -> void:
	for presenter in presenters.values():
		if presenter.visible and _close_popup(presenter): return
	if active:
		if history.is_empty(): close_menu()
		else: page = history.pop_back();_render()
		return
	for id in ["orders","salvage","grade","camera"]:
		if presenters.has(id) and presenters[id].visible:
			_close_presenter(id);return
	if hud and hud._panel_open:
		hud.back();return
	show_menu()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if key == KEY_ESCAPE:
		back();get_viewport().set_input_as_handled()
	elif active:
		# GUI receives navigation/activation; world never sees other keys while paused.
		if key not in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_TAB,KEY_ENTER,KEY_SPACE]: get_viewport().set_input_as_handled()
	elif key == KEY_F9:
		show_menu("load");get_viewport().set_input_as_handled()
	elif external_open() and key in [KEY_B,KEY_TAB,KEY_C,KEY_P]:
		# Existing command router rejects switching during trade/minigame.
		hud.command_requested.emit("bag" if key in [KEY_B,KEY_TAB] else ("camera" if key==KEY_C else "grade"))
		get_viewport().set_input_as_handled()

func button(id: String, text: String, action: Callable, _tint := Cozy.CREAM) -> Button:
	var b := Button.new();b.text=text;b.custom_minimum_size=Vector2(0,48)
	b.add_theme_font_override("font",_font);_body.add_child(b)
	Cozy.style_tree(b)
	b.add_theme_stylebox_override("normal",Cozy.surface(Color.TRANSPARENT,24))
	b.add_theme_font_size_override("font_size",26)
	var focus:=Cozy.surface(Cozy.GOLD,24);focus.draw_center=true
	b.add_theme_stylebox_override("focus",focus)
	var pointer:=preload("res://src/ui/island_pointer.gd").new();pointer.button=b;b.add_child(pointer)
	b.pressed.connect(action);buttons[id]=b
	return b

func _render() -> void:
	for node in _body.get_children(): _body.remove_child(node);node.queue_free()
	buttons.clear()
	match page:
		"pause":
			_title.text="歇一会儿吧";_subtitle.text="已暂停 · 海风与家园，都在等你回来。"
			button("resume","继续今天的生活",close_menu,Cozy.GOLD)
			button("save","记下今天的进度",func(): command_requested.emit("save"))
			button("load","读取上次的记录",func(): show_menu("load"))
			button("settings","偏好设置",func(): show_menu("settings"))
			button("help","操作小手册",func(): show_menu("help"))
			button("quit","结束今天的旅程",func(): show_menu("quit"))
		"load":
			_title.text="回到上一次记录？";_subtitle.text="尚未保存的进度会被替换。潜水时需要先上浮。"
			button("cancel","再想一想",back,Cozy.GOLD)
			button("confirm_load","读取记录",func(): close_menu();command_requested.emit("load"))
		"quit":
			_title.text="今天就到这里吗？";_subtitle.text="离开前记得保存。潜水或打捞时，请先回到安全状态。"
			button("cancel","再待一会儿",back,Cozy.GOLD)
			button("save","先保存进度",func(): command_requested.emit("save"))
			button("confirm_quit","确认退出游戏",func(): get_tree().quit(),Cozy.CORAL)
		"settings":
			_title.text="让自己舒服一点";_subtitle.text="这些偏好只影响画面与操作反馈。"
			_toggle("motion","柔和界面动画",Cozy.motion_enabled,func(on): Cozy.motion_enabled=on;_save_preferences())
			_toggle("oxygen","低氧提醒抖动",feedback_enabled,func(on): feedback_enabled=on;oxygen_feedback_changed.emit(on);_save_preferences())
			_toggle("fullscreen","全屏显示",DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN,func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
			_body.add_child(label("主音量",17))
			var volume := HSlider.new();volume.min_value=0;volume.max_value=100;volume.step=1
			volume.value=AudioServer.get_bus_volume_linear(0)*100;_body.add_child(volume);Cozy.style_tree(volume)
			volume.value_changed.connect(func(value): AudioServer.set_bus_volume_linear(0,value/100);_save_preferences())
			button("return","返回",back)
		"help":
			_title.text="海上的生活指南";_subtitle.text="用鼠标慢慢探索，也可以试试这些按键。"
			for line in ["点击目的地  ·  走过去或划船前往","靠近物件按住 E  ·  采集与操作","B / Tab  ·  打开或收起随身手册","Esc  ·  返回上层；世界中打开暂停菜单","左右键翻页 / 上下键选图标 / Enter 确认","右键拖拽 / 滚轮  ·  观察与缩放","潜水时 F 开关头灯；点击上浮回到海面","F5 保存 / F9 读取确认"]: _body.add_child(label(line,17))
			button("return","记住啦",back,Cozy.GOLD)
	_place.call_deferred()
	if not buttons.is_empty(): buttons.values()[0].grab_focus.call_deferred()

func _toggle(id: String, title: String, on: bool, callback: Callable) -> void:
	var b := button(id,title+"    "+("开启" if on else "关闭"),func(): pass)
	b.toggle_mode=true;b.button_pressed=on
	b.toggled.connect(func(value): b.text=title+"    "+("开启" if value else "关闭");callback.call(value))

func _place() -> void:
	Cozy.place(_paper,580)

func _save_preferences() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui","motion",Cozy.motion_enabled);cfg.set_value("ui","oxygen_feedback",feedback_enabled)
	cfg.set_value("audio","master",AudioServer.get_bus_volume_linear(0));cfg.save(PREFS)

func _load_preferences() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) != OK: return
	Cozy.motion_enabled=bool(cfg.get_value("ui","motion",true));feedback_enabled=bool(cfg.get_value("ui","oxygen_feedback",true))
	AudioServer.set_bus_volume_linear(0,clampf(float(cfg.get_value("audio","master",1.0)),0,1))
