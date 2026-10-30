extends Button
## 动物森友会式的关闭按钮：奶白圆片、深棕描边、手绘粗叉，整体略微歪一点。
##
## 为什么单独一个控件：HUD 右下角原本挂两枚胶囊「Ⓑ 返回 Esc / Ⓐ 选择 Enter」，
## 只要开面板就一起出现。主人要的是"屏幕上只留一个关闭键"，不要键盘提示文案 ——
## Esc / Enter 的键盘路径仍归 `hud._input`，这里只负责那一枚可见按钮。
##
## 自绘而不吃主题：`CozyUI.apply()` 会按 `surface()` 改写 stylebox 与最小高度，
## 圆片尺寸和手感会被刷回去。构造期打 `cozy_skip`，整棵子树退出主题刷新。

const Cozy = preload("res://src/ui/cozy_ui.gd")
## 直径按 1600×1000 基准视口定：比原来的胶囊高（44）大一圈，仍小于右下镜头图标（72）。
const DIAMETER := 62.0
## 歪一点：整枚按钮逆时针 6°。AC 的手绘按键都带倾斜，摆正反而像系统弹窗。
const TILT := -0.105
const SHADOW := Color(0.24,0.19,0.12,0.20)
const SHADOW_OFFSET := Vector2(0,4)
const STROKE := 3.2
const CROSS_WIDTH := 5.6
## 叉的臂长占半径的比例。0.34 让叉在圆片里留出舒服的边距。
const CROSS_RATIO := 0.34
var _hover := false
var _down := false

func _init() -> void:
	# 必须在构造期打标记：`_cozy_node_added` 的延迟 apply 会抢在 _ready 之前跑。
	set_meta("cozy_skip", true)
	custom_minimum_size = Vector2(DIAMETER,DIAMETER)

func _ready() -> void:
	size = custom_minimum_size
	pivot_offset = size * 0.5
	rotation = TILT
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "关闭  Esc"
	text = ""
	# 原生按钮的背景/焦点框全部清空，圆片与叉都在 `_draw` 里画。
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(func() -> void: _hover = true;queue_redraw();_scale_to(1.06))
	mouse_exited.connect(func() -> void: _hover = false;_down = false;queue_redraw();_scale_to(1.0))
	button_down.connect(func() -> void: _down = true;queue_redraw();_scale_to(0.95))
	button_up.connect(func() -> void: _down = false;queue_redraw();_scale_to(1.06))
	focus_entered.connect(func() -> void: queue_redraw())
	focus_exited.connect(func() -> void: queue_redraw())

func _draw() -> void:
	var center := size * 0.5
	var reach := minf(size.x,size.y) * 0.5 - STROKE * 0.5
	var fill := Cozy.CREAM
	if _down: fill = Cozy.GOLD.darkened(0.08)
	elif _hover: fill = Cozy.GOLD
	# 落影画在偏移位，饼心仍对齐：偏移比描边小，圆片边缘才读得出来。
	draw_circle(center + SHADOW_OFFSET, reach, SHADOW)
	draw_circle(center, reach, fill)
	draw_arc(center, reach, 0.0, TAU, 48, Cozy.INK, STROKE, true)
	var arm := reach * CROSS_RATIO
	var width := CROSS_WIDTH * (0.92 if _down else 1.0)
	draw_line(center + Vector2(-arm,-arm), center + Vector2(arm,arm), Cozy.INK, width, true)
	draw_line(center + Vector2(arm,-arm), center + Vector2(-arm,arm), Cozy.INK, width, true)
	# 键盘焦点：外层再套一圈虚线感的青绿细环，不遮住描边。
	if has_focus():
		draw_arc(center, reach + 4.0, 0.0, TAU, 48, Color(Cozy.TEAL,0.85), 2.0, true)

func _scale_to(value: float) -> void:
	if not Cozy.motion_enabled:
		scale = Vector2.ONE
		return
	var tween := create_tween()
	tween.tween_property(self,"scale",Vector2.ONE * value,0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
