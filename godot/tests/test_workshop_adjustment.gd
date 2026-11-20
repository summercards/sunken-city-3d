extends SceneTree
const Recipe = preload("res://src/workshop/recipe.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const Adjustment = preload("res://src/workshop/generation_adjustment.gd")
const Store = preload("res://src/workshop/store.gd")
const Session = preload("res://src/workshop/session.gd")
const Union = preload("res://src/workshop/shell_union_geometry.gd")
var geometry_cases: Array = []
# 只读 git show ae1d431:recipe.gd 与同HEAD standards_v1 推导；不从待测defaults动态取期望。
const LEGACY_FINGERPRINT := "9a8ec9180485004da0a6b9767a787cb326c11233c2992ad24cc848227259d6cb"
var checks := 0
var failures: Array[String] = []
var catalog: Dictionary

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		failures.append(label + ": " + str(detail))
		printerr("FAIL [workshop-adjustment] ", label, " ", detail)

func fixture() -> Dictionary:
	var r: Dictionary = Recipe.authoring_defaults()
	r.architecture.form.enabled = false
	r.taper = 0.0
	r.floors = 1
	return r

func run() -> void:
	catalog = Catalog.definitions()
	geometry_regressions()
	if OS.get_environment("SEA_ADJUSTMENT_GEOMETRY_ONLY") == "1":
		finish_report()
		return
	check(Recipe.fingerprint(Recipe.defaults()) == LEGACY_FINGERPRINT, "HEAD旧defaults指纹保持", Recipe.fingerprint(Recipe.defaults()))
	var legacy: Dictionary = Recipe.defaults()
	var legacy_result: Dictionary = checked(legacy, "有效旧配方零修改", catalog)
	check(legacy_result.ok and legacy_result.changes.is_empty() and legacy_result.candidate == legacy, "旧配方不迁移不改指纹", legacy_result.reason)
	var defaults: Dictionary = Recipe.authoring_defaults()
	check(defaults.floor_height == 5.1 and defaults.slab_thickness == 0.2 and is_equal_approx(defaults.floor_height - defaults.slab_thickness, 4.9), "正式阳光房层高板厚净高参考")
	check(defaults.window_width == 1.5 and defaults.window_height == 1.9 and defaults.door_width == 1.6 and defaults.door_height == 2.4, "不把原型外包尺寸迁为净洞")
	check(defaults.column_width == 0.5 and defaults.architecture.pilaster.width == 0.5, "主柱与贴墙柱仅参考粗细")
	check(defaults.aging == 0.0 and defaults.damage == 0.0 and defaults.vegetation_density == 0.0 and defaults.architecture.shading.materials.is_empty(), "clean且继承公共四材质")
	for slot: String in ["wall", "pillar", "band", "slab", "roof", "frame", "glass"]:
		var expected: Array = [0, 4] if slot in ["wall", "pillar", "band"] else ([1, 1] if slot in ["slab", "roof"] else ([2, 3] if slot == "frame" else [2, 1]))
		check(defaults.architecture.palette.slots[slot] == {"color_mode": "manual", "color_cell": expected}, "正式参考手动色格 " + slot)
	var valid: Dictionary = checked(defaults, "新建原始默认完整生成", catalog)
	check(valid.ok and valid.changes.is_empty() and valid.candidate == defaults, "有效候选零修改", valid.reason)
	var r: Dictionary = fixture()
	r.floor_height = 2.5
	r.architecture.window["height"] = 3.0
	r.window_height = 3.0
	r.architecture.window.frame_depth = 0.04
	r.architecture.window.glass_thickness = 0.08
	var linked: Dictionary = success(r, "层高与玻璃框深互依", [["architecture", "window", "frame_depth"], ["floor_height"]])
	if linked.ok:
		check(linked.candidate.window_height == 3.0 and linked.candidate.architecture.window.height == 3.0, "互依修复不缩净窗")
		check(is_equal_approx(linked.candidate.architecture.window.frame_depth, 0.084), "固定玻璃优先增框深4mm装配缝")
		roundtrip(linked.candidate)
	for scope: String in ["floor_windows", "facade_windows", "window_overrides"]:
		r = fixture()
		var key: String = "0" if scope == "floor_windows" else ("back" if scope == "facade_windows" else "opening_back_0_0")
		r.architecture[scope][key] = {"type": "fixed", "open_angle": 30.0}
		success(r, scope + "真实owner固定角", [["architecture", scope, key, "open_angle"]])
	for scope: String in ["floor_windows", "facade_windows", "window_overrides"]:
		r = fixture()
		var key: String = "0" if scope == "floor_windows" else ("back" if scope == "facade_windows" else "opening_back_0_0")
		r.architecture.window.frame_depth = 0.04
		r.architecture[scope][key] = {"glass_thickness": 0.1}
		success(r, scope + "冲突同层承载框深", [["architecture", scope, key, "frame_depth"]])
	r = fixture()
	r.architecture.floor_windows = {"0": {"type": "casement_left", "open_angle": 20.0}}
	r.architecture.window_overrides = {"opening_back_0_0": {"type": "fixed"}}
	success(r, "继承开角与单窗固定窗冲突真实owner", [["architecture", "window_overrides", "opening_back_0_0", "open_angle"]])
	r = fixture()
	r.architecture.window.type = "casement_left"
	r.architecture.window.open_angle = 0.0
	r.architecture.window.frame_depth = 0.04
	r.architecture.window.glass_thickness = 0.08
	var moving: Dictionary = success(r, "活动窗8mm装配缝", [["architecture", "window", "frame_depth"]])
	if moving.ok: check(moving.candidate.architecture.window.frame_depth >= 0.088 and moving.candidate.architecture.window.frame_depth <= 0.089 + 0.000001, "活动窗不缩玻璃")
	r = fixture()
	r.architecture.window.recess = 0.5
	success(r, "实际recess区间", [["architecture", "window", "recess"]])
	r = fixture()
	r.architecture.window.sill_thickness = 0.5
	r.architecture.window["sill"] = 0.4
	r.window_sill = 0.4
	var sill: Dictionary = success(r, "窗沿窗台与alias", [["architecture", "window", "sill"], ["window_sill"]])
	if sill.ok: check(sill.parameter_count == 1 and sill.changes[1].kind == "alias", "镜像同步明确列出不冒充独立参数")
	r = fixture()
	r.floors = 2
	r.floor_overrides = {"0": {"floor_height": 2.5}, "1": {"slab_thickness": 0.4}}
	success(r, "实际楼层owner和下一层板厚", [["floor_overrides", "0", "floor_height"]])
	r = fixture()
	r.floors = 2
	r.architecture.window_overrides = {"opening_back_1_0": {"height": 4.5}}
	var single: Dictionary = success(r, "单窗仅增加对应楼层承载", [["floor_overrides", "1", "floor_height"]])
	if single.ok: check(single.candidate.architecture.window_overrides == r.architecture.window_overrides and single.candidate.floor_height == r.floor_height, "单窗不清覆盖不改全局层高")
	r = fixture()
	r.window_width = 3.75
	r.architecture.window["width"] = 3.75
	var wide: Dictionary = success(r, "大净窗优先增加实际开间", [["bay_width"]])
	if wide.ok: check(wide.candidate.window_width == 3.75 and wide.candidate.architecture.window.width == 3.75, "开间修复绝不偷偷缩窗")
	r = fixture()
	r.slab_thickness = 0.02
	success(r, "板厚合法域及倒角关系", [["slab_thickness"], ["bevel_width"]])
	r = fixture()
	r.wall_thickness = 0.9
	success(r, "墙厚合法域", [["wall_thickness"], ["bay_width"]])
	r = fixture()
	r.floor_height = 3.0
	r.door_height = 3.3
	success(r, "净门高优先增加层高", [["floor_height"]])
	r = fixture()
	r.door_height = 5.0
	success(r, "高门层高修复通过真实union不再误拒绝", [["floor_height"]])
	r = fixture()
	r.window_width = 2.0
	r.architecture.window["width"] = 2.0
	r.architecture.pilaster.width = 0.9
	success(r, "柱框确定开间解", [["bay_width"]])
	r = fixture()
	r.schema_version = 2
	rejected(r, catalog, "未来配方拒绝")
	r = fixture()
	r.component_bindings.wall = "future_unknown"
	rejected(r, catalog, "未知绑定拒绝")
	var bad_catalog: Dictionary = catalog.duplicate(true)
	bad_catalog.components.wall_sun.profile = "future_unknown"
	rejected(fixture(), bad_catalog, "未知catalog拒绝")
	rejected(fixture(), {}, "空catalog不能偷偷回退")
	r = fixture()
	r.architecture.plan = {"wing_x": "bad"}
	rejected(r, catalog, "非法非数值配置拒绝无运行时异常")
	r = fixture()
	r.architecture.plan["setback_start"] = 0
	var setback_zero: Dictionary = success(r, "退台起始层0只建议关闭退台", [["architecture", "plan", "setback_start"]])
	if setback_zero.ok:
		check(setback_zero.candidate.architecture.plan.setback_start == -1, "退台0修复为显式关闭而非静默改层")
	r = fixture()
	r.architecture.window.type = "future_window"
	rejected(r, catalog, "未知窗型拒绝")
	r = fixture()
	r.architecture.window.frame_depth = "bad"
	rejected(r, catalog, "数值类型错误拒绝")
	r = fixture()
	r.window_width = 6.0
	r.architecture.window["width"] = 6.0
	r.width = 6.0
	r.architecture.pilaster.width = 0.9
	rejected(r, catalog, "无保窗安全开间方案拒绝")
	r = fixture()
	r.floor_height = 1.0
	r.wall_thickness = 2.0
	r.slab_thickness = 2.0
	r.architecture.window.open_angle = 40.0
	rejected(r, catalog, "超过三个参数明确拒绝")
	r = Recipe.authoring_defaults()
	r.architecture.window.open_angle = 20.0
	var derived: Dictionary = success(r, "派生收分透明列出", [["architecture", "window", "open_angle"], ["taper"]])
	if derived.ok:
		check(derived.parameter_count == 1 and derived.changes[1].kind == "derived", "派生值不伪装独立参数或隐藏")
		var repeated: Dictionary = checked(r, "确定性重复提议", catalog)
		check(repeated == derived, "同配方同目录建议确定性")
	r = fixture()
	r.architecture.window_overrides = {"opening_back_0_0": {"width": 3.75}}
	rejected(r, catalog, "开间改变单窗ID拓扑时保守拒绝")
	r = fixture()
	r.architecture.facade_windows = {"back": {"enabled": false, "frame_depth": 0.04, "glass_thickness": 0.1}}
	r.architecture.window.open_angle = 20.0
	success(r, "封墙窗口不修无效装配关系", [["architecture", "window", "open_angle"]])
	r = fixture()
	r.slot_overrides = {"wall_shell_0": {"disabled": true}}
	rejected(r, catalog, "禁止关闭结构绕过生成")
	r = fixture()
	r.architecture.roof.edge_overrides = {"edge_0": {"gap_width": 100.0}}
	rejected(r, catalog, "未知拓扑冲突完整生成拒绝")
	finish_report()

func finish_report() -> void:
	var report := {"checks": checks, "failures": failures, "geometry_cases": geometry_cases, "legacy_fingerprint": LEGACY_FINGERPRINT, "visual": "未执行，仅实际几何与静态保存重载", "expected_failures": "无；负例为预期拒绝断言"}
	var file := FileAccess.open("res://outputs/workshop_adjustment_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[workshop-adjustment] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func geometry_regressions() -> void:
	for floors: int in [1, 2, 3]:
		for form: bool in [false, true]:
			var r: Dictionary = Recipe.authoring_defaults()
			r.floors = floors
			r.architecture.form.enabled = form
			if not form: r.taper = 0.0
			actual_geometry(r, "原始默认_%d层_form_%s" % [floors, form])
	for pillar: bool in [false, true]:
		for band: bool in [false, true]:
			var r: Dictionary = Recipe.authoring_defaults()
			r.floors = 2
			r.architecture.form.enabled = false
			r.taper = 0.0
			r.vegetation_density = 0.15
			r.architecture.window.sill_enabled = false
			r.architecture.pilaster.enabled = pillar
			r.architecture.band.enabled = band
			actual_geometry(r, "两层palette植被窗沿关闭_柱%s_腰线%s" % [pillar, band])
			var large: Dictionary = r.duplicate(true)
			large.merge({"width": 12.0, "depth": 12.0, "bay_width": 6.0, "floor_height": 6.8, "vegetation_density": 0.0}, true)
			large.architecture.window.merge({"width": 3.75, "height": 4.75, "frame_width": 0.275, "frame_depth": 0.30, "glass_thickness": 0.05, "sill_enabled": true, "sill_projection": 0.45, "sill_thickness": 0.25, "sill_extension": 0.20}, true)
			actual_geometry(large, "两层6.8大窗_柱%s_腰线%s" % [pillar, band])
	var l_five: Dictionary = Recipe.authoring_defaults()
	l_five.merge({"shape": "l", "depth": 12.0, "floors": 5, "taper": 0.02}, true)
	l_five.architecture.form.enabled = false
	actual_geometry(l_five, "L形五层原shell真实回归")
	var repair: Dictionary = fixture()
	repair.floors = 2
	var session = Session.new()
	var accepted: Dictionary = session.new_document("two_floor_repair", repair)
	check(accepted.ok and session.snapshot().floors == 2, "实际Session接受原两层repair_fixture", accepted.get("reason", ""))
	repair.floor_height = 2.5
	repair.bay_width = 2.8
	repair.architecture.window.merge({"height": 3.0, "glass_thickness": 0.1, "frame_depth": 0.04}, true)
	success(repair, "UI两层repair联合候选实际修复", [["architecture", "window", "frame_depth"], ["floor_height"], ["bay_width"]])
	var palette: Dictionary = fixture()
	palette.floors = 2
	palette.architecture.palette = {}
	palette.architecture.window.sill_enabled = false
	palette.vegetation_density = 0.15
	actual_geometry(palette, "新scale两层空palette角色继承植被窗沿关闭")
	roundtrip(palette)
	if OS.get_environment("SEA_ADJUSTMENT_DIAGNOSE") == "1":
		for values: Array in [[5.1, 0.2, 0.36], [5.1, 0.18, 0.5], [3.6, 0.2, 0.5], [5.0, 0.2, 0.5], [5.2, 0.2, 0.5]]:
			var r: Dictionary = fixture()
			r.floors = 2
			r.floor_height = values[0]
			r.slab_thickness = values[1]
			r.architecture.pilaster.width = values[2]
			actual_geometry(r, "单因素诊断_" + str(values))

func actual_geometry(r: Dictionary, label: String) -> void:
	var built: Dictionary = Generator.build(r, catalog)
	var record := {"name": label, "ok": bool(built.ok), "reason": str(built.reason)}
	geometry_cases.append(record)
	check(built.ok, label + "完整实际生成", built.reason)
	if not built.ok: return
	var mesh: Mesh = built.root.get_node("GeneratedVisual/structure_union").mesh
	var audit: Dictionary = Union.audit_faces(mesh.get_faces())
	var boundary: Dictionary = built.quality.structure_union.boundary_audit
	record["audit"] = audit
	record["boundary_audit"] = boundary
	check(audit.valid and audit.closed and audit.oriented and audit.components == 1 and audit.nonmanifold_edges == 0, label + "实际单连通闭合定向无非流形", audit)
	check(boundary.valid and boundary.errors == 0, label + "严格实体边界内实外空", boundary)
	built.root.free()

func checked(r: Dictionary, label: String, c: Dictionary) -> Dictionary:
	var before: String = JSON.stringify(r)
	var catalog_before: String = JSON.stringify(c)
	var result: Dictionary = Adjustment.propose(r, c)
	check(JSON.stringify(r) == before and JSON.stringify(c) == catalog_before, label + "原文与目录逐字不变")
	check(result.has_all(["ok", "reason", "candidate", "changes", "original_reason"]), label + "稳定接口")
	return result

func success(r: Dictionary, label: String, expected: Array) -> Dictionary:
	var result: Dictionary = checked(r, label, catalog)
	check(result.ok and not result.changes.is_empty(), label + "可确认建议", result.reason)
	if not result.ok: return result
	check(result.parameter_count <= 3 and result.changes.size() <= 6, label + "仅几个参数")
	var replay: Dictionary = r.duplicate(true)
	var paths: Array = []
	for change: Dictionary in result.changes:
		check(change.has_all(["path", "label", "before", "after", "unit", "reason", "kind"]) and change.path is Array[String], label + "明确真实diff接口")
		check(Adjustment._read_path(r, change.path) == change.before and Adjustment._read_path(result.candidate, change.path) == change.after, label + "旧到新准确")
		paths.append(change.path)
		var target: Dictionary = replay
		for i: int in change.path.size() - 1:
			if not target.has(change.path[i]): target[change.path[i]] = {}
			target = target[change.path[i]]
		target[change.path[-1]] = change.after
	check(paths == expected, label + "最少真实字段及scope", paths)
	check(replay == result.candidate, label + "除列出字段外全部原样")
	check(Recipe.validate(result.candidate, catalog).is_empty(), label + "完整配方校验")
	var built: Dictionary = Generator.build(result.candidate, catalog)
	check(built.ok, label + "完整实际建模", built.reason)
	if is_instance_valid(built.get("root")): built.root.free()
	return result

func rejected(r: Dictionary, c: Dictionary, label: String) -> void:
	var result: Dictionary = checked(r, label, c)
	check(not result.ok and not str(result.reason).is_empty() and result.changes.is_empty() and result.candidate == r, label + "原子拒绝", result.reason)

func roundtrip(r: Dictionary) -> void:
	var store = Store.new()
	var saved: Dictionary = store.export_revision(r, catalog)
	check(saved.ok, "确认候选五件静态保存", saved.reason)
	if not saved.ok: return
	var loaded: Dictionary = store.load_recipe(saved.recipe_path)
	check(loaded.ok and Recipe.fingerprint(loaded.recipe) == Recipe.fingerprint(saved.recipe), "配方保存重载指纹", loaded.reason)
	check(loaded.catalog == catalog, "目录快照重载保持")
	var packed: PackedScene = load(saved.scene_path) as PackedScene
	check(packed != null, "静态TSCN可重载")
	if packed != null:
		var instance: Node = packed.instantiate()
		check(instance.get_script() == null and instance.has_node("GeneratedVisual/structure_union"), "静态实体无重建脚本")
		instance.free()
