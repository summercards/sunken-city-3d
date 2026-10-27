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
	return object({"capacity":integer(1,10000),"counts":map(integer())},["capacity","counts"])
static func schemas() -> Dictionary:
	var string := {"type":"string"}
	var boolean := {"type":"bool"}
	var vector := {"type":"array","items":number(-10000,10000),"sizes":[0,3]}
	var boat := vector.duplicate(true)
	boat.sizes = [0,4]
	return {
		"economy":object({
			"inventory":inventory(),"warehouse":inventory(),"ship_level":integer(1,3),
			"tracked_goal":string,"site_levels":map(integer(1,3)),"facilities":map(boolean),
			"site_work":map(object({"left":number(),"total":number(0.001)},["left","total"])),
			"farm":object({"version":integer(1,2),"day":integer(1),"watering_can":integer(0,12),"selected_crop":string,
				"plots":map(object({"crop":string,"remaining":number(),"total":number(),"water":number(0,1),"harvests":integer()},["crop","remaining","total","water","harvests"]))},["version","day","watering_can","selected_crop","plots"]),
			"orders":object({"slots":list_of(object({"uid":string,"order":string,"left":number(),"refill":number()}),3)},["slots"])},["inventory","warehouse","ship_level","tracked_goal","site_levels","facilities","site_work","farm","orders"]),
		"game":object({"zone":string,"landing":string,"mode":integer(0,3),"far_sea":boolean,"boat":boat,"player":vector},["zone","landing","mode","far_sea","boat","player"]),
		"pickups":object({"reset":boolean,"crates":list_of(object({"id":integer(1),"kind":{"type":"string","enum":["crate","planks","barrel"]},"base":{"type":"array","sizes":[3],"items":number(-1000,1000)},"phase":number(),"yaw":number()},["id","kind","base","phase","yaw"]),32),
			"schools":list_of(object({"id":integer(1),"base":{"type":"array","sizes":[3],"items":number(-1000,1000)},"phase":number(),"count":integer(1,12)},["id","base","phase","count"]),32),
			"pending":list_of(number(0,60),32),"pending_fish":list_of(number(0,60),32),"rng":string,"fish_rng":string,"next_id":integer(1),"anchor":integer(),"elapsed":number()}),
		"gather":map(number()),"dive":object({"found":list_of(integer()),"opened":list_of(integer())},["found","opened"]),
		"salvage":object({"left":number()},["left"]),
		"time":object({"day":integer(1),"seconds":number(0,86399.999999),"day_length":number(60,86400)},["day","seconds","day_length"]),
		"weather":object({"kind":{"type":"string","enum":["clear","cloudy","rain"]},"remaining":number(),"seed":integer(1,2147483646),"duration":number(10,86400)},["kind","remaining","seed","duration"])
	}
static func validate(data: Dictionary) -> String:
	var version_error: String = preload("res://src/core/record_contract.gd").check(data.get("version"),integer(2,2),"version")
	if version_error != "": return version_error
	var rules := schemas()
	for id in rules:
		if not data.has(id): return "Missing module: " + id
		var error: String = preload("res://src/core/record_contract.gd").check(data[id],rules[id],id)
		if error != "": return error
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
		for population in [data.pickups.crates,data.pickups.schools]:
			for item in population:
				if ids.has(item.id) or item.id >= data.pickups.next_id: return "Duplicate or invalid pickup identity"
				ids[item.id]=true
	for plot in data.economy.farm.plots.values():
		if plot.remaining > plot.total: return "Invalid crop timer"
		if plot.crop != "" and plot.total <= 0.0: return "Planted crop requires positive duration"
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
