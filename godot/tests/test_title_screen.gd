extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	check(main._title_active and main.start_screen != null,"default boot shows title")
	var time: Dictionary = main.world_clock.to_dict()
	var coins: int = root.get_node("Economy").coins
	var pickups: Dictionary = main.props.to_dict()
	check(not main.props.visible,"title hides collectible rings")
	for entry in main._title_layers:
		check(not entry.node.visible,"title hides "+entry.node.name)
	main._on_click_command("bag")
	main._on_destination("zone5")
	check(not main.hud.is_panel_open() and not main.boat.starts_sailing(),"title blocks gameplay commands")
	await create_timer(2.1).timeout
	check(main.world_clock.to_dict()==time and root.get_node("Economy").coins==coins,"title does not advance economy or clock")
	check(main.props.to_dict()==pickups,"title freezes fish respawn timers")
	check(main.start_screen.logo.modulate.a>0.99 and main.start_screen.start_button.modulate.a>0.99,"elegant reveal finishes")
	check(main.start_screen.start_button.text=="开始游戏","single start action")
	check(main.start_screen.start_button.get_theme_font("font")==main.start_screen.logo.get_child(0).get_theme_font("font"),"logo and start use same custom face")
	if DisplayServer.get_name() != "headless":
		await process_frame
		root.get_texture().get_image().save_png("res://outputs/sea-start-screen.png")
	# Deliver an actual GUI click, not a direct game-start call.
	var button: Button = main.start_screen.start_button
	var position: Vector2 = button.get_global_transform_with_canvas() * (button.size*0.5)
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = position
		click.pressed = pressed
		root.push_input(click,true)
		await process_frame
	await create_timer(1.9).timeout
	check(not main._title_active and main.start_screen==null,"actual start click enters world")
	check(main.hud.visible and main.markers.visible,"gameplay UI restored")
	check(main.world_clock.seconds>float(time.seconds),"world time resumes")
	main._on_click_command("shop")
	check(main.hud.is_panel_open(),"game controls work after entry")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("res://outputs/sea-start-entered.png")
	print("[title-screen] ",checks," checks, ",failures," failures")
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
