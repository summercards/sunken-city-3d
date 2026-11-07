@tool
extends "res://src/interaction/interactable.gd"
class_name SunroomLadderInteractable
## The same physical ladder exposes two authored interaction points.
## Bottom and top are separate nodes so focus follows the player on both floors.

var service
var climb_request: Callable
@export_enum("up", "down") var direction := "up"
var bottom_point := Vector3.ZERO
var top_point := Vector3.ZERO

func configure(owner, climb: Callable, way: String, bottom: Vector3, top: Vector3) -> void:
	service = owner
	climb_request = climb
	direction = way
	bottom_point = bottom
	top_point = top
	_on_ready()

func _on_ready() -> void:
	id = "sunroom_ladder_" + direction
	label = "阳光房梯子"
	verb = "爬上二楼" if direction == "up" else "下到一楼"
	priority = 13
	focus_radius = 1.8
	hold_time = 0.25
	accent = Color("#e9c07a")
	focus_anchor = "node"
	auto_radius = false

func set_sunroom_stage(next_stage: String) -> void:
	visible = next_stage != "ruined"

func can_interact() -> bool:
	return service != null and bool(service.ladder_repaired())

func blocked_reason() -> String:
	if service == null:
		return "修缮系统未就绪"
	if not service.ladder_repaired():
		return "梯子已经断了，先用木板修好"
	return ""

func interact(actor: Node3D) -> Dictionary:
	if not can_interact():
		return {"blocked": blocked_reason()}
	if not climb_request.is_valid():
		return {"blocked": "攀爬系统未就绪"}
	var from := bottom_point if direction == "up" else top_point
	var to := top_point if direction == "up" else bottom_point
	return climb_request.call(from, to, self)
