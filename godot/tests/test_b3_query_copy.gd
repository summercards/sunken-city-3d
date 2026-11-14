extends SceneTree

const ZonesScript = preload("res://src/world/zones.gd")
const Items = preload("res://src/inventory/item_db.gd")
var checks := 0
var failures := 0

class LandingFixture extends RefCounted:
	var x := 12.0
	func data() -> Dictionary:
		return {"id": "main", "stand": [x, 1.5, 23.0], "boat": [x, 1.12, 25.0]}

class AreaFixture extends Node3D:
	var area_id := "deck"
	var rects: Array[Rect2] = [Rect2(0, 0, 4, 6)]
	var surface_y := 1.5
	var span_min := 1.0
	var span_max := 2.0

class ZoneFixture extends Node3D:
	signal support_moved
	var zone_id := "fixture"
	var walk_areas: Array = []
	var point := LandingFixture.new()
	func landing_points() -> Array:
		return [point]

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func run() -> void:
	_test_zones()
	_test_items()
	print("[b3-query-copy] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_zones() -> void:
	var zones = ZonesScript.new()
	zones._ready()
	var original: Array = zones.list.duplicate(true)
	var actual: Dictionary = zones.get_zone(str(original[0].id))
	actual.clear()
	check(zones.list == original, "真实区块查询不能清空内部记录")
	var source := {
		"id": "fixture", "name": "区块夹具", "origin": [10.0, 20.0],
		"landings": [
			{"id": "main", "stand": [12.0, 1.5, 23.0], "meta": {"rows": [{"amounts": [2, 3]}]}},
			{"id": "side", "stand": [14.0, 1.5, 24.0]},
		],
		"walk": [{"rects": [[10.0, 14.0, 20.0, 26.0]], "span": [1.0, 2.0]}],
	}
	for query in ["get_zone", "landing", "landings_of"]:
		zones.by_id = {"fixture": source.duplicate(true)}
		zones.list = [zones.by_id.fixture]
		var result: Variant = zones.call(query, "fixture")
		var expected: Variant = result.duplicate(true)
		var point: Dictionary
		if query == "get_zone":
			result.name = "已修改"
			result.origin[0] = -100
			result.walk[0].rects[0][0] = -100
			point = result.landings[0]
		elif query == "landing":
			point = result
		else:
			point = result[0]
		point.stand[0] = -100
		point.meta.rows[0].amounts[0] = -100
		point.meta.rows.append({"amounts": []})
		point.id = "已修改"
		point.erase("meta")
		if query != "landing":
			result.clear()
		check(zones.by_id.fixture == source, query + " 不污染内部字典和嵌套容器")
		check(zones.list == [source], query + " 不污染注册列表")
		check(zones.call(query, "fixture") == expected, query + " 再次查询保持原值与顺序")
	# 旧实现的污染不应阻断后续反例和终局 marker。
	zones.by_id = {"fixture": source.duplicate(true)}
	zones.list = [zones.by_id.fixture]
	check(zones.landing("fixture", "side").id == "side", "指定泊位查询不变")
	check(zones.landing("fixture", "").id == "main", "空泊位 ID 仍取首项")
	check(zones.landing("fixture", "unknown").id == "main", "未知泊位仍回退首项")
	check(zones.footprint("fixture") == Rect2(10, 20, 4, 6), "轮廓数值不变")
	check(zones.zone_at(Vector3(12, 0, 23)) == "fixture", "区块位置查询不变")
	for query in ["get_zone", "landing", "landings_of"]:
		var missing: Variant = zones.call(query, "missing")
		if missing is Dictionary:
			missing["caller"] = true
		else:
			missing.append({"caller": true})
		check(zones.call(query, "missing").is_empty(), query + " 空结果独立")
	zones.by_id["empty"] = {"id": "empty"}
	check(zones.landing("empty").is_empty() and zones.landings_of("empty").is_empty(), "无泊位区块仍返回空结果")
	var scene := ZoneFixture.new()
	var area := AreaFixture.new()
	scene.add_child(area)
	scene.walk_areas = [area]
	root.add_child(scene)
	scene.position = Vector3(10, 0, 20)
	zones.bind_scene(scene)
	var bound: Dictionary = zones.get_zone("fixture")
	check(bound.landings == [scene.point.data()], "bind_scene 仍写入内部泊位")
	check(bound.walk == [{"id": "deck", "y": 1.5, "rects": [[10.0, 14.0, 20.0, 26.0]], "span": [1.0, 2.0]}], "bind_scene 仍写入原行走数值")
	bound.landings[0].stand[0] = -100
	bound.walk[0].span[0] = -100
	scene.point.x = 13.0
	scene.support_moved.emit()
	check(zones.landing("fixture").stand[0] == 13.0, "移动支撑事件仍刷新内部记录")
	check(scene.get_signal_connection_list("support_moved").size() == 1, "重复绑定不重复连接事件")
	check(zones.get_zone("fixture").walk[0].span == [1.0, 2.0], "场景绑定后的嵌套查询也隔离")
	scene.free()
	zones.free()

func _test_items() -> void:
	Items.ensure_loaded()
	var original: Dictionary = Items._items.duplicate(true)
	var order: Array = Items.all_ids()
	var materials: Array = Items.ids_in("material")
	var capacity: int = Items.capacity()
	var item: Dictionary = Items.get_item("wood")
	item.label = "已修改"
	item.stack = 1
	item.sell = 999
	item.erase("desc")
	check(Items.get_item("wood") == original.wood, "真实物品再次查询保持原值")
	check(Items.label("wood") == original.wood.label and Items.stack_limit("wood") == 40 and Items.sell_price("wood") == 2, "名称堆叠售价不受返回值修改影响")
	# 当前 JSON 物品只有标量，用局部夹具验证未来嵌套字段，不修改内容表。
	Items._items.wood = original.wood.duplicate(true)
	var saved: Dictionary = Items._items.wood
	Items._items.wood = original.wood.duplicate(true)
	Items._items.wood["nested"] = {"rows": [{"amounts": [2, 3]}]}
	var expected: Dictionary = Items._items.wood.duplicate(true)
	var nested: Dictionary = Items.get_item("wood")
	nested.nested.rows[0].amounts[0] = 999
	nested.nested.rows.append({"amounts": []})
	nested.nested["caller"] = true
	nested.clear()
	check(Items._items.wood == expected, "物品嵌套数组与字典不污染内部定义")
	check(Items.get_item("wood") == expected, "物品嵌套修改后再次查询不变")
	Items._items.wood = saved
	var ids: Array = Items.all_ids()
	ids.reverse()
	ids.append("caller")
	var filtered: Array = Items.ids_in("material")
	filtered.clear()
	check(Items.all_ids() == order and Items.ids_in("material") == materials, "公开 ID 数组可修改但定义顺序不变")
	var missing: Dictionary = Items.get_item("missing")
	missing["caller"] = true
	check(Items.get_item("missing").is_empty() and not Items.has("missing"), "未知物品空结果独立")
	check(Items._items == original and Items.capacity() == capacity, "查询不改变物品表与容量，ensure_loaded 不重复加载")
