@tool
extends SceneTree
## 仅供统一 runner 的 plant-integration；禁止以降低断言换取动态保存通过。
const Recipe = preload("res://src/plant_authoring/recipe.gd")
const Generator = preload("res://src/plant_authoring/generator.gd")
const Geometry = preload("res://src/plant_authoring/geometry.gd")
const TrunkPath = preload("res://src/plant_authoring/trunk_path.gd")
const Session = preload("res://src/plant_authoring/session.gd")
const Store = preload("res://src/plant_authoring/store.gd")
const WindRuntime = preload("res://src/plant_authoring/wind_runtime.gd")
const REPORT_PATH := "res://outputs/plant_integration_report.json"
const REQUIRED_SECTIONS := ["paths", "attachments", "streams-details", "session", "runtime", "store", "host-attachment"]
var checks := 0
var failures: Array[String] = []
var completed_sections: Array[String] = []
var artifacts: Array[String] = []
var diagnostics: Dictionary = {}
var pending: Array[String] = []
var signals_seen := 0
var session_roots: Array[Node] = []

# 用写入计数捕获同值回写，不能只比较最终值而漏掉 owner 被修改。
class ReadOnlyWindOwner extends Node3D:
	var writes := 0
	var elapsed := 19.25:
		set(value):
			writes += 1
			elapsed = value
	var strength := 0.73:
		set(value):
			writes += 1
			strength = value
	var direction := Vector2(-3.0, 4.0):
		set(value):
			writes += 1
			direction = value

class ForbiddenScript extends Node3D:
	pass

func _init() -> void:
	if OS.get_cmdline_user_args().has("--wind-editor-only"):
		call_deferred("test_editor_wind")
	else:
		call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		var message := label + " " + str(detail)
		failures.append(message)
		printerr("FAIL [plant-integration] ", message)

func run() -> void:
	check(not ProjectSettings.has_setting("autoload/GameState"), "runner 隔离玩法 Autoload")
	test_paths()
	test_attachments()
	test_streams_details()
	test_session()
	test_runtime()
	test_store()
	test_host_attachment()
	for section in REQUIRED_SECTIONS:
		check(completed_sections.has(section), "专项完整返回，不能由脚本错误跳过 " + section)
	var report := {
		"suite": "plant-integration", "completed_sections": completed_sections,
		"artifacts": artifacts, "diagnostics": diagnostics, "pending": pending,
		"engine": Engine.get_version_info(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"screenshots": [], "expected_failures": [],
		"scope": "真实网格/法线/UV/COLOR、Session、PackedScene 写盘重载与风参数；未采集截图，不替代 UI 或美术目检"
	}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	check(directory_error == OK, "报告目录可用", directory_error)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "报告可写", FileAccess.get_open_error())
	if file != null:
		report["checks"] = checks
		report["failures"] = failures
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
		print("[plant-integration-report] ", ProjectSettings.globalize_path(REPORT_PATH))
	print("[plant-integration] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func small_recipe(kind: String = "camphor") -> Dictionary:
	var recipe := Recipe.defaults(kind)
	recipe.foliage_mode = "geometry"
	recipe.branch_count = 3
	recipe.subtwig_count = 1
	recipe.leaf_density = 0.25
	recipe.grass_enabled = false
	recipe.moss_enabled = false
	recipe.vine_enabled = false
	return recipe

func curved_recipe(kind: String = "camphor") -> Dictionary:
	var recipe := small_recipe(kind)
	recipe.trunk_path = [
		{"x": 0.0, "y": 0.0, "z": 0.0},
		{"x": 0.8, "y": 1.1, "z": -0.3},
		{"x": -0.45, "y": recipe.height * 0.61, "z": 0.65},
		{"x": 0.6, "y": recipe.height, "z": -0.2}
	]
	return recipe

func test_paths() -> void:
	for kind in Recipe.SPECIES:
		var recipe := curved_recipe(kind)
		check(Recipe.validate(recipe).is_empty(), kind + " 非均匀米制控制点合法", Recipe.validate(recipe))
		var built := Generator.build(recipe)
		check(built.ok, kind + " 手动弯干生成", built.reason)
		if not built.ok:
			continue
		var points := TrunkPath.points(recipe)
		var trunk := built.root.get_node("Trunk/MainTrunk") as MeshInstance3D
		var vertices: PackedVector3Array = trunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(points.size() == 49 and built.stats.trunk_rings == 49, kind + " 三段路径逐段16步含端点")
		for index in recipe.trunk_path.size():
			var point: Dictionary = recipe.trunk_path[index]
			var expected := Vector3(point.x, point.y, point.z)
			check(TrunkPath.sample(recipe, float(point.y) / float(recipe.height)).distance_to(expected) < 0.00001, kind + " 连续采样命中控制点 %d" % index)
			check(ring_center(vertices, index * 16, points.size(), 12).distance_to(expected) < 0.00001, kind + " 实际主干环中心命中控制点 %d" % index)
		var path_data: Dictionary = built.root.get_meta("trunk_path", {})
		check(path_data.get("mode") == "manual" and path_data.get("units") == "meters" and path_data.get("parameter") == "y/height", kind + " 绑定元数据使用米制高度参数")
		check(path_data.get("points") == PackedVector3Array(points), kind + " 绑定中心线与真实环一致")
		for index in recipe.branch_count:
			var ratio := lerpf(float(recipe.branch_start) / float(recipe.height), 0.91, float(index) / float(recipe.branch_count - 1))
			if kind == "maple":
				ratio = float(recipe.branch_start) / float(recipe.height)
			var expected := point_at_height(points, ratio * float(recipe.height))
			var branch := built.root.get_node("Trunk/branch_%02d" % index) as Node3D
			var wood := branch.get_node("Wood") as MeshInstance3D
			var wood_vertices: PackedVector3Array = wood.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check(branch.position.distance_to(expected) < 0.00001 and (branch.position + ring_center(wood_vertices, 0, 9, 8)).distance_to(expected) < 0.00001, kind + " 主枝实际首环随非均匀弯干 %d" % index)
			check((built.root.get_node("Leaves/branch_%02d" % index) as Node3D).position.is_equal_approx(branch.position), kind + " 叶组跟随主枝 %d" % index)
		audit_meshes(built.root, kind + " 弯干")
		built.root.free()
		var auto := small_recipe(kind)
		var old := auto.duplicate(true)
		for key in Recipe.OPTIONAL_KEYS:
			old.erase(key)
		# 旧字段补全会恢复默认 subtwig_count；比较其归一化结果而非人为缩小的当前配方。
		var normalized := Recipe.normalized(old)
		check(Recipe.validate(old).is_empty() and normalized.trunk_path.is_empty(), kind + " 旧配方默认自动路径")
		var actual := TrunkPath.points(auto)
		var legacy := legacy_auto_points(auto)
		check(actual == legacy and actual.size() == 17, kind + " auto逐点保持旧17环公式")
		var omitted := auto.duplicate(true)
		omitted.erase("trunk_path")
		var a := Generator.build(auto)
		var b := Generator.build(omitted)
		check(a.ok and b.ok, kind + " 缺省路径兼容生成")
		if a.ok and b.ok:
			check(geometry_data(a.root) == geometry_data(b.root), kind + " 缺省路径与显式auto实际几何完全一致")
		if a.ok: a.root.free()
		if b.ok: b.root.free()
	for entry in invalid_paths():
		var bad := curved_recipe()
		bad.trunk_path = entry.path
		var reason := Recipe.validate(bad)
		check(not reason.is_empty() and reason.contains("trunk_path") and Recipe.fingerprint(bad).is_empty(), "非法路径拒绝且无指纹 " + entry.label, reason)
		var rejected := Generator.build(bad)
		check(not rejected.ok and rejected.root == null and rejected.stats.triangles == 0, "非法路径不能分配树 " + entry.label, rejected.reason)
		if is_instance_valid(rejected.root): rejected.root.free()
	completed_sections.append("paths")

func invalid_paths() -> Array:
	var controls: Array = curved_recipe().trunk_path
	var result: Array = []
	for label in ["NaN", "乱序", "末高", "根偏", "过近", "无穷", "缺轴", "超数量"]:
		var path := controls.duplicate(true)
		match label:
			"NaN": path[1].x = NAN
			"乱序": path.reverse()
			"末高": path[-1].y -= 0.1
			"根偏": path[0].x = 0.01
			"过近": path[1].y = 0.005
			"无穷": path[1].z = INF
			"缺轴": path[1].erase("z")
			"超数量":
				path.clear()
				for index in 9:
					path.append({"x": 0.0, "y": 7.2 * float(index) / 8.0, "z": 0.0})
		result.append({"label": label, "path": path})
	return result

func test_attachments() -> void:
	var recipe := curved_recipe()
	recipe.moss_enabled = true
	recipe.moss_amount = 0.08
	recipe.moss_scale = 0.13
	recipe.vine_enabled = true
	recipe.vine_count = 1
	recipe.bark_detail = 0.05
	var built := Generator.build(recipe)
	check(built.ok, "弯干附生真实生成", built.reason)
	if not built.ok: return
	check_attached_patches(built.root, "Moss/AttachedPatches", 0.002)
	check_attached_patches(built.root, "Trunk/BarkDetail", 0.0008)
	var points := TrunkPath.points(recipe)
	var radii := Generator._trunk_radii(recipe, points)
	for index in recipe.vine_count:
		var id := "vine_%02d" % index
		var rng := Generator._rng(recipe, id + "/path")
		var ratio := clampf(0.36 + fposmod(index * 0.38196601125, 1.0) * 0.40 + Generator._range(recipe, rng, -0.05, 0.05), 0.30, 0.83)
		var angle: float = float(index) * 2.3999632297 + Generator._range(recipe, rng, -0.35, 0.35)
		var station := Geometry.tube_height_station(points, ratio * float(recipe.height))
		var host := Geometry.tube_surface(points, radii, station, angle)
		var visual := built.root.get_node("Vines/" + id) as MeshInstance3D
		var vertices: PackedVector3Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var center := ring_center(vertices, 0, 13, 5)
		check(center.distance_to(host.position + host.normal * 0.016) < 0.00001, "藤蔓实际首环随弯干真实表面 " + id)
		check(nearest_face_distance(center - host.normal * 0.016, (built.root.get_node("Trunk/MainTrunk") as MeshInstance3D).mesh.get_faces()) < 0.00001, "藤蔓绑定点落在实际树皮三角面 " + id)
	var changed := recipe.duplicate(true)
	changed.trunk_path[1].x += 0.5
	changed.trunk_path[2].z -= 0.4
	var moved := Generator.build(changed)
	check(moved.ok, "修改宿主后重建附生", moved.reason)
	if moved.ok:
		for group in ["Trunk/MainTrunk", "Moss", "Vines"]:
			check(geometry_data(moved.root.get_node(group)) != geometry_data(built.root.get_node(group)), "宿主变动实际移动 " + group)
		check_attached_patches(moved.root, "Moss/AttachedPatches", 0.002)
		moved.root.free()
	built.root.free()
	completed_sections.append("attachments")

func test_streams_details() -> void:
	var recipe := curved_recipe()
	recipe.moss_enabled = true
	recipe.vine_enabled = true
	recipe.vine_count = 1
	recipe.moss_amount = 0.08
	recipe.bark_detail = 0.05
	seed(71129)
	var expected_random := randi()
	seed(71129)
	var base := Generator.build(recipe)
	check(randi() == expected_random, "生成不消费全局随机流")
	check(base.ok, "随机流基线", base.reason)
	if not base.ok: return
	var repeated := Generator.build(recipe)
	check(repeated.ok, "相同seed重建")
	if repeated.ok:
		check(geometry_data(base.root) == geometry_data(repeated.root), "相同seed所有位置法线UV与索引复现")
		repeated.root.free()
	for patch in [{"bark_detail": 0.8}, {"moss_scale": 0.28, "moss_amount": 0.4}, {"leaf_density": 0.5}]:
		var next := recipe.duplicate(true)
		next.merge(patch, true)
		var changed := Generator.build(next)
		check(changed.ok, "独立细节参数生成 " + str(patch), changed.reason)
		if not changed.ok: continue
		for path in ["Trunk/MainTrunk", "Trunk/branch_00", "Trunk/branch_01", "Vines"]:
			check(geometry_data(changed.root.get_node(path)) == geometry_data(base.root.get_node(path)), "细节不重抽宿主/主枝/藤 " + path + str(patch))
		if not patch.has("leaf_density"):
			check(geometry_data(changed.root.get_node("Leaves")) == geometry_data(base.root.get_node("Leaves")), "附生细节不重抽叶")
		changed.root.free()
	var next := recipe.duplicate(true)
	next.seed += 17
	var changed := Generator.build(next)
	check(changed.ok, "新seed生成")
	if changed.ok:
		check(geometry_data(changed.root.get_node("Trunk/MainTrunk")) == geometry_data(base.root.get_node("Trunk/MainTrunk")), "手动主干不受seed扰动")
		check(geometry_data(changed.root.get_node("Leaves")) != geometry_data(base.root.get_node("Leaves")), "seed仍改变真实叶几何")
		changed.root.free()
	next = recipe.duplicate(true)
	next.branch_overrides = {"branch_00": {"enabled": false}}
	changed = Generator.build(next)
	check(changed.ok, "关闭单枝生成")
	if changed.ok:
		check(changed.root.get_node("Trunk/branch_00").get_child_count() == 0 and changed.root.get_node("Leaves/branch_00").get_child_count() == 0, "禁用枝同时移除木与叶")
		check(geometry_data(changed.root.get_node("Trunk/branch_01")) == geometry_data(base.root.get_node("Trunk/branch_01")), "禁用单枝不扰动邻枝")
		check(changed.stats.leaf_count == Recipe.leaf_count(next) and changed.stats.leaf_count > 0, "禁用枝真实叶预算仍非空")
		changed.root.free()
	base.root.free()
	next = recipe.duplicate(true)
	next.random_enabled = false
	var fixed := Generator.build(next)
	next.seed += 101
	var other := Generator.build(next)
	check(fixed.ok and other.ok, "关闭随机仍可生成")
	if fixed.ok and other.ok:
		check(geometry_data(fixed.root) == geometry_data(other.root), "关闭随机后seed不改变任何真实几何或UV")
	if fixed.ok: fixed.root.free()
	if other.ok: other.root.free()
	var stress := curved_recipe()
	stress.trunk_path = []
	for index in 8:
		stress.trunk_path.append({"x": sin(float(index)) * 0.6 if index > 0 else 0.0, "y": float(stress.height) * float(index) / 7.0, "z": 0.0})
	stress.bark_detail = 1.0
	stress.moss_enabled = true
	stress.moss_amount = 1.0
	stress.moss_scale = 1.0
	stress.moss_height = 1.0
	stress.color_mode = "manual"
	stress.trunk_cell = 15
	stress.bark_cell = 10
	stress.moss_cell = 35
	var detailed := Generator.build(stress)
	check(detailed.ok, "最大路径与细节合法预算生成", detailed.reason)
	if detailed.ok:
		var bark_count := triangle_count(detailed.root.get_node("Trunk/BarkDetail"))
		var moss_count := triangle_count(detailed.root.get_node("Moss/AttachedPatches"))
		check(bark_count > 0 and bark_count <= Generator.BARK_TRIANGLE_BUDGET and bark_count == detailed.stats.bark_triangles, "树皮实际三角数受预算限制", bark_count)
		check(moss_count > 0 and moss_count <= Generator.MOSS_TRIANGLE_BUDGET and moss_count == detailed.stats.moss_triangles, "苔藓实际三角数受预算限制", moss_count)
		check(detailed.stats.trunk_rings == TrunkPath.MAX_RINGS and detailed.stats.leaf_count > 0 and detailed.stats.leaf_count == Recipe.leaf_count(stress), "最大113环但保留非空叶")
		check_uv_cell(detailed.root.get_node("Trunk/MainTrunk"), 15)
		check_uv_cell(detailed.root.get_node("Trunk/BarkDetail"), 10)
		check_uv_cell(detailed.root.get_node("Moss/AttachedPatches"), 35)
		audit_meshes(detailed.root, "最大细节预算")
		detailed.root.free()
	stress.branch_count = 18
	stress.subtwig_count = 8
	stress.leaf_density = 2.0
	check(Recipe.leaf_count(stress) > Recipe.LEAF_BUDGET and not Recipe.validate(stress).is_empty(), "超叶预算拒绝而非截断成空树")
	completed_sections.append("streams-details")

func test_session() -> void:
	var session := Session.new()
	var loaded := session.load_recipe(curved_recipe())
	remember(loaded)
	check(loaded.ok, "Session加载弯干", loaded.reason)
	if not loaded.ok: return
	signals_seen = 0
	session.changed.connect(func() -> void: signals_seen += 1)
	var baseline := session.snapshot()
	var original_geometry := geometry_data(loaded.root)
	var basefp := session.fingerprint()
	var detached := session.snapshot()
	detached.trunk_path[1].x += 2.0
	check(session.snapshot() == baseline, "结构化路径snapshot深拷贝")
	var candidate := baseline.duplicate(true)
	candidate.trunk_path[1].x += 0.3
	var edited := session.preview_candidate(candidate, false, basefp)
	remember(edited)
	check(edited.ok and signals_seen == 1 and session.is_dirty() and session.can_undo(), "路径修改只发一次信号并入历史")
	var fp := session.fingerprint()
	candidate.trunk_path[1].x += 0.2
	var merged := session.preview_candidate(candidate, true, fp)
	remember(merged)
	check(merged.ok and signals_seen == 2, "路径拖动指纹合并")
	var before_invalid := session.snapshot()
	var cached_root: Node = session.build().root
	var savedfp := session.saved_fingerprint()
	for entry in invalid_paths():
		var invalid := before_invalid.duplicate(true)
		invalid.trunk_path = entry.path
		check(not session.preview_candidate(invalid).ok and not session.load_recipe(invalid).ok and not session.apply_patch({"trunk_path": entry.path}).ok, "Session非法路径各入口拒绝 " + entry.label)
		check(session.snapshot() == before_invalid and session.saved_fingerprint() == savedfp and session.build().root == cached_root and signals_seen == 2 and session.can_undo() and not session.can_redo() and session.is_dirty(), "失败配方/预览/保存态/历史/信号原子 " + entry.label)
	check(session.undo(), "路径一次撤销")
	remember(session.build())
	check(session.snapshot() == baseline and not session.is_dirty() and not session.can_undo() and session.can_redo() and geometry_data(session.build().root) == original_geometry, "合并拖动一次撤销真实几何与保存态")
	var bad := baseline.duplicate(true)
	bad.trunk_path[1].x = NAN
	var before_signals := signals_seen
	check(not session.preview_candidate(bad).ok and session.can_redo() and signals_seen == before_signals, "非法候选不能清redo或发信号")
	check(session.redo() and session.snapshot() == before_invalid and session.is_dirty(), "redo恢复弯干")
	remember(session.build())
	check(not session.mark_saved(basefp) and session.is_dirty(), "过期保存不能清dirty")
	for owned in session_roots:
		if is_instance_valid(owned): owned.free()
	session_roots.clear()
	completed_sections.append("session")

func test_editor_wind() -> void:
	# --editor 启动的扫描/窗口尚未就绪时不能立即退出，否则掩盖真实风专项结果。
	for frame in 10:
		await process_frame
	if Engine.is_editor_hint():
		while EditorInterface.get_resource_filesystem().is_scanning():
			await process_frame
	check(Engine.is_editor_hint(), "风专项运行在真实editor hint上下文")
	check((WindRuntime as Script).is_tool(), "风脚本是tool，不产生placeholder")
	var built := Generator.build(small_recipe())
	check(built.ok, "编辑器风fixture生成", built.reason)
	if built.ok:
		built.root.set_script(WindRuntime)
		for child in built.root.find_children("*", "", true, false):
			child.owner = built.root
		var packed := PackedScene.new()
		check(packed.pack(built.root) == OK, "编辑器动态根PackedScene打包")
		var a := packed.instantiate()
		var b := packed.instantiate()
		var before := geometry_data(a)
		var original_mesh: Mesh = a.get_node("Trunk/MainTrunk").mesh
		var original_materials := materials_of(a)
		root.add_child(a)
		check(not a.is_processing() and a.get("_materials").is_empty(), "editor ready禁止自动prepare与process")
		a.set_process(true)
		a.call("_process", 0.5)
		a.call("_update_wind", 0.5)
		check(a.get_node("Trunk/MainTrunk").mesh == original_mesh and not a.get_node("Trunk/MainTrunk").has_meta("plant_wind_prepared") and geometry_data(a) == before, "editor自动回调不改网格与metadata")
		var unchanged := true
		for material in original_materials:
			unchanged = unchanged and not bool(material.get_shader_parameter("preview_wind")) and float(material.get_shader_parameter("local_time")) == 0.0
		check(unchanged, "editor自动回调不写材质参数")
		a.call("sample_at", 4.25, 0.31, Vector2.RIGHT)
		b.call("sample_at", 9.75, 1.4, Vector2.UP)
		check_sample(a, 4.25, 0.31, Vector2.RIGHT, "editor入树实例显式采样")
		check_sample(b, 9.75, 1.4, Vector2.UP, "editor未入树PackedScene显式采样无placeholder")
		a.call("_process", 0.5)
		check_sample(a, 4.25, 0.31, Vector2.RIGHT, "editor显式采样后自动回调仍不推进")
		var prepared := geometry_data(b)
		var prepared_mesh: Mesh = b.get_node("Trunk/MainTrunk").mesh
		root.add_child(b)
		check(not b.is_processing() and geometry_data(b) == prepared and b.get_node("Trunk/MainTrunk").mesh == prepared_mesh, "editor采样后入树不重复prepare")
		check_sample(b, 9.75, 1.4, Vector2.UP, "editor入树ready不覆盖显式采样")
		unchanged = true
		for material in original_materials:
			unchanged = unchanged and not bool(material.get_shader_parameter("preview_wind")) and float(material.get_shader_parameter("local_time")) == 0.0
		check(unchanged, "editor显式采样只改实例副本，不污染原始材质")
		a.free()
		b.free()
		built.root.free()
	print("[plant-wind-editor] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_wind_digest(model: Node) -> void:
	var compact_bytes := 0
	var legacy_bytes := 0
	var surfaces := 0
	for visual in visuals(model):
		var snapshot := WindRuntime._mesh_geometry_snapshot(visual.mesh)
		var digest: Array = visual.get_meta(WindRuntime.PREPARED_GEOMETRY_META)
		compact_bytes += var_to_bytes(digest).size()
		legacy_bytes += var_to_bytes(snapshot).size()
		surfaces += snapshot.size()
		check(digest == WindRuntime._geometry_digest(snapshot) and WindRuntime._matches_prepared_snapshot(visual), "准备后摘要精确匹配 " + str(visual.name))
		for surface: Dictionary in digest:
			check(surface.size() == 5, "摘要逐字段保留五种几何通道")
			for value in surface.values():
				check(value is String and value.length() == 64, "metadata仅保存固定长SHA256，无完整几何数组")
	for child in model.find_children("*", "", true, false):
		child.owner = model
	var packed := PackedScene.new()
	check(packed.pack(model) == OK, "紧凑风快照实际打包")
	var compact_path := "user://wind_digest_compact.tscn"
	var legacy_path := "user://wind_digest_legacy.tscn"
	check(ResourceSaver.save(packed, compact_path) == OK, "紧凑风快照实际写盘")
	for visual in visuals(model):
		visual.set_meta(WindRuntime.PREPARED_GEOMETRY_META, WindRuntime._mesh_geometry_snapshot(visual.mesh))
	check(packed.pack(model) == OK and ResourceSaver.save(packed, legacy_path) == OK, "完整快照对照实际写盘")
	for visual in visuals(model):
		visual.set_meta(WindRuntime.PREPARED_GEOMETRY_META, WindRuntime._geometry_digest(WindRuntime._mesh_geometry_snapshot(visual.mesh)))
	var compact_size := FileAccess.get_file_as_bytes(compact_path).size()
	var legacy_size := FileAccess.get_file_as_bytes(legacy_path).size()
	check(compact_bytes <= surfaces * 600 and compact_bytes * 10 < legacy_bytes, "摘要体积只随surface数增长，不随顶点数膨胀")
	check(compact_size > 0 and compact_size < legacy_size, "实际TSCN移除重复几何快照后缩小")
	diagnostics["wind_snapshot_size"] = {"surfaces": surfaces, "compact_metadata_bytes": compact_bytes, "legacy_metadata_bytes": legacy_bytes, "compact_tscn_bytes": compact_size, "legacy_tscn_bytes": legacy_size}
	artifacts.append(ProjectSettings.globalize_path(compact_path))
	artifacts.append(ProjectSettings.globalize_path(legacy_path))
	var visual := model.get_node("Trunk/MainTrunk") as MeshInstance3D
	var mesh := visual.mesh
	var baseline: Array = visual.get_meta(WindRuntime.PREPARED_GEOMETRY_META).duplicate(true)
	for field in ["vertices", "normals", "uv", "uv2", "indices"]:
		var snapshot := WindRuntime._mesh_geometry_snapshot(mesh)
		var tiny := snapshot.duplicate(true)
		if field == "indices":
			tiny[0][field][0] = tiny[0][field][1]
		elif field in ["uv", "uv2"]:
			tiny[0][field][0] += Vector2(0.00001, 0.0)
		else:
			tiny[0][field][0] += Vector3(0.00001, 0.0, 0.0)
		check(WindRuntime._geometry_digest(tiny) != baseline, "后续摘要无容差，微小同count变化也拒绝 " + field)
		var arrays := mesh.surface_get_arrays(0)
		var channel: int = {"vertices": Mesh.ARRAY_VERTEX, "normals": Mesh.ARRAY_NORMAL, "uv": Mesh.ARRAY_TEX_UV, "uv2": Mesh.ARRAY_TEX_UV2, "indices": Mesh.ARRAY_INDEX}[field]
		if field == "indices": arrays[channel][0] = arrays[channel][1]
		elif field in ["uv", "uv2"]: arrays[channel][0] += Vector2(0.02, 0.0)
		else: arrays[channel][0] += Vector3(0.02, 0.0, 0.0)
		var corrupt := ArrayMesh.new()
		corrupt.add_surface_from_arrays(mesh.surface_get_primitive_type(0), arrays)
		visual.mesh = corrupt
		check(corrupt.surface_get_array_index_len(0) == mesh.surface_get_array_index_len(0) and not WindRuntime._matches_prepared_snapshot(visual), "实际同面数网格篡改被摘要发现 " + field)
		WindRuntime.prepare(visual)
		check(visual.get_meta("plant_wind_prepare_rejected", "") == "prepared geometry changed" and visual.get_meta(WindRuntime.PREPARED_GEOMETRY_META) == baseline and visual.mesh == corrupt, "重复prepare拒绝篡改且不重设基线 " + field)
		visual.mesh = mesh
		visual.remove_meta("plant_wind_prepare_rejected")

func test_runtime() -> void:
	var recipe := curved_recipe()
	recipe.moss_enabled = true
	recipe.moss_amount = 0.08
	recipe.vine_enabled = true
	recipe.vine_count = 1
	recipe.grass_enabled = true
	recipe.grass_count = 1
	var built := Generator.build(recipe)
	check(built.ok, "运行时真实树生成", built.reason)
	if not built.ok: return
	check((WindRuntime as Script).is_tool(), "runtime支持编辑器显式采样，不生成placeholder")
	var tolerance_fixture: Array = [{"vertices": PackedVector3Array([Vector3.ZERO]), "normals": PackedVector3Array([Vector3.UP]), "uv": PackedVector2Array([Vector2.ZERO]), "uv2": PackedVector2Array([Vector2.ZERO]), "indices": PackedInt32Array([0, 1, 2])}]
	for field in WindRuntime.FIRST_PREPARE_GEOMETRY_TOLERANCE:
		var changed := tolerance_fixture.duplicate(true)
		if field == "indices": changed[0][field][0] = 1
		elif field in ["uv", "uv2"]: changed[0][field][0] += Vector2(0.0001, 0.0)
		else: changed[0][field][0] += Vector3(0.0002, 0.0, 0.0)
		check(WindRuntime._first_prepare_geometry_reason(tolerance_fixture, changed).is_empty() == (field == "normals"), "首次仅法线允许0.0002，其他字段零容差 " + field)
	var excessive := tolerance_fixture.duplicate(true)
	excessive[0].normals[0] += Vector3(0.000201, 0.0, 0.0)
	check(not WindRuntime._first_prepare_geometry_reason(tolerance_fixture, excessive).is_empty(), "首次法线超过0.0002必须拒绝")
	var snapshot_store := Store.new()
	var static_snapshot := snapshot_store._geometry_snapshot(built.root)
	var original_materials := materials_of(built.root)
	var prepared := WindRuntime.prepare(built.root)
	var wind_snapshot := snapshot_store._geometry_snapshot(built.root)
	diagnostics["wind_prepare_geometry"] = geometry_field_diagnostics(static_snapshot, wind_snapshot)
	check(snapshot_store._verify_wind_geometry(static_snapshot, wind_snapshot).is_empty(), "动态几何门禁允许唯一新增COLOR", snapshot_store._verify_wind_geometry(static_snapshot, wind_snapshot))
	var rejected_snapshot := wind_snapshot.duplicate(true)
	var rejected_surface: Dictionary = rejected_snapshot.nodes["Trunk/MainTrunk"].surfaces[0]
	rejected_surface.vertices[0] += Vector3(0.02, 0.0, 0.0)
	check(not WindRuntime._first_prepare_geometry_reason(static_snapshot.nodes["Trunk/MainTrunk"].surfaces, rejected_snapshot.nodes["Trunk/MainTrunk"].surfaces).is_empty(), "首次prepare拒绝超阈值同count顶点篡改")
	for field in ["vertices", "normals", "uv", "uv2", "indices"]:
		var corrupted := wind_snapshot.duplicate(true)
		var data: Dictionary = corrupted.nodes["Trunk/MainTrunk"].surfaces[0]
		if field == "indices":
			data[field][0] = data[field][1]
		elif field in ["uv", "uv2"]:
			data[field][0] += Vector2(0.02, 0.0)
		else:
			data[field][0] += Vector3(0.02, 0.0, 0.0)
		check(not snapshot_store._verify_wind_geometry(static_snapshot, corrupted).is_empty(), "动态门禁不能放宽同数量篡改 " + field)
	var prepared_geometry := geometry_data(built.root)
	check(not prepared.is_empty() and first_prepare_geometry_ok(static_snapshot, wind_snapshot), "prepare只增COLOR，不改顶点/索引/法线/UV/UV2", diagnostics["wind_prepare_geometry"])
	WindRuntime.apply_sample(prepared, 8.5, 0.6, Vector2(-3.0, 4.0))
	check_sample(built.root, 8.5, 0.6, Vector2(-0.6, 0.8), "准备后确定风采样")
	var untouched := true
	for material in original_materials:
		untouched = untouched and material.get_shader_parameter("preview_wind") == false and float(material.get_shader_parameter("local_time")) == 0.0
	check(untouched, "prepare与风采样不修改原始材质")
	audit_weights(built.root, recipe)
	var weighted_before := raw_colors(built.root)
	WindRuntime.prepare(built.root)
	check(raw_colors(built.root) == weighted_before and geometry_data(built.root) == prepared_geometry, "重复prepare保留真实COLOR且不改首次prepare快照")
	test_wind_digest(built.root)
	built.root.set_script(WindRuntime)
	var runtime: Node3D = built.root
	check(get_nodes_in_group(WindRuntime.OWNER_GROUP).is_empty(), "隔离工程无预存owner")
	root.add_child(runtime)
	runtime.set_process(false)
	runtime.call("sample_at", 3.0)
	runtime.call("_update_wind", 0.025)
	check_sample(runtime, 3.025, 1.1, Vector2(0.86, 0.5).normalized(), "无owner使用本地时钟与默认风")
	runtime.call("_update_wind", 0.7)
	check_sample(runtime, 3.125, 1.1, Vector2(0.86, 0.5).normalized(), "无owner增量限制0.1秒")
	var owner_fixture := ReadOnlyWindOwner.new()
	owner_fixture.name = "WorldWindOwner"
	root.add_child(owner_fixture)
	owner_fixture.add_to_group(WindRuntime.OWNER_GROUP)
	var writes := owner_fixture.writes
	var owner_state := [owner_fixture.elapsed, owner_fixture.strength, owner_fixture.direction, owner_fixture.get_groups()]
	runtime.call("_update_wind", 0.09)
	check_sample(runtime, 19.25, 0.73, Vector2(-0.6, 0.8), "World owner elapsed/strength/direction优先")
	check(owner_fixture.writes == writes and [owner_fixture.elapsed, owner_fixture.strength, owner_fixture.direction, owner_fixture.get_groups()] == owner_state, "owner三字段连同值回写也禁止")
	check(get_nodes_in_group(WindRuntime.OWNER_GROUP) == [owner_fixture] and runtime.get_groups().is_empty(), "runtime不抢注或增加owner")
	owner_fixture.elapsed = 27.0
	runtime.visible = false
	runtime.call("_process", 0.04)
	check_sample(runtime, 19.25, 0.73, Vector2(-0.6, 0.8), "隐藏runtime停止采样")
	runtime.visible = true
	var duplicate_owner := ReadOnlyWindOwner.new()
	root.add_child(duplicate_owner)
	duplicate_owner.add_to_group(WindRuntime.OWNER_GROUP)
	var duplicate_writes := duplicate_owner.writes
	var current_writes := owner_fixture.writes
	runtime.call("_update_wind", 0.01)
	check_sample(runtime, 19.26, 1.1, Vector2(0.86, 0.5).normalized(), "多个owner不任意挑选，使用本地fallback")
	check(duplicate_owner.writes == duplicate_writes and owner_fixture.writes == current_writes, "多owner fallback也不回写任何owner")
	duplicate_owner.free()
	runtime.call("sample_at", 19.25)
	owner_fixture.free()
	runtime.call("_update_wind", 0.05)
	check_sample(runtime, 19.3, 1.1, Vector2(0.86, 0.5).normalized(), "owner移除后连续本地fallback")
	for values in [[NAN, 1.0, Vector2.RIGHT], [1.0, INF, Vector2.RIGHT], [1.0, 1.0, Vector2(NAN, 0.0)]]:
		runtime.call("sample_at", values[0], values[1], values[2])
		check_sample(runtime, 19.3, 1.1, Vector2(0.86, 0.5).normalized(), "非有限风输入原子忽略")
	check(geometry_data(runtime) == prepared_geometry and raw_colors(runtime) == weighted_before, "所有风采样不改首次prepare快照/法线/UV/COLOR")
	runtime.free()
	completed_sections.append("runtime")

func test_store() -> void:
	var recipe := curved_recipe()
	recipe.name = "plant-integration"
	recipe.bark_detail = 0.03
	recipe.moss_enabled = true
	recipe.moss_amount = 0.04
	recipe.vine_enabled = true
	recipe.vine_count = 1
	var external := ProjectSettings.globalize_path("user://").trim_suffix("/") + "/plant_authoring_test_integration_%d" % Time.get_ticks_usec()
	var store := Store.new(external)
	artifacts.append(external)
	var first := store.save(recipe, external)
	diagnostics["static_save"] = first.duplicate(true)
	check(first.ok, "Store.save静态真实闭环必须成功", first.reason)
	var first_hashes: Dictionary = {}
	var static_data: Dictionary = {}
	if first.ok:
		first_hashes = bundle_hashes(first.directory)
		var packed := ResourceLoader.load(first.scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		check(packed != null, "静态最终路径可重载")
		if packed != null:
			var instance := packed.instantiate()
			audit_scripts(instance, false)
			static_data = geometry_data(instance)
			for material in materials_of(instance):
				check(material.get_shader_parameter("preview_wind") == false and float(material.get_shader_parameter("local_time")) == 0.0, "静态材质禁风且清零时钟")
			instance.free()
	var second := store.save_animated(recipe, external)
	diagnostics["animated_save"] = second.duplicate(true)
	check(second.ok, "Store.save_animated必须成功（不得接受失败reason替代旁车）", second.reason)
	if first.ok:
		check(bundle_hashes(first.directory) == first_hashes, "动态保存尝试不改旧静态revision任何字节")
	if second.ok:
		check(second.get("revision") == (2 if first.ok else 1) and second.get("static_scene_path") == second.scene_path and FileAccess.file_exists(second.get("animated_scene_path", "")), "动态新增revision并返回静态/动态两个路径", second)
		var second_hashes := bundle_hashes(second.directory)
		var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(second.manifest_path))
		check(manifest_value is Dictionary, "动态manifest真实JSON对象")
		if manifest_value is Dictionary:
			var manifest: Dictionary = manifest_value
			check(manifest.get("dynamic_scene") == true and manifest.get("static_scene") == true and manifest.get("animated_script_whitelist") == [Store.WIND_RUNTIME_PATH], "manifest静动态双产物及唯一脚本白名单")
			check(manifest.get("animated_scene_sha256") == FileAccess.get_sha256(second.animated_scene_path) and manifest.get("scene_sha256") == FileAccess.get_sha256(second.scene_path), "manifest对应最终静动态文件SHA256")
			check(manifest.get("recipe_fingerprint") == Recipe.fingerprint(recipe), "动态manifest配方指纹准确")
		var static_pack := ResourceLoader.load(second.scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		var dynamic_pack := ResourceLoader.load(second.animated_scene_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		check(static_pack != null and dynamic_pack != null, "动态bundle最终两个PackedScene重载")
		if static_pack != null and dynamic_pack != null:
			var static_instance := static_pack.instantiate()
			var a := dynamic_pack.instantiate()
			var b := dynamic_pack.instantiate()
			audit_scripts(static_instance, false)
			audit_scripts(a, true)
			audit_scripts(b, true)
			var current_static := geometry_data(static_instance)
			if not static_data.is_empty():
				check(store._equivalent(static_data, current_static), "save与save_animated静态几何法线UV相同")
			check(store._equivalent(current_static, geometry_data(a)) and store._equivalent(current_static, geometry_data(b)), "动态旁车逐节点几何/法线/UV/UV2与静态完全相符")
			audit_meshes(a, "动态重载")
			audit_weights(a, recipe)
			var baseline := geometry_data(a)
			var initial_a := materials_of(a)
			var initial_b := materials_of(b)
			var local_on_instantiate := not initial_a.is_empty() and initial_a.size() == initial_b.size()
			for material in initial_a:
				local_on_instantiate = local_on_instantiate and material.resource_local_to_scene and not initial_b.has(material)
			check(local_on_instantiate, "未调用runtime前PackedScene实例材质已独立")
			a.call("sample_at", 4.25, 0.31, Vector2.RIGHT)
			b.call("sample_at", 9.75, 1.4, Vector2.UP)
			check_sample(a, 4.25, 0.31, Vector2.RIGHT, "动态实例A")
			check_sample(b, 9.75, 1.4, Vector2.UP, "动态实例B")
			for instance in [a, b]:
				for visual in visuals(instance):
					check(WindRuntime._matches_prepared_snapshot(visual) and not visual.has_meta("plant_wind_prepare_rejected"), "动态旁车写盘重载后摘要仍精确匹配 " + str(visual.name))
			var a_materials := materials_of(a)
			var b_materials := materials_of(b)
			var independent := not a_materials.is_empty() and a_materials.size() == b_materials.size()
			for material in a_materials:
				independent = independent and not b_materials.has(material)
			check(independent, "同一PackedScene两个实例实际材质对象独立")
			check(geometry_data(a) == baseline and geometry_data(b) == baseline, "实例独立风采样不改几何法线UV")
			check(store._verify_wind_scripts(a, a).is_empty(), "动态白名单正例")
			var forbidden := ForbiddenScript.new()
			a.add_child(forbidden)
			check(not store._verify_wind_scripts(a, a).is_empty(), "动态白名单拒绝子节点脚本")
			forbidden.free()
			a.add_to_group(WindRuntime.OWNER_GROUP)
			check(not store._verify_wind_scripts(a, a).is_empty(), "动态白名单拒绝owner注册")
			a.remove_from_group(WindRuntime.OWNER_GROUP)
			static_instance.free()
			a.free()
			b.free()
		var third := store.save_animated(recipe, external)
		diagnostics["second_animated_save"] = third.duplicate(true)
		check(third.ok and third.get("revision") == int(second.revision) + 1 and third.get("directory") != second.directory, "重复动态保存只新增immutable版本", third.reason)
		check(bundle_hashes(second.directory) == second_hashes, "旧动态revision四文件逐字节immutable")
		if first.ok: check(bundle_hashes(first.directory) == first_hashes, "多次动态提交后旧静态revision仍immutable")
	var before_count := store.list_recipes(external).size()
	var invalid := recipe.duplicate(true)
	invalid.trunk_path[-1].y -= 0.5
	check(not store.save_animated(invalid, external).ok and store.list_recipes(external).size() == before_count, "非法动态保存原子拒绝且无新revision")
	var candidate_dir := external + "/plant-integration"
	var directory := DirAccess.open(candidate_dir)
	if directory != null:
		var no_temps := true
		for entry in directory.get_directories(): no_temps = no_temps and not entry.begins_with(".tmp_")
		check(no_temps, "保存失败不遗留本次临时目录")
	completed_sections.append("store")

func test_host_attachment() -> void:
	# UI代理并行落地此文件；动态加载避免整个测试因缺失preload而无法报告。
	var path := "res://src/plant_authoring/host_attachment.gd"
	check(FileAccess.file_exists(path), "宿主适配器已落地")
	if not FileAccess.file_exists(path):
		pending.append("host_attachment.gd 缺失，宿主专项未执行")
		return
	var adapter_script: Script = load(path)
	check(adapter_script != null and adapter_script.can_instantiate(), "宿主适配器可加载实例化")
	if adapter_script == null or not adapter_script.can_instantiate(): return
	var adapter: RefCounted = adapter_script.new()
	var host := Node3D.new()
	host.name = "ReadOnlyHost"
	host.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(11.0, 2.0, -7.0))
	# z=0侧墙的实际2米宽洞口，不依靠洞口metadata伪装空洞。
	add_host_box(host, "LeftWall", Vector3(4.0, 8.0, 0.2), Vector3(-3.0, 4.0, 0.0))
	add_host_box(host, "RightWall", Vector3(4.0, 8.0, 0.2), Vector3(3.0, 4.0, 0.0))
	host.set_meta("openings", [{"id": "window", "center": Vector3(0.0, 2.4, 0.0), "normal": Vector3.BACK, "height": 2.0, "width": 2.0, "wall_depth": 0.2}])
	var host_before := [host.transform, host.get_meta("openings").duplicate(true)]
	var metadata_before: Array = host.get_meta("openings").duplicate(true)
	var packed := PackedScene.new()
	check(packed.pack(host) == OK, "只读宿主fixture可打包")
	check(str(adapter_script.call("audit_scene", packed)).is_empty(), "独立无脚本PackedScene通过预实例化审计")
	var binding: Dictionary = adapter.call("bind_host", host)
	check(binding.get("ok", false) and binding.get("surface_count") == 2, "宿主收集真实墙面且抵消根世界变换", binding)
	var support_body := StaticBody3D.new()
	host.add_child(support_body)
	var support_collision := CollisionShape3D.new()
	support_collision.name = "SupportFloor"
	var support_shape := BoxShape3D.new()
	support_shape.size = Vector3(12.0, 0.2, 12.0)
	support_collision.shape = support_shape
	support_collision.position = Vector3(0.0, -0.1, 0.0)
	support_body.add_child(support_collision)
	check(bool(adapter.call("bind_host", host).get("ok", false)), "保留真实楼板重新绑定")
	var recipe := small_recipe()
	var before_recipe := recipe.duplicate(true)
	var proposal: Dictionary = adapter.call("propose_path", recipe, 0)
	check(proposal.get("ok", false), "洞口生成米制路径候选", proposal)
	check(recipe == before_recipe and [host.transform, host.get_meta("openings")] == host_before and host.get_meta("openings") == metadata_before, "候选生成不改宿主或输入配方")
	if proposal.get("ok", false):
		var candidate := recipe.duplicate(true)
		candidate.trunk_path = proposal.trunk_path
		check(Recipe.validate(candidate).is_empty(), "宿主候选仍遵守Recipe路径契约", Recipe.validate(candidate))
		var placement: Transform3D = proposal.plant_to_host
		var center: Dictionary = candidate.trunk_path[2]
		check((placement * Vector3(center.x, center.y, center.z)).distance_to(Vector3(0.0, 2.4, 0.0)) < 0.00001, "候选真实控制点穿过宿主局部洞口中心")
		var clear: Dictionary = adapter.call("check_clearance", candidate, placement)
		check(clear.get("ok", false), "真实空洞允许粗干穿过", clear)
		var glass := add_host_box(host, "WindowGlass", Vector3(2.0, 8.0, 0.04), Vector3(0.0, 4.0, 0.0))
		adapter.call("bind_host", host)
		var blocked: Dictionary = adapter.call("check_clearance", candidate, placement)
		check(not blocked.get("ok", true) and str(blocked.get("node", "")) == "WindowGlass" and str(blocked.get("reason", "")).contains("玻璃"), "洞口元数据不能绕过实际玻璃", blocked)
		glass.free()
		adapter.call("bind_host", host)
		check(bool(adapter.call("check_clearance", candidate, placement).get("ok", false)), "移除测试玻璃重新绑定后恢复真实间隙")
		check(recipe == before_recipe and [host.transform, host.get_meta("openings")] == host_before and host.get_meta("openings") == metadata_before, "间隙检测不自动削树或改宿主")
	var transform := Transform3D(Basis(Vector3.UP, 0.7), Vector3(2.0, 0.4, -3.0))
	var encoded: Array = adapter_script.call("encode_transform", transform)
	var decoded: Dictionary = adapter_script.call("decode_transform", encoded)
	check(decoded.get("ok", false) and decoded.get("transform") is Transform3D and decoded.transform.is_equal_approx(transform), "plant_to_host列主序刚体变换往返")
	for mode in ["NaN", "缩放", "镜像", "非仿射", "长度"]:
		var invalid := encoded.duplicate()
		match mode:
			"NaN": invalid[12] = NAN
			"缩放":
				for index in 3: invalid[index] *= 2.0
			"镜像":
				for index in 3: invalid[index] *= -1.0
			"非仿射": invalid[3] = 0.1
			"长度": invalid.pop_back()
		check(not bool(adapter_script.call("decode_transform", invalid).get("ok", true)), "宿主变换拒绝 " + mode)
	var scripted := ForbiddenScript.new()
	scripted.name = "ForbiddenChild"
	host.add_child(scripted)
	scripted.owner = host
	var unsafe_pack := PackedScene.new()
	check(unsafe_pack.pack(host) == OK, "含脚本负例fixture可打包")
	check(not str(adapter_script.call("audit_scene", unsafe_pack)).is_empty(), "预实例化审计拒绝子节点脚本")
	check(not bool(adapter.call("bind_host", host).get("ok", true)), "可信节点入口也拒绝宿主脚本")
	scripted.free()
	host.free()
	# 中心线距墙0.12m不相交，但0.27m粗干必须被拒绝。
	var near_host := Node3D.new()
	add_host_box(near_host, "NearWall", Vector3(0.04, 10.0, 4.0), Vector3(0.12, 4.0, 0.0))
	adapter.call("bind_host", near_host)
	var straight := small_recipe()
	straight.trunk_path = [{"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 0.0, "y": straight.height, "z": 0.0}]
	var thick: Dictionary = adapter.call("check_clearance", straight)
	check(not thick.get("ok", true) and thick.get("radius", 0.0) > 0.1, "粗干胶囊拒绝中心线未碰但半径擦墙", thick)
	near_host.free()
	# 真实楼板不同标高、平根端面、地下与首段侧墙；不得忽略首段或删除楼板。
	for floor_y in [0.0, 3.0, -2.0]:
		var floor_host := Node3D.new()
		var floor_mesh := add_host_box(floor_host, "Floor", Vector3(12.0, 0.2, 12.0), Vector3(0.0, floor_y - 0.1, 0.0))
		floor_host.set_meta("openings", [{"id": "supported", "center": Vector3(0.0, floor_y + 2.4, 0.0), "normal": Vector3.BACK, "height": 2.0}])
		check(bool(adapter.call("bind_host", floor_host).get("ok", false)), "楼板绑定 " + str(floor_y))
		var grounded: Dictionary = adapter.call("propose_path", straight, 0)
		check(grounded.get("ok", false), "实际楼板向下求交路径 " + str(floor_y), grounded)
		if grounded.get("ok", false):
			var placed: Transform3D = grounded.plant_to_host
			var supported := straight.duplicate(true)
			supported.trunk_path = grounded.trunk_path
			check(absf(placed.origin.y - floor_y - 0.002) < 0.00001, "根原点严格为实际板顶加2mm", placed.origin)
			check(bool(adapter.call("check_clearance", supported, placed).get("ok", false)), "保留楼板实际贴板弯干通过", adapter.call("check_clearance", supported, placed))
			var built := Generator.build(supported)
			check(built.ok, "支撑路径生成实际管网格", built.reason)
			if built.ok:
				var vertices: PackedVector3Array = built.root.get_node("Trunk/MainTrunk").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var minimum := INF
				for vertex in vertices: minimum = minf(minimum, (placed * vertex).y)
				check(absf(minimum - floor_y - 0.002) < 0.00001, "真实管最低点贴板且不穿板", minimum)
				built.root.free()
		var standing := Transform3D(Basis.IDENTITY, Vector3(0.0, floor_y + 0.002, 0.0))
		check(bool(adapter.call("check_clearance", straight, standing).get("ok", false)), "直干2mm贴板消除端球误报")
		var underground := standing
		underground.origin.y -= 0.05
		check(not bool(adapter.call("check_clearance", straight, underground).get("ok", true)), "地下根穿板仍拒绝")
		var tilted := standing
		tilted.basis = Basis(Vector3.FORWARD, 0.2)
		check(not bool(adapter.call("check_clearance", straight, tilted).get("ok", true)), "实际倾斜根环穿板仍拒绝")
		var slanted := straight.duplicate(true)
		slanted.trunk_path = [{"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 2.0, "y": 0.2, "z": 0.0}, {"x": 2.0, "y": slanted.height, "z": 0.0}]
		check(not bool(adapter.call("check_clearance", slanted, standing).get("ok", true)), "手动首段倾斜真实根截面穿板拒绝")
		var obstruction := add_host_box(floor_host, "RootSideWall", Vector3(0.04, 0.12, 1.0), Vector3(0.12, floor_y + 0.06, 0.0))
		adapter.call("bind_host", floor_host)
		var root_hit: Dictionary = adapter.call("check_clearance", straight, standing)
		check(not root_hit.get("ok", true) and root_hit.get("node") == "RootSideWall", "首段贴板不能豁免侧墙", root_hit)
		obstruction.free()
		# 同一表面记录中混有楼板和小墙也不能被整记录豁免。
		var combined := floor_mesh.mesh.get_faces()
		for index in combined.size(): combined[index] += floor_mesh.position
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(0.04, 0.12, 1.0)
		var wall_faces := wall_mesh.get_faces()
		for index in wall_faces.size(): wall_faces[index] += Vector3(0.12, floor_y + 0.06, 0.0)
		combined.append_array(wall_faces)
		floor_mesh.free()
		var body := StaticBody3D.new()
		floor_host.add_child(body)
		var collision := CollisionShape3D.new()
		collision.name = "FloorAndWall"
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(combined)
		collision.shape = concave
		body.add_child(collision)
		adapter.call("bind_host", floor_host)
		check(not bool(adapter.call("check_clearance", straight, standing).get("ok", true)), "同一concave楼板加侧墙仍拒绝首段穿墙")
		floor_host.free()
	# 四类实体必须保留局部shape和逆变换；表面远离整棵树也必须报inside。
	for shape: Shape3D in [BoxShape3D.new(), SphereShape3D.new(), CapsuleShape3D.new(), CylinderShape3D.new()]:
		if shape is BoxShape3D: shape.size = Vector3(30.0, 30.0, 30.0)
		else:
			shape.radius = 15.0
			if not shape is SphereShape3D: shape.height = 40.0
		var solid_host := Node3D.new()
		solid_host.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(-50.0, 10.0, 20.0))
		var body := StaticBody3D.new()
		body.transform = Transform3D(Basis(Vector3.FORWARD, 0.3).scaled(Vector3(1.5, 0.9, 1.2)), Vector3(20.0, 1.0, -8.0))
		solid_host.add_child(body)
		var collision := CollisionShape3D.new()
		collision.name = "EnclosingSolid"
		collision.shape = shape
		collision.position = Vector3(2.0, 0.0, 1.0)
		body.add_child(collision)
		check(bool(adapter.call("bind_host", solid_host).get("ok", false)), "带嵌套变换实体可绑定 " + shape.get_class())
		var inside_transform := Transform3D(Basis.IDENTITY, body.transform * collision.position)
		var contained: Dictionary = adapter.call("check_clearance", straight, inside_transform)
		check(not contained.get("ok", true) and contained.get("node") == "EnclosingSolid", "整棵树完全被实体包含仍拒绝 " + shape.get_class(), contained)
		inside_transform.origin += Vector3(100.0, 0.0, 0.0)
		check(bool(adapter.call("check_clearance", straight, inside_transform).get("ok", false)), "实体逆变换不误报外部树 " + shape.get_class())
		solid_host.free()
	var room := Node3D.new()
	var room_body := StaticBody3D.new()
	room.add_child(room_body)
	var room_collision := CollisionShape3D.new()
	var room_mesh := BoxMesh.new()
	room_mesh.size = Vector3(30.0, 30.0, 30.0)
	var room_shape := ConcavePolygonShape3D.new()
	room_shape.set_faces(room_mesh.get_faces())
	room_collision.shape = room_shape
	room_body.add_child(room_collision)
	adapter.call("bind_host", room)
	check(bool(adapter.call("check_clearance", straight).get("ok", false)), "闭合concave房屋仍是表面，不将房内树误判solid inside")
	room.free()
	var invalid_host := Node3D.new()
	var invalid_child := add_host_box(invalid_host, "InvalidChild", Vector3.ONE, Vector3.ZERO)
	invalid_child.top_level = true
	check(not bool(adapter.call("bind_host", invalid_host).get("ok", true)), "绑定拒绝子节点top_level")
	var top_pack := PackedScene.new()
	check(top_pack.pack(invalid_host) == OK and not str(adapter_script.call("audit_scene", top_pack)).is_empty(), "场景审计拒绝top_level")
	invalid_child.top_level = false
	invalid_host.top_level = true
	check(not bool(adapter.call("bind_host", invalid_host).get("ok", true)), "绑定拒绝根top_level")
	invalid_host.top_level = false
	for invalid_transform in [Transform3D(Basis.IDENTITY, Vector3(NAN, 0.0, 0.0)), Transform3D(Basis(Vector3.ZERO, Vector3.UP, Vector3.BACK), Vector3.ZERO)]:
		invalid_child.transform = invalid_transform
		check(not bool(adapter.call("bind_host", invalid_host).get("ok", true)), "绑定拒绝非法子变换")
		check(not bool(adapter.call("check_clearance", straight, invalid_transform).get("ok", true)), "检测拒绝非法相对变换")
	invalid_host.free()
	completed_sections.append("host-attachment")

func add_host_box(host: Node3D, label: String, size: Vector3, position: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = position
	host.add_child(visual)
	visual.owner = host
	return visual

func geometry_data(node: Node) -> Dictionary:
	var snapshot: Dictionary = Store.new()._geometry_snapshot(node).nodes
	# COLOR是动态产物唯一允许新增的顶点通道，另外由audit_weights逐点验证。
	for entry: Dictionary in snapshot.values():
		for surface: Dictionary in entry.get("surfaces", []):
			surface.erase("colors")
	return snapshot

func first_prepare_geometry_ok(before: Dictionary, after: Dictionary) -> bool:
	for path in before.nodes:
		if not after.nodes.has(path): return false
		var reason := WindRuntime._first_prepare_geometry_reason(before.nodes[path].get("surfaces", []), after.nodes[path].get("surfaces", []))
		if not reason.is_empty(): return false
	return true

func geometry_field_diagnostics(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for path in before.nodes:
		if not after.nodes.has(path):
			result[str(path)] = {"missing_after": true}
			continue
		var before_surfaces: Array = before.nodes[path].get("surfaces", [])
		var after_surfaces: Array = after.nodes[path].get("surfaces", [])
		var node_result: Array = []
		for surface_index in mini(before_surfaces.size(), after_surfaces.size()):
			var surface_result: Dictionary = {}
			for field in ["vertices", "normals", "uv", "uv2", "indices"]:
				var left: Variant = before_surfaces[surface_index].get(field, PackedFloat32Array())
				var right: Variant = after_surfaces[surface_index].get(field, PackedFloat32Array())
				var count := mini(left.size(), right.size()) if left is Array or left is PackedVector3Array or left is PackedVector2Array or left is PackedInt32Array or left is PackedFloat32Array else 0
				var maximum := 0.0
				var maximum_index := -1
				for index in count:
					var error := 0.0
					if field == "indices":
						error = absf(float(left[index]) - float(right[index]))
					elif field in ["vertices", "normals"]:
						error = left[index].distance_to(right[index])
					else:
						error = left[index].distance_to(right[index])
					if error > maximum:
						maximum = error
						maximum_index = index
				surface_result[field] = {"before_count": left.size(), "after_count": right.size(), "max_error": maximum, "max_index": maximum_index, "exact": left == right}
			if before_surfaces.size() != after_surfaces.size():
				surface_result["surface_count_mismatch"] = true
			node_result.append(surface_result)
		result[str(path)] = node_result
	return result

func visuals(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(visuals(child))
	return result

func materials_of(node: Node) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for visual in visuals(node):
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as ShaderMaterial
			if material != null: result.append(material)
	return result

func raw_colors(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for visual in visuals(node):
		var surfaces: Array = []
		for surface in visual.mesh.get_surface_count(): surfaces.append(visual.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR])
		# 该函数也用于未加入 SceneTree 的动态实例，不能调用 Node.get_path()。
		result[str(visual.get_instance_id())] = surfaces
	return result

func audit_scripts(node: Node, animated: bool) -> void:
	var store := Store.new()
	var snapshot := store._geometry_snapshot(node)
	check(snapshot.scripts == (1 if animated else 0) and snapshot.cameras == 0 and snapshot.lights == 0 and snapshot.collisions == 0, "导出节点脚本计数及无相机/灯/碰撞 " + str(animated), {"scripts": snapshot.scripts, "cameras": snapshot.cameras, "lights": snapshot.lights, "collisions": snapshot.collisions})
	if animated: check(store._verify_wind_scripts(node, node).is_empty(), "动态仅根WindRuntime脚本", store._verify_wind_scripts(node, node))

func check_sample(node: Node, seconds: float, strength: float, direction: Vector2, label: String) -> void:
	var materials := materials_of(node)
	var valid := not materials.is_empty()
	var observed: Array = []
	for material in materials:
		var time: Variant = material.get_shader_parameter("local_time")
		var power: Variant = material.get_shader_parameter("world_wind_strength")
		var heading: Variant = material.get_shader_parameter("world_wind_direction")
		observed.append([time, power, str(heading)])
		valid = valid and time != null and power != null and heading is Vector2
		if time != null and power != null and heading is Vector2:
			valid = valid and absf(float(time) - seconds) < 0.00001 and absf(float(power) - strength) < 0.00001 and heading.distance_to(direction) < 0.00001
		valid = valid and material.get_shader_parameter("preview_wind") == true and material.get_shader_parameter("wind_vertex_weights") == true
	check(valid, label + " 实际所有ShaderMaterial参数", observed if not valid else "")

func audit_weights(node: Node, recipe: Dictionary) -> void:
	var roles: Dictionary = {}
	var leaves_checked := 0
	for visual in visuals(node):
		for surface in visual.mesh.get_surface_count():
			var arrays := visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var value: Variant = arrays[Mesh.ARRAY_COLOR]
			var material := visual.get_active_material(surface) as ShaderMaterial
			check(value is PackedColorArray and value.size() == vertices.size(), "真实COLOR长度匹配 " + str(visual.name))
			if not (value is PackedColorArray) or value.size() != vertices.size() or material == null: continue
			var colors: PackedColorArray = value
			var role := material.resource_name
			roles[role] = true
			var finite := true
			var moving := false
			var fixed := true
			for color in colors:
				finite = finite and is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a) and color.r >= 0.0 and color.r <= 1.0
				moving = moving or color.r > 0.05
				fixed = fixed and color == Color(0.0, 0.0, 0.0, 1.0)
			check(finite, "风COLOR有限且权重有界 " + str(visual.name))
			if role in ["Plant_trunk", "Plant_moss"]:
				check(fixed, "木质根/干/枝/树皮与苔藓逐点固定 " + str(visual.name))
			elif role == "Plant_vine":
				var attached_fixed := true
				for side in 5:
					attached_fixed = attached_fixed and is_zero_approx(colors[side * 4].r) and is_zero_approx(colors[side * 4 + 1].r)
				check(attached_fixed and moving, "藤首环固定而悬垂端实际有风权重")
			elif role == "Plant_leaf" and visual.name == "Foliage":
				var count := Recipe.leaves_per_twig(recipe) * int(recipe.subtwig_count)
				check(vertices.size() % count == 0, "叶片等长块可独立定位")
				var stride := int(vertices.size() / count)
				var roots_fixed := stride > 40
				var root_hits := 0
				for leaf in count:
					var first := leaf * stride
					for index in range(first, first + 40): roots_fixed = roots_fixed and is_zero_approx(colors[index].r)
					var center := vertices[first + 28]
					var tip_moves := false
					for index in range(first + 40, first + stride):
						# 实体叶根上下表面离叶柄中心有 thickness*0.06 的厚度偏移。
						if center.distance_to(vertices[index]) <= float(recipe.leaf_size) * 1.14 * 0.09 * 0.06 + 0.00001:
							root_hits += 1
							roots_fixed = roots_fixed and is_zero_approx(colors[index].r)
						tip_moves = tip_moves or colors[index].r > 0.05
					roots_fixed = roots_fixed and tip_moves
				leaves_checked += count
				check(roots_fixed and root_hits >= count and moving, "每片叶实际叶柄及连接根固定、叶尖非零风权重", {"node": str(visual.name), "root_hits": root_hits, "leaves": count})
			elif visual.name == "GroundCover":
				var ground_fixed := true
				var ground_hits := 0
				for index in vertices.size():
					if vertices[index].y <= 0.00001:
						ground_hits += 1
						ground_fixed = ground_fixed and is_zero_approx(colors[index].r)
				check(ground_fixed and ground_hits > 0 and moving, "草根实际COLOR固定而草尖可动")
	check(leaves_checked > 0 and roles.has("Plant_trunk") and roles.has("Plant_leaf") and roles.has("Plant_moss") and roles.has("Plant_vine"), "权重检查覆盖非空树及全部四角色", roles.keys())

func audit_meshes(node: Node, label: String) -> void:
	var valid := true
	var uv_valid := true
	var triangles := 0
	for visual in visuals(node):
		for surface in visual.mesh.get_surface_count():
			var arrays := visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			valid = valid and not vertices.is_empty() and vertices.size() == normals.size() and indices.size() % 3 == 0
			uv_valid = uv_valid and uv.size() == vertices.size()
			if normals.size() != vertices.size() or uv.size() != vertices.size() or indices.size() % 3 != 0: continue
			for index in vertices.size():
				valid = valid and vertices[index].is_finite() and normals[index].is_finite() and absf(normals[index].length() - 1.0) < 0.002
			for face in range(0, indices.size(), 3):
				var a := indices[face]
				var b := indices[face + 1]
				var c := indices[face + 2]
				if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size():
					valid = false
					continue
				triangles += 1
				valid = valid and (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() > 1.0e-22
				uv_valid = uv_valid and absf((uv[b] - uv[a]).cross(uv[c] - uv[a])) > 1.0e-14
				var cell := Vector2i(floori(uv[a].x * 8.0), floori(uv[a].y * 8.0))
				for index in [a, b, c]:
					var pixel := uv[index] * 512.0 - Vector2(cell) * 64.0
					uv_valid = uv_valid and uv[index].is_finite() and cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 8 and pixel.x >= 7.999 and pixel.x <= 56.001 and pixel.y >= 7.999 and pixel.y <= 56.001
	check(valid and triangles > 0, label + " 实际非退化三角形/有限顶点/单位法线", triangles)
	check(uv_valid, label + " 实际UV非退化、逐面单格8px安全边距")

func check_uv_cell(node: MeshInstance3D, expected: int) -> void:
	var valid := true
	var count := 0
	for surface in node.mesh.get_surface_count():
		var uvs: PackedVector2Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
		for uv in uvs:
			count += 1
			valid = valid and floori(uv.y * 8.0) * 8 + floori(uv.x * 8.0) == expected
	check(valid and count > 0, "选择色格实际命中全部UV " + str(node.name), expected)

func ring_center(vertices: PackedVector3Array, ring: int, rings: int, sides: int) -> Vector3:
	var result := Vector3.ZERO
	var row := mini(ring, rings - 2)
	var offset := 0 if ring < rings - 1 else 3
	for side in sides:
		result += vertices[row * sides * 4 + side * 4 + offset]
	return result / float(sides)

func point_at_height(points: Array[Vector3], height: float) -> Vector3:
	for index in range(1, points.size()):
		if height <= points[index].y:
			var a := points[index - 1]
			var b := points[index]
			return a.lerp(b, (height - a.y) / (b.y - a.y))
	return points[-1]

func legacy_auto_points(recipe: Dictionary) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(int(recipe.seed)) + ":trunk/shape").sha256_text().substr(0, 15).hex_to_int()
	var phase := lerpf(PI, rng.randf_range(0.0, TAU), float(recipe.variation) if recipe.random_enabled else 0.0)
	var points: Array[Vector3] = []
	for index in 17:
		var t := float(index) / 16.0
		var curve := float(recipe.trunk_curve) * sin(t * PI * 0.9) * (0.30 if recipe.species == "birch" else 1.0)
		points.append(Vector3(curve * sin(t * 2.2 + phase), float(recipe.height) * t, curve * cos(t * 1.7 + phase)))
	return points

func triangle_count(node: Node) -> int:
	var count := 0
	for visual in visuals(node):
		for surface in visual.mesh.get_surface_count():
			var indices: PackedInt32Array = visual.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			count += int(indices.size() / 3)
	return count

func check_attached_patches(node: Node, path: String, lift: float) -> void:
	var trunk := node.get_node("Trunk/MainTrunk") as MeshInstance3D
	var patch := node.get_node_or_null(path) as MeshInstance3D
	check(patch != null, "附生有真实网格 " + path)
	if patch == null: return
	var faces := trunk.mesh.get_faces()
	var arrays := patch.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var attached := not vertices.is_empty() and normals.size() == vertices.size()
	var worst := 0.0
	if normals.size() == vertices.size():
		for index in vertices.size():
			var distance := nearest_face_distance(vertices[index] - normals[index] * lift, faces)
			worst = maxf(worst, distance)
			attached = attached and distance < 0.00001
	check(attached, "附生逐顶点减去法线外偏后命中真实树皮 " + path, worst)

func nearest_face_distance(point: Vector3, faces: PackedVector3Array) -> float:
	var distance := INF
	for index in range(0, faces.size(), 3):
		distance = minf(distance, triangle_distance(point, faces[index], faces[index + 1], faces[index + 2]))
		if distance < 0.000001: break
	return distance

func triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b - a).cross(c - a).normalized()
	var projected := point - normal * normal.dot(point - a)
	var inside := true
	for edge in [[a, b], [b, c], [c, a]]:
		inside = inside and (edge[1] - edge[0]).cross(projected - edge[0]).dot(normal) >= -0.0000001
	if inside: return absf(normal.dot(point - a))
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))

func bundle_hashes(directory: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(directory)
	check(dir != null, "revision目录存在 " + directory)
	if dir == null: return result
	for name in dir.get_files():
		var digest := FileAccess.get_sha256(directory + "/" + name)
		check(digest.length() == 64, "revision文件可哈希 " + name)
		result[name] = digest
	check(result.size() >= 3, "revision至少三个非空产物")
	return result

func remember(result: Dictionary) -> void:
	if result.get("ok", false) and is_instance_valid(result.get("root")) and not session_roots.has(result.root):
		session_roots.append(result.root)
