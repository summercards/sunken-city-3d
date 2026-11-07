@tool
extends "res://src/interaction/interactable.gd"
class_name SunroomUpperInteractable
## Repair intent for the second-floor room. It is only visible after ladder repair.

var service
var refresh: Callable

func configure(owner, on_changed: Callable) -> void:
	service = owner
	refresh = on_changed
	_on_ready()
	add_to_group("interactable")

func _on_ready() -> void:
	id = "sunroom_upper_restore"
	label = "二楼破损的休憩间"
	verb = "休整二楼"
	priority = 11
	focus_radius = 2.2
	hold_time = 0.6  # 动作时长（SEA-INTERACT-R19）：按一次触发，不必一直按着
	accent = Color("#a8d9c6")
	focus_anchor = "node"
	auto_radius = false

func set_sunroom_stage(next_stage: String) -> void:
	visible = next_stage == "ladder_fixed"

func can_interact() -> bool:
	return service != null and str(service.stage) == "ladder_fixed"

func blocked_reason() -> String:
	if service == null:
		return "修缮系统未就绪"
	return str(service.restore_reason())

func focus_text() -> String:
	if service == null:
		return "休整二楼"
	return "休整二楼 · 木板×%d 土壤×%d 玻璃×%d" % [
		int(service.UPPER_COST.get("wood", 0)),
		int(service.UPPER_COST.get("soil", 0)),
		int(service.UPPER_COST.get("glass", 0))]

func interact(_actor: Node3D) -> Dictionary:
	if service == null:
		return {"blocked": "修缮系统未就绪"}
	var result: Dictionary = service.restore_upper()
	if not result.has("blocked") and refresh.is_valid():
		refresh.call()
	return result
