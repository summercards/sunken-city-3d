@tool
extends "res://src/interaction/interactable.gd"
class_name SunroomRepairInteractable
## Repair intent for the solar cabin ladder. The service owns payment and state.

var service
var refresh: Callable

func configure(owner, on_changed: Callable) -> void:
	service = owner
	refresh = on_changed
	_on_ready()
	add_to_group("interactable")

func _on_ready() -> void:
	id = "sunroom_ladder_repair"
	label = "破损的阳光房梯子"
	verb = "修理梯子"
	priority = 12
	focus_radius = 2.1
	hold_time = 0.6  # 动作时长（SEA-INTERACT-R19）：按一次触发，不必一直按着
	accent = Color("#d99b68")
	focus_anchor = "node"
	auto_radius = false

func set_sunroom_stage(next_stage: String) -> void:
	visible = next_stage == "ruined"

func can_interact() -> bool:
	return service != null and str(service.stage) == "ruined"

func blocked_reason() -> String:
	if service == null:
		return "修缮系统未就绪"
	return str(service.repair_reason())

func focus_text() -> String:
	if service == null:
		return "修理梯子"
	return "修理梯子 · 木板×%d" % int(service.LADDER_COST.get("wood", 0))

func interact(_actor: Node3D) -> Dictionary:
	if service == null:
		return {"blocked": "修缮系统未就绪"}
	var result: Dictionary = service.repair_ladder()
	if not result.has("blocked") and refresh.is_valid():
		refresh.call()
	return result
