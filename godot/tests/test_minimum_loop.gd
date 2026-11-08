extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _init() -> void: call_deferred("run")
func instantiate_main() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main._autosave_on = false
	return main
func run() -> void:
	var main = instantiate_main()
	root.add_child(main)
	main.set_process(false)
	var economy = root.get_node("Economy")
	economy.set_process(false)
	var farm = economy.farm
	var daily = economy.daily
	var clock = main.world_clock
	var saves = preload("res://src/save/save_game.gd")
	check(economy.count("lettuce_seed")==3,"starter seeds")
	# 2026-11-08 潜水重新开放：默认范围里「潜水/头灯/上下游」不再锁，
	# 实际下潜与返回由 dive-maps 专项覆盖，这里只确认入口可用且不要中途切场景。
	check(not main.hud._dive_btn.disabled,"dive button available in default scope")
	var scope = preload("res://src/core/play_scope.gd")
	for id in ["dive","lamp","rise","descend"]:
		check(scope.command_enabled(id),"dive-related command enabled "+id)
	for id in ["build","camera","hook"]:
		check(main.hud._panel.tiles[id].disabled,"locked app "+id)
		main.hud._activate(id)
	check(not main.hud.is_panel_open(),"locked apps cannot open")
	check(not main.hud._panel.tiles.grade.disabled,"P debug tool stays available in minimal scope")
	# 2026-11-03 范围修订：横滨铁道放进默认范围；圆弧农场与远海街町从 main.tscn 移除。
	check(main._zone_nodes.has("zone2") and main._zone_nodes.zone2.visible,"横滨铁道在默认范围显示")
	for id in ["zone3","zone4"]:
		check(not main._zone_nodes.has(id),"按最新范围移除 "+id)
	check(main._is_open_water(500,500),"unobstructed ocean is open beyond the former home boundary")
	check(main.props.schools.size()>0 and main.props.crates.size()>6 and main.props.crates.size()<=54,"fishing and driftwood cover the active open sea cells")
	for school in main.props.schools:
		check(main.navigation.is_open_water(school.base.x,school.base.z),"fish point in navigable ocean")
	for school in main.props.schools:
		check(not main.plan_route_to(school.base.x+2.1,school.base.z).is_empty(),"fish has reachable approach")
	var zones = root.get_node("Zones")
	var supply = main._zone_nodes.zone1.landing_point("salvage")
	check(supply.ground().contains_world(main.trade_board.position.x,main.trade_board.position.z),"shop counter stands on accessible platform")
	check(not supply.ground().path_between(supply.stand_position(),main.trade_board.position).is_empty(),"shop counter reachable from landing")
	for destination in ["zone5","zone1"]:
		main._on_destination(destination)
		check(main.boat.starts_sailing(),"sail to "+destination)
		for frame in 6000:
			if not main.boat.starts_sailing(): break
			main.boat._steer(1.0/60.0)
		check(not main.boat.starts_sailing() and root.get_node("GameState").current_zone==destination,"arrive "+destination)
	var home = main._zone_nodes.zone1.landing_point("main")
	check(main._start_walk(home.ground(),main.farm_field.find("home_plot").global_position),"walk to home crop bed")
	for frame in 2000:
		if not main._walking: break
		main._update_walk(1.0/60.0)
	check(not main._walking and root.get_node("GameState").mode==0,"ashore ready for farming and supplies")
	var fish_before: int = economy.count("fish")
	check(main.props.collect_fish(main.props.schools[0]),"collect nearby fish")
	check(economy.count("fish")==fish_before+1,"fish goes into bag")
	check(daily.deposit("fish",1).get("ok",false),"fish can ship")
	var start_coins: int = economy.coins
	check(economy.coins==start_coins,"no immediate sale")
	check(farm.access_reason("platform_plot")=="","aquaculture beds unlocked")
	var plot = main.farm_field.find("home_plot")
	check(plot != null,"home plot exists")
	check(plot.perform("plant","lettuce").get("event","")=="planted","scene plot plants")
	check(economy.count("lettuce_seed")==2,"one seed consumed")
	check(plot.perform("water").get("event","")=="watered","scene plot waters")
	var before: Dictionary = saves.encode(main)
	check(saves.write("user://loop.json",main).ok,"save before dawn")
	# Midnight must not sell; the dawn threshold is shared with rest.
	clock.from_dict({"day":2,"seconds":25199.0,"day_length":1200.0})
	check(economy.coins==start_coins and int(farm.state("home_plot").remaining)==3,"before 07:00 unchanged")
	clock.tick(0.02)
	check(economy.coins==start_coins+preload("res://src/inventory/item_db.gd").sell_price("fish"),"07:00 sale")
	check(int(farm.state("home_plot").remaining)==2,"one growth at dawn")
	var settled_coins: int = economy.coins
	daily.observe(clock.query())
	check(economy.coins==settled_coins and int(farm.state("home_plot").remaining)==2,"dawn idempotent")
	var paid: Dictionary = saves.encode(main)
	check(saves.restore(main,paid).ok and economy.coins==settled_coins,"paid save cannot double pay")
	check(saves.restore(main,before).ok and daily.query().items.get("fish",0)==1,"pending sale restores")
	main._rest_for_day()
	await main.sleep_cycle.woke
	check(clock.query().hour==6.0 and economy.coins==start_coins,"sleep wakes at 06:00 before sale")
	clock.tick(clock.day_length/24.0)
	check(economy.coins==settled_coins,"rest button and natural dawn same payout")
	# Reach mature crop, including a dry day that must not advance growth.
	clock.rest_to_morning()
	check(int(farm.state("home_plot").remaining)==2,"dry day does not grow")
	for i in 2:
		farm.water("home_plot")
		clock.rest_to_morning()
	check(farm.phase("home_plot")=="ready","three watered mornings mature")
	var ready_state: Dictionary = farm.state("home_plot")
	var before_options: Dictionary = economy.to_dict()
	var playback_before: Dictionary = main.player.action_playback().duplicate(true)
	var harvest_events: Array = []
	var harvest_actions: Array = []
	plot.acted.connect(func(_id, event, _payload): harvest_events.append(event))
	main.player.action_started.connect(func(id, token): harvest_actions.append([id, token]))
	check(plot.interact(null).get("event", "") == "options", "成熟地格交互只返回 options")
	check(farm.state("home_plot") == ready_state and economy.to_dict() == before_options,
		"打开收获菜单不提前改作物、库存或体力")
	check(harvest_events.is_empty() and harvest_actions.is_empty()
		and main.player.action_playback() == playback_before and main.player._item_receive.prop == null,
		"打开菜单不发业务成功事件、不启动动作或举物")
	main.hud.world_actions.close(true)
	check(plot.perform("harvest").get("event", "") == "harvested", "显式收获命令完成业务闭环")
	check(harvest_events == ["harvested"] and harvest_actions.size() == 1
		and harvest_actions[0][0] == "harvesting", "显式收获只发一次成功事件与动作")
	check(economy.count("vegetable")==2,"harvest inventory")
	var harvested_business: Dictionary = economy.to_dict()
	check(plot.perform("harvest").has("blocked"), "已收空地格拒绝重复收获")
	check(economy.to_dict() == harvested_business and harvest_events == ["harvested"]
		and harvest_actions.size() == 1, "重复收获失败不重复奖励或庆祝")
	check(economy.storage.deposit("vegetable",2).get("ok",false),"produce stored")
	clock.rest_to_morning()
	check(economy.warehouse.count("vegetable")==2 and economy.coins==settled_coins,"warehouse never auto sells")
	check(economy.storage.withdraw("vegetable",1).get("ok",false),"withdraw produce")
	check(daily.deposit("vegetable",1).get("ok",false),"queue produce")
	check(daily.withdraw("vegetable",1).get("ok",false),"withdraw pending shipment")
	daily.deposit("vegetable",1)
	clock.rest_to_morning()
	check(economy.coins==settled_coins+preload("res://src/inventory/item_db.gd").sell_price("vegetable"),"morning crop revenue")
	var cost_before: int = economy.coins
	check(not farm.buy_seed("lettuce").has("blocked"),"buy next seed")
	check(economy.coins==cost_before-4 and economy.count("lettuce_seed")==3,"economic loop closes")
	var good: Dictionary = saves.encode(main)
	check(saves.write("user://loop.json",main).ok,"save completed cycle")
	check(saves.restore(main,saves.read("user://loop.json").snapshot).ok,"disk round trip")
	# Full bag must preserve fish, produce and queued shipments.
	economy.inventory.from_dict({"capacity":1,"counts":{"wood":999}})
	var schools_before: int = main.props.schools.size()
	check(not main.props.collect_fish(main.props.schools[0]) and main.props.schools.size()==schools_before,"full bag retains fish")
	check(economy.storage.withdraw("vegetable",1).has("blocked") and economy.warehouse.count("vegetable")==1,"full bag retains stored crop")
	check(farm.buy_seed("lettuce").has("blocked"),"full bag purchase rejected")
	saves.restore(main,good)
	economy.inventory.set_count("coins",0)
	var seeds: int = economy.count("lettuce_seed")
	check(farm.buy_seed("lettuce").has("blocked") and economy.count("lettuce_seed")==seeds,"no money no purchase")
	saves.restore(main,good)
	var old: Dictionary = good.duplicate(true)
	old.economy.erase("daily_loop")
	check(not saves.restore(main,old).ok,"current save missing shipments rejected")
	old.version = 2
	old = saves.decode(JSON.stringify(old)).snapshot
	check(saves.restore(main,old).ok and daily.query().expected==0,"old save adopts clock without retroactive sale")
	var far: Dictionary = good.duplicate(true)
	var remote: Dictionary = zones.landing("zone3","main")
	far.game = {"zone":"zone3","landing":"main","mode":1,"far_sea":false,"boat":[remote.boatPark[0],remote.boatPark[1],remote.boatPark[2],remote.boatYaw],"player":[]}
	check(saves.restore(main,far).ok,"remote old progress accepted")
	check(root.get_node("GameState").current_zone=="zone1" and preload("res://src/core/play_scope.gd").HOME_WATER.has_point(Vector2(main.boat.position.x,main.boat.position.z)),"remote player safely returns home")
	check(economy.warehouse.count("vegetable")==1,"migration keeps stored goods")
	saves.restore(main,good)
	# Views use the real command route and remain separate from character dialogue.
	main.hud.toast("已存入仓库")
	check((main.hud.dialogue==null or not main.hud.dialogue.panel.visible) and main.hud._toast_box.custom_minimum_size.y<60,"system notice is compact")
	# 商店从「HUD 的一个页签」升级成独立的商店面板（NPC 商店模块接入后，
	# shop 命令走 shop_panel.open_shop，不再开 HUD 页签）。其余三个仍是页签。
	main._on_click_command("shop")
	check(main.shop_panel != null and main.shop_panel.is_open(),"open shop")
	if main.shop_panel != null and main.shop_panel.is_open():
		main.shop_panel.close()
	await process_frame
	for tab in ["storage","shipping","plant"]:
		main._on_click_command(tab)
		check(main.hud.is_panel_open() and main.hud._tab==tab,"open "+tab)
		await process_frame
	main.hud.close_card()
	if DisplayServer.get_name() != "headless":
		main._process(0.0)
		for i in 8: await process_frame
		check(not main.hover._card.visible,"empty hover card stays hidden")
		root.get_texture().get_image().save_png("res://outputs/minimum-loop-world.png")
		main.hud.open_tab("shipping")
		for i in 20: await process_frame
		root.get_texture().get_image().save_png("res://outputs/minimum-loop-shipping.png")
	print("[minimum-loop] ",checks," checks, ",failures," failures")
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
