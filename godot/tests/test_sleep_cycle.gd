extends SceneTree
var checks := 0
var failures := 0
var main
var iris_phases: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func click(point: Vector2) -> void:
	for down in [true,false]:
		var e := InputEventMouseButton.new()
		e.button_index=MOUSE_BUTTON_LEFT
		e.position=point
		e.pressed=down
		root.push_input(e,true)
		await process_frame

func wait_phase(value: String) -> void:
	for i in 1200:
		if main.sleep_curtain.phase==value: return
		await process_frame
	check(false,"transition reaches "+value)

func iris_snapshot(name: String) -> Image:
	if DisplayServer.get_name()=="headless": return null
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	image.save_png("res://outputs/"+name+".png")
	return image

func check_aperture(image: Image, label: String) -> void:
	if image==null: return
	var focus: Vector2=main.sleep_curtain.iris.get_shader_parameter("focus_uv")
	var centre := Vector2i((focus*Vector2(image.get_size())).clamp(Vector2.ZERO,Vector2(image.get_size()-Vector2i.ONE)))
	var corner := Vector2i(0 if focus.x>0.5 else image.get_width()-1,0 if focus.y>0.5 else image.get_height()-1)
	check(image.get_pixelv(corner).get_luminance()<0.002,label+" outer edge is black")
	check(image.get_pixelv(centre).get_luminance()>0.01,label+" centre remains visible (iris, not whole-screen fade)")

func run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on=false
	main.set_process(false)
	main.interactor.set_process(false)
	root.get_node("Economy").set_process(false)
	var clock=main.world_clock
	var sleep=main.sleep_cycle
	main.sleep_curtain.phase_changed.connect(func(value: String): iris_phases.append(value))
	var economy=root.get_node("Economy")
	var saves=preload("res://src/save/save_game.gd")
	var checkpoint=main._zone_nodes.zone1.get_node("Objects/SleepCheckpoint")
	var pos: Vector3=checkpoint.global_position+Vector3(0,0,1.0)
	main.restore_world_state({"zone":"zone1","landing":"main","mode":1})
	check(main.validate_world_state(main.capture_world_state()).is_empty(),"sleep doorstep is valid walkable ground")
	main.cam.set_process(false)
	main.cam.global_position=Vector3(17,14,26)
	main.cam.look_at(checkpoint.global_position)
	main.cam.fov=40
	await process_frame
	var point: Vector2=main.cam.unproject_position(checkpoint.global_position+Vector3.UP*0.75)
	check(main.hover._pick(point).get("node")==checkpoint,"doorstep world click resolves sleep")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/sleep-doorstep.png")
	economy.give({"fish":1})
	economy.daily.deposit("fish",1)
	var coins: int=economy.coins
	var day: int=clock.day
	await click(point)
	check(main.hud.world_actions.active and not sleep.busy,"door click offers a sleep bubble before executing")
	await create_timer(0.32).timeout
	var sleep_button: Button=main.hud.world_actions.buttons[0]
	await click(sleep_button.get_global_transform_with_canvas()*(sleep_button.size*0.5))
	await create_timer(0.20).timeout
	for i in 600:
		main.actor_controller.tick(1.0/60.0)
		main.interactor.active=not main.actor_controller.walking()
		main.interactor.update(1.0/60.0,main.interactor.auto_hold)
		if sleep.busy: break
	check(sleep.busy,"world click approaches and begins sleep")
	if not sleep.busy:
		print("[sleep-cycle] %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	check(main.input_blocked(),"sleep locks gameplay input")
	check(main.actor_controller.state_id()=="sleeping","independent sleeping state owns actor")
	check(not main.hud.visible,"gameplay HUD stays hidden throughout iris transition")
	var escape := InputEventKey.new()
	escape.keycode=KEY_ESCAPE
	escape.pressed=true
	root.push_input(escape,true)
	check(not paused and not main.hud.menu.active,"Escape cannot interrupt fade or pause wake")
	check(not saves.write("user://during-sleep.json",main).ok,"save rejected during transition")
	sleep.request()
	while main.sleep_curtain.phase=="closing" and main.sleep_curtain.openness>0.55:
		await process_frame
	check(clock.day==day,"time does not jump while iris closes")
	check(main.sleep_curtain.caption.modulate.a==0.0,"night caption waits until fully black")
	check_aperture(await iris_snapshot("sleep-iris-closing"),"closing")
	await wait_phase("closed")
	check(main.sleep_curtain.openness==0.0 and clock.day==day,"iris fully closes before advancing day")
	var closed: Image=await iris_snapshot("sleep-iris-closed")
	if closed!=null:
		check(closed.get_pixel(1,1).get_luminance()<0.002 and closed.get_pixel(closed.get_width()-2,closed.get_height()-2).get_luminance()<0.002,"full black covers opposite corners")
	await wait_phase("morning")
	check(clock.day==day+1 and main.sleep_curtain.openness==0.0,"06:00 and home change behind closed iris")
	await create_timer(0.25).timeout
	await iris_snapshot("sleep-iris-morning")
	await wait_phase("opening")
	while main.sleep_curtain.openness<0.45: await process_frame
	check(main.input_blocked() and clock.paused,"opening still locks input and time")
	check(main.sleep_curtain.caption.modulate.a==0.0,"morning caption clears before opening")
	check_aperture(await iris_snapshot("sleep-iris-opening"),"opening")
	await sleep.woke
	check(iris_phases.slice(0,5)==["closing","closed","morning","opening","idle"],"transition phases occur once in correct order")
	check(not main.sleep_curtain.visible and main.sleep_curtain.openness==1.0,"fully open removes curtain")
	check(main.hud.visible,"gameplay HUD restores only after iris fully opens")
	check(clock.day==day+1 and clock.query().hour==6.0,"one sleep, one next-day 06:00 wake")
	check(main._calendar_label.text.contains("06:00"),"calendar shows wake time before fade reveals scene")
	check(economy.coins==coins and economy.daily.query().items.get("fish")==1,"06:00 cargo stays queued")
	check(main.actor_controller.state_id()=="ashore_idle" and main.validate_world_state(main.capture_world_state()).is_empty(),"wake ashore at home with valid pose")
	check(saves.write("user://wake.json",main).ok,"06:00 wake save valid")
	var saved: Dictionary=saves.read("user://wake.json").snapshot
	check(saves.restore(main,saved).ok and economy.coins==coins,"wake save reload cannot settle early")
	sleep.advance(clock.day_length/24.0)
	check(clock.query().hour==7.0 and economy.coins>coins,"07:00 pickup after waking")
	var paid: int=economy.coins
	sleep.advance(0.0)
	check(economy.coins==paid,"repeated frame cannot pay twice")
	# Sailing + an open inventory must be cancelled by automatic bedtime.
	main._on_destination("zone5")
	for i in 600:
		main.actor_controller.tick(1.0/30.0)
		if main.boat.starts_sailing(): break
	main.hud.open_tab("shipping")
	clock.from_dict({"day":clock.day,"seconds":22.99*3600.0,"day_length":1200.0})
	day=clock.day
	sleep.advance(10000.0)
	check(sleep.busy and clock.query().hour<=23.00001,"large delta capped at 23:00, auto sleep starts")
	check(not main.hud.is_panel_open() and not main.boat.starts_sailing(),"auto sleep closes panel and cancels sailing")
	check(not main.ribbon.visible,"automatic sleep clears stale route preview")
	await sleep.woke
	check(clock.day==day+1 and clock.query().hour==6.0,"automatic sleep wakes only once at 06:00")
	check(main.capture_world_state().zone=="zone1" and main.actor_controller.mode()==0,"automatic sleep returns home")
	clock.from_dict({"day":10,"seconds":3600.0,"day_length":1200.0})
	main._save_path="user://sleep-autosave.json"
	main._autosave_on=true
	sleep.advance(0.0)
	await sleep.woke
	check(clock.day==10 and clock.query().hour==6.0,"after-midnight old save wakes same calendar morning")
	var auto: Dictionary=saves.read("user://sleep-autosave.json")
	check(auto.get("ok",false) and auto.snapshot.time.seconds==21600.0,"wake automatically saves settled 06:00 state")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/sleep-wake.png")
	print("[sleep-cycle] %d checks, %d failures" % [checks,failures])
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
