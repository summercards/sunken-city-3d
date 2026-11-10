@tool
extends RefCounted

const SELF_PATH: String = "res://addons/building_workshop/editor_verification.gd"
const OUTPUT_ROOT: String = "res://outputs/workshop_editor"
const REPORT_PATH: String = "res://outputs/workshop_editor_report.json"
const COMPONENT_ROOT: String = "res://scenes/components/workshop_modules"
const SAMPLE_PATH: String = "res://data/workshop/samples/workshop_sample_001.recipe.json"
const Recipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")

var _shell_samples: Array[Dictionary] = []
var _legacy_check_count: int = 0

var _plugin: EditorPlugin
var _screen: Control
var _store: Object
var _adapter: Object
var _tree: SceneTree
var _checks: Array[Dictionary] = []
var _failures: Array[String] = []
var _artifacts: Array[String] = []
var _build_ids: Array[String] = []
var _dependencies: Array[String] = []
var _edited_root: Node
var _edited_transform: Variant
var _paused: bool = false
var _scene_unchanged: bool = false
var _isolation_ok: bool = false

# 仅由真实编辑器中的 plugin.gd 在主线程 await；不是 --script 入口。
static func run(plugin: EditorPlugin) -> void:
	if not Engine.is_editor_hint() or not OS.get_cmdline_user_args().has("--workshop-editor-verify"):
		return
	var script: Script = load(SELF_PATH) as Script
	var verifier: RefCounted = script.new() as RefCounted
	await verifier.call("_execute", plugin)

func _execute(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_tree = plugin.get_tree()
	_paused = _tree.paused
	_edited_root = EditorInterface.get_edited_scene_root()
	_edited_transform = _root_transform(_edited_root)
	_check("editor_hint", Engine.is_editor_hint())
	_check("主线程", OS.get_thread_caller_id() == OS.get_main_thread_id())
	_check("启动时未运行场景", not EditorInterface.is_playing_scene())
	_isolation_ok = _verify_isolation()
	if not _isolation_ok:
		_finish()
		return
	for frame: int in range(3):
		await _tree.process_frame
	_screen = _property(plugin, "screen") as Control
	_store = _property(plugin, "store") as Object
	_adapter = _property(plugin, "adapter") as Object
	if not _check("插件实际主屏", is_instance_valid(_screen) and _screen.is_inside_tree()):
		_dependencies.append("plugin.screen: 已进入编辑器树的 editor_screen Control")
		_finish()
		return
	var ready: bool = _require_methods(_screen, ["configure", "apply_parameters", "save_building", "open_recipe", "refresh_preview", "snapshot", "has_pending_fields", "select_slot", "get_recovery", "restore_recovery"], "screen")
	ready = _require_methods(_store, ["load_recipe", "export_revision", "list_documents"], "plugin.store") and ready
	ready = _require_methods(plugin, ["_make_visible", "_has_main_screen", "_get_plugin_name"], "plugin") and ready
	if not ready:
		_finish()
		return
	# 只覆盖导出根；保留插件注入的 open_scene / rescan / replace_component 等真实端口。
	_screen.call("configure", {"store": _store, "export_root": OUTPUT_ROOT})
	_plugin.call("_make_visible", true)
	EditorInterface.set_main_screen_editor("楼房工坊")
	await _tree.process_frame
	_check("主屏名称", str(_plugin.call("_get_plugin_name")) == "楼房工坊")
	_check("主屏声明", bool(_plugin.call("_has_main_screen")))
	_check("真实编辑器主屏可见", _screen.is_visible_in_tree() and EditorInterface.get_base_control().is_ancestor_of(_screen))
	_check("隔离导出根已注入", str(_property(_screen, "export_root")) == OUTPUT_ROOT)
	var ports: Dictionary = _dictionary(_property(_screen, "_ports"))
	for port: String in ["open_scene", "rescan", "replace_component"]:
		var callback: Callable = ports.get(port, Callable())
		_check("真实端口：" + port, callback.is_valid())
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var buttons: Dictionary = _dictionary(_property(_screen, "buttons"))
	_check("实际 controls 非空", not controls.is_empty(), str(controls.keys()))
	_check("实际 buttons 非空", not buttons.is_empty(), str(buttons.keys()))
	var session: Object = _property(_screen, "session") as Object
	if not _require_methods(session, ["snapshot", "accept_loaded", "apply_patch", "is_dirty"], "screen.session"):
		_finish()
		return
	var sample: Dictionary = _read_json(SAMPLE_PATH)
	var catalog: Dictionary = _dictionary(_property(session, "catalog"))
	var accepted: Dictionary = _result(session, "accept_loaded", [sample, catalog])
	if not _check_result("版本化样例配方", accepted):
		_finish()
		return
	_screen.call("configure", {})
	var original: Dictionary = _snapshot()
	var invalid: Dictionary = _result(session, "apply_patch", [{"width": -1.0}])
	_check("非法配方原子拒绝", not bool(invalid.get("ok", false)) and _same(original, _snapshot()), str(invalid))
	var building_id: String = "editor_verify_%s_%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	_build_ids.append(building_id)
	if not _set_text("building_id", building_id) or not _set_text("display_name", "编辑器验收楼房"):
		_finish()
		return
	for spec: Array in [["width", 15.0], ["depth", 9.0], ["floors", 3.0], ["taper", 0.0], ["damage", 0.0], ["vegetation_density", 0.0]]:
		if not _set_spin(str(spec[0]), float(spec[1])):
			_finish()
			return
	if not _check_result("真实 UI 应用 simple15", _result(_screen, "apply_parameters")):
		_finish()
		return
	_check("simple15 宽度进入配方", is_equal_approx(float(_snapshot().get("width", 0.0)), 15.0))
	var simple15: Dictionary = _snapshot()
	_emit_button("undo")
	_check("同 session 撤销 simple15", _property(_screen, "session") == session and _same(_snapshot(), original))
	_emit_button("redo")
	_check("同 session 重做 simple15", _property(_screen, "session") == session and _same(_snapshot(), simple15))
	_test_overrides()
	_test_preview()
	print("[workshop-editor-stage] component replacement")
	_test_components(session)
	print("[workshop-editor-stage] saving revisions")
	# 组件操作后用真实 configure 同步绑定下拉框，不能让旧 UI 覆盖新槽位绑定。
	_screen.call("configure", {})
	var first: Dictionary = _result(_screen, "save_building")
	var second: Dictionary = {}
	if _check_result("第一次真实保存", first):
		print("[workshop-editor-stage] verify first bundle")
		_verify_bundle(first, "revision1")
		print("[workshop-editor-stage] first bundle verified")
		var first_hashes: Dictionary = _bundle_hashes(str(first.get("directory", "")))
		_set_spin("width", 15.0)
		# 不改变替件所需尺寸；第二次保存同配方仍必须产生独立 revision。
		second = _result(_screen, "save_building")
		if _check_result("第二次真实保存", second):
			print("[workshop-editor-stage] verify second bundle")
			_verify_bundle(second, "revision2")
			print("[workshop-editor-stage] second bundle verified")
			var first_recipe: Dictionary = _dictionary(first.get("recipe", {}))
			var second_recipe: Dictionary = _dictionary(second.get("recipe", {}))
			_check("同建筑连续两个 revision", str(first_recipe.get("building_id", "")) == building_id and str(second_recipe.get("building_id", "")) == building_id and int(second_recipe.get("revision", -1)) == int(first_recipe.get("revision", -3)) + 1 and first.get("directory") != second.get("directory"))
			_check("旧 revision 内容不变", _same(first_hashes, _bundle_hashes(str(first.get("directory", "")))))
			_check("保存同步 clean 状态", not bool(session.call("is_dirty")) and not bool(_screen.call("has_pending_fields")))
			print("[workshop-editor-stage] reopen saved recipe")
			var opened: Dictionary = _result(_screen, "open_recipe", [str(second.get("recipe_path", ""))])
			print("[workshop-editor-stage] reopened recipe")
			_check_result("主屏重新打开已保存配方", opened)
			_check("打开配方后仍为原 session", _property(_screen, "session") == session)
			print("[workshop-editor-stage] test dirty recovery")
			await _test_recovery(str(first.get("recipe_path", "")), session)
			print("[workshop-editor-stage] dirty recovery finished")
	else:
		_check("第二版本及保存后 dirty 验证", false, "首次保存失败，不能用模拟 Store 代替")
	print("[workshop-editor-stage] lifecycle and screenshots")
	await _test_lifecycle()
	await _capture(Vector2i(1280, 800))
	await _capture(Vector2i(1600, 1000))
	# 门窗页通过真实 OptionButton 信号切换，额外核对局部覆盖控件布局。
	var picker: OptionButton = _property(_screen, "_page_picker") as OptionButton
	if picker != null and picker.item_count > 1:
		picker.select(1)
		picker.item_selected.emit(1)
		await _tree.process_frame
		await _capture(Vector2i(1600, 1000), "_floor_facade")
	# 旧破旧L形仅作 modular_v1 兼容证据，不代表新的连续外壳成品。
	var sample_recipe: Dictionary = _read_json("res://data/workshop/samples/workshop_sample_002.recipe.json")
	var sample_session: Object = _property(_screen, "session") as Object
	var source_catalog: Dictionary = (load("res://src/workshop/catalog.gd") as Script).definitions()
	_check_result("编辑器载入破旧生态样例", _result(sample_session, "accept_loaded", [sample_recipe, source_catalog]))
	_screen.call("configure", {})
	_check_result("破旧生态样例真实生成", _result(_screen, "refresh_preview"))
	var sample_preview: Object = _property(_screen, "preview") as Object
	sample_preview.call("set_view", "perspective")
	await _capture(Vector2i(1600, 1000), "_damaged_l_plants")
	_legacy_check_count = _checks.size()
	await _test_shell_samples()
	_finish()

func _test_shell_samples() -> void:
	print("[workshop-editor-stage] continuous shell samples")
	var session: Object = _property(_screen, "session") as Object
	var preview: Control = _property(_screen, "preview") as Control
	if not _require_methods(preview, ["set_view", "capture_model_image"], "shell.preview"):
		return
	var catalog: Dictionary = Catalog.definitions()
	var token: String = "%s_%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	for shape: String in ["rectangle", "l"]:
		var recipe: Dictionary = Recipe.authoring_defaults()
		_check("新创作默认连续实体", str(recipe.get("construction_mode", "")) == "shell_v2")
		var sample_key: String = "rect" if shape == "rectangle" else "l"
		var building_id: String = "shell_%s_%s" % [sample_key, token]
		recipe["building_id"] = building_id
		recipe["shape"] = shape
		if shape == "l":
			recipe["width"] = 12.0
			recipe["depth"] = 12.0
		_build_ids.append(building_id)
		if not _check_result(sample_key + " 连续实体载入默认配方与原始Catalog", _result(session, "accept_loaded", [recipe, catalog])):
			continue
		_screen.call("configure", {"export_root": OUTPUT_ROOT})
		var built: Dictionary = _result(_screen, "refresh_preview")
		if not _check_result(sample_key + " 主屏真实连续生成", built):
			continue
		_check(sample_key + " shell独立配方没有继承legacy覆盖", str(_snapshot().get("construction_mode", "")) == "shell_v2" and str(_snapshot().get("building_id", "")) == building_id and _dictionary(_snapshot().get("slot_overrides", {})).is_empty() and _dictionary(_snapshot().get("floor_overrides", {})).is_empty())
		var model: Node3D = _property(preview, "_model_root") as Node3D
		var root: Node3D = model.get_child(0) as Node3D if model != null and model.get_child_count() == 1 else null
		var audit: Dictionary = _verify_shell_geometry(root, recipe, sample_key)
		_test_shell_surface_selection(preview, root, built.get("openings", []), sample_key)
		var saved_shell: Dictionary = _result(_screen, "save_building")
		if _check_result(sample_key + " 连续模型五件静态烘焙", saved_shell):
			_verify_bundle(saved_shell, "shell_" + sample_key)
		var artifact_start: int = _artifacts.size()
		preview.call("set_view", "perspective")
		if shape == "rectangle":
			await _capture(Vector2i(1600, 1000), "_continuous_rect")
			await _capture_shell_model(preview, "rect")
			preview.call("set_view", "front")
			await _capture(Vector2i(1600, 1000), "_continuous_front")
			await _capture_shell_model(preview, "front")
			preview.call("set_view", "back")
			await _capture(Vector2i(1600, 1000), "_continuous_back")
		else:
			preview.call("set_view", "top")
			await _capture(Vector2i(1600, 1000), "_continuous_l_top")
			preview.call("set_view", "perspective")
			await _capture(Vector2i(1600, 1000), "_continuous_l")
			await _capture_shell_model(preview, "l")
		var sample_artifacts: Array[String] = []
		for index: int in range(artifact_start, _artifacts.size()):
			sample_artifacts.append(_artifacts[index])
		_shell_samples.append({"building_id": building_id, "recipe": _snapshot(), "actual_geometry": audit, "artifacts": sample_artifacts, "source": "真实主屏session.accept_loaded + refresh_preview；模型图为同一预览世界的独立离屏渲染，不是完整编辑器截图"})

func _test_shell_surface_selection(preview: Control, root: Node3D, openings: Array, label: String) -> void:
	for opening: Dictionary in openings:
		if str(opening.get("type", "")) != "window":
			continue
		var origin: Vector3 = root.global_transform * (opening.center + opening.outward * 1.0)
		var direction: Vector3 = -(root.global_transform.basis * (opening.outward as Vector3)).normalized()
		var suffix: String = str(opening.id).trim_prefix("opening_")
		var wall: Dictionary = {"node_path": "GeneratedVisual/wall_shell_" + str(opening.floor)}
		var glass: Dictionary = {"node_path": "GeneratedVisual/glass_" + suffix}
		var wall_hit: float = float(preview.call("_ray_slot_surface", wall, origin, direction))
		var glass_hit: float = float(preview.call("_ray_slot_surface", glass, origin, direction))
		_check(label + " 点击洞口不先选中整层AABB", glass_hit > 0.0 and (wall_hit < 0.0 or glass_hit < wall_hit))
		break

func _capture_shell_model(preview: Control, label: String) -> void:
	var image: Image = (await preview.call("capture_model_image", Vector2i(1400, 1100))) as Image
	if not _check(label + " 真实离屏模型图1400x1100", image != null and not image.is_empty() and image.get_size() == Vector2i(1400, 1100)):
		return
	var model: Node3D = _property(preview, "_model_root") as Node3D
	var view_camera: Camera3D = _property(preview, "camera") as Camera3D
	_check(label + " 模型原始相机与阴影保留", model != null and view_camera != null and _shadow_enabled(preview))
	# 从真实像素测量主体，不把1400px画布等同于600px模型。
	var background: Color = image.get_pixel(0, 0)
	var left: int = image.get_width()
	var right: int = -1
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if maxf(absf(pixel.r - background.r), maxf(absf(pixel.g - background.g), absf(pixel.b - background.b))) > 0.08:
				left = mini(left, x)
				right = maxi(right, x)
	_check(label + " 模型实际像素宽度至少600", right - left + 1 >= 600, "实际前景宽度：%dpx" % maxi(0, right - left + 1))
	var path: String = "res://outputs/workshop_shell_model_%s.png" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	if _check(label + " 模型大图落盘", image.save_png(path) == OK):
		_artifacts.append(path)

func _shadow_enabled(preview: Control) -> bool:
	var world: Node3D = _property(preview, "_world") as Node3D
	if world == null:
		return false
	for node: Node in world.get_children():
		if node is DirectionalLight3D and (node as DirectionalLight3D).shadow_enabled:
			return true
	return false

func _verify_shell_geometry(root: Node3D, recipe: Dictionary, label: String) -> Dictionary:
	if not _check(label + " 实际连续生成根", root != null and str(root.get_meta("generator_version", "")) == "sea_workshop_continuous_shell_v2" and str(root.get_meta("construction_mode", "")) == "shell_v2"):
		return {}
	var visual: Node3D = root.get_node_or_null("GeneratedVisual") as Node3D
	if not _check(label + " 实际可视几何分支", visual != null):
		return {}
	var walls: int = 0
	var slabs: int = 0
	var roofs: int = 0
	var frames: int = 0
	var glasses: int = 0
	var forbidden: Array[String] = []
	var topology: Dictionary = {}
	for node: Node in visual.get_children():
		var id: String = str(node.name)
		if id.begins_with("wall_shell_"):
			walls += 1
		elif id.begins_with("slab_"):
			slabs += 1
		elif id == "roof_main":
			roofs += 1
		elif id.begins_with("frame_"):
			frames += 1
		elif id.begins_with("glass_"):
			glasses += 1
		else:
			forbidden.append(id)
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if not _check(label + " 整件真实ArrayMesh：" + id, mesh_node != null and mesh_node.mesh is ArrayMesh and mesh_node.get_child_count() == 0):
			continue
		var faces: PackedVector3Array = mesh_node.mesh.get_faces()
		var audit: Dictionary = _audit_shell_faces(faces)
		topology[id] = audit
		_check(label + " 实际三角面单连通闭合且定向：" + id, bool(audit.get("closed", false)) and bool(audit.get("oriented", false)) and int(audit.get("connected_components", 0)) == 1, str(audit))
	var run_lengths: Array[float] = [float(recipe.width), float(recipe.depth), float(recipe.width), float(recipe.depth)]
	if str(recipe.shape) == "l":
		run_lengths = [float(recipe.width), float(recipe.depth) * 0.5, float(recipe.width) * 0.5, float(recipe.depth) * 0.5, float(recipe.width) * 0.5, float(recipe.depth)]
	var openings_per_floor: int = 0
	for run_length: float in run_lengths:
		openings_per_floor += maxi(1, floori(run_length / float(recipe.bay_width)))
	var expected_frames: int = openings_per_floor * int(recipe.floors)
	_check(label + " 实际整框与玻璃数量", frames == expected_frames and glasses == expected_frames - 1, "frame=%d glass=%d expected_frame=%d" % [frames, glasses, expected_frames])
	_check(label + " 每层一墙壳一整板及一个整屋顶", walls == int(recipe.floors) and slabs == int(recipe.floors) and roofs == 1, "wall=%d slab=%d roof=%d" % [walls, slabs, roofs])
	_check(label + " 无legacy屋顶cell或外凸柱及分段墙", forbidden.is_empty(), str(forbidden))
	var height: float = float(recipe.floor_height) * int(recipe.floors)
	var width: float = float(recipe.width)
	var depth: float = float(recipe.depth)
	for floor_index: int in range(int(recipe.floors)):
		var wall: MeshInstance3D = visual.get_node_or_null("wall_shell_%d" % floor_index) as MeshInstance3D
		if not _check(label + " 实际楼层墙壳：%d" % floor_index, wall != null and wall.mesh != null):
			continue
		var faces: PackedVector3Array = wall.mesh.get_faces()
		var transform: Transform3D = _relative_transform(wall, root)
		var untapered: AABB = AABB()
		var initialized: bool = false
		for index: int in range(faces.size()):
			faces[index] = transform * faces[index]
			var point: Vector3 = faces[index]
			var scale: float = 1.0 - float(recipe.taper) * clampf(point.y / height, 0.0, 1.0)
			point = Vector3(point.x / scale, point.y, point.z / scale)
			untapered = untapered.expand(point) if initialized else AABB(point, Vector3.ZERO)
			initialized = true
		_check(label + " 整栋统一taper墙壳包络：%d" % floor_index, initialized and absf(untapered.position.x + width * 0.5) < 0.0001 and absf(untapered.end.x - width * 0.5) < 0.0001 and absf(untapered.position.z + depth * 0.5) < 0.0001 and absf(untapered.end.z - depth * 0.5) < 0.0001)
		# 独立按配方推导正立面洞心，不信任openings/topology元数据。
		var bays: int = maxi(1, floori(width / float(recipe.bay_width)))
		for bay: int in range(bays):
			var is_door: bool = floor_index == 0 and bay == int((bays - 1) / 2)
			var y: float = float(recipe.floor_height) * floor_index + (float(recipe.door_height) * 0.5 if is_door else float(recipe.window_sill) + float(recipe.window_height) * 0.5)
			var scale: float = 1.0 - float(recipe.taper) * y / height
			var x: float = (-width * 0.5 + width * (float(bay) + 0.5) / bays) * scale
			var center: Vector3 = Vector3(x, y, -depth * 0.5 * scale)
			_check(label + " 墙壳真实贯穿门窗：%d/%d" % [floor_index, bay], not _shell_segment_hit(faces, center + Vector3.FORWARD, center + Vector3.BACK))
		var solid_y: float = float(recipe.floor_height) * floor_index + float(recipe.floor_height) - float(recipe.slab_thickness) - 0.1
		var solid_scale: float = 1.0 - float(recipe.taper) * solid_y / height
		var solid: Vector3 = Vector3(0.0, solid_y, -depth * 0.5 * solid_scale)
		_check(label + " 洞外实际墙面存在：%d" % floor_index, _shell_segment_hit(faces, solid + Vector3.FORWARD, solid + Vector3.BACK))
	if str(recipe.shape) == "l":
		for node: Node in visual.get_children():
			if not str(node.name).begins_with("slab_") and str(node.name) != "roof_main":
				continue
			var slab: MeshInstance3D = node as MeshInstance3D
			if slab == null or slab.mesh == null:
				continue
			var faces: PackedVector3Array = slab.mesh.get_faces()
			var transform: Transform3D = _relative_transform(slab, root)
			for index: int in range(faces.size()):
				faces[index] = transform * faces[index]
			_check(label + " L缺口实际无板面：" + str(node.name), not _shell_segment_hit(faces, Vector3(width * 0.25, -1.0, depth * 0.25), Vector3(width * 0.25, height + 1.0, depth * 0.25)))
	return {"geometry": _geometry(root), "wall_shells": walls, "slabs": slabs, "roofs": roofs, "actual_mesh_topology": topology, "generator_topology_auxiliary_only": _dictionary(root.get_meta("quality", {})).get("topology", {})}

func _audit_shell_faces(faces: PackedVector3Array) -> Dictionary:
	var edges: Dictionary = {}
	var adjacency: Dictionary = {}
	var valid: bool = not faces.is_empty() and faces.size() % 3 == 0
	for index: int in range(0, faces.size() - 2, 3):
		valid = valid and faces[index].is_finite() and faces[index + 1].is_finite() and faces[index + 2].is_finite() and (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length_squared() > 0.000000000001
		for edge: int in range(3):
			var a: Vector3i = Vector3i((faces[index + edge] * 100000.0).round())
			var b: Vector3i = Vector3i((faces[index + (edge + 1) % 3] * 100000.0).round())
			if not adjacency.has(a):
				adjacency[a] = []
			if not adjacency.has(b):
				adjacency[b] = []
			(adjacency[a] as Array).append(b)
			(adjacency[b] as Array).append(a)
			var forward: bool = str(a) < str(b)
			var key: String = "%s:%s" % [str(a), str(b)] if forward else "%s:%s" % [str(b), str(a)]
			var count: Vector2i = edges.get(key, Vector2i.ZERO)
			count.x += 1
			count.y += 1 if forward else -1
			edges[key] = count
	var boundary: int = 0
	var nonmanifold: int = 0
	var orientation: int = 0
	for raw: Variant in edges.values():
		var count: Vector2i = raw
		if count.x == 1:
			boundary += 1
		elif count.x != 2:
			nonmanifold += 1
		if count.y != 0:
			orientation += 1
	var visited: Dictionary = {}
	var components: int = 0
	for raw: Variant in adjacency:
		var vertex: Vector3i = raw
		if visited.has(vertex):
			continue
		components += 1
		var pending: Array[Vector3i] = [vertex]
		visited[vertex] = true
		while not pending.is_empty():
			var current: Vector3i = pending.pop_back()
			for neighbor: Vector3i in adjacency[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
	return {"closed": valid and boundary == 0 and nonmanifold == 0, "oriented": valid and orientation == 0, "connected_components": components, "boundary_edges": boundary, "nonmanifold_edges": nonmanifold, "orientation_errors": orientation, "triangles": int(faces.size() / 3)}

func _shell_segment_hit(faces: PackedVector3Array, start: Vector3, end: Vector3) -> bool:
	for index: int in range(0, faces.size() - 2, 3):
		if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null:
			return true
	return false

func _verify_isolation() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	var cli_ok: bool = args.has("--editor") and not args.has("--script") and not args.has("-s")
	_check("真实 --editor 非 --script", cli_ok, str(args))
	var no_autoload: bool = true
	for entry: Dictionary in ProjectSettings.get_property_list():
		if str(entry.get("name", "")).begins_with("autoload/"):
			no_autoload = false
	_check("隔离项目没有 Autoload", no_autoload)
	var no_main: bool = str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty()
	_check("隔离项目没有 Main 入口", no_main)
	var enabled: PackedStringArray = PackedStringArray(ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()))
	var only_plugin: bool = enabled.size() == 1 and enabled[0] == "res://addons/building_workshop/plugin.cfg"
	_check("只启用楼房工坊插件", only_plugin, str(enabled))
	var copy_path: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var isolated_copy: bool = copy_path != "d:/projects/sea/godot"
	_check("fixture 只能写隔离副本", isolated_copy, copy_path)
	var no_main_node: bool = true
	var stack: Array[Node] = [_tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script() as Script
		if node.name == &"Main" or (script != null and script.resource_path == "res://src/bootstrap/main.gd"):
			no_main_node = false
		for child: Node in node.get_children():
			stack.append(child)
	_check("编辑器树没有启动 Main", no_main_node)
	return cli_ok and no_autoload and no_main and only_plugin and isolated_copy and no_main_node

func _test_overrides() -> void:
	var base_width: float = float(_snapshot().get("width", 0.0))
	_set_spin("width", base_width + 0.5)
	_set_spin("floor_override_index", 0.0)
	_set_spin("floor_override_height", 5.5)
	_emit_button("floor_apply")
	var floors: Dictionary = _dictionary(_snapshot().get("floor_overrides", {}))
	var floor_zero: Dictionary = _dictionary(floors.get("0", {}))
	_check("真实楼层按钮应用覆盖", is_equal_approx(float(floor_zero.get("floor_height", 0.0)), 5.5))
	_check("局部按钮不吞未应用宽度", is_equal_approx(_spin("width"), base_width + 0.5) and is_equal_approx(float(_snapshot().get("width", 0.0)), base_width))
	_set_spin("width", base_width)
	_set_spin("facade_width", 1.2)
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var facade_picker: OptionButton = controls.get("facade_index") as OptionButton
	if not _check("实际立面下拉控件", facade_picker != null and facade_picker.selected >= 0):
		return
	var facade: String = str(facade_picker.get_item_metadata(facade_picker.selected))
	_emit_button("facade_apply")
	var facades: Dictionary = _dictionary(_snapshot().get("facade_overrides", {}))
	_check("真实立面按钮应用覆盖", is_equal_approx(float(_dictionary(facades.get(facade, {})).get("width", 0.0)), 1.2))
	_check_result("覆盖后全部参数可应用", _result(_screen, "apply_parameters"))

func _test_preview() -> void:
	_check_result("真实预览生成", _result(_screen, "refresh_preview"))
	var preview: Control = _property(_screen, "preview") as Control
	if not _check("独立编辑器预览", preview != null):
		return
	var viewport: SubViewport = _property(preview, "viewport") as SubViewport
	_check("预览 own_world_3d", viewport != null and viewport.own_world_3d and viewport.find_world_3d() != _tree.root.find_world_3d())
	var model: Node3D = _property(preview, "_model_root") as Node3D
	_check("真实模型几何存在", model != null and not model.find_children("*", "MeshInstance3D", true, false).is_empty())
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	for pair: Array in [["wireframe", "_wireframe_root"], ["collision_overlay", "_collision_root"]]:
		var toggle: CheckButton = controls.get(str(pair[0])) as CheckButton
		if not _check("实际覆盖开关：" + str(pair[0]), toggle != null):
			continue
		toggle.button_pressed = true
		var overlay: Node3D = _property(preview, str(pair[1])) as Node3D
		_check("实际覆盖几何：" + str(pair[0]), overlay != null and overlay.get_child_count() > 0)
		toggle.button_pressed = false
		_check("覆盖关闭清空：" + str(pair[0]), overlay != null and overlay.get_child_count() == 0)

func _test_components(session: Object) -> void:
	if not _require_methods(_adapter, ["export_slot", "apply_prefab"], "plugin.adapter"):
		_check("成功替件路径", false, "适配器缺失，不能仅凭拒绝路径宣告通过")
		return
	var preview: Object = _property(_screen, "preview") as Object
	var slots: Array = _property(preview, "_slots") as Array
	var wall: Dictionary = {}
	var differently_sized: bool = false
	for raw: Variant in slots:
		var slot: Dictionary = _dictionary(raw)
		if str(slot.get("kind", "")) == "wall":
			if wall.is_empty():
				wall = slot
			elif slot.get("component_id") == wall.get("component_id") and not _near_array(slot.get("size", []), wall.get("size", [])):
				differently_sized = true
	if not _check("墙组件覆盖多个不同尺寸槽", not wall.is_empty() and differently_sized):
		return
	var slot_id: String = str(wall.get("id", ""))
	var component_id: String = str(wall.get("component_id", ""))
	_screen.call("select_slot", slot_id)
	var module_button: Button = _dictionary(_property(_screen, "buttons")).get("export_module") as Button
	_check("单槽导出入口可发现且可操作", module_button != null and not module_button.disabled)
	var exported: Dictionary = _result(_screen, "export_module_component")
	if not _check_result("适配器导出真实墙 fixture", exported):
		return
	# 导出结果必须明确给出 prefab_path 或 scene_path；不猜测生成文件名。
	var path: String = str(exported.get("prefab_path", exported.get("scene_path", "")))
	if not _check("fixture 路径在隔离 scenes 下", _isolation_ok and path.begins_with(COMPONENT_ROOT + "/") and not path.contains("..") and path.ends_with(".tscn") and FileAccess.file_exists(path), str(exported)):
		_dependencies.append("adapter.export_slot 返回 prefab_path 或 scene_path")
		return
	_artifacts.append(path)
	if not str(exported.get("manifest_path", "")).is_empty():
		_artifacts.append(str(exported.manifest_path))
	var before: Dictionary = _snapshot()
	var catalog_before: Dictionary = _dictionary(_property(session, "catalog")).duplicate(true)
	var rejected: Dictionary = _result(_adapter, "apply_prefab", [session, component_id, path])
	var reason: String = str(rejected.get("reason", ""))
	var explicit_reason: bool = reason.contains("不兼容") or reason.to_lower().contains("incompat") or reason.contains("尺寸")
	_check("全局多尺寸替件明确拒绝且不改状态", not bool(rejected.get("ok", false)) and explicit_reason and _same(before, _snapshot()) and _same(catalog_before, _dictionary(_property(session, "catalog"))), str(rejected))
	if not _require_methods(_adapter, ["apply_prefab_to_slot"], "plugin.adapter"):
		_check("成功替件路径", false, "需要真实 apply_prefab_to_slot(session, slot_id, path)，验证器不直接改 catalog 伪造成功")
		return
	var applied: Dictionary = _result(_adapter, "apply_prefab_to_slot", [session, slot_id, path])
	if not _check_result("选中槽独立成功替件", applied):
		return
	var override: Dictionary = _dictionary(_dictionary(_snapshot().get("slot_overrides", {})).get(slot_id, {}))
	var clone_id: String = str(override.get("component_id", ""))
	var components: Dictionary = _dictionary(_dictionary(_property(session, "catalog")).get("components", {}))
	var clone: Dictionary = _dictionary(components.get(clone_id, {}))
	_check("成功替件创建独立 catalog ID", not clone_id.is_empty() and clone_id != component_id and str(clone.get("kind", "")) == "prefab" and str(clone.get("prefab", "")) == path)
	var before_overrides: Dictionary = _dictionary(before.get("slot_overrides", {}))
	var after_overrides: Dictionary = _dictionary(_snapshot().get("slot_overrides", {})).duplicate(true)
	after_overrides.erase(slot_id)
	before_overrides = before_overrides.duplicate(true)
	before_overrides.erase(slot_id)
	_check("替件不改变其他槽覆盖或原组件", _same(before_overrides, after_overrides) and _same(_dictionary(catalog_before.get("components", {})).get(component_id), components.get(component_id)))
	_check_result("成功替件后真实生成", _result(_screen, "refresh_preview"))
	var new_slots: Array = _property(preview, "_slots") as Array
	var selected_found: bool = false
	var unaffected: bool = true
	for raw: Variant in new_slots:
		var slot: Dictionary = _dictionary(raw)
		if str(slot.get("id", "")) == slot_id:
			selected_found = str(slot.get("component_id", "")) == clone_id and _near_array(slot.get("bounds_size", []), wall.get("bounds_size", []))
		elif str(slot.get("component_id", "")) == clone_id:
			unaffected = false
	_check("真实生成槽使用独立替件且尺寸不变", selected_found and unaffected)
	var model: Node3D = _property(preview, "_model_root") as Node3D
	var real_prefab: bool = false
	if model != null:
		for node: Node in model.find_children("*", "Node3D", true, false):
			if node.scene_file_path == path and str(node.get_meta("slot_id", "")) == slot_id:
				real_prefab = true
	_check("预览实际实例化替件 PackedScene", real_prefab, path)

func _test_recovery(other_recipe: String, session: Object) -> void:
	var saved: Dictionary = _snapshot()
	_set_spin("width", 15.5)
	_check("已保存后仅未 apply 宽度 spin 触发 dirty", not bool(session.call("is_dirty")) and bool(_screen.call("has_pending_fields")) and _same(saved, _snapshot()))
	_set_spin("floor_override_window_width", 1.3)
	var recovery: Dictionary = _result(_screen, "get_recovery")
	var guarded: Dictionary = _result(_screen, "open_recipe", [other_recipe])
	var confirm: ConfirmationDialog = _property(_screen, "_confirm") as ConfirmationDialog
	_check("未应用输入触发真实确认弹窗", bool(guarded.get("confirmation_required", false)) and confirm != null and confirm.visible)
	if confirm != null:
		# 发出真实按钮 pressed，不声称发生了鼠标点击；由新的 _cancel_discard 连接处理关闭。
		print("[workshop-editor-stage] cancelling dirty popup")
		confirm.get_cancel_button().pressed.emit()
		print("[workshop-editor-stage] popup cancelled ", confirm.visible)
		await _tree.process_frame
		print("[workshop-editor-stage] after popup frame")
		_check("取消关闭弹窗", not confirm.visible)
	_check("取消不丢基础和局部输入", _same(saved, _snapshot()) and is_equal_approx(_spin("width"), 15.5) and is_equal_approx(_spin("floor_override_window_width"), 1.3) and bool(_screen.call("has_pending_fields")))
	var action: Variant = _property(_screen, "_confirm_action")
	_check("取消清除待丢弃动作", action is Callable and not (action as Callable).is_valid())
	_set_spin("width", 14.0)
	_set_spin("floor_override_window_width", 1.1)
	var restored: Dictionary = _result(_screen, "restore_recovery", [recovery])
	_check_result("真实 recovery 恢复", restored)
	_check("恢复保留未提交输入与 session", _property(_screen, "session") == session and _same(saved, _snapshot()) and is_equal_approx(_spin("width"), 15.5) and is_equal_approx(_spin("floor_override_window_width"), 1.3) and bool(_screen.call("has_pending_fields")))

func _test_lifecycle() -> void:
	var old_screen: Control = _screen
	var preview: Object = _property(_screen, "preview") as Object
	var viewport: SubViewport = _property(preview, "viewport") as SubViewport
	var before_recovery: Dictionary = _result(_screen, "get_recovery")
	var before_snapshot: Dictionary = _snapshot()
	var lifecycle_root: Node = EditorInterface.get_edited_scene_root()
	var lifecycle_transform: Variant = _root_transform(lifecycle_root)
	var lifecycle_paused: bool = _tree.paused
	var before_session: Object = _property(_screen, "session") as Object
	var before_catalog: Dictionary = _dictionary(_property(before_session, "catalog")).duplicate(true)
	var before_pending: bool = bool(_screen.call("has_pending_fields"))
	var before_width: float = _spin("width")
	var before_floor_width: float = _spin("floor_override_window_width")
	print("[workshop-editor-stage] hide screen")
	_plugin.call("_make_visible", false)
	await _tree.process_frame
	_check("隐藏主屏停止预览更新", not _screen.visible and viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	_plugin.call("_make_visible", true)
	EditorInterface.set_main_screen_editor("楼房工坊")
	await _tree.process_frame
	_check("恢复可见恢复预览更新", _screen.is_visible_in_tree() and viewport != null and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	_check("隐藏恢复不丢草稿", _same(before_recovery, _result(_screen, "get_recovery")))
	print("[workshop-editor-stage] rebuild screen")
	var rebuilt_recovery: Dictionary = _result(_plugin, "rebuild_screen_for_verification")
	print("[workshop-editor-stage] screen recreated")
	for frame: int in range(3):
		await _tree.process_frame
	_screen = _property(_plugin, "screen") as Control
	_plugin.call("_make_visible", true)
	EditorInterface.set_main_screen_editor("楼房工坊")
	await _tree.process_frame
	var rebuilt_session: Object = _property(_screen, "session") as Object
	var rebuilt_catalog: Dictionary = _dictionary(_property(rebuilt_session, "catalog"))
	var rebuilt_preview: Object = _property(_screen, "preview") as Object
	var rebuilt_viewport: SubViewport = _property(rebuilt_preview, "viewport") as SubViewport
	_check("插件屏幕已实际重建", _screen != null and _screen != old_screen and _screen.is_inside_tree() and not is_instance_valid(old_screen))
	_check("重建 screen recovery 返回一致", _same(before_recovery, rebuilt_recovery) and _same(before_recovery, _result(_screen, "get_recovery")))
	_check("重建恢复草稿 snapshot", _same(before_snapshot, _snapshot()))
	_check("重建恢复 catalog", _same(before_catalog, rebuilt_catalog))
	_check("重建恢复 UI dirty", bool(_screen.call("has_pending_fields")) == before_pending)
	_check("重建恢复 UI width", is_equal_approx(_spin("width"), before_width))
	_check("重建恢复 UI floor override", is_equal_approx(_spin("floor_override_window_width"), before_floor_width))
	_check("重建可见恢复预览更新", _screen.is_visible_in_tree() and rebuilt_viewport != null and rebuilt_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	_check("重建允许新 session", is_instance_valid(rebuilt_session))
	_check("重建保持 edited scene root", EditorInterface.get_edited_scene_root() == lifecycle_root and _root_transform(lifecycle_root) == lifecycle_transform)
	_check("重建保持 tree paused", _tree.paused == lifecycle_paused)
	# 这是插件屏幕生命周期重建（remove old Control + queue_free），不是完整插件卸载/重载。

func _verify_bundle(result: Dictionary, label: String) -> void:
	var directory: String = str(result.get("directory", ""))
	if not _check(label + " 输出隔离", directory.begins_with(OUTPUT_ROOT + "/") and not directory.contains(".."), directory):
		return
	var files: Array[String] = ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json"]
	for name: String in files:
		var path: String = directory.path_join(name)
		if _check(label + " 文件：" + name, FileAccess.file_exists(path)):
			_artifacts.append(path)
	var loaded: Dictionary = _result(_store, "load_recipe", [directory.path_join("building.recipe.json")])
	_check_result(label + " EditorStore 重载", loaded)
	_check(label + " 配方与 catalog 往返", _same(loaded.get("recipe"), result.get("recipe")) and _same(loaded.get("catalog"), result.get("catalog")))
	var manifest: Dictionary = _read_json(directory.path_join("candidate_manifest.json"))
	var ledger: Dictionary = _read_json(directory.path_join("ledger.json"))
	_check(label + " 编辑器来源及候选边界", str(manifest.get("authoring_context", "")) == "editor" and bool(manifest.get("noMain", false)) and manifest.get("formal_registry_written", true) == false and str(ledger.get("status", "")) == "candidate_only")
	var hashes: Dictionary = _dictionary(manifest.get("source_hashes", {}))
	for name: String in ["building.recipe.json", "catalog_snapshot.json", "building.tscn"]:
		_check(label + " SHA256：" + name, not str(hashes.get(name, "")).is_empty() and str(hashes.get(name, "")) == FileAccess.get_sha256(directory.path_join(name)))
	_check(label + " 场景总 hash", str(manifest.get("hash", "")) == FileAccess.get_sha256(directory.path_join("building.tscn")))
	var sources: Dictionary = _dictionary(manifest.get("authoring_source_hashes", {}))
	_check(label + " 创作来源 hashes 非空", not sources.is_empty())
	for source: Variant in sources:
		_check(label + " 来源 hash：" + str(source), FileAccess.file_exists(str(source)) and str(sources[source]) == FileAccess.get_sha256(str(source)))
	var packed: PackedScene = ResourceLoader.load(directory.path_join("building.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not _check(label + " 真实 PackedScene 重载", packed != null):
		return
	if not _check(label + " 实例化前递归确认无 Script", not _unsafe_resource(packed, {})):
		return
	var instance: Node = packed.instantiate()
	var twin: Node = packed.instantiate()
	var actual: Dictionary = _geometry(instance)
	var duplicate: Dictionary = _geometry(twin)
	var expected: Dictionary = _dictionary(manifest.get("geometry", {}))
	_check(label + " 静态实例无脚本相机灯光", int(actual.get("scripts", -1)) == 0 and int(actual.get("editor_nodes", -1)) == 0 and int(actual.get("unowned_nodes", -1)) == 0)
	_check(label + " 两次实例化 geometry hash 一致", _same(actual, duplicate) and not actual.is_empty())
	var preview: Object = _property(_screen, "preview") as Object
	var model: Node3D = _property(preview, "_model_root") as Node3D
	if _check(label + " 保存后真实预览模型仍存在", model != null and model.get_child_count() == 1):
		var live: Dictionary = _geometry(model.get_child(0))
		_check(label + " 导出实例与实际预览 geometry hash 一致", _same(live, actual), "逐网格路径、变换与 surface arrays 的 SHA256")
	for key: String in ["nodes", "visual_meshes", "collision_shapes", "metadata_meshes"]:
		_check(label + " 几何计数：" + key, int(actual.get(key, -1)) == int(expected.get(key, -2)))
	_check(label + " 非空可视和碰撞", int(actual.get("visual_meshes", 0)) > 0 and int(actual.get("collision_shapes", 0)) > 0)
	for key: String in ["bounds_position", "bounds_size", "collision_bounds_position", "collision_bounds_size"]:
		_check(label + " 实际包围盒：" + key, _near_array(actual.get(key, []), expected.get(key, [])), str(actual.get(key)))
	_check(label + " 配方指纹保留", str(instance.get_meta("recipe_fingerprint", "")) == str(manifest.get("recipe_fingerprint", "")))
	instance.free()
	twin.free()

func _geometry(root: Node) -> Dictionary:
	var result: Dictionary = {"nodes": 0, "scripts": 0, "unowned_nodes": 0, "editor_nodes": 0, "visual_meshes": 0, "collision_shapes": 0, "metadata_meshes": 0}
	var visual: AABB = AABB()
	var collision: AABB = AABB()
	var has_visual: bool = false
	var has_collision: bool = false
	var mesh_hashes: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		result["nodes"] += 1
		if node.get_script() != null:
			result["scripts"] += 1
		if node != root and node.owner == null:
			result["unowned_nodes"] += 1
		if node is Camera3D or node is Light3D:
			result["editor_nodes"] += 1
		var transform: Transform3D = _relative_transform(node, root)
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			result["visual_meshes"] += 1
			if node.has_meta("slot_id") and node.has_meta("component_id"):
				result["metadata_meshes"] += 1
			if mesh_node.mesh != null:
				var box: AABB = transform * mesh_node.mesh.get_aabb()
				visual = visual.merge(box) if has_visual else box
				has_visual = true
				for surface: int in range(mesh_node.mesh.get_surface_count()):
					mesh_hashes.append(var_to_bytes([str(root.get_path_to(node)), transform, mesh_node.mesh.surface_get_arrays(surface)]).hex_encode().sha256_text())
		if node is CollisionShape3D:
			result["collision_shapes"] += 1
			var shape: Shape3D = (node as CollisionShape3D).shape
			var box: AABB = AABB()
			var valid: bool = false
			if shape is BoxShape3D:
				var dimensions: Vector3 = (shape as BoxShape3D).size
				box = transform * AABB(-dimensions * 0.5, dimensions)
				valid = true
			elif shape is ConcavePolygonShape3D:
				for point: Vector3 in (shape as ConcavePolygonShape3D).get_faces():
					var transformed: Vector3 = transform * point
					box = box.expand(transformed) if valid else AABB(transformed, Vector3.ZERO)
					valid = true
			if valid:
				collision = collision.merge(box) if has_collision else box
				has_collision = true
		for child: Node in node.get_children():
			stack.append(child)
	result["bounds_position"] = [visual.position.x, visual.position.y, visual.position.z]
	result["bounds_size"] = [visual.size.x, visual.size.y, visual.size.z]
	result["collision_bounds_position"] = [collision.position.x, collision.position.y, collision.position.z]
	result["collision_bounds_size"] = [collision.size.x, collision.size.y, collision.size.z]
	result["mesh_geometry_hash"] = "|".join(mesh_hashes).sha256_text()
	return result

func _relative_transform(node: Node, root: Node) -> Transform3D:
	var transform: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform

func _unsafe_resource(value: Variant, visited: Dictionary) -> bool:
	if value is Script:
		return true
	if value is Resource:
		var resource: Resource = value as Resource
		var id: int = resource.get_instance_id()
		if visited.has(id):
			return false
		visited[id] = true
		if resource.get_script() != null:
			return true
		if resource is PackedScene:
			return _unsafe_state((resource as PackedScene).get_state(), visited)
		for entry: Dictionary in resource.get_property_list():
			if int(entry.get("usage", 0)) & PROPERTY_USAGE_STORAGE:
				if _unsafe_resource(resource.get(str(entry["name"])), visited):
					return true
	elif value is Array:
		for item: Variant in value:
			if _unsafe_resource(item, visited):
				return true
	elif value is Dictionary:
		for key: Variant in value:
			if _unsafe_resource(value[key], visited):
				return true
	return false

func _unsafe_state(state: SceneState, visited: Dictionary) -> bool:
	if state == null:
		return false
	var base: SceneState = state.get_base_scene_state()
	if base != null and _unsafe_state(base, visited):
		return true
	for index: int in range(state.get_node_count()):
		var nested: PackedScene = state.get_node_instance(index)
		if nested != null and _unsafe_resource(nested, visited):
			return true
		for property_index: int in range(state.get_node_property_count(index)):
			if str(state.get_node_property_name(index, property_index)) == "script" or _unsafe_resource(state.get_node_property_value(index, property_index), visited):
				return true
	return false

func _capture(dimensions: Vector2i, suffix: String = "") -> void:
	print("[workshop-editor-stage] capture ", dimensions, suffix)
	var label: String = "%dx%d%s" % [dimensions.x, dimensions.y, suffix]
	if not _check(label + " 非 headless 渲染", DisplayServer.get_name() != "headless"):
		return
	var scan_ready: bool = await _wait_for_filesystem_scan(label)
	if not scan_ready:
		return
	# 只清理本验证窗口的系统窗口状态；不强制隐藏编辑器的其他 popup。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	_tree.root.size = dimensions
	for frame: int in range(5):
		await _tree.process_frame
	# 编辑器可能进入低处理模式，不等待一个可能永不触发的被动帧信号。
	RenderingServer.force_draw()
	print("[workshop-editor-stage] framebuffer ready")
	_check(label + " 实际窗口尺寸", DisplayServer.window_get_size() == dimensions and _tree.root.size == dimensions, str(_tree.root.size))
	_layout_checks(label)
	var image: Image = _tree.root.get_texture().get_image()
	if not _check(label + " 真实编辑器 framebuffer", image != null and not image.is_empty() and image.get_width() == dimensions.x and image.get_height() == dimensions.y):
		return
	var path: String = "res://outputs/workshop_editor_%s.png" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	if _check(label + " 截图落盘", image.save_png(path) == OK):
		_artifacts.append(path)

func _wait_for_filesystem_scan(label: String) -> bool:
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	var deadline_msec: int = Time.get_ticks_msec() + 5000
	var yielded: bool = false
	while filesystem.is_scanning() and Time.get_ticks_msec() < deadline_msec:
		yielded = true
		await _tree.process_frame
	var scanning: bool = filesystem.is_scanning()
	_check(label + " 文件系统扫描已结束", not scanning, "5秒后仍在扫描，截图明确失败" if scanning else ("等待扫描完成" if yielded else "未处于扫描状态"))
	return not scanning

func _layout_checks(label: String) -> void:
	_check(label + " 主屏实际最小宽度700", _screen.is_visible_in_tree() and _screen.size.x >= 700.0 and _screen.custom_minimum_size.x >= 700.0)
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	_check(label + " 使用编辑器主题", _screen.theme == editor_theme)
	var has_base_color: bool = editor_theme.has_color("base_color", "Editor")
	var base_color: Color = editor_theme.get_color("base_color", "Editor") if has_base_color else Color.WHITE
	_check(label + " EditorMain 暗色主题", has_base_color and base_color.get_luminance() < 0.5 and EditorInterface.get_base_control().is_visible_in_tree(), str(base_color))
	var panels: Array[Control] = []
	for property: String in ["_left_panel", "preview", "_right_panel"]:
		var panel: Control = _property(_screen, property) as Control
		if _check(label + " 实际面板非空：" + property, panel != null and panel.is_visible_in_tree() and panel.size.x > 0.0 and panel.size.y > 0.0 and panel.get_child_count() > 0):
			panels.append(panel)
	for index: int in range(panels.size()):
		for next: int in range(index + 1, panels.size()):
			_check(label + " 主面板无重叠：%d/%d" % [index, next], not _visible_rect(panels[index]).intersects(_visible_rect(panels[next])))
	var title_found: bool = false
	var missing: Array[String] = []
	var overlaps: Array[String] = []
	var pages: Dictionary = _dictionary(_property(_screen, "pages"))
	_check(label + " 参数页均有实际内容", pages.size() == 6)
	for key: Variant in pages:
		var page: Control = pages[key] as Control
		_check(label + " 页内容非空：" + str(key), page != null and page.get_child_count() > 0)
	var stack: Array[Node] = [_screen]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var text: String = ""
		if node is Label:
			text = (node as Label).text
		elif node is Button:
			text = (node as Button).text
		if text == "楼房工坊" and node is Control and (node as Control).is_visible_in_tree():
			title_found = true
		if text.to_lower().contains("missing"):
			missing.append(text)
		# 只比较真实容器的可见直接子控件；剪裁掉滚动区域外内容，不使用虚构坐标。
		if node is BoxContainer:
			var children: Array[Control] = []
			for child: Node in node.get_children():
				if child is Control and (child as Control).is_visible_in_tree():
					children.append(child as Control)
			for index: int in range(children.size()):
				for next: int in range(index + 1, children.size()):
					var a: Rect2 = _visible_rect(children[index]).grow(-0.5)
					var b: Rect2 = _visible_rect(children[next]).grow(-0.5)
					if a.has_area() and b.has_area() and a.intersects(b):
						overlaps.append("%s / %s" % [str(children[index].get_path()), str(children[next].get_path())])
		for child: Node in node.get_children():
			if not child is Window:
				stack.append(child)
	_check(label + " 真实标题且无 missing", title_found and missing.is_empty(), str(missing))
	_check(label + " 实际容器控件无重叠", overlaps.is_empty(), str(overlaps))

func _visible_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_rect().intersection(Rect2(Vector2.ZERO, Vector2(_tree.root.size)))
	var current: Node = control.get_parent()
	while current != null and current != _tree.root:
		if current is Control and (current as Control).clip_contents:
			rect = rect.intersection((current as Control).get_global_rect())
		current = current.get_parent()
	return rect

func _finish() -> void:
	var current_root: Node = EditorInterface.get_edited_scene_root()
	_scene_unchanged = current_root == _edited_root and _root_transform(current_root) == _edited_transform
	_check("edited scene root 及 transform 不变", _scene_unchanged)
	_check("root paused 不变", _tree.paused == _paused)
	_check("最终 editor_hint 为真", Engine.is_editor_hint())
	_check("最终未启动游戏场景", not EditorInterface.is_playing_scene())
	_check("报告目录可创建", DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs")) == OK)
	_artifacts.append(REPORT_PATH)
	var report: Dictionary = {
		"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"enginehint": Engine.is_editor_hint(), "is_playing": EditorInterface.is_playing_scene(),
		"scene_unchanged": _scene_unchanged, "root_paused_unchanged": _tree.paused == _paused,
		"artifacts": _artifacts, "buildids": _build_ids, "dependencies": _dependencies,
		"project_path": ProjectSettings.globalize_path("res://"),
		"input_method": "真实 Control 值及真实 Button.pressed 信号；不是鼠标自动化",
		"lifecycle_scope": "实际插件隐藏/恢复及 UPDATE_DISABLED；未执行插件卸载/重载，不 queue_free 插件",
		"visual_acceptance": "截图仅为真实编辑器证据；非空截图和拓扑通过不代表professional美术验收通过，仍须目检接缝、洞口、倒角与阴影",
		"legacy_scope": "原有modular_v1回归、替件、保存和生命周期检查保留；普通、floor_facade及damaged_l_plants截图仅为legacy兼容证据，不是shell_v2新成品",
		"legacy_checks_before_shell": _legacy_check_count,
		"shell_samples": _shell_samples,
		"shell_capture_scope": "continuous_*为1600x1000真实编辑器framebuffer；workshop_shell_model_*.png为1400x1100独立SubViewport的真实模型渲染；未隐藏侧栏或改变主屏stretch，未关闭阴影",
		"game_save_connected": false,
		"boundaries": ["仅生成和保存静态建筑，不启动 Main", "不连接或调用游戏存档", "组件 fixture 仅允许隔离副本", "缺失 API 记为失败，不模拟成功"]
	}
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_check("JSON 报告写入", false, error_string(FileAccess.get_open_error()))
	else:
		file.store_string(JSON.stringify(report, "\t"))
		var error: Error = file.get_error()
		file.close()
		if error != OK:
			_check("JSON 报告写入", false, error_string(error))
	print("[workshop-editor] %d checks, %d failures" % [_checks.size(), _failures.size()])
	_tree.quit(0 if _failures.is_empty() else 1)

func _check(name: String, passed: bool, detail: String = "") -> bool:
	_checks.append({"name": name, "passed": passed, "detail": detail})
	if not passed:
		_failures.append(name + ("：" + detail if not detail.is_empty() else ""))
	return passed

func _check_result(name: String, result: Dictionary) -> bool:
	return _check(name, bool(result.get("ok", false)), str(result.get("reason", "缺少 ok" if not result.has("ok") else "")))

func _property(object: Object, key: String) -> Variant:
	if not is_instance_valid(object):
		return null
	for entry: Dictionary in object.get_property_list():
		if str(entry.get("name", "")) == key:
			return object.get(key)
	return null

func _require_methods(object: Object, methods: Array, owner: String) -> bool:
	var valid: bool = true
	for method: String in methods:
		var available: bool = is_instance_valid(object) and object.has_method(method)
		_check(owner + "." + method + " 可用", available)
		if not available:
			_dependencies.append(owner + "." + method)
			valid = false
	return valid

func _result(object: Object, method: String, args: Array = []) -> Dictionary:
	if not is_instance_valid(object) or not object.has_method(method):
		_check("调用依赖：" + method, false, "缺少真实对象或方法")
		return {"ok": false, "reason": "缺少真实方法：" + method}
	var value: Variant = object.callv(method, args)
	if not value is Dictionary:
		_check("返回 Dictionary：" + method, false, str(value))
		return {"ok": false, "reason": "真实 API 未返回 Dictionary：" + method}
	return value as Dictionary

func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}

func _snapshot() -> Dictionary:
	return _result(_screen, "snapshot")

func _same(a: Variant, b: Variant) -> bool:
	return _stable_value(a) == _stable_value(b)

func _stable_value(value: Variant) -> String:
	# JSON 会将数字读为 float；按数值比较整数，不能把重载差异误报成数据损坏。
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var fields: Array[String] = []
		for key: Variant in keys:
			fields.append(JSON.stringify(str(key)) + ":" + _stable_value(value[key]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var entries: Array[String] = []
		for item: Variant in value:
			entries.append(_stable_value(item))
		return "[" + ",".join(entries) + "]"
	if value is float and is_finite(float(value)) and floor(float(value)) == float(value) and absf(float(value)) <= 9007199254740991.0:
		return str(int(value))
	return JSON.stringify(value)

func _near_array(a: Variant, b: Variant) -> bool:
	if not a is Array or not b is Array or a.size() != 3 or b.size() != 3:
		return false
	for axis: int in range(3):
		if not is_equal_approx(float(a[axis]), float(b[axis])):
			return false
	return true

func _set_spin(key: String, value: float) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var spin: SpinBox = controls.get(key) as SpinBox
	if not _check("实际 SpinBox：" + key, spin != null, str(controls.keys())):
		return false
	spin.value = value
	return _check("SpinBox 接收输入：" + key, is_equal_approx(spin.value, value))

func _spin(key: String) -> float:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var spin: SpinBox = controls.get(key) as SpinBox
	return spin.value if spin != null else NAN

func _set_text(key: String, text: String) -> bool:
	var controls: Dictionary = _dictionary(_property(_screen, "controls"))
	var edit: LineEdit = controls.get(key) as LineEdit
	if not _check("实际 LineEdit：" + key, edit != null):
		return false
	edit.text = text
	edit.text_changed.emit(text)
	return true

func _emit_button(key: String) -> bool:
	var buttons: Dictionary = _dictionary(_property(_screen, "buttons"))
	var button: Button = buttons.get(key) as Button
	if not _check("真实按钮信号：" + key, button != null and not button.disabled, "直接 emit pressed，不是鼠标事件"):
		return false
	button.pressed.emit()
	return true

func _root_transform(root: Node) -> Variant:
	if not is_instance_valid(root):
		return null
	if root is Node3D:
		return (root as Node3D).transform
	if root is CanvasItem:
		return (root as CanvasItem).get_transform()
	return null

func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check("读取 JSON：" + path, false, error_string(FileAccess.get_open_error()))
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_check("JSON 对象：" + path, value is Dictionary)
	return _dictionary(value)

func _bundle_hashes(directory: String) -> Dictionary:
	var hashes: Dictionary = {}
	for name: String in ["building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json"]:
		hashes[name] = FileAccess.get_sha256(directory.path_join(name))
	return hashes
