extends SceneTree
## SEA-CROP 真实渲染证据：三品种 × 四阶段，独立舞台，不加载 main.tscn。
##
## 产出 outputs/crops_stage_grid.png（正视图）、outputs/crops_stage_ortho.png（俯视图）。
## 这是 SEA-CROP-R06 要求的真实渲染证据，不替代四视图源级验收。

const StageDef = preload("res://src/crops/crop_stage.gd")
const CatalogLib = preload("res://src/crops/crop_catalog.gd")

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[crops-render] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func settle(n := 6) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	call_deferred("run")


func _mesh_count(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _mesh_count(child)
	return total


func _stage_root(node: Node, index: int) -> Node3D:
	return node.get_node_or_null(StageDef.node_name(index)) as Node3D


func run() -> void:
	var catalog = CatalogLib.new()
	check(catalog.reload(), "crops.json 加载")

	root.size = Vector2i(1600, 900)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9fd8e8")
	# 环境光取游戏内 world_env.tres 的实测值（0.36 / 偏冷天光），
	# 给太高会把色板颜色洗白，评审看到的不是实机配色。
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.74, 0.88, 0.93)
	e.ambient_light_energy = 0.36
	# 与游戏内 world_env.tres 一致（tonemap_mode=3 / ACES，exposure 1.17），
	# 否则截图颜色比实机浅，评审会误判配色。
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.17
	env.environment = e
	root.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.4
	root.add_child(cam)

	var stage_root := Node3D.new()
	root.add_child(stage_root)

	# 底板：让作物有落影，颜色取色板里的浅木色。
	var board := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(11.0, 5.4)
	board.mesh = plane
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("#c9a677")
	bmat.roughness = 0.95
	board.material_override = bmat
	board.position = Vector3(0, -0.01, 0)
	stage_root.add_child(board)

	var ids: Array = catalog.ids()
	var col_gap := 3.0
	var row_gap := 1.55
	var origin := Vector3(-(ids.size() - 1) * col_gap * 0.5, 0.0, (StageDef.count() - 1) * row_gap * 0.5)

	for row in StageDef.count():
		for col in ids.size():
			var crop_id: String = ids[col]
			var path: String = catalog.model_scene(crop_id)
			check(path != "" and ResourceLoader.exists(path), "%s 场景可加载" % crop_id)
			var packed = load(path)
			var node = packed.instantiate()
			node.position = origin + Vector3(col * col_gap, 0.0, -row * row_gap)
			stage_root.add_child(node)
			for i in StageDef.count():
				var stage_root_node := _stage_root(node, i)
				if stage_root_node == null:
					continue
				stage_root_node.visible = (i == row)
			var visible_root := _stage_root(node, row)
			check(visible_root != null, "%s 阶段 %d 节点存在" % [crop_id, row])
			if visible_root != null:
				check(_mesh_count(visible_root) > 0, "%s 阶段 %d 有实际网格" % [crop_id, row])

	# 正视
	cam.position = Vector3(0.0, 2.6, 7.4)
	cam.look_at(Vector3(0.0, 0.15, 0.0), Vector3.UP)
	await settle(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/crops_stage_grid.png")

	# 俯视：检查水平铺开是否真的填满土面，而不是叠成一条线。
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.4
	cam.position = Vector3(0.0, 6.0, 0.02)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await settle(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/crops_stage_ortho.png")

	print("[crops-render] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
