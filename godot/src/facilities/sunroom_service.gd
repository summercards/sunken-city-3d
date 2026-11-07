extends RefCounted
class_name SunroomService
## SEA-SUNROOM: the repair state owner for the solar cabin.
##
## The scene owns visuals and interaction intent. This service owns the only
## writable progression state and consumes materials through injected ports.
## It deliberately does not own Farm plots, room state, or the building layout.

signal changed

const VERSION := 1
const STAGE_RUINED := "ruined"
const STAGE_LADDER_FIXED := "ladder_fixed"
const STAGE_RESTORED := "restored"
const LADDER_COST := {"wood": 5}
const UPPER_COST := {"wood": 8, "soil": 2, "glass": 1}
const VALID_STAGES := [STAGE_RUINED, STAGE_LADDER_FIXED, STAGE_RESTORED]

var stage := STAGE_RUINED
var seasonal_care := 0
var calendar_day := 1
var ports: Dictionary = {}

func configure(boundary: Dictionary) -> void:
	assert(boundary.has("construction_pay") and boundary["construction_pay"].is_valid(), "Missing port: sunroom construction_pay")
	assert(boundary.has("construction_has") and boundary["construction_has"].is_valid(), "Missing port: sunroom construction_has")
	assert(boundary.has("construction_missing_text") and boundary["construction_missing_text"].is_valid(), "Missing port: sunroom construction_missing_text")
	ports = boundary.duplicate()

func ladder_repaired() -> bool:
	return stage in [STAGE_LADDER_FIXED, STAGE_RESTORED]

func upper_restored() -> bool:
	return stage == STAGE_RESTORED

func season() -> String:
	var month := _month_for_day(calendar_day)
	if month in [3, 4, 5]: return "spring"
	if month in [6, 7, 8]: return "summer"
	if month in [9, 10, 11]: return "autumn"
	return "winter"

func query() -> Dictionary:
	return {
		"version": VERSION,
		"stage": stage,
		"ladder_repaired": ladder_repaired(),
		"upper_restored": upper_restored(),
		"seasonal_care": seasonal_care,
		"season": season(),
		"calendar_day": calendar_day,
	}

func can_repair_ladder() -> bool:
	return stage == STAGE_RUINED and construction_has(LADDER_COST)

func can_restore_upper() -> bool:
	return stage == STAGE_LADDER_FIXED and construction_has(UPPER_COST)

func repair_reason() -> String:
	if stage != STAGE_RUINED:
		return "这架梯子已经修好了"
	return construction_missing_text(LADDER_COST)

func restore_reason() -> String:
	if stage == STAGE_RUINED:
		return "先修好通往二楼的梯子"
	if stage == STAGE_RESTORED:
		return "二楼已经休整好了"
	return construction_missing_text(UPPER_COST)

func repair_ladder() -> Dictionary:
	if stage != STAGE_RUINED:
		return {"blocked": repair_reason()}
	if not construction_pay(LADDER_COST):
		return {"blocked": construction_missing_text(LADDER_COST)}
	stage = STAGE_LADDER_FIXED
	seasonal_care = maxi(seasonal_care, 1)
	changed.emit()
	return {"event": "sunroom_ladder_repaired", "stage": stage, "cost": LADDER_COST.duplicate()}

func restore_upper() -> Dictionary:
	if stage == STAGE_RUINED:
		return {"blocked": "先修好通往二楼的梯子"}
	if stage == STAGE_RESTORED:
		return {"blocked": "二楼已经休整好了"}
	if not construction_pay(UPPER_COST):
		return {"blocked": construction_missing_text(UPPER_COST)}
	stage = STAGE_RESTORED
	seasonal_care = maxi(seasonal_care, 2)
	changed.emit()
	return {"event": "sunroom_upper_restored", "stage": stage, "cost": UPPER_COST.duplicate()}

func set_calendar_day(day: int) -> void:
	var next := maxi(1, day)
	if next == calendar_day:
		return
	calendar_day = next
	# Season is a read-only presentation input. It never advances repair by itself.
	changed.emit()

func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"stage": stage,
		"ladder_repaired": ladder_repaired(),
		"upper_restored": upper_restored(),
		"seasonal_care": seasonal_care,
	}

func from_dict(data: Dictionary) -> void:
	var next_stage := str(data.get("stage", STAGE_RUINED))
	if not VALID_STAGES.has(next_stage):
		next_stage = STAGE_RUINED
	stage = next_stage
	# Accept old/hand-authored snapshots that only contain the compatibility booleans.
	if bool(data.get("upper_restored", false)):
		stage = STAGE_RESTORED
	elif bool(data.get("ladder_repaired", false)) and stage == STAGE_RUINED:
		stage = STAGE_LADDER_FIXED
	seasonal_care = clampi(int(data.get("seasonal_care", 0)), 0, 100)
	changed.emit()

static func validate_snapshot(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	if int(data.get("version", -1)) != VERSION:
		return "Invalid sunroom snapshot version"
	var stage_value := str(data.get("stage", ""))
	if not VALID_STAGES.has(stage_value):
		return "Invalid sunroom stage"
	var ladder := bool(data.get("ladder_repaired", false))
	var upper := bool(data.get("upper_restored", false))
	if upper and not ladder:
		return "Sunroom upper restored without ladder repair"
	if stage_value == STAGE_RUINED and (ladder or upper):
		return "Sunroom stage and repair flags disagree"
	if stage_value == STAGE_LADDER_FIXED and (not ladder or upper):
		return "Sunroom ladder stage flags disagree"
	if stage_value == STAGE_RESTORED and (not ladder or not upper):
		return "Sunroom restored stage flags disagree"
	var care := int(data.get("seasonal_care", -1))
	if care < 0 or care > 100:
		return "Invalid sunroom care count"
	return ""

func construction_has(cost: Dictionary) -> bool:
	return bool(ports["construction_has"].call(cost))

func construction_pay(cost: Dictionary) -> bool:
	return bool(ports["construction_pay"].call(cost))

func construction_missing_text(cost: Dictionary) -> String:
	return str(ports["construction_missing_text"].call(cost))

static func _month_for_day(day: int) -> int:
	var lengths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var remaining := (maxi(1, day) - 1) % 365
	for i in lengths.size():
		if remaining < lengths[i]:
			return i + 1
		remaining -= lengths[i]
	return 1
