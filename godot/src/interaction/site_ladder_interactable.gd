@tool
extends "res://src/interaction/interactable.gd"
class_name SiteLadderInteractable
## 既有设施上的直梯，上下各挂一个交互点。
##
## 与阳光房那架梯子的差别只有一条：那架要先修、修好才能爬（Economy.sunroom 有
## ladder_repaired 状态）；街区里的检修梯是既有设施，没有维修前置。
##
## 为什么必须两个节点：
##   Interactor 会把竖直偏移超过 2.5 m 的目标整个滤掉（candidates()），
##   一根 3.7 m 的梯子只放一个点，站在下面或上面总有一头够不着。
##   两个点同 XZ、一上一下，纵向判据自己就分好工了。
##
## 为什么只吃 Y：
##   ActorController.climb_ladder() 把起终点投影到角色自己的竖线上
##   （Vector3(actor.x, start.y, actor.z)），所以这里传的 X/Z 只当注释用。
##   梯子的位置必须靠节点摆放来对，不能靠这两个数。

@export_enum("up", "down") var direction := "up"
@export var ladder_label := "检修梯"
@export var verb_up := "爬上去"
@export var verb_down := "爬下来"

var climb: Callable = Callable()
var bottom_y := 0.0
var top_y := 0.0
var subject: Node3D


## 由 Bootstrap 在 actor_controller 就绪后注入。bottom/top 是世界高度。
func attach(climb_request: Callable, way: String, bottom: float, top: float,
		subject_node: Node3D) -> void:
	climb = climb_request
	direction = way
	bottom_y = bottom
	top_y = top
	subject = subject_node
	_on_ready()


func _on_ready() -> void:
	id = "site_ladder_" + String(name).to_snake_case()
	label = ladder_label
	verb = verb_up if direction == "up" else verb_down
	priority = 13
	focus_radius = 1.6
	hold_time = 0.25
	accent = Color("#e9c07a")
	focus_anchor = "node"
	auto_radius = false


func can_interact() -> bool:
	return climb.is_valid()


func blocked_reason() -> String:
	if not climb.is_valid():
		return "攀爬系统未就绪"
	return ""


func interact(actor: Node3D) -> Dictionary:
	if not can_interact():
		return {"blocked": blocked_reason()}
	if subject == null or not is_instance_valid(subject):
		return {"blocked": "梯子已经不在了"}
	# climb_ladder 只认 Y：角色是沿「自己脚下那条竖线」升降的。
	# 不先把人挪到梯心线上，站在浮台西缘按「爬上去」，人会在 4.83 米高空
	# 出现在平台外侧，然后直接掉回水里。这个横向纠偏只做一小段（热区内），
	# 相当于「伸手抓住梯子」，不是传送。
	var body := actor.get_parent() as Node3D if actor != null else null
	if body != null and is_instance_valid(body):
		var drift := Vector2(body.global_position.x - global_position.x,
			body.global_position.z - global_position.z).length()
		if drift <= focus_radius + 0.4:
			body.global_position = Vector3(global_position.x, body.global_position.y,
				global_position.z)
	var from_y := bottom_y if direction == "up" else top_y
	var to_y := top_y if direction == "up" else bottom_y
	# X/Z 由 climb_ladder 用角色当前位置覆盖，这里传 0 只是为了参数完整。
	var here := global_position
	return climb.call(Vector3(here.x, from_y, here.z), Vector3(here.x, to_y, here.z), subject)
