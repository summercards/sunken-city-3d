extends RefCounted

func to_dict() -> Dictionary:
	return {"left":salvage_cooldown_left(Time.get_ticks_msec()/1000.0)}

func from_dict(data: Dictionary) -> void:
	salvage_ready_at = Time.get_ticks_msec()/1000.0 + float(data.get("left",0.0))
## Feature-owned rules. External state is accessed only through configured ports.
signal salvage_ready
const SALVAGE_COOLDOWN := 16.0
var salvage_ready_at := 0.0
var ports: Dictionary = {}
func configure(boundary: Dictionary) -> void:
	assert(boundary.has("give") and boundary["give"].is_valid(), "Missing port: give")
	ports = boundary.duplicate()

func give(rewards: Dictionary) -> Dictionary:
	return ports["give"].call(rewards)


func can_salvage(now: float) -> bool:
	return now >= salvage_ready_at

func salvage_cooldown_left(now: float) -> float:
	return maxf(salvage_ready_at - now, 0.0)

func commit_salvage(now: float, haul: Dictionary) -> Dictionary:
	if haul.is_empty() or not can_salvage(now):
		return {}
	salvage_ready_at = now + SALVAGE_COOLDOWN
	salvage_ready.emit()
	return give(haul)

func do_salvage(now: float) -> Dictionary:
	if not can_salvage(now):
		return {}
	salvage_ready_at = now + SALVAGE_COOLDOWN
	var gain := give({"wood": 3, "parts": 2})
	return gain
