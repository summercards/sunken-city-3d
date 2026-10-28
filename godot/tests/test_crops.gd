extends SceneTree
## SEA-CROP 隔离专项：不加载 main.tscn、不依赖 Economy Autoload。
## 这本身就是 SEA-CROP-R05 的证据——品种与表现可以单独跑。

const StageDef = preload("res://src/crops/crop_stage.gd")
const CatalogLib = preload("res://src/crops/crop_catalog.gd")
const ViewLib = preload("res://src/crops/crop_view.gd")

var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _init() -> void:
	call_deferred("run")


func _crop_root(view: Node) -> Node3D:
	# 容器会缓存已加载的品种，只有当前品种是可见的；必须按可见性取根，
	# 否则会一直读到第一个加载的模型（曾经因此误判阶段切换失败）。
	for child in view.get_children():
		if child.visible and child.get_node_or_null(StageDef.node_name(0)) != null:
			return child
	return null


func _visible_stages(root: Node) -> Array:
	var out: Array = []
	for i in StageDef.count():
		var node := root.get_node_or_null(StageDef.node_name(i))
		if node != null and node.visible:
			out.append(i)
	return out


func _meshes(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)
	return out


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in _meshes(node):
		var local: AABB = mesh.transform * mesh.get_aabb()
		if first:
			box = local
			first = false
		else:
			box = box.merge(local)
	return box


func run() -> void:
	var catalog = CatalogLib.new()
	check(catalog.reload(), "crops.json 加载")
	check(catalog.error() == "", "加载无错误：" + catalog.error())
	check(catalog.ids() == ["lettuce", "tomato", "pumpkin"], "三品种且顺序稳定")
	check(catalog.count() == 3, "品种数量为 3")

	var problems: Array = catalog.validate()
	check(problems.is_empty(), "品种自检通过：" + str(problems))

	for id in catalog.ids():
		var crop: Dictionary = catalog.get_crop(id)
		var stages = crop.get("stages", [])
		check(stages is Array and stages.size() == StageDef.count(), id + " 登记四阶段形态")
		check(catalog.stage_labels(id).size() == StageDef.count(), id + " 四阶段标签齐全")
		var model := catalog.model_scene(id)
		check(model != "" and FileAccess.file_exists(model), id + " 模型场景存在 " + model)
		check(catalog.produce_of(id) != "", id + " 登记产物")
		# 阶段键必须与 CropStage.KEYS 一一对应，防止 json 与代码漂移。
		var keys: Array = []
		if stages is Array:
			for row in stages:
				keys.append(str(row.get("key", "")))
		check(keys == StageDef.KEYS, id + " 阶段键与代码一致")

	# 阶段映射：grow_days=3 时 3/2/1/0 天 → seed/sprout/leaf/harvest
	check(StageDef.stage_for_progress(0.0, false) == StageDef.SEED, "剩 3 日 = 种子")
	check(StageDef.stage_for_progress(1.0 / 3.0, false) == StageDef.SPROUT, "剩 2 日 = 发芽")
	check(StageDef.stage_for_progress(2.0 / 3.0, false) == StageDef.LEAF, "剩 1 日 = 二次发芽")
	check(StageDef.stage_for_progress(1.0, true) == StageDef.HARVEST, "成熟 = 收成")
	check(StageDef.stage_for_progress(0.99, false) == StageDef.LEAF, "未成熟止于二次发芽")
	check(StageDef.stage_for_progress(0.0, true) == StageDef.HARVEST, "ready 优先于进度")
	check(StageDef.stage_for_progress(-5.0, false) == StageDef.SEED, "负进度夹到种子")
	check(not StageDef.is_valid(4) and not StageDef.is_valid(-1), "非法阶段索引被拒")

	# 未知品种：空定义、不新建、仍给合法阶段
	check(not catalog.has("nope"), "未知品种 has 为 false")
	check(catalog.get_crop("nope").is_empty(), "未知品种返回空定义")
	check(StageDef.is_valid(catalog.stage_for_progress("nope", 0.6, false)), "未知品种仍给合法阶段")

	# 表现装配：三品种 × 四阶段，每次只有目标阶段可见
	var view = ViewLib.new()
	root.add_child(view)
	for id in catalog.ids():
		view.show_crop(id)
		var crop_root := _crop_root(view)
		check(crop_root != null, id + " 场景根存在")
		if crop_root == null:
			continue
		check(_meshes(crop_root).size() > 0, id + " 含实际网格而非空壳")
		for i in StageDef.count():
			view.set_stage(i)
			var visible := _visible_stages(crop_root)
			check(visible == [i], "%s 阶段 %d 唯一可见：%s" % [id, i, str(visible)])
		check(view.current_stage() == StageDef.HARVEST, id + " 记录当前阶段")

	# 轮廓差异（R09）：番茄最高、生菜居中、南瓜贴地
	var heights := {}
	for id in catalog.ids():
		view.show_crop(id)
		view.set_stage(StageDef.LEAF)
		heights[id] = _bounds(_crop_root(view)).size.y
	check(heights["tomato"] > heights["lettuce"], "二次发芽：番茄高于生菜")
	check(heights["lettuce"] > heights["pumpkin"], "二次发芽：生菜高于南瓜藤")
	check(heights["tomato"] > 0.25, "番茄二次发芽可见直立主茎")

	# 缺水只是压黄，不跳阶段
	view.show_crop("lettuce")
	view.set_stage(StageDef.LEAF)
	view.set_dry(true)
	var tinted := 0
	var meshes := _meshes(_crop_root(view))
	for mesh in meshes:
		if mesh.material_override != null:
			tinted += 1
	check(tinted == meshes.size() and tinted > 0, "缺水压黄覆盖全部网格")
	check(view.current_stage() == StageDef.LEAF, "缺水不改变阶段")
	view.set_dry(false)
	var restored := 0
	for mesh in meshes:
		if mesh.material_override == null:
			restored += 1
	check(restored == meshes.size(), "解除缺水恢复原材质")

	# 降级：未知/缺失品种保留现有显示，不崩不留空箱
	view.show_crop("nope")
	check(view.current_crop() == "lettuce", "未知品种保留当前显示")
	check(_crop_root(view) != null, "降级后仍有可见作物")

	print("[crops] %d checks, %d failed" % [checks, failures])
	view.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
