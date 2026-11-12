@tool
extends EditorPlugin
## 编辑器生产入口；不实例化运行版 Panel，不打开 Main，不改编辑场景。

const ScreenScript = preload("res://addons/building_workshop/editor_screen.gd")
const StoreScript = preload("res://addons/building_workshop/editor_store.gd")
const AdapterScript = preload("res://addons/building_workshop/catalog_adapter.gd")
const RECOVERY_PATH: String = "user://building_workshop_editor/recovery.json"

var screen: Control
var store: RefCounted
var adapter: RefCounted
var _verification_started: bool = false

func _enter_tree() -> void:
	store = StoreScript.new()
	adapter = AdapterScript.new()
	_create_screen()
	add_tool_menu_item("老王场景工坊", Callable(self, "_show_workshop"))
	if OS.get_cmdline_user_args().has("--workshop-editor-verify"):
		call_deferred("_run_verification")

func _create_screen(recovery: Dictionary = {}) -> void:
	screen = ScreenScript.new()
	screen.configure({"store": store, "editor_plugin": self,
		"replace_component": Callable(self, "_replace_component"),
		"export_module_component": Callable(self, "_export_module"),
		"open_scene": Callable(self, "_open_scene"), "rescan": Callable(self, "_rescan")})
	EditorInterface.get_editor_main_screen().add_child(screen)
	_make_visible(false)
	if recovery.is_empty() and not OS.get_cmdline_user_args().has("--workshop-editor-verify"):
		recovery = _read_recovery()
	if not recovery.is_empty():
		screen.restore_recovery(recovery)

func _exit_tree() -> void:
	remove_tool_menu_item("老王场景工坊")
	if is_instance_valid(screen):
		_save_recovery()
		screen.set_screen_visible(false)
		screen.queue_free()
		screen = null

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "老王场景工坊"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("MeshInstance3D", "EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(screen):
		screen.set_screen_visible(value)

func _show_workshop() -> void:
	EditorInterface.set_main_screen_editor(_get_plugin_name())
	_make_visible(true)

func _save_external_data() -> void:
	_save_recovery()

func _save_recovery() -> void:
	if not is_instance_valid(screen) or not screen.is_node_ready():
		return
	var recovery: Dictionary = screen.get_recovery()
	var absolute_parent: String = ProjectSettings.globalize_path(RECOVERY_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_parent) != OK:
		push_warning("老王场景工坊草稿备份目录不可写；请先保存楼房")
		return
	var temporary: String = RECOVERY_PATH + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("老王场景工坊草稿未备份")
		return
	file.store_string(JSON.stringify(recovery, "\t"))
	file.close()
	var verify: FileAccess = FileAccess.open(temporary, FileAccess.READ)
	if verify == null:
		return
	var parsed: Variant = JSON.parse_string(verify.get_as_text())
	verify.close()
	if parsed is Dictionary:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(RECOVERY_PATH))

func _read_recovery() -> Dictionary:
	if not FileAccess.file_exists(RECOVERY_PATH):
		return {}
	var file: FileAccess = FileAccess.open(RECOVERY_PATH, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data is Dictionary else {}

func _replace_component(session: RefCounted, _component_id: String, path: String) -> Dictionary:
	# 默认只替换当前槽；全局同ID可能有不同尺寸，不能连带拉伸其他门窗。
	return AdapterScript.apply_prefab_to_slot(session, str(screen.preview.selected_slot()), path)

func _export_module(session: RefCounted) -> Dictionary:
	var result: Dictionary = AdapterScript.export_slot(session, str(screen.preview.selected_slot()))
	if bool(result.get("ok", false)):
		_rescan()
	return result

func _open_scene(path: String) -> void:
	if path.begins_with("res://scenes/workshop_buildings/") or path.begins_with("res://outputs/workshop_editor/"):
		EditorInterface.open_scene_from_path(path)

func _rescan() -> void:
	# 保存调用栈中不重入全目录扫描，避免首次导入时重复激活插件。
	call_deferred("_update_saved_files")

func _update_saved_files() -> void:
	if not is_instance_valid(screen):
		return
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if filesystem.is_scanning():
		await filesystem.filesystem_changed
	if not is_instance_valid(screen):
		return
	var exported: Dictionary = screen.get_recovery().get("last_export", {})
	for key: String in ["scene_path", "recipe_path", "manifest_path", "catalog_path", "ledger_path"]:
		var path: String = str(exported.get(key, ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			filesystem.update_file(path)

func rebuild_screen_for_verification() -> Dictionary:
	var recovery: Dictionary = screen.get_recovery()
	_make_visible(false)
	var old: Control = screen
	EditorInterface.get_editor_main_screen().remove_child(old)
	old.queue_free()
	_create_screen(recovery)
	return recovery

func _run_verification() -> void:
	if _verification_started or not Engine.is_editor_hint():
		return
	_verification_started = true
	print("[workshop-editor-stage] plugin ready")
	# 插件启用本身处于文件扫描回调中，不在此等待同一扫描结束，避免循环等待。
	await get_tree().create_timer(2.0).timeout
	print("[workshop-editor-stage] starting editor checks")
	var script: Script = load("res://addons/building_workshop/editor_verification.gd") as Script
	if script == null:
		printerr("[workshop-editor] 1 checks, 1 failures: verifier unavailable")
		get_tree().quit(1)
		return
	await script.run(self)
