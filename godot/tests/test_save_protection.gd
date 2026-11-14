extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	# B2 将临时槽位保护与用户自动保存开关分离；验证实际不写盘，而非开关被永久关闭。
	var protected: bool=main._save_protected
	var left: float=main._autosave_left
	main._process(121.0)
	protected = protected and main._autosave_left == left
	var unchanged: bool=FileAccess.get_file_as_string("user://save_slot_0.json")=='{"version":999}'
	var rejected: bool=not main.save_game().ok
	var separate: bool=main.save_game("user://new_slot.json").ok
	var ok := protected and unchanged and rejected and separate
	print("[save-protection] ok=",ok," protected=",protected," unchanged=",unchanged," separate=",separate)
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
