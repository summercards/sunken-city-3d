@tool
extends "res://src/interaction/interactable.gd"
class_name SiteLadderInteractable
## 既有设施上的直梯，上下各挂一个交互点。
##
## 与阳光房那架梯子的差别只有一条：那架要先修、修好才能爬（Economy.sunroom 有
## ladder_repaired 状态）；街区里的检修梯是既有设施，没有维修前置。

@export_enum("up", "down") var direction := "up"
@export var ladder_label := "检修梯"
@export var verb_up := "爬上去"
@export var verb_down := "爬下来"

var climb: Callable = Callable()
var destination: Node3D


func attach(climb_request: Callable, other_end: Node3D) -> void:
	climb = climb_request
	destination = other_end


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


func interact(_actor: Node3D) -> Dictionary:
	if not can_interact():
		return {"blocked": blocked_reason()}
	if not is_instance_valid(destination):
		return {"blocked": "梯子已经不在了"}
	return climb.call(global_position, destination.global_position, self)
