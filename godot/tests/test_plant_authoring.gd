extends SceneTree
## 仅由统一 runner 的 plant-authoring 入口运行；包含真实网格与 PackedScene 保存闭环。
const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const Species = preload("res://src/plant_authoring/species.gd")
const Session = preload("res://src/plant_authoring/session.gd")
const Store = preload("res://src/plant_authoring/store.gd")
const Library = preload("res://src/ambient/vegetation/library.gd")
var checks := 0
var failures: Array[String] = []
var signals_seen := 0
var session_roots: Array[Node] = []
var completed_sections: Array[String] = []
var artifact_paths: Array[String] = []

class ScriptedVisual extends MeshInstance3D:
	pass

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		var message := label + " " + str(detail)
		failures.append(message)
		printerr("FAIL [plant-authoring] ", message)

func run() -> void:
	check(not ProjectSettings.has_setting("autoload/GameState"), "runner 隔离玩法 Autoload")
	test_recipe()
	var protected_paths: Array[String] = [Geometry.PALETTE_PATH, Library.CATALOG]
	for key in Recipe.GRASS_ASSETS:
		protected_paths.append(Library.catalog()[key].model)
		protected_paths.append(Library.catalog()[key].material)
	var protected_before := file_hashes(protected_paths)
	var shared_before := shared_signature()
	for kind in Recipe.SPECIES:
		test_species(kind)
		await process_frame
	test_independent_streams()
	test_attachments()
	test_session()
	test_store()
	test_snapshot_regressions()
	check(file_hashes(protected_paths) == protected_before, "公共 palette/catalog/草模型与材质字节不变")
	check(shared_signature() == shared_before, "公共草几何及材质缓存不被改写")
	for path in ["res://src/plant_authoring/session.gd", "res://src/plant_authoring/store.gd", "res://src/plant_authoring/generator.gd", "res://src/plant_authoring/geometry.gd", "res://src/plant_authoring/leaf.gdshader"]:
		var source := FileAccess.get_file_as_string(path)
		check(not source.contains("global_shader_parameter_set") and not source.contains("global uniform") and not source.contains("building_workshop") and not source.contains("/workshop/"), "作者层不写 global 或依赖建筑层 " + path)
	for section in ["recipe", "camphor", "maple", "birch", "streams", "attachments", "session", "store", "snapshot"]:
		check(completed_sections.has(section), "专项完整执行而非脚本错误后跳过 " + section)
	var report := {"suite": "plant-authoring", "checks": checks, "failures": failures, "completed_sections": completed_sections,
		"artifacts": artifact_paths, "engine": Engine.get_version_info(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"screenshots": [], "scope": "真实网格/法线/UV/指纹与静态保存重载；不替代 UI 或美术目检"}
	var report_path := "res://outputs/plant_authoring_report.json"
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	check(report_file != null, "测试报告可写")
	if report_file != null:
		report.checks = checks
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
		print("[plant-authoring-report] ", ProjectSettings.globalize_path(report_path))
	print("[plant-authoring] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_recipe() -> void:
	check(Species.definitions().keys().size() == 3, "三真实树种定义")
	for kind in Recipe.SPECIES:
		var recipe := Recipe.defaults(kind)
		check(Recipe.validate(recipe).is_empty(), kind + " 默认合法", Recipe.validate(recipe))
		var reordered: Dictionary = {}
		var keys: Array = recipe.keys()
		keys.reverse()
		for key in keys: reordered[key] = recipe[key]
		check(Recipe.fingerprint(recipe) == Recipe.fingerprint(reordered), kind + " 指纹不依赖字典顺序")
		check(JSON.parse_string(Recipe.fingerprint(recipe)) is Dictionary, "fingerprint 是稳定 JSON 而非 hash")
		check(Recipe.fingerprint(JSON.parse_string(JSON.stringify(recipe))) == Recipe.fingerprint(recipe), kind + " JSON 数字往返指纹稳定")
		var old := recipe.duplicate(true)
		for key in Recipe.OPTIONAL_KEYS: old.erase(key)
		check(Recipe.validate(old).is_empty() and Recipe.normalized(old) == recipe, kind + " 旧配方补全新字段")
	var precise := Recipe.defaults()
	precise.height = 7.2 + 0.4
	check(Recipe.fingerprint(precise) == Recipe.fingerprint(JSON.parse_string(JSON.stringify(precise, "", true, true))), "算术浮点尾数JSON往返按1e-9作者精度稳定")
	var distinguish := precise.duplicate(true)
	distinguish.height += 0.001
	check(Recipe.fingerprint(precise) != Recipe.fingerprint(distinguish), "高于指纹精度的尺寸变化仍被识别")
	var bad := Recipe.defaults()
	bad.species = "tree"
	check(not Recipe.validate(bad).is_empty() and Recipe.fingerprint(bad).is_empty(), "非法 tree 不产生指纹")
	var failed := Generator.build(bad)
	check(not failed.ok and failed.root == null, "非法 tree 无生成副作用")
	for pair in [["height", NAN], ["seed", 1.5], ["seed", -1], ["wind_strength", INF], ["color_mode", "other"], ["random_enabled", 1], ["unknown", 1]]:
		bad = Recipe.defaults()
		bad[pair[0]] = pair[1]
		check(not Recipe.validate(bad).is_empty(), "非法字段拒绝 " + str(pair[0]))
	bad = Recipe.defaults()
	bad.branch_overrides = {"branch_99": {"enabled": false}}
	check(not Recipe.validate(bad).is_empty(), "越界 branch override 拒绝")
	bad.branch_overrides = {"branch_00": {"radius_scale": -1}}
	check(not Recipe.validate(bad).is_empty(), "非法 override 数值拒绝")
	bad = Recipe.defaults()
	bad.branch_count = 18
	bad.subtwig_count = 8
	bad.leaf_density = 2.0
	check(Recipe.leaf_count(bad) > Recipe.LEAF_BUDGET and not Recipe.validate(bad).is_empty(), "预算按真实叶计数拒绝")
	check(not Generator.build(bad).ok, "预算超限不分配几何")
	bad = small_recipe()
	bad.branch_count = 3
	bad.subtwig_count = 2
	bad.leaf_density = 0.25
	bad.branch_overrides = {"branch_00": {"enabled": false}}
	var built := Generator.build(bad)
	check(built.ok and built.stats.leaf_count == Recipe.leaf_count(bad) and built.stats.branch_count == 2, "预算扣除禁用枝且与实际生成计数一致")
	if built.ok: built.root.free()
	completed_sections.append("recipe")

func test_species(kind: String) -> void:
	var recipe := Recipe.defaults(kind)
	seed(72391)
	var expected := randi()
	seed(72391)
	var built := Generator.build(recipe)
	check(randi() == expected, kind + " 不消耗全局 RNG")
	check(built.ok, kind + " defaults 真实生成", built.reason)
	if not built.ok: return
	check(built.root.get_parent() == null and built.root.transform == Transform3D.IDENTITY, kind + " root 独立不插入世界")
	check(built.branches.size() == int(recipe.branch_count) and built.stats.leaf_count == Recipe.leaf_count(recipe), kind + " 枝 ID 与实际叶预算")
	for group in ["Trunk", "Leaves", "Moss", "Vines", "Grass"]:
		check(built.root.has_node(group), kind + " 分层 " + group)
	audit_meshes(built.root, kind)
	var signature := mesh_signature(built.root)
	var repeated := Generator.build(recipe)
	check(repeated.ok and mesh_signature(repeated.root) == signature, kind + " 相同 seed 逐顶点/索引/法线/UV 复现")
	if repeated.ok: repeated.root.free()
	var changed := recipe.duplicate(true)
	changed.seed += 1
	var other := Generator.build(changed)
	check(other.ok and mesh_signature(other.root) != signature, kind + " seed 改变真实几何")
	if other.ok: other.root.free()
	built.root.free()
	completed_sections.append(kind)

func audit_meshes(node: Node, label: String) -> void:
	var valid_geometry := true
	var valid_uv := true
	var valid_materials := true
	var roles: Dictionary = {}
	var triangles := 0
	for visual: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface)
			valid_materials = valid_materials and material is ShaderMaterial
			if material is ShaderMaterial:
				roles[material.resource_name] = material
				var palette: Texture2D = material.get_shader_parameter("palette_texture")
				valid_materials = valid_materials and material.resource_local_to_scene and palette != null and palette.resource_path == Geometry.PALETTE_PATH and material.shader.resource_path == "res://src/plant_authoring/leaf.gdshader"
				valid_materials = valid_materials and material.get_shader_parameter("preview_wind") == false and is_zero_approx(float(material.get_shader_parameter("local_time")))
			var arrays := visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			valid_geometry = valid_geometry and not vertices.is_empty() and normals.size() == vertices.size() and indices.size() % 3 == 0
			valid_uv = valid_uv and uvs.size() == vertices.size()
			if normals.size() != vertices.size() or uvs.size() != vertices.size(): continue
			for i in vertices.size():
				valid_geometry = valid_geometry and vertices[i].is_finite() and normals[i].is_finite() and absf(normals[i].length() - 1.0) < 0.002
			for face in range(0, indices.size(), 3):
				var a := indices[face]
				var b := indices[face + 1]
				var c := indices[face + 2]
				if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size():
					valid_geometry = false
					continue
				triangles += 1
				valid_geometry = valid_geometry and (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() > 1.0e-22
				valid_uv = valid_uv and absf((uvs[b] - uvs[a]).cross(uvs[c] - uvs[a])) > 1.0e-14
				var cell := Vector2i(floori(uvs[a].x * 8), floori(uvs[a].y * 8))
				for index in [a, b, c]:
					var pixel := uvs[index] * 512.0 - Vector2(cell) * 64.0
					valid_uv = valid_uv and uvs[index].is_finite() and cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 8 and pixel.x >= 8.0 - 0.001 and pixel.x <= 56.0 + 0.001 and pixel.y >= 8.0 - 0.001 and pixel.y <= 56.0 + 0.001
	check(valid_geometry and triangles > 0, label + " 逐面非退化/有限顶点/单位法线")
	check(valid_uv, label + " 连续 UV 岛每三角面单格且保留 8px 安全区")
	check(valid_materials and roles.size() == 4, label + " 四本地角色 ShaderMaterial，共用只读 palette 外链而非建筑四 TRES", roles.keys())

func test_independent_streams() -> void:
	var recipe := small_recipe()
	var built := Generator.build(recipe)
	if not built.ok:
		check(false, "独立随机流基线", built.reason)
		return
	var wood := mesh_signature(built.root.get_node("Trunk"))
	var next := recipe.duplicate(true)
	next.leaf_density = 1.5
	var more := Generator.build(next)
	check(more.ok and mesh_signature(more.root.get_node("Trunk")) == wood, "叶密度改变不重抽任何 wood")
	if more.ok: more.root.free()
	next = recipe.duplicate(true)
	next.branch_overrides = {"branch_00": {"enabled": false}}
	var hidden := Generator.build(next)
	check(hidden.ok, "关闭一枝生成")
	if hidden.ok:
		check(hidden.root.get_node("Trunk/branch_00").get_child_count() == 0 and hidden.root.get_node("Leaves/branch_00").get_child_count() == 0, "关闭枝同时移除所属 wood 与 leaves")
		for index in range(1, int(recipe.branch_count)):
			var path := "Trunk/branch_%02d" % index
			check(mesh_signature(hidden.root.get_node(path)) == mesh_signature(built.root.get_node(path)), "关闭枝不改其它 wood " + path)
		hidden.root.free()
	for override in [{"length_scale": 1.4}, {"radius_scale": 0.6}, {"angle_offset": 0.4}]:
		next = recipe.duplicate(true)
		next.branch_overrides = {"branch_00": override}
		var changed := Generator.build(next)
		check(changed.ok, "branch override 真实生成 " + str(override))
		if changed.ok:
			check(mesh_signature(changed.root.get_node("Trunk/branch_00")) != mesh_signature(built.root.get_node("Trunk/branch_00")), "override 改变目标木枝 " + str(override))
			check(mesh_signature(changed.root.get_node("Leaves/branch_00")) != mesh_signature(built.root.get_node("Leaves/branch_00")), "override 叶随所属枝走 " + str(override))
			check(mesh_signature(changed.root.get_node("Trunk/branch_01")) == mesh_signature(built.root.get_node("Trunk/branch_01")), "override 不影响其它 wood")
			changed.root.free()
	recipe.random_enabled = false
	var fixed := Generator.build(recipe)
	recipe.seed += 77
	var fixed_other := Generator.build(recipe)
	check(fixed.ok and fixed_other.ok and mesh_signature(fixed.root) == mesh_signature(fixed_other.root), "关闭 random 后 seed 不影响几何和颜色")
	if fixed.ok: fixed.root.free()
	if fixed_other.ok: fixed_other.root.free()
	built.root.free()
	completed_sections.append("streams")

func test_attachments() -> void:
	var recipe := small_recipe()
	recipe.moss_enabled = true
	recipe.vine_enabled = true
	recipe.grass_enabled = true
	recipe.grass_count = 2
	var built := Generator.build(recipe)
	check(built.ok, "附生真实生成", built.reason)
	if not built.ok: return
	var trunk: MeshInstance3D = built.root.get_node("Trunk/MainTrunk")
	var moss: MeshInstance3D = built.root.get_node("Moss/AttachedPatches")
	var faces := trunk.mesh.get_faces()
	var attached := true
	var vertices: PackedVector3Array = moss.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in vertices:
		var distance := INF
		for i in range(0, faces.size(), 3):
			distance = minf(distance, triangle_distance(point, faces[i], faces[i + 1], faces[i + 2]))
		attached = attached and distance >= 0.0005 and distance <= 0.0035
	check(attached and not vertices.is_empty(), "苔藓逐点贴真实树皮三角面且不嵌入")
	var points: Array[Vector3] = Generator._make_trunk_points(recipe)
	var radii: Array[float] = Generator._taper(float(recipe.trunk_radius), points.size(), 0.065)
	var vines_attached := true
	for index in int(recipe.vine_count):
		var id := "vine_%02d" % index
		var rng := Generator._rng(recipe, id + "/path")
		var t := clampf(0.36 + fposmod(index * 0.38196601125, 1.0) * 0.40 + Generator._range(recipe, rng, -0.05, 0.05), 0.30, 0.83)
		var angle := index * 2.3999632297 + Generator._range(recipe, rng, -0.35, 0.35)
		var host := Geometry.tube_surface(points, radii, t, angle)
		var visual: MeshInstance3D = built.root.get_node("Vines/" + id)
		var ps: PackedVector3Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var center := Vector3.ZERO
		for side in 5: center += ps[side * 4]
		center /= 5.0
		vines_attached = vines_attached and center.distance_to(host.position + host.normal * 0.016) < 0.0001
	check(vines_attached, "藤蔓首环中心附着真实树皮并保留外偏移")
	check(built.root.get_node("Grass").get_child_count() > 0, "组合现有草对象")
	var grass: MeshInstance3D = built.root.get_node("Grass/GroundCover")
	var grass_arrays: Array = grass.mesh.surface_get_arrays(0)
	var mask: PackedVector2Array = grass_arrays[Mesh.ARRAY_TEX_UV2]
	check(mask.size() == grass_arrays[Mesh.ARRAY_VERTEX].size() and mask[0].x >= 0 and mask[0].x <= 1 and grass.get_active_material(0).get_shader_parameter("grass_mask") != null, "草UV2保留透明轮廓遮罩且颜色仍走公共色板")
	var before := mesh_signature(built.root.get_node("Moss"))
	recipe.trunk_radius *= 1.5
	var moved := Generator.build(recipe)
	check(moved.ok and mesh_signature(moved.root.get_node("Moss")) != before, "宿主变化附生重新跟随")
	if moved.ok: moved.root.free()
	built.root.free()
	recipe.moss_enabled = false
	recipe.vine_enabled = false
	recipe.grass_enabled = false
	var off := Generator.build(recipe)
	check(off.ok and off.root.get_node("Moss").get_child_count() == 0 and off.root.get_node("Vines").get_child_count() == 0 and off.root.get_node("Grass").get_child_count() == 0, "附生与草开关独立关闭")
	if off.ok: off.root.free()
	completed_sections.append("attachments")

func test_session() -> void:
	var session := Session.new()
	var loaded := session.load_recipe(small_recipe())
	remember(loaded)
	check(loaded.ok and not session.is_dirty() and not session.can_undo(), "Session load 新文档清历史并标记保存")
	var baseline := session.snapshot()
	var detached := session.snapshot()
	detached.branch_overrides["branch_00"] = {"enabled": false}
	check(session.snapshot() == baseline, "snapshot 深副本不能写入 Session 内部")
	var basefp := session.fingerprint()
	var root_id: int = loaded.root.get_instance_id() if loaded.ok else 0
	session.changed.connect(func() -> void: signals_seen += 1)
	var bad := baseline.duplicate(true)
	bad.height = NAN
	check(not session.preview_candidate(bad).ok and not session.load_recipe(bad).ok and not session.new_document("tree").ok, "坏候选/加载/新建原子拒绝")
	check(session.snapshot() == baseline and not session.is_dirty() and not session.can_undo() and signals_seen == 0, "失败不改配方/保存态/历史/信号")
	check(session.build().root.get_instance_id() == root_id, "失败保留原预览 root，build 查询不重复生成")
	var next := baseline.duplicate(true)
	next.height += 0.5
	check(not session.preview_candidate(next, false, "stale").ok and not session.preview_candidate(next, true, basefp).ok, "拒绝陈旧候选及无前驱的历史合并")
	var built := session.preview_candidate(next, false, basefp)
	remember(built)
	check(built.ok and session.is_dirty() and session.can_undo() and signals_seen == 1, "一次生成后一次 changed 原子提交")
	if built.ok:
		check(session.build().root == built.root and session.build().branches == built.branches and session.build().stats == built.stats, "build 查询复用 root/branches/stats")
		var unchanged := session.preview_candidate(next)
		check(unchanged.ok and unchanged.root == built.root and signals_seen == 1, "相同候选复用 build，不写新历史或信号")
	var previous := session.fingerprint()
	next.height += 0.5
	var merged := session.preview_candidate(next, true, previous)
	remember(merged)
	check(merged.ok and signals_seen == 2, "指纹承接同一次拖动合并")
	var after := session.snapshot()
	check(session.undo() and session.snapshot() == baseline and not session.is_dirty() and not session.can_undo(), "合并候选只占一条撤销并恢复保存态")
	remember(session.build())
	check(session.redo() and session.snapshot() == after and session.is_dirty(), "公开 redo 还原候选")
	remember(session.build())
	var draft := session.export_draft()
	var restored := Session.new()
	var recovered := restored.restore_draft(draft)
	remember(recovered)
	check(recovered.ok and restored.snapshot() == after and restored.saved_fingerprint() == basefp and restored.is_dirty(), "草稿恢复当前配方与原保存指纹")
	check(not restored.mark_saved(basefp) and restored.is_dirty(), "旧保存请求不能标记新文档为干净")
	check(restored.mark_saved(restored.fingerprint()) and not restored.is_dirty(), "成功保存按当前稳定指纹标记")
	var malformed := draft.duplicate(true)
	malformed.saved_fingerprint = "not-json"
	check(not restored.restore_draft(malformed).ok and restored.snapshot() == after and not restored.is_dirty(), "坏草稿不改现有文档")
	check(session.undo(), "分叉前撤销")
	remember(session.build())
	var patched := session.apply_patch({"height": baseline.height + 0.2})
	remember(patched)
	check(patched.ok and not session.can_redo(), "新编辑清 redo")
	check(not session.apply_patch({"unknown": 1}).ok, "patch 拒绝未知字段")
	var old := small_recipe()
	for key in Recipe.OPTIONAL_KEYS: old.erase(key)
	var normalized := session.load_recipe(old)
	remember(normalized)
	check(normalized.ok and session.snapshot() == Recipe.normalized(old) and not session.can_undo() and not session.is_dirty(), "load_recipe 归一化旧文档")
	for owned in session_roots:
		if is_instance_valid(owned): owned.free()
	session_roots.clear()
	completed_sections.append("session")

func test_store() -> void:
	var store := Store.new()
	var recipe := small_recipe()
	recipe.name = "immutable-test"
	for path in ["res://scenes/workshop_buildings", "res://outputs/other", "res://outputs/plant_editor/../other", "/", OS.get_environment("HOME"), "user://plant_authoring_test_bad"]:
		check(not store.save(recipe, path).ok, "Store 拒绝未授权根 " + path)
	var external := ProjectSettings.globalize_path("user://").trim_suffix("/") + "/plant_authoring_test_%d" % Time.get_ticks_usec()
	var explicit := Store.new(external)
	check(explicit._validate_root(external).is_empty() and not store.save(recipe, external).ok, "工程外测试根必须显式注入，不自动接受个人路径")
	var first := explicit.save(recipe, external)
	check(first.ok, "真实几何第一版保存闭环", first.reason)
	if not first.ok: return
	var paths: Array[String] = [first.recipe_path, first.scene_path, first.manifest_path]
	var hashes := file_hashes(paths)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first.manifest_path))
	check(manifest.revision == 1 and manifest.candidate_id == "immutable-test/revision_0001" and manifest.candidate_only and manifest.noMain and not manifest.formal_registry_written, "manifest 候选身份及 revision")
	check(manifest.recipe_fingerprint == Recipe.fingerprint(recipe) and manifest.geometry_fingerprint.length() == 64 and manifest.uv_fingerprint.length() == 64 and manifest.material_fingerprint.length() == 64, "manifest 稳定配方 JSON 与 geometry/UV/material SHA256")
	check(manifest.scene_sha256 == hashes[first.scene_path] and manifest.recipe_sha256 == hashes[first.recipe_path], "manifest 文件哈希对应真实产物")
	var source_match := true
	for path in manifest.source_path_hashes:
		source_match = source_match and manifest.source_path_hashes[path] == FileAccess.get_sha256(path) and not str(manifest.source_path_hashes[path]).is_empty()
	check(source_match and manifest.source_path_hashes.has("res://src/plant_authoring/species.gd") and manifest.source_path_hashes.has("res://src/plant_authoring/leaf.gdshader"), "完整生成源与外链 sourcehash")
	var loaded := explicit.load_recipe(first.recipe_path)
	check(loaded.ok and Recipe.fingerprint(loaded.recipe) == Recipe.fingerprint(recipe), "保存配方读回归一化一致")
	var packed := ResourceLoader.load(first.scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	check(packed != null, "真实静态 PackedScene 重载")
	if packed != null:
		var instance := packed.instantiate()
		var snap := explicit._geometry_snapshot(instance)
		var generated := Generator.build(recipe)
		explicit._prepare_static_tree(generated.root)
		check(explicit._verify_static_snapshot(explicit._geometry_snapshot(generated.root), snap).is_empty(), "重载逐节点 vertices/indices/normals/UV/UV2/material 身份一致")
		check(snap.scripts == 0 and snap.cameras == 0 and snap.lights == 0 and snap.collisions == 0, "导出无脚本/相机/灯光/碰撞")
		check(snap.geometry_fingerprint == manifest.geometry_fingerprint and snap.uv_fingerprint == manifest.uv_fingerprint and snap.material_fingerprint == manifest.material_fingerprint, "manifest 指纹与最终路径真实重载数据完全对应")
		generated.root.free()
		instance.free()
	recipe.height += 0.4
	var second := explicit.save(recipe, external)
	check(second.ok and second.get("revision") == 2 and second.directory != first.directory, "第二次只新增 revision_0002", second.reason)
	check(file_hashes(paths) == hashes, "旧 revision 三个文件逐字节 immutable")
	check(explicit.list_recipes(external).size() == 2, "列表只包含两次已提交 revision")
	var invalid := recipe.duplicate(true)
	invalid.species = "tree"
	check(not explicit.save(invalid, external).ok and explicit.list_recipes(external).size() == 2 and file_hashes(paths) == hashes, "坏配方不写 revision、不改旧版")
	var empty := recipe.duplicate(true)
	empty.trunk_visible = false
	empty.leaves_visible = false
	check(not explicit.save(empty, external).ok, "非空几何门禁在创建 tmp 后拒绝空树")
	var candidate_dir := str(first.directory).get_base_dir()
	var entries := DirAccess.open(candidate_dir).get_directories()
	var no_tmp := true
	for entry in entries: no_tmp = no_tmp and not entry.begins_with(".tmp_")
	check(no_tmp and explicit.list_recipes(external).size() == 2 and file_hashes(paths) == hashes, "失败仅清理本次自建 tmp，历史两版不变")
	var fake_tmp: String = str(first.directory).get_base_dir() + "/.tmp_foreign"
	DirAccess.make_dir_recursive_absolute(fake_tmp)
	var sentinel := fake_tmp + "/keep.txt"
	var file := FileAccess.open(sentinel, FileAccess.WRITE)
	file.store_string("保留其它会话文件")
	file.close()
	explicit._remove_dir(fake_tmp)
	explicit._remove_dir(first.directory)
	explicit._remove_dir(external)
	check(FileAccess.file_exists(sentinel) and file_hashes(paths) == hashes, "清理拒绝非本次创建 tmp、旧版及个人测试根")
	artifact_paths.append(external)
	print("[plant-authoring-artifacts] ", external)
	completed_sections.append("store")

func test_snapshot_regressions() -> void:
	var store := Store.new()
	var root_node := Node3D.new()
	root_node.position = Vector3(5, 1, 0)
	var parent := Node3D.new()
	parent.position = Vector3(2, 3, 0)
	root_node.add_child(parent)
	var visual := MeshInstance3D.new()
	visual.mesh = triangle_mesh()
	visual.position = Vector3(1, 0, 0)
	parent.add_child(visual)
	var snap := store._geometry_snapshot(root_node)
	check(absf(float(snap.bounds_position[0]) - 8.0) < 0.0001 and absf(float(snap.bounds_position[1]) - 4.0) < 0.0001, "snapshot 累积祖先 transform 而非局部")
	var before := snap
	var arrays := visual.mesh.surface_get_arrays(0)
	var ps: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	ps[0].x += 0.25
	arrays[Mesh.ARRAY_VERTEX] = ps
	var material := visual.mesh.surface_get_material(0)
	visual.mesh = ArrayMesh.new()
	visual.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	visual.mesh.surface_set_material(0, material)
	check(not store._verify_static_snapshot(before, store._geometry_snapshot(root_node)).is_empty(), "数量相同但顶点改变必须拒绝")
	visual.mesh = triangle_mesh()
	before = store._geometry_snapshot(root_node)
	arrays = visual.mesh.surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	uv2[0].x += 0.02
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	visual.mesh = ArrayMesh.new()
	visual.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	check(not store._verify_static_snapshot(before, store._geometry_snapshot(root_node)).is_empty(), "相同 count 的 UV2 改动必须拒绝")
	visual.mesh = triangle_mesh()
	before = store._geometry_snapshot(root_node)
	var close := before.duplicate(true)
	var path := str(root_node.get_path_to(visual))
	close.nodes[path].surfaces[0].uv2[0] += Vector2(0.00001, 0)
	check(store._verify_static_snapshot(before, close).is_empty(), "UV2 重载允许明确浮点容差")
	for field in ["normals", "uv", "indices"]:
		arrays = triangle_mesh().surface_get_arrays(0)
		if field == "indices": arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1])
		elif field == "normals": arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.BACK, Vector3.BACK])
		else:
			var changed_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			changed_uv[0] += Vector2(0.02, 0)
			arrays[Mesh.ARRAY_TEX_UV] = changed_uv
		visual.mesh = ArrayMesh.new()
		visual.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var changed := store._geometry_snapshot(root_node)
		check(store._verify_static_snapshot(before, before).is_empty() and not store._verify_static_snapshot(before, changed).is_empty(), "逐数据拒绝真实网格同 count 篡改 " + field, store._verify_static_snapshot(before, changed))
	visual.mesh = triangle_mesh()
	var multi_node := MultiMeshInstance3D.new()
	multi_node.multimesh = MultiMesh.new()
	multi_node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_node.multimesh.mesh = triangle_mesh()
	multi_node.multimesh.instance_count = 2
	multi_node.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	multi_node.multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(20, 0, 0)))
	parent.add_child(multi_node)
	before = store._geometry_snapshot(root_node)
	var multi_path := str(root_node.get_path_to(multi_node))
	check(multi_node.multimesh.get_instance_transform(0).origin == Vector3(10, 0, 0) and multi_node.multimesh.get_instance_transform(1).origin == Vector3(20, 0, 0), "后端必须真实保留 MultiMesh 实例数据（Dummy 不满足时须 runner --visual）", {"method": RenderingServer.get_current_rendering_method(), "buffer_size": multi_node.multimesh.buffer.size()})
	check(store._verify_static_snapshot(before, before).is_empty(), "MultiMesh 校验基线无脚本相机碰撞", store._verify_static_snapshot(before, before))
	check(before.triangles == 3 and float(before.bounds_position[0]) + float(before.bounds_size[0]) > 27.5, "MultiMesh 逐实例变换计数与范围", {"triangles": before.triangles, "bounds_position": before.bounds_position, "bounds_size": before.bounds_size, "instances": before.nodes[multi_path].instances, "buffer": multi_node.multimesh.buffer})
	multi_node.multimesh.set_instance_transform(1, Transform3D(Basis.IDENTITY, Vector3(21, 0, 0)))
	var after_multi := store._geometry_snapshot(root_node)
	check(not store._verify_static_snapshot(before, after_multi).is_empty(), "MultiMesh 相同 count 不同实例位置必须拒绝", {"reason": store._verify_static_snapshot(before, after_multi), "instances": after_multi.nodes[multi_path].instances})
	var camera := Camera3D.new()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	root_node.add_child(camera)
	root_node.add_child(body)
	var scripted := ScriptedVisual.new()
	root_node.add_child(scripted)
	var forbidden := store._geometry_snapshot(root_node)
	check(forbidden.scripts == 1 and forbidden.cameras == 1 and forbidden.collisions == 2 and store._verify_static_snapshot(forbidden, forbidden).begins_with("静态场景含禁止节点"), "禁止节点即使前后相同也必须严格拒绝")
	var animated := ShaderMaterial.new()
	animated.resource_name = "Plant_leaf"
	animated.resource_local_to_scene = true
	animated.shader = load("res://src/plant_authoring/leaf.gdshader")
	animated.set_shader_parameter("palette_texture", load(Geometry.PALETTE_PATH))
	animated.set_shader_parameter("surface_roughness", 0.8)
	animated.set_shader_parameter("local_time", 12.0)
	animated.set_shader_parameter("preview_wind", true)
	visual.mesh.surface_set_material(0, animated)
	store._prepare_static_tree(root_node)
	var static_material := visual.get_active_material(0) as ShaderMaterial
	check(static_material != animated and static_material.get_shader_parameter("local_time") == 0.0 and static_material.get_shader_parameter("preview_wind") == false, "保存前复制材质并清零本地风")
	check(animated.get_shader_parameter("local_time") == 12.0 and animated.get_shader_parameter("preview_wind") == true, "静态保存不改原预览材质")
	snap = store._geometry_snapshot(root_node)
	check(snap.scripts == 0 and snap.cameras == 0 and snap.collisions == 0, "静态整理剔除相机碰撞并移除脚本")
	var packed := PackedScene.new()
	check(packed.pack(root_node) == OK, "真实合成网格与 MultiMesh 打包")
	var scene_path := "res://outputs/plant_snapshot_regression.tscn"
	check(ResourceSaver.save(packed, scene_path) == OK, "真实合成几何写盘")
	var reloaded := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	check(reloaded != null, "真实合成几何重载 PackedScene")
	if reloaded != null:
		var instance := reloaded.instantiate()
		var loaded_snapshot := store._geometry_snapshot(instance)
		check(store._verify_static_snapshot(snap, loaded_snapshot).is_empty(), "真实 Mesh/MultiMesh 保存重载逐顶点法线 UV2/实例/材质校验", store._verify_static_snapshot(snap, loaded_snapshot))
		check(loaded_snapshot.material_fingerprint == snap.material_fingerprint, "重载材质参数及 shader/palette 外链 hash 稳定")
		instance.free()
	artifact_paths.append(ProjectSettings.globalize_path(scene_path))
	var changed_identity := snap.duplicate(true)
	changed_identity.materials[path + "/surface_0"].properties.palette_texture.path = "res://different_palette.png"
	check(not store._verify_static_snapshot(snap, changed_identity).is_empty(), "材质外链身份不同即使几何 count 一样也拒绝")
	static_material.set_shader_parameter("surface_roughness", 0.2)
	var material_changed := store._geometry_snapshot(root_node)
	check(snap.material_fingerprint != material_changed.material_fingerprint and not store._verify_static_snapshot(snap, material_changed).is_empty(), "材质参数变更进入 fingerprint 与重载门禁")
	root_node.free()
	completed_sections.append("snapshot")

func small_recipe() -> Dictionary:
	var recipe := Recipe.defaults()
	recipe.branch_count = 3
	recipe.subtwig_count = 1
	recipe.leaf_density = 0.25
	recipe.grass_enabled = false
	recipe.moss_enabled = false
	recipe.vine_enabled = false
	return recipe

func mesh_signature(root_node: Node) -> Dictionary:
	return Store.new()._geometry_snapshot(root_node).nodes

func shared_signature() -> Dictionary:
	var result: Dictionary = {}
	for key in Recipe.GRASS_ASSETS:
		var mesh: Mesh = Library.mesh(key)
		var surfaces: Array = []
		for surface in mesh.get_surface_count(): surfaces.append(var_to_bytes(mesh.surface_get_arrays(surface)).hex_encode().sha256_text())
		result[key] = [surfaces, Store.new()._material_identity(Library.material(key))]
	return result

func file_hashes(paths: Array[String]) -> Dictionary:
	var hashes: Dictionary = {}
	for path in paths:
		hashes[path] = FileAccess.get_sha256(path)
		check(str(hashes[path]).length() == 64, "实际文件存在且 SHA256 非空 " + path)
	return hashes

func remember(result: Dictionary) -> void:
	if result.get("ok", false) and is_instance_valid(result.get("root")) and not session_roots.has(result.root): session_roots.append(result.root)

func triangle_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0.02, 0.02), Vector2(0.1, 0.02), Vector2(0.02, 0.1)])
	arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV].duplicate()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a).normalized()
	var projected := point - normal * normal.dot(point - a)
	var inside := true
	for edge in [[a, b], [b, c], [c, a]]:
		inside = inside and (edge[1] - edge[0]).cross(projected - edge[0]).dot(normal) >= -0.0000001
	if inside: return absf(normal.dot(point - a))
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))
