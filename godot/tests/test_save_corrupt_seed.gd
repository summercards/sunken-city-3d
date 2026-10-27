extends SceneTree
func _init() -> void:
	var file := FileAccess.open("user://save_slot_0.json",FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	print("[save-corrupt-seed] complete")
	quit()
