extends SceneTree
## The helper may request/confirm IDs; it never owns layout or refunds.
const Tool = preload("res://src/building/demolition_tool.gd")
var checks := 0
var failures := 0
var requested := 0
var cancelled := 0
var confirmed_ids: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)

func key(code: Key) -> InputEventKey:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true
	return event

func click(button: Button) -> void:
	var point:=button.get_global_transform_with_canvas()*(button.size/2)
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed
		root.push_input(event,true);await process_frame

func run() -> void:
	var original_mouse_mode:=Input.mouse_mode
	var tool:=Tool.new();root.add_child(tool);tool.set_process(false)
	tool.requested.connect(func(): requested+=1)
	tool.cancelled.connect(func(): cancelled+=1)
	tool.confirmed.connect(func(id: String): confirmed_ids.append(id))
	await process_frame;await process_frame
	check(not tool.active and tool.launcher.visible,"dedicated launcher is available outside the book")
	await click(tool.launcher)
	check(requested==1 and not tool.active,"launcher sends an activation command without changing business state")
	tool.set_active(true)
	check(tool.active and tool.launcher.selected,"active hammer button stays visibly selected")
	var row: Dictionary={"id":"built_demo","kind":"deck","left":0.0}
	tool.set_target(row,"");row.id="mutated_by_caller"
	check(tool.target.id=="built_demo","hover target is copied")
	check(tool.target_label.text.contains("拼接木板") and tool.target_label.text.contains("确认"),"hover describes the named target and confirmation step")
	check(tool.ask(tool.target,{"wood":6}),"first legal target opens confirmation")
	check(tool.confirmation_open() and tool.blocker.visible,"confirmation blocks the world")
	check(root.gui_get_focus_owner()==tool.no_button,"default focus protects the existing object")
	check(tool.details.text.contains("木板") and tool.details.text.contains("×6"),"confirmation lists full recipe refund")
	check(confirmed_ids.is_empty(),"opening confirmation does not commit")
	check(not tool.ask({"id":"other","kind":"deck"},{"wood":6}),"an open confirmation cannot silently switch targets")
	check(tool.handle_input(key(KEY_ENTER)),"confirmation handles keyboard activation")
	check(not tool.confirmation_open() and confirmed_ids.is_empty(),"Enter on default No keeps the object")
	check(tool.ask(tool.target,{"wood":6}),"cancelled confirmation can be reopened")
	await click(tool.no_button)
	check(not tool.confirmation_open() and confirmed_ids.is_empty() and tool.active,"mouse No returns to hammer selection")
	check(tool.ask(tool.target,{"wood":6}),"confirmation can be reopened for a deliberate Yes")
	await click(tool.yes_button)
	check(confirmed_ids==["built_demo"] and not tool.confirmation_open(),"mouse Yes emits exactly the confirmed stable ID")
	tool.yes_button.pressed.emit()
	check(confirmed_ids==["built_demo"],"repeated acceptance cannot confirm an old target again")
	tool.set_target({"id":"blocked","kind":"deck"},"请先搬走木板上的摆件")
	check(tool.target_label.text.contains("请先搬走"),"hover states the precise protection reason")
	check(not tool.ask(tool.target,{"wood":6}) and confirmed_ids.size()==1,"invalid targets cannot open confirmation")
	tool.set_target({"id":"esc_target","kind":"planter_small"},"")
	tool.ask(tool.target,{"wood":2,"soil":1})
	check(tool.is_ui_point(Vector2(1,1)),"confirmation consumes clicks across the viewport")
	tool.handle_input(key(KEY_ESCAPE))
	check(not tool.confirmation_open() and tool.active and cancelled==0,"first Esc only dismisses confirmation")
	tool.handle_input(key(KEY_ESCAPE))
	check(cancelled==1 and confirmed_ids.size()==1,"next Esc requests leaving the hammer tool")
	tool.ask(tool.target,{"wood":2,"soil":1})
	tool.set_active(false)
	check(not tool.confirmation_open() and tool.target.is_empty() and not tool.cursor.visible,"exit clears target, confirmation and cursor")
	check(Input.mouse_mode==original_mouse_mode,"exit restores the original hardware cursor")
	check(not tool.handle_input(key(KEY_ENTER)),"inactive helper does not consume gameplay keys")
	for extent: Vector2i in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=extent;await process_frame;tool._layout()
		check(root.get_visible_rect().encloses(tool.launcher.get_global_rect()),"launcher fits viewport "+str(root.get_visible_rect())+" button="+str(tool.launcher.get_global_rect()))
		check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(tool.confirmation.get_global_rect()),"confirmation fits "+str(extent))
	tool.set_launcher_visible(false)
	check(not tool.launcher.visible,"composition can hide launcher during title, sleep and other modals")
	tool.queue_free();await process_frame
	check(Input.mouse_mode==original_mouse_mode,"teardown leaves the hardware cursor intact")
	print("[building-demolition] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
