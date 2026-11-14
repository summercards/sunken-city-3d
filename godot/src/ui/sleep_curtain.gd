extends CanvasLayer
## Iris closes on the player, holds black for the day change, then opens at home.
signal phase_changed(phase: String)
const CLOSE_SECONDS := 0.85
const OPEN_SECONDS := 1.05
## 两段黑幕文字的停留时长（2026-11-01 需求：原 0.3 / 0.65 秒太快，看不清）。
## 淡入与淡出也相应放长到 0.4 秒以上，慢慢亮起来、慢慢灭掉，读起来才不突兀。
const COVER_FADE := 0.45
const COVER_HOLD := 2.4
const MORNING_FADE := 0.45
const MORNING_HOLD := 2.6
var focus_query: Callable
var shade: ColorRect
var caption: Label
var iris: ShaderMaterial
var phase := "idle"
var _iris_generation := 0
var _iris_tween: Tween
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
	await _close_iris()
	var tween := create_tween()
	tween.tween_property(caption,"modulate:a",1.0,COVER_FADE)
	tween.tween_interval(COVER_HOLD)
	tween.tween_property(caption,"modulate:a",0.0,COVER_FADE)
	await tween.finished


func uncover(text: String) -> void:
	caption.text = text
	_set_phase("morning")
	var tween := create_tween()
	tween.tween_property(caption,"modulate:a",1.0,MORNING_FADE)
	tween.tween_interval(MORNING_HOLD)
	tween.tween_property(caption,"modulate:a",0.0,MORNING_FADE)
	await tween.finished
	await _open_iris()


## 无文字的圆幕（SEA-ROOM 进出房间，2026-11-05）。
##
## 玩家要求「用日夜变化那个过场，但不要增加文字」。所以只借用合拢/打开与
## 遮黑这一段，黑幕上不写任何字 —— 文案由调用方决定，本方法不碰 caption。
func cover_blank() -> void:
	caption.text = ""
	caption.modulate.a = 0.0
	await _close_iris()


func uncover_blank() -> void:
	caption.text = ""
	caption.modulate.a = 0.0
	await _open_iris()


## 房间恢复使旧圆幕等待失效；不启动另一套过场。
func cancel_blank() -> void:
	_iris_generation += 1
	if _iris_tween != null and _iris_tween.is_valid(): _iris_tween.kill()
	openness = 1.0
	caption.text = ""
	caption.modulate.a = 0.0
	hide()
	_set_phase("idle")


func _close_iris() -> void:
	_iris_generation += 1
	var generation := _iris_generation
	openness = 1.0
	_sample_focus()
	show()
	_set_phase("closing")
	if generation != _iris_generation: return
	_iris_tween = create_tween()
	_iris_tween.tween_property(self,"openness",0.0,CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while generation == _iris_generation and _iris_tween.is_running():
		await get_tree().process_frame
	if generation != _iris_generation: return
	_set_phase("closed")


func _open_iris() -> void:
	_iris_generation += 1
	var generation := _iris_generation
	# The wake/teleport command has moved the camera while the screen was black.
	_sample_focus()
	_set_phase("opening")
	if generation != _iris_generation: return
	_iris_tween = create_tween()
	_iris_tween.tween_property(self,"openness",1.0,OPEN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while generation == _iris_generation and _iris_tween.is_running():
		await get_tree().process_frame
	if generation != _iris_generation: return
	hide()
	_set_phase("idle")
