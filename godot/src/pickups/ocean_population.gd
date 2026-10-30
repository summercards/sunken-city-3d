extends RefCounted
## Coordinate-seeded resource slots cover every explored part of the open sea.
## Only the nine nearby cells have scene nodes. Depletion survives unloading.
const CELL_SIZE := 64.0
const RADIUS := 1
const HOME_WATER := preload("res://src/core/play_scope.gd").HOME_WATER
const HOME_CELL := Vector2i.ZERO
const OUTSIDE_WOOD_PERCENT := 30
const MORNING := preload("res://src/time/day_schedule.gd").MORNING_SECONDS / 3600.0
var cycle := -1
var now := 0.0
var missing: Dictionary = {}
var _cells: Dictionary = {}
var _center := Vector2i(2147483647, 2147483647)
var _desired: Dictionary = {}
var _dirty := true

static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))

func observe(clock: Dictionary) -> bool:
	now = (int(clock.day) - 1) * 24.0 + float(clock.hour)
	var next_cycle := int(clock.day) if float(clock.hour) >= MORNING else int(clock.day) - 1
	if next_cycle != cycle:
		cycle = next_cycle
		missing.clear()
		_cells.clear()
		_dirty = true
	for slot in missing.keys():
		if float(missing[slot]) <= now:
			missing.erase(slot)
			_dirty = true
	return _dirty

func collect(slot: String, fish: bool, rng: RandomNumberGenerator) -> void:
	# Morning renews the whole population. Within a day wood gets a separate,
	# independently drawn delay; fish has no same-day replacement.
	missing[slot] = cycle * 24.0 + MORNING if fish else now + rng.randf_range(6.0, 10.0)
	_dirty = true

func invalidate() -> void:
	_cells.clear()
	_dirty = true

func desired(focus: Vector2, wood_count: int, fish_count: int, clear: Callable) -> Dictionary:
	var center := cell_at(focus)
	if center == _center and not _dirty: return _desired
	_center = center
	_desired = {}
	var retained := {}
	for y in range(center.y - RADIUS, center.y + RADIUS + 1):
		for x in range(center.x - RADIUS, center.x + RADIUS + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell): _cells[cell] = _make_cell(cell, wood_count, fish_count, clear)
			retained[cell] = _cells[cell]
			for slot in _cells[cell]:
				if not missing.has(slot): _desired[slot] = _cells[cell][slot]
	_cells = retained
	_dirty = false
	return _desired

func _make_cell(cell: Vector2i, wood_count: int, fish_count: int, clear: Callable) -> Dictionary:
	# Generate the previous layout first: thinning wood must not reroll fish.
	var result := _make_base_cell(cell, wood_count, fish_count, clear)
	var outside: Array[String] = []
	for slot in result.keys():
		if result[slot].fish: continue
		if cell == HOME_CELL or HOME_WATER.has_point(result[slot].point):
			result.erase(slot)
		else: outside.append(slot)
	# Six used to fill every cell. At 30%, integer cells alternate 1/2 bundles;
	# ten open cells keep exactly 18 of the previous 60, rather than rounding
	# every cell up to two (33%) or rerolling whenever the boat comes back.
	var scaled := outside.size() * OUTSIDE_WOOD_PERCENT
	var quota := floori(scaled / 100.0)
	if posmod(cell.x + 3*cell.y + cycle, 10) < (scaled % 100) / 10.0: quota += 1
	for i in range(quota, outside.size()): result.erase(outside[i])
	if cell == HOME_CELL:
		_add_home_wood(result, wood_count, fish_count, clear)
	return result

func _add_home_wood(result: Dictionary, count: int, fish_count: int, clear: Callable) -> void:
	var points: Array[Vector2] = []
	# The original home rectangle straddles four grid cells. Include their fish
	# when placing the six home bundles, and retain the existing slot identities.
	for y in [-1,0]:
		for x in [-1,0]:
			for item in _make_base_cell(Vector2i(x,y), count, fish_count, clear).values():
				if item.fish: points.append(item.point)
	var area := HOME_WATER.grow(-3.0)
	for index in count:
		var slot := "0:0:wood:%d" % index
		var rng := RandomNumberGenerator.new()
		rng.seed = (slot + ":home:" + str(cycle)).hash()
		for attempt in 260:
			var point := Vector2(rng.randf_range(area.position.x,area.end.x),rng.randf_range(area.position.y,area.end.y))
			if clear.is_valid() and not clear.call(point,false): continue
			var separated := true
			for other in points:
				if point.distance_to(other)<7.0: separated=false; break
			if not separated: continue
			points.append(point)
			result[slot] = {"point":point,"fish":false}
			break

func _make_base_cell(cell: Vector2i, wood_count: int, fish_count: int, clear: Callable) -> Dictionary:
	var result := {}
	var points: Array[Vector2] = []
	for kind in ["wood", "fish"]:
		for index in (wood_count if kind == "wood" else fish_count):
			var slot := "%d:%d:%s:%d" % [cell.x, cell.y, kind, index]
			var rng := RandomNumberGenerator.new()
			rng.seed = (slot + ":" + str(cycle)).hash()
			for attempt in 100:
				# A 5m border also separates populations across adjacent cells.
				var point := Vector2(cell) * CELL_SIZE + Vector2(rng.randf_range(5, CELL_SIZE-5), rng.randf_range(5, CELL_SIZE-5))
				if clear.is_valid() and not clear.call(point, kind == "fish"): continue
				var separated := true
				for other in points:
					if point.distance_to(other) < 9.0: separated = false; break
				if not separated: continue
				points.append(point)
				result[slot] = {"point":point, "fish":kind == "fish"}
				break
	return result

func to_dict() -> Dictionary:
	return {"version":1, "cycle":cycle, "now":now, "missing":missing.duplicate(true)}

func from_dict(data: Dictionary) -> void:
	cycle = int(data.cycle)
	now = float(data.now)
	missing = data.missing.duplicate(true)
	invalidate()

static func validate_snapshot(data: Dictionary) -> String:
	for slot in data.missing:
		var parts := str(slot).split(":")
		if parts.size() != 4: return "Invalid ocean resource slot"
		if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[3].is_valid_int(): return "Invalid ocean resource coordinates"
		if parts[2] not in ["wood", "fish"] or int(parts[3]) < 0 or int(parts[3]) >= 9: return "Invalid ocean resource kind"
		var due := float(data.missing[slot])
		if due < float(data.now) or due > float(data.now) + 24.0: return "Invalid ocean resource cooldown"
	return ""
