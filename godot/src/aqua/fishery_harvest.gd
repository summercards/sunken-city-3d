extends "res://src/interaction/interactable.gd"
## Independent world interaction; no fish geometry or inventory ownership.
var model: RefCounted
var command: Callable

func _on_ready() -> void:
	id = "fishery_harvest"
	label = "渔场"
	verb = "收获"
	focus_anchor = "node"
	focus_offset = Vector3(0,0.30,0)
	auto_radius = false
	hold_time = 0.35
	# A dedicated CanvasLayer owns the visible button and its pointer input.
	set_meta("screen_button_owned",true)
	hide()

func configure(service: RefCounted, harvest_command: Callable) -> void:
	model = service
	command = harvest_command
	refresh()

func refresh() -> void:
	visible = model != null and model.unlocked
	if visible and not is_in_group("interactable"): add_to_group("interactable")
	if not visible and is_in_group("interactable"): remove_from_group("interactable")

func can_interact() -> bool:
	return model != null and model.unlocked

func blocked_reason() -> String:
	return model.harvest_reason() if model != null else "渔场未开放"

func interact(_actor: Node3D) -> Dictionary:
	return command.call() if command.is_valid() else {}
