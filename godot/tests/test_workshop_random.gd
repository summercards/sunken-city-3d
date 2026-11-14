extends SceneTree
## 由runner的workshop-random入口运行；真实Generator/Session几何专项，不直接启动主工程。
const RandomRecipe = preload("res://src/workshop/random_recipe.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Session = preload("res://src/workshop/session.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Union = preload("res://src/workshop/shell_union_geometry.gd")
const Builder = preload("res://src/workshop/mesh_builder.gd")
const SEEDS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
var checks: int = 0
var failures: Array[String] = []
var cases: Array = []
var changes: int = 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		var message: String = label + " " + str(detail)
		failures.append(message)
		printerr("FAIL [workshop-random] ", message)

func run() -> void:
	check(not ProjectSettings.has_setting("autoload/GameState"), "runner隔离玩法Autoload")
	var shapes: Dictionary = {}
	var variants: Dictionary = {}
	for field: String in ["floors", "width", "depth", "door_width", "door_height", "window_width", "window_height", "roof", "pilaster", "band", "palette", "window_type"]:
		variants[field] = {}
	for seed_value: int in SEEDS:
		seed(81723)
		var expected: int = randi()
		seed(81723)
		var recipe: Dictionary = RandomRecipe.create(seed_value)
		check(randi() == expected, "配方不消耗全局随机 " + str(seed_value))
		check(Recipe.fingerprint(recipe) == Recipe.fingerprint(RandomRecipe.create(seed_value)), "相同seed配方复现 " + str(seed_value))
		check(RandomRecipe.generate_candidates(seed_value) == [recipe], "候选有界且首案不偷偷换模板 " + str(seed_value))
		check(Recipe.validate(recipe, Catalog.definitions()).is_empty(), "联动配方合法 " + str(seed_value), Recipe.validate(recipe, Catalog.definitions()))
		check(recipe.vegetation_density == 0.0 and recipe.locked_vegetation.is_empty(), "只随机房屋，不新增植物制作 " + str(seed_value))
		shapes[recipe.shape] = true
		for field: String in variants:
			var value: Variant = recipe.get(field)
			if field in ["roof", "pilaster", "band", "palette"]: value = recipe.architecture[field]
			if field == "window_type": value = recipe.architecture.window.type
			variants[field][JSON.stringify(value)] = true
		var start: int = Time.get_ticks_msec()
		seed(71839)
		expected = randi()
		seed(71839)
		var session: RefCounted = Session.new(Catalog.definitions())
		var built: Dictionary = session.preview_candidate(recipe)
		check(randi() == expected, "真实生成不消耗玩法随机 " + str(seed_value))
		check(bool(built.get("ok", false)), "actual generator成功 " + str(seed_value), built.get("reason", ""))
		var record: Dictionary = {"seed": seed_value, "shape": recipe.shape, "recipe": recipe, "ok": built.get("ok", false)}
		cases.append(record)
		if bool(built.get("ok", false)):
			audit_build(built, recipe, str(seed_value))
			var signature: Dictionary = model_signature(built.root)
			var repeated: Dictionary = session.preview_candidate(RandomRecipe.create(seed_value))
			check(bool(repeated.get("ok", false)), "相同seed再次真实生成 " + str(seed_value), repeated.get("reason", ""))
			if bool(repeated.get("ok", false)):
				check(model_signature(repeated.root) == signature, "相同seed实际Mesh/PaletteUV复现 " + str(seed_value))
				repeated.root.free()
			record["triangles"] = built.stats.triangles
			record["signature"] = signature
			built.root.free()
		record["build_and_repeat_ms"] = Time.get_ticks_msec() - start
		print("[workshop-random-case] seed=", seed_value, " shape=", recipe.shape, " ok=", record.ok, " ms=", record.build_and_repeat_ms)
		await process_frame
	check(shapes.size() == 4, "20个固定seed覆盖矩形L/T/U四形状", shapes.keys())
	for field: String in variants:
		check(variants[field].size() >= 2, "实际配方多样性 " + field, variants[field].size())
	test_transaction()
	test_old_vegetation()
	var report: Dictionary = {"suite": "workshop-random", "checks": checks, "failures": failures, "passed": failures.is_empty(), "seeds": SEEDS, "cases": cases, "shape_coverage": shapes.keys(), "visual": "本专项headless；紧凑布局与随机按钮交互另由editor-workshop-upgrade真实渲染验证", "engine": Engine.get_version_info()}
	var file := FileAccess.open("res://outputs/workshop_random_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-random] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func audit_build(built: Dictionary, recipe: Dictionary, label: String) -> void:
	var root: Node3D = built.root
	check(root.get_parent() == null and root.transform == Transform3D.IDENTITY, label + "不主动插入世界")
	var structure: MeshInstance3D = root.get_node_or_null("GeneratedVisual/structure_union")
	check(structure != null and structure.mesh != null, label + "实际最终union存在")
	if structure == null: return
	var faces: PackedVector3Array = structure.mesh.get_faces()
	var topology: Dictionary = Union.audit_faces(faces)
	check(bool(topology.valid), label + "实际union单连通闭合定向正体积", topology)
	var sources: Dictionary = built.get("semantic_sources", {})
	check(not sources.is_empty(), label + "有真实结构操作数而非固定模板")
	var pilasters: int = 0
	var bands: int = 0
	for id: String in sources:
		if id.begins_with("pilaster_"): pilasters += 1
		if id.begins_with("band_"): bands += 1
		var source: Node = root.get_node_or_null("GeneratedVisual/" + id)
		check(source != null and not source is MeshInstance3D, label + "源不重复可见 " + id)
	check((pilasters > 0) == bool(recipe.architecture.pilaster.enabled), label + "真实柱开关变化")
	check((bands > 0) == bool(recipe.architecture.band.enabled), label + "真实腰线开关变化")
	var found_roof: bool = false
	var valid_uv: bool = true
	var selected_glass: bool = false
	var door_count: int = 0
	var window_count: int = 0
	var opening_sizes_match: bool = true
	for opening: Dictionary in built.get("openings", []):
		var is_door: bool = str(opening.type) == "door"
		opening_sizes_match = opening_sizes_match and is_equal_approx(float(opening.clear_width), float(recipe.door_width if is_door else recipe.window_width)) and is_equal_approx(float(opening.clear_height), float(recipe.door_height if is_door else recipe.window_height))
	check(opening_sizes_match, label + "真实洞口尺寸随配方变化且不静默缩孔")
	var shared: Dictionary = Builder.shared_materials()
	var expected_glass: Array = recipe.architecture.palette.slots.glass.color_cell
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if str(node.name).begins_with("parapet_") or str(node.name).begins_with("railing_"): found_roof = true
		if str(node.name).begins_with("door_"): door_count += 1
		if str(node.name).begins_with("glass_"): window_count += 1
		for surface: int in node.mesh.get_surface_count():
			valid_uv = valid_uv and node.mesh.surface_get_material(surface) in shared.values()
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			valid_uv = valid_uv and uvs == arrays[Mesh.ARRAY_TEX_UV2] and not uvs.is_empty()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for index: int in range(0, indices.size() if not indices.is_empty() else uvs.size(), 3):
				var triangle: Array[Vector2] = []
				for corner: int in 3: triangle.append(uvs[indices[index + corner] if not indices.is_empty() else index + corner])
				valid_uv = valid_uv and absf((triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])) > 1.0e-10
				var cell := Vector2i(floori(triangle[0].x * 8.0), floori(triangle[0].y * 8.0))
				for uv: Vector2 in triangle:
					var inset: Vector2 = uv * 8.0 - Vector2(cell)
					valid_uv = valid_uv and uv.is_finite() and inset.x >= 0.125 - 0.0001 and inset.x <= 0.875 + 0.0001 and inset.y >= 0.125 - 0.0001 and inset.y <= 0.875 + 0.0001
				if str(node.name).begins_with("glass_") and cell == Vector2i(int(expected_glass[1]), int(expected_glass[0])): selected_glass = true
	check(valid_uv and selected_glass, label + "真实非退化PaletteUV安全区与所选色格/共享材质")
	check(found_roof == (str(recipe.architecture.roof.mode) != "none"), label + "真实屋顶构造变化")
	check(door_count > 0 and window_count > 0, label + "真实门扇窗网格")
	var collision_matches: bool = false
	for shape: Node in root.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is ConcavePolygonShape3D and (shape.shape as ConcavePolygonShape3D).get_faces() == faces: collision_matches = true
	check(collision_matches, label + "真实union与凹碰撞逐点一致")

func model_signature(root: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var surfaces: Array = []
		for surface: int in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			surfaces.append(var_to_bytes([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_TEX_UV]]).hex_encode().sha256_text())
		result[str(node.name)] = surfaces
	return result

func test_transaction() -> void:
	var session: RefCounted = Session.new()
	var original: Dictionary = session.snapshot()
	var built: Dictionary = session.preview_candidate(RandomRecipe.create(7))
	check(bool(built.get("ok", false)), "事务基线实际生成", built.get("reason", ""))
	if not bool(built.get("ok", false)): return
	var original_model: Node = built.root
	var before: Dictionary = session.snapshot()
	var before_hash: Dictionary = model_signature(original_model)
	var cat: String = Catalog.fingerprint(session.catalog)
	session.mark_saved()
	session.changed.connect(func() -> void: changes += 1)
	var bad: Dictionary = RandomRecipe.create(8)
	bad.architecture.window.recess = -0.5
	check(Recipe.validate(bad, session.catalog).is_empty(), "几何失败用例通过静态配方门禁")
	var failed: Dictionary = session.preview_candidate(bad)
	check(not bool(failed.get("ok", false)), "实际模型失败被拒绝", failed.get("reason", ""))
	check(changes == 0 and not session.is_dirty() and before == session.snapshot() and Catalog.fingerprint(session.catalog) == cat and model_signature(original_model) == before_hash, "失败不改配方模型目录保存态历史信号")
	var next: Dictionary = RandomRecipe.create(9)
	var success: Dictionary = session.preview_candidate(next)
	check(bool(success.get("ok", false)) and changes == 1 and session.is_dirty(), "成功一次原子提交及changed")
	if bool(success.get("ok", false)):
		check(session.undo() and Recipe.fingerprint(session.snapshot()) == Recipe.fingerprint(before) and not session.is_dirty(), "一次撤销回原房且保存态恢复")
		check(session.redo() and Recipe.fingerprint(session.snapshot()) == Recipe.fingerprint(next), "重做复现随机房")
		check(session.undo() and session.undo() and session.snapshot() == original and not session.undo(), "成功仅占一条历史，失败不占历史")
		success.root.free()
	original_model.free()

func test_old_vegetation() -> void:
	var recipe: Dictionary = RandomRecipe.create(3)
	recipe.vegetation_density = 0.1
	recipe.vegetation_variation = 0.5
	recipe.component_bindings.plant = "plant_shrub"
	var session: RefCounted = Session.new()
	var built: Dictionary = session.preview_candidate(recipe)
	check(bool(built.get("ok", false)), "房屋兼容原vegetation装饰，不扩展植物制作", built.get("reason", ""))
	if bool(built.get("ok", false)):
		check(int(built.stats.plant_meshes) > 0, "旧植物装饰仍真实存在")
		built.root.free()
