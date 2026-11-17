extends SceneTree
## 由runner的workshop-random入口运行；真实Generator/Session几何专项，不直接启动主工程。
const RandomRecipe = preload("res://src/workshop/random_recipe.gd")
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Session = preload("res://src/workshop/session.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Union = preload("res://src/workshop/shell_union_geometry.gd")
const Builder = preload("res://src/workshop/mesh_builder.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
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
	for field: String in ["floors", "width", "depth", "door_width", "door_height", "window_width", "window_height", "roof", "pilaster", "band", "window_type"]:
		variants[field] = {}
	var palette_fingerprints: Dictionary = {}
	var structure_fingerprints: Dictionary = {}
	var window_fingerprints: Dictionary = {}
	var color_baseline: Dictionary = {}
	var actual_structures: Dictionary = {}
	var actual_windows: Dictionary = {}
	for seed_value: int in SEEDS:
		seed(81723)
		var expected: int = randi()
		seed(81723)
		var recipe: Dictionary = RandomRecipe.create(seed_value)
		check(randi() == expected, "配方不消耗全局随机 " + str(seed_value))
		check(Recipe.fingerprint(recipe) == Recipe.fingerprint(RandomRecipe.create(seed_value)), "相同seed配方复现 " + str(seed_value))
		check(RandomRecipe.generate_candidates(seed_value) == [recipe], "候选有界且首案不偷偷换模板 " + str(seed_value))
		check(Recipe.validate(recipe, Catalog.definitions()).is_empty(), "联动配方合法 " + str(seed_value), Recipe.validate(recipe, Catalog.definitions()))
		palette_fingerprints[Recipe._stable_string(recipe.architecture.palette)] = true
		structure_fingerprints[Recipe._stable_string({"shape": recipe.shape, "width": recipe.width, "depth": recipe.depth, "floors": recipe.floors, "roof": recipe.architecture.roof, "pilaster": recipe.architecture.pilaster, "band": recipe.architecture.band})] = true
		window_fingerprints[Recipe._stable_string({"type": recipe.architecture.window.type, "open_angle": recipe.architecture.window.open_angle, "frame_width": recipe.architecture.window.frame_width, "frame_depth": recipe.architecture.window.frame_depth, "sill_projection": recipe.architecture.window.sill_projection, "sill_enabled": recipe.architecture.window.sill_enabled})] = true
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
			var colors: Dictionary = color_signature(built.root)
			compare_colors(color_baseline, colors, "默认跨seed " + str(seed_value))
			color_baseline.merge(colors, false)
			record["final_colors"] = colors
			var signature: Dictionary = model_signature(built.root)
			actual_structures[str(signature.get("structure_union", []))] = true
			var window_meshes: Dictionary = {}
			for id: String in signature:
				if id.begins_with("glass_") or id.begins_with("frame_") or id.begins_with("sash_"):
					window_meshes[id] = signature[id]
			actual_windows[Recipe._stable_string(window_meshes)] = true
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
	check(palette_fingerprints.size() == 1, "不同seed的空palette保持不变", palette_fingerprints.keys())
	check(structure_fingerprints.size() >= 2, "不同seed结构仍变化", structure_fingerprints.size())
	check(window_fingerprints.size() >= 2, "不同seed窗型/窗参数仍变化", window_fingerprints.size())
	check(actual_structures.size() >= 2 and actual_windows.size() >= 2, "跨seed最终结构/窗Mesh实际变化")
	check(not color_baseline.is_empty(), "20seed实际配色断言非空")
	var user_palette: Dictionary = {"color_mode": "manual", "color_cell": [6, 1], "color_seed": 73519,
		"slots": {"glass": {"color_mode": "manual", "color_cell": [7, 7]}}, "materials": {}}
	var user_palette_fingerprint: String = Recipe._stable_string(user_palette)
	var overridden_a: Dictionary = RandomRecipe.create(101, user_palette)
	var overridden_b: Dictionary = RandomRecipe.create(202, user_palette)
	check(Recipe._stable_string(overridden_a.architecture.palette) == user_palette_fingerprint and Recipe._stable_string(overridden_b.architecture.palette) == user_palette_fingerprint, "用户显式palette不被随机seed覆盖")
	check(Recipe._stable_string(user_palette) == user_palette_fingerprint, "用户当前palette输入未被修改")
	test_solar_random_colors()
	test_color_inputs()
	await test_current_colors()
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
	var glass_settings: Dictionary = Config.palette_settings(recipe, "glass", "SEA_Gloss")
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
				if str(node.name).begins_with("glass_"):
					var expected_cell: Vector2i
					if glass_settings.is_empty():
						var uv: Vector2 = Builder._encode_shell_palette_uv(PackedVector2Array([Vector2.ZERO]), "glass", float(recipe.aging))[0]
						expected_cell = Vector2i(floori(uv.x * 8.0), floori(uv.y * 8.0))
					else:
						var expected_glass: Array = Config.palette_cell(glass_settings, str(node.name), "SEA_Gloss")
						expected_cell = Vector2i(int(expected_glass[1]), int(expected_glass[0]))
					valid_uv = valid_uv and cell == expected_cell
					selected_glass = true
	check(valid_uv and selected_glass, label + "真实非退化PaletteUV安全区与所选色格/共享材质")
	check(found_roof == (str(recipe.architecture.roof.mode) != "none"), label + "真实屋顶构造变化")
	check(door_count > 0 and window_count > 0, label + "真实门扇窗网格")
	var collision_matches: bool = false
	for shape: Node in root.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is ConcavePolygonShape3D and (shape.shape as ConcavePolygonShape3D).get_faces() == faces: collision_matches = true
	check(collision_matches, label + "真实union与凹碰撞逐点一致")

func mesh_colors(mesh: Mesh) -> Dictionary:
	var result: Dictionary = {}
	var shared: Dictionary = Builder.shared_materials()
	for surface: int in mesh.get_surface_count():
		var role: String = ""
		for key: String in shared:
			if mesh.surface_get_material(surface) == shared[key]: role = key
		check(not role.is_empty(), "最终Mesh沿用共享材质角色")
		var cells: Array = result.get(role, [])
		var arrays: Array = mesh.surface_get_arrays(surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		check(not uvs.is_empty() and uvs == arrays[Mesh.ARRAY_TEX_UV2], "最终Mesh双UV非空且一致")
		for uv: Vector2 in uvs:
			var cell: int = floori(uv.y * 8.0) * 8 + floori(uv.x * 8.0)
			if not cells.has(cell): cells.append(cell)
		cells.sort()
		result[role] = cells
	return result

func color_signature(root: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		result[str(node.name)] = mesh_colors(node.mesh)
	return result

func compare_colors(before: Dictionary, after: Dictionary, label: String, compare_union: bool = true) -> void:
	if before.is_empty(): return
	var common: int = 0
	for id: String in after:
		if not before.has(id) or (id == "structure_union" and not compare_union): continue
		common += 1
		check(before[id] == after[id], label + " 最终Mesh角色/色格不变 " + id, [before[id], after[id]])
	check(common > 0, label + " 存在共同实际网格，不空过")

func test_solar_random_colors() -> void:
	var source: Dictionary = RandomRecipe.create(17)
	source.architecture.palette = {"color_mode": "auto", "color_seed": 999}
	source.architecture.window.color_mode = "manual"
	source.architecture.window.color_cell = [7, 7]
	source.architecture.facade_windows = {"front": {"color_mode": "manual", "color_cell": [7, 0], "width": source.window_width}}
	var before: Dictionary = source.duplicate(true)
	var fixed: Dictionary = RandomRecipe.solar_colors(source)
	check(source == before, "阳光房配色转换不修改当前原房")
	check(fixed.architecture.palette == Recipe.authoring_defaults().architecture.palette, "随机强制阳光房完整色板")
	check(not fixed.architecture.facade_windows.front.has("color_mode") and fixed.architecture.facade_windows.front.width == source.window_width, "清局部窗色但保留窗几何")
	var built: Dictionary = Generator.build(fixed, Catalog.definitions())
	check(bool(built.get("ok", false)), "带旧局部色的随机房真实构建", built.get("reason", ""))
	if bool(built.get("ok", false)):
		audit_build(built, fixed, "锁阳光房")
		built.root.free()

func test_color_inputs() -> void:
	for invalid: Variant in [42, "auto", [], false, {"slots": []}, {"color_cell": [8, 0]}]:
		seed(62719)
		var expected: int = randi()
		seed(62719)
		check(RandomRecipe.create(1, invalid).is_empty(), "非法palette拒绝而非cast/回退 " + str(invalid))
		check(RandomRecipe.generate_candidates(1, invalid).is_empty(), "非法palette无候选")
		check(randi() == expected, "拒绝非法palette不污染RNG")
	var source: Dictionary = RandomRecipe.create(0)
	source.architecture.palette = {"color_mode": "manual", "color_cell": [2, 4]}
	var explicit: Dictionary = {"color_mode": "manual", "color_cell": [7, 6]}
	var output: Dictionary = RandomRecipe.create(1, explicit, source)
	check(output.architecture.palette == explicit, "显式palette优先于当前配方，不被覆盖")
	output.architecture.palette.color_cell[0] = 0
	check(explicit.color_cell == [7, 6] and source.architecture.palette.color_cell == [2, 4], "输出色板深拷贝不反写输入")

func test_current_colors() -> void:
	var palettes: Array[Dictionary] = [
		{},
		{"color_mode": "manual", "color_cell": [6, 1], "color_seed": 73519,
			"materials": {"SEA_Gloss": {"color_cell": [4, 2]}},
			"slots": {"glass": {"color_cell": [7, 7]}, "frame": {"color_cell": [3, 5]}}},
		{"color_mode": "auto", "color_seed": 73519,
			"materials": {"SEA_Matte": {"color_seed": 943}, "SEA_Gloss": {"color_mode": "manual", "color_cell": [4, 2]}},
			"slots": {"glass": {"color_mode": "auto", "color_seed": 315}, "frame": {"color_mode": "manual", "color_cell": [3, 5]}}}
	]
	palettes.append(palettes[2].duplicate(true))
	for index: int in palettes.size():
		var current: Dictionary = RandomRecipe.create(0, palettes[index])
		current.aging = 0.5
		current.component_bindings.wall = "wall_warm"
		current.architecture.shading = {"materials": {
			"SEA_Matte": {"roughness": 0.76, "specular": 0.27},
			"SEA_Gloss": {"roughness": 0.14, "transparency": 0.63}}}
		if index == 3:
			current.architecture.window.color_seed = 679
			current.architecture.facade_windows["front"] = {"color_mode": "manual", "color_cell": [2, 6]}
			current.architecture.floor_windows["0"] = {"color_seed": 321}
			current.architecture.window_overrides["opening_back_0_0"] = {"color_mode": "manual", "color_cell": [5, 7]}
		var original: String = Recipe.fingerprint(current)
		var baseline: Dictionary = Session.new().preview_candidate(current)
		check(bool(baseline.get("ok", false)), "当前配色基线实际生成 " + str(index), baseline.get("reason", ""))
		if not bool(baseline.get("ok", false)): continue
		var baseline_colors: Dictionary = color_signature(baseline.root)
		var seed_only: Dictionary = current.duplicate(true)
		seed_only.structure_seed = int(current.structure_seed) + 1
		var seed_build: Dictionary = Session.new().preview_candidate(seed_only)
		check(bool(seed_build.get("ok", false)), "奇偶structure_seed切换实际生成", seed_build.get("reason", ""))
		if bool(seed_build.get("ok", false)):
			check(color_signature(seed_build.root) == baseline_colors, "完整最终Mesh色格不依赖structure_seed，自动规则无需冻结")
			seed_build.root.free()
		for seed_value: int in [0, 1, 7]:
			seed(27183)
			var expected: int = randi()
			seed(27183)
			var candidate: Dictionary = RandomRecipe.create(seed_value, null, current)
			check(randi() == expected, "继承当前外观不污染RNG")
			check(candidate.architecture.palette == current.architecture.palette and candidate.architecture.shading == current.architecture.shading, "完整手动/自动palette及shading原样保留")
			check(RandomRecipe.generate_candidates(seed_value, null, current) == [candidate], "当前配方候选透传")
			check(candidate.architecture.window.color_seed == current.architecture.window.color_seed, "旧窗色种子保留")
			check(Recipe.validate(candidate, Catalog.definitions()).is_empty(), "继承配色后配方合法")
			seed(27183)
			var built: Dictionary = Session.new().preview_candidate(candidate)
			check(randi() == expected, "继承外观真实生成不污染RNG")
			check(bool(built.get("ok", false)), "继承外观实际生成", built.get("reason", ""))
			if not bool(built.get("ok", false)): continue
			# 自动按槽ID取色：新结构可增加/移除ID，不将全楼自动搭配错误压成一个色格。
			compare_colors(baseline_colors, color_signature(built.root), "当前配色%d/seed%d" % [index, seed_value], index < 2 or seed_value == 0)
			audit_union_colors(built, baseline, index >= 2)
			for node: Node in built.root.find_children("*", "MeshInstance3D", true, false):
				var old: Node = baseline.root.get_node_or_null(built.root.get_path_to(node))
				if old == null: continue
				# 随机结构可能让同一slot换成不同材质角色；只比较仍属同一角色的实例参数，
				# 不把“结构变化导致节点角色变化”误报成颜色搭配变化。
				var new_role: int = int(node.get_instance_shader_parameter("sea_material_role"))
				var old_role: int = int(old.get_instance_shader_parameter("sea_material_role"))
				check(new_role == old_role or new_role < 0 or old_role < 0, "实际实例材质角色保持 " + str(node.name))
				if new_role != old_role or new_role < 0: continue
				var role_name: String = ["matte", "metal", "gloss", "emission"][new_role]
				for parameter: String in ["sea_" + role_name + "_controls", "sea_" + role_name + "_emission_energy"]:
					check(node.get_instance_shader_parameter(parameter) == old.get_instance_shader_parameter(parameter), "实际实例shading保留 " + str(node.name) + "/" + parameter)
			built.root.free()
			await process_frame
		check(Recipe.fingerprint(current) == original, "当前配方输入未被修改")
		baseline.root.free()

func merge_color_sets(target: Dictionary, source: Dictionary) -> void:
	for role: String in source:
		if not target.has(role): target[role] = []
		for cell: int in source[role]:
			if not target[role].has(cell): target[role].append(cell)

func audit_union_colors(built: Dictionary, baseline: Dictionary, automatic: bool) -> void:
	var allowed: Dictionary = {}
	var common: int = 0
	for id: String in built.semantic_sources:
		var colors: Dictionary = {}
		for record: Dictionary in built.semantic_sources[id].mesh_records:
			merge_color_sets(colors, mesh_colors(record.mesh))
		for role: String in colors:
			if not allowed.has(role): allowed[role] = []
			for cell: int in colors[role]:
				if not allowed[role].has(cell): allowed[role].append(cell)
		if automatic and baseline.semantic_sources.has(id):
			var old: Dictionary = {}
			for record: Dictionary in baseline.semantic_sources[id].mesh_records:
				merge_color_sets(old, mesh_colors(record.mesh))
			check(old == colors, "自动配色共同结构槽角色/色格不变 " + id)
			common += 1
	var union_node: MeshInstance3D = built.root.get_node("GeneratedVisual/structure_union")
	var final_colors: Dictionary = mesh_colors(union_node.mesh)
	check(not final_colors.is_empty(), "最终union色格验证非空")
	for role: String in final_colors:
		for cell: int in final_colors[role]:
			check(allowed.has(role) and allowed[role].has(cell), "最终union真实UV未出现源规则以外颜色 " + role + "/" + str(cell))
	if automatic: check(common > 0, "自动结构保色有共同语义槽")

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
