extends SceneTree
## 独立 UI 专项；不加载 Main、不修改真实存档。由统一 runner 注册后执行。
const Catalog = preload("res://src/building/building_catalog.gd")
const Controller = preload("res://src/building/building_controller.gd")
var checks := 0
var failures := 0

class Model extends RefCounted:
	signal changed
	signal completed(id: String)
	var rows: Array=[]
	func query() -> Array: return rows.duplicate(true)
	func row(id: String) -> Dictionary:
		for item in rows:
			if str(item.id)==id: return item.duplicate(true)
		return {}
	func context_reason() -> String: return ""
	func tick(_delta: float) -> void: pass

class Hud extends CanvasLayer:
	var owned_modal_query: Callable
	var owned_modal_close: Callable
	var owned_modal_input: Callable
	var owned_modal_camera_query: Callable
	func close_card() -> void: pass
	func set_external_modal(_on: bool,_shade: bool) -> void: pass
	func toast(_message: String) -> void: pass

class TestProjection extends Node3D:
	func position_for(row: Dictionary) -> Vector3:
		return Catalog.ORIGIN+Vector3(float(row.get("px",0)),float(row.get("py",0)),float(row.get("pz",0)))

class Editor extends Controller:
	var submissions := 0
	func _refresh_ghosts() -> void: pass
	func update_preview(_screen: Vector2) -> void: _sync_view()
	func _request_build(_request: Dictionary) -> void: submissions+=1

class Router extends Node:
	var editor: Node
	var world_events := 0
	func _unhandled_input(event: InputEvent) -> void:
		if editor.handle_input(event): get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton: world_events+=1

func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func key(code: Key) -> InputEventKey:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true;return event
func click(button: Button) -> void:
	var point:=button.get_global_transform_with_canvas()*(button.size/2)
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await process_frame

func run() -> void:
	root.size=Vector2i(1600,1000)
	var model:=Model.new()
	model.rows=[{"id":"old","kind":"deck","py":2.8,"px":8.0,"pz":0.0,"left":0.0},
		{"id":"new","kind":"deck","py":5.086335,"px":12.0,"pz":0.0,"left":0.0}]
	var hud:=Hud.new();root.add_child(hud)
	var projection:=TestProjection.new();root.add_child(projection)
	var camera:=Camera3D.new();root.add_child(camera)
	var editor:=Editor.new();root.add_child(editor)
	editor.configure(model,projection,camera,hud,func(): return {},func(): pass,Callable(),Callable(),
		func(): return {"mode":0,"position":Catalog.ORIGIN+Vector3.UP*2.8})
	var router:=Router.new();router.editor=editor;root.add_child(router)
	await process_frame
	check(not editor.demolition.launcher.visible,"建筑模式外没有常驻锤子")
	editor.open();await process_frame
	check(editor.book.visible and editor.guide.visible,"手册与统一工具栏属于同一建筑界面")
	check(editor.book==editor.view.book and editor.hint==editor.view.hint and editor.demolition==editor.view.demolition,"保留旧测试接口别名")
	check(is_equal_approx(editor.build_level*Catalog.LAYER_HEIGHT,2.8),"继承旧高度不按新层高舍入")
	await click(editor.view.buttons.move)
	check(editor.recipe=="move" and not editor.book.visible,"真实鼠标点选搬移工具")
	await click(editor.view.buttons.remove)
	check(editor.recipe=="remove" and editor.demolition.active,"真实鼠标点选拆除工具")
	await click(editor.guide_back)
	check(editor.book.visible and not editor.demolition.active,"工具栏返回手册")
	editor.select_recipe("planter_small")
	var old_snap: bool=editor.snap_assist
	await click(editor.view.buttons.snap)
	check(editor.snap_assist!=old_snap,"工具栏吸附开关发送动作")
	var old_turn: int=editor.turn
	await click(editor.view.buttons.rotate)
	check(editor.turn==(old_turn+1)%4,"工具栏旋转发送动作")
	editor.build_level=0.0
	await click(editor.view.buttons.level)
	check(is_equal_approx(editor.build_level*Catalog.LAYER_HEIGHT,2.8),"首个实际高度为旧 2.8 米")
	await click(editor.view.buttons.level)
	check(is_equal_approx(editor.build_level*Catalog.LAYER_HEIGHT,5.086335),"第二个实际高度为新 5.086335 米")
	await click(editor.view.buttons.auto)
	check(not editor.manual_level,"工具栏恢复自动识别高度")
	for extent: Vector2i in [Vector2i(1280,800),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size=extent;await process_frame
		editor.show_book();editor._place_book()
		var bounds:=root.get_visible_rect()
		check(bounds.encloses(editor.guide.get_global_rect()),"工具栏无越界 "+str(extent))
		check(bounds.encloses(editor.book.get_global_rect()),"手册无越界 "+str(extent))
		check(not editor.guide.get_global_rect().intersects(editor.book.get_global_rect()),"手册不遮挡工具栏 "+str(extent))
		for button: Button in editor.view.buttons.values():
			check(bounds.encloses(button.get_global_rect()),"工具按钮无越界 "+button.text+str(extent))
		check(editor.guide.get_global_rect().encloses(editor.demolition.launcher.get_global_rect()),"兼容锤子只位于工具栏内")
		check(bounds.encloses(editor.demolition.confirmation.get_global_rect()),"确认页无越界 "+str(extent))
	editor.select_recipe("remove")
	var confirmed: Array[String]=[]
	editor.demolition.confirmed.connect(func(id: String): confirmed.append(id))
	var row: Dictionary={"id":"confirm_only","kind":"deck","left":0.0}
	editor.demolition.set_target(row,"");editor.demolition.ask(row,{"wood":6})
	check(root.gui_get_focus_owner()==editor.demolition.no_button,"拆除确认默认焦点否")
	check(not editor.allows_camera(),"确认期间锁定相机")
	check(editor.handle_input(key(KEY_ENTER)),"确认消费 Enter")
	check(confirmed.is_empty() and not editor.demolition.confirmation_open(),"默认确认保留物件")
	editor.demolition.ask(row,{"wood":6})
	var mouse:=InputEventMouseButton.new();mouse.position=Vector2(5,5);mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
	check(editor.handle_input(mouse),"确认页外点击不会穿透")
	check(editor.demolition.confirmation_open() and confirmed.is_empty(),"外侧点击不确认、不关页")
	var dismiss_escape:=key(KEY_ESCAPE)
	editor.handle_input(dismiss_escape)
	check(editor.active and editor.recipe=="remove" and not editor.demolition.confirmation_open(),"第一次 Esc 仅关闭确认")
	# 同一个事件若再次从 Main 的未处理入口到达，不能再跳一级。
	editor.handle_input(dismiss_escape)
	check(editor.active and editor.recipe=="remove" and editor.book.visible==false,"同一 Esc 事件不会双分发")
	editor.handle_input(key(KEY_ESCAPE))
	check(editor.active and editor.book.visible,"第二次 Esc 返回建筑手册")
	check(editor.handle_input(mouse),"手册外空白点击也不穿透")
	editor.handle_input(key(KEY_ESCAPE))
	check(not editor.active and not editor.demolition.launcher.visible,"手册 Esc 退出并收起锤子")
	editor.open();editor.select_recipe("move");editor.moving_id="old"
	editor.handle_input(key(KEY_ESCAPE))
	check(editor.active and editor.moving_id=="","搬移 Esc 仅取消当前选取")
	check(editor.submissions==0,"工具栏、确认与退出均未误施工")
	check(router.world_events==0,"真实鼠标点击工具栏未落入世界输入")
	await click(editor.view.buttons.exit)
	check(not editor.active,"工具栏退出动作有效")
	router.queue_free();editor.queue_free();hud.queue_free();projection.queue_free();camera.queue_free()
	await process_frame
	print("[building-ui-unified] %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
