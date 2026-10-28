extends CanvasLayer
## Only the menu owns its animation and selection. Callbacks own all commands.
const Bubble = preload("res://src/ui/action_bubble.gd")
const Cozy = preload("res://src/ui/cozy_ui.gd")
signal dismissed
var root: Control
var cluster: Control
var buttons: Array[Button] = []
var entries: Array = []
var anchor_query: Callable
var notify: Callable
## 层级标题：`hint_box` 是承托的奶油胶囊，`hint_label` 是里面的字。
var hint_box: PanelContainer
var hint_label: Label
var active := false
var closing := false
var animation: Tween
var generation := 0

func _ready() -> void:
	layer = 64
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			root.accept_event();close())
	cluster = Control.new()
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cluster)
	root.hide()

func open(query: Callable, options: Array, hint := "") -> void:
	generation += 1
	if animation: animation.kill()
	for node in cluster.get_children():
		cluster.remove_child(node);node.queue_free()
	hint_label = null
	hint_box = null
	buttons.clear();entries = options.duplicate(true);anchor_query = query
	active = true;closing = false;root.show()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var button := Bubble.new()
		button.kind = str(entry.get("icon","hand"))
		button.item_icon = str(entry.get("item_icon",""))
		button.caption = str(entry.get("caption",""))
		button.available = str(entry.get("blocked","")) == ""
		button.set_meta("action_id",str(entry.id))
		button.set_meta("action_label",str(entry.get("label",entry.id)))
		button.pressed.connect(func(): activate(i))
		cluster.add_child(button);buttons.append(button)
		var destination := _offset(i,entries.size())
		button.position = Vector2(-38,-38)
		if Cozy.motion_enabled:
			button.modulate.a = 0;button.scale = Vector2.ONE*0.12
			var tween := button.create_tween().set_parallel(true)
			button.entrance=tween
			tween.tween_property(button,"position",destination,0.24).set_delay(i*0.035).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(button,"scale",Vector2.ONE,0.24).set_delay(i*0.035).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(button,"modulate:a",1.0,0.12).set_delay(i*0.035)
		else: button.position = destination
	if hint != "":
		_build_hint(hint)
	_place()

## 气泡上方的层级标题（「选择种子」）。位置由 `_place` 每帧跟着气泡包围盒算，
## 不写死像素 —— 二级菜单的按钮是沿上弧排开的，标题必须让开它们。
##
## 做成奶油胶囊而不是裸文字：菜单弹出的位置往往正落在木地板或水面上，
## `INK` 深棕直接写在木色上是糊的，读不清「现在在第几级」。
func _build_hint(text: String) -> void:
	hint_box = PanelContainer.new()
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.add_theme_stylebox_override("panel", Cozy.surface(Color(1.0,0.976,0.91,0.97),16))
	hint_label = Label.new()
	hint_label.text = text
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Cozy.world_text(hint_label,0.52)
	hint_box.add_child(hint_label)
	cluster.add_child(hint_box)
	var extent := hint_box.get_combined_minimum_size()
	hint_box.size = extent
	hint_box.position = Vector2(-extent.x*0.5,-200.0)
	hint_box.modulate.a = 0.0 if Cozy.motion_enabled else 1.0
	if Cozy.motion_enabled:
		hint_box.create_tween().tween_property(hint_box,"modulate:a",1.0,0.16).set_delay(0.05)

func _offset(i: int, count: int) -> Vector2:
	if count == 1: return Vector2(-38,-128)
	var angle := lerpf(-PI*0.82,-PI*0.18,float(i)/float(count-1))
	return Vector2(cos(angle),sin(angle))*118-Vector2(38,38)

func activate(index: int) -> void:
	if not active or index < 0 or index >= entries.size(): return
	var entry: Dictionary = entries[index]
	var reason := str(entry.get("blocked",""))
	if reason != "":
		if notify.is_valid(): notify.call(reason)
		return
	var command: Callable = entry.get("command",Callable())
	close()
	if command.is_valid(): command.call()

func close(immediate := false) -> void:
	if not active and not closing: return
	active = false;closing = true
	generation += 1
	var token := generation
	if animation: animation.kill()
	for button in buttons:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if button.motion: button.motion.kill()
		if button.entrance: button.entrance.kill()
	if immediate or not Cozy.motion_enabled:
		root.hide();closing = false;dismissed.emit();return
	animation = create_tween().set_parallel(true)
	for i in buttons.size():
		var button := buttons[i]
		animation.tween_property(button,"position",Vector2(-38,-32),0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		animation.tween_property(button,"scale",Vector2.ONE*0.15,0.16)
		animation.tween_property(button,"modulate:a",0.0,0.13)
	animation.chain().tween_callback(func():
		if token == generation:
			root.hide();closing = false;dismissed.emit())

func is_open() -> bool: return active or closing

## 把整簇气泡（含标题与胶囊文字）收进视口。
##
## 旧实现只夹锚点，且假设气泡都在锚点上方偏左一点点。二级菜单沿整条上弧排开、
## 还要多一行标题，锚点靠边时最外那颗会被切掉半截。现在按「气泡相对锚点的
## 包围盒」反推锚点下限，标题也跟着包围盒走。
const MARGIN := 26.0
const CAPTION_ROOM := 40.0

func _place() -> void:
	if not anchor_query.is_valid(): close(true);return
	var anchor: Variant = anchor_query.call()
	if not anchor is Vector2 or not anchor.is_finite(): close(true);return
	var vp := get_viewport().get_visible_rect().size
	const HINT_GAP := 14.0
	var box := _content_box()
	if hint_box != null:
		# 标题贴在整簇最上沿之上，留 `HINT_GAP` 的呼吸位；不是固定 -38，
		# 否则弧顶那颗气泡会压住字（二级菜单三颗时中间那颗正好顶到）。
		var extent := hint_box.get_combined_minimum_size()
		hint_box.size = extent
		hint_box.position = Vector2(-extent.x*0.5, box.position.y-HINT_GAP-extent.y)
		box.position.y -= HINT_GAP + extent.y
	var low := vp - Vector2(MARGIN,MARGIN)
	# 先夹上下限，再套「气泡在锚点左/上所以要往里推」的一维收缩。
	var pos := Vector2(anchor.x,anchor.y)
	pos.x = clampf(pos.x,MARGIN-box.position.x,low.x-box.end.x)
	pos.y = clampf(pos.y,MARGIN-box.position.y,low.y-box.end.y)
	cluster.position = pos

## 所有气泡（含圆下方的胶囊）相对 cluster 原点的包围盒。
func _content_box() -> Rect2:
	var box := Rect2()
	var first := true
	for button in buttons:
		var r := Rect2(button.position,button.size)
		r.size.y += CAPTION_ROOM
		box = r if first else box.merge(r)
		first = false
	return box if not first else Rect2()

func _process(_delta: float) -> void:
	if is_open(): _place()
