extends SceneTree
func _init() -> void: call_deferred("run")
func nodes_under(node: Node, out: Array) -> void:
	out.append(node)
	for child in node.get_children(): nodes_under(child, out)
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	for i in 20: await process_frame
	var nodes: Array = []
	nodes_under(main,nodes)
	var modes: Array = []
	for n in nodes: modes.append([n, n.is_processing(), n.is_physics_processing()])
	for mode in ["normal", "physics_off", "process_off", "main_off"]:
		for row in modes:
			if is_instance_valid(row[0]):
				row[0].set_process(row[1] and not (mode == "process_off" or (mode == "main_off" and row[0] == main)))
				row[0].set_physics_process(row[2] and mode != "physics_off")
		for i in 10: await process_frame
		var frames: Array = []
		var stamp := Time.get_ticks_usec()
		for i in 40:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now-stamp)/1000.0); stamp = now
		frames.sort()
		var sum := 0.0
		for t in frames: sum += t
		print("[frame-subsystems] ", JSON.stringify({"mode":mode,"fps":40000.0/sum,"p50_ms":frames[20],"p95_ms":frames[38]}))
	print("[frame-subsystems] complete")
	quit()
