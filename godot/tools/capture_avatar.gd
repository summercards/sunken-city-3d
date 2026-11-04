extends SceneTree
## Real renderer + real GUI event dispatch, three viewport sizes, original meshes.
var main: Node
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("[avatar-render] ","PASS " if ok else "FAIL ",label)
func settle(frames:=8) -> void:
	for i in frames: await process_frame
func click(button: Control) -> void:
	await settle(3)
	var point:=button.get_global_transform_with_canvas()*(button.size*0.5)
	var motion:=InputEventMouseMotion.new(); motion.position=point; root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
		root.push_input(event,true); await process_frame
	await settle(3)
func shot(id: String) -> void:
	await settle(); await RenderingServer.frame_post_draw
	var path: String="res://outputs/avatar-"+id+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"capture "+id)
func wait_phase(value: String) -> void:
	var deadline:=Time.get_ticks_msec()+8000
	while main.avatar_session.phase!=value and Time.get_ticks_msec()<deadline: await process_frame
	check(main.avatar_session.phase==value,"session "+value)
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate(); root.add_child(main)
	main._autosave_on=false
	main._begin_title()
	await settle(100)
	await shot("01-title")
	await click(main.start_screen.start_button)
	await wait_phase("editing")
	var editor=main.avatar_session.editor
	if editor==null: quit(1); return
	# Real key events must reach the text field after the title's input handoff.
	await click(editor.name_input)
	var enter:=InputEventKey.new(); enter.keycode=KEY_ENTER; enter.pressed=true
	root.push_input(enter,true); await process_frame
	enter.pressed=false; root.push_input(enter,true); await process_frame
	check(editor.step==0,"real Enter cannot bypass blank name")
	for letter in "Sea":
		var key:=InputEventKey.new(); key.unicode=letter.unicode_at(0); key.pressed=true
		root.push_input(key,true); await process_frame
		key.pressed=false; root.push_input(key,true); await process_frame
	check(editor.name_input.text=="Sea","real keyboard reaches name input after title: "+editor.name_input.text)
	editor.name_input.text="海风小满"; editor.name_input.text_changed.emit("海风小满")
	await shot("02-name")
	await click(editor.next_button)
	check(editor.step==1,"actual mouse advances name to appearance")
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=resolution; await settle()
		var extent:=root.get_visible_rect()
		check(extent.encloses(editor.paper.get_global_rect()),"paper fits "+str(resolution))
		check(extent.encloses(editor.next_button.get_global_rect()) and extent.encloses(editor.back_button.get_global_rect()),"footer fits "+str(resolution))
		await click(editor.buttons["group/hair"])
		check(editor.group_id=="hair","actual mouse opens hair tab "+str(resolution))
		await click(editor.buttons["hair_style/twin"])
		check(main.player.get_meta("avatar_appearance").hair_style=="twin","actual hair choice updates actor "+str(resolution))
		await shot("03-hair-"+str(resolution.x))
	root.size=Vector2i(1600,1000); await settle()
	await click(editor.buttons["group/eyes"])
	await click(editor.buttons["eyes/smile"]); await shot("04-eyes")
	await click(editor.buttons["group/extras"])
	await click(editor.buttons["hat/bucket"]); await shot("05-hat")
	var scroll: ScrollContainer=editor.options_scroll
	var scroll_point:=scroll.get_global_transform_with_canvas()*(scroll.size*0.5)
	for i in 12:
		var wheel:=InputEventMouseButton.new(); wheel.position=scroll_point; wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true
		root.push_input(wheel,true); await process_frame
		wheel.pressed=false; root.push_input(wheel,true); await process_frame
	await click(editor.buttons["glasses/round"])
	check(editor.draft.appearance.glasses=="round","real wheel scroll reaches lower accessory options")
	await shot("05-glasses")
	await click(editor.buttons.rotate_right)
	check(absf(main.player.body_pivot.rotation.y)>0.1,"actual rotate control turns visual root")
	await shot("06-turn")
	await click(editor.buttons.front)
	await click(editor.next_button)
	check(editor.step==2,"actual mouse opens confirmation")
	await shot("07-card")
	await click(editor.next_button); await wait_phase("idle")
	check(not main._title_active and main.avatar_profile.query().completed,"actual save restores gameplay")
	var dialogue=main.hud.dialogue
	check(dialogue!=null and main.hud.narrative_active(),"arrival narrative owns input")
	await settle(48)
	await shot("08-gameplay")
	var pos: Vector3=main.player.global_position
	var point:=Vector2(120,160)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
		root.push_input(event,true); await process_frame
	check(main.player.global_position==pos and not main._walking,"narrative backdrop absorbs world clicks")
	for resolution in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=resolution; await settle(6)
		check(root.get_visible_rect().encloses(dialogue.panel.get_global_rect()),"narrative card fits "+str(resolution))
		check(not main.hud._zoom.visible,"no view percentage overlaps narrative "+str(resolution))
		await shot("09-dialogue-"+str(resolution.x))
	while dialogue.panel.visible:
		dialogue._advance()
	check(not main.input_blocked(),"finishing narrative releases gameplay input")
	main.hud.menu.show_menu("pause"); await settle()
	check(main.hud.menu.buttons.has("appearance"),"pause menu has maintainable appearance entry")
	await click(main.hud.menu.buttons.appearance); await wait_phase("editing")
	editor=main.avatar_session.editor
	check(not editor.first_creation,"pause menu reopens editable profile")
	await click(editor.back_button); await wait_phase("idle")
	check(not main._title_active,"actual cancel releases game input")
	main.queue_free(); await process_frame
	print("[avatar-render] %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
