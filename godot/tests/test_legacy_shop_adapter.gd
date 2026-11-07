extends SceneTree

const HUD = preload("res://src/ui/hud.gd")
const Pocket = preload("res://src/ui/pocket_service.gd")
const EconomyScript = preload("res://src/economy/economy.gd")
const InventoryScript = preload("res://src/inventory/inventory.gd")
var checks := 0
var failures := 0
var query_calls := 0
var purchases: Array = []
var reply: Dictionary = {"blocked":"适配器拒绝"}
var offer: Dictionary = {"catalog":[{"id":"tomato_seed","crop":"general_test_product","count":0,"price":137,"max_buy":7}],
	"coins":11,"display_name":"测试杂货铺","caption":"测试补给说明"}

class TestHUD extends HUD:
	var result: Dictionary = {}
	func _farm_action(action: Callable) -> void:
		result=action.call()

class LegacyFarm extends RefCounted:
	var purchases: Array = []
	func crop_definitions() -> Dictionary:
		return {"tomato":{}}
	func crop_def(_id: String) -> Dictionary:
		return {"seed":"tomato_seed","seed_price":5}
	func buy_seed(id: String, amount: int) -> Dictionary:
		purchases.append([id,amount])
		return {"ok":true}

class LegacyMaterial extends RefCounted:
	var amounts: Array = []
	func buy_soil(amount: int) -> Dictionary:
		amounts.append(amount)
		return {"ok":true}

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL ",message)

func shop_snapshot() -> Dictionary:
	query_calls+=1
	return offer.duplicate(true)

func buy(product_id: String, amount: int) -> Dictionary:
	purchases.append([product_id,amount])
	return reply.duplicate(true)

func run() -> void:
	var hud:=TestHUD.new()
	var economy:=EconomyScript.new()
	economy.inventory=InventoryScript.new(1)
	economy.inventory.from_dict({"capacity":1,"counts":{"coins":80,"wood":1}})
	hud.economy=economy
	hud._tab="shop"
	hud.shop_query=shop_snapshot
	hud.shop_buy=buy
	# 不挂 HUD 或主场景；没有 Farm/MaterialShop 时注入路径仍须正常工作。
	var snapshot: Dictionary=hud._service_snapshot("shop")
	check(snapshot.catalog==offer.catalog,"目录、价格与上限完全来自 query，不按余额或背包重算")
	check(snapshot.coins==11 and snapshot.shop_name==offer.display_name and snapshot.caption==offer.caption,"余额与店铺文案透传")
	var view:=Pocket.new()
	view.font=ThemeDB.fallback_font
	view.query=hud._service_snapshot
	view.operation_requested.connect(hud._service_command)
	root.add_child(view)
	view.refresh("shop")
	check(view.get_node("ServiceName").text==offer.display_name and view.caption.text==offer.caption,"口袋显示注入的店名与说明")
	view.select(1,0)
	view.show_actions()
	view.adjust_buy_amount(99)
	check(view.buy_amount==7,"数量上限使用注入 max_buy")
	view.buy_button().pressed.emit()
	check(purchases==[["general_test_product",7]],"购买原样传递 crop 产品 ID 和数量，不调用旧规则")
	check(hud.result==reply,"购买拒绝结果不被改写")
	reply={"ok":true,"message":"适配器完成"}
	hud._service_command("soil","buy",2)
	check(purchases.back()==["soil",2] and hud.result==reply,"旧键也原样交给 buy，由 main 负责映射")
	for service in ["shipping","storage"]:
		view.refresh(service)
		check(not view.snapshot.has("shop_name"),"非商店不带店铺文案："+service)
	check(query_calls==2,"出货与仓库不查询商店")
	hud.shop_query=Callable()
	hud.shop_buy=Callable()
	economy.farm=LegacyFarm.new()
	hud.material_shop=LegacyMaterial.new()
	view.refresh("shop")
	check(view.get_node("ServiceName").text=="家园补给" and view.caption.text=="种子与土壤 · 选一份带回家","未注入保留默认文案")
	check(view.snapshot.catalog[0].crop=="tomato" and view.snapshot.catalog[0].price==5 and view.snapshot.catalog[0].max_buy==0,"未注入保留旧目录与背包上限")
	hud._service_command("tomato","buy",3)
	hud._service_command("soil","buy",2)
	check(economy.farm.purchases==[["tomato",3]] and hud.material_shop.amounts==[2],"未注入保留旧种子与土壤购买路由")
	view.free()
	hud.free()
	economy.energy.free()
	economy.free()
	await process_frame
	print("[legacy-shop-adapter] %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
