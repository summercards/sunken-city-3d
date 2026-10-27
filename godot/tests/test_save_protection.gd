extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	var protected: bool=main._save_protected and not main._autosave_on
	main._process(121.0)
	var unchanged: bool=FileAccess.get_file_as_string("user://save_slot_0.json")=='{"version":999}'
	var rejected: bool=not main.save_game().ok
	var separate: bool=main.save_game("user://new_slot.json").ok
	var ok := protected and unchanged and rejected and separate
	print("[save-protection] ok=",ok," protected=",protected," unchanged=",unchanged," separate=",separate)
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
