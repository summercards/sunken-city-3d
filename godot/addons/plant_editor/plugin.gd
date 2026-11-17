@tool
extends EditorPlugin

const Screen = preload("res://addons/plant_editor/editor_screen.gd")
const DRAFT_PATH := "user://plant_authoring_draft.json"

var screen: Control
var _verification_started := false
var _draft_timer: Timer
# 只有确认无旧草稿或完整恢复成功后才放行写入；失败保持锁定至插件重载。
var _draft_write_allowed: bool = false

func _enter_tree() -> void:
	_draft_write_allowed = false
	screen = Screen.new()
	EditorInterface.get_editor_main_screen().add_child(screen)
	_make_visible(false)
	add_tool_menu_item("树木工坊", _show_workshop)
	_draft_timer = Timer.new()
	_draft_timer.wait_time = 4.0
	_draft_timer.timeout.connect(_save_draft)
	add_child(_draft_timer)
	if _is_verification():
		call_deferred("_run_verification")
	else:
		call_deferred("_restore_draft")

func _exit_tree() -> void:
	remove_tool_menu_item("树木工坊")
	_save_draft()
	if is_instance_valid(screen):
		screen.set_screen_visible(false)
		screen.queue_free()
		screen = null
	if is_instance_valid(_draft_timer):
		_draft_timer.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "树木工坊"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node3D", "EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(screen):
		screen.set_screen_visible(value)

func _show_workshop() -> void:
	EditorInterface.set_main_screen_editor(_get_plugin_name())
	_make_visible(true)

func request_document(path: String, token: int) -> void:
	_show_workshop()
	screen.request_document(path, token)

func _save_external_data() -> void:
	_save_draft()

func _is_verification() -> bool:
	return OS.get_cmdline_user_args().has("--plant-editor-verify")

func _draft_io_allowed() -> bool:
	if not _is_verification():
		return true
	var args: PackedStringArray = OS.get_cmdline_args()
	if not Engine.is_editor_hint() or not args.has("--editor") or args.has("--script") or args.has("-s") or not OS.get_cmdline_user_args().has("--workshop-switch-verify"):
		return false
	var token: String = str(ProjectSettings.get_setting("verification/workshop_switch_token", ""))
	var root: String = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var expected_root: String = OS.get_environment("SEA_WORKSHOP_SWITCH_PROJECT").simplify_path().trim_suffix("/")
	if token.is_empty() or token != OS.get_environment("SEA_WORKSHOP_SWITCH_TOKEN") or root != expected_root or root.get_file() != "project":
		return false
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var expected_user: String = OS.get_environment("SEA_WORKSHOP_SWITCH_USER").simplify_path().trim_suffix("/")
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) or not str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("sea-verification/") or user_root != expected_user:
		return false
	if DirAccess.dir_exists_absolute("res://src/bootstrap") or FileAccess.file_exists("res://scenes/main.tscn") or not str(ProjectSettings.get_setting("application/run/main_scene", "")).is_empty() or not is_inside_tree():
		return false
	for property: Dictionary in ProjectSettings.get_property_list():
		if str(property.name).begins_with("autoload/"):
			return false
	for node: Node in get_tree().root.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if node.name == &"Main" or (script != null and script.resource_path.begins_with("res://src/bootstrap/")):
			return false
	return true

func _save_draft() -> void:
	if not _draft_write_allowed or not _draft_io_allowed() or not is_instance_valid(screen) or not screen.is_node_ready():
		return
	var draft: Dictionary = screen.get_recovery()
	var temporary: String = DRAFT_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("树木工坊草稿不可写；请保存配方")
		return
	file.store_string(JSON.stringify(draft, "\t", true, true))
	var error: Error = file.get_error()
	file.close()
	var parsed := JSON.new()
	if error == OK and parsed.parse(FileAccess.get_file_as_string(temporary)) == OK and parsed.data is Dictionary:
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(DRAFT_PATH)) != OK:
			push_warning("树木工坊草稿提交失败；原草稿保持")

func _restore_draft() -> void:
	_draft_write_allowed = false
	if not _draft_io_allowed() or not is_instance_valid(screen) or not screen.is_node_ready():
		return
	if FileAccess.file_exists(DRAFT_PATH):
		var file: FileAccess = FileAccess.open(DRAFT_PATH, FileAccess.READ)
		if file == null:
			_preserve_draft("无法读取：" + error_string(FileAccess.get_open_error()))
			return
		if file.get_length() > 2 * 1024 * 1024:
			file.close()
			_preserve_draft("文件超过 2 MiB")
			return
		var text: String = file.get_as_text()
		var read_error: Error = file.get_error()
		file.close()
		if read_error != OK:
			_preserve_draft("读取失败：" + error_string(read_error))
			return
		var parser: JSON = JSON.new()
		if parser.parse(text) != OK or not parser.data is Dictionary:
			_preserve_draft("JSON 损坏或根对象不是字典")
			return
		var result: Dictionary = screen.restore_recovery(parser.data)
		if not bool(result.get("ok", false)):
			_preserve_draft(str(result.get("reason", "恢复失败")))
			return
	_draft_write_allowed = true
	_draft_timer.start()

func _preserve_draft(reason: String) -> void:
	_draft_write_allowed = false
	if is_instance_valid(_draft_timer):
		_draft_timer.stop()
	var message: String = "原草稿已保留，自动及退出草稿写入已禁用：%s。请另存配方；修复或备份原草稿后重新加载插件。" % reason
	push_warning("树木工坊：" + message)
	if is_instance_valid(screen):
		screen.report_draft_preserved(message)

func _run_verification() -> void:
	if _verification_started or not Engine.is_editor_hint():
		return
	_verification_started = true
	await get_tree().process_frame
	await get_tree().process_frame
	var script := load("res://addons/plant_editor/editor_verification.gd") as Script
	if script == null:
		printerr("[plant-editor] 1 checks, 1 failures: verifier unavailable")
		get_tree().quit(1)
		return
	await script.run(self)
