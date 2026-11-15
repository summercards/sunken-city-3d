@tool
extends EditorPlugin

const Library = preload("res://addons/scene_assembly/library.gd")
const LibraryList = preload("res://addons/scene_assembly/library_list.gd")
const DropSurface = preload("res://addons/scene_assembly/drop_surface.gd")
const META := "sea_placement"

var dock: VBoxContainer
var items: ItemList
var edit_button: Button
var status: Label
var drop_height: SpinBox
var surfaces: Array[Control] = []
var bridges: Dictionary = {}
var pending: Dictionary = {}
var binding: Dictionary = {}
var serial := 0
var _routing := false
var _selection: EditorSelection
var _thumbnails: Dictionary = {}
var _thumbnail_queue: Array[String] = []
var _thumbnail_busy := false
var _thumbnail_view: SubViewport

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "场景装配"
	dock.custom_minimum_size.x = 260
	var note := Label.new()
	note.text = "候选库 · 拖入3D视口\n原生 gizmo 移动/旋转/缩放\n用途未正式注册；不自动接入通行或水下适配"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(note)
	var refresh := Button.new()
	refresh.text = "刷新已保存预览库"
	refresh.pressed.connect(refresh_library)
	dock.add_child(refresh)
	var height_row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = "放置平面世界 Y"
	height_row.add_child(caption)
	drop_height = SpinBox.new()
	drop_height.min_value = -10000
	drop_height.max_value = 10000
	drop_height.step = 0.1
	height_row.add_child(drop_height)
	dock.add_child(height_row)
	items = LibraryList.new()
	items.assembly = self
	items.fixed_icon_size = Vector2i(96, 96)
	items.icon_mode = ItemList.ICON_MODE_TOP
	items.max_columns = 2
	items.fixed_column_width = 135
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.custom_minimum_size.y = 240
	dock.add_child(items)
	edit_button = Button.new()
	edit_button.text = "编辑选中实例（原工坊）"
	edit_button.pressed.connect(edit_selected)
	dock.add_child(edit_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_selection = EditorInterface.get_selection()
	_selection.selection_changed.connect(_selection_changed)
	scene_closed.connect(_scene_closed)
	call_deferred("_setup")

func _setup() -> void:
	_thumbnail_view = preload("res://addons/scene_assembly/thumbnail.gd").new()
	add_child(_thumbnail_view)
	for index in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(index)
		if viewport == null: continue
		var surface := DropSurface.new()
		surface.name = "SceneAssemblyDrop"
		surface.assembly = self
		surface.viewport_index = index
		var container: Control = viewport.get_parent()
		container.get_parent().add_child(surface)
		surface.position = container.position
		surface.size = container.size
		container.resized.connect(func() -> void:
			surface.position = container.position
			surface.size = container.size)
		surface.hide()
		surfaces.append(surface)
	_connect_bridges(get_tree().root)
	refresh_library()
	if OS.get_cmdline_user_args().has("--scene-assembly-verify"):
		await get_tree().create_timer(2.0).timeout
		var verifier: Script = load("res://tests/test_scene_assembly_editor.gd")
		if verifier == null or not verifier.can_instantiate():
			get_tree().quit(1)
			return
		await verifier.run(self)

func _connect_bridges(node: Node) -> void:
	var script: Script = node.get_script()
	if script != null:
		var path := script.resource_path
		var kind := "building" if path == "res://addons/building_workshop/plugin.gd" else "plant" if path == "res://addons/plant_editor/plugin.gd" else ""
		if not kind.is_empty():
			bridges[kind] = node
			node.screen.document_opened.connect(_document_opened.bind(kind))
			node.screen.document_request_finished.connect(_request_finished.bind(kind))
			node.screen.revision_saved.connect(_revision_saved.bind(kind))
	for child in node.get_children(): _connect_bridges(child)

func _exit_tree() -> void:
	if is_instance_valid(_selection): _selection.selection_changed.disconnect(_selection_changed)
	for surface in surfaces:
		if is_instance_valid(surface): surface.queue_free()
	remove_control_from_docks(dock)
	dock.queue_free()

func report(message: String) -> void:
	status.text = message
	status.tooltip_text = message

func refresh_library(announce: bool = true) -> void:
	items.clear()
	var plants := 0
	for row: Dictionary in Library.collect():
		if row.kind == "plant": plants += 1
		var label: String = str(row.label) + "\n" + str(row.revision) + (" · 动态风" if row.animated else " · 静态")
		var index := items.add_item(label, _thumbnails.get(row.preview_path))
		items.set_item_metadata(index, row)
		items.set_item_tooltip(index, "%s\n用途：%s · 未正式注册\n%s" % [row.recipe_path, row.purpose, "旧 modular 仅可摆放，不可回编" if not row.editable else "选中场景实例后点击编辑"])
		if not _thumbnails.has(row.preview_path) and not _thumbnail_queue.has(row.preview_path):
			_thumbnail_queue.append(row.preview_path)
	call_deferred("_render_thumbnails")
	if announce:
		report("建筑与树均为候选，场景由你手动保存。" + ("\n树库为空：先到树木工坊保存静态或动态版本。" if plants == 0 else ""))
	_selection_changed()

func _render_thumbnails() -> void:
	if _thumbnail_busy or not is_instance_valid(_thumbnail_view): return
	_thumbnail_busy = true
	while not _thumbnail_queue.is_empty() and is_inside_tree():
		var path: String = _thumbnail_queue.pop_front()
		var texture: Texture2D = await _thumbnail_view.capture(path)
		if not is_inside_tree(): return
		_preview_ready(path, texture, null, null)
	_thumbnail_busy = false

func _preview_ready(path: String, texture: Texture2D, _small: Texture2D, _data: Variant) -> void:
	if texture == null: return
	_thumbnails[path] = texture
	for index in items.item_count:
		if items.get_item_metadata(index).preview_path == path: items.set_item_icon(index, texture)

func arm_drop(_entry: Dictionary) -> void:
	for surface in surfaces:
		surface.get_parent().move_child(surface, -1)
		surface.show()

func can_insert() -> bool:
	return EditorInterface.get_edited_scene_root() is Node3D

func placement_for(node: Node) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	while is_instance_valid(node) and node != root:
		if node is Node3D and node.has_meta(META): return node
		node = node.get_parent()
	return null

func selected_placement() -> Node3D:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	return placement_for(selected[0]) if selected.size() == 1 else null

func _selection_changed() -> void:
	if _routing: return
	var placement := selected_placement()
	edit_button.disabled = placement == null or not bool(placement.get_meta(META).get("editable", false))
	if placement == null: return
	if not placement.get_meta(META).get("editable", false):
		report("旧 modular 历史建筑不可回编；可原生摆放，原文件保持。")
	var selection := EditorInterface.get_selection()
	if not selection.get_selected_nodes().has(placement):
		_routing = true
		selection.clear()
		selection.add_node(placement)
		_routing = false

func insert_candidate(entry: Dictionary, world_position: Vector3) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if not root is Node3D: return {"ok": false}
	var fresh := Library.describe(str(entry.get("recipe_path", "")), str(entry.get("kind", "")), bool(entry.get("animated", false)))
	if fresh.is_empty():
		report("候选文件已失效，请刷新预览库。")
		return {"ok": false}
	var packed := load(str(fresh.scene_path)) as PackedScene
	if packed == null: return {"ok": false}
	var asset := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if asset == null: return {"ok": false}
	var parent: Node3D = root
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() == 1 and selected[0] is Node3D and placement_for(selected[0]) == null and (selected[0] == root or selected[0].owner == root): parent = selected[0]
	var placement := Node3D.new()
	placement.name = "Placement_" + str(fresh.kind)
	fresh["instance_id"] = str(Time.get_unix_time_from_system()) + "_" + str(placement.get_instance_id())
	placement.set_meta(META, fresh)
	asset.name = "Asset"
	placement.add_child(asset)
	placement.position = parent.to_local(world_position)
	var undo := get_undo_redo()
	undo.create_action("装配候选实例", UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(self, "_attach", parent, placement, root, parent.get_child_count())
	undo.add_do_method(self, "_select_nodes", [placement])
	undo.add_undo_method(self, "_detach", parent, placement)
	undo.add_undo_method(self, "_select_nodes", selected)
	undo.add_do_reference(placement)
	undo.commit_action()
	report("已插入候选；使用原生 gizmo 编辑。未自动保存场景。")
	return {"ok": true, "placement": placement}

func _attach(parent: Node, node: Node, owner_node: Node, index: int) -> void:
	parent.add_child(node, true)
	parent.move_child(node, mini(index, parent.get_child_count() - 1))
	node.owner = owner_node
	if node.has_meta(META): node.get_node("Asset").owner = owner_node

func _detach(parent: Node, node: Node) -> void:
	parent.remove_child(node)

func _select_nodes(nodes: Array) -> void:
	_routing = true
	var selection := EditorInterface.get_selection()
	selection.clear()
	for node in nodes:
		if is_instance_valid(node) and node.is_inside_tree(): selection.add_node(node)
	_routing = false
	_selection_changed()

func edit_selected() -> void:
	var target := selected_placement()
	if target == null: return
	var data: Dictionary = target.get_meta(META)
	if not data.editable:
		report("旧 modular 历史建筑不可回编。")
		return
	var kind := str(data.kind)
	if not bridges.has(kind) or not is_instance_valid(bridges[kind]):
		report("对应工坊未启用，请在插件设置启用。")
		return
	if not pending.is_empty():
		report("请先处理工坊的未保存确认窗口。")
		return
	serial += 1
	pending = {"token": serial, "kind": kind, "target": weakref(target), "root": weakref(EditorInterface.get_edited_scene_root()),
		"scene": EditorInterface.get_edited_scene_root().scene_file_path, "node_path": EditorInterface.get_edited_scene_root().get_path_to(target), "data": data.duplicate(true), "asset": weakref(target.get_node("Asset"))}
	bridges[kind].request_document(str(data.recipe_path), serial)

func _document_opened(_path: String, token: int, kind: String) -> void:
	if token == 0:
		if not binding.is_empty() and binding.kind == kind: binding.clear()
		return
	if not pending.is_empty() and pending.token == token and pending.kind == kind:
		binding = pending.duplicate()
		pending.clear()
		report("工坊已绑定此实例；另选节点不会改变目标。保存新版本后只更新此实例。")

func _request_finished(token: int, result: Dictionary, _kind: String) -> void:
	if not pending.is_empty() and pending.token == token:
		pending.clear()
		if not result.get("ok", false): report("未切换编辑绑定：" + str(result.get("reason", "打开失败")))

func _scene_closed(path: String) -> void:
	if not binding.is_empty() and binding.scene == path: binding["closed"] = true
	if not pending.is_empty() and pending.scene == path: pending["closed"] = true

func _revision_saved(token: int, result: Dictionary, kind: String) -> void:
	call_deferred("refresh_library", false)
	if binding.is_empty() or binding.token != token or binding.kind != kind: return
	var target: Node3D = binding.target.get_ref()
	var root: Node = binding.root.get_ref()
	var old_asset: Node = binding.asset.get_ref()
	var reason := ""
	if binding.get("closed", false) or root == null or root != EditorInterface.get_edited_scene_root(): reason = "目标场景已关闭或不再是当前场景"
	elif target == null or not root.is_ancestor_of(target): reason = "目标实例已删除"
	elif root.get_path_to(target) != binding.node_path: reason = "目标实例路径已改变"
	elif target.get_meta(META, {}) != binding.data or old_asset == null or old_asset.get_parent() != target: reason = "目标实例已换版"
	var path := str(result.get("animated_scene_path" if binding.data.animated else "scene_path", ""))
	if reason.is_empty() and path.is_empty(): reason = "动态实例需要工坊的保存动态风版本，不能替换为静态场景"
	if not reason.is_empty():
		report("新版本已保存，实例未更新：" + reason)
		return
	var data := Library.describe(str(result.recipe_path), kind, bool(binding.data.animated))
	if data.is_empty() or data.asset_id != binding.data.asset_id:
		report("新版本已保存，实例未更新：新候选不可读取或文档身份已改变")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		report("新版本已保存，实例未更新：场景加载失败")
		return
	var asset := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	asset.name = old_asset.name
	data["instance_id"] = binding.data.instance_id
	var previous: Dictionary = target.get_meta(META).duplicate(true)
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var index := old_asset.get_index()
	var undo := get_undo_redo()
	undo.create_action("工坊更新绑定实例", UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(self, "_replace", target, old_asset, asset, root, index, data, selected)
	undo.add_undo_method(self, "_replace", target, asset, old_asset, old_asset.owner, index, previous, selected)
	undo.add_do_reference(asset)
	undo.add_undo_reference(old_asset)
	undo.commit_action()
	binding.data = data.duplicate(true)
	binding.asset = weakref(asset)
	report("新版本已保存，仅绑定实例已更新；摆放变换保持，场景尚未自动保存。")

func _replace(target: Node, old: Node, next: Node, owner_node: Node, index: int, data: Dictionary, selected: Array) -> void:
	target.remove_child(old)
	_attach(target, next, owner_node, index)
	target.set_meta(META, data.duplicate(true))
	_select_nodes(selected)
