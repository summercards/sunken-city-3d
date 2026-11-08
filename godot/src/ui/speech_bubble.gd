extends Control
## 角色头顶气泡：和底部对话框同一张奶白纸面，下面一个指向头顶的小三角。
##
## 为什么不做成 Label + PanelContainer：
##   底部对话框（`character_dialogue.gd`）用的是 `Cozy.surface(#fbf6e8, 28)` 圆角纸面，
##   头顶气泡要跟它一致；而 PanelContainer 画不出那个指向角色的尾巴。
##   这里自绘同样的纸面 + 一个三角，字体取同一个 `Cozy.ui_font()`，观感是同一套。
##
## 只负责「把一句话画在某个 3D 节点头上」：不判断该不该说话、不记当天是否说过，
## 那些属于 NPC 世界层的职责（见 `main.gd` 的菜园桥招呼）。

const Cozy = preload("res://src/ui/cozy_ui.gd")
const PAPER := Color("#fbf6e8")
const PAPER_SHADOW := Color(0.03, 0.15, 0.15, 0.16)
const RADIUS := 30
## 字号/内边距按「船上抬头也读得清」定：原先 21 号、292 宽，1280×800 下
## 相当于一行小字，玩家得把船靠到楼下才看清。现在 30 号、468 宽，
## 配合 32 米的触发半径，主航道经过就能读。
const FONT_SIZE := 30
## 尾巴尺寸：宽度略窄于圆角，看起来是从气泡底边长出来的。
const TAIL_WIDTH := 34.0
const TAIL_HEIGHT := 20.0
const PAD := Vector2(28.0, 20.0)
## 文本最大宽度上限（像素）。实际取值还会按视口宽度收窄：
## 1280 宽的小窗里 468 已经占四成，再宽就顶到屏幕两边了。
const MAX_TEXT_WIDTH := 468.0
## 文本宽度最多占视口宽度的这个比例。
const MAX_VIEWPORT_SHARE := 0.42
## 头顶参考点：角色身高约 1.82 m，气泡吊在头上方一点，避免压住帽子。
const HEAD_OFFSET := 2.06

var _label: Label
var _font: Font
var _target: Node3D
var _camera: Camera3D
## 剩余显示时间；<= 0 时开始淡出。
var _hold := 0.0
var _hold_total := 4.5
var _fade_time := 0.45
var _alpha := 1.0
## 尾巴尖在气泡内的横向位置（像素）。角色偏在气泡一侧时，尾巴跟过去，
## 否则「带箭头的头顶对话框」就只是贴了个三角，指不到人。
var _tail_x := -1.0
## 角色当前是否在镜头内。不在镜头内只把气泡藏起来，不结束这次说话 ——
## 触发半径 32 米，玩家一转头就会把角色甩出画外，等他转回来还得能接着看。
var _on_screen := true


func _ready() -> void:
	set_meta("cozy_skip", true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Cozy.ui_font()
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", _font)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Cozy.INK)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	hide()


## 让气泡跟着 `target` 说话。`hold` 是完整显示的秒数，之后淡出。
func speak(text: String, target: Node3D, camera: Camera3D, hold := 4.5) -> void:
	if text.strip_edges().is_empty() or not is_instance_valid(target) or camera == null:
		return
	_target = target
	_camera = camera
	_hold = maxf(0.8, hold)
	_hold_total = _hold
	_alpha = 1.0
	modulate.a = 1.0
	_layout(text)
	_track()
	visible = _on_screen


func dismiss() -> void:
	_target = null
	_hold = 0.0
	hide()


func is_speaking() -> bool:
	return is_instance_valid(_target) and _alpha > 0.0


func text() -> String:
	return _label.text if _label != null else ""


func _layout(text: String) -> void:
	_label.text = text
	# 直接量，不靠 Label.reset_size()：未进容器时它的最小尺寸要等一帧才稳，
	# 那一帧里 size 还是 0，气泡会被夹到屏幕底边（实测尾巴落在 y=790）。
	var limit := MAX_TEXT_WIDTH
	var viewport := get_viewport_rect().size
	if viewport.x > 1.0:
		limit = minf(limit, viewport.x * MAX_VIEWPORT_SHARE)
	var single := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var width := minf(single, limit)
	var wrap := single > limit
	var measured := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, FONT_SIZE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	_label.size = Vector2(width, measured.y)
	_label.position = PAD
	size = Vector2(width, measured.y) + PAD * 2.0 + Vector2(0.0, TAIL_HEIGHT * 0.5)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		hide()
		return
	if _hold > 0.0:
		_hold -= delta
	elif _alpha > 0.0:
		_alpha = maxf(0.0, _alpha - delta / _fade_time)
	# 先算位置再决定显不显示：角色转出画外时 _on_screen=false，
	# 这一帧只是藏起来，计时继续走；他再转回来气泡就回来。
	_track()
	visible = _on_screen and _alpha > 0.0
	modulate.a = _alpha
	if _alpha <= 0.0:
		_target = null


## 把气泡底部的尾巴尖对准角色头顶上方一点。
func _track() -> void:
	if _camera == null or not is_instance_valid(_target):
		return
	var head: Vector3 = _target.global_position + Vector3.UP * HEAD_OFFSET
	# 角色在相机背后时 unproject 会给出镜像点，必须先挡掉。
	if _camera.is_position_behind(head):
		_on_screen = false
		return
	var screen: Vector2 = _camera.unproject_position(head)
	var viewport: Vector2 = get_viewport_rect().size
	# 触发半径放到 32 米后，角色经常在镜头外。这种时候不该在屏幕边缘
	# 挂一张指向画外的小纸条 —— 那会让人以为是 UI 出错。留 48 像素余量，
	# 角色刚出画就藏起来，回到画面里立刻恢复。
	_on_screen = not (screen.x < -48.0 or screen.y < -48.0
		or screen.x > viewport.x + 48.0 or screen.y > viewport.y + 48.0)
	if not _on_screen:
		return
	# 贴边时把气泡往内收，但尾巴仍指向角色（尾巴跟着气泡一起挪）。
	var top_left := screen - Vector2(size.x * 0.5, size.y + TAIL_HEIGHT)
	top_left.x = clampf(top_left.x, 8.0, maxf(8.0, viewport.x - size.x - 8.0))
	top_left.y = clampf(top_left.y, 8.0, maxf(8.0, viewport.y - size.y - TAIL_HEIGHT - 8.0))
	position = top_left
	# 尾巴尖对准角色的屏幕横坐标；气泡被夹到贴边时它自然偏向一侧。
	_tail_x = clampf(screen.x - position.x, TAIL_WIDTH * 0.75, size.x - TAIL_WIDTH * 0.75)
	queue_redraw()


func _draw() -> void:
	var body := Rect2(Vector2.ZERO, Vector2(size.x, size.y - TAIL_HEIGHT * 0.5))
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.set_corner_radius_all(RADIUS)
	paper.corner_detail = 20
	paper.anti_aliasing = true
	paper.shadow_color = PAPER_SHADOW
	paper.shadow_size = 14
	paper.shadow_offset = Vector2(0, 4)
	draw_style_box(paper, body)
	# 尾巴：一个向下的小三角，颜色与纸面一致，尖端对准头顶。
	# 先画在纸面之外再补一块纸色矩形把接缝盖住，避免抗锯齿留下细缝。
	var tail_x: float = _tail_x if _tail_x >= 0.0 else size.x * 0.5
	tail_x = clampf(tail_x, TAIL_WIDTH * 0.75, size.x - TAIL_WIDTH * 0.75)
	var tail_tip := Vector2(tail_x, size.y)
	var tail := PackedVector2Array([
		Vector2(tail_x - TAIL_WIDTH * 0.5, body.end.y - 1.0),
		Vector2(tail_x + TAIL_WIDTH * 0.5, body.end.y - 1.0),
		tail_tip,
	])
	draw_colored_polygon(tail, PAPER)
