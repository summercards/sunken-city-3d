extends RefCounted
## 无状态关系运算；持久字典只由 NpcService 持有。
const Catalog = preload("res://src/npc/npc_catalog.gd")

static func graph(state: Dictionary) -> Array:
	var out: Array = []
	for edge in Catalog.relationships():
		edge["delta"] = int(state.edge_deltas[edge.id])
		edge["effective"] = clampi(int(edge.base) + int(edge.delta), -100, 100)
		edge["known"] = bool(state.met[edge.from]) and bool(state.met[edge.to])
		out.append(edge)
	return out

static func npc_snapshot(state: Dictionary, npc_id: String) -> Dictionary:
	if not state.affinity.has(npc_id): return {}
	return {"met": state.met[npc_id], "affinity": state.affinity[npc_id],
		"hearts": floori(float(state.affinity[npc_id]) / 100.0), "last_talk_day": state.last_talk_day[npc_id],
		"gift_week": state.gift_week[npc_id], "gift_count": state.gift_count[npc_id],
		"birthday_gift_day": state.birthday_gift_day[npc_id]}

static func affinity_value(old: int, delta: int) -> int:
	return clampi(old + delta, 0, 1000)

static func edge_value(edge_id: String, old: int, delta: int) -> int:
	for edge in Catalog.relationships():
		if edge.id == edge_id:
			return clampi(int(edge.base) + old + delta, -100, 100) - int(edge.base)
	return old
