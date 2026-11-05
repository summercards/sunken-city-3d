extends SceneTree
## 家园外围残楼围挡 · 运行期专项（SEA-ASSET-R47 / SEA-WORLD-R19）
##
## 只验这一件事：20 段围挡真的在正式主场景里、真的把 90×90 的四边挡住船、
## 且不往可活动范围里塞任何阻挡。造型与面数归 Blender 源级验收，这里不重复。

const WRAPPERS := "res://scenes/components/barrier/"
const ASSEMBLY := "res://scenes/world/sea_barrier.tscn"
const HALF := 120.0
const DEPTH := 10.0
const SAMPLE := 0.5

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


## 从圈内一点做四邻域搜索：能不能走到围挡外。
## 比「逐点是否被矩形覆盖」更贴近语义 —— 转角外侧有 10 米见方的空腔（两条腿
## 只覆盖各自的带），玩家到不了那里，但「被覆盖」检查会误报成漏。
func escapes(rects: Array, start: Vector2, limit: float, step: float) -> bool:
	var visited := {}
	var queue: Array[Vector2i] = [Vector2i(int(round(start.x / step)), int(round(start.y / step)))]
	visited[queue[0]] = true
	var reach := int(round(limit / step))
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + delta
			if absi(next.x) > reach or absi(next.y) > reach:
				return true
			if visited.has(next) or covered(rects, next.x * step, next.y * step):
				continue
			visited[next] = true
			queue.append(next)
	return false


func covered(rects: Array, x: float, z: float, tolerance := 0.02) -> bool:
	for r in rects:
		var rect: Rect2 = r
		if (x >= rect.position.x - tolerance and x <= rect.end.x + tolerance and
				z >= rect.position.y - tolerance and z <= rect.end.y + tolerance):
			return true
	return false


func check_wrappers() -> void:
	var files := Array(DirAccess.get_files_at(WRAPPERS)).filter(
		func(name): return name.ends_with(".tscn"))
	files.sort()
	check(files.size() == 46, "46 independent component wrappers, got %d" % files.size())
	for name in files:
		var packed := load(WRAPPERS + name) as PackedScene
		check(packed != null, name + " loads")
		if packed == null:
			continue
		var component := packed.instantiate() as Node3D
		check(component.get_meta("asset_version") == "v001", name + " stable wrapper version")
		check(component.get_meta("building_class") == "above_water", name + " above-water class")
		check(component.get("water_layer") == "surface" and component.get("water_layer_role") == "part",
			name + " water layer declared")
		var blocker := component.get_node_or_null("Blockers")
		check(blocker != null and blocker.get("mode") == "manual", name + " ships a manual blocker")
		if blocker != null:
			var rects: Array = blocker.get("manual_rects")
			check(not rects.is_empty(), name + " blocker has rects")
			for r in rects:
				var rect: Rect2 = r
				check(rect.size.x > 0.5 and rect.size.y > 0.5, name + " rect has real size")
		root.add_child(component)
		var meshes := component.find_children("*", "MeshInstance3D", true, false)
		check(not meshes.is_empty(), name + " independent geometry")
		# 材质必须落在真正的 MeshInstance3D 上（SEA-ASSET-R43 的教训）
		for child in meshes:
			var mesh_instance := child as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface) as StandardMaterial3D
				check(material != null and material.albedo_texture != null,
					name + " / " + mesh_instance.name + " surface has palette material")
				if material != null and material.albedo_texture != null:
					check(material.albedo_texture.resource_path.ends_with("sea_cabin_timber_8x8_512.png"),
						name + " canonical palette")
		component.queue_free()


func run() -> void:
	check_wrappers()

	var packed := load(ASSEMBLY) as PackedScene
	check(packed != null, "assembly loads independently")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 10:
		await process_frame

	var barrier := main.get_node_or_null("World/SeaStructures/sea_barrier") as Node3D
	check(barrier != null, "barrier instance lives under World/SeaStructures")
	if barrier == null:
		print("[sea-barrier] ", checks, " checks, ", failures, " failures")
		quit(1)
		return
	check(barrier.is_visible_in_tree(), "barrier visible in default scope")
	check(barrier.scale.is_equal_approx(Vector3.ONE), "barrier at real scale")
	var visual := barrier.get_node("Visual")
	check(visual.get_child_count() == 48, "48 placements instantiated, got %d" % visual.get_child_count())

	# 每段都必须在自己那一格上，不许有实例被摆到圈内或远处
	var rects: Array = []
	var water_y: float = main.get_node("World/Water").global_position.y
	for node in visual.get_children():
		var blocker := node.get_node("Blockers")
		blocker.rebuild(water_y, 1.6)
		var rects_of: Array = blocker.rects_world
		check(not rects_of.is_empty(), node.name + " derives blockers")
		rects += rects_of
	check(rects.size() >= 44, "at least 44 blocker rects, got %d" % rects.size())

	# 内侧不许有阻挡：可活动范围留 0.5 米余量后，任何矩形都不许压进来
	var intrusions := 0
	for r in rects:
		var rect: Rect2 = r
		var lo := Vector2(maxf(rect.position.x, -HALF + 0.5), maxf(rect.position.y, -HALF + 0.5))
		var hi := Vector2(minf(rect.end.x, HALF - 0.5), minf(rect.end.y, HALF - 0.5))
		if lo.x < hi.x and lo.y < hi.y:
			intrusions += 1
	check(intrusions == 0, "no blocker intrudes into the 90x90 playable area, got %d" % intrusions)

	# 四边连续：沿每条边每 0.5 米采一点，必须被至少一条矩形挡住
	var gaps := []
	var t := -HALF
	while t <= HALF:
		for side in [
			["north", Vector2(t, -HALF - 1.0)],
			["south", Vector2(t, HALF + 1.0)],
			["west", Vector2(-HALF - 1.0, t)],
			["east", Vector2(HALF + 1.0, t)],
		]:
			if not covered(rects, (side[1] as Vector2).x, (side[1] as Vector2).y):
				gaps.append("%s@%.1f" % [side[0], t])
		t += SAMPLE
	check(gaps.is_empty(), "four sides are continuous, gaps: %s" % str(gaps.slice(0, 8)))

	# 再往深里采一层：围挡进深 10 米，靠外一侧也必须实心，不能只有贴边一圈
	var shallow := []
	t = -HALF + 1.0
	while t <= HALF - 1.0:
		for side in [
			["north", Vector2(t, -HALF - 8.0)],
			["south", Vector2(t, HALF + 8.0)],
			["west", Vector2(-HALF - 8.0, t)],
			["east", Vector2(HALF + 8.0, t)],
		]:
			if not covered(rects, (side[1] as Vector2).x, (side[1] as Vector2).y):
				shallow.append("%s@%.1f" % [side[0], t])
		t += SAMPLE * 4
	check(shallow.is_empty(), "barrier is %s m deep, thin spots: %s" % [str(DEPTH), str(shallow.slice(0, 8))])

	# 真正的水面查询：圈内开阔、圈外被挡
	main._water_shapes()
	var open_inside: bool = main._is_open_water(0.0, -90.0)
	var blocked_outside: bool = not main._is_open_water(HALF + 5.0, 0.0)
	check(open_inside, "home water stays open")
	check(blocked_outside, "boat cannot pass the east wall")
	# 真正要证明的是「出不去」：从圈内开阔水面做四邻域搜索，不许有任何一条
	# 0.5 米宽的缝通到围挡外面。
	var escaped: bool = escapes(rects, Vector2(0.0, -90.0), HALF + 15.0, SAMPLE)
	check(not escaped, "no 0.5 m gap leads out of the 90x90 area")

	# 岸线：围挡跨水线，水面必须切出白波纹，否则「船知道它存在、水不知道」。
	# 这一条曾在水下裙体上出过整齐直角白框，所以直接数岸线段数。
	# 岸线：围挡跨水线，水面必须从它的几何切出白波纹，否则「船知道它存在、水不知道」。
	# 用「藏起来再数一遍」做差，而不是比较某个魔法数字 —— 基线随其他几何变化。
	var water := main.get_node_or_null("World/Water")
	# 段数由几何切片给出，围挡走的是「结构轮廓种子」那条路（与浮店同一套），
	# 所以不数段数，直接问距线图：贴着墙内侧 1 米处必须离岸很近，圈心必须很远。
	var near_wall: float = water.shoreline.distance_at(Vector2(0.0, 118.0)) if water != null else 99.0
	var center: float = water.shoreline.distance_at(Vector2(0.0, -60.0)) if water != null else 0.0
	check(near_wall < 2.5, "water knows the barrier is there (1 m inside the wall -> %.2f m)" % near_wall)
	check(center > 20.0, "open water in the middle is still far from shore (%.2f m)" % center)
	print("[sea-barrier] barrier rects ", rects.size(), " water_y ", water_y,
		" shore distance wall/center ", "%.2f" % near_wall, "/", "%.2f" % center)
	print("[sea-barrier] ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
