extends RefCounted
## 商店静态内容入口；品种种子从 CropCatalog 解析物品与价格，名称从 ItemDB 解析。
const PATH: String = "res://assets/data/shop/shops.json"
const Crops = preload("res://src/crops/crop_catalog.gd")
const Items = preload("res://src/inventory/item_db.gd")
const MAX_VALUE: int = 9007199254740991
static var _data: Variant = null
static var _loaded: bool = false

static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data.duplicate(true) if _data is Dictionary else {}

## JSON 数值会被解析为 float；仅在内容边界接受有限、精确的整数值。
static func integer_value(value: Variant) -> bool:
	if value is int:
		return value >= 0 and value <= MAX_VALUE
	return value is float and is_finite(value) and value >= 0 and value <= MAX_VALUE and value == floor(value)

static func identifier(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value == value.strip_edges()

## 全表失败关闭，不把坏商品静默过滤成另一份可购买目录。
## source/crops 仅是独立测试与装配注入端口；生产默认读取正式内容。
static func resolve(source: Variant = null, crops: RefCounted = null) -> Dictionary:
	var raw: Variant = data() if source == null else source
	if not raw is Dictionary or raw.get("schema") != "sea.shops":
		return _invalid("商店目录格式无效")
	var shops: Variant = raw.get("shops")
	if not shops is Array or shops.size() != 2:
		return _invalid("商店目录必须包含花店和综合商店")
	if crops == null:
		crops = Crops.new()
		if not crops.reload():
			return _invalid("作物目录无法读取")
	var out: Array = []
	var seen: Dictionary = {}
	for shop in shops:
		if not shop is Dictionary:
			return _invalid("商店定义无效")
		var id: Variant = shop.get("id")
		if not identifier(id) or id not in ["shop_flower", "shop_general"] or seen.has(id):
			return _invalid("商店标识无效或重复")
		seen[id] = true
		if not identifier(shop.get("display_name")) or not identifier(shop.get("vendor_npc_id")):
			return _invalid("商店名称或经营者标识无效")
		if not shop.get("enabled", true) is bool:
			return _invalid("商店开放配置无效")
		var products: Variant = shop.get("products")
		if not products is Array or products.is_empty():
			return _invalid("商店目录为空")
		var rows: Array = []
		var product_ids: Dictionary = {}
		for product in products:
			if not product is Dictionary:
				return _invalid("商品定义无效")
			var pid: Variant = product.get("id")
			if not identifier(pid) or product_ids.has(pid):
				return _invalid("商品标识无效或重复")
			product_ids[pid] = true
			var row: Dictionary = product.duplicate(true)
			var item: Variant = row.get("item")
			var price: Variant = row.get("price")
			if row.has("crop_id"):
				if not identifier(row.crop_id) or row.has("price") or row.has("item") or row.get("type") != "seed":
					return _invalid("品种种子必须为 seed，且不能重复登记物品或价格")
				var crop: Dictionary = crops.get_crop(row.crop_id)
				item = crop.get("seed")
				price = crop.get("seed_price")
			else:
				# 已登记的品种种子也不能通过固定价格绕过 CropCatalog。
				for crop_id in crops.ids():
					if crops.seed_of(str(crop_id)) == item:
						return _invalid("品种种子必须引用 crop_id")
			if not identifier(item) or not Items.has(item) or Items.is_currency(item):
				return _invalid("商品引用未知物品或货币")
			if not integer_value(price) or price <= 0:
				return _invalid("商品价格必须为正整数")
			var limit: Variant = row.get("max_amount")
			if not integer_value(limit) or limit <= 0:
				return _invalid("商品数量上限必须为正整数")
			var kind: Variant = row.get("type")
			if not identifier(kind) or kind != Items.get_item(item).get("category"):
				return _invalid("商品类型与物品表不一致")
			row["item"] = item
			row["price"] = int(price)
			row["max_amount"] = int(limit)
			row["label"] = Items.label(item)
			row["description"] = str(Items.get_item(item).get("desc", ""))
			rows.append(row)
		var resolved: Dictionary = shop.duplicate(true)
		resolved["products"] = rows
		resolved["enabled"] = shop.get("enabled", true)
		out.append(resolved)
	return {"ok": true, "reason": "", "shops": out}

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "shops": []}

static func all() -> Array:
	return resolve().get("shops", []).duplicate(true)

static func ids() -> Array:
	var out: Array = []
	for row in all():
		out.append(row.id)
	return out

static func get_shop(shop_id: String) -> Dictionary:
	for row in all():
		if row.id == shop_id:
			return row.duplicate(true)
	return {}

static func products(shop_id: String) -> Array:
	return get_shop(shop_id).get("products", []).duplicate(true)

static func product(shop_id: String, product_id: String) -> Dictionary:
	for row in products(shop_id):
		if row.id == product_id:
			return row.duplicate(true)
	return {}

static func validate() -> String:
	return str(resolve().get("reason", ""))
