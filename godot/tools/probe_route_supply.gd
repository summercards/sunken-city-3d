extends SceneTree
## 只读探针：zone3 → sea_supply 的航路是否真的压到岸线。
##
## 背景：selftest 曾用 shore.json 的粗包围矩形判穿岛，而那块家园港矩形比实际甲板
## 外扩约 0.7 米，于是船开得过去的航路被判红。这里按同一套采样复算，并逐点
## 对比实时几何（`main._is_open_water`）这个真正挡船的口径：判红点若实时是开阔水面，
## 就说明是烘焙矩形粗糙，而不是航路有问题。
var main: Node
const SailNav = preload("res://src/navigation/sail_nav.gd")

func _init() -> void:
	call_deferred("run")

func hits(shapes: Array, p: Vector2) -> Array:
	var out: Array = []
	for s in shapes:
		var cx := float(s.get("x", 0.0))
		var cz := float(s.get("z", 0.0))
		var hx := float(s.get("hx", 0.0))
		if bool(s.get("round", false)):
			if (p.x - cx) * (p.x - cx) + (p.y - cz) * (p.y - cz) <= (hx + 0.15) * (hx + 0.15):
				out.append([cx, cz, hx])
		elif absf(p.x - cx) <= hx + 0.15 and absf(p.y - cz) <= float(s.get("hz", hx)) + 0.15:
			out.append([cx, cz, hx, float(s.get("hz", hx))])
	return out

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 6:
		await process_frame
	var zones: Node = root.get_node("Zones")
	var grid: Dictionary = main.nav_grid()
	var a: Dictionary = zones.landing("zone3", "main")
	var b: Dictionary = zones.landing("sea_supply", "main")
	var from := Vector2(float(a.boatPark[0]), float(a.boatPark[2]))
	var to := Vector2(float(b.boatPark[0]), float(b.boatPark[2]))
	var route: Array = SailNav.plan_route(grid, from, to)
	var shore: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/baked/shore.json"))
	var shapes: Array = shore.shapes
	var total := 0.0
	for i in range(1, route.size()):
		total += (route[i] as Vector2).distance_to(route[i - 1])
	var walked := 0.0
	var baked_hits := 0
	var real_crossings := 0
	for i in range(1, route.size()):
		var p0: Vector2 = route[i - 1]
		var p1: Vector2 = route[i]
		var seg := p0.distance_to(p1)
		var steps := maxi(2, int(ceil(seg / 0.5)))
		for k in range(steps + 1):
			var t := float(k) / float(steps)
			var run := walked + seg * t
			if run < 3.0 or run > total - 3.0:
				continue
			var p := p0.lerp(p1, t)
			var h := hits(shapes, p)
			if h.is_empty():
				continue
			baked_hits += 1
			var live: bool = main._is_open_water(p.x, p.y)
			if not live:
				real_crossings += 1
			if baked_hits <= 6:
				print("[route-probe] seg=", i, " p=", p, " shapes=", JSON.stringify(h),
					" live_open_water=", live)
		walked += seg
	print("[route-probe] total=", total, " baked_hits=", baked_hits,
		" real_crossings=", real_crossings, " shapes=", shapes.size())
	var ok: bool = route.size() > 1 and real_crossings == 0
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
