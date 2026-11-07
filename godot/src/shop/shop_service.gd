extends RefCounted
## SEA-SHOP 唯一规则层。库存唯一写端口为注入的 exchange(costs, gains)。
## exchange 必须返回 {ok: bool, reason: String}，失败时数量/排列/信号全部不变，
## 成功时完整提交后再发 Inventory 信号；服务绝不使用 pay/add/remove 或补偿退款。
## token 仅在本服务实例内保留 120 秒、最多 256 条（含拒绝结果）；不续期、
## 不持久化、不写 NPC。过期/淘汰/重新 configure/重建实例后不保证去重；
## configure 仅用于装配或换档，不应每次打开商店调用；空 token 是兼容的独立请求。
## 同 token 不同参数拒绝；同 token 重放深副本且不重复发购买事件。
signal shop_opened(shop_id: String, vendor_npc_id: String)
signal purchase_completed(shop_id: String, product_id: String, amount: int, total_cost: int)
signal purchase_blocked(shop_id: String, product_id: String, reason: String)
const Catalog = preload("res://src/shop/shop_catalog.gd")
const TOKEN_TTL_MS: int = 120000
const TOKEN_LIMIT: int = 256
var inventory: RefCounted
var _exchange: Callable = Callable()
var _shops: Array = []
var _catalog_error: String = ""
var _requests: Dictionary = {}
var _busy: bool = false

## 保留 configure(bag)；也可显式注入 Callable，绝不自行模拟原子交换。
## content/crops 是纯模块测试端口，入参不会被持有为可写目录。
func configure(bag: RefCounted, exchange: Callable = Callable(), content: Variant = null, crops: RefCounted = null) -> void:
	if _busy:
		return
	inventory = bag
	_exchange = exchange
	if not _exchange.is_valid() and bag != null and bag.has_method("exchange"):
		_exchange = Callable(bag, "exchange")
	var resolved: Dictionary = Catalog.resolve(content, crops)
	_shops = resolved.shops.duplicate(true)
	_catalog_error = resolved.reason
	_requests.clear()

func shops() -> Array:
	return _shops.duplicate(true)

func _shop(shop_id: String) -> Dictionary:
	for shop in _shops:
		if shop.id == shop_id:
			return shop.duplicate(true)
	return {}

func _product(shop: Dictionary, product_id: String) -> Dictionary:
	for product in shop.get("products", []):
		if product.id == product_id:
			return product.duplicate(true)
	return {}

func _shop_error(shop_id: Variant) -> String:
	if not Catalog.identifier(shop_id):
		return "商店标识无效"
	if not _catalog_error.is_empty():
		return _catalog_error
	var shop: Dictionary = _shop(shop_id)
	if shop.is_empty():
		return "未知商店"
	if not shop.enabled:
		return "商店暂未营业"
	return ""

func open_shop(shop_id: Variant, vendor_npc_id: Variant = "") -> Dictionary:
	var reason: String = _shop_error(shop_id)
	if not vendor_npc_id is String:
		reason = "经营者标识无效"
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var shop: Dictionary = _shop(shop_id)
	# 经营者只作为公开事件元数据，不向 NPC 读写任何状态。
	if vendor_npc_id != "" and vendor_npc_id != shop.vendor_npc_id:
		return {"ok": false, "reason": "经营者与商店不匹配"}
	shop_opened.emit(shop_id, shop.vendor_npc_id)
	return {"ok": true, "shop_id": shop_id, "vendor_npc_id": shop.vendor_npc_id}

func inventory_snapshot() -> Dictionary:
	if inventory == null:
		return {"ok": false, "reason": "背包尚未接入"}
	for method in ["count", "room_for", "slots_used", "capacity"]:
		if not inventory.has_method(method):
			return {"ok": false, "reason": "背包查询接口不完整"}
	var coins: Variant = inventory.count("coins")
	var used: Variant = inventory.slots_used()
	var capacity: Variant = inventory.capacity()
	if not _quantity(coins) or not _quantity(used) or not _quantity(capacity) or used > capacity:
		return {"ok": false, "reason": "背包数据无效"}
	return {"ok": true, "reason": "", "coins": coins, "slots_used": used, "capacity": capacity}

func _quantity(value: Variant) -> bool:
	return value is int and value >= 0 and value <= Catalog.MAX_VALUE

## 纯查询：无事件、不缓存 token、不改变目录或库存，返回完全独立的快照。
func quote(shop_id: Variant, product_id: Variant, amount: Variant = 1) -> Dictionary:
	var reason: String = _shop_error(shop_id)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "max_buy": 0}
	if not Catalog.identifier(product_id):
		return {"ok": false, "reason": "商品标识无效", "max_buy": 0}
	var product: Dictionary = _product(_shop(shop_id), product_id)
	if product.is_empty():
		return {"ok": false, "reason": "未知商品", "max_buy": 0}
	var state: Dictionary = inventory_snapshot()
	if not state.ok:
		return {"ok": false, "reason": state.reason, "max_buy": 0}
	var room: Variant = inventory.room_for(product.item)
	var owned: Variant = inventory.count(product.item)
	if not _quantity(room) or not _quantity(owned):
		return {"ok": false, "reason": "背包物品数据无效", "max_buy": 0}
	var price: int = product.price
	var by_balance: int = state.coins / price
	var limit: int = mini(product.max_amount, mini(by_balance, mini(room, Catalog.MAX_VALUE - owned)))
	var out: Dictionary = {"ok": false, "reason": "", "shop_id": shop_id, "product_id": product_id,
		"product": product.duplicate(true), "item": product.item, "label": product.label,
		"unit_price": price, "amount": amount, "total_cost": 0, "max_buy": limit,
		"coins": state.coins, "owned": owned, "room": room,
		"slots_used": state.slots_used, "capacity": state.capacity}
	if not _quantity(amount) or amount == 0:
		out.reason = "购买数量必须为正整数"
	elif amount > Catalog.MAX_VALUE / price:
		out.reason = "购买总价超出安全整数范围"
	else:
		out.total_cost = price * amount
		if amount > product.max_amount:
			out.reason = "超过单次购买上限"
		elif out.total_cost > state.coins:
			out.reason = "瓶盖不足"
		elif amount > room:
			out.reason = "背包已满或剩余空间不足"
		elif amount > Catalog.MAX_VALUE - owned:
			out.reason = "物品总量超出安全整数范围"
		elif not _exchange.is_valid():
			out.reason = "背包原子交易接口尚未接入"
		else:
			out.ok = true
	return out.duplicate(true)

func max_buy(shop_id: Variant, product_id: Variant) -> int:
	return int(quote(shop_id, product_id).get("max_buy", 0))

func shop_snapshot(shop_id: Variant) -> Dictionary:
	if not Catalog.identifier(shop_id) or _shop(shop_id).is_empty():
		return {}
	var shop: Dictionary = _shop(shop_id)
	var rows: Array = []
	for product in shop.products:
		var row: Dictionary = product.duplicate(true)
		var estimate: Dictionary = quote(shop_id, product.id)
		row["max_buy"] = estimate.get("max_buy", 0)
		row["quote"] = estimate
		rows.append(row)
	shop["products"] = rows
	var state: Dictionary = inventory_snapshot()
	shop["coins"] = state.get("coins", 0)
	shop["inventory"] = state
	shop["reason"] = _shop_error(shop_id)
	return shop.duplicate(true)

func buy(shop_id: Variant, product_id: Variant, amount: Variant, request_token: Variant = "") -> Dictionary:
	if not request_token is String or request_token.length() > 128:
		return {"ok": false, "reason": "请求标识无效"}
	var now: int = Time.get_ticks_msec()
	_prune_requests(now)
	var fingerprint: Array = [shop_id, product_id, amount]
	if request_token != "" and _requests.has(request_token):
		var entry: Dictionary = _requests[request_token]
		if not _same_request(entry.fingerprint, fingerprint):
			return {"ok": false, "reason": "请求标识已用于其他购买"}
		return entry.result.duplicate(true)
	if _busy:
		return {"ok": false, "reason": "交易正在处理中，请稍后重试"}
	var estimate: Dictionary = quote(shop_id, product_id, amount)
	var result: Dictionary
	if not estimate.ok:
		result = {"ok": false, "reason": estimate.reason}
	else:
		_busy = true
		var costs: Dictionary = {"coins": estimate.total_cost}
		var gains: Dictionary = {str(estimate.item): amount}
		var exchanged: Variant = _exchange.call(costs, gains)
		_busy = false
		if not exchanged is Dictionary or not exchanged.get("ok") is bool:
			result = {"ok": false, "reason": "背包原子交易返回无效"}
		elif not exchanged.ok:
			var message: Variant = exchanged.get("reason", "背包拒绝交易")
			result = {"ok": false, "reason": message if message is String and not message.is_empty() else "背包拒绝交易"}
		else:
			result = {"ok": true, "reason": "", "shop_id": shop_id, "product_id": product_id,
				"item": estimate.item, "label": estimate.label, "amount": amount, "total_cost": estimate.total_cost}
	# 必须先登记再发事件，信号处理器重入同 token 也只能获得原结果。
	if request_token != "":
		_requests[request_token] = {"at": now, "fingerprint": fingerprint.duplicate(true), "result": result.duplicate(true)}
		_prune_requests(now)
	if result.ok:
		purchase_completed.emit(shop_id, product_id, amount, result.total_cost)
	else:
		purchase_blocked.emit(shop_id if shop_id is String else "", product_id if product_id is String else "", result.reason)
	return result.duplicate(true)

func _same_request(a: Array, b: Array) -> bool:
	for i in a.size():
		if typeof(a[i]) != typeof(b[i]):
			return false
		if a[i] is float and is_nan(a[i]) and is_nan(b[i]):
			continue
		if a[i] != b[i]:
			return false
	return true

func _prune_requests(now: int) -> void:
	for token in _requests.keys():
		if now - _requests[token].at >= TOKEN_TTL_MS:
			_requests.erase(token)
	while _requests.size() > TOKEN_LIMIT:
		_requests.erase(_requests.keys()[0])
