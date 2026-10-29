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
## 锚点查不到时（目标投影已经出屏）退回到「玩家点下去的那一点」。
##
## 没有这个兜底，`_place` 会走 `close(true)`：玩家看着对面平台上有个能操作的箱子，
## 点下去菜单开了一帧就没了，读起来就是「点了没反应」。菜单必须停在手指落下的位置。
var fallback_anchor := Vector2.INF
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

func open(query: Callable, options: Array, hint := "", screen_fallback := Vector2.INF) -> void:
	generation += 1
	if animation: animation.kill()
	for node in cluster.get_children():
		cluster.remove_child(node);node.queue_free()
	hint_label = null
	hint_box = null
	buttons.clear();entries = options.duplicate(true);anchor_query = query
	fallback_anchor = screen_fallback
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
	# 标题可能是一整句（「那边在别的区域，需要先坐船靠岸」），不是两个字的层级名。
	# 世界浮层字体带 `variation_embolden = 1.0`，是给 44px 的 HUD 数字补粗细用的；
	# 落到 23px 的长句上，笔画会糊成一团、再叠 3px 投影就成了重影。
	# 这里换回不加粗的圆体，投影收到 1px：读起来是「一句提示」，不是「一团粗字」。
	hint_label.add_theme_font_override("font", Cozy.ui_font())
	hint_label.add_theme_font_size_override("font_size", 24)
	hint_label.add_theme_constant_override("shadow_offset_x",1)
	hint_label.add_theme_constant_override("shadow_offset_y",1)
	hint_label.add_theme_constant_override("shadow_outline_size",0)
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
## 右上（菜单）/ 右下（回到角色）两颗常驻圆按钮的保护区，含呼吸位。
##
## 菜单锚点常常正落在右上角：远处物体的图标被夹到边上，菜单就在它旁边展开 ——
## 标题和弧形气泡会整片压住那颗菜单按钮，玩家点不到 HUD。保护区只让位、不裁剪。
const HUD_CORNER := 118.0

func _place() -> void:
	var anchor: Variant = anchor_query.call() if anchor_query.is_valid() else null
	if not anchor is Vector2 or not (anchor as Vector2).is_finite():
		# 目标投影出屏/被销毁：先退回到点击点，让菜单停住；
		# 连点击点都没有（不是玩家点开的）才收起来。
		if not fallback_anchor.is_finite(): close(true);return
		anchor = fallback_anchor
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
	# 标题也要算进横向范围：它是以 cluster 原点居中的，锚点贴右边时
	# 「那边在别的区域，需要先坐船靠岸」这种长句会整段探出屏幕。
	var half_hint := 0.0
	if hint_box != null:
		half_hint = hint_box.size.x * 0.5
	var point: Vector2 = anchor
	var pos := point
	pos.x = clampf(pos.x,maxf(MARGIN-box.position.x,MARGIN+half_hint),
		minf(low.x-box.end.x,low.x-half_hint))
	pos.y = clampf(pos.y,MARGIN-box.position.y,low.y-box.end.y)
	# 让开右上 / 右下两颗常驻圆按钮：整簇（含标题）与保护区相交就往下 / 往上推。
	# 推不动（比如整屏都被占）就保持原样 —— 宁可压一角，也不能把菜单推出屏幕。
	var global_box := Rect2(pos + box.position, box.size)
	var top_right := Rect2(Vector2(vp.x - HUD_CORNER, 0.0), Vector2(HUD_CORNER, HUD_CORNER))
	if global_box.intersects(top_right):
		var shifted := pos.y + (top_right.end.y - global_box.position.y) + MARGIN
		if shifted + box.end.y <= low.y:
			pos.y = shifted
	elif Rect2(Vector2(vp.x - HUD_CORNER, vp.y - HUD_CORNER), Vector2(HUD_CORNER, HUD_CORNER)).intersects(global_box):
		var lifted := pos.y - (global_box.end.y - (vp.y - HUD_CORNER)) - MARGIN
		if lifted + box.position.y >= MARGIN:
			pos.y = lifted
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
