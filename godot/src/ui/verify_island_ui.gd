extends SceneTree
## Native coverage of every current UI surface and real keyboard / pointer input.
var main: Node
var hud: CanvasLayer
var menu: CanvasLayer
var checks := 0
var failures := 0
var visual := false
var output := ""
var dive_clicks := 0
var font_mismatches: Dictionary = {}

func _init() -> void: call_deferred("run")
func check(value: bool, name: String) -> void:
	checks+=1
	print("[island-ui] ","PASS " if value else "FAIL ",name)
	if not value: failures+=1
func frames(n := 3) -> void:
	for i in n: await process_frame
func settle(seconds := 0.3) -> void: await create_timer(seconds,true).timeout
func key(code: int) -> void:
	for pressed in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e,true);await process_frame
	await frames(2)
func click(control: Control) -> void:
	check(control!=null,"click target exists")
	if control==null: return
	var ancestor: Node=control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await frames(3)
	var p:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=p;root.push_input(motion,true)
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed
		root.push_input(e,true)
	await frames(2)
	await settle(0.25)
## 世界浮层字（`Cozy.world_text`）用的是 `FontVariation`：基字体仍是同一份打包圆体，
## 只是叠了合成加粗补拉丁数字的字重差。所以判等要落到 base_font 上 ——
## 断言的本意是「同一套字体家族」，不是「同一个对象引用」。
func same_family(font: Font) -> bool:
	var f: Font = font
	while f is FontVariation and (f as FontVariation).base_font != null:
		f = (f as FontVariation).base_font
	return f == hud._font

func inspect_fonts(node: Node) -> void:
	if (node is Label or node is Button or node is LineEdit) and node.is_visible_in_tree():
		if not same_family(node.get_theme_font("font")): font_mismatches[str(node.get_path())]=true
	for child in node.get_children(true): inspect_fonts(child)

func screenshot(tag: String) -> void:
	await settle(0.32)
	inspect_fonts(main)
	if not visual: return
	# A macOS-occluded test window may stop automatic drawing while process frames
	# continue. Draw the real viewport explicitly so capture cannot wait forever.
	RenderingServer.force_draw(false)
	var img:=root.get_texture().get_image()
	check(img.save_png(output.path_join(tag+".png"))==OK,"screenshot "+tag)
func inside(control: Control) -> bool:
	return root.get_visible_rect().encloses(control.get_global_rect())
func first_button(node: Node, text: String) -> Button:
	for b in node.find_children("*","Button",true,false):
		if b.text.contains(text): return b
	return null

func run() -> void:
	visual=DisplayServer.get_name()!="headless"
	if visual: root.size=Vector2i(1600,1000)
	root.content_scale_size=Vector2i(1600,1000)
	output=OS.get_environment("SEA_WORK_ROOT")
	if output.is_empty(): output="/Users/summercards/WorkBuddy/sea-work"
	output=output.path_join("ui_full_island");DirAccess.make_dir_recursive_absolute(output)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);main._autosave_on=false
	hud=main.hud;menu=hud.menu
	await frames(40)
	check(root.msaa_2d==Viewport.MSAA_4X,"canvas antialiasing enabled")
	if OS.get_environment("SEA_UI_CAMERA_PROBE") == "1":
		print("[island-ui] camera probe opening")
		main.cam_panel.set_open(true)
		print("[island-ui] camera opened; waiting for native frames")
		await screenshot("15_camera")
		check(inside(main.cam_panel._panel),"camera fits")
		print("[island-ui] %d checks, %d failures" % [checks,failures])
		quit(0 if failures==0 else 1)
		return
	var economy: Node=root.get_node("Economy")
	economy.give({"fish":6,"vegetable":8,"tomato":3,"pumpkin":1,"wood":52,"shell":8,"parts":4,"pearl":1})
	await screenshot("01_world")
	await key(KEY_ESCAPE)
	check(menu.active and paused,"Esc opens paused system menu")
	await screenshot("02_pause")
	check(inside(menu._paper),"pause fits viewport")
	await click(menu.buttons.settings)
	check(menu.page=="settings","settings navigation")
	await screenshot("03_settings")
	var before: bool=menu.feedback_enabled
	await click(menu.buttons.oxygen)
	check(menu.feedback_enabled!=before and hud._panel.feedback_enabled==menu.feedback_enabled,"oxygen preference updates HUD")
	await click(menu.buttons.oxygen)
	await click(menu.buttons.motion)
	check(not preload("res://src/ui/cozy_ui.gd").motion_enabled,"reduced motion preference")
	hud._panel.flip(1)
	check(not hud._panel.turning and hud._panel.page==1,"reduced motion page switch immediate")
	await click(menu.buttons.motion)
	hud._panel.show_grid(0)
	await key(KEY_ESCAPE)
	check(menu.active and menu.page=="pause","Esc settings returns pause")
	await click(menu.buttons.help)
	await screenshot("04_help")
	await key(KEY_ESCAPE)
	await click(menu.buttons.load)
	check(menu.page=="load" and menu.buttons.cancel.has_focus(),"load confirmation defaults cancel")
	await screenshot("05_load_confirmation")
	await key(KEY_ESCAPE)
	check(menu.active and menu.page=="pause","Esc load does not load")
	await click(menu.buttons.quit)
	await screenshot("06_quit_confirmation")
	await key(KEY_ESCAPE)
	await click(menu.buttons.save)
	check(menu._subtitle.text.contains("存档"),"save gives visible result inside menu")
	await screenshot("07_save_feedback")
	await key(KEY_ESCAPE)
	check(not menu.active and not paused,"Esc resumes world")
	await click(hud.command_buttons.bag)
	check(hud._panel_open,"mouse opens handbook")
	await screenshot("08_handbook")
	await key(KEY_RIGHT)
	await settle()
	check(hud._panel.page==1,"flip completed")
	await screenshot("09_apps")
	await click(hud.command_buttons.plant)
	check(hud._tab=="plant" and hud._panel.detail.visible,"plant page opens")
	await screenshot("10_farm")
	check(hud._panel.size==Vector2(680,680),"management uses wide paper")
	check(hud._tab_body.size.x<=hud._panel.detail.size.x,"farm content fits")
	check(hud._panel.detail.size.x<=hud._panel.size.x-80,"farm scroll stays inside paper margins")
	await key(KEY_ESCAPE)
	check(hud._panel_open and not hud._panel.detail.visible,"Esc detail returns handbook")
	hud.open_tab("build");await screenshot("11_build")
	check(hud._tab_body.size.x<=hud._panel.detail.size.x,"build content fits")
	check(hud._panel.detail.size.x<=hud._panel.size.x-80,"build scroll stays inside paper margins")
	hud.open_tab("storage");await screenshot("12_inventory")
	check(hud._tab_body.size.x<=hud._panel.detail.size.x,"inventory grid fits")
	var pocket: GridContainer=hud._tab_body.get_node("PocketSlots")
	check(pocket.get_child_count()==economy.inventory.capacity(),"pockets show real capacity including empty slots")
	var displayed: Dictionary={}
	var empty_count:=0
	var vegetable: Button=null
	for tile in pocket.get_children():
		if tile.empty_slot: empty_count+=1;continue
		displayed[tile.kind]=int(displayed.get(tile.kind,0))+tile.amount
		if tile.kind=="vegetable": vegetable=tile
	check(empty_count==economy.inventory.slots_free(),"empty dots match free inventory slots")
	check(displayed.get("wood",0)==economy.count("wood"),"visible stack totals match inventory owner")
	await click(vegetable)
	check(hud._tab=="vegetable","pocket click opens the existing item command")
	await screenshot("13_item")
	await key(KEY_ESCAPE)
	check(hud._tab=="storage","Esc nested item restores inventory")
	hud.open_tab("map");await screenshot("14_map")
	hud.close_card()
	await key(KEY_C);await screenshot("15_camera")
	check(main.cam_panel.visible and not hud._panel_open,"camera exclusive")
	check(inside(main.cam_panel._panel),"camera fits")
	await key(KEY_ESCAPE)
	check(not main.cam_panel.visible and not menu.active,"Esc camera closes only camera")
	await key(KEY_P);await screenshot("16_filter")
	check(inside(main.grade._panel),"filter fits")
	await click(main.grade._tab_buttons[main.grade.TAB_WATER]);await screenshot("17_water")
	check(inside(main.grade._panel),"water fits")
	await click(main.grade._preset_option)
	await screenshot("27_preset_choices")
	check(main.grade._preset_option.get_popup().visible,"preset list opens")
	main.grade._preset_option.get_popup().hide()
	await click(first_button(main.grade._panel,"存"))
	await screenshot("28_preset_name")
	check(main.grade._name_dialog.visible,"preset naming dialog opens")
	main.grade._name_edit.text="海风验收"
	main.grade._name_dialog.get_ok_button().pressed.emit()
	await frames(4)
	check(main.grade._preset_names.has("海风验收"),"preset saves via existing dialog signal")
	await click(main.grade._preset_delete)
	await screenshot("29_preset_delete")
	check(main.grade._delete_dialog.visible,"delete confirmation opens")
	main.grade._delete_dialog.get_cancel_button().pressed.emit()
	check(main.grade._preset_names.has("海风验收"),"delete cancellation preserves preset")
	var picker: ColorPickerButton=main.grade._panel.find_children("*","ColorPickerButton",true,false)[0]
	await click(picker)
	await screenshot("30_color_picker")
	check(picker.get_popup().visible,"color popup opens")
	check(root.get_visible_rect().encloses(Rect2(picker.get_popup().position,picker.get_popup().size)),"color popup stays inside viewport")
	await key(KEY_ESCAPE)
	check(not picker.get_popup().visible and main.grade.visible,"Esc closes popup before underlying panel")
	await click(main.grade._scheme_buttons.absorption)
	await screenshot("31_absorption_water")
	check(inside(main.grade._panel),"alternate water scheme fits")
	await key(KEY_ESCAPE)
	check(not main.grade.visible,"Esc water closes")
	main.order_panel.set_open(true);await screenshot("18_orders")
	check(inside(main.order_panel._card),"orders fit")
	var slot: Dictionary=main.order_panel.model.slots[0].duplicate(true)
	economy.give({str(slot.item):int(slot.amount)})
	await frames(5)
	var coins_before: int=economy.count("coins")
	await click(main.order_panel._rows[0].button)
	check(economy.count("coins")==coins_before+int(slot.pay),"order delivery keeps real payment command")
	await screenshot("32_order_waiting")
	await key(KEY_ESCAPE)
	check(not main.order_panel.visible and not menu.active,"Esc orders closes only orders")
	main.salvage_panel.begin();await screenshot("19_salvage_drop")
	check(inside(main.salvage_panel._card),"salvage fits")
	await click(main.salvage_panel._action_button);await screenshot("20_salvage_reel")
	await key(KEY_ESCAPE)
	check(not main.salvage_panel.visible and not menu.active,"Esc salvage cancels only salvage")
	main.salvage_panel.begin()
	main.salvage_panel.model.update(1.8,false)
	main.salvage_panel.model.press()
	for step in 2000:
		var model=main.salvage_panel.model
		if model.is_finished(): break
		model.update(0.016,model.tension<0.65)
	await screenshot("33_salvage_success")
	check(main.salvage_panel.model!=null and not main.salvage_panel.model.haul().is_empty(),"salvage success from model update")
	await key(KEY_ESCAPE)
	main.salvage_panel.begin();main.salvage_panel.model.press()
	for step in 200: main.salvage_panel.model.update(0.016,true)
	await screenshot("34_salvage_failure")
	check(main.salvage_panel._result.text.contains("断"),"salvage failure feedback")
	await key(KEY_ESCAPE)
	hud.toast("今天也收获满满！海风送来了新的礼物。",5)
	await screenshot("21_dialogue")
	var paper: Control=null
	for node in hud._root.get_children():
		if node.has_meta("paper_owner") and node.get_meta("paper_owner")==hud._toast_box: paper=node
	check(paper!=null and paper.visible and paper.modulate.a>0.9,"dialogue background follows visible text")
	hud._toast_left=0.3;await settle(0.1)
	check(is_equal_approx(paper.modulate.a,hud._toast_box.modulate.a),"dialogue background fade synchronized")
	await settle(0.4)
	check(not paper.visible,"dialogue background disappears")
	main.prompt.celebrate();await screenshot("22_completion")
	await settle(1.5)
	hud.dive_pressed.connect(func(): dive_clicks+=1)
	print("[island-ui] dive precondition: visible=",hud._dive_btn.is_visible_in_tree()," modal=",menu.external_open()," paused=",paused," sailing=",main.boat.starts_sailing()," windows=",root.get_embedded_subwindows().size())
	await click(hud._dive_btn);await settle(1.5)
	print("[island-ui] dive input: signals=",dive_clicks," message=",hud._toast.text)
	check(dive_clicks==1,"dive click reaches original command once")
	check(main.dive.active,"dive active")
	main.dive.debug_teleport(Vector3(0,-10,12));await settle()
	await key(KEY_ESCAPE)
	check(menu.active and paused and main.dive.active,"underwater Esc pauses instead of surfacing")
	var air_before: float=main.dive.air.ratio();await settle(0.4)
	check(is_equal_approx(air_before,main.dive.air.ratio()),"pause stops oxygen drain")
	await screenshot("23_underwater_pause")
	await key(KEY_ESCAPE)
	await key(KEY_B);await settle()
	var drain: float=main.dive.air.drain_rate(main.dive.depth,false,false)
	main.dive.air.update((main.dive.air.ratio()-0.12)*main.dive.air.MAX/drain,main.dive.depth,false,false);main.dive._emit_air()
	await screenshot("24_underwater_log")
	check(hud._air_ratio<=0.15,"low oxygen real signal")
	await key(KEY_ESCAPE)
	check(not hud._panel_open and main.dive.active,"Esc log preserves dive")
	main.dive._finish_exit();await frames()
	for extent in [Vector2i(1280,800),Vector2i(1920,1080)]:
		if visual: root.size=extent
		await frames(6)
		hud.open_tab("build");await settle()
		check(inside(hud._panel),"wide paper fits "+str(extent))
		await screenshot("25_build_"+str(extent.x))
		hud.close_card();await key(KEY_ESCAPE);await settle()
		check(inside(menu._paper),"pause fits "+str(extent))
		await screenshot("26_pause_"+str(extent.x));await key(KEY_ESCAPE)
	check(font_mismatches.is_empty(),"all visible interface text uses shared bundled font: "+str(font_mismatches.keys()))
	print("[island-ui] %d checks, %d failures" % [checks,failures])
	main.queue_free();await frames(4)
	quit(0 if failures==0 else 1)
