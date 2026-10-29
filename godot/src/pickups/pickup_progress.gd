extends CanvasLayer
## 海上拾取（漂流浮木 / 鱼群）的进度表现。
##
## 只做表现，不改玩法：进度值由调用方给（主场景按剩余航程算好），
## 这里只负责把这条细进度条放到**角色头顶**，并在没有拾取时收起来。
##
## 为什么挂在角色头上、而不是挂在目标上：
##   目标会跑出画面。拾取时船是朝着目标划过去的，镜头跟着角色走，
##   目标一偏出取景框，条就跟着一起消失 —— 玩家在最需要看进度的
##   那几秒反而什么都没有（实测截图：夜里航行，目标在画面外，
##   条完全不可见）。角色永远在镜头里，挂在它头上就永远看得见。
##
## 为什么单独一个文件：拾取是 SEA-PICKUP 的行为，它的进度条就该挂在
## godot/src/pickups 下，而不是塞进主场景；主场景只负责接线。
##
## 视觉规格与建造进度条共用 `res://src/ui/thin_progress_bar.gd`：
## 同一条轨道、同一套圆角与配色，只是拾取更细一点（6px vs 8px），
## 两者不会各画各的、慢慢长成两种粗细。
##
## 画布层号 30：与建造进度条同一层（同一族世界浮层反馈），
## 但低于 HUD（60）、订单（62）与菜单（90）。

const ThinBar = preload("res://src/ui/thin_progress_bar.gd")
## 角色头顶的世界抬升（米）。
##
## 角色 `head_pivot` 在本地 (0, 0.98)，头部半径约 0.21、发顶再高一点，
## 所以头顶约在原点上方 1.19 米。取 1.35 让条离头发留一点空隙，
## 不会贴着帽子。真正决定观感的还是下面的 SCREEN_GAP。
const ANCHOR_LIFT := 1.35
## 条与锚点投影之间的屏幕间距（px）。
##
## 为什么还要屏幕间距：项目相机是斜俯视，垂直方向在屏幕上被压缩，
## 世界抬升只能拉开一点点。屏幕偏移与相机角度、缩放都无关，
## 不论俯视多陡，条都稳稳在角色头顶上方这么多像素处。
const SCREEN_GAP := 16.0
## 收尾停留（秒）。条走到 100% 后不立刻消失，
## 留一拍让玩家看清"到了"再收；否则最后那一格永远看不见。
const HOLD_SECONDS := 0.5

## 投影用的相机。主场景注入。
var camera: Camera3D
## 挂靠的主体（角色）。主场景注入；条永远跟着它，不跟目标。
var subject: Node3D
## 细条本体。公开出来是为了让验收脚本能直接读它的实际尺寸。
var bar: ThinBar

var _hold := 0.0
var _active := false


func _ready() -> void:
	layer = 30
	name = "PickupProgress"
	bar = ThinBar.new()
	bar.name = "PickupBar"
	add_child(bar)
	bar.configure(ThinBar.PICK_WIDTH, ThinBar.PICK_HEIGHT, ThinBar.PICK_FILL)
	bar.visible = false


## 开始一次拾取：进度从 0 起。位置由 `subject` 决定，与目标无关。
func begin() -> void:
	_active = true
	_hold = 0.0
	bar.set_ratio(0.0)
	bar.visible = false


## 设置进度（0..1，超出自动夹紧）。
func set_ratio(value: float) -> void:
	bar.set_ratio(value)


## 暂时收起条（但保留本次拾取）。
##
## 航行段用它：船还在远处划过来的时候，这不是「拾取」，不该有进度条；
## 等进入开始打捞的距离再 refresh() 显示。与 clear() 的区别是
## 本次拾取还在，随时可以重新露出来。
func hide_bar() -> void:
	bar.visible = false


## 每帧把条挪到角色头顶。
##
## 角色失效（场景重载）或落到相机背后时收条：
## 那两种情况下继续画一条悬在半空的条，比不画更误导。
func refresh() -> void:
	if not _active or camera == null:
		bar.visible = false
		return
	if subject == null or not is_instance_valid(subject):
		bar.visible = false
		return
	var point: Vector3 = subject.global_position + Vector3.UP * ANCHOR_LIFT
	if camera.is_position_behind(point):
		bar.visible = false
		return
	bar.visible = true
	bar.place_at(camera.unproject_position(point), SCREEN_GAP)


## 到了：进度条走到头并停一小会儿再收。
func complete() -> void:
	_active = false
	_hold = HOLD_SECONDS
	bar.set_ratio(1.0)


## 结束（或被取消）：收条、归零。
func clear() -> void:
	_active = false
	_hold = 0.0
	bar.set_ratio(0.0)
	bar.visible = false


## 每帧推进收尾停留计时。
func tick(delta: float) -> void:
	if _hold <= 0.0:
		return
	_hold -= delta
	if _hold <= 0.0:
		clear()
