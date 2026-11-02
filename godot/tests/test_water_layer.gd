extends SceneTree
## 水层义务专项：水上必须有活动区域与水面阻挡，水下必须什么都没有。
##
## 为什么不用「六栋名字列表」：那套写在 test_submerged_neighborhood.gd 里的
## const KEYS 只会守着它自己认识的资产。主场景后来长到八栋实例，名字表不会
## 跟着变 —— 新加的楼既不受管，child_count()==6 反而变红。
##
## 这里改成按节点自己声明的 water_layer 派生义务：
##   surface / amphibious  → 有人能站上去（行走面），船必须绕开（BlockerSet）
##   submerged             → 无阻挡、无碰撞、无交互、整体低于水面
##   backdrop              → 纯远景，不挡船，不参与玩法
## 规则出处：docs/standards/水层分类与空间职责.md

const BlockerSet = preload("res://src/world/blocker_set.gd")
const WalkArea = preload("res://src/navigation/walk_area.gd")
const LAYERS := ["surface", "amphibious", "submerged", "backdrop", "none"]
## 水下资产的包围盒顶面必须比水面低这么多，避免「半沉」的楼被当成水下。
const SUBMERGED_CLEARANCE := 0.25

var checks := 0
var failures := 0
var main
var water_y := 0.0
var evidence := {"entities": [], "parts": 0, "unregistered": []}


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func layer_of(node: Node) -> String:
	if node.get("water_layer") != null:
		return str(node.get("water_layer"))
	return str(node.get_meta("water_layer", ""))


func role_of(node: Node) -> String:
	if node.get("water_layer_role") != null:
		return str(node.get("water_layer_role"))
	return str(node.get_meta("water_layer_role", ""))


func blockers_of(node: Node) -> BlockerSet:
	for child in node.find_children("*", "Node3D", true, false):
		if child.get_script() == BlockerSet:
			return child
	return null


func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "VisualInstance3D", true, false):
		if not (mesh is MeshInstance3D or mesh is MultiMeshInstance3D):
			continue
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		result = part if first else result.merge(part)
		first = false
	return result


## 行走面可能由自己提供（浮店），也可能由所在区块提供（阳光房住在 zone1 里）。
func has_activity(node: Node) -> bool:
	var walk: Variant = node.get("walk_areas")
	if walk is Array and not (walk as Array).is_empty():
		return true
	if not node.find_children("*", "Node3D", true, false).filter(
			func(n): return n.get_script() == WalkArea).is_empty():
		return true
	var ancestor := node.get_parent()
	while ancestor != null:
		var areas: Variant = ancestor.get("walk_areas")
		if areas is Array and not (areas as Array).is_empty():
			return true
		ancestor = ancestor.get_parent()
	return false


func collect(node: Node, found: Array) -> void:
	var layer := layer_of(node)
	if not layer.is_empty():
		found.append(node)
	for child in node.get_children():
		collect(child, found)


func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	main.world_clock.paused = true
	main.weather_service.paused = true
	main.cam.set_process(false)
	for i in 4:
		await process_frame
	water_y = main.water_node.global_position.y

	var declared: Array = []
	collect(main, declared)
	check(not declared.is_empty(), "main scene declares at least one water layer")
	evidence.water_y = water_y

	var seen := {"surface": 0, "amphibious": 0, "submerged": 0, "backdrop": 0, "none": 0}
	for node in declared:
		var layer := layer_of(node)
		var role := role_of(node)
		var label := String(node.get_path()).replace("/root/Main/", "")
		check(layer in LAYERS, label + ": water_layer '" + layer + "' is a known value")
		if role == "part" or role == "none":
			evidence.parts += 1
			continue
		check(role == "entity", label + ": water_layer_role '" + role + "' is known")
		seen[layer] = seen.get(layer, 0) + 1
		var blocker := blockers_of(node)
		var boxes := bounds(node)
		evidence.entities.append({"path": label, "layer": layer,
			"blocker": "absent" if blocker == null else blocker.mode,
			"top": snappedf(boxes.end.y, 0.01)})

		match layer:
			"surface", "amphibious":
				# 主人的判据：水上的东西有活动区域，并且会影响航线。
				# 两条合法的占用出口：区块/结构物的 BlockerSet，或自己实现 water_shapes()
				# （渔场用后者，因为它要靠 upgraded 状态决定围网在不在）。
				var routes: Array = []
				if blocker != null and blocker.mode != "none" and blocker.blocks_water:
					routes.append("blocker")
				if node.has_method("water_shapes"):
					routes.append("water_shapes")
				check(not routes.is_empty(),
					label + " (" + layer + "): needs a boat-blocking route (BlockerSet or water_shapes)")
				check(has_activity(node), label + " (" + layer + "): needs a walkable area or landing point")
			"submerged":
				# 主人的判据：水下纯粹美化，不要阻挡、不要其它功能。
				check(blocker == null or (blocker.mode == "none" and not blocker.blocks_water),
					label + ": submerged scenery must not block boats")
				check(node.find_children("*", "CollisionObject3D", true, false).is_empty(),
					label + ": submerged scenery must not carry physics")
				check(not node.is_in_group("interactable"), label + ": submerged scenery must not be interactive")
				check(boxes.has_volume() and boxes.end.y < water_y - SUBMERGED_CLEARANCE,
					label + ": submerged scenery must sit fully below the waterline")
			"backdrop":
				check(blocker == null or blocker.mode == "none",
					label + ": backdrop must not block navigation")
				check(node.find_children("*", "CollisionObject3D", true, false).is_empty(),
					label + ": backdrop must not carry physics")
			"none":
				check(role == "none", label + ": layer none requires role none")

	# 每层至少有一个实体被真正检查过，否则「全绿」可能只是场景里没有这种东西。
	check(seen["surface"] + seen["amphibious"] > 0, "at least one above-water entity is placed in main")
	check(seen["submerged"] > 0, "at least one submerged entity is placed in main")

	var file := FileAccess.open("res://outputs/water-layer.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("[water-layer] ", checks, " checks, ", failures, " failures; ", JSON.stringify(seen))
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
