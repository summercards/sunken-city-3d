extends SceneTree
## 正式 HUD + 真实业务模型；验收输入只走 root.push_input 按下和松开。
## runner 映射名与输出 marker 均为 keyboard-panels。
var checks := 0
var failures := 0
var hud
var economy
var plot_requests: Array[String] = []
var destination_requests: Array[String] = []
var captures: Array[String] = []

class WorldProbe extends Node:
	var seen: Array[int] = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			seen.append(event.physical_keycode if event.physical_keycode else event.keycode)

func _init() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",text)

func shot(label: String, panel: Control) -> void:
	if DisplayServer.get_name()=="headless": return
	# 等待真实布局与入场动画；无渲染设备时绝不等待 frame_post_draw。
	await create_timer(0.3).timeout
	for layout_frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var focused:=root.gui_get_focus_owner()
	check(panel.is_visible_in_tree() and focused!=null and (focused==panel or panel.is_ancestor_of(focused)),"截图保留当前面板真实焦点 · "+label)
	var image:=root.get_texture().get_image()
	check(not image.is_empty() and image.get_width()==1600 and image.get_height()==1000,"真实渲染图像尺寸1600×1000 · "+label)
	var path: String="res://outputs/keyboard-panels-"+label+".png"
	var saved:=image.save_png(path)
	check(saved==OK and FileAccess.file_exists(path),"截图成功写入 · "+label)
	if saved==OK: captures.append(path)

func send(code: int, pressed: bool, echo := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed;event.echo=echo;event.shift_pressed=shift
	root.push_input(event,true)

func key(code: int, shift := false) -> void:
	send(code,true,false,shift)
	await process_frame
	send(code,false,false,shift)
	await process_frame

func seek_item(view, id: String, pool := 0) -> void:
	for attempt in 80:
		if view==hud.pockets:
			if view.selected_id==id: return
		else:
			if view.selected_pool==pool and str(view.selected_data.get("id",""))==id: return
		await key(KEY_RIGHT)
	check(false,"键盘可找到物品 "+id)

func category(id: String) -> void:
	for attempt in 4:
		if root.gui_get_focus_owner() in hud.notebook.categories.values(): break
		await key(KEY_UP)
	for attempt in 4:
		if root.gui_get_focus_owner()==hud.notebook.categories[id]:
			await key(KEY_ENTER);return
		await key(KEY_RIGHT)
	check(false,"键盘可达分类 "+id)

func run() -> void:
	root.content_scale_size=Vector2i(1600,1000)
	if DisplayServer.get_name()!="headless": root.size=Vector2i(1600,1000)
	economy=root.get_node("Economy")
	economy.ticking=false
	# 所有领域命令均限定在初始夹具准备阶段。
	economy.inventory.from_dict({"capacity":32,"counts":{"coins":100,"lettuce_seed":3,"fish":4,"vegetable":6},"order":["lettuce_seed","fish","vegetable"]})
	economy.warehouse.from_dict({"capacity":48,"counts":{"tomato":5}})
	# HUD-alone 不实例化 FarmField；plots.json 只有浮台基格，须补正式场景展开的六格登记。
	var platform_ids: Array[String]=["platform_plot","platform_plot:1","platform_plot:2","platform_plot:3","platform_plot:4","platform_plot:5"]
	var initial_platform_count:=0
	for row in economy.farm.plot_specs():
		if str(row.id) in platform_ids: initial_platform_count+=1
	print("[keyboard-panels-fixture] HUD-alone 初始浮台登记 %d/6，补齐正式六地格" % initial_platform_count)
	for id in platform_ids:
		economy.farm.register_plot({"id":id,"zone":"zone5","name":"培养土种植格","requires_site":"","requires_level":0})
	var registered_platform_count:=0
	for row in economy.farm.plot_specs():
		if str(row.id) in platform_ids: registered_platform_count+=1
	check(registered_platform_count==6,"初始夹具通过 Farm 命令登记正式六地格")
	root.get_node("GameState").set_mode(0)
	hud=preload("res://src/ui/hud.gd").new()
	# 独立正式 Zones 查询实例：保留真实目录，中间一个目的地受限，用来验证跳过禁用项。
	var map_zones:=preload("res://src/world/zones.gd").new()
	map_zones.zone_enabled_query=func(id: String) -> bool: return id!="rooftop_ranch"
	root.add_child(map_zones)
	hud.economy=economy;hud.game_state=root.get_node("GameState");hud.zones=map_zones
	hud.material_shop=preload("res://src/building/material_shop.gd").new()
	hud.plot_focus_requested.connect(func(id): plot_requests.append(id))
	hud.destination_pressed.connect(func(id): destination_requests.append(id))
	hud.command_requested.connect(func(command):
		if command in ["bag","notes","plant","shop","shipping","storage"]: hud.open_tab(command))
	root.add_child(hud)
	var probe:=WorldProbe.new();root.add_child(probe)
	await process_frame
	await process_frame

	await key(KEY_B)
	var pocket=hud.pockets
	check(pocket.visible and pocket.slots[pocket.selected_index].has_focus(),"B 打开背包并获得初始焦点")
	await key(KEY_KP_ENTER)
	check(pocket.actions.visible and pocket.actions.is_ancestor_of(root.gui_get_focus_owner()),"小键盘 Enter 打开动作层并抓焦点")
	await shot("01-bag-actions",pocket.actions)
	var first: Control=root.gui_get_focus_owner()
	await key(KEY_DOWN)
	check(pocket.actions.visible and root.gui_get_focus_owner()!=first,"动作层方向键切换而不隐藏")
	await key(KEY_ESCAPE)
	check(not pocket.actions.visible and pocket.selected_id=="lettuce_seed" and pocket.slots[pocket.selected_index].has_focus(),"Esc 回到原物品 ID")
	await key(KEY_RIGHT)
	check(pocket.selected_id=="fish","背包方向键切换真实物品")
	await key(KEY_ENTER)
	var fish_before: int=economy.count("fish")
	send(KEY_1,true);send(KEY_1,true,true);send(KEY_E,true);send(KEY_SPACE,true)
	await process_frame
	for code in [KEY_1,KEY_E,KEY_SPACE]: send(code,false)
	await process_frame
	check(economy.count("fish")==fish_before-1 and int(economy.daily.query().items.get("fish",0))==1,"数字/确认同帧及 echo 不重复发出业务命令")
	check(hud._panel_feedback.text.contains("已转移"),"成功反馈持久显示")
	await key(KEY_TAB)
	check(not hud.is_panel_open() and not hud.menu.active,"Tab 按下松开关闭面板，不打开暂停")

	await key(KEY_N)
	var note=hud.notebook
	check(note.cards[0].has_focus(),"笔记有初始卡片焦点")
	await key(KEY_RIGHT)
	check(note.selected=="garden" and note.detail_title.text=="我的小菜园","卡片焦点立即同步详情")
	await key(KEY_ENTER)
	check(note.action_button.has_focus(),"卡片确认可达详情动作")
	await create_timer(1.1).timeout
	check(note.action_button.has_focus() and note.detail_title.text=="我的小菜园","实时查询刷新保留详情焦点与选中 ID")
	await key(KEY_SPACE)
	check(note.category=="plant","详情动作切换种植分类")
	check(note.entries.size()==economy.farm.crop_definitions().size()+7 and note.page_count()==2,"笔记读取三作物与家园加六浮台地格，形成两页")
	await key(KEY_PAGEDOWN)
	check(note.page==1,"笔记 PgDn 真正翻到第二页")
	await key(KEY_PAGEUP)
	check(note.page==0 and note.previous.disabled,"笔记 PgUp 返回首页，边界禁用")
	await key(KEY_UP)
	check(root.gui_get_focus_owner() in note.categories.values(),"卡片向上可达分类")
	await key(KEY_LEFT);await key(KEY_ENTER)
	check(note.category=="overview","分类可经方向键与确认切换")
	await key(KEY_ENTER);await key(KEY_ENTER)
	check(note.category=="plant","总览生活闭环入口进入种植")
	await key(KEY_ENTER);await key(KEY_ENTER)
	var service=hud.services
	check(service.visible and service.mode=="shop" and service.selected_pool==1,"作物详情进入正式商店")
	await key(KEY_KP_ENTER)
	check(service.actions.visible and service.buy_amount==1,"商店小键盘 Enter 打开数量层，默认1")
	await key(KEY_RIGHT);await key(KEY_RIGHT)
	check(service.buy_amount==3 and service._buy_counter.text=="3","左右键更新购买数量及可读数字")
	await shot("02-shop-buy-three",service.actions)
	var price: int=service.selected_data.price
	var coins: int=economy.count("coins")
	var seeds: int=economy.count("lettuce_seed")
	await key(KEY_E)
	check(economy.count("lettuce_seed")==seeds+3 and economy.count("coins")==coins-price*3,"E 只购买所选数量且扣真实余额")
	check(str(service.selected_data.id)=="lettuce_seed","购买刷新后按物品 ID 恢复焦点")
	await key(KEY_ENTER)
	for i in 30: await key(KEY_RIGHT)
	check(service.buy_amount==service._buy_limit and service._buy_plus.disabled,"购买达到实际上限，禁用增加")
	await key(KEY_E)
	await key(KEY_ENTER)
	check(service.action_buttons().is_empty() and service.action_body.get_child(1).text=="瓶盖不足","余额不足显示原因而非可执行购买控件")
	var blocked_coins: int=economy.count("coins")
	await key(KEY_E);await key(KEY_1);await key(KEY_UP)
	check(economy.count("coins")==blocked_coins,"失败层确认及数字不触发禁用业务")
	await key(KEY_ESCAPE)
	await create_timer(0.16).timeout
	check(service.slots[1][service.selected_index].has_focus(),"购买数量层 Esc 恢复商品焦点")
	await key(KEY_ESCAPE)
	check(note.visible and note.category=="plant","商店 Esc 回原笔记而非世界")

	await category("life")
	await key(KEY_RIGHT)
	await key(KEY_ENTER);await key(KEY_ENTER)
	check(service.visible and service.mode=="shop","生活买卖卡可进入商店")
	await key(KEY_ESCAPE)
	await key(KEY_RIGHT)
	await key(KEY_ENTER);await key(KEY_ENTER)
	check(service.mode=="storage" and service.visible,"生活保管卡可进入仓库")
	await seek_item(service,"vegetable",0)
	await key(KEY_ENTER);await key(KEY_DOWN)
	check(int(root.gui_get_focus_owner().get_meta("amount",0))==6,"存入整叠选项可由方向键到达")
	await shot("03-warehouse-whole-stack",service.actions)
	await key(KEY_SPACE)
	check(economy.count("vegetable")==0 and economy.warehouse.count("vegetable")==6,"空格存入整叠只结算一次")
	await key(KEY_UP)
	await seek_item(service,"tomato",1)
	await key(KEY_ENTER);await key(KEY_1)
	check(economy.count("tomato")==1 and economy.warehouse.count("tomato")==4,"数字1取回1件")
	await key(KEY_ENTER);await key(KEY_2)
	check(economy.count("tomato")==5 and economy.warehouse.count("tomato")==0,"数字2取回余下整叠")
	await key(KEY_PAGEDOWN)
	check(service.pages[1]==1,"下方仓库 PgDn 真正翻页")
	await key(KEY_PAGEUP)
	check(service.pages[1]==0,"下方仓库 PgUp 真正返回")
	await key(KEY_DOWN)
	await key(KEY_PAGEDOWN)
	check(service.pages[0]==1,"背包扩容页也可 PgDn 翻页")
	await key(KEY_PAGEUP)
	check(service.pages[0]==0,"扩容背包 PgUp 返回")
	await key(KEY_TAB)
	check(not hud.is_panel_open(),"Tab 从服务面板关闭，无返回断路")
	await key(KEY_N)
	await category("plant")
	await key(KEY_PAGEDOWN)
	for attempt in 6:
		if note.selected.begins_with("plot/") and not note.action_button.disabled: break
		await key(KEY_RIGHT)
	check(note.page==1 and note.selected=="plot/platform_plot:2" and note.cards[0].has_focus(),"第二页首卡保留正式浮台稳定 ID 与焦点")
	var plot_id: String=note.selected.trim_prefix("plot/")
	await key(KEY_KP_ENTER)
	check(note.action_button.has_focus(),"小键盘 Enter 从地格卡片进入详情动作")
	await key(KEY_KP_ENTER)
	check(plot_requests.size()==1 and plot_requests[0]==plot_id and not hud.is_panel_open(),"笔记地格详情由键盘发出原有稳定 plot ID 请求")
	check(probe.seen.is_empty(),"面板导航、业务确认及关闭键按下松开均未穿透世界")

	# 整理与原动作独立：Shift+方向必须复用排序命令，不能买卖或增减数量。
	await key(KEY_B)
	await seek_item(pocket,"lettuce_seed")
	var counts_before: Dictionary=economy.inventory.all()
	var order_before: Array=economy.inventory.ordered_ids()
	var pocket_sort_events: Array=[]
	pocket.sort_requested.connect(func(from_id,to_id): pocket_sort_events.append([from_id,to_id]))
	await key(KEY_RIGHT,true)
	check(pocket_sort_events==[["lettuce_seed","fish"]] and economy.inventory.ordered_ids()[0]=="fish","纯背包 Shift+右通过原排序信号交换邻格")
	check(pocket.selected_id=="lettuce_seed" and pocket.selected_index==1 and pocket.slots[1].has_focus(),"整理刷新后焦点跟随原物品 ID")
	check(hud._panel_feedback.text.contains("已整理") and not hud._panel_feedback.text.contains("Shift+方向"),"整理即时反馈只显示结果，不显示键位教程")
	await key(KEY_LEFT,true)
	check(economy.inventory.ordered_ids()==order_before,"Shift+左可逆换回原顺序")
	await key(KEY_DOWN,true)
	check(economy.inventory.ordered_ids().back()=="lettuce_seed" and pocket_sort_events.back()==["lettuce_seed",""],"Shift+方向落空格复用移到末尾命令")
	check(economy.inventory.all()==counts_before and not pocket.actions.visible,"键盘整理不改数量余额，也不触发业务动作层")
	await key(KEY_SPACE)
	var sort_event_count:=pocket_sort_events.size()
	await key(KEY_LEFT,true)
	check(pocket.actions.visible and pocket_sort_events.size()==sort_event_count,"Space仍确认动作层，Shift+方向不会在动作层意外整理")
	await key(KEY_ESCAPE);await key(KEY_TAB)

	await key(KEY_N);await category("life")
	await key(KEY_RIGHT);await key(KEY_RIGHT)
	await key(KEY_ENTER);await key(KEY_ENTER)
	check(service.visible and service.mode=="storage","整理验收经真实笔记键盘入口进入服务背包")
	await seek_item(service,"fish",0)
	var service_sort_events: Array=[]
	service.sort_requested.connect(func(from_id,to_id): service_sort_events.append([from_id,to_id]))
	var service_order: Array=economy.inventory.ordered_ids()
	await key(KEY_RIGHT,true)
	check(service_sort_events==[["fish","tomato"]] and economy.inventory.ordered_ids()[1]=="fish","服务背包 Shift+方向使用同一排序信号")
	check(str(service.selected_data.id)=="fish" and service.slots[0][service.selected_index].has_focus(),"服务排序后保留物品 ID 焦点")
	await key(KEY_LEFT,true)
	check(economy.inventory.ordered_ids()==service_order and economy.inventory.all()==counts_before,"服务排序可逆且数量余额不变")
	await key(KEY_UP)
	var before_tray_sort:=service_sort_events.size()
	var warehouse_before: Dictionary=economy.warehouse.all()
	await key(KEY_RIGHT,true)
	check(service.selected_pool==1 and service_sort_events.size()==before_tray_sort and economy.warehouse.all()==warehouse_before,"下方仓库托盘拒绝背包换位，无跨池改动")
	check(hud._panel_feedback.text.contains("只能整理上方背包"),"跨池整理拒绝原因持久可读")
	await key(KEY_TAB)

	# 航海图只发已有 destination_pressed，不创建航行或改写世界状态。
	for confirm in [KEY_ENTER,KEY_KP_ENTER,KEY_E,KEY_SPACE]:
		await key(KEY_N);await category("life")
		await key(KEY_DOWN);await key(KEY_RIGHT)
		await key(KEY_ENTER);await key(KEY_ENTER)
		check(hud._tab=="map" and hud._panel.detail.visible,"笔记航海卡可由真实键盘打开地图")
		if destination_requests.is_empty():
			check(str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone1","地图初始焦点采用当前稳定 zone ID")
			await key(KEY_DOWN)
			check(str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone2","地图方向键移动目的地焦点")
			await key(KEY_TAB)
			check(hud.is_panel_open() and str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone5","地图 Tab 不关闭并跳过中间禁用目的地")
			await key(KEY_TAB,true)
			check(str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone2","地图 Shift+Tab 反向选择")
			await key(KEY_RIGHT)
			var old_focus: Control=root.gui_get_focus_owner()
			# 只模拟公开 UI 重建，不直接设置焦点或调用业务命令。
			hud.refresh_view()
			for layout_frame in 4: await process_frame
			check(root.gui_get_focus_owner()!=old_focus and str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone5","动态重建以稳定 zone ID 恢复到新按钮")
			var scroll: ScrollContainer=hud._panel.detail
			var focused_rect: Rect2=root.gui_get_focus_owner().get_global_rect()
			if scroll.scroll_vertical<=0 or not scroll.get_global_rect().grow(2).encloses(focused_rect):
				printerr("[map-scroll] offset=",scroll.scroll_vertical," viewport=",scroll.get_global_rect()," button=",focused_rect," body=",hud._tab_body.size," vbar=",scroll.get_v_scroll_bar().max_value," page=",scroll.get_v_scroll_bar().page," mode=",scroll.vertical_scroll_mode," pending=",hud._map_scroll_pending)
			check(scroll.scroll_vertical>0 and scroll.get_global_rect().grow(2).encloses(focused_rect),"地图焦点自动滚动进入可见区域")
			check(str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone5" and not hud._panel_feedback.text.contains("Shift+Tab"),"地图焦点恢复且面板不显示键位教程")
			await shot("04-map-zone5-focus",root.gui_get_focus_owner())
			await key(KEY_ESCAPE)
			check(note.visible and not hud._panel.visible and destination_requests.is_empty(),"地图 Esc 返回笔记，不发送目的地事件")
			await key(KEY_ENTER);await key(KEY_ENTER)
		check(str(root.gui_get_focus_owner().get_meta("zone_id",""))=="zone5","地图再次打开仍恢复稳定目的地焦点")
		var requests_before:=destination_requests.size()
		if confirm==KEY_ENTER:
			for code in [KEY_ENTER,KEY_KP_ENTER,KEY_E,KEY_SPACE]: send(code,true)
			send(KEY_ENTER,true,true)
			await process_frame
			for code in [KEY_ENTER,KEY_KP_ENTER,KEY_E,KEY_SPACE]: send(code,false)
			await process_frame
		else: await key(confirm)
		check(destination_requests.size()==requests_before+1 and destination_requests.back()=="zone5" and not hud.is_panel_open(),"地图确认只发一次原 destination_pressed · "+OS.get_keycode_string(confirm))
	check(economy.inventory.all()==counts_before,"地图选择与背包整理不改变业务库存余额")
	check(probe.seen.is_empty(),"地图方向/Tab/确认连发及整理修饰键均不穿透世界")
	if DisplayServer.get_name()!="headless":
		check(captures.size()==4,"真实渲染四个验收时点均已截图")
		print("[keyboard-panels-captures] %d screenshots" % captures.size())
	print("[keyboard-panels] %d checks, %d failures" % [checks,failures])
	hud.queue_free();probe.queue_free();map_zones.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
