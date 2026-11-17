@tool
extends RefCounted

const Library = preload("res://addons/scene_assembly/library.gd")
const BuildingRecipe = preload("res://src/workshop/recipe.gd")
const Catalog = preload("res://src/workshop/catalog.gd")
const BuildingStore = preload("res://addons/building_workshop/editor_store.gd")
const PlantRecipe = preload("res://src/plant_authoring/recipe.gd")
const PlantStore = preload("res://src/plant_authoring/store.gd")
var checks := 0
var failures: Array[String] = []
var check_results: Array[Dictionary] = []
var plugin: EditorPlugin
var evidence: Dictionary = {}
var drag_evidence: Dictionary = {}
var window_was_on_top := false

func input_state(stage: String) -> void:
	var viewport: Viewport = plugin.dock.get_viewport()
	var hovered: Control = viewport.gui_get_hovered_control()
	drag_evidence[stage] = {
		"focused": plugin.get_window().has_focus(),
		"mouse": str(viewport.get_mouse_position()),
		"dragging": viewport.gui_is_dragging(),
		"hovered": str(hovered.get_path()) if hovered != null else "null",
		"window_position": str(plugin.get_window().position),
		"window_size": str(plugin.get_window().size),
		"viewport_rect": str(viewport.get_visible_rect()),
	}

static func run(p: EditorPlugin) -> void:
	var suite = load("res://tests/test_scene_assembly_editor.gd").new()
	suite.plugin = p
	await suite.execute()

func check(value: bool, label: String) -> void:
	checks += 1
	check_results.append({"label": label, "passed": value})
	if not value:
		failures.append(label)
		printerr("[scene-assembly-fail] " + label)

func frames(count: int = 4) -> void:
	for i in count: await plugin.get_tree().process_frame

func select(node: Node) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)

func mouse(point: Vector2, pressed: bool, motion: bool = false) -> void:
	plugin.dock.get_viewport().warp_mouse(point)
	var event: InputEventMouse
	if motion:
		var move := InputEventMouseMotion.new()
		move.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		move.relative = Vector2(30, 15)
		event = move
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event = button
	event.window_id = plugin.get_window().get_window_id()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)

func drag(index: int) -> void:
	plugin._show_attachment_page(false)
	while plugin._thumbnail_busy: await frames()
	drag_evidence = {}
	input_state("before_input")
	DisplayServer.window_move_to_foreground(plugin.get_window().get_window_id())
	plugin.get_window().grab_focus()
	await frames(8)
	input_state("after_foreground")
	var child: Node = plugin.dock
	while child.get_parent() != null:
		var ancestor := child.get_parent()
		if ancestor is TabContainer:
			ancestor.current_tab = child.get_index()
		child = ancestor
	await frames(8)
	check(plugin.items.is_visible_in_tree(), "候选库页签真实可见")
	plugin.items.ensure_current_is_visible()
	# 每次把目标条目放在首行，保证输入坐标落在真实条目中。
	var row: Dictionary = plugin.items.get_item_metadata(index)
	plugin.items.clear()
	plugin.items.add_item(str(row.label))
	plugin.items.set_item_metadata(0, row)
	await frames()
	var start: Vector2 = plugin.items.global_position + plugin.items.get_item_rect(0).get_center()
	evidence["drag_start"] = str(start)
	mouse(start, false, true)
	await frames(2)
	input_state("source_hover")
	check(plugin.dock.get_viewport().gui_get_hovered_control() == plugin.items, "按下前真实悬停候选库：" + str(row.kind))
	mouse(start, true)
	await frames(2)
	mouse(start + Vector2(35, 20), true, true)
	await frames(3)
	check(plugin.dock.get_viewport().gui_is_dragging(), "真实鼠标按下和移动启动库拖放")
	input_state("drag_started")
	var surface: Control = plugin.surfaces[0]
	surface.set_meta("can_drop_seen", false)
	surface.set_meta("drop_seen", false)
	var end: Vector2 = surface.global_position + surface.size * Vector2(0.55, 0.55)
	evidence["drop_surface"] = {"class": surface.get_parent().get_class(), "size": str(surface.size), "position": str(surface.global_position)}
	mouse(end, true, true)
	await frames(3)
	var hovered: Control = plugin.dock.get_viewport().gui_get_hovered_control()
	evidence["hovered"] = str(hovered.get_path()) if hovered != null else "null"
	evidence["surface_path"] = str(surface.get_path())
	evidence["surface_visible"] = surface.is_visible_in_tree()
	input_state("target_hover")
	drag_evidence["target_hover"]["can_insert"] = plugin.can_insert()
	drag_evidence["target_hover"]["os_mouse"] = str(DisplayServer.mouse_get_position())
	drag_evidence["target_hover"]["window_id"] = plugin.get_window().get_window_id()
	check(bool(surface.get_meta("can_drop_seen", false)), "释放前真实移动已触发can_drop：" + str(row.kind))
	mouse(end, false)
	await frames(5)
	check(not plugin.dock.get_viewport().gui_is_dragging(), "真实鼠标释放结束拖放")
	check(not surface.visible, "拖动结束接收层关闭，不拦原生编辑")
	evidence["can_drop_seen"] = surface.get_meta("can_drop_seen", false)
	evidence["drop_seen"] = surface.get_meta("drop_seen", false)
	check(bool(evidence.can_drop_seen), "本次真实移动经过接收层can_drop：" + str(row.kind))
	check(bool(evidence.drop_seen), "本次真实释放经过接收层drop：" + str(row.kind))
	input_state("released")
	drag_evidence["can_drop_seen"] = evidence.can_drop_seen
	drag_evidence["drop_seen"] = evidence.drop_seen
	drag_evidence["kind"] = row.kind
	if not evidence.has("drags"): evidence["drags"] = []
	evidence.drags.append(drag_evidence.duplicate(true))

func check_bridge_connections(kind: String, label: String) -> void:
	check(plugin._bridge_connections.has(kind), label + "：存在连接记录")
	if not plugin._bridge_connections.has(kind): return
	var connection: Dictionary = plugin._bridge_connections[kind]
	check(connection.bridge_id == plugin.bridges[kind].get_instance_id() and connection.screen_id == plugin.bridges[kind].screen.get_instance_id(), label + "：plugin/screen双身份一致")
	for pair: Dictionary in connection.connections:
		var source: Signal = pair.source
		var count := 0
		for entry: Dictionary in source.get_connections():
			if entry.callable == pair.callback: count += 1
		check(count == 1, label + "：" + str(source.get_name()) + "仅连接一次")

func check_disconnected(connections: Array, label: String) -> void:
	for pair: Dictionary in connections:
		var source: Signal = pair.source
		check(not is_instance_valid(source.get_object()) or not source.is_connected(pair.callback), label + "：" + str(source.get_name()) + "已断开")

func bridge_lifecycle(house: Node3D, tree: Node3D) -> void:
	var building: EditorPlugin = plugin.bridges.building
	var plant_screen: Control = plugin.bridges.plant.screen
	# 另一工坊重建不能取消当前树的确认事务或既有绑定。
	plant_screen.input_recipe.height = float(plant_screen.input_recipe.height) + 0.2
	select(tree)
	plugin.edit_selected()
	var plant_pending: Dictionary = plugin.pending.duplicate()
	var plant_binding: Dictionary = plugin.binding.duplicate()
	check(not plant_pending.is_empty() and plant_screen._confirm.visible, "树存在待确认请求供跨工坊隔离验证")
	building.rebuild_screen_for_verification()
	await frames()
	check(plugin.pending == plant_pending and plugin.binding == plant_binding, "房屋screen重建不清理树pending/binding")
	plant_screen._confirm.canceled.emit()
	plant_screen._confirm.hide()
	plant_screen.input_recipe = plant_screen.session.snapshot()
	check_bridge_connections("building", "房屋重建后事件自动重连")

	select(house)
	plugin.edit_selected()
	var screen: Control = building.screen
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames()
	check(screen.is_visible_in_tree() and screen.is_screen_active(), "重建后经装配请求真实显示房屋主屏")
	check(not plugin.binding.is_empty() and plugin.binding.screen_id == screen.get_instance_id(), "重建后的房屋可重新绑定")
	screen.session.apply_patch({"display_name": "重建前未保存"})
	plugin.edit_selected()
	var old_pending: Dictionary = plugin.pending.duplicate()
	var old_connection: Dictionary = plugin._bridge_connections.building.duplicate()
	check(not old_pending.is_empty() and screen._confirm.visible, "房屋重建前保留待确认请求")
	var same_token: int = plugin.pending.token
	plant_screen.document_opened.emit("", 0)
	plant_screen.document_opened.emit("", same_token)
	plant_screen.document_request_finished.emit(same_token, {"ok": false})
	plant_screen.revision_saved.emit(same_token, {})
	check(plugin.pending == old_pending and plugin.binding.kind == "building", "另一工坊相同token不能改绑或完成pending")
	building.rebuild_screen_for_verification()
	check(plugin.pending.is_empty() and plugin.binding.is_empty(), "旧screen退出立即取消对应pending和binding")
	check_disconnected(old_connection.connections, "旧房屋screen及plugin回调")
	# 旧screen已排队但尚未释放，发信号及重放已捕获回调均不能污染新事务。
	screen.document_opened.emit("", same_token)
	screen.document_request_finished.emit(same_token, {"ok": true})
	screen.revision_saved.emit(same_token, {})
	select(house)
	plugin.edit_selected()
	screen = building.screen
	var fresh_pending: Dictionary = plugin.pending.duplicate()
	var fresh_binding: Dictionary = plugin.binding.duplicate()
	old_connection.connections[0].callback.call("", same_token)
	old_connection.connections[1].callback.call(same_token, {"ok": false})
	old_connection.connections[2].callback.call(same_token, {})
	check(plugin.pending == fresh_pending and plugin.binding == fresh_binding, "请求前刷新且旧双身份回调不能污染新事务")
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames()
	check(not plugin.binding.is_empty() and plugin.binding.screen_id == screen.get_instance_id(), "失效pending不再堵塞新请求")
	var token: int = plugin.binding.get("token", -1)
	plugin._refresh_bridges()
	plugin._refresh_bridges()
	check(plugin.binding.get("token", -2) == token, "重复刷新保留当前有效绑定")
	check_bridge_connections("building", "重复刷新幂等")

	for kind: String in ["building", "plant"]:
		var addon := "building_workshop" if kind == "building" else "plant_editor"
		var target := house if kind == "building" else tree
		select(target)
		plugin.edit_selected()
		var previous: EditorPlugin = plugin.bridges[kind]
		var previous_screen: Control = previous.screen
		if previous_screen._confirm.visible:
			previous_screen._confirm.hide()
			previous_screen._confirm.confirmed.emit()
		if kind == "building": previous_screen.session.apply_patch({"display_name": "禁用前未保存"})
		else: previous_screen.input_recipe.height = float(previous_screen.input_recipe.height) + 0.2
		plugin.edit_selected()
		var previous_id := previous.get_instance_id()
		var previous_connections: Array = plugin._bridge_connections[kind].connections.duplicate()
		check(not plugin.pending.is_empty(), kind + "禁用前有pending")
		EditorInterface.set_plugin_enabled(addon, false)
		check(plugin.pending.is_empty() and plugin.binding.is_empty() and not plugin.bridges.has(kind), kind + "禁用立即清理对应事务和bridge")
		check_disconnected(previous_connections, kind + "禁用断开旧回调")
		await frames()
		EditorInterface.set_plugin_enabled(addon, true)
		await frames(8)
		check(plugin.bridges.has(kind) and plugin.bridges[kind].get_instance_id() != previous_id, kind + "重启后node_added自动发现新plugin")
		if not plugin.bridges.has(kind): continue
		check_bridge_connections(kind, kind + "重启后连接")
		select(target)
		plugin.edit_selected()
		var current_screen: Control = plugin.bridges[kind].screen
		if current_screen._confirm.visible:
			current_screen._confirm.hide()
			current_screen._confirm.confirmed.emit()
		await frames()
		check(current_screen.is_visible_in_tree() and (current_screen.is_screen_active() if kind == "building" else current_screen._screen_active), kind + "重启后请求真实显示主屏")
		check(not plugin.binding.is_empty() and plugin.binding.bridge_id == plugin.bridges[kind].get_instance_id(), kind + "新plugin成功绑定")
		var transform_before := target.transform
		var saved: Dictionary = current_screen.save_building() if kind == "building" else current_screen.save_animated()
		var expected_path := str(saved.get("scene_path" if kind == "building" else "animated_scene_path", ""))
		check(saved.get("ok", false) and not expected_path.is_empty() and target.get_node("Asset").scene_file_path == expected_path, kind + "重启后保存仅更新绑定Asset")
		check(target.transform == transform_before, kind + "重启换版保持用户transform")
		if kind == "building":
			check(current_screen.open_recipe(str(saved.recipe_path)).get("ok", false) and plugin.binding.is_empty(), "普通打开token零解除当前实例绑定")

func execute() -> void:
	if not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or FileAccess.file_exists("res://scenes/main.tscn"):
		printerr("装配验证只允许无Main的隔离runner工程")
		plugin.get_tree().quit(1)
		return
	window_was_on_top = plugin.get_window().always_on_top
	# 原生窗口被别的应用遮挡时，warp鼠标的OS命中窗口与注入GUI窗口不一致。
	plugin.get_window().always_on_top = true
	print("[scene-assembly-stage] fixtures")
	check(Engine.is_editor_hint(), "真实Editor运行")
	check(not EditorInterface.is_playing_scene(), "未运行游戏")
	check(Library.collect().is_empty(), "隔离库初始为空，未注入生产样例")
	var recipe := BuildingRecipe.authoring_defaults()
	recipe.building_id = "assembly_house"
	var house: Dictionary = BuildingStore.new().export_revision(recipe, Catalog.editor_catalog({}), "res://scenes/workshop_buildings")
	check(house.get("ok", false), "真实建筑Store保存候选：" + str(house.get("reason", "")))
	var tree := PlantRecipe.defaults("camphor")
	tree.name = "assembly_tree"
	var plant: Dictionary = PlantStore.new().save_animated(tree, "res://scenes/workshop_plants")
	check(plant.get("ok", false), "真实树Store保存动态旁车")
	if not house.get("ok", false) or not plant.get("ok", false):
		await finish()
		return
	var root := Node3D.new()
	root.name = "AssemblyFixture"
	var parent := Node3D.new()
	parent.name = "RotatedParent"
	root.add_child(parent)
	parent.owner = root
	parent.transform = Transform3D(Basis(Vector3.UP, 0.45).scaled(Vector3(1.2, 1.2, 1.2)), Vector3(4, 2, -3))
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.owner = root
	light.rotation_degrees = Vector3(-50, -30, 0)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://outputs/assembly_fixture.tscn")
	root.free()
	EditorInterface.open_scene_from_path("res://outputs/assembly_fixture.tscn")
	EditorInterface.set_main_screen_editor("3D")
	await frames(15)
	root = EditorInterface.get_edited_scene_root()
	parent = root.get_node("RotatedParent")
	select(parent)
	plugin.refresh_library()
	await frames(8)
	var house_index := -1
	for i in plugin.items.item_count:
		if plugin.items.get_item_metadata(i).kind == "building": house_index = i
	check(house_index >= 0, "生产目录枚举建筑")
	print("[scene-assembly-stage] real drag house")
	await drag(house_index)
	var a: Node3D = plugin.selected_placement()
	check(a != null, "真实3D视口drop插入建筑")
	if a == null:
		await screenshot("failed_drag")
		await finish()
		return
	check(a.get_parent() == parent, "插入选中本地父节点")
	check(absf(a.global_position.y) < 0.001, "父坐标变换后仍落世界Y平面")
	check(a.get_script() == null and not a.get_node("Asset").scene_file_path.is_empty(), "无脚本Placement和外链Asset")
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
	history.undo()
	check(not a.is_inside_tree(), "插入undo真实移除")
	history.redo()
	check(a.is_inside_tree() and a.owner == root, "插入redo恢复owner")
	# 通过同一个真实拖放输入链插入动态树。
	plugin.refresh_library()
	select(parent)
	await frames()
	var tree_index := -1
	for i in plugin.items.item_count:
		var row: Dictionary = plugin.items.get_item_metadata(i)
		if row.kind == "plant" and row.animated: tree_index = i
	await drag(tree_index)
	var b: Node3D = plugin.selected_placement()
	check(b != null and b != a, "真实视口drop插入树")
	if b == null or b == a:
		await finish()
		return
	check(b.get_node("Asset").scene_file_path.ends_with("plant_wind.tscn"), "动态树选择动态旁车")
	var static_entry := Library.describe(plant.recipe_path, "plant")
	var static_result: Dictionary = plugin.insert_candidate(static_entry, Vector3(-8, 0, 0))
	check(static_result.ok, "补充静态树插入")
	var c: Node3D = static_result.placement
	var duplicate_result: Dictionary = plugin.insert_candidate(Library.describe(house.recipe_path, "building"), Vector3(18, 0, -3))
	var duplicate_house: Node3D = duplicate_result.placement
	var duplicate_transform := duplicate_house.transform
	var duplicate_path: String = duplicate_house.get_node("Asset").scene_file_path
	# 原生变换属性与场景历史；不借用工坊打开时的旧位置。
	a.transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.4, 1.1, 0.9)), Vector3(2, 1, 3))
	b.position = Vector3(-4, 0, 2)
	var b_transform := b.transform
	var c_transform := c.transform
	select(a.get_node("Asset").find_children("*", "MeshInstance3D", true, false)[0])
	await frames()
	check(plugin.selected_placement() == a and EditorInterface.get_selection().get_selected_nodes() == [a], "mesh选择路由Placement，不强制切工坊")
	check(not plugin.bridges.building.screen.visible, "仅选择不切工坊")
	print("[scene-assembly-stage] building bridge")
	plugin.edit_button.pressed.emit()
	await frames()
	var screen: Control = plugin.bridges.building.screen
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	await frames()
	check(screen.is_visible_in_tree() and screen.is_screen_active(), "装配请求真实切换房屋主屏，不手调可见性")
	check(not plugin.binding.is_empty(), "打开成功才建立token绑定")
	a.position += Vector3(2, 3, 4)
	var edited_transform := a.transform
	select(b)
	var old_path: String = a.get_node("Asset").scene_file_path
	var old_hash := FileAccess.get_sha256(old_path)
	var saved: Dictionary = screen.save_building()
	check(saved.get("ok", false), "工坊真实保存新revision")
	check(a.get_node("Asset").scene_file_path != old_path, "只更新绑定建筑")
	check(a.transform == edited_transform, "保存使用当前Placement变换")
	check(duplicate_house.transform == duplicate_transform and duplicate_house.get_node("Asset").scene_file_path == duplicate_path, "同源另一建筑实例路径和变换均不更新")
	check(b.transform == b_transform and c.transform == c_transform, "非目标变换保持")
	check(EditorInterface.get_selection().get_selected_nodes() == [b], "编辑中另选不改绑定并保留选择")
	check(FileAccess.get_sha256(old_path) == old_hash, "旧版本磁盘保持")
	history.undo()
	check(a.get_node("Asset").scene_file_path == old_path and a.transform == edited_transform, "换版undo保留摆放")
	history.redo()
	check(a.get_node("Asset").scene_file_path == saved.scene_path, "换版redo恢复外链")
	# 脏确认取消不能绑定到新目标。
	screen.session.apply_patch({"display_name": "待保存"})
	select(a)
	var prior_token: int = plugin.binding.token
	plugin.edit_selected()
	check(not plugin.pending.is_empty() and plugin.binding.token == prior_token, "脏确认阶段不提前绑定")
	screen._confirm.canceled.emit()
	screen._confirm.hide()
	check(plugin.pending.is_empty() and plugin.binding.token == prior_token, "取消保留原绑定")
	var original_data: Dictionary = a.get_meta(plugin.META).duplicate(true)
	var broken_data := original_data.duplicate(true)
	broken_data.recipe_path = "res://scenes/workshop_buildings/missing/building.recipe.json"
	a.set_meta(plugin.META, broken_data)
	plugin.edit_selected()
	if screen._confirm.visible:
		screen._confirm.hide()
		screen._confirm.confirmed.emit()
	check(plugin.pending.is_empty() and plugin.binding.token == prior_token, "打开失败不替换原绑定")
	a.set_meta(plugin.META, original_data)
	var failures_before := a.get_node("Asset").scene_file_path
	screen.export_root = "res://not_allowed"
	check(not screen.save_building().get("ok", false), "保存错误返回失败")
	check(a.get_node("Asset").scene_file_path == failures_before, "失败不发成功换版")
	screen.export_root = "res://scenes/workshop_buildings"
	print("[scene-assembly-stage] plant bridge")
	select(b)
	plugin.edit_selected()
	var plant_screen: Control = plugin.bridges.plant.screen
	if plant_screen._confirm.visible:
		plant_screen._confirm.hide()
		plant_screen._confirm.confirmed.emit()
	await frames()
	check(plant_screen.is_visible_in_tree() and plant_screen._screen_active, "装配请求真实切换树主屏，不手调可见性")
	check(plugin.binding.kind == "plant", "树安全打开绑定")
	var tree_old: String = b.get_node("Asset").scene_file_path
	var tree_saved: Dictionary = plant_screen.save_recipe()
	check(tree_saved.ok and b.get_node("Asset").scene_file_path == tree_old, "静态保存不把动态实例降级")
	check(plugin.status.text.contains("新版本已保存，实例未更新"), "静动态不匹配明确反馈")
	tree_saved = plant_screen.save_animated()
	check(tree_saved.ok and b.get_node("Asset").scene_file_path == tree_saved.animated_scene_path, "动态保存仅替换动态旁车")
	check(b.get_node("Asset").get_script().resource_path.ends_with("wind_runtime.gd"), "动态风脚本保持")
	plant_screen.input_recipe.height = float(plant_screen.input_recipe.height) + 0.2
	select(c)
	var plant_token: int = plugin.binding.token
	plugin.edit_selected()
	check(plant_screen._confirm.visible and plugin.binding.token == plant_token, "树脏确认不提前改绑定")
	plant_screen._confirm.hide()
	plant_screen._confirm.canceled.emit()
	check(plugin.pending.is_empty() and plugin.binding.token == plant_token, "树取消保留原目标")
	plant_screen.input_recipe = plant_screen.session.snapshot()
	var changed_data: Dictionary = b.get_meta(plugin.META).duplicate(true)
	changed_data.revision = "external_change"
	b.set_meta(plugin.META, changed_data)
	var before_external: String = b.get_node("Asset").scene_file_path
	check(plant_screen.save_animated().ok, "外部换版情况下仍保存新revision")
	check(b.get_node("Asset").scene_file_path == before_external and plugin.status.text.contains("实例未更新"), "外部换版拒绝陈旧绑定")
	b.set_meta(plugin.META, plugin.binding.data.duplicate(true))
	check(c.get_node("Asset").get_script() == null and c.transform == c_transform, "静态兄弟实例不受影响")
	EditorInterface.set_main_screen_editor("3D")
	select(a)
	await frames(10)
	var focus := InputEventKey.new()
	focus.keycode = KEY_F
	focus.physical_keycode = KEY_F
	focus.pressed = true
	var surface: Control = plugin.surfaces[0]
	mouse(surface.global_position + surface.size * 0.5, false, true)
	Input.parse_input_event(focus)
	await plugin.get_tree().create_timer(0.8).timeout
	focus.pressed = false
	Input.parse_input_event(focus)
	for step in 20:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = surface.global_position + surface.size * 0.5
		wheel.global_position = wheel.position
		Input.parse_input_event(wheel)
		wheel = wheel.duplicate()
		wheel.pressed = false
		Input.parse_input_event(wheel)
		await frames(2)
	await plugin.get_tree().create_timer(0.5).timeout
	check(not plugin._thumbnails.is_empty(), "已保存候选有真实静态缩略图缓存")
	await screenshot("assembled")
	print("[scene-assembly-stage] bridge lifecycle")
	await bridge_lifecycle(a, b)
	plant_screen = plugin.bridges.plant.screen
	check(EditorInterface.save_scene() == OK, "真实Editor保存隔离场景")
	var text := FileAccess.get_file_as_string("res://outputs/assembly_fixture.tscn")
	check(text.contains("instance=ExtResource") and text.contains("metadata/sea_placement"), "场景序列化外链与绑定metadata")
	# 删除目标后保存仍保留新revision，但不得修改其他实例。
	select(b)
	plugin.edit_selected()
	if plant_screen._confirm.visible:
		plant_screen._confirm.hide()
		plant_screen._confirm.confirmed.emit()
	parent = b.get_parent()
	parent.remove_child(b)
	var deleted_save: Dictionary = plant_screen.save_animated()
	check(deleted_save.ok and FileAccess.file_exists(deleted_save.animated_scene_path), "目标删除后新revision不回滚磁盘")
	check(plugin.status.text.contains("新版本已保存，实例未更新"), "目标删除明确未更新")
	parent.add_child(b)
	b.owner = root
	b.get_node("Asset").owner = root
	# 用真实重载入口验证磁盘场景，不把内存pack重载冒充编辑器重开。
	EditorInterface.reload_scene_from_path("res://outputs/assembly_fixture.tscn")
	await frames(20)
	root = EditorInterface.get_edited_scene_root()
	var placements: Array[Node] = []
	for node in root.find_children("*", "Node3D", true, false):
		if node.has_meta(plugin.META): placements.append(node)
	check(placements.size() == 4, "Editor重开恢复四个Placement")
	for node in placements:
		check(node.get_script() == null and node.get_node("Asset").owner == root, "重开owner与无运行脚本包装")
		check(node.get_node("Asset").scene_file_path == node.get_meta(plugin.META).scene_path, "重开metadata路径与外链一致")
	EditorInterface.set_main_screen_editor("3D")
	await screenshot("reopened")
	var detached_before: String = placements[0].get_node("Asset").scene_file_path
	check(plant_screen.save_animated().ok, "旧场景重载失效后仍保留新revision")
	check(plugin.status.text.contains("实例未更新") and placements[0].get_node("Asset").scene_file_path == detached_before, "场景关闭重载后陈旧实例不更新")
	# 旧modular仅允许摆放，禁止误导用户回编。
	var legacy_data: Dictionary = placements[0].get_meta(plugin.META).duplicate(true)
	legacy_data.editable = false
	placements[0].set_meta(plugin.META, legacy_data)
	select(placements[0])
	await frames()
	check(plugin.edit_button.disabled and plugin.status.text.contains("不可回编"), "历史modular编辑禁用并说明")
	check(Library.describe("res://scenes/workshop_plants/../escape", "plant").is_empty(), "候选路径越界拒绝")
	await finish()

func screenshot(label: String) -> void:
	await frames(5)
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty(), "真实编辑器截图：" + label)
	image.save_png("res://outputs/scene_assembly_" + label + ".png")

func finish() -> void:
	evidence.merge({"checks": checks, "check_results": check_results, "failures": failures, "passed": failures.is_empty(), "enginehint": Engine.is_editor_hint(), "main_protection": {"main_absent": not FileAccess.file_exists("res://scenes/main.tscn"), "isolated_user_dir": ProjectSettings.get_setting("application/config/custom_user_dir_name", "")}, "input_chain": "Viewport.warp_mouse + Input.parse_input_event → ItemList._get_drag_data → Control._can_drop_data/_drop_data → EditorUndoRedoManager", "automation_boundary": "自动GUI覆盖建筑和动态树真实拖放；补充静态树/同源实例由API建立；工坊保存、undo/redo及真实Editor保存重开自动断言。未替代人工OS窗口激活、物理鼠标和gizmo手感验收。"})
	plugin.get_window().always_on_top = window_was_on_top
	EditorInterface.get_selection().clear()
	EditorInterface.edit_node(EditorInterface.get_edited_scene_root())
	var tree := plugin.get_tree()
	plugin.get_undo_redo().clear_history()
	print("[scene-assembly-stage] history cleared")
	EditorInterface.save_scene()
	var close_scene := InputEventKey.new()
	close_scene.keycode = KEY_W
	close_scene.physical_keycode = KEY_W
	close_scene.meta_pressed = OS.get_name() == "macOS"
	close_scene.ctrl_pressed = OS.get_name() != "macOS"
	close_scene.pressed = true
	Input.parse_input_event(close_scene)
	await tree.create_timer(1.0).timeout
	close_scene.pressed = false
	Input.parse_input_event(close_scene)
	print("[scene-assembly-stage] closed root: ", EditorInterface.get_edited_scene_root())
	await tree.create_timer(1.0).timeout
	var bridge_connections: Array = []
	for connection: Dictionary in plugin._bridge_connections.values(): bridge_connections.append_array(connection.connections)
	var node_added_callback := Callable(plugin, "_bridge_node_added")
	# 留一个已排队刷新，确认卸载后不会重新接回工坊。
	plugin._queue_bridge_refresh()
	EditorInterface.set_plugin_enabled("scene_assembly", false)
	await tree.process_frame
	check_disconnected(bridge_connections, "装配卸载")
	check(not tree.node_added.is_connected(node_added_callback), "装配卸载断开editor tree监听")
	evidence.merge({"checks": checks, "check_results": check_results, "failures": failures, "passed": failures.is_empty()}, true)
	var file := FileAccess.open("res://outputs/scene_assembly_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	print("[scene-assembly] %d checks, %d failures" % [checks, failures.size()])
	EditorInterface.set_plugin_enabled("plant_editor", false)
	EditorInterface.set_plugin_enabled("building_workshop", false)
	await tree.create_timer(0.5).timeout
	print("[scene-assembly-stage] plugins unloaded")
	tree.quit(0 if failures.is_empty() else 1)
