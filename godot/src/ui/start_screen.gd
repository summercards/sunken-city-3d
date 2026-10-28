extends CanvasLayer
## Title-only presentation; the bootstrap owns gameplay suspension and camera handoff.
signal start_requested
const Cream := Color("#fff9e9")
var root_control: Control
var logo: Control
var start_button: Button
var _entering := false
var _reveal: Tween
var _font: FontVariation

func _ready() -> void:
	layer = 100
	root_control = Control.new()
	root_control.set_meta("cozy_skip",true)
	root_control.set_meta("preserve_font",true)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root_control)
	_font = FontVariation.new()
	_font.base_font = preload("res://src/ui/ui_font.gd").embedded()
	_font.variation_embolden = 0.36
	_font.variation_transform = Transform2D(Vector2(1,0),Vector2(-0.13,1),Vector2.ZERO)
	logo = Control.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.custom_minimum_size = Vector2(500,300)
	root_control.add_child(logo)
	var letters := "SEA"
	for i in 3:
		var letter := Label.new()
		letter.text = letters[i]
		letter.add_theme_font_override("font",_font)
		letter.add_theme_font_size_override("font_size",220)
		letter.add_theme_color_override("font_color",Cream)
		letter.add_theme_color_override("font_outline_color",Cream)
		letter.add_theme_constant_override("outline_size",0)
		letter.position = Vector2(i*144,[0,-9,2][i])
		letter.rotation = deg_to_rad([-7,-2,5][i])
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.add_child(letter)
	start_button = Button.new()
	start_button.name = "StartGame"
	start_button.text = "开始游戏"
	start_button.custom_minimum_size = Vector2(310,70)
	start_button.add_theme_font_override("font",_font)
	start_button.add_theme_font_size_override("font_size",42)
	for state in ["normal","hover","pressed","focus","disabled"]:
		start_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		start_button.add_theme_color_override(state,Cream)
	start_button.rotation = deg_to_rad(-5)
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	root_control.add_child(start_button)
	start_button.pressed.connect(_start)
	start_button.mouse_entered.connect(func(): if not _entering: create_tween().tween_property(start_button,"modulate",Color("#ffe29a"),0.18))
	start_button.mouse_exited.connect(func(): if not _entering: create_tween().tween_property(start_button,"modulate",Color.WHITE,0.18))
	root_control.resized.connect(_layout)
	_layout()
	_reveal = create_tween().set_parallel(true)
	logo.modulate.a = 0
	start_button.modulate.a = 0
	var finish := logo.position
	logo.position.y += 24
	_reveal.tween_property(logo,"modulate:a",1.0,1.2).set_delay(0.15).set_trans(Tween.TRANS_SINE)
	_reveal.tween_property(logo,"position",finish,1.5).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal.tween_property(start_button,"modulate:a",1.0,0.9).set_delay(0.85).set_trans(Tween.TRANS_SINE)
	start_button.grab_focus()

func _layout() -> void:
	var extent := get_viewport().get_visible_rect().size
	var fit := minf(extent.x/1600.0,extent.y/1000.0)
	logo.scale = Vector2.ONE*fit
	logo.position = Vector2(extent.x*0.61,extent.y*0.19)
	start_button.scale = Vector2.ONE*fit
	start_button.position = Vector2(extent.x*0.755,extent.y*0.47)
	start_button.pivot_offset = start_button.size*0.5

func _start() -> void:
	if _entering: return
	_entering = true
	start_button.disabled = true
	if _reveal: _reveal.kill()
	var fade := create_tween()
	fade.tween_property(root_control,"modulate:a",0.0,0.45).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(func(): start_requested.emit())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER,KEY_SPACE]: _start()
		get_viewport().set_input_as_handled()
