extends RefCounted
## Presentation snapshots only: rules and counts come from the injected owners.
const Items = preload("res://src/inventory/item_db.gd")
const Scope = preload("res://src/core/play_scope.gd")

static func entries(economy: Node, calendar: Dictionary) -> Dictionary:
	var farm=economy.farm
	var pending: Dictionary=economy.daily.query()
	var plants: Array=[]
	var goods: Array=[]
	var plots: Array=[]
	for id in farm.crop_definitions():
		var crop: Dictionary=farm.crop_def(id)
		var yield_text: PackedStringArray=[]
		for item in farm.yield_of(id): yield_text.append("%s ×%d" % [Items.label(item),int(farm.yield_of(id)[item])])
		var icon: String=str(crop.get("yield",{}).keys()[0])
		plants.append(card("crop/"+id,crop.name,icon,"种子 ×%d" % economy.count(crop.seed),
			"作物资料", "%s\n\n每天浇水，07:00推进生长；缺水只会暂停生长。" % crop.desc,
			["首熟  %d 个浇水日" % farm.grow_days(id),"收获  "+"、".join(yield_text),"种子  %d 瓶盖 / 包" % int(crop.seed_price)],"shop","去商店买种子"))
	for row in farm.plot_specs():
		if not Scope.zone_enabled(str(row.zone)): continue
		var id:=str(row.id)
		var state: Dictionary=farm.state(id)
		var crop: Dictionary=farm.crop_def(str(state.crop))
		var reason: String=farm.access_reason(id)
		var status: String=reason if reason!="" else farm.status_text(id)
		var icon: String=str(crop.get("yield",{"vegetable":0}).keys()[0])
		plots.append(card("plot/"+id,row.name,icon,status,"种植记录",
			"%s\n\n在场景中点击种植格，选择播种、浇水或收获。" % ("这块地还空着，可以种下新的期待。" if farm.is_empty(id) else str(crop.get("name","作物"))),
			["状态  "+status,"水壶  %d / %d" % [farm.watering_can,farm.WATER_CAPACITY]],"plot:"+id,"前往种植格"))
	plants.append_array(plots)
	for id in Items.all_ids():
		if not economy.daily.accepts(id): continue
		goods.append(card("item/"+id,Items.label(id),id,"背包 ×%d" % economy.count(id),"物产记录",
			str(Items.get_item(id).get("desc",""))+"\n\n需要卖出时，先放进出货箱。仓库中的物品会一直保管。",
			["背包  ×%d" % economy.count(id),"仓库  ×%d" % economy.warehouse.count(id),"出货单价  %d 瓶盖" % Items.sell_price(id)],"shipping","查看出货箱"))
	var today: Array=[
		card("today","海上的今天","sleep",str(calendar.get("text","日历")),"今日概况","06:00醒来，07:00作物生长、收货员收走出货箱中的货物。\n\n慢慢照料，享受今天的海风。",["瓶盖  %d" % economy.count("coins"),"背包  %d / %d 格" % [economy.inventory.slots_used(),economy.inventory.capacity()]],"", ""),
		card("garden","我的小菜园","vegetable","%d 块种植格" % plots.size(),"种植目录","作物资料与每一块种植格的状态，都收在种植分页里。",["水壶  %d / %d" % [farm.watering_can,farm.WATER_CAPACITY],"种子种类  %d" % farm.crop_definitions().size()],"category:plant","翻到种植"),
		card("shipment","明早的出货","shipping","待收 %d 瓶盖" % pending.expected,"收货记录","收货员每天07:00收走箱内货物，结算前可以取回。",_receipt(pending),"shipping","查看出货箱"),
		card("pocket","随身的小宝贝","bag","%d / %d 格" % [economy.inventory.slots_used(),economy.inventory.capacity()],"背包记录","随身物品按真实堆叠占格；瓶盖不占格。\n\n多余的物品可以存进保管仓库。",["仓库  %d / %d 格" % [economy.warehouse.slots_used(),economy.warehouse.capacity()]],"bag","打开背包")]
	var life: Array=[
		card("care","种植与照料","water","每天一点照料","生活指南","点击空地选择背包中的种子；每天浇水一次。\n\n07:00只有已浇水的作物生长。成熟后点击收获，满包时作物会留在地里。",["岸上可免费补满水壶"],"category:plant","查看种植记录"),
		card("trade","收获与买卖","shop","让收成换来新种子","生活指南","捕鱼或收获 → 放进出货箱 → 次日07:00获得瓶盖 → 去商店买种子。\n\n仓库只保管，不自动卖出。",["待收货  %d 瓶盖" % pending.expected],"shop","打开商店"),
		card("rest","睡个好觉","sleep","06:00醒来","生活指南","点击太阳房入口睡觉，23:00会自动回家休息。\n\n醒来后先照料作物，07:00再查看今天的收货。",[],"", ""),
		card("sailing","出门与回家","anchor","小船与泊位","生活指南","点击水面划船，点击泊位靠岸。岸上再次点击泊位，会走回小船。\n\n回到角色可恢复镜头跟随，停止行动可取消当前目标。",[],"map","打开航海图")]
	return {"overview":today,"plant":plants,"goods":goods,"life":life}

static func _receipt(pending: Dictionary) -> Array:
	var receipt: Dictionary=pending.receipt
	return ["结算前可随时取回货物"] if receipt.is_empty() else ["上次收货  第%d天" % int(receipt.day),"上次收入  %d 瓶盖" % int(receipt.income)]

static func card(id: String, title: String, icon: String, subtitle: String, tag: String, body: String, facts: Array, action: String, button: String) -> Dictionary:
	return {"id":id,"title":title,"icon":icon,"subtitle":subtitle,"tag":tag,"body":body,"facts":facts,"action":action,"button":button}
