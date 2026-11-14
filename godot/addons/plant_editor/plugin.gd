@tool
extends EditorPlugin

const Screen = preload("res://addons/plant_editor/editor_screen.gd")
const DRAFT_PATH := "user://plant_authoring_draft.json"

var screen: Control
var _verification_started := false
var _draft_timer: Timer

func _enter_tree() -> void:
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
		_draft_timer.start()

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

func _save_external_data() -> void:
	_save_draft()

func _is_verification() -> bool:
	return OS.get_cmdline_user_args().has("--plant-editor-verify")

func _save_draft() -> void:
	if _is_verification() or not is_instance_valid(screen) or not screen.is_node_ready():
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
	if not is_instance_valid(screen) or not FileAccess.file_exists(DRAFT_PATH):
		return
	var file := FileAccess.open(DRAFT_PATH, FileAccess.READ)
	if file == null or file.get_length() > 2 * 1024 * 1024:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		screen.restore_recovery(data)

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
