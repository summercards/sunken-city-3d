extends SceneTree
## Update compatibility exercises current commands against historical layouts.
const Catalog=preload("res://src/building/building_catalog.gd")
const Save=preload("res://src/save/save_game.gd")
const Service=preload("res://src/building/building_service.gd")
const Space=preload("res://src/building/building_space.gd")
var main: Node
var checks:=0
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point
	root.push_input(motion,true);await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		root.push_input(event,true);await process_frame
func model() -> RefCounted:
	var service:=Service.new()
	service.configure({"eligibility":func(): return "","space_reason":func(_r): return "",
		"pay":func(_cost): return true,"refund":func(_cost): return true})
	return service
func equivalent(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b
func old_layout(offset := 0.0) -> Dictionary:
	return {"version":1,"next_id":3,"instances":[
		{"id":"built_1","kind":"raft_4x4","x":0,"z":0,"px":2.0+offset,"pz":10.0,"py":0.0,"turn":0,"support":"","left":0.0},
		{"id":"built_2","kind":"flower_pot","x":0,"z":0,"px":.8+offset,"pz":8.4,"py":0.0,"turn":0,"support":"built_1","left":0.0}]}
func rules() -> void:
	var service:=model();var legacy:=old_layout()
	check(service.from_dict(legacy),"historical off-grid raft restores")
	var request:=Catalog.snap_deck(Vector2(5.0,10.0),service.query())
	check(Catalog.platform_contact(Catalog.footprint_rect(request),service.query())>=Catalog.JOIN_MIN,"a board snaps onto a historical off-grid raft")
	var made: Dictionary=service.begin(request)
	check(made.ok,"board beside old raft is accepted: "+str(made.get("reason","")))
	if made.ok:
		service.tick(3.0)
		var board: Dictionary=service.row(made.id)
		check(board.get("positioned",false),"off-grid board stores an explicit position")
		check(service.row("built_1")==legacy.instances[0] and service.row("built_2")==legacy.instances[1],"joining never repositions old platform or furnishing")
		var walk:=Space.walk_rects([],service.query())
		check(Space.point_components(walk,Space.components(walk),Vector2(3.9,10)).any(func(id): return Space.point_components(walk,Space.components(walk),Vector2(4.1,10)).has(id)),"new seam is continuously walkable")
		var saved: Dictionary=service.to_dict()
		check(Service.validate_snapshot(saved)=="","mixed coordinate layout validates")
		var fresh:=model()
		check(fresh.from_dict(JSON.parse_string(JSON.stringify(saved))) and equivalent(fresh.query(),service.query()),"mixed layout survives JSON and fresh service restore")
		check(not fresh.begin(request).ok,"duplicate off-grid board is refused")
		check(fresh.can_remove(made.id)=="" and fresh.remove(made.id).ok,"new attached board can be reclaimed")
		var corrupt:=saved.duplicate(true);corrupt.instances[-1].positioned="true"
		check(Service.validate_snapshot(corrupt)!="","malformed position marker is rejected")
		corrupt=saved.duplicate(true);corrupt.instances[-1].px=INF
		check(Service.validate_snapshot(corrupt)!="","nonfinite explicit board position is rejected")
	check(service.move("built_2",{"px":1.0,"pz":9.0}).ok,"old furnishing can move with stable identity")
	check(service.remove("built_2").ok,"old furnishing can be reclaimed")
	var legacy_board: Dictionary={"version":1,"next_id":2,"instances":[{"id":"built_1","kind":"deck","x":3,"z":0,"px":0.0,"pz":0.0,"turn":0,"support":"","left":0.0}]}
	check(service.from_dict(legacy_board) and service.to_dict()==legacy_board,"historical grid board remains byte-field equivalent")
func wait_action() -> void:
	await process_frame
func run() -> void:
	rules()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.interactor.set_process(false);main.boat.set_process(false);main.cam.set_process(false)
	var econ: Node=root.get_node("Economy");econ.set_process(false)
	await process_frame
	var fixture:=OS.get_environment("SEA_BUILDING_AUDIT_FIXTURE")
	if fixture!="":
		var decoded:=Save.decode(FileAccess.get_file_as_string(fixture))
		check(decoded.ok,"player copy decodes: "+str(decoded.reason))
		if decoded.ok:
			var restored:=Save.restore(main,decoded.snapshot)
			check(restored.ok,"player copy restores: "+str(restored.reason))
			var old_rows: Array = decoded.snapshot.building.instances
			var live_rows: Array = main.building.query()
			check(equivalent(live_rows.slice(0, old_rows.size()),old_rows),"existing player layout unchanged after restore")
			var additions := live_rows.slice(old_rows.size())
			if not decoded.snapshot.building.get("starter_planters",false):
				check(additions.size() == 6 and additions.all(func(row): return row.kind == "planter" and row.left == 0),"legacy player layout gains six removable beds")
			check(root.get_node("GameState").current_zone==decoded.snapshot.game.zone,"saved active zone survives restore")
			var migrated_plots: Array = []
			for plot_id: String in decoded.snapshot.economy.farm.plots:
				var saved: Dictionary = decoded.snapshot.economy.farm.plots[plot_id]
				if str(saved.crop) != "":
					var actual := plot_id
					if plot_id.begins_with("platform_plot") and econ.farm.is_empty(plot_id):
						for row in additions:
							var candidate := "dynamic/" + str(row.id)
							if candidate not in migrated_plots and equivalent(econ.farm.state(candidate),saved):
								actual = candidate
								migrated_plots.append(candidate)
								break
					check(equivalent(econ.farm.state(actual),saved),"player crop survives restoration: " + plot_id)
	var editor: Node=main.building_controller
	# Management buttons must explain context, even while the player is home.
	main.restore_world_state({"zone":"zone1","landing":"main","mode":0,"player":[8.35,1.38,9.55]})
	editor.open()
	for i in 8: editor.tick(0);await process_frame
	var remove: Button=editor.book.recipe_buttons.remove
	await click(remove.get_global_transform_with_canvas()*(remove.size/2))
	editor.tick(0)
	check(editor.recipe=="remove" and not editor.book.visible and editor.active,"mouse opens persistent remove mode from home")
	check(editor.hint.visible and editor.hint.text.contains("自建平台"),"unavailable context explains how to reach building area")
	check(editor.guide.visible and editor.guide_title.text.contains("拆除模式") and editor.guide_back.visible,"mode title and return control are visible")
	await click(editor.guide_back.get_global_transform_with_canvas()*(editor.guide_back.size/2))
	check(editor.book.visible and editor.guide.visible and editor.guide_back.visible,"return button reopens book inside unified building toolbar")
	editor.close()
	# An old independent raft plus new edge board, projected into the real world.
	var fixture_layout := old_layout(18.0)
	main._restore_building(fixture_layout)
	check(equivalent(main.building.query().slice(0,fixture_layout.instances.size()),fixture_layout.instances),"historical fixture projects into real game")
	main._debug_teleport("zone5")
	main.actor_controller.restore_pose({"mode":0,"player":[42.5,1.48,25.5]})
	root.get_node("GameState").enter_zone("zone5")
	main.cam.follow_enabled=false
	main.cam.global_position=Vector3(42,23,38);main.cam.look_at(Catalog.ORIGIN+Vector3(20,0,10))
	econ.inventory.set_count("wood",100);econ.inventory.set_count("soil",10)
	var snapped: Dictionary=editor._deck_request(Vector2(23.0,10.0))
	check(main.building.can_place(snapped)=="","mouse board request can extend restored raft")
	var joined: Dictionary=main.building.begin(snapped);check(joined.ok,"real world accepts snapped board")
	main.building.tick(3)
	check(main.building_world.node_for(joined.id).has_node("Construction"),"accepted build runs completion animation")
	for frame in 3: await physics_frame
	var snapshot:=Save.encode(main)
	var written:=Save.write("user://building-compat.json",main)
	check(written.ok,"mixed layout writes through production save: "+str(written.reason))
	var read:=Save.read("user://building-compat.json")
	check(read.ok and equivalent(read.snapshot.building,snapshot.building),"mixed layout survives disk read")
	if read.ok: check(Save.restore(main,read.snapshot).ok,"mixed layout restores through production registry")
	check(not main.building_world.node_for(joined.id).has_node("Construction"),"loading a completed build skips its animation")
	check(equivalent(main.building.row("built_1"),fixture_layout.instances[0]),"disk roundtrip leaves old raft untouched")
	# A high lamp is selected at its body, rather than only its tiny ground square.
	var lamp: Dictionary=main.building.begin({"kind":"lamp_post","px":21.2,"pz":11.1,"py":0.0,"turn":0,"support":"built_1"})
	check(lamp.ok,"tall furnishing fixture builds")
	main.building.tick(20)
	await physics_frame;await physics_frame
	editor.open()
	for i in 8: editor.tick(0);await process_frame
	await click(remove.get_global_transform_with_canvas()*(remove.size/2))
	check(editor.recipe=="remove" and not editor.book.visible,"real mouse opens remove mode")
	if lamp.ok:
		var body: Vector3=main.building_world.position_for(main.building.row(lamp.id))+Vector3.UP*1.2
		editor.update_preview(main.cam.unproject_position(body))
		check(editor.hovered_id==lamp.id,"tall furnishing selected by visible body")
		check(editor.selection_outline.visible,"selected remove target has outline")
		var count_before: int=econ.count("wood")
		await click(main.cam.unproject_position(body))
		check(editor.demolition.confirmation_open() and not main.building.row(lamp.id).is_empty(),"old-layout demolition waits for confirmation")
		await click(editor.demolition.yes_button.get_global_transform_with_canvas()*(editor.demolition.yes_button.size/2));await wait_action()
		check(main.building.row(lamp.id).is_empty(),"real mouse removes tall furnishing after approach: "+main.hud._toast.text)
		check(econ.count("wood")==count_before+int(Catalog.RECIPES.lamp_post.cost.get("wood",0)),"removal refunds exactly once")
	# Save/load rebuilding the layout must not strand reclaim commands.
	var pot: Dictionary=main.building.row("built_2")
	main.actor_controller.restore_pose({"mode":0,"player":[42.5,1.48,25.5]})
	editor.update_preview(main.cam.unproject_position(main.building_world.position_for(pot)+Vector3.UP*.15))
	check(editor.hovered_id==pot.id,"historical furnishing can be selected after restore")
	check(editor.demolition.target.get("id","")==pot.id and editor.selection_outline.visible and editor.demolition.target_label.text.contains(str(Catalog.RECIPES[pot.kind].name)),"remove mode shows selected object's real name and outline without a permanent key tutorial")
	check(editor.demolition.ask(pot,Catalog.RECIPES[pot.kind].cost),"restored target still opens safe confirmation")
	check(editor.demolition.details.text.contains("全额返还") and editor.demolition.details.text.contains("安全检查") and editor.demolition.no_button.has_focus(),"refund and safety details remain visible in default-No confirmation")
	editor.demolition.dismiss()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/building-remove-guide.png")
	editor.close()
	main.queue_free();await process_frame
	print("[building-save-compat] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
