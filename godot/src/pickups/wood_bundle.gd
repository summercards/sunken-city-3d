extends RefCounted
## One source for wood yield, silhouette and interaction footprint.
const SUNROOM_CENTER := Vector2(6.158, 1.813)
const NEAR_DISTANCE := 45.0
const OUTER_DISTANCE := 150.0
const TIERS := [
	{"label":"零散浮木", "min":2, "max":3, "copies":1, "width":0.70, "length":1.50, "ring":1.05, "reach":2.2},
	{"label":"中束浮木", "min":7, "max":9, "copies":2, "width":1.15, "length":1.85, "ring":1.25, "reach":2.45},
	{"label":"大簇浮木", "min":12, "max":16, "copies":3, "width":1.60, "length":2.10, "ring":1.50, "reach":2.7},
]

static func arrangement(amount: int) -> Array:
	match tier(amount):
		1:
			return [Vector4(-0.18,0.0,-0.10,0.0), Vector4(0.18,0.06,0.10,-0.14)]
		2:
			return [Vector4(-0.36,0.0,-0.08,-0.12), Vector4(0.36,0.04,0.06,0.11), Vector4(0.0,0.085,0.35,-0.035)]
	return [Vector4.ZERO]

static func tier(amount: int) -> int:
	for index in TIERS.size():
		if amount >= TIERS[index].min and amount <= TIERS[index].max: return index
	return -1

static func profile(amount: int) -> Dictionary:
	return TIERS[maxi(0, tier(amount))]

static func weights(point: Vector2) -> Vector3:
	var distance := point.distance_to(SUNROOM_CENTER)
	var t := clampf((distance - NEAR_DISTANCE) / (OUTER_DISTANCE - NEAR_DISTANCE), 0.0, 1.0)
	return Vector3(0.90, 0.09, 0.01).lerp(Vector3(0.40, 0.40, 0.20), t)

static func draw(point: Vector2, rng: RandomNumberGenerator) -> int:
	var odds := weights(point)
	var roll := rng.randf()
	var index := 0 if roll < odds.x else (1 if roll < odds.x + odds.y else 2)
	return rng.randi_range(TIERS[index].min, TIERS[index].max)

static func for_slot(point: Vector2, slot: String, cycle: int, generation: int) -> int:
	# A separate stream leaves the fish layout and replenishment stream intact.
	var rng := RandomNumberGenerator.new()
	rng.seed = (slot + ":wood-yield:" + str(cycle) + ":" + str(generation)).hash()
	return draw(point, rng)

static func clearance() -> float:
	# Bound all rotated silhouettes plus 0.45m drift and a little roll slack.
	return 2.6
