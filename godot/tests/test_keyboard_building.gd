extends SceneTree
## 输入验收使用真实 root.push_input；领域命令仅用于初始夹具。
## runner 映射 keyboard-building，成功 marker：[keyboard-building] N checks, 0 failures。
const Catalog=preload("res://src/building/building_catalog.gd")
var checks:=0
var failures:=0
var main
var editor
var economy

class WorldProbe extends Node:
	var leaked: Array[int]=[]
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			var code: int=event.physical_keycode if event.physical_keycode else event.keycode
			if code!=KEY_K: leaked.append(code)

func visible_cards() -> Array[Button]:
	var result: Array[Button]=[]
	for card: Button in editor.book.cards.values():
		if card.is_visible_in_tree(): result.append(card)
	result.sort_custom(func(a: Button,b: Button):
		return a._base.x<b._base.x if is_equal_approx(a._base.y,b._base.y) else a._base.y<b._base.y)
	return result

func capture(stage: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var path:=ProjectSettings.globalize_path("res://outputs/keyboard-building-"+stage+".png")
	check(not image.is_empty() and image.save_png(path)==OK,"真实渲染截图保存："+stage)
	print("[keyboard-building-shot] ",path)

func _init() -> void: call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",text)
func has_instruction_hint(value: String) -> bool:
	for phrase in ["方向键","WASD","Shift","Enter / E","Esc","右键","鼠标移动","点击施工","点击选择","循环物件","选择新位置","提交"]:
		if value.contains(phrase): return true
	return false
func send(code: int,pressed: bool,echo:=false,shift:=false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.echo=echo;event.shift_pressed=shift
	root.push_input(event,true)
func key(code: int) -> void:
	send(code,true);await process_frame
	send(code,false);await process_frame
	editor.tick(0)
func seek(kind: String) -> void:
	for i in 40:
		if editor.book.recipe_buttons[kind].has_focus(): return
		await key(KEY_RIGHT)
		if i%10==9: await key(KEY_DOWN)
	check(false,"手册键盘可达 "+kind)
func select_target(id: String) -> void:
	for i in 20:
		if editor.hovered_id==id: return
		await key(KEY_TAB)
	check(false,"循环选物可达 "+id)
func settle() -> void:
	for i in 1800:
		main.actor_controller.tick(1.0/60.0);editor.tick(1.0/60.0)
		if i>2 and editor.pending.is_empty():
			editor.tick(20.0);return
func run() -> void:
	root.content_scale_size=Vector2i(1600,1000)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	main._autosave_on=false;main.set_process(false);main.set_physics_process(false)
	main.set_process_input(false)
	main.interactor.set_process(false);main.boat.set_process(false);main.cam.set_process(false)
	economy=root.get_node("Economy");economy.set_process(false)
	await process_frame
	if main.building_controller==null:
		check(false,"正式建造控制器必须可编译并完成装配")
		print("[keyboard-building] %d checks, %d failures"%[checks,failures]);quit(1);return
	main._title_active=false
	if is_instance_valid(main.start_screen): main.start_screen.hide();main.start_screen.set_process_input(false)
	economy.inventory.set_count("wood",160);economy.inventory.set_count("soil",20)
	main._restore_building({"version":1,"next_id":4,"instances":[
		{"id":"built_1","kind":"raft_4x4","x":0,"z":0,"px":2.0,"pz":10.0,"py":0.0,"turn":0,"support":"","left":0.0},
		{"id":"built_2","kind":"raft_4x4","x":0,"z":0,"px":6.0,"pz":10.0,"py":0.0,"turn":0,"support":"","left":0.0},
		{"id":"built_3","kind":"planter_small","x":0,"z":0,"px":.8,"pz":8.8,"py":0.0,"turn":0,"support":"built_1","left":0.0}]})
	main._debug_teleport("zone5")
	var actor: Vector3=Catalog.ORIGIN+Vector3(2,0,11.5)
	main.actor_controller.restore_pose({"mode":0,"player":[actor.x,actor.y,actor.z]})
	root.get_node("GameState").enter_zone("zone5")
	main.cam.follow_enabled=false;main.cam.global_position=Catalog.ORIGIN+Vector3(2,20,24)
	main.cam.look_at(Catalog.ORIGIN+Vector3(2,0,10))
	economy.farm.plant("dynamic/built_3","lettuce");economy.farm.water("dynamic/built_3")
	var crop: Dictionary=economy.farm.state("dynamic/built_3").duplicate(true)
	editor=main.building_controller
	var entry:=WorldProbe.new();main.add_child(entry)
	await physics_frame;await physics_frame
	await key(KEY_K)
	var first_page:=visible_cards()
	check(editor.active and editor.book.visible and first_page.size()>1,"Main 的 K 入口打开当前目录并显示配方")
	if first_page.size()<2:
		print("[keyboard-building] %d checks, %d failures"%[checks,failures]);quit(1);return
	var first: Button=first_page[0]
	var first_kind: String=editor.book.cards.find_key(first)
	check(first.has_focus() and not first.disabled and Catalog.enabled(first_kind),"初始焦点精确落在当前启用且可见的首卡："+first_kind)
	check(first._base.is_equal_approx(Vector2(38,145)) and editor.book.get_global_rect().encloses(first.get_global_rect()),"首卡位于实际第一页左上槽位且完整可见（允许焦点上浮动画）")
	check(editor.book._visible_cards==first_page,"导航列表与画面可见卡的阅读顺序完全一致")
	await capture("book")
	await key(KEY_RIGHT)
	check(first_page[1].has_focus(),"右方向键精确导航到可见第二卡")
	await key(KEY_LEFT)
	check(first.has_focus(),"左方向键返回可见首卡")
	await key(KEY_ENTER)
	check(editor.recipe==first_kind and not editor.book.visible and main.building.query().size()==3,"Enter 选择可见首卡对应配方且不提交布局")
	await key(KEY_ESCAPE)
	check(editor.book.visible and first.has_focus(),"首卡选择后 Esc 恢复同一可见卡焦点")
	await key(KEY_PAGEDOWN)
	check(editor.book.page==1,"PgDn 翻页")
	await key(KEY_PAGEUP)
	await key(KEY_UP)
	check(root.gui_get_focus_owner() in editor.book.category_buttons.values(),"向上到分类")
	for i in 5:
		if editor.book.category_buttons.planting.has_focus(): break
		await key(KEY_RIGHT)
	await key(KEY_ENTER);await key(KEY_DOWN)
	await seek("planter_small")
	await key(KEY_ENTER)
	check(editor.recipe=="planter_small" and not editor.book.visible,"GUI 前 Enter 选择配方而不提交世界")
	check(main.building.query().size()==3,"选择配方不收费不建造")
	var before: Vector3=editor.keyboard_cursor
	await key(KEY_RIGHT)
	check(is_equal_approx(editor.keyboard_cursor.distance_to(before),.1),"相机相对游标每次 0.1m")
	send(KEY_SHIFT,true);await process_frame
	before=editor.keyboard_cursor
	await key(KEY_RIGHT)
	check(is_equal_approx(editor.keyboard_cursor.distance_to(before),.01),"Shift 游标每次 0.01m")
	send(KEY_SHIFT,false);await process_frame
	await key(KEY_R)
	check(editor.turn==1,"保留 R 旋转")
	await key(KEY_U)
	check(editor.manual_level,"U 保留显式选层")
	await key(KEY_H)
	check(not editor.manual_level,"H 恢复自动选层")
	check(not has_instruction_hint(editor.hint.text),"合法选位不显示常驻按键教程；允许真实坐标或材料状态")
	await capture("placement")
	var wood: int=economy.count("wood")
	send(KEY_ENTER,true);send(KEY_E,true);send(KEY_ENTER,true,true)
	await process_frame
	for code in [KEY_ENTER,KEY_E]: send(code,false)
	await process_frame
	await settle()
	check(main.building.query().size()==4 and economy.count("wood")==wood-2,"真实确认提交仅一次，库存与布局同时变化")
	var new_id: String="built_4"
	check(not main.building.row(new_id).is_empty(),"新建实例进入真实服务")
	await key(KEY_E);await settle()
	check(main.building.query().size()==4 and economy.count("wood")==wood-2 and not main.hud._toast.text.is_empty(),"重叠的不可能放置有反馈且不扣材料")
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(800,420);motion.relative=Vector2(1,0)
	root.push_input(motion,true);await process_frame;editor.tick(0)
	check(not editor.keyboard_mode,"鼠标移动切回指针模式")
	await key(KEY_RIGHT)
	check(editor.keyboard_mode,"键盘移动重新接管世界游标")
	await key(KEY_ESCAPE)
	check(editor.book.visible and editor.book.recipe_buttons.planter_small.has_focus(),"Esc 返回原手册卡片焦点")
	await key(KEY_M)
	await select_target("built_3")
	check(editor.selection_outline.visible,"搬移键盘选物显示轮廓")
	await key(KEY_E)
	check(editor.moving_id=="built_3","E 选中可搬物件")
	var old: Dictionary=main.building.row("built_3")
	for i in 4: await key(KEY_RIGHT)
	await key(KEY_ESCAPE)
	check(editor.moving_id=="" and main.building.row("built_3")==old,"取消搬移保持原物")
	await select_target("built_3");await key(KEY_ENTER)
	for i in 4: await key(KEY_RIGHT)
	wood=economy.count("wood")
	await key(KEY_E);await settle()
	check(float(main.building.row("built_3").px)>float(old.px) and economy.count("wood")==wood,"搬移更改布局且不收费")
	check(economy.farm.state("dynamic/built_3")==crop and main.building.row("built_3").id=="built_3","搬移保留 ID、作物、水分和生长")
	await key(KEY_DELETE)
	await select_target("built_3");await key(KEY_E)
	check(not editor.demolition.confirmation_open() and not main.building.row("built_3").is_empty(),"有作物拆除被安全规则拒绝")
	await select_target(new_id);await key(KEY_ENTER)
	check(editor.demolition.confirmation_open() and editor.demolition.no_button.has_focus(),"拆除弹窗默认否")
	check(editor.demolition.details.text.contains("全额返还") and editor.demolition.details.text.contains("安全检查"),"确认完整展示退款和重新安全校验说明")
	check(not has_instruction_hint(editor.hint.text),"确认层不显示常驻教程，安全确认由弹窗和默认否焦点承载")
	await capture("demolition")
	await key(KEY_ENTER)
	check(not editor.demolition.confirmation_open() and not main.building.row(new_id).is_empty() and economy.count("wood")==wood,"默认 Enter 取消，不拆不退款")
	await key(KEY_E);await key(KEY_ESCAPE)
	check(not editor.demolition.confirmation_open() and editor.recipe=="remove","确认层 Esc 只返回选物")
	await key(KEY_E);await key(KEY_RIGHT)
	check(editor.demolition.yes_button.has_focus(),"明确方向导航才选择是")
	send(KEY_ENTER,true);send(KEY_E,true);await process_frame
	send(KEY_ENTER,false);send(KEY_E,false);await process_frame
	await settle()
	check(main.building.row(new_id).is_empty() and economy.count("wood")==wood+2,"确认拆除走原请求，仅全额退款一次")
	await key(KEY_ESCAPE)
	check(editor.active and editor.book.visible,"拆除 Esc 返回手册")
	await key(KEY_ESCAPE)
	check(not editor.active,"手册 Esc 才退出")
	check(entry.leaked.is_empty(),"建造确认、导航及关闭的按下松开均不穿透世界")
	print("[keyboard-building] %d checks, %d failures"%[checks,failures])
	main.queue_free();entry.queue_free();await process_frame
	quit(1 if failures else 0)
