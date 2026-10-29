extends Control
## 世界浮层用的细进度条（拾取 / 建造共用同一份视觉规格）。
##
## 为什么不用 ProgressBar：
##   ProgressBar 的最小高度由样式盒的 **content margin** 决定，而
##   `cozy_ui.surface()` 固定留了 16/16/10/10 的内容边距 —— 代码里写
##   `size = Vector2(92, 12)`，实际渲染出来是 92×20 的一根粗棒。
##   再叠上 `cozy_ui.apply()` / `style_tree()` 里 ProgressBar 分支的
##   16px / 18px 最小高下限，想画细条根本画不出来。
##   所以这里改成 **自绘**：高度就是 `bar_height`，content margin 不再参与，
##   描边也不要 —— 细条上再描一圈只会显得更粗。
##
## 视觉取自休闲界面同一套色板（见 `cozy_ui.gd`）：
##   · 拾取轨道：深青半透明，世界浮层里压得住水面也不糊；
##   · 拾取填充：薄荷（采集/打捞），与按住 E 的交互提示条同一色；
##   · 建造轨道/填充：保留原来的暖棕 + 暖金，只改粗细，不改配色。
## 两种场合共用同一个控件，所以两者的粗细比例天然一致 ——
## 以后要再调，只改这一处的两个常量。

## 拾取条轨道色：奶油白半透明（cozy 的 `#fff9e8`）。
##
## 原来用深青 `(0.10,0.24,0.30,.72)`，那是抄 `interact_prompt` 的按住条 ——
## 但那条贴在建筑/船舷前，而拾取条浮在**亮蓝水面**上：深青在半透明叠加后
## 变成一条脏暗线，远看像水波纹，反而读不出"这是个进度条"。
## 奶油白底 + 青绿填充在这套色板里本来就是"可读的浅底 + 有色的量"，
## 也与 HUD 的奶油圆边同源。
const TRACK_COLOR := Color(1.0, 0.976, 0.909, 0.62)
## 建造条轨道色：沿用原来的暖棕，深色压得住木质与手绘感。
const BUILD_TRACK := Color("#584c38")
## 建造条填充色：沿用原来的暖金。
const BUILD_FILL := Color("#e9c16b")
## 拾取条填充色：青绿（cozy `TEAL #5baa96`）。
##
## 原先是薄荷 `(0.53,0.95,0.83)`，那是往深青底上用的亮色；换成奶油底之后
## 薄荷压不出对比，远看整条还是白的。青绿在奶油底上对比足够，
## 又是这套色板里"正在进行 / 有效"的那个颜色。
const PICK_FILL := Color("#5baa96")

## 建造条高度（px）。原实现实际渲染约 20px，这里压到 8px。
const BUILD_HEIGHT := 8.0
## 拾取条高度（px）。比建造条更细 —— 拾取是随手一瞥的反馈，
## 建造是盯着看的进度，两者不该一样重。
const PICK_HEIGHT := 6.0
## 建造条宽度（px）。
const BUILD_WIDTH := 92.0
## 拾取条宽度（px）。比建造条窄一圈，配合更细的高度读起来更"扁"。
const PICK_WIDTH := 76.0

## 进度比例 0..1。
var ratio := 0.0
## 条高（px）。
var bar_height := PICK_HEIGHT
## 填充色。
var fill_color := PICK_FILL
## 轨道色。
var track_color := TRACK_COLOR

var _track_box := StyleBoxFlat.new()
var _fill_box := StyleBoxFlat.new()


func _init() -> void:
	# 标记在构造期就打上：`_cozy_node_added` 对每个 Control 子节点都会调
	# `CozyUI.apply_instance`，那是延迟调用，等它跑起来时 `_ready` 已经写过标记，
	# 但只要有一帧抢在前面，`style_tree` 就可能把尺寸重新刷回去。
	set_meta("cozy_skip", true)


func _ready() -> void:
	# 不吃鼠标，也不参与布局：位置完全由调用方每帧给。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_boxes()


## 设定尺寸与填充色。宽度/高度以 px 为准，不受任何主题最小尺寸影响。
## `track` 不传就用默认的深青轨道。
func configure(width: float, height: float, fill: Color, track := TRACK_COLOR) -> void:
	custom_minimum_size = Vector2(width, height)
	size = Vector2(width, height)
	bar_height = height
	fill_color = fill
	track_color = track
	_apply_boxes()
	queue_redraw()


## 设置进度比例（0..1，超出范围自动夹紧）。
func set_ratio(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	if is_equal_approx(v, ratio):
		return
	ratio = v
	queue_redraw()


## 让细条水平居中贴在屏幕点上方 `gap` 像素处。
##
## 世界浮层里进度条跟着目标走：目标投影到屏幕哪，这条就出现在哪的正上方，
## 不跟着相机视差漂移。
func place_at(screen: Vector2, gap := 12.0) -> void:
	position = screen - Vector2(size.x * 0.5, gap + bar_height)


func _apply_boxes() -> void:
	var r := int(maxf(1.0, floorf(bar_height * 0.5)))
	_track_box.bg_color = track_color
	_track_box.set_corner_radius_all(r)
	_track_box.anti_aliasing = true
	_fill_box.bg_color = fill_color
	_fill_box.set_corner_radius_all(r)
	_fill_box.anti_aliasing = true


func _draw() -> void:
	var w := size.x
	var h := bar_height
	if w <= 0.0 or h <= 0.0:
		return
	draw_style_box(_track_box, Rect2(Vector2.ZERO, Vector2(w, h)))
	var filled := w * ratio
	if filled <= 0.0:
		return
	# 填充贴着左端生长；比例极低时按半高收口，避免出现一个比条还高的圆点。
	draw_style_box(_fill_box, Rect2(Vector2.ZERO, Vector2(minf(filled, w), h)))
