extends SceneTree
## Native pointer verification for the concise picture/name/material recipe cards.
const Catalog=preload("res://src/building/building_catalog.gd")
var main
var book
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func click(node: Control) -> void:
	var at: Vector2=node.get_global_transform_with_canvas()*(node.size/2)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true);await process_frame
func button_text(label: String) -> Button:
	for child in book.get_children():
		if child is Button and child.text==label: return child
	return null
func visible_cards() -> Array:
	var result: Array=[]
	for card in book.cards.values():
		if card.is_visible_in_tree(): result.append(card)
	return result
func settle() -> void:
	for i in 25: await process_frame
func shot(name: String) -> void:
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/recipe-cards-"+name+".png")
func check_cards() -> void:
	var cards:=visible_cards()
	for card in cards:
		check(card.image.texture!=null,"actual component photo "+card.kind)
		check(card._name.text==Catalog.RECIPES[card.kind].name,"component name "+card.kind)
		check(not "秒" in card._cost.text and not "选择" in card._cost.text,"materials only "+card.kind)
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.cam.set_process(false)
	root.get_node("Economy").set_process(false)
	main._debug_teleport("zone5");main.cam.suspend_follow();main.cam.target=Vector3(22,1.48,16);main.cam.distance=34;main.cam.refresh()
	main.building_controller.open();book=main.building_controller.book
	await settle()
	check(book.visible and visible_cards().size()==10,"ten cards in first page")
	check(book.page_label.text=="1 / 3","catalog pagination")
	check_cards();await shot("all")
	await click(book.category_buttons.decoration);await settle()
	check(book.category=="decoration" and visible_cards().size()==10,"native click selects decoration category")
	check_cards();await shot("decoration")
	await click(book.category_buttons.structure);await settle()
	check(book.category=="structure" and visible_cards().size()==10,"native click selects structure category")
	await click(button_text("›"));await settle()
	check(book.page==1 and visible_cards().size()==3,"native click turns to final structure page")
	check_cards();await shot("structure-page2")
	await click(book.category_buttons.planting);await settle()
	check(visible_cards().size()==2,"native click selects planting category")
	await click(book.recipe_buttons.planter_small)
	check(not book.visible and main.building_controller.recipe=="planter_small","whole card selects recipe through native pointer")
	main.building_controller.open();await settle()
	await click(book.category_buttons.decoration);await settle()
	await click(book.recipe_buttons.oil_lamp)
	check(main.building_controller.recipe=="oil_lamp" and not book.visible,"lamp card selects new content")
	main.building_controller.open();await settle();await click(button_text("×"))
	check(not main.building_controller.active,"native close button exits cards")
	main.queue_free();await process_frame
	print("[recipe-cards] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
