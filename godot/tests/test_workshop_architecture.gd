@tool
extends SceneTree
## 架构增量专项QA；只读实际生成root、Mesh和ConcavePolygonShape3D，不读取quality代替几何证据。

const Recipe = preload("res://src/workshop/recipe.gd")
const Config = preload("res://src/workshop/architecture_config.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const Generator = preload("res://src/workshop/generator.gd")
const ShellGenerator = preload("res://src/workshop/shell_generator.gd")
const ShellGeometry = preload("res://src/workshop/shell_geometry.gd")
const Session = preload("res://src/workshop/session.gd")
const Store = preload("res://src/workshop/store.gd")

const REPORT_PATH: String = "res://outputs/workshop_architecture_report.json"
const WELD: float = 0.00001
const EPS: float = 0.0001
const SAMPLE_PATHS: Array[String] = [
	"res://data/workshop/samples/workshop_sample_001.recipe.json",
	"res://data/workshop/samples/workshop_sample_002.recipe.json"
]

var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {
	"suite": "workshop-architecture",
	"fixtures": {},
	"invalid_cases": {},
	"legacy_samples": {},
	"store": {},
	"visual_acceptance": "未执行；本专项只报告实际mesh/root与实际凹碰撞"
}

func _init() -> void:
	call_deferred("run")

func check(value: bool, meaning: String, detail: String = "") -> void:
	checks += 1
	if not value:
		var message: String = meaning + ("：" + detail if not detail.is_empty() else "")
		failures.append(message)
		printerr("FAIL [workshop-architecture] ", message)

func run() -> void:
	var catalog: Dictionary = Catalog.definitions()
	check(not catalog.is_empty() and Catalog.validate(catalog).is_empty(), "组件目录有效")
	_test_recipe_compatibility(catalog)
	_test_config_precedence()
	_test_legacy_samples(catalog)
	_test_noarchitecture_shell_equivalence(catalog)

	var base: Dictionary = _recipe("architecture_rectangle", "rectangle", 12.0, 9.0, 3)
	_test_fixture("rectangle_default_arch_none", base, catalog)
	_test_shape("l_12x12_f2_wing_42_58", base, catalog, "l", 12.0, 12.0, 2, Vector2(0.42, 0.58), Vector2(3.0, 3.0))
	_test_shape("t_12x12_f2_wing_42_58", base, catalog, "t", 12.0, 12.0, 2, Vector2(0.42, 0.58), Vector2(4.0, 3.0))
	_test_shape("u_15x12_f3_wing_42_58", base, catalog, "u", 15.0, 12.0, 3, Vector2(0.42, 0.58), Vector2(0.0, 3.0))
	_test_setback(base, catalog)
	_test_mixed_roof(base, catalog)
	_test_windows(base, catalog)
	_test_window_mesh_contract(catalog)
	_test_invalid_cases(base, catalog)
	_test_session_atomic(base, catalog)
	_test_store(base, catalog)
	_test_form(base, catalog)
	_test_frame(base, catalog)
	await process_frame
	_finish()

func _recipe(building_id: String, shape: String, width: float, depth: float, floors: int) -> Dictionary:
	var recipe: Dictionary = Recipe.authoring_defaults()
	recipe["building_id"] = building_id
	recipe["shape"] = shape
	recipe["width"] = width
	recipe["depth"] = depth
	recipe["floors"] = floors
	recipe["taper"] = 0.0
	recipe["vegetation_density"] = 0.0
	recipe["damage"] = 0.0
	# 形体开启后 taper 是派生值；本文件的正交基线必须显式关掉，否则 taper=0 会被区间落值覆盖。
	recipe["architecture"]["form"]["enabled"] = false
	return recipe

func _test_recipe_compatibility(catalog: Dictionary) -> void:
	var defaults: Dictionary = Recipe.defaults()
	var default_fingerprint: String = Recipe.fingerprint(defaults)
	check(not defaults.has("architecture"), "Recipe.defaults不注入architecture")
	check(Recipe.fingerprint(Recipe.normalized(defaults)) == default_fingerprint, "Recipe.defaults fingerprint不因架构默认值变化")
	check(Recipe.validate(defaults, catalog).is_empty(), "旧Recipe.defaults仍可验证")
	var authoring: Dictionary = Recipe.authoring_defaults()
	var authoring_architecture: Dictionary = authoring.get("architecture", {}) as Dictionary
	check(authoring.has("architecture") and Config.validate(authoring_architecture, int(authoring.floors)).is_empty(), "authoring_defaults具有有效architecture增量", str(authoring_architecture))
	check(bool((authoring_architecture.get("window", {}) as Dictionary).get("sill_enabled", false)) and str((authoring_architecture.get("roof", {}) as Dictionary).get("mode", "")) == "parapet", "authoring默认含窗台板与女儿墙")
	check(str(authoring.get("construction_mode", "")) == "shell_v2", "authoring_defaults使用shell_v2")

func _test_config_precedence() -> void:
	var recipe: Dictionary = _recipe("config_precedence", "rectangle", 12.0, 9.0, 3)
	var architecture: Dictionary = Config.defaults()
	architecture["window"] = {"type": "awning", "open_angle": 25.0, "frame_depth": 0.16}
	architecture["floor_windows"] = {"1": {"height": 1.7, "sill": 1.1}}
	architecture["facade_windows"] = {"front": {"type": "casement_left", "open_angle": 35.0, "width": 1.25}}
	architecture["window_overrides"] = {"opening_front_0_2": {"enabled": false, "height": 1.55}}
	recipe["architecture"] = architecture
	var settings: Dictionary = Config.window_settings(recipe, 0, "front", "opening_front_0_2")
	check(str(settings.get("type", "")) == "casement_left", "Config.window_settings按global到floor到facade到single覆盖type")
	check(float(settings.get("open_angle", -1.0)) == 35.0, "Config.window_settings保留facade open_angle覆盖")
	check(float(settings.get("frame_depth", -1.0)) == 0.16, "Config.window_settings保留global frame_depth")
	check(float(settings.get("height", -1.0)) == 1.55 and not bool(settings.get("enabled", true)), "Config.window_settings最后应用single覆盖")
	var floor_settings: Dictionary = Config.window_settings(recipe, 1, "front", "opening_front_1_0")
	check(float(floor_settings.get("height", -1.0)) == 1.7 and float(floor_settings.get("sill", -1.0)) == 1.1, "Config.window_settings楼层覆盖位于立面覆盖之前")
	check(str(Config.window_settings(recipe, 0, "back", "opening_back_0_0").get("type", "")) == "awning", "Config.window_settings未命中立面时使用global")

func _test_noarchitecture_shell_equivalence(catalog: Dictionary) -> void:
	var authoring: Dictionary = _recipe("noarchitecture_shell", "rectangle", 12.0, 9.0, 3)
	var without_architecture: Dictionary = authoring.duplicate(true)
	without_architecture.erase("architecture")
	var explicit_none: Dictionary = authoring.duplicate(true)
	explicit_none["architecture"] = Config.defaults()
	var implicit: Dictionary = _adopt_build_root(Generator.build(without_architecture, catalog))
	var explicit: Dictionary = _adopt_build_root(Generator.build(explicit_none, catalog))
	var implicit_root: Node3D = implicit.get("root") as Node3D
	var explicit_root: Node3D = explicit.get("root") as Node3D
	check(bool(implicit.get("ok", false)) and bool(explicit.get("ok", false)) and implicit_root != null and explicit_root != null, "无architecture与显式none shell均生成", str(implicit.get("reason", explicit.get("reason", ""))))
	if implicit_root != null and explicit_root != null:
		check(_structural_signature(implicit_root, implicit.get("semantic_sources", {})) == _structural_signature(explicit_root, explicit.get("semantic_sources", {})), "无architecture shell结构geometry与显式none保持一致")
		check(_parts_have_no_architecture_accessory(_inventory(implicit_root, implicit.get("semantic_sources", {})).parts), "无architecture shell不生成新窗扇/窗沿/屋顶附件")
	_free_build_root(implicit)
	_free_build_root(explicit)

func _parts_have_no_architecture_accessory(parts: Dictionary) -> bool:
	for id: String in parts:
		if id.begins_with("sash_") or id.begins_with("sill_") or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_"):
			return false
	return true

func _floor_base(recipe: Dictionary, floor: int) -> float:
	var base: float = 0.0
	for index: int in floor:
		var override: Dictionary = recipe.get("floor_overrides", {}).get(str(index), {})
		base += float(override.get("floor_height", recipe.get("floor_height", 0.0)))
	return base

func _test_legacy_samples(catalog: Dictionary) -> void:
	var defaults: Dictionary = Recipe.defaults()
	for path: String in SAMPLE_PATHS:
		var source_hash: String = FileAccess.get_sha256(path)
		var sample: Dictionary = _read_json(path)
		check(not sample.is_empty(), "旧sample可读取", path)
		if sample.is_empty():
			continue
		check(not sample.has("architecture"), "旧sample没有被写入architecture", path)
		var implicit: Dictionary = _adopt_build_root(Generator.build(sample, catalog))
		var explicit_recipe: Dictionary = sample.duplicate(true)
		explicit_recipe["construction_mode"] = "modular_v1"
		var explicit: Dictionary = _adopt_build_root(Generator.build(explicit_recipe, catalog))
		var implicit_root: Node3D = implicit.get("root") as Node3D
		var explicit_root: Node3D = explicit.get("root") as Node3D
		check(bool(implicit.get("ok", false)) and bool(explicit.get("ok", false)) and implicit_root != null and explicit_root != null, "旧sample隐式/显式legacy均可生成", path)
		if implicit_root != null and explicit_root != null:
			check(_root_signature(implicit_root) == _root_signature(explicit_root), "旧sample隐式/显式legacy实际mesh不变", path)
			check(JSON.stringify(implicit.get("slots", [])) == JSON.stringify(explicit.get("slots", [])), "旧sample隐式/显式legacy槽位不变", path)
			check(str(implicit_root.get_meta("generator_version", "")) == Generator.GENERATOR_VERSION, "旧sample仍由legacy generator生成", path)
		_free_build_root(implicit)
		_free_build_root(explicit)
		check(FileAccess.get_sha256(path) == source_hash, "旧sample文件未改写", path)
	check(not defaults.has("architecture"), "legacy兼容检查结束后defaults仍无architecture")

func _test_fixture(label: String, recipe: Dictionary, catalog: Dictionary) -> Dictionary:
	var result: Dictionary = _adopt_build_root(Generator.build(recipe, catalog))
	var root: Node3D = result.get("root") as Node3D
	check(bool(result.get("ok", false)) and root != null, label + "生成实际root", str(result.get("reason", "")))
	if root == null:
		report.fixtures[label] = {"ok": false, "reason": str(result.get("reason", ""))}
		return result
	var inventory: Dictionary = _inventory(root, result.get("semantic_sources", {}))
	var topology: Dictionary = _audit_parts(inventory.parts)
	var actual_collisions: bool = _collision_matches_visual(inventory)
	check(str(root.get_meta("generator_version", "")) == ShellGenerator.GENERATOR_VERSION, label + " root metadata为当前shell生成器")
	check(str(root.get_meta("construction_mode", "")) == "shell_v2", label + " root metadata construction_mode正确")
	check(root.transform.is_equal_approx(Transform3D.IDENTITY), label + " root变换恒等")
	check(int(inventory.visual_meshes) > 0 and int(inventory.triangles) > 0, label + "实际Mesh存在面")
	check(_all_parts_closed_oriented(topology), label + "所有实际新part闭合定向且nonmanifold为0", str(topology.get("bad_parts", {})))
	check(actual_collisions, label + "实际Concave碰撞与结构视觉part一一对应")
	check(int(inventory.invalid_collision_shapes) == 0, label + "实际碰撞全部是ConcavePolygonShape3D")
	report.fixtures[label] = {
		"ok": true,
		"visual_meshes": inventory.visual_meshes,
		"triangles": inventory.triangles,
		"collision_shapes": inventory.collision_shapes,
		"parts": _sorted_strings(inventory.parts.keys()),
		"topology": topology,
		"visible_topology": _audit_parts(inventory.visible_parts),
		"source_audit": "独立semantic_sources实际网格；最终可见网格另列visible_topology",
		"root_metadata": {
			"generator_version": root.get_meta("generator_version", ""),
			"construction_mode": root.get_meta("construction_mode", ""),
			"recipe_fingerprint": root.get_meta("recipe_fingerprint", "")
		}
	}
	return result

func _test_shape(label: String, base: Dictionary, catalog: Dictionary, shape: String, width: float, depth: float, floors: int, wing: Vector2, void_point: Vector2) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = label
	recipe["shape"] = shape
	recipe["width"] = width
	recipe["depth"] = depth
	recipe["floors"] = floors
	recipe["architecture"]["plan"]["wing_x"] = wing.x
	recipe["architecture"]["plan"]["wing_z"] = wing.y
	var result: Dictionary = _test_fixture(label, recipe, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root, result.get("semantic_sources", {}))
	var height: float = _height(recipe)
	var void_hits: int = _ray_hits(_all_faces(inventory.parts), Vector3(void_point.x, height + 2.0, void_point.y), Vector3(void_point.x, -1.0, void_point.y))
	check(void_hits == 0, label + " roof top ray不封L/T/U内部void", str(void_hits))
	report.fixtures[label]["void_top_ray_hits"] = void_hits
	_free_build_root(result)

func _test_setback(base: Dictionary, catalog: Dictionary) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = "rectangle_setback_f3_start2_step035"
	recipe["architecture"]["plan"]["setback_start"] = 2
	recipe["architecture"]["plan"]["setback_step"] = 0.35
	var result: Dictionary = _test_fixture("rectangle_setback_f3_start2_step035", recipe, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root, result.get("semantic_sources", {}))
	var wall_1: AABB = _bounds(inventory.parts.get("wall_shell_1", PackedVector3Array()))
	var wall_2: AABB = _bounds(inventory.parts.get("wall_shell_2", PackedVector3Array()))
	check(wall_2.size.x < wall_1.size.x - EPS and wall_2.size.z < wall_1.size.z - EPS, "setback floor2实际wall_shell bounds变窄")
	check(_has_roof_surface(result.get("roof_surfaces", []), "terrace_floor_2"), "setback实际roof_surfaces保留terrace_floor_2 top")
	var slab_2: PackedVector3Array = inventory.parts.get("slab_2", PackedVector3Array())
	var floor_2_top: float = _floor_base(recipe, 2)
	var slab_top_hits: int = _ray_hits(slab_2, Vector3(0.0, floor_2_top + 1.0, 0.0), Vector3(0.0, floor_2_top - 1.0, 0.0))
	check(slab_top_hits > 0, "setback slab2实际mesh存在terrace top")
	var no_setback: Dictionary = base.duplicate(true)
	no_setback["building_id"] = "rectangle_no_setback_roof_edges"
	no_setback["architecture"]["roof"]["mode"] = "parapet"
	var no_setback_result: Dictionary = _adopt_build_root(Generator.build(no_setback, catalog))
	var no_setback_root: Node3D = no_setback_result.get("root") as Node3D
	check(no_setback_root != null and bool(no_setback_result.get("ok", false)), "无退台屋顶边界fixture生成", str(no_setback_result.get("reason", "")))
	if no_setback_root != null:
		var no_setback_parts: Dictionary = _inventory(no_setback_root, no_setback_result.get("semantic_sources", {})).parts
		check(not _has_id_containing(no_setback_parts, "terrace_floor_0"), "无退台时slab0没有roof edge part")
	_free_build_root(no_setback_result)
	report.fixtures["rectangle_setback_f3_start2_step035"]["wall_shell_1_bounds"] = _aabb_json(wall_1)
	report.fixtures["rectangle_setback_f3_start2_step035"]["wall_shell_2_bounds"] = _aabb_json(wall_2)
	report.fixtures["rectangle_setback_f3_start2_step035"]["slab2_top_ray_hits"] = slab_top_hits
	_free_build_root(result)

func _test_mixed_roof(base: Dictionary, catalog: Dictionary) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = "rectangle_roof_mixed"
	recipe["architecture"]["roof"]["mode"] = "mixed"
	var result: Dictionary = _test_fixture("rectangle_roof_mixed", recipe, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root, result.get("semantic_sources", {}))
	check(_has_id_prefix(inventory.parts, "parapet_"), "roof_main mixed实际存在parapet part")
	check(_has_id_prefix(inventory.parts, "roofcap_"), "roof_main mixed实际存在roofcap part")
	check(_has_id_prefix(inventory.parts, "railing_"), "roof_main mixed实际存在railing part")
	check(_collision_matches_visual(inventory), "roof_main mixed每个附属结构均有实际Concave碰撞")
	var gap_recipe: Dictionary = recipe.duplicate(true)
	gap_recipe["building_id"] = "rectangle_roof_mixed_edge_gap"
	gap_recipe["architecture"]["roof"]["edge_overrides"] = {"edge_0": {"gap_center": 0.5, "gap_width": 2.0}}
	var gap_result: Dictionary = _adopt_build_root(Generator.build(gap_recipe, catalog))
	var gap_root: Node3D = gap_result.get("root") as Node3D
	check(gap_root != null and bool(gap_result.get("ok", false)), "roof edge gap fixture生成", str(gap_result.get("reason", "")))
	if gap_root != null:
		var gap_inventory: Dictionary = _inventory(gap_root, gap_result.get("semantic_sources", {}))
		var fragments: Array[String] = []
		for id: String in gap_inventory.parts:
			if id.begins_with("parapet_roof_main_0_") or id.begins_with("roofcap_roof_main_0_") or id.begins_with("railing_roof_main_0_"):
				fragments.append(id)
		check(fragments.size() >= 6, "roof edge gap实际生成两端fragment并保持三类边件")
		var gap_point: Vector2 = Vector2(0.0, -float(gap_recipe["depth"]) * 0.5 - 0.14)
		var end_point: Vector2 = Vector2(-float(gap_recipe["width"]) * 0.25, -float(gap_recipe["depth"]) * 0.5 - 0.14)
		var gap_ray: int = _ray_hits(_all_faces(gap_inventory.parts), Vector3(gap_point.x, _height(gap_recipe) + 0.25, gap_point.y - 1.0), Vector3(gap_point.x, _height(gap_recipe) + 0.25, gap_point.y + 1.0))
		var end_ray: int = _ray_hits(_all_faces(gap_inventory.parts), Vector3(end_point.x, _height(gap_recipe) + 0.25, end_point.y - 1.0), Vector3(end_point.x, _height(gap_recipe) + 0.25, end_point.y + 1.0))
		check(gap_ray == 0 and end_ray > 0, "roof edge gap中段无barrier且fragment端部闭合")
		report.fixtures["rectangle_roof_mixed"]["edge_gap"] = {"fragment_parts": fragments, "gap_ray_hits": gap_ray, "end_ray_hits": end_ray}
	_free_build_root(gap_result)
	report.fixtures["rectangle_roof_mixed"]["roof_parts"] = _filter_roof_parts(inventory.parts)
	_free_build_root(result)

func _test_windows(base: Dictionary, catalog: Dictionary) -> void:
	var windows: Dictionary = base.duplicate(true)
	windows["building_id"] = "windows_fixed_casement_awning_sill"
	windows["architecture"]["window"] = {
		"type": "fixed", "open_angle": 0.0, "sill_enabled": true,
		"sill_projection": 0.2, "sill_thickness": 0.1, "sill_extension": 0.08
	}
	windows["architecture"]["facade_windows"] = {
		"left": {"type": "casement_left", "open_angle": 35.0},
		"right": {"type": "awning", "open_angle": 25.0}
	}
	var result: Dictionary = _test_fixture("windows_fixed_casement_awning_sill", windows, catalog)
	var root: Node3D = result.get("root") as Node3D
	if root == null:
		return
	var inventory: Dictionary = _inventory(root, result.get("semantic_sources", {}))
	var fixed_ok: bool = false
	var casement_ok: bool = false
	var awning_ok: bool = false
	var sill_ok: bool = false
	for opening: Dictionary in result.get("openings", []):
		if str(opening.get("type", "")) != "window":
			continue
		var opening_id: String = str(opening.get("id", ""))
		var suffix: String = opening_id.trim_prefix("opening_")
		var settings: Dictionary = opening.get("settings", {})
		var frame_id := "frame_" + suffix
		var glass_id := "glass_" + suffix
		fixed_ok = fixed_ok or (str(settings.get("type", "")) == "fixed" and inventory.parts.has(frame_id) and inventory.parts.has(glass_id))
		casement_ok = casement_ok or (str(settings.get("type", "")) == "casement_left" and float(settings.get("open_angle", -1.0)) == 35.0 and inventory.parts.has("sash_" + suffix))
		awning_ok = awning_ok or (str(settings.get("type", "")) == "awning" and float(settings.get("open_angle", -1.0)) == 25.0 and inventory.parts.has("sash_" + suffix))
		sill_ok = sill_ok or (bool(settings.get("sill_enabled", false)) and inventory.parts.has("sill_" + suffix))	
	check(fixed_ok, "fixed窗实际frame与glass存在")
	check(casement_ok, "casement_left 35度实际sash存在")
	check(awning_ok, "awning 25度实际sash存在")
	check(sill_ok, "固定窗实际sill存在")
	_free_build_root(result)

	var disabled: Dictionary = windows.duplicate(true)
	disabled["building_id"] = "windows_single_disabled"
	disabled["architecture"]["window_overrides"] = {"opening_front_0_2": {"enabled": false}}
	var disabled_result: Dictionary = _adopt_build_root(Generator.build(disabled, catalog))
	var disabled_root: Node3D = disabled_result.get("root") as Node3D
	check(disabled_root != null and bool(disabled_result.get("ok", false)), "单窗enabled=false生成", str(disabled_result.get("reason", "")))
	if disabled_root != null:
		var disabled_inventory: Dictionary = _inventory(disabled_root, disabled_result.get("semantic_sources", {}))
		var disabled_suffix := "front_0_2"
		check(not disabled_inventory.parts.has("glass_" + disabled_suffix) and not disabled_inventory.parts.has("frame_" + disabled_suffix) and not disabled_inventory.parts.has("sash_" + disabled_suffix) and not disabled_inventory.parts.has("sill_" + disabled_suffix), "enabled=false移除实际glass/frame/sash/sill")
		var disabled_wall: PackedVector3Array = disabled_inventory.parts.get("wall_shell_0", PackedVector3Array())
		var disabled_target: Dictionary = {}
		for opening: Dictionary in result.get("openings", []):
			if str(opening.get("id", "")) == "opening_front_0_2":
				disabled_target = opening
				break
		var target_center: Vector3 = disabled_target.get("center", Vector3(1.5, 1.9, -4.5))
		var target_outward: Vector3 = disabled_target.get("outward", Vector3(0.0, 0.0, -1.0))
		var hit: int = _ray_hits(disabled_wall, target_center + target_outward, target_center - target_outward)
		check(hit > 0, "enabled=false洞口位置实际wall ray命中")
		var enabled_ids: Array[String] = _window_ids(result.get("openings", []))
		var disabled_ids: Array[String] = _window_ids(disabled_result.get("openings", []))
		check(not disabled_ids.has("opening_front_0_2"), "enabled=false不伪造已禁用opening记录")
		for id: String in enabled_ids:
			if id != "opening_front_0_2":
				check(disabled_ids.has(id), "enabled=false保持其他window ordinal identity", id)
		report.fixtures["windows_single_disabled"] = {"ok": true, "disabled_part_ids": ["frame_front_0_2", "glass_front_0_2", "sash_front_0_2", "sill_front_0_2"], "window_ids": disabled_ids, "disabled_wall_ray_hits": hit}
	_free_build_root(disabled_result)

	var changed: Dictionary = windows.duplicate(true)
	changed["building_id"] = "windows_depth_glass_sill_dimensions"
	changed["architecture"]["window"]["frame_depth"] = 0.18
	changed["architecture"]["window"]["glass_thickness"] = 0.03
	changed["architecture"]["window"]["sill_projection"] = 0.2
	var baseline_result: Dictionary = _adopt_build_root(Generator.build(windows, catalog))
	var changed_result: Dictionary = _adopt_build_root(Generator.build(changed, catalog))
	var baseline_root: Node3D = baseline_result.get("root") as Node3D
	var changed_root: Node3D = changed_result.get("root") as Node3D
	check(baseline_root != null and changed_root != null and bool(baseline_result.get("ok", false)) and bool(changed_result.get("ok", false)), "窗frame_depth/glass/sill尺寸对照均生成")
	if baseline_root != null and changed_root != null:
		var before_inventory: Dictionary = _inventory(baseline_root, baseline_result.get("semantic_sources", {}))
		var after_inventory: Dictionary = _inventory(changed_root, changed_result.get("semantic_sources", {}))
		var suffix: String = _first_window_suffix(baseline_result.get("openings", []), "fixed")
		var frame_changed: bool = _bounds_changed(before_inventory.parts.get("frame_" + suffix, PackedVector3Array()), after_inventory.parts.get("frame_" + suffix, PackedVector3Array()))
		var glass_changed: bool = _bounds_changed(before_inventory.parts.get("glass_" + suffix, PackedVector3Array()), after_inventory.parts.get("glass_" + suffix, PackedVector3Array()))
		check(frame_changed and glass_changed, "frame_depth .18与glass_thickness .03改变实际AABB")
		check(after_inventory.parts.has("sill_" + suffix), "sill_projection .2生成实际sill part")
	_free_build_root(baseline_result)
	_free_build_root(changed_result)

## 每个快照只取实际Mesh数据；hash不包含配方、type或metadata。
func _window_mesh_snapshot(recipe: Dictionary, catalog: Dictionary) -> Dictionary:
	var built: Dictionary = Generator.build(recipe, catalog)
	var root: Node3D = built.get("root") as Node3D
	check(bool(built.get("ok", false)) and root != null, "窗核心对照生成实际root", str(built.get("reason", "")))
	var snapshot: Dictionary = {"parts": {}, "opening": {}}
	if root == null: return snapshot
	for opening: Dictionary in built.get("openings", []):
		if str(opening.id) == "opening_front_0_0": snapshot.opening = opening.duplicate(true)
	var sources: Dictionary = built.get("semantic_sources", {})
	for prefix: String in ["frame_", "glass_", "sash_", "sill_"]:
		var id: String = prefix + "front_0_0"
		var mesh: Mesh
		var transform := Transform3D.IDENTITY
		if sources.has(id):
			var source: Dictionary = sources[id]
			check(source.mesh_records.size() == 1, "窗核心源部件必须只有一个实际Mesh", id)
			if source.mesh_records.size() != 1: continue
			mesh = source.mesh_records[0].mesh
			transform = Transform3D(Basis.IDENTITY, source.position) * source.mesh_records[0].transform
		else:
			var node := root.get_node_or_null("GeneratedVisual/" + id) as MeshInstance3D
			if node == null: continue
			mesh = node.mesh
			transform = _relative(node, root)
		check(mesh != null and not mesh.get_faces().is_empty(), "窗核心Mesh.get_faces非空", id)
		if mesh == null or mesh.get_faces().is_empty(): continue
		var faces: PackedVector3Array = _transformed(mesh.get_faces(), transform)
		var arrays: Array = mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var local_bounds: AABB = mesh.get_aabb()
		var face_bounds: AABB = _bounds(mesh.get_faces())
		# Godot的get_faces经过TriangleMesh焊接量化，surface原顶点与AABB不量化；仍使用既有0.1mm门限。
		check(local_bounds.position.distance_to(face_bounds.position) < EPS and local_bounds.end.distance_to(face_bounds.end) < EPS, "窗核心Mesh.get_aabb与实际faces一致", id)
		var raw_faces := PackedVector3Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index: int in arrays[Mesh.ARRAY_INDEX]: raw_faces.append(transform * vertices[index])
		check(_faces_match_points(faces, raw_faces) and _faces_match_points(raw_faces, faces), "窗核心get_faces与surface原顶点量化误差小于0.1mm", id)
		check(_all_parts_closed_oriented(_audit_parts({id: faces})), "窗核心实际Mesh严格闭合定向", id)
		var uv_safe: bool = uv.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for point: Vector2 in uv: uv_safe = uv_safe and point.is_finite() and point.x > 0.0 and point.x < 1.0 and point.y > 0.0 and point.y < 1.0
		check(uv_safe, "窗核心UV数量匹配且有限安全", id)
		snapshot.parts[prefix.trim_suffix("_")] = {
			"faces": faces, "raw_faces": raw_faces, "bounds": _bounds(faces), "mesh_aabb": _aabb_json(local_bounds),
			"geometry_hash": var_to_bytes(faces).hex_encode().sha256_text(),
			"uv_hash": var_to_bytes(uv).hex_encode().sha256_text(), "uv_count": uv.size()
		}
	check(not snapshot.opening.is_empty(), "窗核心对照洞口身份存在")
	_free_build_root(built)
	return snapshot

func _window_mesh_evidence(snapshot: Dictionary) -> Dictionary:
	var evidence: Dictionary = {}
	for id: String in snapshot.parts:
		var part: Dictionary = snapshot.parts[id]
		evidence[id] = {"geometry_hash": part.geometry_hash, "uv_hash": part.uv_hash, "uv_count": part.uv_count, "world_aabb": _aabb_json(part.bounds), "mesh_aabb": part.mesh_aabb}
	return evidence

func _faces_match_points(actual: PackedVector3Array, expected: PackedVector3Array) -> bool:
	if actual.is_empty() or expected.is_empty(): return false
	for point: Vector3 in actual:
		var found: bool = false
		for other: Vector3 in expected:
			if point.distance_to(other) <= EPS:
				found = true
				break
		if not found: return false
	return true

func _test_window_mesh_contract(catalog: Dictionary) -> void:
	var recipe: Dictionary = _recipe("window_mesh_contract", "rectangle", 12.0, 9.0, 1)
	recipe.architecture = Config.defaults()
	recipe.architecture.window.sill_enabled = true
	var baseline: Dictionary = _window_mesh_snapshot(recipe, catalog)
	if not baseline.parts.has("glass") or not baseline.parts.has("frame"): return
	var evidence: Dictionary = {"fixed_baseline": _window_mesh_evidence(baseline), "fixed_parameters": {}, "types": {}, "rejections": {}}
	report["window_mesh_contract"] = evidence
	var frame_bounds: AABB = baseline.parts.frame.bounds
	var glass_bounds: AABB = baseline.parts.glass.bounds
	check(absf(frame_bounds.size.z - 0.12) < EPS and absf(frame_bounds.get_center().z - (-4.5 + 0.15)) < EPS, "fixed框深与recess实际为配置值")
	check(absf(glass_bounds.size.z - 0.02) < EPS and absf(glass_bounds.get_center().z - (-4.5 + 0.15)) < EPS, "fixed玻璃实际厚度与框中心吻合")
	for spec: Array in [["frame_width", 0.20, "frame"], ["frame_depth", 0.24, "frame"], ["recess", 0.20, "glass"], ["glass_thickness", 0.06, "glass"], ["sill_projection", 0.40, "sill"]]:
		var changed: Dictionary = recipe.duplicate(true)
		changed.architecture.window[spec[0]] = spec[1]
		var snapshot: Dictionary = _window_mesh_snapshot(changed, catalog)
		var id: String = str(spec[2])
		check(snapshot.parts.has(id), "fixed单参数目标Mesh存在：" + str(spec[0]))
		if not snapshot.parts.has(id): continue
		var before: Dictionary = baseline.parts[id]
		var after: Dictionary = snapshot.parts[id]
		check(before.geometry_hash != after.geometry_hash and _bounds_changed(before.faces, after.faces), "fixed单参数改变真实Mesh.get_faces与世界AABB：" + str(spec[0]))
		var box: AABB = after.bounds
		match str(spec[0]):
			"frame_width": check(absf(box.size.x - (float(recipe.window_width) + 0.40)) < EPS and absf(box.size.y - (float(recipe.window_height) + 0.40)) < EPS, "fixed frame_width精确改变框外廓而不缩净孔")
			"frame_depth":
				check(absf(box.size.z - 0.24) < EPS, "fixed frame_depth实际框厚精确生效")
				check(snapshot.parts.glass.geometry_hash == baseline.parts.glass.geometry_hash, "fixed框深不应伪造玻璃厚度或改变框中心")
			"recess":
				check(absf(box.get_center().z - (-4.5 + 0.20)) < EPS, "fixed recess实际移动玻璃中心")
				check(snapshot.parts.frame.geometry_hash != baseline.parts.frame.geometry_hash and absf((snapshot.parts.frame.bounds as AABB).get_center().z - box.get_center().z) < EPS, "fixed recess同时移动框与玻璃")
			"glass_thickness": check(absf(box.size.z - 0.06) < EPS, "fixed玻璃不再固定20mm")
			"sill_projection": check(absf(box.position.z - (-4.5 - 0.40)) < EPS, "fixed sill_projection精确改变实体外挑")
		check(before.uv_hash == after.uv_hash, "fixed几何参数不改写PaletteUV色格：" + str(spec[0]))
		evidence.fixed_parameters[str(spec[0])] = {"value": spec[1], "parts": _window_mesh_evidence(snapshot), "uv_changed": before.uv_hash != after.uv_hash}
	# 旧入口也必须消费settings，而不是另留一份20mm/墙厚中心实现。
	var settings: Dictionary = Config.window_settings(recipe, 0, "front")
	settings.glass_thickness = 0.06
	settings.recess = 0.20
	var hole: Dictionary = ShellGeometry._opening(0.0, -0.0008, 1.5, settings, false)
	hole.settings = settings
	var run: Dictionary = {"start": Vector2(-6.0, -4.5), "axis": Vector2.RIGHT, "outward": Vector2(0.0, -1.0), "depth": 0.3}
	var buffer: Dictionary = ShellGeometry._buffer()
	ShellGeometry._glass(buffer, hole, run)
	var direct_bounds: AABB = _bounds(buffer.v)
	check(absf(direct_bounds.size.z - 0.06) < EPS and absf(direct_bounds.get_center().z - (-4.5 + 0.20)) < EPS, "统一玻璃旧入口同样使用settings厚度与recess")
	var hashes: Dictionary = {baseline.parts.glass.geometry_hash: true}
	for type: String in ["casement_left", "casement_right", "awning"]:
		var closed_recipe: Dictionary = recipe.duplicate(true)
		closed_recipe.architecture.window.type = type
		var closed: Dictionary = _window_mesh_snapshot(closed_recipe, catalog)
		var opened_recipe: Dictionary = closed_recipe.duplicate(true)
		opened_recipe.architecture.window.open_angle = 35.0
		var opened: Dictionary = _window_mesh_snapshot(opened_recipe, catalog)
		check(closed.parts.has("sash") and opened.parts.has("sash"), type + "真实闭合和开启窗扇均存在")
		if not closed.parts.has("sash") or not opened.parts.has("sash"): continue
		check(closed.parts.glass.geometry_hash != baseline.parts.glass.geometry_hash, type + "仅type变化已改变玻璃Mesh而非仅metadata")
		var center: Vector3 = closed.opening.center
		var pivot: Vector3 = center + Vector3.UP * float(closed.opening.clear_height) * (0.5 if type == "awning" else -0.5)
		if type != "awning": pivot += Vector3.RIGHT * float(closed.opening.clear_width) * (0.5 if type == "casement_right" else -0.5)
		var axis: Vector3 = Vector3.RIGHT if type == "awning" else Vector3.UP
		var angle: float = deg_to_rad(35.0) * (-1.0 if type == "casement_right" else 1.0)
		var hinge: Dictionary = opened.opening.hinge_before_taper
		check((hinge.pivot as Vector3).distance_to(pivot) < EPS and (hinge.axis as Vector3).distance_to(axis) < EPS and absf(float(hinge.angle) - angle) < EPS, type + "铰链位于正确左右/上边且轴角方向正确")
		for id: String in ["sash", "glass"]:
			var expected := PackedVector3Array()
			for point: Vector3 in closed.parts[id].raw_faces: expected.append(pivot + Basis(axis, angle) * (point - pivot))
			var actual: PackedVector3Array = opened.parts[id].faces
			check(_faces_match_points(actual, expected) and _faces_match_points(expected, actual), type + "实际" + id + "逐点满足独立铰链旋转")
			check(closed.parts[id].geometry_hash != opened.parts[id].geometry_hash and _bounds_changed(closed.parts[id].faces, actual), type + "开角改变实际" + id + "Mesh与AABB")
			check((_bounds(actual).position.z < -4.5 - EPS), type + "实际" + id + "向墙外打开")
		check(opened.parts.frame.geometry_hash == closed.parts.frame.geometry_hash, type + "开角不转动固定外框")
		hashes[opened.parts.glass.geometry_hash] = true
		var tapered_recipe: Dictionary = opened_recipe.duplicate(true)
		tapered_recipe.taper = 0.06
		var tapered: Dictionary = _window_mesh_snapshot(tapered_recipe, catalog)
		for id: String in opened.parts:
			if not tapered.parts.has(id):
				check(false, type + " taper后部件不能消失", id)
				continue
			var expected := PackedVector3Array()
			for point: Vector3 in opened.parts[id].raw_faces:
				var scale: float = 1.0 - 0.06 * clampf(point.y / _height(opened_recipe), 0.0, 1.0)
				expected.append(Vector3(point.x * scale, point.y, point.z * scale))
			check(_faces_match_points(tapered.parts[id].faces, expected) and _faces_match_points(expected, tapered.parts[id].faces), type + "实际" + id + "先旋转再全局taper")
		evidence.types[type] = {"closed": _window_mesh_evidence(closed), "opened": _window_mesh_evidence(opened), "tapered": _window_mesh_evidence(tapered), "hinge": {"pivot": [pivot.x, pivot.y, pivot.z], "axis": [axis.x, axis.y, axis.z], "angle": angle}}
	check(hashes.size() == 4, "fixed/left/right/awning开启状态实际玻璃geometry hash四者不同")
	# 固定窗也必须登记相邻包络；重复位置不得因为没有活动扇而漏掉冲突。
	var guard_hole: Dictionary = hole.duplicate(true)
	var window_geometry: Script = preload("res://src/workshop/shell_window_geometry.gd")
	var bay_reason: String = window_geometry.validate_bay(guard_hole, run, 0.0, 3.0, 0.0, 3.42)
	check(bay_reason.is_empty(), "fixed合法包络仍通过开间守卫", bay_reason)
	var envelopes: Array = []
	check(window_geometry.register_envelope(envelopes, guard_hole, run, "window_a", 0).is_empty(), "fixed完整装配包络登记成功")
	var adjacent_reason: String = window_geometry.register_envelope(envelopes, guard_hole, run, "window_b", 0)
	check(adjacent_reason.contains("相邻洞口冲突"), "fixed相邻装配包络交叠仍严格拒绝", adjacent_reason)
	evidence.rejections["fixed/adjacent_envelope"] = {"rejected": not adjacent_reason.is_empty(), "reason": adjacent_reason}
	for type: String in ["casement_left", "casement_right", "awning"]:
		var sweep_hole: Dictionary = hole.duplicate(true)
		sweep_hole.settings.type = type
		sweep_hole.settings.open_angle = 80.0
		sweep_hole.settings.frame_depth = 0.60
		var envelope: Dictionary = window_geometry._envelope(sweep_hole, run)
		var axis: Vector3 = Vector3.RIGHT if type == "awning" else Vector3.UP
		var pivot: Vector3 = Vector3(-4.5, float(hole.sill) + (float(hole.height) if type == "awning" else 0.0), -4.35)
		if type != "awning": pivot.x += float(hole.width) * (0.5 if type == "casement_right" else -0.5)
		var half_depth: float = (0.60 - 0.004) * 0.5
		var contained: bool = true
		var sampled_low := Vector3(INF, INF, INF)
		var sampled_high := Vector3(-INF, -INF, -INF)
		for step: int in 161:
			var angle: float = deg_to_rad(float(step) * 0.5) * (-1.0 if type == "casement_right" else 1.0)
			for x: float in [float(hole.cx) - float(hole.width) * 0.5 + 0.002, float(hole.cx) + float(hole.width) * 0.5 - 0.002]:
				for y: float in [float(hole.sill) + 0.002, float(hole.sill) + float(hole.height) - 0.002]:
					for depth: float in [float(settings.recess) - half_depth, float(settings.recess) + half_depth]:
						var point: Vector3 = pivot + Basis(axis, angle) * (Vector3(-6.0 + x, y, -4.5 + depth) - pivot)
						var local := Vector3(point.x + 6.0, point.y, point.z + 4.5)
						sampled_low = sampled_low.min(local)
						sampled_high = sampled_high.max(local)
						for coordinate: int in 3:
							contained = contained and local[coordinate] >= (envelope.min as Vector3)[coordinate] - EPS and local[coordinate] <= (envelope.max as Vector3)[coordinate] + EPS
		check(contained and sampled_low.distance_to(envelope.min) < EPS and sampled_high.distance_to(envelope.max) < EPS, type + "解析包络覆盖0到80度完整扫掠而非仅终态")
	var fixed_taper: Dictionary = recipe.duplicate(true)
	fixed_taper.taper = 0.06
	var tapered_fixed: Dictionary = _window_mesh_snapshot(fixed_taper, catalog)
	for id: String in baseline.parts:
		if not tapered_fixed.parts.has(id):
			check(false, "fixed taper后部件不能消失", id)
			continue
		var expected := PackedVector3Array()
		for point: Vector3 in baseline.parts[id].raw_faces:
			var scale: float = 1.0 - 0.06 * clampf(point.y / _height(recipe), 0.0, 1.0)
			expected.append(Vector3(point.x * scale, point.y, point.z * scale))
		check(_faces_match_points(tapered_fixed.parts[id].faces, expected) and _faces_match_points(expected, tapered_fixed.parts[id].faces), "fixed实际" + id + "保留全局taper")
	evidence["fixed_tapered"] = _window_mesh_evidence(tapered_fixed)
	for spec: Array in [["fixed", "open_angle", 1.0, "open_angle"], ["fixed", "glass_thickness", 0.10, "玻璃厚度"], ["fixed", "recess", -0.30, "窗框脱离墙洞"], ["fixed", "sill_projection", 0.003, "窗沿外挑"], ["casement_left", "frame_depth", 0.60, "完整开合包络"], ["casement_right", "frame_depth", 0.60, "完整开合包络"], ["awning", "frame_depth", 0.60, "完整开合包络"]]:
		var invalid: Dictionary = recipe.duplicate(true)
		invalid.architecture.window.type = spec[0]
		invalid.architecture.window.open_angle = 80.0 if str(spec[0]) != "fixed" else 0.0
		if str(spec[1]) == "glass_thickness": invalid.architecture.window.frame_depth = 0.04
		invalid.architecture.window[spec[1]] = spec[2]
		var rejected: Dictionary = ShellGeometry.generate(invalid, catalog)
		var reason: String = str(rejected.get("reason", ""))
		check(not bool(rejected.ok) and rejected.parts.is_empty() and reason.contains(str(spec[3])), "窗核心非法组合仍严格拒绝：" + str(spec[0]) + "/" + str(spec[1]), reason)
		evidence.rejections[str(spec[0]) + "/" + str(spec[1])] = {"rejected": not bool(rejected.ok), "reason": reason}

func _test_invalid_cases(base: Dictionary, catalog: Dictionary) -> void:
	var invalids: Array[Dictionary] = []
	var fixed_angle: Dictionary = base.duplicate(true)
	fixed_angle.building_id = "invalid_fixed_angle"
	fixed_angle.architecture.window.open_angle = 35.0
	invalids.append({"id": "fixed_angle", "recipe": fixed_angle})
	var envelope: Dictionary = base.duplicate(true)
	envelope.building_id = "invalid_open_envelope"
	envelope.architecture.window.type = "casement_left"
	envelope.architecture.window.open_angle = 80.0
	envelope.architecture.window.width = 2.99
	envelope.architecture.window.frame_depth = 0.5
	envelope.architecture.window.recess = 0.27
	envelope.architecture.window.sill = 1.0
	envelope.architecture.window.height = 3.5
	envelope.wall_thickness = 0.6
	invalids.append({"id": "open_envelope_over_bay", "recipe": envelope})
	var detached: Dictionary = base.duplicate(true)
	detached.building_id = "invalid_window_detached"
	detached.architecture.window.frame_depth = 0.12
	detached.architecture.window.recess = -0.30
	check(Config.validate(detached.architecture, int(detached.floors)).is_empty(), "脱离墙洞负例在扩大后的WINDOW_BOUNDS内")
	check(Recipe.validate(detached, catalog).is_empty(), "脱离墙洞负例通过静态参数验证，交由真实几何守卫拒绝")
	var detached_build: Dictionary = Generator.build(detached, catalog)
	var detached_reason: String = str(detached_build.get("reason", ""))
	check(not bool(detached_build.get("ok", false)) and detached_reason.contains("窗框脱离墙洞"), "recess负例因真实脱离墙洞拒绝而非旧边界误报", detached_reason)
	report.invalid_cases["window_detached_from_wall"] = {"rejected": not bool(detached_build.get("ok", false)), "reason": detached_reason}
	_free_build_root(detached_build)
	var roof_mode: Dictionary = base.duplicate(true)
	roof_mode.building_id = "invalid_roof_mode"
	roof_mode.architecture.roof.mode = "balcony"
	invalids.append({"id": "roof_invalid_mode", "recipe": roof_mode})
	var roof_height: Dictionary = base.duplicate(true)
	roof_height.building_id = "invalid_roof_height"
	roof_height.architecture.roof.height = 0.3
	invalids.append({"id": "roof_invalid_bounds", "recipe": roof_height})
	var u_wing: Dictionary = base.duplicate(true)
	u_wing.building_id = "invalid_u_wing"
	u_wing.shape = "u"
	u_wing.architecture.plan.wing_x = 0.2
	invalids.append({"id": "u_invalid_wing", "recipe": u_wing})
	var old_t: Dictionary = base.duplicate(true)
	old_t.building_id = "invalid_t_modular"
	old_t.shape = "t"
	old_t.construction_mode = "modular_v1"
	invalids.append({"id": "t_old_modular", "recipe": old_t})
	for entry: Dictionary in invalids:
		var invalid_recipe: Dictionary = entry.recipe
		var reason: String = Recipe.validate(invalid_recipe, catalog)
		check(not reason.is_empty(), str(entry.id) + "被Recipe/architecture边界拒绝", reason)
		report.invalid_cases[str(entry.id)] = {"rejected": not reason.is_empty(), "reason": reason}

func _test_session_atomic(base: Dictionary, catalog: Dictionary) -> void:
	var session: RefCounted = Session.new(catalog)
	var accepted: Dictionary = session.call("accept_loaded", base, catalog)
	check(bool(accepted.get("ok", false)), "session装入shell architecture recipe", str(accepted.get("reason", "")))
	if not bool(accepted.get("ok", false)):
		return
	var built: Dictionary = _adopt_build_root(session.call("build"))
	var root: Node3D = built.get("root") as Node3D
	check(root != null and bool(built.get("ok", false)), "session last_build.root实际生成", str(built.get("reason", "")))
	if root == null:
		return
	var before_snapshot: String = JSON.stringify(session.call("snapshot"))
	var before_root: Node = session.get("_last_build").get("root") as Node
	var invalid_architecture: Dictionary = base.architecture.duplicate(true)
	invalid_architecture.roof.mode = "invalid_session_mode"
	var rejected: Dictionary = session.call("apply_patch", {"architecture": invalid_architecture})
	check(not bool(rejected.get("ok", false)) and not str(rejected.get("reason", "")).is_empty(), "session架构patch在commit前原子拒绝")
	check(JSON.stringify(session.call("snapshot")) == before_snapshot, "session拒绝patch保持snapshot")
	check(session.get("_last_build").get("root") == before_root and session.get("_last_build").get("root") == root, "session拒绝patch保持lastbuild root身份")
	report["session_atomic"] = {"rejected": not bool(rejected.get("ok", false)), "reason": rejected.get("reason", ""), "root_retained": session.get("_last_build").get("root") == root}
	_free_build_root(built)
	(session.get("_last_build") as Dictionary).clear()

func _test_store(base: Dictionary, catalog: Dictionary) -> void:
	var recipe: Dictionary = base.duplicate(true)
	recipe["building_id"] = "architecture_store_roundtrip"
	recipe["architecture"]["roof"]["mode"] = "mixed"
	recipe["architecture"]["window"]["frame_depth"] = 0.18
	var store: RefCounted = Store.new()
	var base_dir: String = "user://building_workshop/workshop_architecture_suite"
	var exported: Dictionary = store.call("export_revision", recipe, catalog, base_dir)
	check(bool(exported.get("ok", false)), "Store导出shell architecture recipe", str(exported.get("reason", "")))
	if not bool(exported.get("ok", false)):
		return
	var loaded: Dictionary = store.call("load_recipe", str(exported.get("recipe_path", "")))
	check(bool(loaded.get("ok", false)), "Store architecture recipe roundtrip可读取", str(loaded.get("reason", "")))
	if bool(loaded.get("ok", false)):
		var loaded_recipe: Dictionary = loaded.get("recipe", {})
		var exported_recipe: Dictionary = exported.get("recipe", {})
		check(Recipe.fingerprint(loaded_recipe) == Recipe.fingerprint(exported_recipe), "Store roundtrip保持architecture recipe fingerprint")
		var loaded_architecture: Variant = loaded_recipe.get("architecture", null)
		var exported_architecture: Variant = exported_recipe.get("architecture", null)
		var architecture_roundtrip: bool = loaded_recipe.has("architecture") and exported_recipe.has("architecture")
		architecture_roundtrip = architecture_roundtrip and loaded_architecture is Dictionary and exported_architecture is Dictionary
		if architecture_roundtrip:
			architecture_roundtrip = Config.validate(loaded_architecture, int(loaded_recipe.get("floors", 0))).is_empty()
			architecture_roundtrip = architecture_roundtrip and _same_json(loaded_architecture, exported_architecture)
		check(architecture_roundtrip, "Store roundtrip保留有效且数值等价的architecture对象")
	var scene: PackedScene = ResourceLoader.load(str(exported.get("scene_path", "")), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(scene != null, "Store导出场景可重载")
	if scene != null:
		var root: Node3D = scene.instantiate() as Node3D
		root = _adopt_node(root) as Node3D
		check(root != null, "Store导出场景可实例化")
		if root != null:
			check(str(root.get_meta("construction_mode", "")) == "shell_v2", "Store保存root metadata construction_mode正确")
			check(str(root.get_meta("generator_version", "")) == ShellGenerator.GENERATOR_VERSION, "Store保存root metadata generator_version正确")
			check(str(root.get_meta("recipe_fingerprint", "")) == Recipe.fingerprint(exported.get("recipe", {})), "Store保存root metadata recipe_fingerprint正确")
			var reference: Dictionary = Generator.build(exported.get("recipe", {}), catalog)
			check(bool(reference.get("ok", false)), "Store源母型对照重新生成", str(reference.get("reason", "")))
			var saved_inventory: Dictionary = _inventory(root, reference.get("semantic_sources", {}))
			check(_all_parts_closed_oriented(_audit_parts(saved_inventory.parts)), "Store独立源母型实际parts闭合定向")
			check(_all_parts_closed_oriented(_audit_parts(saved_inventory.visible_parts)), "Store重载root实际可见parts闭合定向")
			check(_collision_matches_visual(saved_inventory), "Store重载实际融合网格与碰撞逐点一致")
			var reference_root: Node3D = reference.get("root") as Node3D
			if reference_root != null:
				var reference_parts: Dictionary = _inventory(reference_root, reference.get("semantic_sources", {})).visible_parts
				check(var_to_bytes(reference_parts) == var_to_bytes(saved_inventory.visible_parts), "Store重载实际可见网格与重新生成逐点一致")
			_free_build_root(reference)
			report.store = {"directory": exported.get("directory", ""), "recipe_path": exported.get("recipe_path", ""), "scene_path": exported.get("scene_path", ""), "metadata": {"construction_mode": root.get_meta("construction_mode", ""), "generator_version": root.get_meta("generator_version", ""), "recipe_fingerprint": root.get_meta("recipe_fingerprint", "")}}
		_free_build_root({"root": root})
	scene = null

func _adopt_build_root(result: Dictionary) -> Dictionary:
	var root: Node = result.get("root") as Node
	if root != null:
		result["root"] = _adopt_node(root)
	return result

func _adopt_node(node: Node) -> Node:
	if node != null and node.get_parent() == null:
		get_root().add_child(node)
	return node

func _free_build_root(result: Dictionary) -> void:
	var root: Node = result.get("root") as Node
	if is_instance_valid(root):
		_release_node_resources(root)
		root.free()
	result.clear()

func _release_node_resources(node: Node) -> void:
	for child: Node in node.get_children():
		_release_node_resources(child)
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = mesh_node.mesh
		mesh_node.mesh = null
		mesh_node.material_override = null
		mesh_node.material_overlay = null
		if mesh is ArrayMesh:
			(mesh as ArrayMesh).clear_surfaces()
	elif node is CollisionShape3D:
		(node as CollisionShape3D).shape = null

func _inventory(root: Node3D, semantic_sources: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"parts": {}, "visible_parts": {}, "collisions": {}, "visual_meshes": 0, "collision_shapes": 0, "invalid_collision_shapes": 0, "triangles": 0}
	for id: String in semantic_sources:
		var source: Dictionary = semantic_sources[id]
		var faces := PackedVector3Array()
		for record: Dictionary in source.mesh_records:
			faces.append_array(_transformed(record.mesh.get_faces(), Transform3D(Basis.IDENTITY, source.position) * record.transform))
		check(not faces.is_empty(), "语义源实际母型存在三角面", id)
		var slot: Node3D = root.get_node_or_null("GeneratedVisual/" + id) as Node3D
		check(slot != null and not slot is MeshInstance3D and slot.get_child_count() == 0 and bool(slot.get_meta("semantic_source_only", false)), "融合源槽只保留无Mesh语义节点", id)
		result.parts[id] = faces
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node.mesh != null:
				var id: String = str(node.get_meta("slot_id", node.name))
				var faces: PackedVector3Array = _transformed(mesh_node.mesh.get_faces(), _relative(mesh_node, root))
				var current: PackedVector3Array = result.visible_parts.get(id, PackedVector3Array())
				current.append_array(faces)
				result.visible_parts[id] = current
				if id != "structure_union": result.parts[id] = current
				result.visual_meshes += 1
				result.triangles += int(faces.size() / 3)
		if node is CollisionShape3D:
			result.collision_shapes += 1
			var shape_node: CollisionShape3D = node as CollisionShape3D
			if shape_node.disabled or not shape_node.shape is ConcavePolygonShape3D:
				result.invalid_collision_shapes += 1
			else:
				var collision_faces: PackedVector3Array = _transformed((shape_node.shape as ConcavePolygonShape3D).get_faces(), _relative(shape_node, root))
				var collision_id: String = str(node.get_meta("slot_id", node.get_parent().get_meta("slot_id", node.name)))
				var existing: PackedVector3Array = result.collisions.get(collision_id, PackedVector3Array())
				existing.append_array(collision_faces)
				result.collisions[collision_id] = existing
		for child: Node in node.get_children():
			stack.append(child)
	if str(root.get_meta("construction_mode", "")) == "shell_v2":
		var structure: MeshInstance3D = root.get_node_or_null("GeneratedVisual/structure_union") as MeshInstance3D
		check(structure != null and structure.visible and structure.mesh != null and not structure.mesh.get_faces().is_empty(), "最终可见structure_union实际Mesh存在")
		check(not semantic_sources.is_empty(), "shell源几何审计必须取得semantic_sources，不能空测")
	return result

func _audit_parts(parts: Dictionary) -> Dictionary:
	var result: Dictionary = {"part_count": parts.size(), "bad_parts": {}, "topology": {}}
	for id: String in parts:
		var audit: Dictionary = _topology(parts[id])
		result.topology[id] = audit
		if not bool(audit.get("closed", false)) or not bool(audit.get("oriented", false)) or int(audit.get("nonmanifold_edges", -1)) != 0:
			result.bad_parts[id] = audit
	return result

func _all_parts_closed_oriented(audit: Dictionary) -> bool:
	return int(audit.get("part_count", 0)) > 0 and (audit.get("bad_parts", {}) as Dictionary).is_empty()

func _topology(faces: PackedVector3Array) -> Dictionary:
	var indices := PackedInt32Array()
	for index: int in faces.size():
		indices.append(index)
	return ShellGeometry._topology({"v": faces, "i": indices})

func _collision_matches_visual(inventory: Dictionary) -> bool:
	var structural_count: int = 0
	for id: String in inventory.visible_parts:
		if not _is_collidable_part(id):
			continue
		structural_count += 1
		if not inventory.collisions.has(id):
			return false
		var visual: PackedVector3Array = inventory.visible_parts[id]
		var collision: PackedVector3Array = inventory.collisions[id]
		if visual.size() != collision.size(): return false
		for index: int in visual.size():
			if not visual[index].is_finite() or not collision[index].is_finite() or visual[index].distance_to(collision[index]) > EPS: return false
	for id: String in inventory.collisions:
		if not _is_collidable_part(id):
			return false
	return structural_count == int(inventory.collisions.size())

func _is_collidable_part(id: String) -> bool:
	return id == "structure_union" or id.begins_with("wall_shell_") or id.begins_with("slab_") or id == "roof_main" or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_")

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node3D = node
	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result

func _transformed(faces: PackedVector3Array, transform: Transform3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(faces.size())
	for index: int in faces.size():
		result[index] = transform * faces[index]
	return result

func _all_faces(parts: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	for faces: PackedVector3Array in parts.values():
		result.append_array(faces)
	return result

func _ray_hits(faces: PackedVector3Array, from: Vector3, to: Vector3) -> int:
	var direction: Vector3 = to - from
	var hits: int = 0
	for start: int in range(0, faces.size() - 2, 3):
		var a: Vector3 = faces[start]
		var edge_1: Vector3 = faces[start + 1] - a
		var edge_2: Vector3 = faces[start + 2] - a
		var cross: Vector3 = direction.cross(edge_2)
		var determinant: float = edge_1.dot(cross)
		if absf(determinant) < 0.000000001:
			continue
		var inverse: float = 1.0 / determinant
		var offset: Vector3 = from - a
		var u: float = offset.dot(cross) * inverse
		if u < -EPS or u > 1.0 + EPS:
			continue
		var q: Vector3 = offset.cross(edge_1)
		var v: float = direction.dot(q) * inverse
		if v < -EPS or u + v > 1.0 + EPS:
			continue
		var t: float = edge_2.dot(q) * inverse
		if t >= 0.0 and t <= 1.0:
			hits += 1
	return hits

func _bounds(faces: PackedVector3Array) -> AABB:
	if faces.is_empty():
		return AABB()
	var result: AABB = AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces:
		result = result.expand(point)
	return result

func _bounds_changed(before: PackedVector3Array, after: PackedVector3Array) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	var a: AABB = _bounds(before)
	var b: AABB = _bounds(after)
	return a.position.distance_to(b.position) > EPS or a.size.distance_to(b.size) > EPS

func _root_signature(root: Node3D) -> String:
	var inventory: Dictionary = _inventory(root)
	var ids: Array[String] = _sorted_strings(inventory.parts.keys())
	var data: Array = []
	for id: String in ids:
		data.append([id, inventory.parts[id]])
	return var_to_bytes(data).hex_encode().sha256_text()

func _structural_signature(root: Node3D, semantic_sources: Dictionary) -> String:
	var inventory: Dictionary = _inventory(root, semantic_sources)
	var ids: Array[String] = []
	for id: String in inventory.parts:
		if _is_collidable_part(id):
			ids.append(id)
	ids.sort()
	var data: Array = []
	for id: String in ids:
		data.append([id, inventory.parts[id]])
	return var_to_bytes(data).hex_encode().sha256_text()

func _window_ids(openings: Array) -> Array[String]:
	var result: Array[String] = []
	for opening: Dictionary in openings:
		if str(opening.get("type", "")) == "window":
			result.append(str(opening.get("id", "")))
	result.sort()
	return result

func _first_window_suffix(openings: Array, window_type: String) -> String:
	for opening: Dictionary in openings:
		if str(opening.get("type", "")) == "window" and str(opening.get("window_type", "")) == window_type:
			return str(opening.get("id", "")).trim_prefix("opening_")
	return ""

func _has_roof_surface(surfaces: Array, surface_id: String) -> bool:
	for surface: Dictionary in surfaces:
		if str(surface.get("id", "")) == surface_id:
			return true
	return false

func _has_id_prefix(parts: Dictionary, prefix: String) -> bool:
	for id: String in parts:
		if id.begins_with(prefix):
			return true
	return false

func _has_id_containing(parts: Dictionary, text: String) -> bool:
	for id: String in parts:
		if id.contains(text):
			return true
	return false

func _filter_roof_parts(parts: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id: String in parts:
		if id == "roof_main" or id.begins_with("parapet_") or id.begins_with("roofcap_") or id.begins_with("railing_"):
			result.append(id)
	result.sort()
	return result

func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result

func _height(recipe: Dictionary) -> float:
	var total: float = 0.0
	for floor: int in int(recipe.get("floors", 0)):
		var override: Dictionary = recipe.get("floor_overrides", {}).get(str(floor), {})
		total += float(override.get("floor_height", recipe.get("floor_height", 0.0)))
	return total

func _aabb_json(box: AABB) -> Dictionary:
	return {"position": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]}

func _same_json(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		var left: Dictionary = a
		var right: Dictionary = b
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_json(left[key], right[key]):
				return false
		return true
	if a is Array and b is Array:
		var left_array: Array = a
		var right_array: Array = b
		if left_array.size() != right_array.size():
			return false
		for index: int in left_array.size():
			if not _same_json(left_array[index], right_array[index]):
				return false
		return true
	return a == b

func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}

## 承重柱与层间腰线：开关独立性、柱落在墙垛而非洞口、腰线收在柱后、闭合性。
func _test_frame(base: Dictionary, catalog: Dictionary) -> void:
	var defaults: Dictionary = Config.defaults()
	check(defaults.has("pilaster") and defaults.has("band"), "architecture默认含pilaster与band两节")
	check(not bool(defaults.pilaster.enabled) and not bool(defaults.band.enabled), "两个开关默认关闭，不改变既有配方外观", str(defaults.pilaster.enabled))

	# 1) 开关互不影响：只开柱时没有腰线件，只开腰线时没有柱件。
	for spec in [["pilaster", true, "band", false], ["pilaster", false, "band", true], ["pilaster", true, "band", true]]:
		var recipe: Dictionary = base.duplicate(true)
		recipe["building_id"] = "frame_" + str(spec[0]) + "_" + str(spec[2])
		recipe["taper"] = 0.0
		recipe["architecture"]["pilaster"] = {"enabled": bool(spec[1]), "corner": true, "middle": true, "width": 0.36, "projection": 0.18, "bite": 0.06, "bevel": 0.014}
		recipe["architecture"]["band"] = {"enabled": bool(spec[3]), "projection": 0.10, "thickness": 0.34, "bevel": 0.012}
		var build: Dictionary = Generator.build(recipe, catalog)
		check(bool(build.get("ok", false)), "构架配方可生成：" + str(spec), str(build.get("reason", "")))
		var root: Node3D = build.get("root") as Node3D
		if root == null: continue
		var inventory: Dictionary = _inventory(root, build.get("semantic_sources", {}))
		check(_all_parts_closed_oriented(_audit_parts(inventory.parts)), "柱腰线独立源母型闭合定向：" + str(spec))
		var pilasters: int = 0
		var bands: int = 0
		for id: String in inventory.parts:
			if id.begins_with("pilaster_"): pilasters += 1
			if id.begins_with("band_"): bands += 1
		check((pilasters > 0) == bool(spec[1]), "柱开关生效：" + str(spec), str(pilasters))
		check((bands > 0) == bool(spec[3]), "腰线开关生效：" + str(spec), str(bands))
		# 顶层不生成腰线：只有 floors-1 层有腰线件（矩形4边 × 层数）。
		if bool(spec[3]):
			check(bands <= 4 * (int(recipe.floors) - 1), "腰线不在顶层重复生成", "%d <= %d" % [bands, 4 * (int(recipe.floors) - 1)])
		root.free()

	# 2) 柱必须落在墙垛上，压到洞口必须明确拒绝而不是静默挪位。
	# 不走整楼生成：收窄开间会先被"开口与墙角冲突"拦下，测不出这条守卫。直接对守卫做单元验证。
	var guard_run: Dictionary = {"facade": "front", "holes": [{"cx": 0.0, "x0": -0.86, "x1": 0.86, "reach": 0.86}]}
	var clear_context: Dictionary = {"error": ""}
	check(not bool(ShellGeometry._pilaster_clear(guard_run, 0.0, 0.9, clear_context)), "柱压在洞口上被判为不可放置")
	check(str(clear_context.get("error", "")).contains("压到洞口"), "拒绝原因指出柱压到洞口", str(clear_context.get("error", "")))
	check(str(clear_context.get("error", "")).contains("pilaster.width"), "拒绝原因给出可执行的调整项", str(clear_context.get("error", "")))
	var ok_context: Dictionary = {"error": ""}
	check(bool(ShellGeometry._pilaster_clear(guard_run, 2.0, 0.9, ok_context)), "柱落在墙垛上被判为可放置", str(ok_context.get("error", "")))
	check(str(ok_context.get("error", "")).is_empty(), "可放置时不写错误")

	# 3) 腰线必须收在柱后：柱凸出 > 腰线凸出，否则转角会多出悬挑薄片。
	var both: Dictionary = base.duplicate(true)
	both["building_id"] = "frame_order"
	both["taper"] = 0.0
	both["architecture"]["pilaster"] = {"enabled": true, "corner": true, "middle": true, "width": 0.36, "projection": 0.18, "bite": 0.06, "bevel": 0.014}
	# 故意给腰线一个比柱更大的凸出，生成时必须被压回去。
	both["architecture"]["band"] = {"enabled": true, "projection": 0.30, "thickness": 0.34, "bevel": 0.012}
	var ordered: Dictionary = Generator.build(both, catalog)
	check(bool(ordered.get("ok", false)), "腰线凸出大于柱时可生成", str(ordered.get("reason", "")))
	var ordered_root: Node3D = ordered.get("root") as Node3D
	if ordered_root != null:
		var ordered_parts: Dictionary = _inventory(ordered_root, ordered.get("semantic_sources", {})).parts
		# 比"离墙面有多远"：腰线横贯整个立面，用 max|x| 会比成立面半宽，毫无意义。
		# 只比较落在正面中段（避开转角柱）的构件，正面朝 -Z，z 越小越凸。
		var depth_half: float = float(both.get("depth", 9.0)) * 0.5
		var band_front: float = INF
		var post_front: float = INF
		for id: String in ordered_parts:
			# inventory已将独立源母型按position与record.transform变换到根局部空间。
			var front_z: float = _front_extent(ordered_parts[id])
			# 只认"伸到正面墙皮之外"的件：侧立面的柱/腰线最外只到 -depth/2，不会更负。
			if front_z > -(depth_half + 0.02):
				continue
			if id.begins_with("band_"): band_front = minf(band_front, front_z)
			if id.begins_with("pilaster_"): post_front = minf(post_front, front_z)
		check(band_front < INF and post_front < INF, "柱与腰线都实际生成", "band=%f post=%f" % [band_front, post_front])
		check(post_front < band_front, "柱比腰线更凸（腰线收在柱后）", "post z=%f band z=%f" % [post_front, band_front])
		ordered_root.free()

	# 4) 参数越界与非法组合必须拒绝。
	var bite_zero: Dictionary = base.duplicate(true)
	bite_zero["architecture"]["pilaster"] = {"enabled": true, "corner": true, "middle": true, "width": 0.36, "projection": 0.18, "bite": 0.0, "bevel": 0.014}
	check(not Recipe.validate(bite_zero, catalog).is_empty(), "柱bite为0被拒绝（必须咬入墙体）", Recipe.validate(bite_zero, catalog))
	var thin: Dictionary = base.duplicate(true)
	thin["architecture"]["pilaster"] = {"enabled": true, "corner": true, "middle": true, "width": 0.36, "projection": 0.05, "bite": 0.02, "bevel": 0.06}
	check(not Recipe.validate(thin, catalog).is_empty(), "柱厚小于倒角被拒绝", Recipe.validate(thin, catalog))
	var thin_band: Dictionary = base.duplicate(true)
	thin_band["architecture"]["band"] = {"enabled": true, "projection": 0.10, "thickness": 0.10, "bevel": 0.05}
	check(not Recipe.validate(thin_band, catalog).is_empty(), "腰线厚度小于倒角被拒绝", Recipe.validate(thin_band, catalog))
	var unknown: Dictionary = base.duplicate(true)
	unknown["architecture"]["pilaster"] = {"enabled": true, "corner": true, "middle": true, "width": 0.36, "projection": 0.18, "bite": 0.06, "bevel": 0.014, "radius": 0.1}
	check(not Recipe.validate(unknown, catalog).is_empty(), "柱未知字段被拒绝", Recipe.validate(unknown, catalog))

## 某件 mesh 在正面(-Z)方向最靠外（z 最小）的值，用来比"谁更凸出墙面"。
func _front_extent(faces: PackedVector3Array) -> float:
	if faces.is_empty(): return INF
	var extreme: float = INF
	for point in faces:
		extreme = minf(extreme, point.z)
	return extreme

func _test_form(base: Dictionary, catalog: Dictionary) -> void:
	# 1) 区间 + seed 的落值必须落在区间内，且同 seed 稳定、不同 seed 会变。
	var interval_recipe: Dictionary = base.duplicate(true)
	interval_recipe["building_id"] = "form_interval"
	interval_recipe["architecture"]["form"] = {
		"enabled": true, "preset": "SF-B", "seed": 11010, "max_tilt_deg": 8.0,
		"structure": {"min": 0.030, "max": 0.060, "sign": "positive"},
		"opening": {"min": 0.020, "max": 0.045, "sign": "positive"},
		"accessory": {"min": 0.040, "max": 0.090, "sign": "positive"}
	}
	var resolved: Dictionary = Config.resolve_form(Recipe.normalized(interval_recipe))
	check(bool(resolved.get("enabled", false)), "形体落值已启用")
	for category in ["structure", "opening", "accessory"]:
		var entry: Dictionary = interval_recipe["architecture"]["form"][category]
		var value: float = absf(float(resolved.get(category, 0.0)))
		check(value >= float(entry["min"]) - EPS and value <= float(entry["max"]) + EPS, "形体落值在区间内：" + category, "%f not in [%f,%f]" % [value, float(entry["min"]), float(entry["max"])])
		check(value > 0.0, "形体落值不为0（零方正）：" + category, str(value))
	var repeat: Dictionary = Config.resolve_form(Recipe.normalized(interval_recipe.duplicate(true)))
	check(is_equal_approx(float(repeat.structure), float(resolved.structure)) and is_equal_approx(float(repeat.opening), float(resolved.opening)) and is_equal_approx(float(repeat.accessory), float(resolved.accessory)), "同seed落值可复现")
	var rerolled: Dictionary = interval_recipe.duplicate(true)
	rerolled["architecture"]["form"]["seed"] = 11011
	var other: Dictionary = Config.resolve_form(Recipe.normalized(rerolled))
	check(not is_equal_approx(float(other.structure), float(resolved.structure)), "换seed会改变落值", "%f vs %f" % [float(other.structure), float(resolved.structure)])

	# 2) 结构收分写入 taper；关闭形体时不改写 taper。
	check(is_equal_approx(float(Recipe.normalized(interval_recipe).taper), float(resolved.structure)), "结构落值写入taper", str(Recipe.normalized(interval_recipe).taper))
	var off: Dictionary = interval_recipe.duplicate(true)
	off["architecture"]["form"]["enabled"] = false
	var off_normalized: Dictionary = Recipe.normalized(off)
	check(is_equal_approx(float(off_normalized.taper), float(base.taper)), "关闭形体退回配方taper")

	# 3) 幅度越界与结构倒锥必须拒绝，并给出可执行的倾角上限。
	var too_wide: Dictionary = interval_recipe.duplicate(true)
	too_wide["architecture"]["form"]["max_tilt_deg"] = 4.0
	too_wide["architecture"]["form"]["structure"] = {"min": 0.05, "max": 0.09, "sign": "positive"}
	check(not Recipe.validate(too_wide, catalog).is_empty(), "4°下结构幅度超限被拒绝", Recipe.validate(too_wide, catalog))
	check(Recipe.validate(too_wide, catalog).contains("上限"), "拒绝原因给出可用上限", Recipe.validate(too_wide, catalog))
	# tan 线性只属于倾角这一项：可用收分 = min(倾角限制, taper字段上限0.10)，
	# 所以必须用 tilt_taper_limit 验线性，用 structure_limit 验最终封顶。
	var limit_four: float = Config.tilt_taper_limit(Recipe.normalized(too_wide))
	check(limit_four > 0.0, "4°倾角上限为正", str(limit_four))
	var same_at_eight: Dictionary = too_wide.duplicate(true)
	same_at_eight["architecture"]["form"]["max_tilt_deg"] = 8.0
	check(Recipe.validate(same_at_eight, catalog).is_empty(), "同一幅度在8°下通过", Recipe.validate(same_at_eight, catalog))
	var tilt_eight: float = Config.tilt_taper_limit(Recipe.normalized(same_at_eight))
	var expected_eight: float = limit_four * (tan(deg_to_rad(8.0)) / tan(deg_to_rad(4.0)))
	check(absf(tilt_eight - expected_eight) < 0.00001, "倾角上限按tan线性放大", "%.4f vs %.4f" % [tilt_eight, expected_eight])
	check(tilt_eight > 0.10, "8°下12m三层楼倾角允许超过10%", str(tilt_eight))
	# 最终可用值被 taper 字段封顶，必须精确等于 cap 而不是继续放大。
	var capped: float = Config.structure_limit(Recipe.normalized(same_at_eight))
	check(is_equal_approx(capped, 0.10) and capped <= 0.10 + 0.000001, "可用收分被taper字段封顶0.10", str(capped))
	check(capped < tilt_eight - 0.01, "封顶确实比倾角允许值更严", "%.4f vs %.4f" % [capped, tilt_eight])
	# 倾角越界与非法取号必须拒绝。
	var tilt_out: Dictionary = interval_recipe.duplicate(true)
	tilt_out["architecture"]["form"]["max_tilt_deg"] = 40.0
	check(not Recipe.validate(tilt_out, catalog).is_empty(), "倾角上限超出可调范围被拒绝")
	var mixed_structure: Dictionary = interval_recipe.duplicate(true)
	mixed_structure["architecture"]["form"]["structure"] = {"min": 0.03, "max": 0.05, "sign": "mixed"}
	check(not Recipe.validate(mixed_structure, catalog).is_empty(), "结构族不允许mixed取号")
	var negative: Dictionary = interval_recipe.duplicate(true)
	negative["architecture"]["form"]["structure"] = {"min": 0.01, "max": 0.015, "sign": "negative"}
	check(not Recipe.validate(negative, catalog).is_empty(), "结构族倒锥被拒绝")
	var reversed_interval: Dictionary = interval_recipe.duplicate(true)
	reversed_interval["architecture"]["form"]["opening"] = {"min": 0.03, "max": 0.02, "sign": "positive"}
	check(not Recipe.validate(reversed_interval, catalog).is_empty(), "min大于max被拒绝")
	var unknown_field: Dictionary = interval_recipe.duplicate(true)
	unknown_field["architecture"]["form"]["accessory"] = {"min": 0.03, "max": 0.04, "sign": "positive", "jitter": 1.0}
	check(not Recipe.validate(unknown_field, catalog).is_empty(), "形体未知字段被拒绝")

	# 4) 实际几何：洞口真梯形、整楼真收分、配件真变径。
	var built: Dictionary = Generator.build(interval_recipe, catalog)
	var root: Node3D = built.get("root") as Node3D
	check(bool(built.get("ok", false)) and root != null, "形体配方可生成真实模型", str(built.get("reason", "")))
	if root == null:
		return
	var visual: Node3D = root.get_node_or_null("GeneratedVisual") as Node3D
	var opening: Array = built.get("openings", [])
	var window_id: String = ""
	for entry in opening:
		if str((entry as Dictionary).get("type", "")) == "window":
			window_id = str((entry as Dictionary).get("id", "")).trim_prefix("opening_")
			break
	check(not window_id.is_empty(), "存在可核对的窗洞口")
	if visual != null and not window_id.is_empty():
		var glass: MeshInstance3D = visual.get_node_or_null("glass_" + window_id) as MeshInstance3D
		var frame: MeshInstance3D = visual.get_node_or_null("frame_" + window_id) as MeshInstance3D
		check(glass != null and frame != null, "窗玻璃与窗框存在")
		if glass != null and frame != null:
			var glass_span: Vector2 = _top_bottom_span(glass.mesh.get_faces())
			var frame_span: Vector2 = _top_bottom_span(frame.mesh.get_faces())
			# positive 取号下整栋同向：上口窄于下口。
			check(glass_span.y < glass_span.x - 0.001, "窗玻璃实际梯形（上口窄于下口）", "bottom=%f top=%f" % [glass_span.x, glass_span.y])
			check(frame_span.y < frame_span.x - 0.001, "窗框实际梯形（上口窄于下口）", "bottom=%f top=%f" % [frame_span.x, frame_span.y])
			check(absf((glass_span.x - glass_span.y) - (frame_span.x - frame_span.y)) < 0.02, "玻璃与窗框梯形收分量一致（同pull派生）", "glass=%f frame=%f" % [glass_span.x - glass_span.y, frame_span.x - frame_span.y])
		var post: MeshInstance3D = visual.get_node_or_null("canopy_post_0") as MeshInstance3D
		if post != null:
			var post_span: Vector2 = _top_bottom_span(post.mesh.get_faces())
			check(post_span.y < post_span.x - 0.0005, "雨棚柱实际变径（非直筒）", "bottom=%f top=%f" % [post_span.x, post_span.y])
		var wall: PackedVector3Array = _inventory(root, built.get("semantic_sources", {})).parts.get("wall_shell_0", PackedVector3Array())
		check(not wall.is_empty(), "首层墙壳独立源母型存在")
		if not wall.is_empty():
			var wall_span: Vector2 = _top_bottom_span(wall)
			check(wall_span.y < wall_span.x - 0.001, "墙壳随整楼收分（上口窄于下口）", "bottom=%f top=%f" % [wall_span.x, wall_span.y])
	# 5) 关闭形体时必须退回正交：同一洞口上下等宽。
	var orthographic: Dictionary = interval_recipe.duplicate(true)
	orthographic["building_id"] = "form_off_orthographic"
	orthographic["architecture"]["form"]["enabled"] = false
	orthographic["taper"] = 0.0
	var flat: Dictionary = Generator.build(orthographic, catalog)
	var flat_root: Node3D = flat.get("root") as Node3D
	check(bool(flat.get("ok", false)) and flat_root != null, "关闭形体仍可生成", str(flat.get("reason", "")))
	if flat_root != null:
		var flat_visual: Node3D = flat_root.get_node_or_null("GeneratedVisual") as Node3D
		var flat_glass: MeshInstance3D = flat_visual.get_node_or_null("glass_" + window_id) as MeshInstance3D if flat_visual != null else null
		check(flat_glass != null, "正交基线的同一窗存在")
		if flat_glass != null:
			var flat_span: Vector2 = _top_bottom_span(flat_glass.mesh.get_faces())
			check(absf(flat_span.y - flat_span.x) < 0.001, "关闭形体后窗口回正交矩形", "bottom=%f top=%f" % [flat_span.x, flat_span.y])
	# 6) 窗洞取号：mixed 必须让同一立面同时出现两个方向，且同列上下一致。
	var mixed: Dictionary = interval_recipe.duplicate(true)
	mixed["building_id"] = "form_mixed"
	mixed["architecture"]["form"]["opening"] = {"min": 0.020, "max": 0.045, "sign": "mixed"}
	var mixed_recipe: Dictionary = Recipe.normalized(mixed)
	var narrow: int = 0
	var wide: int = 0
	for facade in ["front", "back", "left", "right"]:
		for ordinal in 6:
			var rho: float = Config.opening_rho(mixed_recipe, str(facade) + "_" + str(ordinal))
			check(absf(absf(rho) - 0.020) >= -1.0 and absf(rho) <= 0.045 + EPS and absf(rho) >= 0.020 - EPS, "mixed每列幅度仍在区间内：" + str(facade) + "_" + str(ordinal), str(rho))
			if rho > 0.0: narrow += 1
			elif rho < 0.0: wide += 1
	check(narrow > 0 and wide > 0, "mixed同时存在上窄与上宽列", "窄%d 宽%d" % [narrow, wide])
	var repeat_rho: float = Config.opening_rho(Recipe.normalized(mixed.duplicate(true)), "front_0")
	check(is_equal_approx(repeat_rho, Config.opening_rho(mixed_recipe, "front_0")), "mixed逐列取号同seed可复现")
	var mixed_build: Dictionary = Generator.build(mixed, catalog)
	var mixed_root: Node3D = mixed_build.get("root") as Node3D
	check(bool(mixed_build.get("ok", false)) and mixed_root != null, "mixed配方可生成真实模型", str(mixed_build.get("reason", "")))
	if mixed_root != null:
		var mixed_visual: Node3D = mixed_root.get_node_or_null("GeneratedVisual") as Node3D
		var up_narrow: int = 0
		var up_wide: int = 0
		for node: Node in mixed_visual.get_children():
			if not str(node.name).begins_with("glass_"):
				continue
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null: continue
			var m_span: Vector2 = _top_bottom_span(mesh_node.mesh.get_faces())
			if m_span.y < m_span.x - 0.0005: up_narrow += 1
			elif m_span.y > m_span.x + 0.0005: up_wide += 1
		check(up_narrow > 0 and up_wide > 0, "mixed在真实玻璃上两个方向都出现", "上窄%d 上宽%d" % [up_narrow, up_wide])
		mixed_root.free()
	# 7) 统一上宽：所有窗反转，墙仍正收分（结构族只做正锥）。
	var inverted: Dictionary = interval_recipe.duplicate(true)
	inverted["building_id"] = "form_inverted"
	inverted["architecture"]["form"]["opening"] = {"min": 0.020, "max": 0.045, "sign": "negative"}
	var inverted_build: Dictionary = Generator.build(inverted, catalog)
	var inverted_root: Node3D = inverted_build.get("root") as Node3D
	check(bool(inverted_build.get("ok", false)) and inverted_root != null, "统一上宽可生成真实模型", str(inverted_build.get("reason", "")))
	if inverted_root != null:
		var inverted_visual: Node3D = inverted_root.get_node_or_null("GeneratedVisual") as Node3D
		var bad_up_narrow: int = 0
		var inverted_wide: int = 0
		for node: Node in inverted_visual.get_children():
			if not str(node.name).begins_with("glass_"):
				continue
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null: continue
			var i_span: Vector2 = _top_bottom_span(mesh_node.mesh.get_faces())
			if i_span.y > i_span.x + 0.0005: inverted_wide += 1
			elif i_span.y < i_span.x - 0.0005: bad_up_narrow += 1
		check(inverted_wide > 0 and bad_up_narrow == 0, "统一上宽时无一片上窄", "上宽%d 上窄%d" % [inverted_wide, bad_up_narrow])
		inverted_root.free()

	if root != null:
		root.free()
	if flat_root != null:
		flat_root.free()

## 取某件mesh最上/最下各4mm切片内的x向宽度，用来判定"上口是否窄于下口"。
func _top_bottom_span(faces: PackedVector3Array) -> Vector2:
	if faces.is_empty(): return Vector2.ZERO
	var low: float = faces[0].y
	var high: float = faces[0].y
	for point in faces:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var bottom_lo: float = INF
	var bottom_hi: float = -INF
	var top_lo: float = INF
	var top_hi: float = -INF
	for point in faces:
		if point.y < low + 0.004:
			bottom_lo = minf(bottom_lo, point.x)
			bottom_hi = maxf(bottom_hi, point.x)
		if point.y > high - 0.004:
			top_lo = minf(top_lo, point.x)
			top_hi = maxf(top_hi, point.x)
	return Vector2(bottom_hi - bottom_lo, top_hi - top_lo)

func _finish() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	check(directory_error == OK, "报告目录可用", error_string(directory_error))
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	check(file != null, "架构报告可写", error_string(FileAccess.get_open_error()))
	if file != null:
		report["checks"] = checks
		report["failures"] = failures.duplicate()
		report["failure_count"] = failures.size()
		file.store_string(JSON.stringify(report, "\t"))
		var write_error: Error = file.get_error()
		file.close()
		file = null
		if write_error != OK:
			check(false, "架构报告写入成功", error_string(write_error))
	report.clear()
	print("[workshop-architecture] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
