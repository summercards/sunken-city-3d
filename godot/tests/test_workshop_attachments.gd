extends SceneTree

const Data = preload("res://addons/building_workshop/attachment_work_data.gd")
const Store = preload("res://addons/building_workshop/editor_store.gd")
const HouseRecipe = preload("res://src/workshop/recipe.gd")
const HouseCatalog = preload("res://src/workshop/catalog.gd")
const HouseGenerator = preload("res://src/workshop/generator.gd")
const Controller = preload("res://addons/scene_assembly/attachment_controller.gd")
const History = preload("res://addons/building_workshop/attachment_history.gd")
const PreviewInput = preload("res://addons/building_workshop/attachment_preview_input.gd")
const Surface = preload("res://addons/scene_assembly/attachment_surface.gd")
const Recipe = preload("res://src/building_attachments/recipe.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const BASE := "res://outputs/workshop_editor/attachment_logic"
const FILES := ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json", "building.attachments.json", "building.attachments.tscn", "building.work.tscn"]
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var mount_report: Dictionary = {}

class MountView extends Control:
	var work: Node3D
	var asset: Node3D
	var temporary: Node3D
	var selection: Array = []
	var ray: Dictionary = {}

	func get_work_root() -> Node3D: return work
	func get_host_asset() -> Node3D: return asset
	func get_temporary_root() -> Node3D: return temporary
	func get_selection() -> Array: return selection
	func set_selection(nodes: Array) -> void: selection = nodes.duplicate()
	func ray_from_local_position(_position: Vector2) -> Dictionary: return ray

class HeadlessPanel extends "res://addons/scene_assembly/attachment_panel.gd":
	func _render_thumbnails() -> void: pass

class FailingStore extends "res://addons/building_workshop/editor_store.gd":
	var fail_file := ""
	var fail_after_write := false
	func _write_json(path: String, value: Dictionary) -> bool:
		if path.get_file() == fail_file and not fail_after_write: return false
		var result := super._write_json(path, value)
		return false if path.get_file() == fail_file else result

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	rows.append({"label": label, "passed": value, "mode": "direct_call"})
	if not value:
		failures.append(label)
		printerr("FAIL [workshop-attachments] ", label)

func run() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		quit(1)
		return
	var empty: Dictionary = Data.empty_snapshot()
	check(Data.validate(empty).is_empty(), "空外挂快照合法")
	var layer := Node3D.new()
	layer.name = "Attachments"
	for type_id: String in ["sign_fascia", "tank_tower_cone"]:
		var recipe: Dictionary = Recipe.defaults(type_id)
		recipe.condition = "damaged"
		if type_id == "sign_fascia": recipe.text = "SEA CAFE"
		var built: Dictionary = Generator.build(recipe)
		check(built.ok, "可信原生生成：" + type_id)
		if not built.ok: continue
		var node: Node3D = built.root
		node.name = type_id
		node.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(7.0)), Vector3(1.234567, 2.345678, -3.456789))
		node.set_meta("sea_attachment", {"schema_version": 1, "instance_id": type_id, "instanceid": type_id, "recipe": recipe.duplicate(true), "host_path": ".", "anchor": {"mode": "wall" if type_id == "sign_fascia" else "roof", "mesh_path": "GeneratedVisual/structure_union", "surface": 0, "triangle": 0, "host_position": [0.0, 2.0, 0.0], "host_normal": [0.0, 0.0, 1.0], "local_position": built.mount_anchor.position.duplicate(), "native": built.mount_anchor.duplicate(true), "declared_clearance_m": 0.012, "offset_m": 0.03, "angle_degrees": 7.0}, "stats": built.stats.duplicate(true)})
		layer.add_child(node)
	var snapshot: Dictionary = Data.capture(layer)
	check(Data.validate(snapshot).is_empty(), "两类型可信安装快照合法")
	var rebuilt: Dictionary = Data.build(snapshot)
	check(rebuilt.ok, "快照重新原生生成")
	if rebuilt.ok:
		check(Data.fingerprint(Data.capture(rebuilt.root)) == Data.fingerprint(snapshot), "变换及英文原文无损roundtrip")
		check(static_owned(rebuilt.root, rebuilt.root), "原生静态节点无脚本且owner完整")
		rebuilt.root.free()
	test_invalid(snapshot)
	await process_frame
	test_store(snapshot)
	test_store(empty)
	layer.free()
	test_mounting()
	var report := {"suite": "workshop-attachments", "checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Data/EditorStore、图库参数隔离、挂载输入及工坊真实新建默认网格；不模拟原生GUI", "automatic_gui": [], "direct_call": rows, "mounting": mount_report, "real_rendering": "未执行", "expected_failures": [], "exit_code": 0 if failures.is_empty() else 1}
	write_text("res://outputs/workshop_attachments_logic_report.json", JSON.stringify(report, "\t"))
	print("[workshop-attachments] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_mounting() -> void:
	var house: Dictionary = HouseGenerator.build(HouseRecipe.authoring_defaults())
	check(house.ok, "真实新建阳光房参考默认成功生成")
	if not house.ok: return
	var view := MountView.new()
	root.add_child(view)
	view.work = Node3D.new()
	view.add_child(view.work)
	view.asset = Node3D.new()
	view.asset.name = "Asset"
	view.work.add_child(view.asset)
	view.asset.add_child(house.root)
	view.temporary = Node3D.new()
	view.add_child(view.temporary)
	var controller := Controller.new()
	view.add_child(controller)
	var history := History.new()
	var input := PreviewInput.new()
	input.configure(view, controller, view.set_selection)
	check(controller.configure_workshop({"root": view.get_work_root, "host_asset": view.get_host_asset,
		"selection_get": view.get_selection, "selection_set": view.set_selection,
		"arm": input.arm, "cancel": input.cancel, "history": history}).ok, "挂载使用真实工坊控制器和本地历史")
	check(controller.set_host(view.work).ok, "锁定真实宿主")
	var panel := HeadlessPanel.new()
	panel.embedded_workshop = true
	panel.controller = controller
	view.add_child(panel)
	panel._choice_value("mount_mode", "wall")
	panel.fields.offset.slider.value = 0.08
	panel.fields.angle.slider.value = 23.0
	var drag: Dictionary = panel.prepare_drag("satellite_dish")
	check(drag.ok and controller._mode(drag.recipe) == "roof" and is_zero_approx(controller.offset) and is_zero_approx(controller.angle_degrees), "天线没有自身草稿时不继承当前墙牌参数")
	panel._context = "draft:satellite_dish"
	panel._load_inputs(Recipe.defaults("satellite_dish"), {"mode": "wall", "offset_m": 0.03, "angle_degrees": 7.0})
	drag = panel.prepare_drag("satellite_dish")
	check(drag.ok and controller._mode(drag.recipe) == "wall" and is_equal_approx(controller.offset, 0.03) and is_equal_approx(controller.angle_degrees, 7.0), "当前卡片自己的显式墙面、偏移、角度被保留")
	panel._stash()
	panel._context = "draft:sign_fascia"
	panel._load_inputs(Recipe.defaults("sign_fascia"))
	drag = panel.prepare_drag("satellite_dish")
	check(drag.ok and controller._mode(drag.recipe) == "wall" and is_equal_approx(controller.offset, 0.03) and is_equal_approx(controller.angle_degrees, 7.0), "拖不同卡片时读取该卡片缓存的安装参数")
	controller.cancel_arm(false)
	check(controller.set_mount_options("roof").ok, "准备严格屋顶探测")
	var roof_ray := {"origin": Vector3(0, 20, 0), "direction": Vector3.DOWN}
	var tank: Dictionary = Recipe.defaults("tank_tower_cone")
	var roof_result: Dictionary = controller.preview_at_ray(tank, roof_ray.origin, roof_ray.direction)
	mount_report.roof_center = {"ok": roof_result.ok, "reason": roof_result.reason, "point": str(roof_result.get("position", "")), "support_checks": roof_result.get("support_checks", 0)}
	check(roof_result.ok and int(roof_result.get("support_checks", 0)) == 12, "默认阳光房中央屋顶承托水塔全部12个支点")
	test_drop_input(view, controller, input, panel, history, roof_ray)
	probe_mount_range(controller)
	test_chaining(view, controller, input, history)
	controller.cancel_arm(false)
	history.clear_history()
	view.free()

func test_drop_input(view: MountView, controller: Node, input: RefCounted, panel: Control, history: RefCounted, roof_ray: Dictionary) -> void:
	view.ray = roof_ray
	var drag: Dictionary = panel.prepare_drag("tank_tower_cone")
	if not drag.ok:
		check(false, "建立屋顶水塔拖放事务")
		return
	var payload := {"type": "sea_building_attachment", "recipe": drag.recipe, "arm_token": drag.token}
	var stale := payload.duplicate(true)
	stale.arm_token -= 1
	check(not input.can_drop(Vector2.ZERO, stale) and controller.armed, "过期拖放不能取消新事务")
	var malformed := payload.duplicate(true)
	malformed.erase("arm_token")
	check(not input.can_drop(Vector2.ZERO, malformed) and controller.armed, "没有事务令牌不能提交拖放")
	check(input.can_drop(Vector2.ZERO, payload) and input.ghost.visible, "真实中央屋面预判合法并显示 ghost")
	view.ray = {}
	check(not input.can_drop(Vector2.ZERO, payload) and not input.ghost.visible, "射线失效不显示上次绿色 ghost")
	view.ray = {"origin": Vector3(4.5, 20, 4.0), "direction": Vector3.DOWN}
	var center_hit: Dictionary = Surface.raycast(controller.host_asset, view.ray.origin, view.ray.direction, "roof")
	check(center_hit.ok and not input.can_drop(Vector2.ZERO, payload), "屋顶边缘中心命中仍拒绝悬空底脚")
	var rejected: Dictionary = input.drop(Vector2.ZERO, payload)
	check(not rejected.ok and str(rejected.reason).contains("支承不足") and not history.can_undo(), "松开时独立重验且返回真实支承失败原因，无历史")
	input.drag_finished(true)
	check(not controller.armed and input.ghost == null and not view.work.has_node("Attachments"), "引擎接受拖放但真实几何失败，不留点击事务或节点")
	drag = panel.prepare_drag("tank_tower_cone")
	payload = {"type": "sea_building_attachment", "recipe": drag.get("recipe", {}), "arm_token": drag.get("token", 0)}
	check(not input.can_drop(Vector2.ZERO, payload), "拖到屋顶边缘不能接受")
	input.drag_finished(false)
	check(not controller.armed and panel.status.text.contains("支承不足"), "无效拖放结束清理试放并保留具体失败反馈")
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	view.ray = roof_ray
	check(not input.handle_input(click_event) and not history.can_undo(), "失败拖放后下一次普通点击不会暗中放置")
	drag = panel.prepare_drag("tank_tower_cone")
	payload = {"type": "sea_building_attachment", "recipe": drag.get("recipe", {}), "arm_token": drag.get("token", 0)}
	check(not input.handle_input(click_event), "拖放事务不能同时进入贴面点击")
	click_event.pressed = false
	check(not input.handle_input(click_event) and not history.can_undo(), "拖放鼠标释放不提前提交点击放置")
	var placed: Dictionary = input.drop(Vector2.ZERO, payload)
	check(placed.ok and view.work.get_node("Attachments").get_child_count() == 1 and history.can_undo(), "合法释放向本栋安装且只提交一次")
	if not placed.ok: return
	var installed: Node3D = placed.attachment
	check(installed.get_meta("sea_attachment").anchor.mode == "roof", "最终元数据与拖放挂载面一致")
	panel.fields.angle.slider.value = 31.0
	panel.fields.offset.slider.value = 0.12
	drag = panel.prepare_drag("tank_tower_cone")
	check(drag.ok and is_zero_approx(controller.angle_degrees) and is_zero_approx(controller.offset), "同类型已装实例的未应用值不进入图库拖放")
	controller.cancel_arm(false)
	check(history.undo() and not view.work.has_node("Attachments") and not history.can_undo(), "一次撤销移除唯一放置记录")

func test_chaining(view: MountView, controller: Node, input: RefCounted, history: RefCounted) -> void:
	# 独立实心墙，不绕过射线或实际安装检查；避开默认阳光房窗口对夹具的干扰。
	view.asset.get_child(0).hide()
	var wall := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(25, 12, 0.6)
	wall.mesh = slab
	wall.position = Vector3(0, 6, 0)
	view.asset.add_child(wall)
	controller._select_nodes([])
	check(not controller.supports_chain(Recipe.defaults("sign_fascia")), "普通招牌仍无连续工具")
	var template: Dictionary = Recipe.defaults("pipe_t_valve")
	var damaged := template.duplicate(true)
	damaged.condition = "damaged"
	check(not controller.supports_chain(damaged), "缺口管不伪造完整接头")
	for type_id: String in ["pipe_t_valve", "awning_slope", "awning_barrel", "canopy_entry", "pipe_elbow"]:
		controller.cancel_arm(false)
		controller._select_nodes([])
		controller.set_mount_options("wall")
		var recipe: Dictionary = Recipe.defaults(type_id)
		var ports: Array = controller.chain_ports(recipe)
		check(ports.size() == 2, "两处真实接口 " + type_id)
		if ports.size() != 2: continue
		var y: float = {"pipe_t_valve": 2.0, "awning_slope": 5.0, "awning_barrel": 8.0, "canopy_entry": 4.0, "pipe_elbow": 2.0}[type_id]
		var x: float = 7.0 if type_id == "canopy_entry" else (-7.0 if type_id == "pipe_elbow" else 0.0)
		check(controller.arm_chain(recipe).ok, "启用连续模式 " + type_id)
		var first: Dictionary = controller.viewportclick_place(Vector3(x, y, 10), Vector3.FORWARD)
		check(first.ok and controller.chain_active, "首段真实安装并保持工具 " + type_id + ": " + str(first.reason))
		if not first.ok: continue
		var source: Node3D = first.attachment
		var next_port: Dictionary = ports.back()
		var target: Vector3 = source.global_transform * (next_port.position as Vector3)
		var outward: Vector3 = source.global_basis * (next_port.direction as Vector3)
		var hover := target + outward * 0.8
		hover.z = 10.0
		var shown: Dictionary = input._update_ghost_at_ray({"origin": hover, "direction": Vector3.FORWARD})
		check(shown.ok and is_instance_valid(input.ghost) and input.ghost.visible, "接头吸附显示真实试放 " + type_id + ": " + str(shown.reason))
		var count: int = source.get_parent().get_child_count()
		var next: Dictionary = controller.viewportclick_place(hover, Vector3.FORWARD)
		check(next.ok and controller.chain_active and source.get_parent().get_child_count() == count + 1, "一次点击接一段且无需重新启用 " + type_id + ": " + str(next.reason))
		if not next.ok: continue
		var mate: Node3D = next.attachment
		var connected := false
		for port: Dictionary in ports:
			var peak: Vector3 = mate.global_transform * (port.position as Vector3)
			connected = connected or (peak.distance_to(target) < 0.003 and (mate.global_basis * (port.direction as Vector3)).dot(outward) < -0.998)
		check(connected and mate.global_transform.is_equal_approx(shown.pose), "实物两端接合且与预览一致 " + type_id)
		if type_id in ["pipe_t_valve", "awning_slope"]:
			var layer: Node3D = source.get_parent()
			var refused: Dictionary = controller.viewportclick_place(Vector3(0, 35, 10), Vector3.FORWARD)
			check(not refused.ok and controller.chain_active and layer.get_child_count() == count + 1, "空处拒绝且不结束接长 " + type_id)
			var occupied := target - outward * 0.8
			occupied.z = 10.0
			refused = controller.viewportclick_place(occupied, Vector3.FORWARD)
			check(not refused.ok and controller.chain_active and layer.get_child_count() == count + 1, "已占用接头拒绝且不增段 " + type_id)
			var beyond := hover + outward * (target.distance_to(mate.global_transform * (next_port.position as Vector3)))
			beyond.z = 10.0
			var third: Dictionary = controller.viewportclick_place(beyond, Vector3.FORWARD)
			check(third.ok and controller.chain_active and layer.get_child_count() == count + 2, "同一工具继续第三段 " + type_id + ": " + str(third.reason))
			var snapshot: Dictionary = Data.capture(layer)
			if type_id == "awning_slope":
				var house_recipe: Dictionary = HouseRecipe.authoring_defaults()
				house_recipe.building_id = "attachment_chain_work"
				var store := Store.new()
				var saved: Dictionary = store.export_work_revision(house_recipe, HouseCatalog.definitions(), snapshot, BASE)
				check(saved.ok, "含连续管道和顶棚的完整作品保存：" + str(saved.get("reason", "")))
				if saved.ok:
					var reopened: Dictionary = store.load_recipe(saved.recipe_path)
					check(reopened.ok and Data.fingerprint(reopened.attachments_snapshot) == Data.fingerprint(snapshot), "磁盘重开仍保留每段接缝、位置与选型")
			check(Data.validate(snapshot).is_empty(), "接长仍使用兼容的已装外挂格式 " + type_id)
			var loaded: Dictionary = Data.build(snapshot)
			check(loaded.ok, "接长快照可信重建 " + type_id)
			if loaded.ok:
				check(Data.fingerprint(Data.capture(loaded.root)) == Data.fingerprint(snapshot), "重开保持接缝变换 " + type_id)
				loaded.root.free()
			controller.cancel_arm()
			var total: int = layer.get_child_count()
			check(not controller.chain_active and input.ghost == null and layer.get_child_count() == total, "退出只清预览并保留已确认段 " + type_id)
			history.undo()
			check(layer.get_child_count() == total - 1, "一键只撤销最后一段 " + type_id)
			history.redo()
			check(layer.get_child_count() == total, "重做找回刚撤的段 " + type_id)

func probe_mount_range(controller: Node) -> void:
	# 仅记离散测点，不把抽样边界宣传为连续可挂范围。
	var wall_hits: Array[Dictionary] = []
	var roof_hits: Array[Dictionary] = []
	for y_step: int in range(1, 10):
		for x_step: int in range(-12, 13):
			var origin := Vector3(x_step * 0.5, y_step * 0.5, 16)
			var hit: Dictionary = Surface.raycast(controller.host_asset, origin, Vector3.FORWARD, "wall")
			if hit.ok and hit.position.z > 3.0: wall_hits.append(hit)
	for z_step: int in range(-9, 10):
		for x_step: int in range(-12, 13):
			var origin := Vector3(x_step * 0.5, 20, z_step * 0.5)
			var hit: Dictionary = Surface.raycast(controller.host_asset, origin, Vector3.DOWN, "roof")
			if hit.ok: roof_hits.append(hit)
	mount_report.facade_ray_hits = wall_hits.size()
	mount_report.roof_ray_hits = roof_hits.size()
	for type_id: String in ["sign_fascia", "awning_slope", "awning_barrel", "canopy_entry", "satellite_dish", "tank_tower_cone"]:
		var mode := "wall" if type_id in ["sign_fascia", "awning_slope", "awning_barrel"] else "roof"
		var hits := wall_hits if mode == "wall" else roof_hits
		controller.set_mount_options(mode)
		var types: Dictionary = {}
		var configurations: Array[String] = ["1.0", "0.75"]
		if type_id == "sign_fascia": configurations.append("0.75_narrow")
		for configuration: String in configurations:
			var recipe: Dictionary = Recipe.defaults(type_id)
			recipe.scale = 1.0 if configuration == "1.0" else 0.75
			if configuration == "0.75_narrow": recipe.dimensions.width = float(recipe.dimensions.width) * 0.75
			var count := 0
			var sample := ""
			var rejected: Dictionary = {}
			for hit: Dictionary in hits:
				var result: Dictionary = controller.validate_installation(recipe, hit)
				if result.ok:
					count += 1
					if sample.is_empty(): sample = str(hit.position)
				else:
					rejected[result.reason] = int(rejected.get(result.reason, 0)) + 1
			types[configuration] = {"accepted": count, "example": sample, "rejected": rejected}
		mount_report[type_id] = {"mode": mode, "step_m": 0.5, "results": types}

func test_invalid(snapshot: Dictionary) -> void:
	var cases: Dictionary = {}
	var bad := snapshot.duplicate(true)
	bad.schema_version = 2
	cases.future = bad
	bad = snapshot.duplicate(true)
	bad.instances.append(bad.instances[0].duplicate(true))
	cases.duplicate = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].transform[9] = INF
	cases.nonfinite = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment.anchor = {"mode": "not_a_surface", "local_position": ["bad"]}
	cases.malformed_anchor = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment = false
	cases.false_metadata = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment.script = "res://outputs/never_execute.gd"
	cases.script_reference = bad
	bad = snapshot.duplicate(true)
	bad.instances[0].sea_attachment.scene_path = "res://outputs/never_execute.tscn"
	cases.bad_scene = bad
	for key: String in cases:
		check(not Data.validate(cases[key]).is_empty(), "拒绝非法快照：" + key)
		var built: Dictionary = Data.build(cases[key])
		check(not built.ok and built.root == null, "非法快照不构造节点：" + key)
		if built.get("root") != null: built.root.free()

func test_store(snapshot: Dictionary) -> void:
	var store := Store.new()
	var recipe: Dictionary = HouseRecipe.authoring_defaults()
	recipe.building_id = "attachment_empty" if snapshot.instances.is_empty() else "attachment_logic"
	recipe.floors = 1
	var catalog: Dictionary = HouseCatalog.definitions().duplicate(true)
	var saved: Dictionary = store.export_work_revision(recipe, catalog, snapshot, BASE)
	check(saved.ok, "新作品八件原子保存：" + str(saved.get("reason", "")))
	if not saved.ok:
		var parser := JSON.new()
		parser.parse(JSON.stringify(snapshot, "\t"))
		print("[workshop-attachments-diagnostic] JSON差异 ", JSON.stringify(json_differences(snapshot, parser.data)))
		return
	var directory := str(saved.directory)
	var original := file_hashes(directory)
	check(original.size() == 8, "revision恰好固定八件")
	var loaded: Dictionary = store.load_recipe(saved.recipe_path)
	check(loaded.ok, "完整作品重新打开：" + str(loaded.get("reason", "")))
	if loaded.ok:
		check(Data.fingerprint(loaded.attachments_snapshot) == Data.fingerprint(snapshot), "JSON姿态与文本严格往返一致")
		check(not loaded.recipe.has("attachments") and not loaded.recipe.has("attachment_snapshot"), "外挂不进入房屋Recipe")
	var wrapper := FileAccess.get_file_as_string(saved.work_scene_path)
	check(not wrapper.contains(".tmp") and not wrapper.contains("res://") and not wrapper.contains("/Users/"), "wrapper只用同目录相对引用")
	var packed := ResourceLoader.load(saved.work_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(packed != null, "最终目录wrapper真实重载")
	if packed != null:
		var root := packed.instantiate()
		check(root.get_child_count() == 2 and root.has_node("Asset") and root.has_node("Attachments"), "wrapper原生双层")
		var attachments := root.get_node("Attachments") as Node3D
		attachments.scene_file_path = ""
		check(store._static_snapshot_matches(Data.capture(attachments), snapshot), "静态场景姿态和英文一致")
		check(root.find_children("*", "CollisionShape3D", true, false).size() > 0, "保存作品保留真实碰撞")
		check(no_scripts(root), "重开作品全树无重建脚本")
		root.free()
	for fail_file: String in ["building.recipe.json", "catalog_snapshot.json", "building.attachments.json", "candidate_manifest.json", "ledger.json"]:
		for after: bool in [false, true]:
			var failing := FailingStore.new()
			failing.fail_file = fail_file
			failing.fail_after_write = after
			var result: Dictionary = failing.export_work_revision(recipe, catalog, snapshot, BASE)
			check(not result.ok, "注入写失败拒绝：%s/%s" % [fail_file, after])
			check(DirAccess.get_directories_at(directory.get_base_dir()) == PackedStringArray(["revision_0001"]), "失败清理八件且不留最新半revision：%s/%s" % [fail_file, after])
			check(file_hashes(directory) == original, "失败不覆盖旧版：%s/%s" % [fail_file, after])
	var manifest_path := directory.path_join("candidate_manifest.json")
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var manifest: Dictionary = JSON.parse_string(manifest_text)
	for name: String in ["building.attachments.json", "building.attachments.tscn", "building.work.tscn", "candidate_manifest.json"]:
		var path := directory.path_join(name)
		var old := FileAccess.get_file_as_bytes(path)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".held"))
		check(not store.load_recipe(saved.recipe_path).ok, "新作品缺文件必须拒绝：" + name)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".held"), ProjectSettings.globalize_path(path))
		write_text(path, "{bad json" if name.ends_with(".json") else "malformed scene that must never execute")
		check(not store.load_recipe(saved.recipe_path).ok, "新作品损坏文件必须拒绝：" + name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(old)
		file.close()
	var future := manifest.duplicate(true)
	future.schema_version = 999
	write_text(manifest_path, JSON.stringify(future))
	check(not store.load_recipe(saved.recipe_path).ok, "未来manifest不降级")
	write_text(manifest_path, manifest_text)
	var legacy_recipe := recipe.duplicate(true)
	legacy_recipe.building_id = str(recipe.building_id) + "_legacy"
	var legacy: Dictionary = store.export_revision(legacy_recipe, catalog, BASE)
	check(legacy.ok, "legacy五件仍可导出")
	if legacy.ok:
		var reopened: Dictionary = store.load_recipe(legacy.recipe_path)
		check(reopened.ok and reopened.attachments_snapshot.instances.is_empty(), "legacy仅五件合法为空外挂")
		write_text(str(legacy.directory).path_join("building.attachments.json"), JSON.stringify(snapshot))
		check(not store.load_recipe(legacy.recipe_path).ok, "legacy未声明旁车拒绝")
	check(file_hashes(directory) == original, "所有负例恢复后旧版八件字节不变")

func static_owned(node: Node, root: Node) -> bool:
	if node.get_script() != null or not node.scene_file_path.is_empty(): return false
	if node != root and node.owner != root: return false
	for child: Node in node.get_children():
		if not static_owned(child, root): return false
	return true

func no_scripts(node: Node) -> bool:
	if node.get_script() != null: return false
	for child: Node in node.get_children():
		if not no_scripts(child): return false
	return true

func file_hashes(directory: String) -> Dictionary:
	var hashes: Dictionary = {}
	for name: String in DirAccess.get_files_at(directory): hashes[name] = FileAccess.get_sha256(directory.path_join(name))
	return hashes

func json_differences(a: Variant, b: Variant, path: String = "snapshot") -> Array:
	var differences: Array = []
	if a is Dictionary and b is Dictionary:
		for key: Variant in a:
			differences.append_array(json_differences(a[key], b.get(key), path + "." + str(key)))
	elif a is Array and b is Array:
		for index: int in mini(a.size(), b.size()): differences.append_array(json_differences(a[index], b[index], path + "[%d]" % index))
	elif a != b:
		differences.append({"path": path, "before": str(a), "after": str(b), "delta": float(a) - float(b) if (a is float or a is int) and (b is float or b is int) else ""})
	return differences

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
