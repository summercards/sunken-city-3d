extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	root.get_node("Economy").coins=98765
	main.world_clock.day=17
	main.weather_service.set_weather("rain")
	var result: Dictionary = main.save_game()
	print("[save-seed] ok=",result.ok)
	main.queue_free()
	await process_frame
	quit(0 if result.ok else 1)
