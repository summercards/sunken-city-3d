extends RefCounted
## Wire contract validates types before any module sees untrusted data.
static func number(low := 0.0, high := 1.0e9) -> Dictionary:
	return {"type":"number","min":low,"max":high}
static func integer(low := 0, high := 1000000000) -> Dictionary:
	return {"type":"integer","min":low,"max":high}
static func object(fields: Dictionary, required: Array = []) -> Dictionary:
	return {"type":"object","fields":fields,"required":required}
static func map(values: Dictionary) -> Dictionary: return {"type":"object","values":values}
static func list_of(items: Dictionary, maximum := 10000) -> Dictionary: return {"type":"array","items":items,"max":maximum}
static func signed_integer_string(raw: String) -> bool:
	if not raw.is_valid_int(): return false
	var negative := raw.begins_with("-")
	var digits := raw.substr(1) if negative else raw
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	if digits.length()>limit.length(): return false
	if digits.length()==limit.length() and digits.casecmp_to(limit)>0: return false
	return str(int(raw))==raw
static func inventory() -> Dictionary:
	# `order` 是玩家拖拽整理出的物品次序，2026-10-29 新增。
	# **不进 required**：旧存档没有这个字段必须照样能读（读档后退回物品表顺序）。
	# 但只要出现，就必须是字符串数组 —— 脏数据不能用它把界面搞崩。
	return object({"capacity":integer(1,10000),"counts":map(integer()),
		"order":list_of({"type":"string"},256)},["capacity","counts"])
static func schemas() -> Dictionary:
	var string := {"type":"string"}
	var boolean := {"type":"bool"}
	var vector := {"type":"array","items":{"type":"number"},"sizes":[0,3]}
	var boat := vector.duplicate(true)
	boat.sizes = [0,4]
	return {
		"profile":object({}),
		# No gameplay instance limit. The storage layer's byte budget and the
		# building admission policy protect actual serialized capacity together.
		"building":object({"version":integer(1,1),"next_id":{"type":"integer","min":1},
			"instances":{"type":"array","items":object({}),"max":2147483647}},["version","next_id","instances"]),
		"economy":object({
			"daily_loop":object({"version":integer(1,1),"cargo":inventory(),"last_morning":integer(-1),"receipt":object({"day":integer(1),"income":integer(),"items":map(integer())})},["version","cargo","last_morning","receipt"]),
			"inventory":inventory(),"warehouse":inventory(),"ship_level":integer(1,3),
			"tracked_goal":string,"site_levels":map(integer(1,3)),"facilities":map(boolean),
			"site_work":map(object({"left":number(),"total":number(0.001)},["left","total"])),
			# `grow_day` 是生长水位线（SEA-FARM-R14），2026-11-01 新增；不进 required，
			# 旧档缺它时由 FarmModel 按 `day` 起步。
			"farm":object({"version":integer(1,3),"day":integer(1),"grow_day":integer(1),"watering_can":integer(0,12),"selected_crop":string,
				"plots":map(object({"crop":string,"remaining":number(),"total":number(),"water":number(0,1),"harvests":integer()},["crop","remaining","total","water","harvests"]))},["version","day","watering_can","selected_crop","plots"]),
			"orders":object({"slots":list_of(object({"uid":string,"order":string,"left":number(),"refill":number()}),3)},["slots"]),
			# SEA-ENERGY：体力上限/当前值与「今天上限减半」的惩罚标记。
			# 不进 required —— 加体力之前的旧档没有这个字段，读进来按满体力起步。
			"energy":object({"version":integer(1,1),"current":number(0,10000),"maximum":number(1,10000),"pending_half":boolean},["version","current","maximum"]),
			# SEA-AQUA：家园补给站是否已改成渔场。同样不进 required（旧档=没升过）。
			"fishery":object({"version":integer(1,2),"unlocked":boolean,"pending":integer(0,24),
				"observed_hour":number(-1,1.0e12),"next_hour":number(-1,1.0e12)},["version","unlocked"]),
			# SEA-SUNROOM：旧 v4 档缺少时按「破损、尚未修缮」恢复；出现时严格校验阶段与兼容布尔值。
			"sunroom":object({"version":integer(1,1),"stage":{"type":"string","enum":["ruined","ladder_fixed","restored"]},
				"ladder_repaired":boolean,"upper_restored":boolean,"seasonal_care":integer(0,100)},["version","stage","ladder_repaired","upper_restored","seasonal_care"])},
			["inventory","warehouse","ship_level","tracked_goal","site_levels","facilities","site_work","farm","orders","daily_loop"]),
		"game":object({"zone":string,"landing":string,"mode":integer(0,3),"far_sea":boolean,"boat":boat,"player":vector},["zone","landing","mode","far_sea","boat","player"]),
		# SEA-ROOM：床铺摆放（房间局部坐标）与「人在不在屋里」。2026-11-05 新增模块，
		# 不进 required —— 加房间之前的 v4 档没有这一段，读进来按初版床位置补。
		"room":object({"version":integer(1,1),
			"bed":object({"position":vector,"yaw":number(-100.0,100.0)},["position","yaw"]),
			"inside":boolean},["version","bed","inside"]),
		"pickups":object({"reset":boolean,"crates":list_of(object({"id":integer(1),"slot":string,"kind":{"type":"string","enum":["crate","planks","barrel"]},"wood_amount":integer(2,16),"base":{"type":"array","sizes":[3],"items":number(-1.0e9,1.0e9)},"phase":number(),"yaw":number()},["id","kind","base","phase","yaw"]),128),
			"schools":list_of(object({"id":integer(1),"slot":string,"base":{"type":"array","sizes":[3],"items":number(-1.0e9,1.0e9)},"phase":number(),"count":integer(1,12)},["id","base","phase","count"]),128),
			"pending":list_of(number(0,60),32),"pending_fish":list_of(number(0,60),32),"rng":string,"fish_rng":string,"next_id":integer(1),"anchor":integer(),"elapsed":number(),
			"ocean":object({"version":integer(1,1),"cycle":integer(),"now":number(0,1.0e12),"missing":map(number(0,1.0e12)),"harvested":map(integer(1,1000000)),"wood_yields":map(integer(2,16))},["version","cycle","now","missing"])}),
		"gather":map(number()),"dive":object({"found":list_of(integer()),"opened":list_of(integer())},["found","opened"]),
		"salvage":object({"left":number()},["left"]),
		"time":object({"day":integer(1),"seconds":number(0,86399.999999),"day_length":number(60,86400)},["day","seconds","day_length"]),
		"weather":object({"kind":{"type":"string","enum":["clear","cloudy","rain"]},"remaining":number(),"seed":integer(1,2147483646),"duration":number(10,86400)},["kind","remaining","seed","duration"]),
		"npc":object({"version":integer(1,1),"graph":object({"met":map({"type":"bool"}),"affinity":map(integer(0,1000)),"last_talk_day":map(integer(-1,1000000000)),"gift_week":map({"type":"string"}),"gift_count":map(integer(0,100)),"edge_deltas":map(integer(-1000,1000))},["met","affinity","last_talk_day","gift_week","gift_count","edge_deltas"]),"seen_events":object({}),"choice_flags":object({}),"request_states":object({})},["version","graph","seen_events","choice_flags","request_states"])
	}
static func validate(data: Dictionary) -> String:
	var version_error: String = preload("res://src/core/record_contract.gd").check(data.get("version"),integer(4,4),"version")
	if version_error != "": return version_error
	var rules := schemas()
	for id in rules:
		if id == "profile" and not data.has(id): continue # explicit legacy policy at restore/decode
		# 房间是后加的模块：decode 会给旧档补默认值，这里再放一次，避免外部快照被误判为损坏。
		if id in ["room", "npc"] and not data.has(id): continue
		if not data.has(id): return "Missing module: " + id
		var error: String = preload("res://src/core/record_contract.gd").check(data[id],rules[id],id)
		if error != "": return error
	if data.has("profile"):
		var profile_error: String=preload("res://src/avatar/avatar_profile.gd").validate_snapshot(data.profile)
		if profile_error!="": return profile_error
	if data.has("npc"):
		var npc_error: String = preload("res://src/npc/npc_save_codec.gd").validate(data.npc)
		if npc_error != "": return npc_error
	var fishery_error: String = preload("res://src/aqua/fishery_service.gd").validate_snapshot(data.economy.get("fishery",{}),(int(data.time.day)-1)*24.0+float(data.time.seconds)/3600.0)
	if fishery_error != "": return fishery_error
	var building_error: String=preload("res://src/building/building_service.gd").validate_snapshot(data.building)
	if building_error!="": return building_error
	var dynamic_ids: Dictionary={}
	for item in data.building.instances:
		if preload("res://src/building/building_catalog.gd").role(str(item.kind))=="planter" and item.left<=0:
			dynamic_ids["dynamic/"+str(item.id)]=true
	for id in data.economy.farm.plots:
		if str(id).begins_with("dynamic/") and not dynamic_ids.has(id): return "Orphan dynamic crop"
	# A historical save has no pickup population: migration explicitly requests a rebuild.
	# An empty/truncated current record must never silently regenerate collected rewards.
	if data.pickups.get("reset",false):
		if data.pickups.size()!=1: return "Reset pickup record cannot contain live population"
	else:
		for key in ["rng","fish_rng","next_id","anchor","elapsed","crates","schools","pending","pending_fish"]:
			if not data.pickups.has(key): return "Missing pickup state " + key
		for key in ["rng","fish_rng"]:
			var raw: String = data.pickups[key]
			if not signed_integer_string(raw): return "Invalid random stream state"
		var ids := {}
		for item in data.pickups.crates:
			if item.has("wood_amount"):
				if item.kind != "planks" or preload("res://src/pickups/wood_bundle.gd").tier(int(item.wood_amount)) < 0: return "Invalid wood bundle yield"
		for population in [data.pickups.crates,data.pickups.schools]:
			for item in population:
				if ids.has(item.id) or item.id >= data.pickups.next_id: return "Duplicate or invalid pickup identity"
				ids[item.id]=true
		if data.pickups.has("ocean"):
			var ocean_error: String = preload("res://src/pickups/ocean_population.gd").validate_snapshot(data.pickups.ocean)
			if ocean_error != "": return ocean_error
			var clock_hours := (int(data.time.day)-1)*24.0+float(data.time.seconds)/3600.0
			var current_cycle := int(data.time.day) if float(data.time.seconds)>=preload("res://src/time/day_schedule.gd").MORNING_SECONDS else int(data.time.day)-1
			if float(data.pickups.ocean.now)>clock_hours+0.000001 or int(data.pickups.ocean.cycle)>current_cycle: return "Future ocean refresh watermark"
			if not data.pickups.pending.is_empty() or not data.pickups.pending_fish.is_empty(): return "Mixed ocean and legacy respawn timers"
			var slots := {}
			for item in data.pickups.crates:
				var yields: Dictionary = data.pickups.ocean.get("wood_yields", {})
				if yields.has(item.get("slot", "")) and int(yields[item.slot]) != int(item.get("wood_amount", 3)): return "Conflicting wood bundle yield"
			for population in [data.pickups.crates,data.pickups.schools]:
				for item in population:
					var slot := str(item.get("slot",""))
					if slot == "" or slots.has(slot) or data.pickups.ocean.missing.has(slot): return "Duplicate or depleted live ocean slot"
					var parts := slot.split(":")
					if parts.size()!=4 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[3].is_valid_int(): return "Invalid live ocean slot"
					if parts[2]!=("wood" if item.has("kind") else "fish") or int(parts[3])<0 or int(parts[3])>=9: return "Invalid live ocean resource kind"
					slots[slot] = true
	for plot in data.economy.farm.plots.values():
		if plot.remaining > plot.total: return "Invalid crop timer"
		if plot.crop != "" and plot.total <= 0.0: return "Planted crop requires positive duration"
	if data.economy.has("daily_loop"):
		var loop: Dictionary = data.economy.daily_loop
		var morning := int(data.time.day) if float(data.time.seconds)>=preload("res://src/time/day_schedule.gd").MORNING_SECONDS else int(data.time.day)-1
		if int(loop.last_morning)>morning: return "Future shipping watermark"
		for id in loop.cargo.counts:
			if id not in ["fish","vegetable","tomato","pumpkin"]: return "Invalid shipment item"
		if not loop.receipt.is_empty():
			for key in ["day","income","items"]:
				if not loop.receipt.has(key): return "Incomplete shipping receipt"
	var offer_ids := {}
	for offer in data.economy.orders.slots:
		if offer.is_empty(): continue
		if offer.has("refill"):
			if offer.size()!=1: return "Refilling order cannot also be an offer"
		else:
			for key in ["uid","order","left"]:
				if not offer.has(key): return "Incomplete order offer: "+key
			if offer.uid=="" or offer.order=="" or offer_ids.has(offer.uid): return "Invalid or duplicate order identity"
			offer_ids[offer.uid]=true
	for work in data.economy.get("site_work",{}).values():
		if work.left > work.total: return "Invalid construction timer"
	if data.weather.remaining > data.weather.duration: return "Invalid weather timer"
	return ""
