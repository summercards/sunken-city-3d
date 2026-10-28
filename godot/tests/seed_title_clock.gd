extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false)
	root.get_node("Economy").ticking=false
	main.world_clock.paused=true
	var ok:=true
	for entry in [["day",4,9.0],["night",4,21.25],["dawn",5,6.0]]:
		main.world_clock.from_dict({"day":entry[1],"seconds":entry[2]*3600.0,"day_length":1200.0})
		var result: Dictionary=main.save_game("user://title-clock-"+entry[0]+".json",true)
		ok=ok and result.get("ok",false)
	main.queue_free();await process_frame
	print("[title-clock-seed] ok=",ok);quit(0 if ok else 1)
