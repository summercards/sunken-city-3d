extends SceneTree
## 海上地图的两件事：你在哪、太阳房在哪。
## 地图是只读描绘，不编造路线/解锁；这里只验证投影与标记数据，不验证像素美观。
const Atlas = preload("res://src/ui/island_atlas.gd")
const GameStateScript = preload("res://src/bootstrap/game_state.gd")
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func run() -> void:
	var zones = load("res://src/world/zones.gd").new()
	root.add_child(zones)
	await process_frame
	check(zones.list.size() >= 4, "zone registry loaded")

	var atlas = Atlas.new()
	atlas.zones = zones
	atlas.size = Vector2(560,235)
	root.add_child(atlas)
	await process_frame

	var footprints: Dictionary = atlas.footprints
	check(footprints.has("zone1"), "home zone has a footprint")
	check(footprints.has("zone5"), "aqua zone has a footprint")
	check(zones.label("zone1") == "太阳房", "home zone is labelled 太阳房")

	# 世界坐标 -> 地图坐标：落在地图内，且两块区分得开。
	var home_center: Vector2 = (footprints["zone1"] as Rect2).get_center()
	var aqua_center: Vector2 = (footprints["zone5"] as Rect2).get_center()
	var p_home: Vector2 = atlas.project(home_center)
	var p_aqua: Vector2 = atlas.project(aqua_center)
	check(p_home.distance_to(p_aqua) > 24.0, "two berths stay apart on the map")
	for p in [p_home, p_aqua]:
		var point: Vector2 = p
		check(point.x >= 0 and point.x <= atlas.size.x and point.y >= 0 and point.y <= atlas.size.y,
			"berth projects inside the paper")

	# 注入真实坐标：你自己必须落在投影点，而不是区块中心。
	var spot_world := Vector3(home_center.x, 1.4, home_center.y)
	atlas.player_query = func() -> Dictionary: return {"zone":"zone1","position":spot_world}
	var spot: Dictionary = atlas._you_spot()
	check(bool(spot.get("available", false)), "player query yields a spot")
	check((spot.pos as Vector2).distance_to(p_home) < 1.0, "player spot uses real world coordinates")

	# 船开到两块之间时，标记要落在中间，不能贴回任一区块中心。
	var between := Vector3((home_center.x+aqua_center.x)*0.5, 1.2, (home_center.y+aqua_center.y)*0.5)
	atlas.player_query = func() -> Dictionary: return {"zone":"zone1","position":between}
	var mid: Dictionary = atlas._you_spot()
	var p_mid: Vector2 = mid.pos
	check(p_mid.distance_to(p_home) > 24.0 and p_mid.distance_to(p_aqua) > 24.0,
		"mid-sea position is not snapped to a berth centre")

	# 没有坐标来源时退回当前区块中心，而不是不画。
	atlas.player_query = Callable()
	var state = GameStateScript.new()
	state.current_zone = "zone5"
	atlas.game_state = state
	var fallback: Dictionary = atlas._you_spot()
	check(bool(fallback.get("available", false)), "fallback spot exists without a player query")
	check((fallback.pos as Vector2).distance_to(p_aqua) < 1.0, "fallback sits on the current zone")

	# 太阳房徽标：家园钉在 zone1，永远有名字，不随解锁状态消失。
	check(Atlas.HOME_ZONE == "zone1", "home badge is pinned to zone1")

	print("[island-atlas] %d checks, %d failures" % [checks, failures])
	state.free()
	quit(1 if failures > 0 else 0)
