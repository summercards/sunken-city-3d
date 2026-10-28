extends CanvasLayer
## Iris closes on the player, holds black for the day change, then opens at home.
signal phase_changed(phase: String)
const CLOSE_SECONDS := 0.85
const OPEN_SECONDS := 1.05
var focus_query: Callable
var shade: ColorRect
var caption: Label
var iris: ShaderMaterial
var phase := "idle"
var openness := 1.0:
	set(value):
		openness = clampf(value,0.0,1.0)
		if iris != null: iris.set_shader_parameter("openness",openness)

func _ready() -> void:
	layer = 100
	shade = ColorRect.new()
	shade.set_meta("cozy_skip",true)
	shade.color = Color.BLACK
	iris = ShaderMaterial.new()
	iris.shader = preload("res://shaders/sleep_iris.gdshader")
	shade.material = iris
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	caption = Label.new()
	caption.set_meta("cozy_skip",true)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font",preload("res://src/ui/ui_font.gd").embedded())
	caption.add_theme_font_size_override("font_size",36)
	caption.modulate = Color("fff6df")
	shade.add_child(caption)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.modulate.a = 0.0
	_sync_viewport()
	hide()

func _process(_delta: float) -> void:
	if visible: _sync_viewport()

func _sync_viewport() -> void:
	iris.set_shader_parameter("viewport_size",get_viewport().get_visible_rect().size)

func _sample_focus() -> void:
	var rect := get_viewport().get_visible_rect()
	var point := rect.size*0.5
	if focus_query.is_valid(): point = focus_query.call()
	# Offscreen players (e.g. a manually panned camera) close at the nearest screen edge.
	var uv := point/rect.size
	iris.set_shader_parameter("focus_uv",uv.clamp(Vector2.ZERO,Vector2.ONE))
	_sync_viewport()

func _set_phase(value: String) -> void:
	phase = value
	phase_changed.emit(phase)

func _input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()

func cover(text: String) -> void:
	caption.text = text
	caption.modulate.a = 0.0
	openness = 1.0
	_sample_focus()
	show()
	_set_phase("closing")
	var tween := create_tween()
	tween.tween_property(self,"openness",0.0,CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_set_phase("closed")
	tween = create_tween()
	tween.tween_property(caption,"modulate:a",1.0,0.18)
	tween.tween_interval(0.3)
	tween.tween_property(caption,"modulate:a",0.0,0.18)
	await tween.finished

func uncover(text: String) -> void:
	caption.text = text
	_set_phase("morning")
	var tween := create_tween()
	tween.tween_property(caption,"modulate:a",1.0,0.2)
	tween.tween_interval(0.65)
	tween.tween_property(caption,"modulate:a",0.0,0.2)
	await tween.finished
	# The wake command has moved both player and camera while the screen was black.
	_sample_focus()
	_set_phase("opening")
	tween = create_tween()
	tween.tween_property(self,"openness",1.0,OPEN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	hide()
	_set_phase("idle")
