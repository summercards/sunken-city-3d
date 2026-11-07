extends SceneTree
## 仅由 run_verification 的 flower-crops 入口运行，不加载 Main，不读写玩家档。
const Catalog = preload("res://src/crops/crop_catalog.gd")
const Stage = preload("res://src/crops/crop_stage.gd")
const View = preload("res://src/crops/crop_view.gd")
const Farm = preload("res://src/farming/farm.gd")
const FarmPorts = preload("res://src/farming/farming_ports.gd")
const InventoryLib = preload("res://src/inventory/inventory.gd")
const Items = preload("res://src/inventory/item_db.gd")
const NpcService = preload("res://src/npc/npc_service.gd")
const HarvestVisual = preload("res://src/crops/harvest_visual.gd")
const CharacterLib = preload("res://src/player/character.gd")
const FLOWERS := ["flower_blue", "flower_sun", "flower_coral"]
const SEEDS := ["flower_seed_blue", "flower_seed_sun", "flower_seed_coral"]
const DAYS := [2, 3, 4]
const PRICES := [8, 10, 12]
const PLOT := "flower_test"

var checks := 0
var failures := 0


class Host extends RefCounted:
	var inventory = InventoryLib.new()
	var day := 1
	var greenhouse := false
	var gifts: Array = []
	func pay(costs: Dictionary) -> bool: return inventory.pay(costs)
	func give(gains: Dictionary) -> bool: return inventory.add_all(gains)
	func has_greenhouse() -> bool: return greenhouse
	func access_reason(_row: Dictionary) -> String: return ""
	func clock() -> Dictionary: return {"day": day, "hour": 12.0, "weather": "clear"}
	func exchange(costs: Dictionary, gains: Dictionary) -> Dictionary: return inventory.exchange(costs, gains)
	func count(id: String) -> int: return inventory.count(id)
	func result(value: Dictionary) -> void: gifts.append(value.duplicate(true))


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _farm(host: Host):
	var ports = FarmPorts.new()
	ports.inventory = host.inventory
	ports.pay = host.pay
	ports.give = host.give
	ports.has_greenhouse = host.has_greenhouse
	ports.access_reason = host.access_reason
	var farm = Farm.new()
	farm.configure(ports)
	farm.catalog = Catalog.new()
	check(farm.catalog.reload(), "隔离 Farm 加载正式目录")
	farm.crops = farm.catalog.definitions()
	farm.register_plot({"id": PLOT, "name": "花卉测试格"})
	return farm


func _catalog() -> void:
	var catalog := Catalog.new()
	check(catalog.reload(), "正式作物目录加载")
	check(catalog.validate().is_empty(), "正式目录与物品、模型引用一致")
	check(catalog.ids().slice(0, 3) == ["lettuce", "tomato", "pumpkin"], "旧三品种顺序保留")
	var original_yields := {"lettuce": {"vegetable": 2}, "tomato": {"tomato": 2}, "pumpkin": {"pumpkin": 3}}
	var host := Host.new()
	var farm = _farm(host)
	for id in original_yields:
		check(catalog.get_crop(id).get("yield") == original_yields[id], id + " 旧品种整数产量不变")
		check(farm.yield_of(id) == original_yields[id], id + " 原 Farm 产量不变")
		host.greenhouse = true
		var boosted: Dictionary = original_yields[id].duplicate()
		boosted[boosted.keys()[0]] += 1
		check(farm.yield_of(id) == boosted, id + " 旧温室加成不变")
		host.greenhouse = false
	farm.free()
	for index in FLOWERS.size():
		var id: String = FLOWERS[index]
		var row := catalog.get_crop(id)
		check(not row.is_empty(), id + " 正式登记")
		check(catalog.seed_of(id) == SEEDS[index], id + " 使用现有花种")
		check(catalog.produce_of(id) == id and row.get("yield") == {id: 2}, id + " 独立产物且产量为二")
		check(int(row.get("grow_days", -1)) == DAYS[index], id + " 成熟日数")
		check(int(row.get("seed_price", -1)) == PRICES[index], id + " 种价由 CropCatalog 提供")
		check(int(row.get("regrow_days", -1)) == 0 and int(row.get("harvests", -1)) == 1, id + " 不再生")
		check(catalog.model_scene(id) == "res://scenes/crops/" + id + ".tscn", id + " 独立模型入口")
		check(Items.get_item(SEEDS[index]).get("category") == "seed", id + " 种子类别保留")
		check(Items.get_item(id).get("category") == "gift" and Items.stack_limit(id) > 1, id + " 是可堆叠鲜花礼物")
		var keys: Array = []
		for stage in row.get("stages", []): keys.append(stage.get("key"))
		check(keys == Stage.KEYS and catalog.stage_labels(id).size() == 4, id + " 四阶段登记")
		row["seed_price"] = 999
		check(int(catalog.get_crop(id).seed_price) == PRICES[index], id + " 查询副本不可污染种价")


func _cycle(index: int) -> void:
	var id: String = FLOWERS[index]
	var seed: String = SEEDS[index]
	var host := Host.new()
	var farm = _farm(host)
	var empty_bag: Dictionary = host.inventory.to_dict()
	check(farm.buy_seed(id).has("blocked") and host.inventory.to_dict() == empty_bag, id + " 瓶盖不足不扣款不发种")
	check(host.inventory.add("coins", 100).ok, id + " 测试初始瓶盖")
	check(farm.select_crop(id) and farm.selected_crop == id, id + " 复用原品种选择")
	check(farm.plant(PLOT, id).has("blocked") and farm.is_empty(PLOT), id + " 无种子拒绝播种")
	check(not farm.buy_seed(id).has("blocked"), id + " 正式 Farm 购种")
	check(host.count("coins") == 100 - PRICES[index] and host.count(seed) == 1, id + " 按目录价格购得原花种")
	check(farm.plant(PLOT, id).get("event") == "planted", id + " 真播种")
	check(host.count(seed) == 0 and farm.crop_of(PLOT) == id, id + " 一次扣种并写原 Farm 状态")
	var planted: Dictionary = farm.state(PLOT)
	check(farm.plant(PLOT, id).has("blocked") and farm.state(PLOT) == planted, id + " 重复播种不覆盖")
	check(farm.harvest(PLOT).has("blocked"), id + " 未成熟不收获")
	farm.tick(100000.0)
	check(farm.state(PLOT) == planted, id + " 帧时间不生长")
	farm.advance_to_day(farm.grow_day + 1)
	check(farm.state(PLOT) == planted and farm.is_dry(PLOT), id + " 缺水日只停长")
	for watered_day in DAYS[index]:
		var before: Dictionary = farm.state(PLOT)
		var water_before: int = farm.watering_can
		check(farm.water(PLOT).get("event") == "watered", id + " 真浇水 " + str(watered_day))
		check(farm.watering_can == water_before - 1, id + " 单次耗水")
		check(farm.water(PLOT).has("blocked") and farm.watering_can == water_before - 1, id + " 重复浇水不多扣")
		check(float(farm.state(PLOT).remaining) == float(before.remaining), id + " 浇水不提前扣天")
		# 使用 JSON 往返，防止仅内存副本掩盖真实存档类型转换。
		if watered_day == 0:
			var saved: Dictionary = JSON.parse_string(JSON.stringify({"farm": farm.to_dict(), "inventory": host.inventory.to_dict()}))
			var restored_host := Host.new()
			restored_host.inventory.from_dict(saved.inventory)
			var restored = _farm(restored_host)
			restored.from_dict(saved.farm)
			check(restored.to_dict() == farm.to_dict(), id + " 生长中存档保留品种、水、剩余日、选种与水位线")
			check(restored_host.inventory.to_dict() == host.inventory.to_dict(), id + " 背包存档保留扣种与余额")
			var same_day: Dictionary = restored.state(PLOT)
			check(restored.advance_to_day(restored.grow_day).get("skipped", false) and restored.state(PLOT) == same_day, id + " 读档同日不重长")
			farm.free()
			farm = restored
			host = restored_host
		var result: Dictionary = farm.advance_to_day(farm.grow_day + 1)
		check(result.get("grew") == 1 and float(farm.state(PLOT).remaining) == DAYS[index] - watered_day - 1, id + " 换天只长一天")
		check(float(farm.state(PLOT).water) == 0.0, id + " 换天清水")
		var after: Dictionary = farm.state(PLOT)
		check(farm.advance_to_day(farm.grow_day).get("skipped", false) and farm.state(PLOT) == after, id + " 同日重复结算不重长")
		check((farm.phase(PLOT) == "ready") == (watered_day == DAYS[index] - 1), id + " 正好目标天数成熟")
	check(host.count(id) == 0, id + " 成熟不自动发奖")
	# 仅剩一朵堆叠空间时也必须整笔拒绝，不能先塞一朵再丢一朵。
	host.inventory = _full_inventory(id)
	farm.ports.inventory = host.inventory
	var full_before: Dictionary = host.inventory.to_dict()
	var mature_before: Dictionary = farm.to_dict()
	check(farm.harvest(PLOT).has("blocked"), id + " 满包拒绝整笔收获")
	check(host.inventory.to_dict() == full_before and farm.to_dict() == mature_before, id + " 满包不丢花不清地")
	check(farm.buy_seed(id).has("blocked") and host.inventory.to_dict() == full_before, id + " 满包购种不扣钱")
	var mature_save: Dictionary = JSON.parse_string(JSON.stringify(farm.to_dict()))
	farm.from_dict(mature_save)
	check(farm.phase(PLOT) == "ready" and farm.crop_of(PLOT) == id, id + " 满包成熟档可恢复")
	check(host.inventory.remove("wood", 40), id + " 腾出一格")
	var produce_before := host.count(id)
	var harvested: Dictionary = farm.harvest(PLOT)
	check(harvested.get("event") == "harvested" and harvested.get("reward") == {id: 2}, id + " 真收获独立鲜花二朵")
	check(not harvested.get("regrow", true) and farm.is_empty(PLOT), id + " 收后空地不续茬")
	check(host.count(id) == produce_before + 2, id + " 奖励真实写入 Inventory")
	check(host.count("flower_bundle") == 0, id + " 不冒充商店小束鲜花")
	for other in FLOWERS:
		if other != id: check(host.count(other) == 0, id + " 不串入其他花产物")
	check(farm.harvest(PLOT).has("blocked") and host.count(id) == produce_before + 2, id + " 重复收获不重发")
	var bag = InventoryLib.new()
	bag.from_dict(JSON.parse_string(JSON.stringify(host.inventory.to_dict())))
	check(bag.count(id) == host.count(id), id + " 收成背包存档保留")
	_gift(host, id)
	check(host.inventory.remove("wood", 40), id + " 再播前腾出种子空间")
	check(not farm.buy_seed(id).has("blocked") and farm.plant(PLOT, id).get("event") == "planted", id + " 收后可重新播种")
	farm.free()


func _full_inventory(id: String):
	var bag = InventoryLib.new()
	check(bag.add("coins", 100).ok, id + " 满包夹具货币")
	check(bag.add("wood", Items.stack_limit("wood") * (bag.capacity() - 1)).ok, id + " 满包夹具材料")
	check(bag.add(id, Items.stack_limit(id) - 1).ok and bag.room_for(id) == 1, id + " 仅剩一朵堆叠空间")
	return bag


func _gift(host: Host, id: String) -> void:
	var service := NpcService.new()
	check(service.configure(host.clock, host.exchange, Callable(), host.count, host.result).get("ok", false), id + " 注入现有送礼服务")
	var options: Dictionary = service.gift_options("npc_hua_yi")
	var available := false
	for item in options.get("items", []):
		if item.get("item_id") == id:
			available = bool(item.get("available", false))
	check(available, id + " 收获产物进入真实礼物列表")
	var before := host.count(id)
	check(service.give_gift("npc_hua_yi", id).get("ok", false), id + " 可经原 NPC 服务送礼")
	check(host.count(id) == before - 1, id + " 送礼准确扣除一朵收成")
	service.dispose()


func _meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D: out.append(node)
	for child in node.get_children(): _meshes(child, out)


func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform_to_stage := node.transform
	var parent := node.get_parent()
	while parent != ancestor:
		if parent is Node3D: transform_to_stage = parent.transform * transform_to_stage
		parent = parent.get_parent()
	return transform_to_stage


func _bounds(stage: Node3D) -> AABB:
	var meshes: Array = []
	_meshes(stage, meshes)
	var box := AABB()
	var first := true
	for mesh in meshes:
		var local: AABB = _relative(mesh, stage) * mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		var count: int = indices.size() if indices != null and not indices.is_empty() else vertices.size()
		total += int(count / 3)
	return total


func _grid() -> void:
	var grid := Node3D.new()
	grid.name = "FlowerFourStageGrid"
	root.add_child(grid)
	var leaf_heights: Array = []
	for row in FLOWERS.size():
		var id: String = FLOWERS[row]
		var heights: Array = []
		var shapes: Array = []
		for index in Stage.count():
			var view := View.new()
			view.position = Vector3(index * 1.6, 0, row * 1.3)
			grid.add_child(view)
			view.show_crop(id)
			view.set_stage(index)
			check(view.current_crop() == id and view.current_stage() == index, id + " 网格单元接口")
			var model: Node3D = view.get_child(0) if view.get_child_count() > 0 else null
			check(model != null, id + " 网格单元模型实例")
			if model == null: continue
			var visible: Array = []
			var nodes: Array = []
			for candidate in Stage.count():
				var stage := model.get_node_or_null(Stage.node_name(candidate)) as Node3D
				check(stage != null, id + " 四个独立阶段节点齐全")
				if stage != null:
					nodes.append(stage.get_instance_id())
					if stage.is_visible_in_tree(): visible.append(candidate)
			check(visible == [index], "%s 阶段 %d 唯一可见" % [id, index])
			var current := model.get_node(Stage.node_name(index)) as Node3D
			var meshes: Array = []
			_meshes(current, meshes)
			check(not meshes.is_empty(), id + " 每个阶段均有实际网格")
			var triangles := 0
			var originals: Array = []
			var transforms: Array = []
			for mesh in meshes:
				triangles += _triangles(mesh.mesh)
				originals.append(mesh.get_active_material(0))
				transforms.append(mesh.transform)
				check(mesh.get_active_material(0) is StandardMaterial3D, id + " 真实表面材质")
			var box := _bounds(current)
			heights.append(box.end.y)
			shapes.append([meshes.size(), box.size])
			check(triangles > 0 and triangles <= 900, id + " 单阶段整格三角面预算")
			check(box.position.x >= -0.65 and box.end.x <= 0.65 and box.position.z >= -0.45 and box.end.z <= 0.45, id + " 花冠叶片不越木框")
			view.set_dry(true)
			for mesh in meshes: check(mesh.material_override != null, id + " 缺水压黄覆盖网格")
			check(view.current_stage() == index and current.is_visible_in_tree(), id + " 缺水不改阶段可见性")
			view.set_dry(false)
			for mesh_index in meshes.size():
				check(meshes[mesh_index].material_override == null and meshes[mesh_index].get_active_material(0) == originals[mesh_index], id + " 解除缺水还原原材质")
				check(meshes[mesh_index].transform == transforms[mesh_index], id + " 着色不缩放网格")
			for candidate in Stage.count(): view.set_stage(candidate)
			for candidate in Stage.count():
				check(model.get_node(Stage.node_name(candidate)).get_instance_id() == nodes[candidate], id + " 阶段切换不销毁节点")
			view.set_stage(index)
		if heights.size() == 4:
			check(heights[1] >= heights[0] * 3.0 and heights[2] >= heights[1] and heights[3] >= heights[2] * 0.9, id + " 四阶段高度可分且成熟不缩水")
			check(shapes[0] != shapes[1] and shapes[1] != shapes[2] and shapes[2] != shapes[3], id + " 相邻阶段不同几何")
			leaf_heights.append(heights[2])
	if leaf_heights.size() == 3:
		check(leaf_heights[1] > leaf_heights[2] and leaf_heights[2] > leaf_heights[0], "叶阶段高直晨光、三叉珊瑚、低矮蓝星轮廓独立")
	check(grid.get_child_count() == FLOWERS.size() * Stage.count(), "三花乘四阶段网格共十二单元")
	grid.free()


func _harvest_visuals() -> void:
	var catalog := Catalog.new()
	check(catalog.reload(), "手持花使用正式模型目录")
	for id in ["lettuce", "tomato", "pumpkin"]:
		check(HarvestVisual.supports(id), id + " 原手持支持保留")
		var original := HarvestVisual.create(id)
		check(original != null, id + " 原手持实物仍可创建")
		if original != null: original.free()
	check(not HarvestVisual.supports("flower_unknown") and HarvestVisual.create("flower_unknown") == null, "未知花不伪造手持物")
	for id in FLOWERS:
		check(HarvestVisual.supports(id), id + " 纳入 Character 原收获动作支持")
		var packed: PackedScene = load(catalog.model_scene(id))
		var source: Node3D = packed.instantiate()
		check(not source.is_inside_tree(), id + " 成熟花实例离树构建")
		var stage := source.get_node(Stage.node_name(Stage.HARVEST)) as Node3D
		var source_meshes: Array = []
		_meshes(stage, source_meshes)
		check(not source_meshes.is_empty(), id + " 离树实例通知已生成真实花")
		var source_count := source_meshes.size()
		source.ensure_built()
		var after_build: Array = []
		_meshes(stage, after_build)
		check(after_build.size() == source_count, id + " 显式 ensure 构建幂等不叠花")
		var snapshot: Array = []
		var source_nodes: Array = []
		for mesh in source_meshes:
			source_nodes.append(mesh.get_instance_id())
			snapshot.append([mesh.transform, mesh.visible, mesh.mesh, mesh.get_active_material(0)])
		var prop := HarvestVisual.create(id)
		check(prop != null, id + " 离树创建真实手持花")
		if prop == null:
			source.free()
			continue
		check(prop.get_meta("crop_id", "") == id and prop.get_parent() == null, id + " 手持花身份正确且脱离地格")
		check(prop.find_children("*", "CollisionObject3D", true, false).is_empty(), id + " 手持花无碰撞")
		var copies: Array = []
		_meshes(prop, copies)
		check(copies.size() == source_meshes.size(), id + " 仅复制成熟切花的真实网格")
		var petals := 0
		var hearts := 0
		for mesh in copies:
			check(not source_nodes.has(mesh.get_instance_id()), id + " 手持节点不是地格原节点")
			check(not str(mesh.name).begins_with("Soil") and not str(mesh.name).begins_with("Seed"), id + " 切花不含土壤和种子")
			check(mesh.get_active_material(0) != null, id + " 手持花保留真实材质")
			if str(mesh.name).begins_with("Petal"): petals += 1
			if str(mesh.name).begins_with("FlowerHeart"): hearts += 1
		check(petals > 0 and hearts > 0, id + " 手持花有真花瓣和花心而非占位块")
		for index in mini(copies.size(), source_meshes.size()):
			check(copies[index].mesh.get_faces() == source_meshes[index].mesh.get_faces(), id + " 副本网格顶点与成熟花逐面一致")
			check(copies[index].get_active_material(0).albedo_color == source_meshes[index].get_active_material(0).albedo_color, id + " 副本材质颜色与成熟花一致")
		var bounds := _bounds(prop)
		check(is_equal_approx(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)), 0.40), id + " 手持实物归一为0.40米")
		check(bounds.get_center().is_equal_approx(Vector3.ZERO), id + " 手持实物居中适配原双手动作")
		prop.rotate_y(0.8)
		prop.visible = false
		prop.free()
		for index in source_meshes.size():
			var mesh: MeshInstance3D = source_meshes[index]
			check([mesh.transform, mesh.visible, mesh.mesh, mesh.get_active_material(0)] == snapshot[index], id + " 创建销毁副本不改源网格材质或姿态")
		source.free()


func _character_receive() -> void:
	var actor := CharacterLib.new()
	root.add_child(actor)
	actor.build()
	actor.set_process(false)
	var host := Host.new()
	var farm = _farm(host)
	for id in FLOWERS:
		check(host.inventory.add(farm.crop_catalog().seed_of(id), 1).ok, id + " 动作测试持有原花种")
		check(farm.plant(PLOT, id).get("event") == "planted", id + " 动作测试真实播种")
		for day in int(farm.crop_def(id).grow_days):
			farm.water(PLOT)
			farm.advance_to_day(farm.grow_day + 1)
		var result: Dictionary = farm.harvest(PLOT)
		check(result.get("event") == "harvested", id + " 动作只接成功收获结果")
		var inventory_before: Dictionary = host.inventory.to_dict()
		var farm_before: Dictionary = farm.to_dict()
		actor.play_farm_action(result.event, result)
		check(actor.action_playback().get("id") == "harvesting", id + " 沿 Character 原 harvesting 动作")
		var prop: Node3D = actor._item_receive.prop
		check(is_instance_valid(prop) and not prop.visible, id + " 原准备阶段不提前显示成功物")
		if is_instance_valid(prop):
			actor._process(1.23)
			check(prop.is_visible_in_tree() and prop.position.y > actor.head_pivot.position.y, id + " 原动作真实举花高于头顶")
			check(prop.get_meta("crop_id", "") == id, id + " 举高的是本次花产物")
			actor._process(0.73)
			check(prop.position.distance_to(actor._item_receive.bag.position) < 0.35, id + " 花沿原轨迹进入挎包口")
			actor._process(0.29)
			check(not prop.visible, id + " 花进挎包后才隐藏")
			actor._process(0.16)
			actor._process(0.0)
			check(actor._item_receive.prop == null and actor.animation_state() == "idle", id + " 原动作结束清理临时花")
		check(host.inventory.to_dict() == inventory_before and farm.to_dict() == farm_before, id + " 举花动作不重发收成或改变 Farm")
		check(actor.play_receive_item(id) > 0, id + " 再次创建用于取消验证")
		actor.cancel_action("flower_test")
		check(actor._item_receive.prop == null, id + " 取消动作清理临时花")
	farm.free()
	actor.free()


func run() -> void:
	_catalog()
	for index in FLOWERS.size(): _cycle(index)
	_grid()
	_harvest_visuals()
	_character_receive()
	print("[flower-crops] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
