extends RefCounted
## 无状态日程解析，依次按剧情、天气、关系、星期与默认优先级选取。
const Catalog = preload("res://src/npc/npc_catalog.gd")

func resolve(npc_id: String, world: Dictionary, available_anchors: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	var row := Catalog.get_npc(npc_id)
	if row.is_empty(): return {"ok": false, "reason": "未知NPC"}
	var hour: Variant = world.get("hour", 8.0)
	if not (hour is int or hour is float) or not is_finite(float(hour)) or hour < 0 or hour >= 24: return {"ok": false, "reason": "小时须为0至24之间的有限数"}
	if not Catalog.whole(world.get("day", 1), 1, 2147483647): return {"ok": false, "reason": "游戏日须为正整数"}
	if world.get("weather", "clear") not in ["clear", "cloudy", "rain", "storm"]: return {"ok": false, "reason": "未知天气"}
	var selected := {"anchor": row.home_anchor, "action": "rest", "priority": -1}
	for rule in row.schedule:
		if hour < rule.from or hour >= rule.to: continue
		if int(rule.get("priority", 0)) <= int(selected.priority): continue
		var conditions: Dictionary = rule.get("conditions", {})
		if not conditions.is_empty():
			if state.is_empty() or not Catalog.matches(conditions, [npc_id], world, state): continue
		selected = rule.duplicate(true)
		selected["priority"] = rule.get("priority", 0)
	var anchor := str(selected.anchor)
	var fallback := not _available(available_anchors, anchor)
	return {"ok": true, "npc_id": npc_id, "anchor_id": str(row.home_anchor) if fallback else anchor,
		"action": "home_fallback" if fallback else str(selected.action), "fallback": fallback,
		"requested_anchor": anchor, "home_available": _available(available_anchors, row.home_anchor),
		"priority": selected.priority}

func _available(anchors: Dictionary, id: String) -> bool:
	if not anchors.has(id): return false
	var value: Variant = anchors[id]
	return value != false if value is bool else value != null
