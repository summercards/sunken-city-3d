extends SceneTree
var checks:=0
var failures:=0
var main
var economy
var hud
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",text)
func click(control: Control) -> void:
	var at:=control.get_global_transform_with_canvas()*(control.size*0.5)
	var motion:=InputEventMouseMotion.new();motion.position=at;root.push_input(motion,true)
	await process_frame
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at
		root.push_input(event,true);await process_frame
func key(code: int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event,true);await process_frame
func move(at: Vector2) -> void:
	# The same injected pointer query drives hover and landing animation. Synthetic
	# viewport events do not move Windows' persistent global cursor position.
	main._debug_mouse="%f,%f" % [at.x,at.y]
	var event:=InputEventMouseMotion.new();event.position=at;root.push_input(event,true)
	await create_timer(0.4).timeout
func shot(name: String) -> void:
	main._process(0.0);await create_timer(0.25).timeout
	for i in 4: await process_frame
	if DisplayServer.get_name()!="headless": root.get_texture().get_image().save_png("res://outputs/"+name+".png")
func run() -> void:
	root.content_scale_size=Vector2i(1600,1000)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.interactor.set_process(false);main.cam.set_process(false)
	economy=root.get_node("Economy");economy.set_process(false);hud=main.hud
	main.world_clock.paused=true;main.weather_service.paused=true
	main.cam.follow_enabled=false;main.cam.target=Vector3(3,3,4);main.cam.distance=62;main.cam.refresh()
	main.world_clock.from_dict({"day":41,"seconds":9.25*3600,"day_length":1200.0})
	economy.inventory.add("fish",4)
	main._process(0.0);await create_timer(0.4).timeout
	hud._toast_left=0;hud._toast_box.hide();hud._zoom_left=0
	check(main._calendar_label==hud.clock_label,"single calendar output is now inside the status card")
	check(hud.clock_label.text.contains("2月10日") and hud.clock_label.text.contains("09:15"),"saved day 41 appears as February 10 without changing time")
	check(hud.corner.status.is_ancestor_of(hud._res_label) and hud.corner.status.is_ancestor_of(hud.clock_label),"time and balance share one compact region")
	check(hud.corner.status.get_theme_stylebox("panel") is StyleBoxEmpty,"status has no backplate")
	check(hud._res_label.get_theme_font("font")==preload("res://src/ui/cozy_ui.gd").world_font(),"status preserves original bold round font")
	for button in hud.corner.buttons.values(): check(button.text.is_empty(),"launcher icon has no visible text")
	check(not hud.corner.buttons.has("cancel"),"stop-action button is removed")
	check(hud._res_label.get_theme_font_size("font_size")==28,"bottle caps use the smaller backpack-sized font")
	check(not hud.corner.status.is_ancestor_of(hud.corner.buttons.follow),"camera lock is outside the lower-left information")
	check(hud.corner.menu_button.text.is_empty(),"main launcher has no visible text")
	check(hud.corner.capacity.text=="背包 %d / %d" % [economy.inventory.slots_used(),economy.inventory.capacity()],"bag occupancy uses Inventory")
	check(not hud.corner.expanded and not hud.corner.popup.visible,"only menu button is visible initially")
	await shot("hud-compact-day")
	for extent in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=extent;await process_frame;hud._layout();await process_frame
		var viewport:=root.get_visible_rect()
		check(viewport.encloses(hud.corner.status.get_global_rect()),"status fits "+str(extent))
		check(hud.corner.status.get_global_rect().end.x<viewport.size.x*0.28,"status is compact at "+str(extent))
		var follow_rect: Rect2=hud.corner.buttons.follow.get_global_rect()
		check(viewport.encloses(follow_rect) and follow_rect.position.x>viewport.size.x*0.85 and follow_rect.position.y>viewport.size.y*0.85,"round camera-lock icon fits lower right "+str(extent))
		await click(hud.corner.menu_button)
		check(hud.corner.expanded and hud.is_modal(),"click expands menu and blocks world "+str(extent))
		check(viewport.encloses(hud.corner.popup.get_global_rect()),"expanded menu fits "+str(extent))
		check(not hud.corner.buttons.has("plant"),"planting belongs inside notes")
		await shot("hud-menu-%dx%d" % [extent.x,extent.y])
		await click(hud.corner.buttons.notes);await create_timer(0.2).timeout
		var note=hud.notebook
		check(note.is_visible_in_tree() and not hud.corner.expanded and not hud._panel.visible,"notes opens its own page")
		check(viewport.encloses(note.get_global_rect()),"notebook fits "+str(extent))
		await shot("notebook-index-%dx%d" % [extent.x,extent.y])
		await click(note.categories.plant)
		check(note.category=="plant" and note.page_count()>=2,"planting has real paginated records")
		check(note.detail_facts.text.contains("%d 瓶盖" % economy.farm.crop_def("lettuce").seed_price),"seed price comes from crop definition")
		var pages: int=note.page_count()
		for page in pages:
			check(note.page==page,"next page advances once")
			await shot("notebook-plant-%dx%d-p%d" % [extent.x,extent.y,page+1])
			if page<pages-1: await click(note.next)
		check(note.next.disabled,"last page disables next")
		await key(KEY_LEFT)
		check(note.page==pages-2,"left key turns one page")
		await key(KEY_ESCAPE)
		check(not hud.is_panel_open() and not hud.menu.active,"Esc returns to world")
	# Actual routes, not a cosmetic menu.
	root.size=Vector2i(1600,1000);await process_frame
	main._process(0.0)
	check(not hud.corner.buttons.follow.selected,"camera icon shows manual observation state")
	var target_before_lock=main.actor_controller.auto_target
	await click(hud.corner.buttons.follow)
	main._process(0.0);main.cam._process(0.1)
	check(main.cam.follow_enabled and hud.corner.buttons.follow.selected,"real camera-lock click restores follow and updates icon")
	check(main.cam.target.distance_to(main.player.global_position+Vector3.UP*0.7)<0.001,"camera follows the real player position")
	check(main.actor_controller.auto_target==target_before_lock,"camera icon does not issue a world movement target")
	await shot("hud-follow-locked")
	main.cam._begin_pan(Vector2(600,400));main.cam._drag_pan(Vector2(650,400));main.cam._end_drag()
	main._process(0.0)
	check(not main.cam.follow_enabled and not hud.corner.buttons.follow.selected,"manual pan releases follow and refreshes icon")
	main.cam.target=Vector3(3,3,4);main.cam.distance=62;main.cam.refresh()
	await create_timer(0.2).timeout
	for service in ["bag","shop","storage","shipping"]:
		await click(hud.corner.menu_button);await create_timer(0.12).timeout
		print("[launcher-probe] ",service," expanded=",hud.corner.expanded," button=",hud.corner.buttons[service].get_global_rect()," paused=",paused)
		await click(hud.corner.buttons[service]);await create_timer(0.2).timeout
		print("[launcher-probe] result tab=",hud._tab," open=",hud.is_panel_open())
		check(hud._tab==service and hud.is_panel_open(),"launcher routes to actual "+service)
		hud.close_card()
	await click(hud.corner.menu_button);await key(KEY_ESCAPE)
	check(not hud.corner.expanded and not hud.menu.active,"first Esc collapses menu without pausing")
	await click(hud.corner.menu_button);await move(Vector2(550,950))
	var target_before=main.actor_controller.auto_target
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=Vector2(550,950);root.push_input(event,true);await process_frame
	check(not hud.corner.expanded and main.actor_controller.auto_target==target_before,"outside click dismisses without moving player")
	await key(KEY_N)
	check(hud.notebook.visible,"N opens notes")
	await click(hud.notebook.categories.overview)
	economy.inventory.add("coins",27);await process_frame
	check(hud.notebook.detail_facts.text.contains(str(economy.count("coins"))),"open notes refresh after real inventory event")
	await click(hud.notebook.categories.goods)
	await shot("notebook-goods")
	await click(hud.notebook.categories.life)
	await shot("notebook-life")
	hud.menu.show_menu();check(not hud.notebook.visible,"pause covers and hides notes")
	hud.menu.close_menu();check(hud.notebook.visible,"continue restores notes")
	hud.close_card()
	# Proximity, both easing directions and stable target IDs.
	var markers=main.get_node("LandingMarkers")
	main._process(0.0)
	await move(Vector2(1500,950));await process_frame
	var marker: Dictionary={}
	for item in markers.items:
		if item.zone=="zone1" and item.landing=="main": marker=item;break
	check(not marker.is_empty() and marker.visible,"home dock marker exists")
	var small: float=marker.size
	print("[dock-probe] far=",main._pointer_pos()," center=",marker.screen," size=",small)
	await move(marker.screen)
	print("[dock-probe] near=",main._pointer_pos()," center=",marker.screen," size=",marker.size)
	main.hover.update_hover(marker.screen)
	check(main.hover.target.get("type","")=="landing" and not main.hover._card.visible,"dock hover has no duplicate hand bubble")
	check(marker.size>small+12 and marker.size<=markers.ICON_MAX,"nearby cursor smoothly enlarges dock icon")
	check(markers.pick(marker.screen).get("landing","")=="main","new artwork preserves landing hit target")
	check(markers._tex==preload("res://src/ui/illustrated_icons.gd").texture("anchor",true),"dock uses the same handdrawn action sheet")
	check(not FileAccess.get_file_as_string("res://src/ui/landing_markers.gd").contains("draw_string("),"dock has no text")
	await shot("hud-dock-hover")
	await move(Vector2(1500,950))
	check(marker.size<small+1.0,"dock shrinks again after cursor leaves")
	main.world_clock.from_dict({"day":41,"seconds":21.25*3600,"day_length":1200.0})
	await shot("hud-compact-night")
	check(hud.clock_label.text.contains("21:15"),"night status uses world time")
	print("[corner-notebook] %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
